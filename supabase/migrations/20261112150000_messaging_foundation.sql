-- HomaGram messaging foundation: secure schema only; client workflows are added in later phases.
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('direct','group','channel')),
  title text,
  photo_path text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversations_title_length check (title is null or char_length(title) between 1 and 100),
  constraint conversations_group_metadata check (
    (kind = 'direct' and title is null and photo_path is null)
    or kind in ('group','channel')
  )
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  muted_until timestamptz,
  archived_at timestamptz,
  last_read_at timestamptz,
  primary key (conversation_id,user_id),
  constraint conversation_members_left_after_join check (left_at is null or left_at >= joined_at)
);
create index conversation_members_user_active_idx
  on public.conversation_members(user_id, joined_at desc) where left_at is null;

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  client_message_id uuid not null,
  message_type text not null default 'text'
    check (message_type in ('text','image','video','audio','file','system')),
  body text not null default '',
  reply_to_id uuid,
  forwarded_from_message_id uuid,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint messages_body_length check (char_length(body) <= 10000),
  constraint messages_content_required check (message_type = 'system' or char_length(btrim(body)) > 0),
  constraint messages_reply_same_conversation_fk
    foreign key (reply_to_id,conversation_id)
    references public.messages(id,conversation_id) deferrable initially immediate,
  constraint messages_forward_same_conversation_fk
    foreign key (forwarded_from_message_id,conversation_id)
    references public.messages(id,conversation_id) deferrable initially immediate,
  unique (id,conversation_id),
  unique (sender_id,conversation_id,client_message_id)
);
create index messages_conversation_created_idx
  on public.messages(conversation_id,created_at desc,id desc);
create index messages_sender_created_idx on public.messages(sender_id,created_at desc);

create table public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 32),
  created_at timestamptz not null default now(),
  primary key (message_id,user_id,emoji)
);

create table public.message_receipts (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id,user_id),
  constraint message_receipts_read_after_delivery check (read_at is null or delivered_at is not null)
);

create table public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id,blocked_id),
  constraint user_blocks_no_self check (blocker_id <> blocked_id)
);

create index message_receipts_user_idx on public.message_receipts(user_id,message_id);
create index message_reactions_user_idx on public.message_reactions(user_id,message_id);

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.message_receipts enable row level security;
alter table public.user_blocks enable row level security;

revoke all on public.conversations,public.conversation_members,public.messages,
  public.message_reactions,public.message_receipts,public.user_blocks from anon,authenticated;

grant select on public.conversations,public.conversation_members,public.messages,
  public.message_reactions,public.message_receipts to authenticated;
grant select,insert,delete on public.user_blocks to authenticated;
grant insert,delete on public.messages to authenticated;
grant update (body,edited_at,deleted_at,updated_at) on public.messages to authenticated;
grant insert,delete on public.message_reactions to authenticated;
grant insert,update on public.message_receipts to authenticated;

create or replace function private.is_active_conversation_member(target_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
      and cm.user_id = (select auth.uid())
      and cm.left_at is null
  );
$;
revoke all on function private.is_active_conversation_member(uuid) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_active_conversation_member(uuid) to authenticated;

create policy "Members can read their conversations"
on public.conversations for select to authenticated
using (exists (
  select 1 from public.conversation_members cm
  where cm.conversation_id = id and cm.user_id = (select auth.uid()) and cm.left_at is null
));

create policy "Members can read membership of their conversations"
on public.conversation_members for select to authenticated
using (private.is_active_conversation_member(conversation_id));

create policy "Active members can read messages"
on public.messages for select to authenticated
using (exists (
  select 1 from public.conversation_members cm
  where cm.conversation_id = messages.conversation_id
    and cm.user_id = (select auth.uid()) and cm.left_at is null
));

create policy "Active members can send messages as themselves"
on public.messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and message_type <> 'system'
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = messages.conversation_id
      and cm.user_id = (select auth.uid()) and cm.left_at is null
  )
  and not exists (
    select 1 from public.conversation_members cm
    join public.user_blocks b
      on (b.blocker_id = cm.user_id and b.blocked_id = (select auth.uid()))
      or (b.blocker_id = (select auth.uid()) and b.blocked_id = cm.user_id)
    where cm.conversation_id = messages.conversation_id
      and cm.left_at is null and cm.user_id <> (select auth.uid())
  )
);

create policy "Senders can edit their own messages"
on public.messages for update to authenticated
using (sender_id = (select auth.uid()) and deleted_at is null)
with check (sender_id = (select auth.uid()) and message_type <> 'system');

create policy "Users can add reactions as themselves"
on public.message_reactions for insert to authenticated
with check (user_id = (select auth.uid()) and exists (
  select 1 from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id
  where m.id = message_id and cm.user_id = (select auth.uid()) and cm.left_at is null
));

create policy "Members can read reactions in their conversations"
on public.message_reactions for select to authenticated
using (exists (
  select 1 from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id
  where m.id = message_id and cm.user_id = (select auth.uid()) and cm.left_at is null
));

create policy "Users can remove their own reactions"
on public.message_reactions for delete to authenticated
using (user_id = (select auth.uid()));

create policy "Users can read receipts in their conversations"
on public.message_receipts for select to authenticated
using (user_id = (select auth.uid()) or exists (
  select 1 from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id
  where m.id = message_id and cm.user_id = (select auth.uid()) and cm.left_at is null
));

create policy "Users can create their own receipts"
on public.message_receipts for insert to authenticated
with check (user_id = (select auth.uid()) and exists (
  select 1 from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id
  where m.id = message_id and cm.user_id = (select auth.uid()) and cm.left_at is null
));

create policy "Users can update their own receipts"
on public.message_receipts for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "Users can read blocks they created"
on public.user_blocks for select to authenticated
using (blocker_id = (select auth.uid()));
create policy "Users can block others as themselves"
on public.user_blocks for insert to authenticated
with check (blocker_id = (select auth.uid()));
create policy "Users can unblock others"
on public.user_blocks for delete to authenticated
using (blocker_id = (select auth.uid()));

-- Conversation creation and membership management are intentionally not exposed yet.
-- They will be added through validated database functions in the next implementation step.
