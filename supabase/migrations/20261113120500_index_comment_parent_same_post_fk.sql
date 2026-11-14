create index if not exists post_comments_parent_post_idx on public.post_comments (parent_id, post_id);
