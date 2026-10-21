-- Admin dashboard RPC execution grants.
-- Run this once in Supabase SQL Editor if the dashboard shows
-- "permission denied for function admin_get_technician_profile".
-- These grants do not bypass the functions' own admin checks.

grant execute on function public.admin_get_technician_profile(bigint) to authenticated;
grant execute on function public.admin_get_order_control(bigint) to authenticated;
grant execute on function public.admin_confirm_order_completion_payment(bigint, text) to authenticated;
grant execute on function public.admin_complete_order_emergency(bigint, text) to authenticated;
grant execute on function public.admin_list_confirmed_payments() to authenticated;
grant execute on function public.admin_list_technicians_for_control() to authenticated;
grant execute on function public.admin_list_profession_technicians() to authenticated;
grant execute on function public.admin_apply_technician_action(bigint, text, text, text, integer) to authenticated;
grant execute on function public.admin_review_technician(bigint, text, text, boolean) to authenticated;
