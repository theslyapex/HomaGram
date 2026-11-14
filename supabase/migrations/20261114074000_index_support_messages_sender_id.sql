-- Cover the sender foreign key used by support inbox lookups and joins.
create index if not exists support_messages_sender_id_idx on public.support_messages (sender_id);
