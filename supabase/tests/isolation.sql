-- =====================================================================
-- Lovebird — Love Circle isolation & security suite (brief §42: "Test this explicitly")
-- Run:  psql -v ON_ERROR_STOP=1 -f tests/isolation.sql   (after migrations)
-- Every check raises an exception on failure, so the script stops at the first breach.
-- Cast:  Circle A = Mercy ❤️ David    Circle B = Kemi ❤️ Femi    Eve = outsider    Ada = admin
-- =====================================================================
\set ON_ERROR_STOP 1
set client_min_messages = notice;

\set mercy '''11111111-1111-1111-1111-111111111111'''
\set david '''22222222-2222-2222-2222-222222222222'''
\set kemi  '''33333333-3333-3333-3333-333333333333'''
\set femi  '''44444444-4444-4444-4444-444444444444'''
\set eve   '''55555555-5555-5555-5555-555555555555'''
\set ada   '''66666666-6666-6666-6666-666666666666'''

-- ---------- helpers ----------
create or replace function public.t_ok(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAIL: %', label; end if;
  raise notice 'PASS: %', label;
end $$;
create or replace function public.t_count(q text) returns bigint language plpgsql as $$
declare n bigint; begin execute 'select count(*) from (' || q || ') x' into n; return n; end $$;
create or replace function public.t_fails(q text, label text) returns void language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    raise notice 'PASS: % (blocked: %)', label, sqlerrm;
    return;
  end;
  raise exception 'FAIL: % — statement succeeded but should have been blocked', label;
end $$;
-- run a DML statement, return affected rows (RLS-filtered updates/deletes affect 0)
create or replace function public.t_affected(q text) returns bigint language plpgsql as $$
declare n bigint; begin execute q; get diagnostics n = row_count; return n; end $$;
grant execute on function public.t_ok(boolean, text), public.t_count(text), public.t_fails(text, text), public.t_affected(text) to authenticated;

-- ---------- users (as the auth service would create them) ----------
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at, created_at) values
 (:mercy, 'mercy@x.test', '{"display_name":"Mercy","date_of_birth":"1998-02-14","country_code":"ng","currency_code":"ngn"}', now(), now() - interval '60 days'),
 (:david, 'david@x.test', '{"display_name":"David","date_of_birth":"1997-06-01","country_code":"NG","currency_code":"NGN"}', now(), now() - interval '60 days'),
 (:kemi,  'kemi@x.test',  '{"display_name":"Kemi","date_of_birth":"1995-01-01","country_code":"US","currency_code":"USD"}', now(), now() - interval '60 days'),
 (:femi,  'femi@x.test',  '{"display_name":"Femi","date_of_birth":"1994-01-01","country_code":"US","currency_code":"USD"}', now(), now() - interval '60 days'),
 (:eve,   'eve@x.test',   '{"display_name":"Eve","date_of_birth":"1990-01-01","country_code":"US","currency_code":"USD"}', now(), now() - interval '60 days'),
 (:ada,   'ada@x.test',   '{"display_name":"Ada","date_of_birth":"1985-01-01"}', now(), now() - interval '60 days');
insert into public.app_admins (user_id) values (:ada);

select public.t_ok(public.t_count('select 1 from public.profiles') = 6, 'profiles auto-created from sign-up metadata');
select public.t_ok((select country_code from public.profiles where id = :mercy) = 'NG', 'country code normalised');

-- 18+ is enforced by the database
select public.t_fails($q$insert into auth.users (email, raw_user_meta_data) values ('kid@x.test', jsonb_build_object('display_name','Kid','date_of_birth', (current_date - interval '16 years')::date))$q$,
  'under-18 sign-up rejected');
select public.t_fails($q$insert into auth.users (email, raw_user_meta_data) values ('nodob@x.test', '{"display_name":"NoDob"}')$q$,
  'sign-up without date of birth rejected');

-- =====================================================================
-- Circle formation
-- =====================================================================
set role authenticated;
select set_config('request.jwt.claim.sub', :mercy, false);
create temp table _a as select * from public.create_circle();
select public.t_ok((select code from _a) ~ '^[A-HJ-NP-Z2-9]{8}$', 'Mercy creates circle A and gets an 8-char code');
select public.t_fails('select public.create_circle()', 'cannot create a second circle while in one');
select public.t_fails($q$select public.join_circle((select code from _a))$q$, 'cannot join your own invitation');

select set_config('request.jwt.claim.sub', :david, false);
select public.t_ok((select inviter_name from public.preview_invitation((select lower(code) from _a))) = 'Mercy', 'David previews invitation (case-insensitive)');
create temp table _aid as select public.join_circle((select code from _a)) as id;
select public.t_ok((select status from public.circles where id = (select id from _aid)) = 'active', 'circle A active after David joins');

select set_config('request.jwt.claim.sub', :kemi, false);
create temp table _b as select * from public.create_circle();
select set_config('request.jwt.claim.sub', :femi, false);
create temp table _bid as select public.join_circle((select code from _b)) as id;

select set_config('request.jwt.claim.sub', :eve, false);
select public.t_ok(public.join_circle((select code from _a)) is null, 'outsider cannot reuse a used invitation');
select public.t_ok(public.t_count($q$select 1 from public.preview_invitation('ABCDEFGH')$q$) = 0, 'unknown code previews as invalid');
select public.t_ok(public.t_count('select 1 from public.circles') = 0, 'outsider sees no circles');

reset role;
select public.t_fails(format('insert into public.circle_members (circle_id, user_id) values (%L, %L)', (select id from _aid), :eve),
  'third member blocked by trigger even with direct DB access');
\set A '(select id from _aid)'
\set B '(select id from _bid)'

-- =====================================================================
-- Circle A creates private content (as Mercy / David)
-- =====================================================================
set role authenticated;
select set_config('request.jwt.claim.sub', :mercy, false);
insert into public.messages (circle_id, sender_id, client_id, body) values (:A, :mercy, gen_random_uuid(), 'good morning ❤️');
insert into public.diary_entries (circle_id, author_id, title, body) values (:A, :mercy, 'Our first game night', 'We laughed so much');
insert into public.memories (circle_id, author_id, title) values (:A, :mercy, 'First movie night');
insert into public.plans (circle_id, title, category, created_by) values (:A, 'Gifts', 'gifts', :mercy);
insert into public.plan_items (plan_id, circle_id, text, created_by, private_to)
  values ((select id from public.plans where title = 'Gifts'), :A, 'Surprise watch for David', :mercy, :mercy);
insert into public.plan_items (plan_id, circle_id, text, created_by)
  values ((select id from public.plans where title = 'Gifts'), :A, 'Matching mugs', :mercy);
insert into public.special_dates (circle_id, kind, title, date, created_by) values (:A, 'anniversary', 'Our anniversary', '2024-10-20', :mercy);
insert into public.game_sessions (circle_id, game_key, started_by) values (:A, 'would_you_rather', :mercy);
insert into public.movie_sessions (circle_id, title, source_url, source_kind, created_by) values (:A, 'Sintel', 'https://example.org/sintel.mp4', 'catalog', :mercy);
insert into public.circle_books (circle_id, book_id, added_by) values (:A, (select id from public.books where title = 'The Clock Between Us'), :mercy);
insert into public.media (circle_id, uploader_id, path, mime, bytes) values (:A, :mercy, (select id from _aid)::text || '/photos/a.jpg', 'image/jpeg', 1000);
insert into storage.objects (bucket_id, name, owner_id) values ('circle-media', (select id from _aid)::text || '/photos/a.jpg', :mercy);
select public.t_ok(true, 'Mercy writes chat, diary, memory, plans, dates, game, movie, book, media in circle A');

select public.t_fails(format($q$insert into public.messages (circle_id, sender_id, client_id, body) values (%L, %L, gen_random_uuid(), 'spoof')$q$, (select id from _aid), :david),
  'cannot send a message as your partner');
select public.t_fails(format($q$insert into public.messages (circle_id, sender_id, client_id, kind, body) values (%L, %L, gen_random_uuid(), 'system', 'fake system')$q$, (select id from _aid), :mercy),
  'cannot forge system messages');
select public.t_fails(format($q$update public.circles set status = 'pending' where id = %L$q$, (select id from _aid)), 'cannot change circle status directly');
select public.t_ok(public.t_affected(format($q$update public.circles set couple_name = 'Mercy & David' where id = %L$q$, (select id from _aid))) = 1, 'can set couple name');

-- =====================================================================
-- ISOLATION: Kemi (circle B) attacks circle A
-- =====================================================================
select set_config('request.jwt.claim.sub', :kemi, false);
select public.t_ok(public.t_count(format('select 1 from public.%I', t)) = 0, 'circle B cannot read circle A ' || t)
  from unnest(array['messages','diary_entries','memories','plans','plan_items','special_dates','game_sessions',
                    'movie_sessions','circle_books','media','together_sessions','message_reactions','highlights','reading_progress']) t;
select public.t_ok(public.t_count(format('select 1 from public.circles where id = %L', (select id from _aid))) = 0, 'circle B cannot see circle A row');
select public.t_ok(public.t_count(format('select 1 from public.profiles where id in (%L, %L)', :mercy, :david)) = 0, 'circle B cannot read circle A profiles');
select public.t_ok(public.t_count(format('select 1 from public.circle_members where circle_id = %L', (select id from _aid))) = 0, 'circle B cannot list circle A members');
select public.t_ok(public.t_count(format('select 1 from public.invitations where circle_id = %L', (select id from _aid))) = 0, 'circle B cannot read circle A invitations');

select public.t_fails(format($q$insert into public.messages (circle_id, sender_id, client_id, body) values (%L, %L, gen_random_uuid(), 'hi')$q$, (select id from _aid), :kemi),
  'circle B cannot post into circle A chat');
select public.t_fails(format($q$insert into public.diary_entries (circle_id, author_id, body) values (%L, %L, 'x')$q$, (select id from _aid), :kemi),
  'circle B cannot write circle A diary');
select public.t_fails(format($q$insert into public.game_responses (session_id, circle_id, round, user_id, answer) values ((select id from public.game_sessions limit 1), %L, 1, %L, '"a"')$q$, (select id from _aid), :kemi),
  'circle B cannot answer circle A game');
select public.t_ok(public.t_affected(format($q$update public.game_sessions set round = 5 where circle_id = %L$q$, (select id from _aid))) = 0, 'circle B cannot advance circle A game');
select public.t_ok(public.t_affected(format($q$delete from public.memories where circle_id = %L$q$, (select id from _aid))) = 0, 'circle B cannot delete circle A memories');
select public.t_ok(public.t_affected(format($q$update public.movie_sessions set position_ms = 1 where circle_id = %L$q$, (select id from _aid))) = 0, 'circle B cannot control circle A movie');
select public.t_fails(format($q$select public.mark_messages_read(%L)$q$, (select id from _aid)), 'circle B cannot mark circle A messages read');
select public.t_fails(format($q$select public.end_circle(%L)$q$, (select id from _aid)), 'circle B cannot end circle A');
select public.t_fails(format($q$select public.start_together(%L, 'play', null, null, 'x')$q$, (select id from _aid)), 'circle B cannot start Together Mode in circle A');
select public.t_fails(format($q$select public.circle_year_recap(%L, 2026)$q$, (select id from _aid)), 'circle B cannot read circle A recap');
select public.t_fails(format($q$insert into public.circle_books (circle_id, book_id, added_by) values (%L, (select id from public.books limit 1), %L)$q$, (select id from _bid), :kemi)
  || '; insert into public.highlights (circle_book_id, circle_id, user_id, chapter, quote) values ((select id from public.circle_books where circle_id = ''' || (select id from _bid) || '''), ''' || (select id from _aid) || ''', ''' || :kemi || ''', 1, ''x'')',
  'cross-circle child row (B book, A circle) rejected');

-- storage & realtime
select public.t_ok(public.t_count($q$select 1 from storage.objects where bucket_id = 'circle-media'$q$) = 0, 'circle B cannot list circle A files');
select public.t_fails(format($q$insert into storage.objects (bucket_id, name) values ('circle-media', %L)$q$, (select id from _aid)::text || '/photos/evil.jpg'),
  'circle B cannot upload into circle A folder');
select public.t_fails($q$insert into storage.objects (bucket_id, name) values ('circle-media', 'not-a-uuid/x.jpg')$q$, 'malformed storage path rejected');
select set_config('realtime.topic', 'circle:' || (select id from _aid), false);
select public.t_fails($q$insert into realtime.messages (topic, payload) values (realtime.topic(), '{}')$q$, 'circle B cannot broadcast on circle A channel');
select public.t_ok(public.t_count('select 1 from realtime.messages') = 0, 'circle B cannot subscribe to circle A channel');

-- own circle still works for Kemi
select set_config('realtime.topic', 'circle:' || (select id from _bid), false);
insert into realtime.messages (topic, payload) values (realtime.topic(), '{"t":"typing"}');
select public.t_ok(true, 'circle B can broadcast on its own channel');
select public.t_fails($q$select public.notify(auth.uid(), null, 'x', 'spam', null)$q$, 'clients cannot create notifications directly');

-- =====================================================================
-- Inside circle A: partner privacy rules
-- =====================================================================
select set_config('request.jwt.claim.sub', :david, false);
select public.t_ok(public.t_count('select 1 from public.plan_items') = 1, 'David sees shared item but not Mercy''s private gift idea');
select public.t_ok(public.t_count(format('select 1 from public.profiles where id = %L', :mercy)) = 1, 'David can read partner profile');
select public.t_ok(public.t_affected($q$update public.messages set body = 'edited by partner'$q$) = 0, 'partner cannot edit your messages');
select public.t_ok(public.t_affected($q$delete from public.diary_entries$q$) = 0, 'partner cannot delete your diary entry');
select public.mark_messages_read((select id from _aid));
select public.t_ok((select read_at is not null from public.messages limit 1), 'read receipt set via RPC');
select public.t_ok(public.t_count('select 1 from public.chat_reads') = 1, 'David has a private last-read marker');
select set_config('request.jwt.claim.sub', :mercy, false);
select public.t_ok(public.t_count('select 1 from public.chat_reads') = 0, 'Mercy cannot see David''s last-read marker');
select set_config('request.jwt.claim.sub', :david, false);

-- Sealed answers ------------------------------------------------------
select set_config('request.jwt.claim.sub', :mercy, false);
insert into public.game_responses (session_id, circle_id, round, user_id, answer)
  values ((select id from public.game_sessions limit 1), (select id from _aid), 1, :mercy, '"beach"');
select set_config('request.jwt.claim.sub', :david, false);
select public.t_ok(public.t_count('select 1 from public.game_responses') = 0, 'SEALED: David cannot see Mercy''s answer before answering');
insert into public.game_responses (session_id, circle_id, round, user_id, answer)
  values ((select id from public.game_sessions limit 1), (select id from _aid), 1, :david, '"mountains"');
select public.t_ok(public.t_count('select 1 from public.game_responses') = 2, 'REVEAL: both answers visible once David answers');
select public.t_fails(format($q$insert into public.game_responses (session_id, circle_id, round, user_id, answer) values ((select id from public.game_sessions limit 1), %L, 1, %L, '"changed"')$q$, (select id from _aid), :david),
  'cannot answer the same round twice');

insert into public.reading_reflections (circle_book_id, circle_id, chapter, user_id, body)
  values ((select id from public.circle_books limit 1), (select id from _aid), 1, :david, 'I loved the clocks');
select set_config('request.jwt.claim.sub', :mercy, false);
select public.t_ok(public.t_count('select 1 from public.reading_reflections') = 0, 'SEALED: chapter reflection hidden until Mercy reflects');
insert into public.highlights (circle_book_id, circle_id, user_id, chapter, quote)
  values ((select id from public.circle_books limit 1), (select id from _aid), :mercy, 1, 'He is in there, five hours ago');
select set_config('request.jwt.claim.sub', :david, false);
select public.t_ok(public.t_count($q$select 1 from public.notifications where kind = 'reading_highlight'$q$) = 1, 'David notified of Mercy''s highlight');

-- Library & admin boundaries ------------------------------------------
select public.t_fails($q$insert into public.books (title, license, published) values ('Pirated bestseller', 'public_domain', true)$q$, 'users cannot add to the global catalog');
select public.t_fails($q$insert into public.books (circle_id, title, license, created_by) values (public.current_circle_id(), 'x', 'licensed', auth.uid())$q$, 'couples cannot mark uploads as licensed');
insert into public.books (circle_id, title, license, created_by) values (public.current_circle_id(), 'Our love letters', 'user_authorized', :david);
select public.t_ok(true, 'couple can upload a private book');
select set_config('request.jwt.claim.sub', :kemi, false);
select public.t_ok(public.t_count($q$select 1 from public.books where title = 'Our love letters'$q$) = 0, 'circle B cannot see circle A private book');
select public.t_ok(public.t_count($q$select 1 from public.books where circle_id is null$q$) = 4, 'everyone sees the published catalog');

select set_config('request.jwt.claim.sub', :ada, false);
select public.t_ok(public.t_count('select 1 from public.messages') + public.t_count('select 1 from public.diary_entries')
                   + public.t_count('select 1 from public.memories') + public.t_count($q$select 1 from storage.objects$q$) = 0,
                   'ADMIN cannot read any couple''s messages, diary, memories or files');
insert into public.books (title, license, license_ref, published) values ('Licensed novel', 'licensed', 'CONTRACT-001', false);
select public.t_ok(true, 'admin can add licensed catalog book with license ref');
select public.t_fails($q$insert into public.books (title, license, published) values ('No ref', 'licensed', true)$q$, 'licensed book requires license reference');

-- Privilege escalation -------------------------------------------------
select set_config('request.jwt.claim.sub', :eve, false);
select public.t_fails(format($q$insert into public.app_admins (user_id) values (%L)$q$, :eve), 'users cannot make themselves admin');
select public.t_fails(format($q$update public.profiles set date_of_birth = '2015-01-01' where id = %L$q$, :eve), 'cannot change DOB to under 18');
-- invite brute force
select public.join_circle('ZZZZZZZZ') from generate_series(1, 8);   -- + 1 failed preview + 1 failed join above = 10
do $$ begin
  perform public.join_circle('YYYYYYYY');
  raise exception 'FAIL: rate limit did not trigger';
exception when sqlstate '54000' then
  raise notice 'PASS: invite guessing rate-limited after 10 failures/hour (%)', sqlerrm;
end $$;

-- =====================================================================
-- Competition rules
-- =====================================================================
reset role;
insert into public.competitions (id, year, status, registration_opens, registration_closes, voting_opens, voting_closes,
                                 selection_method, allowed_countries, terms_md)
values ('77777777-7777-7777-7777-777777777777', 2026, 'registration', now() - interval '1 day', now() + interval '10 days',
        now() - interval '1 day', now() + interval '20 days', 'hybrid', '{NG,US}', 'Terms v1');
insert into public.competition_fees values ('77777777-7777-7777-7777-777777777777', 'NGN', 0), ('77777777-7777-7777-7777-777777777777', 'USD', 0);

set role authenticated;
select set_config('request.jwt.claim.sub', :mercy, false);
insert into public.competition_entries (competition_id, circle_id, couple_name, story, submitted_by)
  values ('77777777-7777-7777-7777-777777777777', (select id from _aid), 'Mercy & David', 'Our story', :mercy);
select public.t_ok(public.consent_to_entry((select id from public.competition_entries), true, 'v1') = 'awaiting_consent', 'one partner''s consent is not enough');
select public.t_fails($q$update public.competition_entries set payment_status = 'paid'$q$, 'couple cannot mark entry as paid');
select set_config('request.jwt.claim.sub', :david, false);
select public.t_ok(public.consent_to_entry((select id from public.competition_entries), true, 'v1') = 'submitted', 'entry submitted once BOTH partners consent (free entry)');

reset role;
update public.competition_entries set status = 'finalist';
update public.competitions set status = 'voting';
set role authenticated;
select set_config('request.jwt.claim.sub', :kemi, false);
select public.t_ok(public.t_count($q$select 1 from public.list_finalists('77777777-7777-7777-7777-777777777777')$q$) = 1, 'consented finalist is publicly listed');
select public.t_ok(public.t_count('select 1 from public.competition_entries') = 0, 'raw entry rows stay private to the couple');
select public.cast_vote((select entry_id from public.list_finalists('77777777-7777-7777-7777-777777777777')));
select public.t_fails($q$select public.cast_vote((select entry_id from public.list_finalists('77777777-7777-7777-7777-777777777777')))$q$, 'one vote per person');
select set_config('request.jwt.claim.sub', :david, false);
select public.t_fails($q$select public.cast_vote((select entry_id from public.list_finalists('77777777-7777-7777-7777-777777777777')))$q$, 'cannot vote for your own entry');
select public.t_fails($q$insert into public.competition_votes (competition_id, entry_id, voter_id) values ('77777777-7777-7777-7777-777777777777', (select id from public.competition_entries), auth.uid())$q$, 'votes cannot be inserted directly');
-- withdrawing public approval removes from public listing
delete from public.competition_consents where user_id = auth.uid();
select set_config('request.jwt.claim.sub', :kemi, false);
select public.t_ok(public.t_count($q$select 1 from public.list_finalists('77777777-7777-7777-7777-777777777777')$q$) = 0, 'finalist hidden when a partner withdraws consent');

select set_config('request.jwt.claim.sub', :ada, false);
select public.t_ok(public.t_count($q$select 1 from public.compute_competition_results('77777777-7777-7777-7777-777777777777')$q$) = 1, 'admin can compute results');
select set_config('request.jwt.claim.sub', :kemi, false);
select public.t_fails($q$select public.compute_competition_results('77777777-7777-7777-7777-777777777777')$q$, 'non-admin cannot compute results');

-- =====================================================================
-- Ending a relationship
-- =====================================================================
select set_config('request.jwt.claim.sub', :mercy, false);
select public.t_ok(public.end_circle((select id from _aid)) > now() + interval '29 days', 'Mercy ends circle A; 30-day export window');
select public.t_fails(format($q$insert into public.messages (circle_id, sender_id, client_id, body) values (%L, %L, gen_random_uuid(), 'after')$q$, (select id from _aid), :mercy),
  'ended circle is read-only');
select public.t_ok(public.t_count('select 1 from public.memories') = 1, 'former member can still view memories during export window');
select public.t_ok(public.t_count(format('select 1 from public.profiles where id = %L', :mercy)) = 1, 'account untouched after ending circle');
select set_config('request.jwt.claim.sub', :david, false);
select public.t_ok(public.t_count($q$select 1 from public.notifications where kind = 'circle_ended'$q$) = 1, 'David receives a neutral notice');
select public.delete_my_content((select id from _aid));
select public.t_ok(public.t_count(format('select 1 from public.messages where sender_id = %L', :david)) = 0
                   and public.t_count('select 1 from public.diary_entries') = 1, 'David deletes only his own content; Mercy''s diary remains');
create temp table _d as select * from public.create_circle();
select public.t_ok(true, 'David can start a new circle after the old one ends');
select set_config('request.jwt.claim.sub', :mercy, false);
select public.t_ok(public.join_circle((select code from _d)) is not null, 'former partners may reconnect in a NEW circle');
select public.t_ok(public.t_count(format('select 1 from public.messages where circle_id = %L', (select circle_id from _d))) = 0,
                   'new circle starts empty (old content not carried over)');

-- purge after the window
reset role;
update public.circles set purge_after = now() - interval '1 minute' where id = (select id from _aid);
select public.t_ok(public.purge_ended_circles() = 1, 'scheduled purge removes the ended circle');
select public.t_ok((select count(*) from public.memories) = 0 and (select count(*) from storage.objects where bucket_id = 'circle-media') = 0,
                   'its memories and files are gone');
select public.t_ok((select count(*) from public.profiles) = 6, 'all user accounts still exist');

\echo '✅ ALL ISOLATION & SECURITY CHECKS PASSED'
