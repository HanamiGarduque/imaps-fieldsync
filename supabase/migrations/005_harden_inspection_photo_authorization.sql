-- Workstream #9: harden inspection-photo authorization.
--
-- Scope:
--   - Storage INSERT on inspection-photos requires the canonical path shape and
--     the currently-assigned inspector.
--   - Storage UPDATE on inspection-photos is retained ONLY for the Storage
--     upload-overwrite operation (storage.object.upload_update); move/rename is
--     denied by the operation gate.
--   - field_job_photos gains a canonical path-shape + namespace-coherence CHECK.
--
-- No DELETE permission is added, no admin write is added, no bucket change,
-- no custom trigger/function on storage.objects.
--
-- Applied via the Supabase CLI Management API query path
-- (`supabase db query --linked --file`).

BEGIN;

-- 1. Tighten Storage INSERT to canonical inspection-photo paths owned by
--    the currently assigned inspector.

DROP POLICY IF EXISTS "inspectors upload own inspection photos"
ON storage.objects;

CREATE POLICY "inspectors upload own inspection photos"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'inspection-photos'
    AND (storage.foldername(name))[1] = 'inspections'
    AND (storage.foldername(name))[2] ~ '^[0-9a-fA-F-]{36}$'
    AND name ~ '^inspections/[0-9a-fA-F-]{36}/photo_[A-Za-z0-9_-]+\.jpg$'
    AND EXISTS (
      SELECT 1
      FROM field_jobs
      WHERE (field_jobs.id)::text = (storage.foldername(name))[2]
        AND field_jobs.assigned_inspector_id = auth.uid()
    )
  );

-- 2. Retain Storage UPDATE only for same-key Storage upload/upsert behavior.
--    Move/rename operations must fail the operation gate.

DROP POLICY IF EXISTS
  "r4p1_inspectors_update_assigned_inspection_objects"
ON storage.objects;

CREATE POLICY "r4p1_inspectors_update_assigned_inspection_objects"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'inspection-photos'
    AND storage.allow_only_operation('storage.object.upload_update')
    AND (storage.foldername(name))[1] = 'inspections'
    AND name ~ '^inspections/[0-9a-fA-F-]{36}/photo_[A-Za-z0-9_-]+\.jpg$'
    AND EXISTS (
      SELECT 1
      FROM field_jobs job
      WHERE (job.id)::text = (storage.foldername(objects.name))[2]
        AND job.assigned_inspector_id = auth.uid()
    )
  )
  WITH CHECK (
    bucket_id = 'inspection-photos'
    AND storage.allow_only_operation('storage.object.upload_update')
    AND (storage.foldername(name))[1] = 'inspections'
    AND name ~ '^inspections/[0-9a-fA-F-]{36}/photo_[A-Za-z0-9_-]+\.jpg$'
    AND EXISTS (
      SELECT 1
      FROM field_jobs job
      WHERE (job.id)::text = (storage.foldername(objects.name))[2]
        AND job.assigned_inspector_id = auth.uid()
    )
  );

-- 3. Enforce metadata path shape + field_job namespace coherence.

ALTER TABLE public.field_job_photos
  ADD CONSTRAINT field_job_photos_path_namespace_chk
  CHECK (
    photo_url ~ (
      '^inspections/'
      || field_job_id::text
      || '/photo_[A-Za-z0-9_-]+\.jpg$'
    )
  );

COMMIT;
