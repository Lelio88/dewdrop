-- service_role_group_name_grant — the push Edge Function (send-thought-push)
-- reads `groups` to name the circle a pensée was addressed to. It runs as
-- service_role, which bypasses RLS but still needs a table-level privilege to
-- go through PostgREST — and `groups` was created five days AFTER
-- service_role_read_grants, so it never received one.
--
-- The read therefore came back 42501 and the function fell through to its
-- unnamed fallback: every group notification has read "un groupe" since groups
-- shipped, whichever circle it actually was — which is precisely why a member
-- of several circles could never tell them apart. The data was never at fault
-- (every stored group pensée resolves its name by a plain join); only the
-- reader lacked the right to look.
--
-- Invariant this restores: any table the push function reads needs BOTH its RLS
-- story AND a service_role grant. Adding a read to that function means checking
-- this list. `verify_prod.py` now asserts it against the live server, because
-- the repo alone cannot see a missing grant.
--
-- SELECT only, and only on `groups`: the function reads nothing else there.
-- `group_members` stays ungranted on purpose — least privilege. The fan-out
-- that needs it runs inside the database (send_to_group, SECURITY DEFINER),
-- never over PostgREST.

begin;

grant select on public.groups to service_role;

commit;
