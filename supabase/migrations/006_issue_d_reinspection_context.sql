-- ISSUE D - Round identity + read-only reinspection context (additive only).
--
-- This migration is strictly additive. It introduces NO DROP, NO column
-- rename, NO constraint removal and NO change to RLS or grants. It exists only
-- to transport two things FieldSync already needs:
--
--   1. the reviewed round's full Planning Review metadata, including the PO
--      decision reason now kept on field_job_reviews; and
--   2. the authoritative round context iMAPS already derives but has never
--      pushed: the round number, the previous (reviewed) round, the PO reason
--      and the review timestamp that created this round.
--
-- Applied to the shared Supabase project via the Supabase CLI Management API
-- query path (`supabase db query --linked --file`), as earlier migrations in
-- this repository.

BEGIN;

-- A. field_job_reviews: keep the actual PO reason on the round that was
-- reviewed. All existing fields (decision, reviewed_by, reviewed_at, ...)
-- remain the canonical record of that review; this row is NOT copied to the
-- new reinspection round.
ALTER TABLE public.field_job_reviews
    ADD COLUMN IF NOT EXISTS decision_reason text;

COMMENT ON COLUMN public.field_job_reviews.decision_reason IS
    'The Planning Officer decision reason for the REVIEWED round (iMAPS technical_reviews.decision_reason). NULL when not recorded. This row describes the round that was reviewed, never the new reinspection round.';

-- B. field_jobs: authoritative round context supplied by iMAPS. For an
-- ordinary first inspection all of these stay NULL; they are populated only
-- for a new round created from a Requires Reinspection technical review.
ALTER TABLE public.field_jobs
    ADD COLUMN IF NOT EXISTS inspection_round_number integer;

ALTER TABLE public.field_jobs
    ADD COLUMN IF NOT EXISTS previous_site_inspection_id bigint;

ALTER TABLE public.field_jobs
    ADD COLUMN IF NOT EXISTS reinspection_reason text;

ALTER TABLE public.field_jobs
    ADD COLUMN IF NOT EXISTS reinspection_reviewed_at timestamptz;

COMMENT ON COLUMN public.field_jobs.inspection_round_number IS
    'Authoritative round number within the (zoning_application_id, parcel_id) chain, derived iMAPS-side from site_inspections ordered by id ASC. Round 1 = the original inspection.';

COMMENT ON COLUMN public.field_jobs.previous_site_inspection_id IS
    'site_inspections.id of the round that was reviewed and produced this round. NULL for the original inspection.';

COMMENT ON COLUMN public.field_jobs.reinspection_reason IS
    'PO technical_reviews.decision_reason that created this round. NULL for the original inspection.';

COMMENT ON COLUMN public.field_jobs.reinspection_reviewed_at IS
    'PO technical_reviews.reviewed_at that created this round. NULL for the original inspection.';

CREATE INDEX IF NOT EXISTS field_jobs_inspection_round_number_idx
    ON public.field_jobs (inspection_round_number);

COMMIT;
