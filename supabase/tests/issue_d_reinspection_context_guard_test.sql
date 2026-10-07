-- Run ONLY in the disposable security fixture (never production):
-- psql -v ON_ERROR_STOP=1 -f <captured-policy-fixture.sql>
--   -f supabase/migrations/007_issue_d_reinspection_context_guard.sql
--   -f supabase/tests/issue_d_reinspection_context_guard_test.sql
BEGIN;
CREATE FUNCTION pg_temp.expect_context_denied(statement text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE statement;
  RAISE EXCEPTION 'Expected server-context authorization denial: %', statement;
EXCEPTION WHEN insufficient_privilege THEN
  IF SQLERRM <> 'reinspection context is server-managed' THEN
    RAISE EXCEPTION 'Wrong authorization boundary rejected the write: %', SQLERRM;
  END IF;
END;
$$;

SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET inspection_round_number=99 WHERE local_inspection_id=102');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET previous_site_inspection_id=999 WHERE local_inspection_id=102');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET reinspection_reason=''forged'' WHERE local_inspection_id=102');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET reinspection_reviewed_at=''2099-01-01Z'' WHERE local_inspection_id=102');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET inspection_round_number=99,previous_site_inspection_id=999,reinspection_reason=''forged'',reinspection_reviewed_at=''2099-01-01Z'' WHERE local_inspection_id=102');
-- Value -> NULL and NULL -> value must both be denied, for every column.
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET inspection_round_number=NULL WHERE local_inspection_id=102');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET previous_site_inspection_id=NULL WHERE local_inspection_id=102');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET reinspection_reason=NULL WHERE local_inspection_id=102');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET reinspection_reviewed_at=NULL WHERE local_inspection_id=102');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET inspection_round_number=1 WHERE local_inspection_id=104');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET previous_site_inspection_id=101 WHERE local_inspection_id=104');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET reinspection_reason=''forged'' WHERE local_inspection_id=104');
SELECT pg_temp.expect_context_denied('UPDATE public.field_jobs SET reinspection_reviewed_at=''2099-01-01Z'' WHERE local_inspection_id=104');

DO $$ DECLARE affected integer; BEGIN
  UPDATE public.field_jobs SET status='in_progress', current_step=1,
    started_at='2026-10-07T02:00:00Z' WHERE local_inspection_id=102;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION 'Own workflow update blocked'; END IF;
  UPDATE public.field_jobs SET current_step=2,
    inspection_round_number=2, previous_site_inspection_id=101,
    reinspection_reason='Controlled Issue D reinspection context test',
    reinspection_reviewed_at='2026-10-07T01:02:03Z' WHERE local_inspection_id=102;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION 'Unchanged context blocked workflow'; END IF;
  UPDATE public.field_jobs SET status='in_progress' WHERE local_inspection_id=103;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'Foreign RLS regression'; END IF;
  BEGIN
    UPDATE public.field_jobs SET local_inspection_id=999 WHERE local_inspection_id=102;
    RAISE EXCEPTION 'Existing identity guard bypassed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  UPDATE public.field_job_reviews SET decision_reason='forged' WHERE technical_review_id=501;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'Canonical review write allowed'; END IF;
  IF has_table_privilege(current_user,'public.field_jobs','INSERT') THEN
    RAISE EXCEPTION 'Inspector INSERT grant broadened';
  END IF;
  BEGIN
    INSERT INTO public.field_jobs(id) VALUES ('99999999-9999-4999-8999-999999999999');
    RAISE EXCEPTION 'Inspector INSERT unexpectedly accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

-- Exercise insert guard even if future policies permit an insert. Keep actual
-- inspector grants unchanged: use the administrative role with end-user claims.
RESET ROLE;
SELECT pg_temp.expect_context_denied('INSERT INTO public.field_jobs(id,inspection_round_number) VALUES (''99999999-9999-4999-8999-999999999999'',99)');
SELECT pg_temp.expect_context_denied('INSERT INTO public.field_jobs(id,previous_site_inspection_id) VALUES (''99999999-9999-4999-8999-999999999999'',999)');
SELECT pg_temp.expect_context_denied('INSERT INTO public.field_jobs(id,reinspection_reason) VALUES (''99999999-9999-4999-8999-999999999999'',''forged'')');
SELECT pg_temp.expect_context_denied('INSERT INTO public.field_jobs(id,reinspection_reviewed_at) VALUES (''99999999-9999-4999-8999-999999999999'',''2099-01-01Z'')');

SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL ROLE service_role;
DO $$ DECLARE affected integer; BEGIN
  UPDATE public.field_jobs SET inspection_round_number=1,
    previous_site_inspection_id=NULL,reinspection_reason=NULL,reinspection_reviewed_at=NULL
    WHERE local_inspection_id=104;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION 'Trusted Round 1 publication blocked'; END IF;
  UPDATE public.field_jobs SET inspection_round_number=2,previous_site_inspection_id=101,
    reinspection_reason='Controlled Issue D reinspection context test',
    reinspection_reviewed_at='2026-10-07T01:02:03Z' WHERE local_inspection_id=102;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION 'Trusted Round 2 publication blocked'; END IF;
  UPDATE public.field_jobs SET reinspection_reason='Authoritative correction' WHERE local_inspection_id=102;
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION 'Trusted context correction blocked'; END IF;
  INSERT INTO public.field_jobs(id,local_inspection_id,inspection_round_number)
    VALUES ('99999999-9999-4999-8999-999999999999',999,1);
END $$;
RESET ROLE;
SET LOCAL request.jwt.claims='{}';
UPDATE public.field_jobs SET reinspection_reason='Administrative correction' WHERE local_inspection_id=102;
SELECT 'PASS: 17 protected writes denied; workflow, foreign RLS, identity, review, insert and trusted-server controls passed' AS result;
ROLLBACK;
