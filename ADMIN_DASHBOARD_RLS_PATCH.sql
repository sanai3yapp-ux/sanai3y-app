-- Sanai3y Admin Dashboard
-- Applied to the connected Supabase project as migration:
-- admin_dashboard_read_access
--
-- These policies allow only active admin accounts to read technician
-- membership data used by the in-app admin dashboard.

create policy "technicians_admin_select"
on public.technicians
as permissive
for select
to authenticated
using (
  exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
      and au.is_active = true
  )
);

create policy "technician_professions_admin_select"
on public.technician_professions
as permissive
for select
to authenticated
using (
  exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
      and au.is_active = true
  )
);
