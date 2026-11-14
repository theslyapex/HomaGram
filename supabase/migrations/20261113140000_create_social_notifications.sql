create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references auth.users(id) on delete cascade,
 actor_id uuid references public.profiles(id) on delete set null,
 type text not null check (type in ('follow','post_like','post_comment','comment_reply','post_repost','story_reaction')),
 entity_id uuid,
 entity_type text not null check (entity_type in ('profile','post','comment','story')),
 message text,
 is_read boolean not null default false,
 created_at timestamptz not null default now()
);
create index if not exists notifications_recipient_created_idx on public.notifications(recipient_id, created_at desc);
create index if not exists notifications_recipient_unread_idx on public.notifications(recipient_id, is_read) where is_read = false;
alter table public.notifications enable row level security;
create policy "Users can read their own notifications" on public.notifications for select to authenticated using ((select auth.uid()) = recipient_id);
create policy "Users can update their own notifications" on public.notifications for update to authenticated using ((select auth.uid()) = recipient_id) with check ((select auth.uid()) = recipient_id);
create policy "Users can delete their own notifications" on public.notifications for delete to authenticated using ((select auth.uid()) = recipient_id);
grant select, update, delete on public.notifications to authenticated;
revoke all on public.notifications from anon;
create or replace function public.handle_social_notification()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_recipient uuid; v_actor uuid; v_entity uuid; v_type text; v_entity_type text; v_message text;
begin
 if tg_table_name = 'user_follows' then
  v_actor := new.follower_id; v_recipient := new.following_id; v_entity := new.following_id; v_type := 'follow'; v_entity_type := 'profile'; v_message := 'شما را دنبال کرد.';
 elsif tg_table_name = 'post_likes' then
  v_actor := new.user_id; select author_id into v_recipient from public.posts where id = new.post_id; v_entity := new.post_id; v_type := 'post_like'; v_entity_type := 'post'; v_message := 'پسندید.';
 elsif tg_table_name = 'post_reposts' then
  v_actor := new.user_id; select author_id into v_recipient from public.posts where id = new.post_id; v_entity := new.post_id; v_type := 'post_repost'; v_entity_type := 'post'; v_message := 'پست شما را بازنشر کرد.';
 elsif tg_table_name = 'post_comments' then
  v_actor := new.user_id; v_entity := new.id; v_entity_type := 'comment';
  if new.parent_id is not null then
   select user_id into v_recipient from public.post_comments where id = new.parent_id and post_id = new.post_id; v_type := 'comment_reply'; v_message := 'به دیدگاه شما پاسخ داد.';
  else
   select author_id into v_recipient from public.posts where id = new.post_id; v_type := 'post_comment'; v_message := 'برای پست شما دیدگاه گذاشت.';
  end if;
 elsif tg_table_name = 'story_reactions' then
  v_actor := new.user_id; select author_id into v_recipient from public.stories where id = new.story_id; v_entity := new.story_id; v_type := 'story_reaction'; v_entity_type := 'story'; v_message := 'به استوری شما واکنش نشان داد.';
 else return new;
 end if;
 if v_recipient is not null and v_actor is not null and v_actor <> v_recipient then
  insert into public.notifications(recipient_id,actor_id,type,entity_id,entity_type,message) values(v_recipient,v_actor,v_type,v_entity,v_entity_type,v_message);
 end if;
 return new;
end; $$;
revoke all on function public.handle_social_notification() from public, anon, authenticated;
create trigger notify_follow_created after insert on public.user_follows for each row execute function public.handle_social_notification();
create trigger notify_post_like_created after insert on public.post_likes for each row execute function public.handle_social_notification();
create trigger notify_post_comment_created after insert on public.post_comments for each row execute function public.handle_social_notification();
create trigger notify_post_repost_created after insert on public.post_reposts for each row execute function public.handle_social_notification();
create trigger notify_story_reaction_created after insert on public.story_reactions for each row execute function public.handle_social_notification();