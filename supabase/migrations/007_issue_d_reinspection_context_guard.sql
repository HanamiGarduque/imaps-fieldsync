-- Issue D: server-owned round / Planning Review context is read-only to clients.
-- Additive follow-up to 006; existing policies, grants and guards stay intact.
BEGIN;

CREATE FUNCTION public.protect_field_job_reinspection_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF current_user = 'authenticated'
     OR current_setting('role', true) = 'authenticated'
     OR auth.role() = 'authenticated' THEN
    IF (TG_OP = 'INSERT' AND (
          NEW.inspection_round_number IS NOT NULL
          OR NEW.previous_site_inspection_id IS NOT NULL
          OR NEW.reinspection_reason IS NOT NULL
          OR NEW.reinspection_reviewed_at IS NOT NULL
        )) OR (TG_OP = 'UPDATE' AND (
          NEW.inspection_round_number IS DISTINCT FROM OLD.inspection_round_number
          OR NEW.previous_site_inspection_id IS DISTINCT FROM OLD.previous_site_inspection_id
          OR NEW.reinspection_reason IS DISTINCT FROM OLD.reinspection_reason
          OR NEW.reinspection_reviewed_at IS DISTINCT FROM OLD.reinspection_reviewed_at
        )) THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'reinspection context is server-managed';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER guard_field_job_reinspection_context
BEFORE INSERT OR UPDATE ON public.field_jobs
FOR EACH ROW EXECUTE FUNCTION public.protect_field_job_reinspection_context();

COMMIT;
