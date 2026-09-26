-- Loop 8 — Planning Review Metadata (read-only transport to FieldSync).
--
-- Scope: this table carries ONLY read-only Planning Review metadata for the
-- exact inspection round that was reviewed. It deliberately adds NO Planning
-- Review lifecycle to `field_jobs`: status, current_step, progress, completed
-- state, reinspection state, photo evidence and sync ACK state are untouched.
--
-- Writers: the iMAPS server-side service credential only (BYPASSRLS).
-- Readers: the authenticated Site Inspector, and ONLY for the exact field_jobs
-- row they are authorized to read. No INSERT/UPDATE/DELETE policy is granted
-- to any client role, so FieldSync review metadata is read-only by policy.
--
-- Applied to the shared Supabase project via the Supabase CLI Management API
-- query path (`supabase db query --linked --file`).

BEGIN;

CREATE TABLE IF NOT EXISTS public.field_job_reviews (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    field_job_id uuid NOT NULL,
    technical_review_id bigint NOT NULL,
    reviewed_site_inspection_id bigint,
    decision text NOT NULL,
    reviewed_by bigint,
    reviewed_by_name text,
    reviewed_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT field_job_reviews_pkey PRIMARY KEY (id),
    CONSTRAINT field_job_reviews_field_job_id_fkey
        FOREIGN KEY (field_job_id) REFERENCES public.field_jobs (id) ON DELETE CASCADE,
    CONSTRAINT field_job_reviews_decision_check
        CHECK (decision IN ('Approved', 'Declined', 'Requires Reinspection'))
);

-- One source review event maps to exactly one transport row, so a repeated
-- review transport converges instead of duplicating.
CREATE UNIQUE INDEX IF NOT EXISTS field_job_reviews_technical_review_id_key
    ON public.field_job_reviews (technical_review_id);

CREATE INDEX IF NOT EXISTS field_job_reviews_field_job_id_index
    ON public.field_job_reviews (field_job_id);

COMMENT ON TABLE public.field_job_reviews IS
    'Loop 8 read-only Planning Review metadata for the exact reviewed inspection round. Written only by the iMAPS server service credential.';
COMMENT ON COLUMN public.field_job_reviews.technical_review_id IS
    'Source iMAPS technical_reviews.id for the review event; unique conflict target.';
COMMENT ON COLUMN public.field_job_reviews.reviewed_site_inspection_id IS
    'Source iMAPS site_inspections.id of the round that was reviewed. Traceability only; never a remote foreign key.';

ALTER TABLE public.field_job_reviews ENABLE ROW LEVEL SECURITY;

-- Inspector read scope mirrors the existing field_jobs ownership model: a
-- Site Inspector may read review metadata only for jobs assigned to them.
DROP POLICY IF EXISTS "inspectors read own job review metadata" ON public.field_job_reviews;
CREATE POLICY "inspectors read own job review metadata"
    ON public.field_job_reviews
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.field_jobs job
            WHERE job.id = field_job_reviews.field_job_id
              AND job.assigned_inspector_id = auth.uid()
        )
    );

-- Explicitly no INSERT/UPDATE/DELETE policy for authenticated/anon: with RLS
-- enabled and no matching policy, those commands are denied for client roles.
-- The iMAPS service credential bypasses RLS and remains the only writer.

COMMIT;
