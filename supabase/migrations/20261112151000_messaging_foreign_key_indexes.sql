-- Cover messaging foreign keys to keep joins and referential checks efficient.
create index if not exists conversations_created_by_idx
  on public.conversations(created_by);
create index if not exists messages_reply_conversation_idx
  on public.messages(reply_to_id,conversation_id)
  where reply_to_id is not null;
create index if not exists messages_forward_conversation_idx
  on public.messages(forwarded_from_message_id,conversation_id)
  where forwarded_from_message_id is not null;
create index if not exists user_blocks_blocked_id_idx
  on public.user_blocks(blocked_id);
