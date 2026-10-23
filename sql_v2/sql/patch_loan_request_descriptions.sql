-- Persist optional borrower-written context from the loan request form.
-- Safe to re-run.

begin;

alter table public.loan_requests
  add column if not exists description text;

comment on column public.loan_requests.description is
  'Optional borrower-provided context describing how loan funds will be used.';

create or replace view public.v_loan_listing_descriptions as
select
  lr.id as request_id,
  lr.description
from public.loan_requests lr
where lr.status = 'active'
  and not private.is_blocked_from_future_request(
    lr.borrower_id,
    auth.uid(),
    lr.listed_at
  );

comment on view public.v_loan_listing_descriptions is
  'Optional borrower-written context for active Loan Requests. Exposes no borrower identity or private income information and follows the active-listing block visibility rule.';

grant select on public.v_loan_listing_descriptions to authenticated, anon;

commit;
