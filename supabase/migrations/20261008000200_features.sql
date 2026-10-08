-- =====================================================================
-- Lovebird 0002 — Shared content: chat, media, memories, diary, plans,
-- special dates, Together Mode, games (sealed answers), Movie Night,
-- library & Read Together, suggestions, reports, AI usage, entitlements.
-- Every private table: circle_id + RLS via can_read_circle/can_write_circle.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Media registry (quota + cleanup; files live in storage bucket circle-media)
-- ---------------------------------------------------------------------
create table public.media (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid not null references public.circles(id) on delete cascade,
  uploader_id uuid not null references auth.users(id) on delete cascade,
  path        text not null unique,
  mime        text not null check (mime ~ '^(image|audio|video)/'),
  bytes       bigint not null check (bytes > 0 and bytes <= 52428800),
  width       int,
  height      int,
  duration_ms int,
  created_at  timestamptz not null default now(),
  check (split_part(path, '/', 1) = circle_id::text)
);
create index media_circle on public.media (circle_id, created_at desc);

-- ---------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------
create table public.messages (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid not null references public.circles(id) on delete cascade,
  sender_id   uuid not null references auth.users(id) on delete cascade,
  client_id   uuid not null,                         -- idempotent retries on bad networks
  kind        text not null default 'text' check (kind in ('text','image','voice','gif','system')),
  body        text check (char_length(body) <= 4000),
  media_path  text,
  meta        jsonb not null default '{}'::jsonb,      -- duration, dimensions, gif url
  reply_to    uuid references public.messages(id) on delete set null,
  created_at  timestamptz not null default now(),
  delivered_at timestamptz,
  read_at     timestamptz,
  deleted_at  timestamptz,
  unique (sender_id, client_id),
  check (kind <> 'text' or (body is not null and char_length(btrim(body)) > 0)),
  check (kind not in ('image','voice') or media_path is not null),
  check (media_path is null or split_part(media_path, '/', 1) = circle_id::text)
);
create index messages_circle_time on public.messages (circle_id, created_at desc);

create table public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  circle_id  uuid not null references public.circles(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  emoji      text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

-- reaction.circle_id must match its message's circle
create or replace function public.reaction_matches_message()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.messages where id = new.message_id and circle_id = new.circle_id) then
    raise exception 'Reaction does not match message' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger message_reactions_match before insert on public.message_reactions
  for each row execute function public.reaction_matches_message();

-- Each person's private "last read" marker (drives their own unread badge even
-- when they've turned read receipts OFF, so the partner never learns it).
create table public.chat_reads (
  circle_id    uuid not null references public.circles(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);

-- Receipts: partner marks everything up to now as delivered/read.
create or replace function public.mark_messages_read(p_circle uuid, p_read boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  show_receipts boolean;
begin
  if not public.can_read_circle(p_circle) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  select coalesce((privacy_prefs ->> 'read_receipts')::boolean, true) into show_receipts
    from public.profiles where id = uid;
  if p_read then
    insert into public.chat_reads (circle_id, user_id, last_read_at) values (p_circle, uid, now())
    on conflict (circle_id, user_id) do update set last_read_at = now();
  end if;
  update public.messages
     set delivered_at = coalesce(delivered_at, now()),
         read_at = case when p_read and show_receipts then coalesce(read_at, now()) else read_at end
   where circle_id = p_circle and sender_id <> uid
     and (delivered_at is null or (p_read and show_receipts and read_at is null));
end $$;

create or replace function public.delete_message(p_message uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.messages
     set deleted_at = now(), body = null, media_path = null, meta = '{}'::jsonb
   where id = p_message and sender_id = (select auth.uid()) and deleted_at is null
     and public.can_write_circle(circle_id);
  if not found then raise exception 'Not allowed' using errcode = '42501'; end if;
end $$;

-- ---------------------------------------------------------------------
-- Memories
-- ---------------------------------------------------------------------
create table public.memories (
  id           uuid primary key default gen_random_uuid(),
  circle_id    uuid not null references public.circles(id) on delete cascade,
  author_id    uuid references auth.users(id) on delete set null,
  title        text not null check (char_length(btrim(title)) between 1 and 120),
  description  text check (char_length(description) <= 4000),
  happened_on  date not null default current_date,
  category     text not null default 'moment'
               check (category in ('moment','date','milestone','trip','movie','game','reading','chat','photo','other')),
  photo_paths  text[] not null default '{}',
  source       text not null default 'manual' check (source in ('manual','suggested')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index memories_circle_date on public.memories (circle_id, happened_on desc);
create trigger memories_touch before update on public.memories for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- Our Diary
-- origin: 'partner' (written by author_id), 'together', 'suggested' (Lovebird proposed, a partner saved)
-- ---------------------------------------------------------------------
create table public.diary_entries (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid not null references public.circles(id) on delete cascade,
  author_id   uuid references auth.users(id) on delete set null,
  origin      text not null default 'partner' check (origin in ('partner','together','suggested')),
  entry_type  text not null default 'written'
              check (entry_type in ('written','memory','funny','romantic','game','movie','reading','milestone','chat')),
  title       text check (char_length(title) <= 120),
  body        text check (char_length(body) <= 20000),
  photo_paths text[] not null default '{}',
  payload     jsonb not null default '{}'::jsonb,   -- e.g. quoted messages, game result
  mood        text check (char_length(mood) <= 16),
  entry_date  date not null default current_date,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (title is not null or body is not null or cardinality(photo_paths) > 0 or payload <> '{}'::jsonb)
);
create index diary_circle_date on public.diary_entries (circle_id, entry_date desc, created_at desc);
create trigger diary_touch before update on public.diary_entries for each row execute function public.touch_updated_at();

-- Frequency cap for "Remember this?" suggestions (avoid fatigue, §26)
create table public.suggestion_log (
  id         bigint generated always as identity primary key,
  circle_id  uuid not null references public.circles(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null,
  outcome    text not null default 'shown' check (outcome in ('shown','saved','dismissed')),
  created_at timestamptz not null default now()
);
create index suggestion_log_circle on public.suggestion_log (circle_id, created_at desc);

create or replace function public.may_suggest(p_circle uuid, p_kind text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select public.can_write_circle(p_circle)
     and not exists (
       select 1 from public.suggestion_log
        where circle_id = p_circle and user_id = (select auth.uid())
          and created_at > now() - interval '20 hours'
     )
     and (select count(*) from public.suggestion_log
           where circle_id = p_circle and user_id = (select auth.uid())
             and outcome = 'dismissed' and created_at > now() - interval '7 days') < 3;
$$;

-- ---------------------------------------------------------------------
-- Our Plans
-- ---------------------------------------------------------------------
create table public.plans (
  id         uuid primary key default gen_random_uuid(),
  circle_id  uuid not null references public.circles(id) on delete cascade,
  title      text not null check (char_length(btrim(title)) between 1 and 80),
  category   text not null default 'bucket'
             check (category in ('dates','movies','books','restaurants','places','gifts','bucket','goals','try','custom')),
  emoji      text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index plans_circle on public.plans (circle_id);

create table public.plan_items (
  id         uuid primary key default gen_random_uuid(),
  plan_id    uuid not null references public.plans(id) on delete cascade,
  circle_id  uuid not null references public.circles(id) on delete cascade,
  text       text not null check (char_length(btrim(text)) between 1 and 300),
  notes      text check (char_length(notes) <= 2000),
  due_at     timestamptz,
  private_to uuid references auth.users(id) on delete cascade, -- e.g. gift ideas hidden from partner
  done_at    timestamptz,
  done_by    uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  position   double precision not null default extract(epoch from now()),
  created_at timestamptz not null default now()
);
create index plan_items_plan on public.plan_items (plan_id, position);
create index plan_items_due on public.plan_items (circle_id, due_at) where due_at is not null and done_at is null;

create or replace function public.plan_item_matches_plan()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.plans where id = new.plan_id and circle_id = new.circle_id) then
    raise exception 'Item does not match plan' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger plan_items_match before insert or update on public.plan_items
  for each row execute function public.plan_item_matches_plan();

-- ---------------------------------------------------------------------
-- Special dates
-- ---------------------------------------------------------------------
create table public.special_dates (
  id           uuid primary key default gen_random_uuid(),
  circle_id    uuid not null references public.circles(id) on delete cascade,
  kind         text not null check (kind in ('anniversary','first_date','first_meeting','birthday','custom')),
  title        text not null check (char_length(btrim(title)) between 1 and 80),
  date         date not null,
  recurs_yearly boolean not null default true,
  remind       boolean not null default true,
  person_id    uuid references auth.users(id) on delete set null,   -- whose birthday
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index special_dates_circle on public.special_dates (circle_id);

-- ---------------------------------------------------------------------
-- Together Mode sessions (the umbrella for any shared activity)
-- ---------------------------------------------------------------------
create table public.together_sessions (
  id           uuid primary key default gen_random_uuid(),
  circle_id    uuid not null references public.circles(id) on delete cascade,
  activity     text not null check (activity in ('play','watch','read','talk','date','create','surprise')),
  ref_type     text check (ref_type in ('game','movie','reading','date','challenge','starter')),
  ref_id       uuid,
  title        text,
  started_by   uuid references auth.users(id) on delete set null,
  status       text not null default 'inviting' check (status in ('inviting','active','ended')),
  joined_at    timestamptz,
  created_at   timestamptz not null default now(),
  ended_at     timestamptz
);
create index together_circle on public.together_sessions (circle_id, created_at desc);
create unique index together_one_live on public.together_sessions (circle_id) where status <> 'ended';

create or replace function public.start_together(p_circle uuid, p_activity text, p_ref_type text, p_ref_id uuid, p_title text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  sid uuid;
begin
  if not public.can_write_circle(p_circle) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  update public.together_sessions set status = 'ended', ended_at = now()
   where circle_id = p_circle and status <> 'ended';
  insert into public.together_sessions (circle_id, activity, ref_type, ref_id, title, started_by)
  values (p_circle, p_activity, p_ref_type, p_ref_id, left(p_title, 120), uid)
  returning id into sid;
  perform public.notify(public.partner_of(p_circle, uid), p_circle, 'together_invite',
    public.display_name_of(uid) || ' wants to spend time together ❤️',
    coalesce(p_title, 'Join them in Together Mode'),
    jsonb_build_object('session_id', sid, 'activity', p_activity, 'ref_type', p_ref_type, 'ref_id', p_ref_id));
  return sid;
end $$;

-- ---------------------------------------------------------------------
-- Games — session state is shared; answers are SEALED until both answer.
-- ---------------------------------------------------------------------
create table public.game_sessions (
  id           uuid primary key default gen_random_uuid(),
  circle_id    uuid not null references public.circles(id) on delete cascade,
  game_key     text not null check (game_key ~ '^[a-z_]{2,40}$'),
  status       text not null default 'active' check (status in ('active','finished','abandoned')),
  round        int  not null default 1 check (round between 1 and 200),
  total_rounds int  not null default 10 check (total_rounds between 1 and 200),
  deck         jsonb not null default '[]'::jsonb,   -- ordered prompt ids for this session
  turn_user_id uuid references auth.users(id) on delete set null,
  state        jsonb not null default '{}'::jsonb,   -- per-game extras (truth/dare choice, revealed flag…)
  scores       jsonb not null default '{}'::jsonb,
  started_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create index game_sessions_circle on public.game_sessions (circle_id, created_at desc);
create trigger game_sessions_touch before update on public.game_sessions for each row execute function public.touch_updated_at();

create table public.game_responses (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.game_sessions(id) on delete cascade,
  circle_id   uuid not null references public.circles(id) on delete cascade,
  round       int not null,
  user_id     uuid not null references auth.users(id) on delete cascade,
  answer      jsonb not null,
  created_at  timestamptz not null default now(),
  unique (session_id, round, user_id)
);
create index game_responses_session on public.game_responses (session_id, round);

create or replace function public.game_response_matches_session()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.game_sessions
                  where id = new.session_id and circle_id = new.circle_id and status = 'active') then
    raise exception 'Game session not active' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger game_responses_match before insert on public.game_responses
  for each row execute function public.game_response_matches_session();

create or replace function public.has_answered_round(p_session uuid, p_round int)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.game_responses
                  where session_id = p_session and round = p_round and user_id = (select auth.uid()));
$$;

-- ---------------------------------------------------------------------
-- Movie Night (durable state for resume; low-latency sync over Broadcast)
-- ---------------------------------------------------------------------
create table public.movie_sessions (
  id               uuid primary key default gen_random_uuid(),
  circle_id        uuid not null references public.circles(id) on delete cascade,
  title            text not null check (char_length(title) <= 200),
  source_url       text not null check (source_url ~ '^https://'),
  source_kind      text not null check (source_kind in ('catalog','user_link')),
  catalog_id       text,
  rights_confirmed boolean not null default false,
  playback_state   text not null default 'paused' check (playback_state in ('paused','playing','ended')),
  position_ms      bigint not null default 0 check (position_ms >= 0),
  state_updated_at timestamptz not null default now(),
  updated_by       uuid references auth.users(id) on delete set null,
  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  ended_at         timestamptz,
  check (source_kind = 'catalog' or rights_confirmed)
);
create index movie_sessions_circle on public.movie_sessions (circle_id, created_at desc);

-- ---------------------------------------------------------------------
-- Library. books.circle_id null = global catalog (admin-managed);
-- non-null = that couple's private upload (love letters, own writing).
-- ---------------------------------------------------------------------
create table public.books (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid references public.circles(id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 200),
  author      text not null default 'Unknown' check (char_length(author) <= 120),
  description text check (char_length(description) <= 2000),
  cover_color text not null default '#E8628C' check (cover_color ~ '^#[0-9A-Fa-f]{6}$'),
  category    text not null default 'short_story'
              check (category in ('novel','short_story','romance','poetry','relationship','interactive','love_letter','original','other')),
  license     text not null check (license in ('public_domain','original','licensed','user_authorized')),
  license_ref text,                        -- contract id / source for licensed works
  language    text not null default 'en',
  tags        text[] not null default '{}',
  published   boolean not null default false,
  is_premium  boolean not null default false,   -- Phase 5 boundary
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  check (license <> 'licensed' or license_ref is not null),
  check (circle_id is null or license = 'user_authorized'),
  check (circle_id is not null or license <> 'user_authorized')
);

create table public.book_chapters (
  id       uuid primary key default gen_random_uuid(),
  book_id  uuid not null references public.books(id) on delete cascade,
  number   int not null check (number >= 1),
  title    text not null,
  body     text not null check (char_length(body) <= 200000),
  unique (book_id, number)
);

create or replace function public.can_read_book(p_book uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.books b
     where b.id = p_book
       and ((b.circle_id is null and b.published) or public.can_read_circle(b.circle_id) or public.is_admin())
  );
$$;

-- A couple's shared shelf / book club
create table public.circle_books (
  id              uuid primary key default gen_random_uuid(),
  circle_id       uuid not null references public.circles(id) on delete cascade,
  book_id         uuid not null references public.books(id) on delete cascade,
  added_by        uuid references auth.users(id) on delete set null,
  status          text not null default 'saved' check (status in ('saved','reading','finished')),
  is_club         boolean not null default false,
  goal            text check (char_length(goal) <= 200),
  schedule        jsonb not null default '{}'::jsonb,   -- {"weekday":5,"time":"20:00","tz":"Africa/Lagos"}
  next_session_at timestamptz,
  started_at      timestamptz,
  finished_at     timestamptz,
  created_at      timestamptz not null default now(),
  unique (circle_id, book_id)
);

create table public.reading_progress (
  circle_book_id uuid not null references public.circle_books(id) on delete cascade,
  circle_id      uuid not null references public.circles(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  chapter        int not null default 1,
  scroll         real not null default 0 check (scroll between 0 and 1),
  chapters_done  int[] not null default '{}',
  last_read_on   date not null default current_date,
  streak_days    int not null default 1,
  updated_at     timestamptz not null default now(),
  primary key (circle_book_id, user_id)
);

create table public.highlights (
  id             uuid primary key default gen_random_uuid(),
  circle_book_id uuid not null references public.circle_books(id) on delete cascade,
  circle_id      uuid not null references public.circles(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  chapter        int not null,
  quote          text not null check (char_length(quote) between 1 and 2000),
  note           text check (char_length(note) <= 2000),
  reaction       text,
  created_at     timestamptz not null default now()
);
create index highlights_book on public.highlights (circle_book_id, chapter);

create table public.highlight_replies (
  id           uuid primary key default gen_random_uuid(),
  highlight_id uuid not null references public.highlights(id) on delete cascade,
  circle_id    uuid not null references public.circles(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 2000),
  created_at   timestamptz not null default now()
);

-- "What did you think of that chapter?" — sealed until both answered.
create table public.reading_reflections (
  id             uuid primary key default gen_random_uuid(),
  circle_book_id uuid not null references public.circle_books(id) on delete cascade,
  circle_id      uuid not null references public.circles(id) on delete cascade,
  chapter        int not null,
  user_id        uuid not null references auth.users(id) on delete cascade,
  body           text not null check (char_length(body) between 1 and 4000),
  rating         int check (rating between 1 and 5),
  created_at     timestamptz not null default now(),
  unique (circle_book_id, chapter, user_id)
);

create or replace function public.has_reflected(p_cb uuid, p_chapter int)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.reading_reflections
                  where circle_book_id = p_cb and chapter = p_chapter and user_id = (select auth.uid()));
$$;

-- Child rows must point at a parent in the same circle.
create or replace function public.circle_book_child_matches()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.circle_books where id = new.circle_book_id and circle_id = new.circle_id) then
    raise exception 'Book does not belong to this circle' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger reading_progress_match before insert or update on public.reading_progress for each row execute function public.circle_book_child_matches();
create trigger highlights_match before insert on public.highlights for each row execute function public.circle_book_child_matches();
create trigger reflections_match before insert on public.reading_reflections for each row execute function public.circle_book_child_matches();

create or replace function public.highlight_reply_matches()
returns trigger language plpgsql as $$
begin
  if not exists (select 1 from public.highlights where id = new.highlight_id and circle_id = new.circle_id) then
    raise exception 'Highlight does not belong to this circle' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger highlight_replies_match before insert on public.highlight_replies for each row execute function public.highlight_reply_matches();

create or replace function public.circle_book_visible()
returns trigger language plpgsql as $$
begin
  if not exists (
    select 1 from public.books b where b.id = new.book_id
      and ((b.circle_id is null and b.published) or b.circle_id = new.circle_id)
  ) then
    raise exception 'Book not available' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger circle_books_visible before insert on public.circle_books for each row execute function public.circle_book_visible();

-- Partner notified when you highlight something (§18)
create or replace function public.on_highlight()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notify(public.partner_of(new.circle_id, new.user_id), new.circle_id, 'reading_highlight',
    'Your partner highlighted something in Chapter ' || new.chapter || ' ❤️',
    left(new.quote, 140), jsonb_build_object('circle_book_id', new.circle_book_id, 'highlight_id', new.id));
  return new;
end $$;
create trigger highlights_notify after insert on public.highlights for each row execute function public.on_highlight();

-- Reading streak bookkeeping
create or replace function public.reading_streak()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    if old.last_read_on = current_date then
      new.streak_days := old.streak_days;
    elsif old.last_read_on = current_date - 1 then
      new.streak_days := old.streak_days + 1;
    else
      new.streak_days := 1;
    end if;
  end if;
  new.last_read_on := current_date;
  new.updated_at := now();
  return new;
end $$;
create trigger reading_progress_streak before insert or update on public.reading_progress
  for each row execute function public.reading_streak();

-- ---------------------------------------------------------------------
-- Reports & moderation. Reporter chooses what to disclose (snapshot).
-- ---------------------------------------------------------------------
create table public.reports (
  id             uuid primary key default gen_random_uuid(),
  reporter_id    uuid not null references auth.users(id) on delete cascade,
  circle_id      uuid references public.circles(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  category       text not null check (category in ('abuse','harassment','inappropriate','illegal','account_abuse','competition_manipulation','other')),
  description    text not null check (char_length(description) between 1 and 4000),
  snapshot       jsonb not null default '{}'::jsonb,
  status         text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  admin_notes    text,
  created_at     timestamptz not null default now(),
  resolved_at    timestamptz
);
create index reports_status on public.reports (status, created_at);

create table public.announcements (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text not null,
  starts_at  timestamptz not null default now(),
  ends_at    timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- AI quota (written by edge functions with the service role only)
create table public.ai_usage (
  circle_id uuid not null references public.circles(id) on delete cascade,
  day       date not null default current_date,
  count     int not null default 0,
  primary key (circle_id, day)
);

-- Phase 5 boundary: entitlements granted by a future payments webhook.
create table public.entitlements (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references auth.users(id) on delete cascade,
  circle_id  uuid references public.circles(id) on delete cascade,
  feature    text not null,
  source     text not null default 'grant' check (source in ('grant','subscription','purchase','prize')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (user_id is not null or circle_id is not null)
);

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.media               enable row level security;
alter table public.messages            enable row level security;
alter table public.message_reactions   enable row level security;
alter table public.chat_reads          enable row level security;
alter table public.memories            enable row level security;
alter table public.diary_entries       enable row level security;
alter table public.suggestion_log      enable row level security;
alter table public.plans               enable row level security;
alter table public.plan_items          enable row level security;
alter table public.special_dates       enable row level security;
alter table public.together_sessions   enable row level security;
alter table public.game_sessions       enable row level security;
alter table public.game_responses      enable row level security;
alter table public.movie_sessions      enable row level security;
alter table public.books               enable row level security;
alter table public.book_chapters       enable row level security;
alter table public.circle_books        enable row level security;
alter table public.reading_progress    enable row level security;
alter table public.highlights          enable row level security;
alter table public.highlight_replies   enable row level security;
alter table public.reading_reflections enable row level security;
alter table public.reports             enable row level security;
alter table public.announcements       enable row level security;
alter table public.ai_usage            enable row level security;
alter table public.entitlements        enable row level security;

-- media
create policy "media: read" on public.media for select to authenticated using (public.can_read_circle(circle_id));
create policy "media: add" on public.media for insert to authenticated
  with check (public.can_write_circle(circle_id) and uploader_id = (select auth.uid()));
create policy "media: delete own" on public.media for delete to authenticated using (uploader_id = (select auth.uid()));

-- messages: no client UPDATE policy; receipts & deletes go through RPCs.
create policy "messages: read" on public.messages for select to authenticated using (public.can_read_circle(circle_id));
create policy "messages: send" on public.messages for insert to authenticated
  with check (public.can_write_circle(circle_id) and sender_id = (select auth.uid()) and kind <> 'system'
              and delivered_at is null and read_at is null and deleted_at is null);

create policy "chat reads: own only" on public.chat_reads for select to authenticated
  using (user_id = (select auth.uid()));

create policy "reactions: read" on public.message_reactions for select to authenticated using (public.can_read_circle(circle_id));
create policy "reactions: add" on public.message_reactions for insert to authenticated
  with check (public.can_write_circle(circle_id) and user_id = (select auth.uid()));
create policy "reactions: remove own" on public.message_reactions for delete to authenticated
  using (user_id = (select auth.uid()));

-- memories: both partners may edit (shared story); only author deletes.
create policy "memories: read" on public.memories for select to authenticated using (public.can_read_circle(circle_id));
create policy "memories: add" on public.memories for insert to authenticated
  with check (public.can_write_circle(circle_id) and author_id = (select auth.uid()));
create policy "memories: edit" on public.memories for update to authenticated
  using (public.can_write_circle(circle_id)) with check (public.can_write_circle(circle_id));
create policy "memories: delete own" on public.memories for delete to authenticated
  using (author_id = (select auth.uid()) and public.can_read_circle(circle_id));
create trigger memories_guard before update on public.memories for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','author_id','created_at');

-- diary: author edits own; 'together' entries editable by both; author deletes.
create policy "diary: read" on public.diary_entries for select to authenticated using (public.can_read_circle(circle_id));
create policy "diary: add" on public.diary_entries for insert to authenticated
  with check (public.can_write_circle(circle_id) and author_id = (select auth.uid()));
create policy "diary: edit" on public.diary_entries for update to authenticated
  using (public.can_write_circle(circle_id) and (author_id = (select auth.uid()) or origin = 'together'))
  with check (public.can_write_circle(circle_id));
create policy "diary: delete own" on public.diary_entries for delete to authenticated
  using (author_id = (select auth.uid()) and public.can_read_circle(circle_id));
create trigger diary_guard before update on public.diary_entries for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','author_id','origin','created_at');

create policy "suggestions: own" on public.suggestion_log for select to authenticated using (user_id = (select auth.uid()));
create policy "suggestions: log" on public.suggestion_log for insert to authenticated
  with check (user_id = (select auth.uid()) and public.can_write_circle(circle_id));

-- plans
create policy "plans: read" on public.plans for select to authenticated using (public.can_read_circle(circle_id));
create policy "plans: add" on public.plans for insert to authenticated
  with check (public.can_write_circle(circle_id) and created_by = (select auth.uid()));
create policy "plans: edit" on public.plans for update to authenticated
  using (public.can_write_circle(circle_id)) with check (public.can_write_circle(circle_id));
create policy "plans: delete" on public.plans for delete to authenticated using (public.can_write_circle(circle_id));
create trigger plans_guard before update on public.plans for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','created_by');

create policy "plan items: read" on public.plan_items for select to authenticated
  using (public.can_read_circle(circle_id) and (private_to is null or private_to = (select auth.uid())));
create policy "plan items: add" on public.plan_items for insert to authenticated
  with check (public.can_write_circle(circle_id) and created_by = (select auth.uid())
              and (private_to is null or private_to = (select auth.uid())));
create policy "plan items: edit" on public.plan_items for update to authenticated
  using (public.can_write_circle(circle_id) and (private_to is null or private_to = (select auth.uid())))
  with check (public.can_write_circle(circle_id) and (private_to is null or private_to = (select auth.uid())));
create policy "plan items: delete" on public.plan_items for delete to authenticated
  using (public.can_write_circle(circle_id) and (private_to is null or private_to = (select auth.uid())));
create trigger plan_items_guard before update on public.plan_items for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','created_by');

-- special dates
create policy "dates: read" on public.special_dates for select to authenticated using (public.can_read_circle(circle_id));
create policy "dates: add" on public.special_dates for insert to authenticated
  with check (public.can_write_circle(circle_id) and created_by = (select auth.uid()));
create policy "dates: edit" on public.special_dates for update to authenticated
  using (public.can_write_circle(circle_id)) with check (public.can_write_circle(circle_id));
create policy "dates: delete" on public.special_dates for delete to authenticated using (public.can_write_circle(circle_id));
create trigger special_dates_guard before update on public.special_dates for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','created_by');

-- together sessions (create via start_together RPC; members may update status)
create policy "together: read" on public.together_sessions for select to authenticated using (public.can_read_circle(circle_id));
create policy "together: update" on public.together_sessions for update to authenticated
  using (public.can_write_circle(circle_id)) with check (public.can_write_circle(circle_id));
create trigger together_guard before update on public.together_sessions for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','started_by','activity','created_at');

-- games
create policy "games: read" on public.game_sessions for select to authenticated using (public.can_read_circle(circle_id));
create policy "games: start" on public.game_sessions for insert to authenticated
  with check (public.can_write_circle(circle_id) and started_by = (select auth.uid()));
create policy "games: advance" on public.game_sessions for update to authenticated
  using (public.can_write_circle(circle_id)) with check (public.can_write_circle(circle_id));
create trigger game_sessions_guard before update on public.game_sessions for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','game_key','started_by','created_at');

-- SEALED: you see your own answer always; your partner's only once you've answered that round.
create policy "game answers: sealed read" on public.game_responses for select to authenticated
  using (
    public.can_read_circle(circle_id)
    and (user_id = (select auth.uid()) or public.has_answered_round(session_id, round))
  );
create policy "game answers: submit" on public.game_responses for insert to authenticated
  with check (public.can_write_circle(circle_id) and user_id = (select auth.uid()));

-- movie
create policy "movie: read" on public.movie_sessions for select to authenticated using (public.can_read_circle(circle_id));
create policy "movie: start" on public.movie_sessions for insert to authenticated
  with check (public.can_write_circle(circle_id) and created_by = (select auth.uid()));
create policy "movie: sync" on public.movie_sessions for update to authenticated
  using (public.can_write_circle(circle_id)) with check (public.can_write_circle(circle_id));
create trigger movie_guard before update on public.movie_sessions for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','source_url','source_kind','created_by','rights_confirmed');

-- books: catalog readable when published; private uploads only by that circle; admins manage catalog.
create policy "books: read" on public.books for select to authenticated
  using ((circle_id is null and published) or public.can_read_circle(circle_id) or public.is_admin());
create policy "books: couple upload" on public.books for insert to authenticated
  with check (circle_id is not null and public.can_write_circle(circle_id)
              and license = 'user_authorized' and created_by = (select auth.uid()) and not is_premium);
create policy "books: couple edit" on public.books for update to authenticated
  using (circle_id is not null and public.can_write_circle(circle_id))
  with check (circle_id is not null and public.can_write_circle(circle_id) and license = 'user_authorized');
create policy "books: couple delete" on public.books for delete to authenticated
  using (circle_id is not null and public.can_write_circle(circle_id));
create policy "books: admin all" on public.books for all to authenticated
  using (public.is_admin() and circle_id is null) with check (public.is_admin() and circle_id is null);
create trigger books_guard before update on public.books for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','created_by');

create policy "chapters: read" on public.book_chapters for select to authenticated using (public.can_read_book(book_id));
create policy "chapters: write own or admin" on public.book_chapters for all to authenticated
  using (exists (select 1 from public.books b where b.id = book_id
                  and ((b.circle_id is not null and public.can_write_circle(b.circle_id)) or (b.circle_id is null and public.is_admin()))))
  with check (exists (select 1 from public.books b where b.id = book_id
                  and ((b.circle_id is not null and public.can_write_circle(b.circle_id)) or (b.circle_id is null and public.is_admin()))));

create policy "shelf: read" on public.circle_books for select to authenticated using (public.can_read_circle(circle_id));
create policy "shelf: add" on public.circle_books for insert to authenticated
  with check (public.can_write_circle(circle_id) and added_by = (select auth.uid()));
create policy "shelf: edit" on public.circle_books for update to authenticated
  using (public.can_write_circle(circle_id)) with check (public.can_write_circle(circle_id));
create policy "shelf: remove" on public.circle_books for delete to authenticated using (public.can_write_circle(circle_id));
create trigger circle_books_guard before update on public.circle_books for each row
  when (current_user = 'authenticated') execute function public.guard_immutable('circle_id','book_id','added_by');

create policy "progress: read" on public.reading_progress for select to authenticated using (public.can_read_circle(circle_id));
create policy "progress: own insert" on public.reading_progress for insert to authenticated
  with check (public.can_write_circle(circle_id) and user_id = (select auth.uid()));
create policy "progress: own update" on public.reading_progress for update to authenticated
  using (user_id = (select auth.uid()) and public.can_write_circle(circle_id))
  with check (user_id = (select auth.uid()) and public.can_write_circle(circle_id));

create policy "highlights: read" on public.highlights for select to authenticated using (public.can_read_circle(circle_id));
create policy "highlights: add" on public.highlights for insert to authenticated
  with check (public.can_write_circle(circle_id) and user_id = (select auth.uid()));
create policy "highlights: delete own" on public.highlights for delete to authenticated using (user_id = (select auth.uid()));

create policy "hl replies: read" on public.highlight_replies for select to authenticated using (public.can_read_circle(circle_id));
create policy "hl replies: add" on public.highlight_replies for insert to authenticated
  with check (public.can_write_circle(circle_id) and user_id = (select auth.uid()));

create policy "reflections: sealed read" on public.reading_reflections for select to authenticated
  using (public.can_read_circle(circle_id)
         and (user_id = (select auth.uid()) or public.has_reflected(circle_book_id, chapter)));
create policy "reflections: add" on public.reading_reflections for insert to authenticated
  with check (public.can_write_circle(circle_id) and user_id = (select auth.uid()));

-- reports
create policy "reports: file" on public.reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and status = 'open' and admin_notes is null
              and (circle_id is null or public.can_read_circle(circle_id)));
create policy "reports: see own" on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()) or public.is_admin());
create policy "reports: admin triage" on public.reports for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "announcements: read live" on public.announcements for select to authenticated
  using ((starts_at <= now() and (ends_at is null or ends_at > now())) or public.is_admin());
create policy "announcements: admin" on public.announcements for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "entitlements: own" on public.entitlements for select to authenticated
  using (user_id = (select auth.uid()) or (circle_id is not null and public.can_read_circle(circle_id)));
-- ai_usage: no client policies (service role only).

-- RPC grants
revoke execute on function public.mark_messages_read(uuid, boolean) from public, anon;
revoke execute on function public.delete_message(uuid) from public, anon;
revoke execute on function public.start_together(uuid, text, text, uuid, text) from public, anon;
revoke execute on function public.may_suggest(uuid, text) from public, anon;
grant execute on function public.mark_messages_read(uuid, boolean) to authenticated;
grant execute on function public.delete_message(uuid) to authenticated;
grant execute on function public.start_together(uuid, text, text, uuid, text) to authenticated;
grant execute on function public.may_suggest(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- Year recap (§29) — computed, private to the circle.
-- ---------------------------------------------------------------------
create or replace function public.circle_year_recap(p_circle uuid, p_year int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  y0 timestamptz := make_timestamptz(p_year, 1, 1, 0, 0, 0, 'UTC');
  y1 timestamptz := make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, 'UTC');
  result jsonb;
begin
  if not public.can_read_circle(p_circle) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'year', p_year,
    'messages', (select count(*) from public.messages where circle_id = p_circle and created_at >= y0 and created_at < y1),
    'games_played', (select count(*) from public.game_sessions where circle_id = p_circle and status = 'finished' and created_at >= y0 and created_at < y1),
    'movie_nights', (select count(*) from public.movie_sessions where circle_id = p_circle and created_at >= y0 and created_at < y1),
    'date_nights', (select count(*) from public.together_sessions where circle_id = p_circle and activity = 'date' and created_at >= y0 and created_at < y1),
    'books_finished', (select count(*) from public.circle_books where circle_id = p_circle and finished_at >= y0 and finished_at < y1),
    'chapters_discussed', (select count(distinct (circle_book_id, chapter)) from public.reading_reflections where circle_id = p_circle and created_at >= y0 and created_at < y1),
    'memories', (select count(*) from public.memories where circle_id = p_circle and happened_on >= y0::date and happened_on < y1::date),
    'diary_entries', (select count(*) from public.diary_entries where circle_id = p_circle and entry_date >= y0::date and entry_date < y1::date),
    'funny_moments', (select count(*) from public.diary_entries where circle_id = p_circle and entry_type = 'funny' and entry_date >= y0::date and entry_date < y1::date),
    'plans_completed', (select count(*) from public.plan_items where circle_id = p_circle and done_at >= y0 and done_at < y1),
    'favorite_activity', (select activity from public.together_sessions where circle_id = p_circle and created_at >= y0 and created_at < y1
                           group by activity order by count(*) desc limit 1),
    'favorite_game', (select game_key from public.game_sessions where circle_id = p_circle and created_at >= y0 and created_at < y1
                       group by game_key order by count(*) desc limit 1),
    'highlights', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'type', entry_type, 'date', entry_date) order by entry_date), '[]'::jsonb)
                     from (select title, entry_type, entry_date from public.diary_entries
                            where circle_id = p_circle and entry_type in ('funny','romantic','milestone')
                              and entry_date >= y0::date and entry_date < y1::date
                            order by created_at desc limit 6) h)
  ) into result;
  return result;
end $$;
revoke execute on function public.circle_year_recap(uuid, int) from public, anon;
grant execute on function public.circle_year_recap(uuid, int) to authenticated;
