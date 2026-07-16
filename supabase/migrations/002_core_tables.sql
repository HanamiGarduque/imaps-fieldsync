-- =============================================================================
-- Migration: 002 — Core tables for iMAPS FieldSync
-- Date: 2026-07-17
--
-- Creates (in dependency order):
--   1. profiles                       — inspector/admin user metadata
--   2. supabase_zoning_applications   — zoning application records from main iMAPS
--   3. supabase_parcels               — land/parcel info linked to an application
--   4. field_jobs                     — site inspection assignment record
--   5. inspector_device_subscriptions — push token registry for OneSignal
--   6. RPC: get_jobs_as_geojson       — GeoJSON output for flutter_map
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. PROFILES
--    One row per auth.users entry. role = 'inspector' | 'admin'
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null,
  role        text not null default 'inspector'
                check (role in ('inspector', 'admin')),
  avatar_url  text,
  phone       text,
  department  text,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create index if not exists idx_profiles_role on public.profiles (role);

-- Auto-create a profile row when a user signs up
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'role', 'inspector')
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Auto-bump updated_at
create or replace function public.handle_profile_update()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists on_profile_updated on public.profiles;
create trigger on_profile_updated
  before update on public.profiles
  for each row execute function public.handle_profile_update();

alter table public.profiles enable row level security;

create policy "users view own profile"
  on public.profiles for select to authenticated
  using (auth.uid() = id);

create policy "users update own profile"
  on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

create policy "admins manage all profiles"
  on public.profiles for all to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ---------------------------------------------------------------------------
-- 2. SUPABASE_ZONING_APPLICATIONS
--    Synced from the main iMAPS system. Field app is read-only.
-- ---------------------------------------------------------------------------
create table if not exists public.supabase_zoning_applications (
  id                    uuid primary key default gen_random_uuid(),
  reference_number      text not null unique,
  applicant_name        text not null,
  application_type      text,        -- e.g. 'Residential reclassification'
  declared_land_use     text,        -- e.g. 'Single-detached residential'
  barangay              text,
  address               text,
  lot_area_sqm          numeric,
  zoning_classification text,        -- e.g. 'R-1'
  status                text default 'pending'
                          check (status in ('pending', 'under_review', 'approved', 'rejected')),
  submitted_at          timestamptz,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);

create index if not exists idx_zoning_apps_status   on public.supabase_zoning_applications (status);
create index if not exists idx_zoning_apps_barangay on public.supabase_zoning_applications (barangay);

alter table public.supabase_zoning_applications enable row level security;

create policy "authenticated users view applications"
  on public.supabase_zoning_applications for select to authenticated
  using (true);

create policy "admins manage applications"
  on public.supabase_zoning_applications for all to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ---------------------------------------------------------------------------
-- 3. SUPABASE_PARCELS
--    Land/parcel details for each application. Stores GPS boundary data.
-- ---------------------------------------------------------------------------
create table if not exists public.supabase_parcels (
  id                      uuid primary key default gen_random_uuid(),
  supabase_application_id uuid references public.supabase_zoning_applications(id) on delete cascade,
  parcel_number           text,
  lot_number              text,
  block_number            text,
  survey_number           text,
  land_area_sqm           numeric,
  latitude                double precision,   -- centroid latitude
  longitude               double precision,   -- centroid longitude
  geojson_boundary        jsonb,              -- GeoJSON polygon of parcel boundary
  owner_name              text,
  tct_number              text,               -- Transfer Certificate of Title
  land_classification     text,               -- e.g. 'Agricultural', 'Residential'
  created_at              timestamptz default now(),
  updated_at              timestamptz default now()
);

create index if not exists idx_parcels_application_id on public.supabase_parcels (supabase_application_id);

alter table public.supabase_parcels enable row level security;

create policy "authenticated users view parcels"
  on public.supabase_parcels for select to authenticated
  using (true);

create policy "admins manage parcels"
  on public.supabase_parcels for all to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ---------------------------------------------------------------------------
-- 4. FIELD_JOBS
--    One row = one site inspection assignment.
--    Flutter queries: fetchMyJobs()  → assigned_inspector_id = auth.uid()
--                     submitInspection() → update by id
-- ---------------------------------------------------------------------------
create table if not exists public.field_jobs (
  id                      uuid primary key default gen_random_uuid(),
  local_inspection_id     bigint unique,
  assigned_inspector_id   uuid not null references public.profiles(id) on delete restrict,
  supabase_application_id uuid references public.supabase_zoning_applications(id) on delete set null,
  supabase_parcel_id      uuid references public.supabase_parcels(id) on delete set null,

  -- Scheduling
  scheduled_date          date,
  priority                text default 'normal'
                            check (priority in ('low', 'normal', 'high', 'urgent')),

  -- Workflow status
  -- 'assigned'    → not yet started
  -- 'in_progress' → GPS confirmed, checklist started
  -- 'completed'   → submitted with findings
  -- 'cancelled'   → cancelled before completion
  status                  text not null default 'assigned'
                            check (status in ('assigned', 'in_progress', 'completed', 'cancelled')),

  -- Inspector output (written during/after inspection)
  findings                text,
  observations            text,
  discrepancies           text,
  recommendations         text,
  is_compliant            boolean,
  inspection_result       text
                            check (inspection_result in (
                              'Compliant',
                              'With discrepancy',
                              'For review',
                              'Requires reinspection'
                            )),
  inspector_notes         text,

  -- GPS confirmation
  confirmed_latitude      double precision,
  confirmed_longitude     double precision,
  gps_accuracy_m          double precision,
  gps_confirmed_at        timestamptz,

  -- Checklist summary
  checklist_data          jsonb,    -- [{item: string, checked: bool}]
  checklist_completed_count int default 0,
  checklist_total_count   int default 0,

  -- Photo evidence
  photo_paths             text[],   -- storage paths
  photo_count             int default 0,

  -- Submission metadata
  submitted_at            timestamptz,
  reviewed_by             uuid references public.profiles(id) on delete set null,
  reviewed_at             timestamptz,

  created_at              timestamptz default now(),
  updated_at              timestamptz default now()
);

create index if not exists idx_field_jobs_inspector   on public.field_jobs (assigned_inspector_id);
create index if not exists idx_field_jobs_status      on public.field_jobs (status);
create index if not exists idx_field_jobs_application on public.field_jobs (supabase_application_id);
create index if not exists idx_field_jobs_scheduled   on public.field_jobs (scheduled_date);

-- Auto-bump updated_at
create or replace function public.handle_job_update()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists on_job_updated on public.field_jobs;
create trigger on_job_updated
  before update on public.field_jobs
  for each row execute function public.handle_job_update();

alter table public.field_jobs enable row level security;

create policy "inspectors view own jobs"
  on public.field_jobs for select to authenticated
  using (auth.uid() = assigned_inspector_id);

create policy "inspectors update own jobs"
  on public.field_jobs for update to authenticated
  using (auth.uid() = assigned_inspector_id)
  with check (auth.uid() = assigned_inspector_id);

create policy "admins manage all jobs"
  on public.field_jobs for all to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ---------------------------------------------------------------------------
-- 5. INSPECTOR_DEVICE_SUBSCRIPTIONS
--    Stores OneSignal push tokens per inspector device.
-- ---------------------------------------------------------------------------
create table if not exists public.inspector_device_subscriptions (
  id            uuid primary key default gen_random_uuid(),
  inspector_id  uuid not null references public.profiles(id) on delete cascade,
  device_token  text not null,
  platform      text check (platform in ('android', 'ios', 'web')),
  created_at    timestamptz default now(),
  updated_at    timestamptz default now(),
  unique (inspector_id, device_token)
);

create index if not exists idx_device_subs_inspector on public.inspector_device_subscriptions (inspector_id);

alter table public.inspector_device_subscriptions enable row level security;

create policy "inspectors manage own tokens"
  on public.inspector_device_subscriptions for all to authenticated
  using (auth.uid() = inspector_id) with check (auth.uid() = inspector_id);

create policy "admins manage all tokens"
  on public.inspector_device_subscriptions for all to authenticated
  using (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ---------------------------------------------------------------------------
-- 6. RPC: get_jobs_as_geojson
--    Returns assigned + in-progress jobs as a GeoJSON FeatureCollection
--    for the flutter_map SiteMapScreen.
-- ---------------------------------------------------------------------------
create or replace function public.get_jobs_as_geojson()
returns json
language sql
security definer
as $$
  select json_build_object(
    'type', 'FeatureCollection',
    'features', coalesce(
      json_agg(
        json_build_object(
          'type', 'Feature',
          'geometry', json_build_object(
            'type', 'Point',
            'coordinates', json_build_array(p.longitude, p.latitude)
          ),
          'properties', json_build_object(
            'job_id',           j.id,
            'status',           j.status,
            'scheduled_date',   j.scheduled_date,
            'applicant_name',   a.applicant_name,
            'reference_number', a.reference_number,
            'barangay',         a.barangay,
            'parcel_id',        p.id
          )
        )
      ) filter (where p.latitude is not null and p.longitude is not null),
      '[]'::json
    )
  )
  from public.field_jobs j
  left join public.supabase_zoning_applications a on a.id = j.supabase_application_id
  left join public.supabase_parcels p on p.id = j.supabase_parcel_id
  where j.assigned_inspector_id = auth.uid()
    and j.status in ('assigned', 'in_progress');
$$;

-- ---------------------------------------------------------------------------
-- SEED INSTRUCTIONS
-- ---------------------------------------------------------------------------
-- 1. Go to Supabase Dashboard → Authentication → Users
-- 2. Create:
--      admin@test.com     (any strong password)
--      inspector@test.com (any strong password)
-- 3. Note their UUIDs, then run the seed block below in the SQL Editor,
--    replacing the placeholder UUIDs.
--
-- insert into public.profiles (id, full_name, role) values
--   ('<admin-uuid>',     'Admin User',    'admin'),
--   ('<inspector-uuid>', 'J. Reyes',      'inspector')
-- on conflict (id) do update set full_name = excluded.full_name, role = excluded.role;
--
-- insert into public.supabase_zoning_applications
--   (reference_number, applicant_name, application_type, declared_land_use,
--    barangay, address, lot_area_sqm, zoning_classification)
-- values
--   ('ZN-2026-00871', 'Jose Santos', 'Residential reclassification',
--    'Single-detached residential', 'Brgy. Maligaya',
--    'Lot 22-B, Brgy. Maligaya, Zone 3', 340, 'R-1'),
--   ('ZN-2026-00872', 'Maria Cruz', 'Commercial permit',
--    'Sari-sari store', 'Brgy. San Roque',
--    '12 Mabini Ave, Brgy. San Roque', 120, 'C-1');
--
-- insert into public.supabase_parcels
--   (supabase_application_id, lot_number, land_area_sqm, latitude, longitude, owner_name)
-- select id, 'Lot 22-B', 340, 14.0554, 121.1603, 'Jose Santos'
-- from public.supabase_zoning_applications where reference_number = 'ZN-2026-00871';
--
-- insert into public.field_jobs
--   (assigned_inspector_id, supabase_application_id, supabase_parcel_id,
--    status, scheduled_date, local_inspection_id)
-- select
--   '<inspector-uuid>',
--   a.id,
--   p.id,
--   'assigned',
--   current_date + 1,
--   100001
-- from public.supabase_zoning_applications a
-- join public.supabase_parcels p on p.supabase_application_id = a.id
-- where a.reference_number = 'ZN-2026-00871';
