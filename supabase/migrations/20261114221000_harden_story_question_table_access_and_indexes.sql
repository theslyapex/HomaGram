create policy "No direct access to story questions"
on public.story_questions for all to anon, authenticated
using (false) with check (false);
create policy "No direct access to story question responses"
on public.story_question_responses for all to anon, authenticated
using (false) with check (false);
create index if not exists story_question_responses_user_id_idx
on public.story_question_responses(user_id);