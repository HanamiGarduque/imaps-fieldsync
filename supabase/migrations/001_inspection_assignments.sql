-- Migration: Create inspection_assignments table with RLS
-- Date: 2026-07-11

create table if not exists public.inspection_assignments (
  id uuid primary key default gen_random_uuid(),
  inspector_id uuid not null references auth.users(id) on delete cascade,
  applicant_name text not null,
  barangay text not null,
  address text,
  latitude double precision,
  longitude double precision,
  lot_area_sqm numeric,
  parcel_count int default 1,
  status text not null default 'assigned' check (status in ('assigned', 'in_progress', 'completed')),
  deadline date,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index idx_assignments_inspector_id on public.inspection_assignments (inspector_id);
create index idx_assignments_status on public.inspection_assignments (status);

alter table public.inspection_assignments enable row level security;

create policy "inspectors view own assignments"
  on public.inspection_assignments
  for select
  to authenticated
  using (auth.uid() = inspector_id);

create policy "inspectors update own assignment status"
  on public.inspection_assignments
  for update
  to authenticated
  using (auth.uid() = inspector_id)
  with check (auth.uid() = inspector_id);

create policy "admins manage all assignments"
  on public.inspection_assignments
  for all
  to authenticated
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'admin'
    )
  );

create or replace function public.handle_assignment_update()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger on_assignment_updated
  before update on public.inspection_assignments
  for each row execute function public.handle_assignment_update();