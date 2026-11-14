-- The invite table is intentionally RPC-only; deny direct authenticated row access.
drop policy if exists "Block direct invite table access" on public.channel_invites;
create policy "Block direct invite table access"
on public.channel_invites
for all
to authenticated
using (false)
with check (false);
