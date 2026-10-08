-- =====================================================================
-- Lovebird 0004 — Storage buckets & policies, Realtime, scheduled jobs
-- =====================================================================

-- Private buckets only. Clients receive 1-hour signed URLs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('circle-media', 'circle-media', false, 52428800,
     array['image/jpeg','image/png','image/webp','image/gif','image/heic','audio/aac','audio/mp4','audio/m4a','audio/mpeg','audio/webm','audio/ogg','video/mp4']),
  ('avatars', 'avatars', false, 5242880, array['image/jpeg','image/png','image/webp']),
  ('competition', 'competition', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- circle-media:  {circle_id}/{kind}/{uuid}.{ext}
create policy "circle-media: members read" on storage.objects for select to authenticated
  using (bucket_id = 'circle-media' and public.can_read_circle(public.try_uuid((storage.foldername(name))[1])));
create policy "circle-media: members upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'circle-media' and public.can_write_circle(public.try_uuid((storage.foldername(name))[1])));
create policy "circle-media: uploader deletes" on storage.objects for delete to authenticated
  using (bucket_id = 'circle-media' and owner_id = (select auth.uid())::text);

-- avatars:  {user_id}/avatar-{n}.jpg  — you and your partner can see it.
create policy "avatars: self or partner read" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (
           (storage.foldername(name))[1] = (select auth.uid())::text
           or public.shares_circle_with(public.try_uuid((storage.foldername(name))[1]))));
create policy "avatars: self write" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars: self update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars: self delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- competition:  {entry_id}/{uuid}.jpg — couple, judges/admin; public only for consented finalists.
create or replace function public.can_read_entry_media(p_entry uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.competition_entries e
      join public.competitions c on c.id = e.competition_id
     where e.id = p_entry
       and (public.can_read_circle(e.circle_id)
            or public.is_admin()
            or public.is_judge(e.competition_id)
            or (e.status in ('finalist','winner') and public.entry_fully_consented(e.id, true)
                and c.status <> 'closed'))
  );
$$;
create or replace function public.can_write_entry_media(p_entry uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.competition_entries e
                  where e.id = p_entry and e.status in ('draft','awaiting_consent')
                    and public.can_write_circle(e.circle_id));
$$;
create policy "competition: read" on storage.objects for select to authenticated
  using (bucket_id = 'competition' and public.can_read_entry_media(public.try_uuid((storage.foldername(name))[1])));
create policy "competition: couple upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'competition' and public.can_write_entry_media(public.try_uuid((storage.foldername(name))[1])));
create policy "competition: uploader delete" on storage.objects for delete to authenticated
  using (bucket_id = 'competition' and owner_id = (select auth.uid())::text);

-- ---------------------------------------------------------------------
-- Realtime: postgres_changes respects RLS per subscriber.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.circles, public.circle_members, public.messages, public.message_reactions,
      public.notifications, public.together_sessions, public.game_sessions, public.game_responses,
      public.movie_sessions, public.reading_progress, public.highlights, public.highlight_replies,
      public.reading_reflections, public.diary_entries, public.memories, public.plan_items;
  end if;
end $$;

-- Full old-row images so DELETE events carry circle_id (lets clients drop removed rows).
alter table public.message_reactions replica identity full;
alter table public.plan_items        replica identity full;
alter table public.memories          replica identity full;
alter table public.diary_entries     replica identity full;
alter table public.highlights        replica identity full;

-- Private Broadcast/Presence channels "circle:{uuid}" — only members may join/send.
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'realtime' and table_name = 'messages') then
    execute $p$
      create policy "circle channel: members listen" on realtime.messages for select to authenticated
        using (realtime.topic() like 'circle:%'
               and public.can_write_circle(public.try_uuid(substr(realtime.topic(), 8))))
    $p$;
    execute $p$
      create policy "circle channel: members send" on realtime.messages for insert to authenticated
        with check (realtime.topic() like 'circle:%'
                    and public.can_write_circle(public.try_uuid(substr(realtime.topic(), 8))))
    $p$;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Scheduled jobs (pg_cron is available on Supabase; skipped locally if absent)
-- ---------------------------------------------------------------------

-- Anniversary / special-date reminders: 14, 7, 1 and 0 days before.
create or replace function public.send_date_reminders()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; next_on date; days int;
begin
  for r in
    select d.*, c.status from public.special_dates d join public.circles c on c.id = d.circle_id
     where d.remind and c.status = 'active'
  loop
    -- date + N years clamps Feb 29 to Feb 28 in non-leap years
    next_on := case when r.recurs_yearly then
                 (r.date + make_interval(years => (extract(year from current_date) - extract(year from r.date))::int))::date
               else r.date end;
    if r.recurs_yearly and next_on < current_date then
      next_on := (next_on + interval '1 year')::date;
    end if;
    days := next_on - current_date;
    if days in (14, 7, 1, 0) then
      perform public.notify(m.user_id, r.circle_id, 'special_date',
        case when days = 0 then 'Today: ' || r.title || ' ❤️'
             else days || ' day' || case when days = 1 then '' else 's' end || ' until ' || r.title || ' ❤️' end,
        case when r.kind = 'anniversary' then 'Lovebird has a few ideas to make it special.' else null end,
        jsonb_build_object('special_date_id', r.id, 'days', days))
        from public.circle_members m where m.circle_id = r.circle_id and m.left_at is null;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function public.send_date_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('lovebird-purge-ended-circles', '17 3 * * *', 'select public.purge_ended_circles()');
    perform cron.schedule('lovebird-date-reminders', '0 8 * * *', 'select public.send_date_reminders()');
  end if;
end $$;
