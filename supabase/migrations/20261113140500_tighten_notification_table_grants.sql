create index if not exists notifications_actor_id_idx on public.notifications(actor_id);
revoke all privileges on table public.notifications from anon, authenticated;
grant select, update, delete on table public.notifications to authenticated;