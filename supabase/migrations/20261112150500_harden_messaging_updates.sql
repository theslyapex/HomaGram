-- Tighten mutable columns and require current membership for message edits.
drop policy if exists "Senders can edit their own messages" on public.messages;
create policy "Active senders can edit their own messages"
on public.messages for update to authenticated
using (
  sender_id = (select auth.uid())
  and deleted_at is null
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = messages.conversation_id
      and cm.user_id = (select auth.uid()) and cm.left_at is null
  )
)
with check (
  sender_id = (select auth.uid())
  and message_type <> 'system'
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = messages.conversation_id
      and cm.user_id = (select auth.uid()) and cm.left_at is null
  )
);

revoke update on public.message_receipts from authenticated;
grant update (delivered_at,read_at) on public.message_receipts to authenticated;
drop policy if exists "Users can update their own receipts" on public.message_receipts;
create policy "Users can update their own receipts"
on public.message_receipts for update to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.messages m
    join public.conversation_members cm on cm.conversation_id = m.conversation_id
    where m.id = message_id and cm.user_id = (select auth.uid()) and cm.left_at is null
  )
)
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.messages m
    join public.conversation_members cm on cm.conversation_id = m.conversation_id
    where m.id = message_id and cm.user_id = (select auth.uid()) and cm.left_at is null
  )
);
