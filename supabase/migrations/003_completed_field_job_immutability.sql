-- Loop 5: completed is terminal for one field_jobs row.
-- Evidence columns remain editable; lifecycle/progress/submission identity do not regress.
create or replace function public.preserve_completed_field_job_lifecycle()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.status = 'completed' then
    new.status := 'completed';
    new.current_step := 6;
    new.submitted_at := old.submitted_at;
  end if;

  if new.status = 'completed' then
    new.current_step := 6;
    if old.submitted_at is not null then
      new.submitted_at := old.submitted_at;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_preserve_completed_field_job_lifecycle
  on public.field_jobs;
create trigger trg_preserve_completed_field_job_lifecycle
  before update on public.field_jobs
  for each row
  execute function public.preserve_completed_field_job_lifecycle();
