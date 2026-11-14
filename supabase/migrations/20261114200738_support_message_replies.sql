alter table public.support_messages
  add column reply_to_id uuid;

alter table public.support_messages
  add constraint support_messages_id_conversation_unique
  unique (id, conversation_id);

alter table public.support_messages
  add constraint support_messages_reply_same_conversation_fkey
  foreign key (reply_to_id, conversation_id)
  references public.support_messages (id, conversation_id)
  on delete restrict;

create index support_messages_reply_to_id_idx
  on public.support_messages (reply_to_id)
  where reply_to_id is not null;
