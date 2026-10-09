-- Lovebird: complete database setup. Paste this whole file into Supabase → SQL Editor → Run.
-- Generated from supabase/migrations/*.sql — do not edit by hand.

-- ===== migrations/20261008000100_core.sql =====
-- =====================================================================
-- Lovebird 0001 — Core: profiles, Love Circles, membership, invitations
-- Concepts are deliberately separate (brief §40):
--   User account  -> auth.users + public.profiles
--   Love Circle   -> public.circles
--   Membership    -> public.circle_members
--   Shared content-> every feature table, keyed by circle_id (+ author)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create or replace function public.try_uuid(p text)
returns uuid language plpgsql immutable as $$
begin
  return p::uuid;
exception when others then
  return null;
end $$;

-- Reject changes to ownership / scope columns on UPDATE.
-- Usage: create trigger ... execute function public.guard_immutable('circle_id','author_id')
create or replace function public.guard_immutable()
returns trigger language plpgsql as $$
declare
  col text;
  o jsonb := to_jsonb(old);
  n jsonb := to_jsonb(new);
begin
  foreach col in array tg_argv loop
    if (o -> col) is distinct from (n -> col) then
      raise exception 'Column % cannot be changed', col using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Profiles (1:1 with auth.users). 18+ enforced here, not in the UI.
-- ---------------------------------------------------------------------
create table public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  display_name   text not null check (char_length(btrim(display_name)) between 1 and 40),
  avatar_path    text,
  date_of_birth  date not null,
  country_code   char(2),
  currency_code  char(3),
  bio            text check (char_length(bio) <= 280),
  notification_prefs jsonb not null default '{}'::jsonb,
  privacy_prefs      jsonb not null default '{"show_online": true, "read_receipts": true}'::jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create or replace function public.enforce_adult()
returns trigger language plpgsql as $$
begin
  if new.date_of_birth is null or new.date_of_birth > (current_date - interval '18 years')::date then
    raise exception 'Lovebird is for adults aged 18 and over' using errcode = '22023';
  end if;
  if new.date_of_birth < date '1900-01-01' then
    raise exception 'Please enter a valid date of birth' using errcode = '22023';
  end if;
  return new;
end $$;

create trigger profiles_adult before insert or update of date_of_birth on public.profiles
  for each row execute function public.enforce_adult();
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Create the profile from sign-up metadata. If DOB is missing/under 18 the
-- whole sign-up transaction fails, so no under-age account can exist.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, date_of_birth, country_code, currency_code)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), 'Lovebird'),
    (new.raw_user_meta_data ->> 'date_of_birth')::date,
    upper(nullif(new.raw_user_meta_data ->> 'country_code', '')),
    upper(nullif(new.raw_user_meta_data ->> 'currency_code', ''))
  );
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Admins (writable only by service role; no client policy grants insert)
-- ---------------------------------------------------------------------
create table public.app_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_admins where user_id = (select auth.uid()));
$$;

-- ---------------------------------------------------------------------
-- Love Circles
-- ---------------------------------------------------------------------
create table public.circles (
  id                 uuid primary key default gen_random_uuid(),
  status             text not null default 'pending' check (status in ('pending','active','ended')),
  created_by         uuid not null references auth.users(id) on delete cascade,
  couple_name        text check (char_length(couple_name) <= 60),
  relationship_start date,
  theme              text not null default 'blush' check (theme in ('blush','rose','plum','peach','night')),
  created_at         timestamptz not null default now(),
  activated_at       timestamptz,
  ended_at           timestamptz,
  ended_by           uuid references auth.users(id) on delete set null,
  purge_after        timestamptz,
  updated_at         timestamptz not null default now()
);
create trigger circles_touch before update on public.circles
  for each row execute function public.touch_updated_at();

create table public.circle_members (
  id         uuid primary key default gen_random_uuid(),
  circle_id  uuid not null references public.circles(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  joined_at  timestamptz not null default now(),
  left_at    timestamptz,
  unique (circle_id, user_id)
);
-- A person can be in only ONE live circle at a time.
create unique index circle_members_one_active_per_user
  on public.circle_members (user_id) where left_at is null;
create index circle_members_circle on public.circle_members (circle_id);

-- Hard cap: a circle belongs to exactly two people, ever. Defence in depth
-- even if an RPC is bypassed by a future bug.
create or replace function public.enforce_two_members()
returns trigger language plpgsql as $$
declare n int;
begin
  perform 1 from public.circles where id = new.circle_id for update;
  select count(*) into n from public.circle_members where circle_id = new.circle_id;
  if n >= 2 then
    raise exception 'A Love Circle can only have two members' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger circle_members_cap before insert on public.circle_members
  for each row execute function public.enforce_two_members();

-- ---------------------------------------------------------------------
-- Membership helpers. SECURITY DEFINER so policies on other tables can
-- call them without recursive RLS evaluation.
-- ---------------------------------------------------------------------

-- Read access: live member of a pending/active circle, OR former member of
-- an ended circle still inside its export window.
create or replace function public.can_read_circle(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.circle_members m
    join public.circles c on c.id = m.circle_id
    where m.circle_id = cid
      and m.user_id = (select auth.uid())
      and (
        (c.status in ('pending','active') and m.left_at is null)
        or (c.status = 'ended' and c.purge_after > now())
      )
  );
$$;

-- Write access: live member of an ACTIVE circle only.
create or replace function public.can_write_circle(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.circle_members m
    join public.circles c on c.id = m.circle_id
    where m.circle_id = cid
      and m.user_id = (select auth.uid())
      and m.left_at is null
      and c.status = 'active'
  );
$$;

create or replace function public.current_circle_id()
returns uuid language sql stable security definer set search_path = public as $$
  select m.circle_id from public.circle_members m
  where m.user_id = (select auth.uid()) and m.left_at is null
  limit 1;
$$;

create or replace function public.partner_of(cid uuid, uid uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select m.user_id from public.circle_members m
  where m.circle_id = cid and m.user_id <> uid
  limit 1;
$$;

-- True when the caller and `other` share (or shared, within the window) a circle.
create or replace function public.shares_circle_with(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.circle_members a
    join public.circle_members b on b.circle_id = a.circle_id and b.user_id = other
    where a.user_id = (select auth.uid())
      and public.can_read_circle(a.circle_id)
  );
$$;

-- ---------------------------------------------------------------------
-- Invitations
-- ---------------------------------------------------------------------
create table public.invitations (
  id          uuid primary key default gen_random_uuid(),
  circle_id   uuid not null references public.circles(id) on delete cascade,
  code        text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_by  uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '72 hours',
  used_at     timestamptz,
  used_by     uuid references auth.users(id) on delete set null,
  revoked_at  timestamptz
);
create index invitations_circle on public.invitations (circle_id);

create table public.join_attempts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now(),
  success      boolean not null default false
);
create index join_attempts_user_time on public.join_attempts (user_id, attempted_at desc);

-- Unambiguous alphabet (no 0/O/1/I).
create or replace function public.gen_invite_code()
returns text language plpgsql volatile set search_path = public, pg_catalog as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  -- bytes 0-5 and 10-11 of a v4 UUID are fully random (others carry version/variant bits)
  raw bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  idx int[] := array[0, 1, 2, 3, 4, 5, 10, 11];
  out text := '';
  i int;
begin
  foreach i in array idx loop
    out := out || substr(alphabet, (get_byte(raw, i) % 32) + 1, 1);
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- In-app notifications (created only by server-side functions/triggers)
-- ---------------------------------------------------------------------
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  circle_id  uuid references public.circles(id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text,
  data       jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user on public.notifications (user_id, created_at desc);

-- Respects per-kind preferences: notification_prefs = {"game_invite": false, ...}
create or replace function public.notify(p_user uuid, p_circle uuid, p_kind text, p_title text, p_body text, p_data jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare prefs jsonb;
begin
  if p_user is null then return; end if;
  select notification_prefs into prefs from public.profiles where id = p_user;
  if coalesce((prefs ->> p_kind)::boolean, true) = false then
    return;
  end if;
  insert into public.notifications (user_id, circle_id, kind, title, body, data)
  values (p_user, p_circle, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb));
end $$;

create or replace function public.display_name_of(uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select display_name from public.profiles where id = uid), 'Your partner');
$$;

-- ---------------------------------------------------------------------
-- Circle lifecycle RPCs (the ONLY way to create/join/end circles)
-- ---------------------------------------------------------------------
create or replace function public.create_circle()
returns table (circle_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  cid uuid;
  c text;
  exp timestamptz;
begin
  if uid is null then raise exception 'Not signed in' using errcode = '42501'; end if;
  if exists (select 1 from public.circle_members m where m.user_id = uid and m.left_at is null) then
    raise exception 'You are already in a Love Circle' using errcode = '23505';
  end if;

  insert into public.circles (created_by) values (uid) returning id into cid;
  insert into public.circle_members (circle_id, user_id) values (cid, uid);

  loop
    c := public.gen_invite_code();
    begin
      insert into public.invitations (circle_id, code, created_by)
      values (cid, c, uid) returning invitations.expires_at into exp;
      exit;
    exception when unique_violation then
      -- extremely unlikely collision: try again
    end;
  end loop;

  return query select cid, c, exp;
end $$;

create or replace function public.regenerate_invitation(p_circle uuid)
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  c text;
  exp timestamptz;
begin
  if not exists (
    select 1 from public.circle_members m join public.circles ci on ci.id = m.circle_id
    where m.circle_id = p_circle and m.user_id = uid and m.left_at is null and ci.status = 'pending'
  ) then
    raise exception 'Invitation not available' using errcode = '42501';
  end if;
  update public.invitations set revoked_at = now()
   where circle_id = p_circle and used_at is null and revoked_at is null;
  loop
    c := public.gen_invite_code();
    begin
      insert into public.invitations (circle_id, code, created_by)
      values (p_circle, c, uid) returning invitations.expires_at into exp;
      exit;
    exception when unique_violation then
    end;
  end loop;
  return query select c, exp;
end $$;

-- Shows "Mercy invited you" before accepting. Counts as a join attempt.
create or replace function public.preview_invitation(p_code text)
returns table (inviter_name text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  inv public.invitations;
  recent int;
begin
  if uid is null then raise exception 'Not signed in' using errcode = '42501'; end if;
  select count(*) into recent from public.join_attempts
   where user_id = uid and attempted_at > now() - interval '1 hour' and not success;
  if recent >= 10 then
    raise exception 'Too many attempts. Please wait a while and try again.' using errcode = '54000';
  end if;

  select * into inv from public.invitations i where i.code = upper(btrim(p_code));
  if not found or inv.used_at is not null or inv.revoked_at is not null or inv.expires_at < now() then
    -- Do NOT raise: an exception would roll back the attempt log and defeat rate limiting.
    insert into public.join_attempts (user_id, success) values (uid, false);
    return;  -- empty result = invalid/expired
  end if;
  return query select public.display_name_of(inv.created_by), inv.expires_at;
end $$;

create or replace function public.join_circle(p_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  inv public.invitations;
  circ public.circles;
  recent int;
  members int;
begin
  if uid is null then raise exception 'Not signed in' using errcode = '42501'; end if;

  select count(*) into recent from public.join_attempts
   where user_id = uid and attempted_at > now() - interval '1 hour' and not success;
  if recent >= 10 then
    raise exception 'Too many attempts. Please wait a while and try again.' using errcode = '54000';
  end if;

  select * into inv from public.invitations i where i.code = upper(btrim(p_code)) for update;
  if not found or inv.used_at is not null or inv.revoked_at is not null or inv.expires_at < now() then
    -- Do NOT raise: an exception would roll back the attempt log and defeat rate limiting.
    insert into public.join_attempts (user_id, success) values (uid, false);
    return null;  -- null = invalid/expired; client shows a friendly message
  end if;

  select * into circ from public.circles where id = inv.circle_id for update;
  if circ.status <> 'pending' then
    insert into public.join_attempts (user_id, success) values (uid, false);
    return null;
  end if;
  if inv.created_by = uid then
    raise exception 'You cannot join your own invitation. Share it with your partner.' using errcode = '22023';
  end if;
  if exists (select 1 from public.circle_members m where m.user_id = uid and m.left_at is null) then
    raise exception 'You are already in a Love Circle' using errcode = '23505';
  end if;

  select count(*) into members from public.circle_members where circle_id = circ.id;
  if members <> 1 then
    raise exception 'This Love Circle is full' using errcode = '23514';
  end if;

  insert into public.circle_members (circle_id, user_id) values (circ.id, uid);
  update public.invitations set used_at = now(), used_by = uid where id = inv.id;
  update public.invitations set revoked_at = now()
   where circle_id = circ.id and id <> inv.id and used_at is null and revoked_at is null;
  update public.circles set status = 'active', activated_at = now() where id = circ.id;
  insert into public.join_attempts (user_id, success) values (uid, true);

  perform public.notify(circ.created_by, circ.id, 'partner_joined',
    public.display_name_of(uid) || ' joined your Love Circle ❤️',
    'Your private world is ready.', '{}'::jsonb);
  return circ.id;
end $$;

-- Creator abandons a circle nobody joined yet.
create or replace function public.cancel_pending_circle(p_circle uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.circles c
   where c.id = p_circle and c.status = 'pending' and c.created_by = (select auth.uid());
  if not found then
    raise exception 'Nothing to cancel' using errcode = 'P0002';
  end if;
end $$;

-- End a relationship. Account is NOT touched. Shared content becomes
-- read-only for both for 30 days (export window), then is purged.
create or replace function public.end_circle(p_circle uuid)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  other uuid;
  purge timestamptz := now() + interval '30 days';
begin
  if not public.can_write_circle(p_circle) then
    raise exception 'You are not in this Love Circle' using errcode = '42501';
  end if;
  other := public.partner_of(p_circle, uid);

  update public.circles
     set status = 'ended', ended_at = now(), ended_by = uid, purge_after = purge
   where id = p_circle;
  update public.circle_members set left_at = now()
   where circle_id = p_circle and left_at is null;
  -- close anything live
  update public.together_sessions set status = 'ended', ended_at = now()
   where circle_id = p_circle and status <> 'ended';

  -- Neutral, non-manipulative notice.
  perform public.notify(other, p_circle, 'circle_ended',
    'Your Love Circle has ended',
    'Shared memories stay viewable for 30 days so you can save anything you want to keep.',
    jsonb_build_object('purge_after', purge));
  return purge;
end $$;

-- During the export window, remove content *I* authored. Never the partner's.
create or replace function public.delete_my_content(p_circle uuid)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := (select auth.uid());
begin
  if not exists (select 1 from public.circle_members where circle_id = p_circle and user_id = uid) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  delete from public.messages where circle_id = p_circle and sender_id = uid;
  delete from public.diary_entries where circle_id = p_circle and author_id = uid;
  delete from public.memories where circle_id = p_circle and author_id = uid;
  delete from public.media where circle_id = p_circle and uploader_id = uid;
  delete from storage.objects
   where bucket_id = 'circle-media'
     and public.try_uuid((storage.foldername(name))[1]) = p_circle
     and owner_id = uid::text;
end $$;

-- Scheduled (pg_cron, daily): purge circles past their export window.
create or replace function public.purge_ended_circles()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from storage.objects o
   using public.circles c
   where o.bucket_id = 'circle-media'
     and public.try_uuid((storage.foldername(o.name))[1]) = c.id
     and c.status = 'ended' and c.purge_after < now();
  delete from public.circles where status = 'ended' and purge_after < now();
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.purge_ended_circles() from public;

-- ---------------------------------------------------------------------
-- RLS — core
-- ---------------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.app_admins     enable row level security;
alter table public.circles        enable row level security;
alter table public.circle_members enable row level security;
alter table public.invitations    enable row level security;
alter table public.join_attempts  enable row level security;
alter table public.notifications  enable row level security;

create policy "profiles: read self or partner" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.shares_circle_with(id));
create policy "profiles: update self" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "admins: see self" on public.app_admins for select to authenticated
  using (user_id = (select auth.uid()));

create policy "circles: members read" on public.circles for select to authenticated
  using (public.can_read_circle(id));
-- Only cosmetic fields are client-updatable; status etc. guarded by trigger.
create policy "circles: members update" on public.circles for update to authenticated
  using (public.can_write_circle(id)) with check (public.can_write_circle(id));
create trigger circles_guard before update on public.circles
  for each row when (current_user = 'authenticated')
  execute function public.guard_immutable('status','created_by','created_at','activated_at','ended_at','ended_by','purge_after');

create policy "members: read own circles" on public.circle_members for select to authenticated
  using (public.can_read_circle(circle_id) or user_id = (select auth.uid()));

create policy "invitations: members read" on public.invitations for select to authenticated
  using (public.can_read_circle(circle_id));

create policy "notifications: own" on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
create policy "notifications: mark read" on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "notifications: delete own" on public.notifications for delete to authenticated
  using (user_id = (select auth.uid()));
create trigger notifications_guard before update on public.notifications
  for each row when (current_user = 'authenticated')
  execute function public.guard_immutable('user_id','circle_id','kind','title','body','data','created_at');

-- RPC permissions
revoke execute on function public.create_circle() from public, anon;
revoke execute on function public.join_circle(text) from public, anon;
revoke execute on function public.preview_invitation(text) from public, anon;
revoke execute on function public.regenerate_invitation(uuid) from public, anon;
revoke execute on function public.end_circle(uuid) from public, anon;
revoke execute on function public.cancel_pending_circle(uuid) from public, anon;
revoke execute on function public.delete_my_content(uuid) from public, anon;
revoke execute on function public.notify(uuid, uuid, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.create_circle() to authenticated;
grant execute on function public.join_circle(text) to authenticated;
grant execute on function public.preview_invitation(text) to authenticated;
grant execute on function public.regenerate_invitation(uuid) to authenticated;
grant execute on function public.end_circle(uuid) to authenticated;
grant execute on function public.cancel_pending_circle(uuid) to authenticated;
grant execute on function public.delete_my_content(uuid) to authenticated;

-- ===== migrations/20261008000200_features.sql =====
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

-- ===== migrations/20261008000300_competition.sql =====
-- =====================================================================
-- Lovebird 0003 — Couple of the Year (Phase 4)
-- Legal posture (see docs/ARCHITECTURE.md §3.1): fee may be 0, per-country
-- allowlist, 18+, published criteria/terms/prize before entry, judge-led
-- selection by default, votes cannot be bought (no price column exists).
-- =====================================================================

create table public.competitions (
  id                   uuid primary key default gen_random_uuid(),
  year                 int not null,
  title                text not null default 'Lovebird Couple of the Year',
  description          text not null default '',
  status               text not null default 'draft'
                       check (status in ('draft','announced','registration','review','finalists','voting','winner','celebration','closed')),
  registration_opens   timestamptz,
  registration_closes  timestamptz,
  voting_opens         timestamptz,
  voting_closes        timestamptz,
  winner_announce_at   timestamptz,
  celebration_ends_at  timestamptz,
  selection_method     text not null default 'judges' check (selection_method in ('community','judges','hybrid')),
  judge_weight         numeric not null default 0.7 check (judge_weight between 0 and 1),
  criteria             jsonb not null default '[
     {"key":"story","label":"Story & Connection","weight":25},
     {"key":"creativity","label":"Creativity","weight":20},
     {"key":"engagement","label":"Lovebird Engagement","weight":20},
     {"key":"fun","label":"Fun & Personality","weight":15},
     {"key":"community","label":"Community Spirit","weight":20}]'::jsonb,
  terms_md             text not null default '',
  number_of_winners    int not null default 1 check (number_of_winners between 1 and 20),
  allowed_countries    text[] not null default '{}',    -- empty = nowhere until admin sets it
  min_age              int not null default 18 check (min_age >= 18),
  free_entry_available boolean not null default true,
  min_account_age_days int not null default 7,
  created_at           timestamptz not null default now(),
  unique (year)
);

create table public.competition_fees (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  currency       char(3) not null check (currency ~ '^[A-Z]{3}$'),
  amount_minor   bigint not null check (amount_minor >= 0),    -- kobo, cents…
  primary key (competition_id, currency)
);

create table public.competition_prizes (
  id                uuid primary key default gen_random_uuid(),
  competition_id    uuid not null references public.competitions(id) on delete cascade,
  rank              int not null default 1,
  title             text not null,
  description       text not null default '',
  cash_amount_minor bigint check (cash_amount_minor >= 0),
  cash_currency     char(3)
);

create table public.competition_entries (
  id                uuid primary key default gen_random_uuid(),
  competition_id    uuid not null references public.competitions(id) on delete cascade,
  circle_id         uuid not null references public.circles(id) on delete cascade,
  couple_name       text not null check (char_length(btrim(couple_name)) between 1 and 80),
  story             text not null default '' check (char_length(story) <= 5000),
  how_we_met        text not null default '' check (char_length(how_we_met) <= 2000),
  favorite_activity text not null default '' check (char_length(favorite_activity) <= 200),
  favorite_memory   text not null default '' check (char_length(favorite_memory) <= 2000),
  why_lovebird      text not null default '' check (char_length(why_lovebird) <= 2000),
  photo_paths       text[] not null default '{}',
  status            text not null default 'draft'
                    check (status in ('draft','awaiting_consent','pending_payment','submitted','under_review','finalist','rejected','winner','withdrawn')),
  payment_status    text not null default 'not_required' check (payment_status in ('not_required','pending','paid','waived','refunded')),
  fee_currency      char(3),
  fee_amount_minor  bigint,
  submitted_by      uuid references auth.users(id) on delete set null,
  submitted_at      timestamptz,
  final_score       numeric,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (competition_id, circle_id)
);
create trigger competition_entries_touch before update on public.competition_entries
  for each row execute function public.touch_updated_at();

-- BOTH partners must consent; each also separately approves public display.
create table public.competition_consents (
  entry_id        uuid not null references public.competition_entries(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  consented_at    timestamptz not null default now(),
  public_approved boolean not null default false,
  terms_version   text not null,
  primary key (entry_id, user_id)
);

create table public.competition_votes (
  id             uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  entry_id       uuid not null references public.competition_entries(id) on delete cascade,
  voter_id       uuid not null references auth.users(id) on delete cascade,
  created_at     timestamptz not null default now(),
  unique (competition_id, voter_id)                -- one vote per person per year
);

create table public.competition_judges (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  user_id        uuid not null references auth.users(id) on delete cascade,
  display_name   text not null,
  primary key (competition_id, user_id)
);

create table public.competition_scores (
  id             uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  entry_id       uuid not null references public.competition_entries(id) on delete cascade,
  judge_id       uuid not null references auth.users(id) on delete cascade,
  scores         jsonb not null,           -- {"story":8,"creativity":7,...} each 0..10
  comment        text,
  created_at     timestamptz not null default now(),
  unique (entry_id, judge_id)
);

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create or replace function public.is_judge(p_comp uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.competition_judges where competition_id = p_comp and user_id = (select auth.uid()));
$$;

create or replace function public.entry_fully_consented(p_entry uuid, p_public boolean default false)
returns boolean language sql stable security definer set search_path = public as $$
  select (select count(*) from public.competition_consents c
            join public.competition_entries e on e.id = c.entry_id
            join public.circle_members m on m.circle_id = e.circle_id and m.user_id = c.user_id
           where c.entry_id = p_entry and (not p_public or c.public_approved)) = 2;
$$;

-- Partner gives (or withdraws) consent. When both consent, entry advances.
create or replace function public.consent_to_entry(p_entry uuid, p_public boolean, p_terms_version text)
returns text language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  e public.competition_entries;
  comp public.competitions;
  prof public.profiles;
  fee bigint;
begin
  select * into e from public.competition_entries where id = p_entry for update;
  if not found or not public.can_write_circle(e.circle_id) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  select * into comp from public.competitions where id = e.competition_id;
  if comp.status <> 'registration' or now() < coalesce(comp.registration_opens, now()) or now() > coalesce(comp.registration_closes, now()) then
    raise exception 'Registration is closed' using errcode = '22023';
  end if;
  select * into prof from public.profiles where id = uid;
  if prof.date_of_birth > (current_date - make_interval(years => comp.min_age))::date then
    raise exception 'You must be % or older to enter', comp.min_age using errcode = '22023';
  end if;
  if prof.country_code is null or not (prof.country_code = any (comp.allowed_countries)) then
    raise exception 'This competition is not available in your country' using errcode = '22023';
  end if;

  insert into public.competition_consents (entry_id, user_id, public_approved, terms_version)
  values (p_entry, uid, p_public, p_terms_version)
  on conflict (entry_id, user_id) do update set public_approved = excluded.public_approved,
                                                terms_version = excluded.terms_version,
                                                consented_at = now();

  if public.entry_fully_consented(p_entry) then
    select amount_minor into fee from public.competition_fees
     where competition_id = comp.id and currency = coalesce(prof.currency_code, 'USD');
    if coalesce(fee, 0) = 0 then
      update public.competition_entries
         set status = 'submitted', submitted_at = now(), payment_status = 'not_required',
             fee_currency = prof.currency_code, fee_amount_minor = 0
       where id = p_entry;
    else
      -- Payment capture is a Phase 5 integration (Paystack/Stripe webhook flips to 'paid').
      update public.competition_entries
         set status = 'pending_payment', payment_status = 'pending',
             fee_currency = prof.currency_code, fee_amount_minor = fee
       where id = p_entry;
    end if;
  else
    update public.competition_entries set status = 'awaiting_consent' where id = p_entry and status = 'draft';
    perform public.notify(public.partner_of(e.circle_id, uid), e.circle_id, 'competition',
      'Your partner wants to enter Couple of the Year 🏆',
      'Review the entry and give your consent if you''d like to take part.',
      jsonb_build_object('entry_id', p_entry));
  end if;
  return (select status from public.competition_entries where id = p_entry);
end $$;

-- Anti-abuse voting: 18+, confirmed email, account age, one vote, not own entry, live window.
create or replace function public.cast_vote(p_entry uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := (select auth.uid());
  e public.competition_entries;
  comp public.competitions;
  u auth.users;
  prof public.profiles;
begin
  select * into e from public.competition_entries where id = p_entry;
  if not found or e.status <> 'finalist' then
    raise exception 'You can only vote for finalists' using errcode = '22023';
  end if;
  select * into comp from public.competitions where id = e.competition_id;
  if comp.selection_method = 'judges' then
    raise exception 'This year''s winner is chosen by judges' using errcode = '22023';
  end if;
  if comp.status <> 'voting' or now() < comp.voting_opens or now() > comp.voting_closes then
    raise exception 'Voting is not open' using errcode = '22023';
  end if;
  select * into u from auth.users where id = uid;
  if u.email_confirmed_at is null then
    raise exception 'Please confirm your email before voting' using errcode = '22023';
  end if;
  if u.created_at > now() - make_interval(days => comp.min_account_age_days) then
    raise exception 'Your account is too new to vote this year' using errcode = '22023';
  end if;
  select * into prof from public.profiles where id = uid;
  if prof.date_of_birth > (current_date - interval '18 years')::date then
    raise exception 'Not eligible' using errcode = '22023';
  end if;
  if exists (select 1 from public.circle_members where circle_id = e.circle_id and user_id = uid) then
    raise exception 'You can''t vote for your own entry' using errcode = '22023';
  end if;
  insert into public.competition_votes (competition_id, entry_id, voter_id)
  values (comp.id, p_entry, uid);
exception when unique_violation then
  raise exception 'You have already voted this year' using errcode = '23505';
end $$;

-- Public finalist profiles: ONLY approved fields, only when both partners approved public display.
create or replace function public.list_finalists(p_comp uuid)
returns table (entry_id uuid, couple_name text, story text, how_we_met text, favorite_activity text,
               favorite_memory text, photo_paths text[], status text, votes bigint)
language sql stable security definer set search_path = public as $$
  select e.id, e.couple_name, e.story, e.how_we_met, e.favorite_activity, e.favorite_memory,
         e.photo_paths, e.status,
         case when c.status in ('winner','celebration','closed') then (select count(*) from public.competition_votes v where v.entry_id = e.id) else null end
    from public.competition_entries e
    join public.competitions c on c.id = e.competition_id
   where e.competition_id = p_comp
     and e.status in ('finalist','winner')
     and public.entry_fully_consented(e.id, true)
     and (c.status <> 'closed' and (c.celebration_ends_at is null or c.celebration_ends_at > now()));
$$;

-- Admin: compute final scores (does not auto-announce). Scores normalised to 0..100.
create or replace function public.compute_competition_results(p_comp uuid)
returns table (entry_id uuid, judge_score numeric, vote_share numeric, final_score numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare comp public.competitions; total_votes numeric;
begin
  if not public.is_admin() then raise exception 'Admins only' using errcode = '42501'; end if;
  select * into comp from public.competitions where id = p_comp;
  select greatest(count(*), 1) into total_votes from public.competition_votes where competition_id = p_comp;

  return query
  with j as (
    select s.entry_id as eid,
           avg((select sum(least(greatest(coalesce((s.scores ->> (cr ->> 'key'))::numeric, 0), 0), 10) / 10.0
                           * (cr ->> 'weight')::numeric)
                  from jsonb_array_elements(comp.criteria) cr)) as js
      from public.competition_scores s where s.competition_id = p_comp group by s.entry_id
  ), v as (
    select ve.entry_id as eid, count(*)::numeric / total_votes * 100 as vs
      from public.competition_votes ve where ve.competition_id = p_comp group by ve.entry_id
  ), calc as (
    select e.id as eid, coalesce(j.js, 0) as js, coalesce(v.vs, 0) as vs
      from public.competition_entries e
      left join j on j.eid = e.id
      left join v on v.eid = e.id
     where e.competition_id = p_comp and e.status in ('finalist','winner')
  ), upd as (
    update public.competition_entries e
       set final_score = round(case comp.selection_method
                                 when 'judges' then calc.js
                                 when 'community' then calc.vs
                                 else comp.judge_weight * calc.js + (1 - comp.judge_weight) * calc.vs end, 2)
      from calc where e.id = calc.eid
    returning e.id as eid, e.final_score as fs
  )
  select calc.eid, round(calc.js, 2), round(calc.vs, 2), upd.fs
    from calc join upd on upd.eid = calc.eid
   order by upd.fs desc;
end $$;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.competitions         enable row level security;
alter table public.competition_fees     enable row level security;
alter table public.competition_prizes   enable row level security;
alter table public.competition_entries  enable row level security;
alter table public.competition_consents enable row level security;
alter table public.competition_votes    enable row level security;
alter table public.competition_judges   enable row level security;
alter table public.competition_scores   enable row level security;

-- Everything a couple must see BEFORE entering is public to signed-in users (§33).
create policy "comp: read published" on public.competitions for select to authenticated
  using (status <> 'draft' or public.is_admin());
create policy "comp: admin" on public.competitions for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "fees: read" on public.competition_fees for select to authenticated using (true);
create policy "fees: admin" on public.competition_fees for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "prizes: read" on public.competition_prizes for select to authenticated using (true);
create policy "prizes: admin" on public.competition_prizes for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Entries: the couple, judges (submitted+), admins.
create policy "entries: couple read" on public.competition_entries for select to authenticated
  using (public.can_read_circle(circle_id)
         or public.is_admin()
         or (public.is_judge(competition_id) and status in ('submitted','under_review','finalist','winner')));
create policy "entries: couple create" on public.competition_entries for insert to authenticated
  with check (public.can_write_circle(circle_id) and submitted_by = (select auth.uid())
              and status = 'draft' and payment_status = 'not_required' and final_score is null);
create policy "entries: couple edit draft" on public.competition_entries for update to authenticated
  using (public.can_write_circle(circle_id) and status in ('draft','awaiting_consent'))
  with check (public.can_write_circle(circle_id) and status in ('draft','awaiting_consent','withdrawn'));
create policy "entries: admin" on public.competition_entries for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create trigger entries_guard before update on public.competition_entries for each row
  when (current_user = 'authenticated' and not public.is_admin())
  execute function public.guard_immutable('competition_id','circle_id','payment_status','fee_amount_minor','fee_currency','final_score','submitted_at');

-- Editing an entry after a partner consented invalidates consent (they agreed to different content).
create or replace function public.entry_edit_resets_consent()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (old.story, old.how_we_met, old.favorite_activity, old.favorite_memory, old.why_lovebird, old.couple_name, old.photo_paths)
     is distinct from
     (new.story, new.how_we_met, new.favorite_activity, new.favorite_memory, new.why_lovebird, new.couple_name, new.photo_paths) then
    delete from public.competition_consents where entry_id = new.id and user_id <> (select auth.uid());
  end if;
  return new;
end $$;
create trigger entries_reset_consent after update on public.competition_entries for each row
  when (old.status in ('draft','awaiting_consent')) execute function public.entry_edit_resets_consent();

create policy "consents: couple read" on public.competition_consents for select to authenticated
  using (exists (select 1 from public.competition_entries e where e.id = entry_id and public.can_read_circle(e.circle_id)) or public.is_admin());
create policy "consents: withdraw own" on public.competition_consents for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "votes: own" on public.competition_votes for select to authenticated
  using (voter_id = (select auth.uid()) or public.is_admin());

create policy "judges: read" on public.competition_judges for select to authenticated using (true);
create policy "judges: admin" on public.competition_judges for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "scores: judge own" on public.competition_scores for select to authenticated
  using (judge_id = (select auth.uid()) or public.is_admin());
create policy "scores: judge write" on public.competition_scores for insert to authenticated
  with check (judge_id = (select auth.uid()) and public.is_judge(competition_id));
create policy "scores: judge update" on public.competition_scores for update to authenticated
  using (judge_id = (select auth.uid()) and public.is_judge(competition_id))
  with check (judge_id = (select auth.uid()) and public.is_judge(competition_id));

revoke execute on function public.consent_to_entry(uuid, boolean, text) from public, anon;
revoke execute on function public.cast_vote(uuid) from public, anon;
revoke execute on function public.list_finalists(uuid) from public, anon;
revoke execute on function public.compute_competition_results(uuid) from public, anon;
grant execute on function public.consent_to_entry(uuid, boolean, text) to authenticated;
grant execute on function public.cast_vote(uuid) to authenticated;
grant execute on function public.list_finalists(uuid) to authenticated;
grant execute on function public.compute_competition_results(uuid) to authenticated;

-- ===== migrations/20261008000400_storage_realtime.sql =====
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

-- ===== migrations/20261008000500_seed_library.sql =====
-- =====================================================================
-- Lovebird 0005 — Library seed: Lovebird Originals + public-domain poetry.
-- Only original or public-domain text ships here (brief §20).
-- =====================================================================

do $$
declare b uuid;
begin
  -- -------------------------------------------------------------------
  insert into public.books (title, author, description, cover_color, category, license, tags, published)
  values ('The Clock Between Us', 'Lovebird Originals',
          'Lagos and Toronto are five hours apart. Ada and Tomi decide that is not the same thing as being apart.',
          '#C2185B', 'original', 'original', '{long-distance,romance,short}', true)
  returning id into b;
  insert into public.book_chapters (book_id, number, title, body) values
  (b, 1, 'Two Clocks', $t$Ada kept two clocks on her desk. The first was the one everyone in Lagos had: honest, loud, permanently ten minutes fast because her mother had set it that way in 2014 and nobody had dared to touch it since. The second clock was small and white and set five hours behind. It was Tomi's clock.

"You know your phone can do this," Tomi said on the first night she showed him. His face filled the screen, pixelated at the edges, the light behind him the colour of an evening that had not reached her yet.

"My phone can do a lot of things," Ada said. "It cannot sit on my desk and be yours."

He laughed, the kind of laugh that started in his shoulders before it reached his mouth, and she decided she had been right to buy it.

The rule was simple. When Ada woke up, she looked at the white clock and guessed what he was doing. Two in the morning: asleep, probably on his stomach, probably with one sock off. Seven in the evening: walking home from the library, earphones in, pretending not to be cold. She wrote her guesses down in a notebook, and on Sundays they compared.

She was right more often than he liked.

"It's unsettling," he said. "You've built a model of me."

"I've built a model of us," she corrected. "You're just the part that lives in a different time zone."$t$),
  (b, 2, 'The Overlap', $t$There were three hours every day when they were both awake and neither of them was working. They called it the Overlap, and they guarded it like a country guards its border.

In the Overlap they cooked the same meal: jollof on both ends of the call, his always a little too wet, hers always a little too proud. They watched the same terrible films and paused them at the same moment to argue about whether the main character deserved forgiveness. They read the same chapter of the same book and fought, gently, about the ending.

Sometimes they did nothing at all. Ada would fall asleep with the call still running, and Tomi would listen to the fan in her room turn and turn, and he would finish his reading to the sound of it.

"Is that weird?" he asked once. "That I like listening to you sleep?"

"It's weird," Ada agreed, eyes closed. "Keep doing it."

The Overlap was not enough. They both knew that. But it was theirs, and it was built on purpose, and on the nights when the distance felt like a physical thing pressing on Ada's chest, she would look at the white clock and think: he is in there, five hours ago, walking towards me.$t$),
  (b, 3, 'Same Time Zone', $t$The ticket was for a Thursday. Ada had wanted a Saturday, for the symmetry, but Thursday was cheaper and Tomi said symmetry was a luxury for people who did not pay rent.

On the flight she did not sleep. She held the white clock in her lap, and somewhere over the Atlantic, she reached into the back of it and turned the little wheel. One hour. Two. She stopped at four, because the plane was still in the air and she did not want to arrive early, even in theory.

He was at the barrier with a sign that said ADA in letters so large they were almost rude. He was wearing both socks. She checked.

"Hi," he said, which was a stupid thing to say after eleven months, and also the only thing.

"Hi," she said, and held up the white clock. The last hour was still left. "Will you do it?"

He took it from her carefully, like it was something that might wake up. He turned the wheel until the hands matched the big clock on the arrivals board, and then he gave it back.

"There," he said. "Same time."

They would go back to two clocks in nine days. They both knew that too. But Ada kept the white clock on Toronto time for the whole visit, and on the flight home she did not change it back for a long while.$t$);

  -- -------------------------------------------------------------------
  insert into public.books (title, author, description, cover_color, category, license, tags, published)
  values ('Letters from the Lighthouse', 'Lovebird Originals',
          'A lighthouse keeper and a radio operator fall in love one sentence at a time, sixty seconds per night.',
          '#AD1457', 'original', 'original', '{letters,slow-burn,short}', true)
  returning id into b;
  insert into public.book_chapters (book_id, number, title, body) values
  (b, 1, 'Sixty Seconds', $t$The regulations gave Mara sixty seconds of open radio every night at nine. It was meant for weather. For the first month, she used it for weather.

"Wind north-north-east, twelve knots. Visibility good. Nothing to report."

On the thirty-third night, a voice came back that was not the coastguard.

"Nothing at all? Not even a nice cloud?"

Mara stared at the receiver. Regulations did not cover nice clouds.

"There was one," she said finally, "shaped like a teapot."

"Thank you," said the voice. "That's the best thing anyone's told me all week." And the sixty seconds ran out.

His name, she learned over the next fortnight, was Ilan. He ran the relay station on the mainland, alone, the way she ran the light. He had a dog that was afraid of seagulls and a kettle that whistled in a minor key. He learned that she had read every book in the lighthouse twice and was starting on the instruction manuals.

Sixty seconds is not a long time. It turns out you can fall in love in it anyway, if you do it a minute at a time.$t$),
  (b, 2, 'The Storm Night', $t$The storm came in on a Tuesday. By nine, the waves were throwing themselves against the rocks with a sound like furniture being moved in heaven, and the radio was mostly static.

"Mara?" His voice came through in pieces. "Mara, are you—"

"I'm fine," she said, though the light was shuddering in its housing and she had not sat down in four hours. "Wind west, forty knots. Visibility—" A wave hit. "Visibility: rude."

Static. Then, faintly: "Talk to me. Use the whole minute. Regulations be damned."

So she did. She told him about the teapot cloud and the instruction manuals and how she had started saving the best sentences of her day for nine o'clock, like sweets in a pocket. She told him she didn't know what his face looked like and found she didn't mind. She was still talking when the minute ended, and she kept talking into the dead radio for a long while after, because the storm was loud and it helped.

At five past nine, the receiver crackled. It was against every rule he had.

"I heard all of it," Ilan said. "Every word. The relay picks up the overflow." A pause. "I save my best sentences too."$t$),
  (b, 3, 'The Boat', $t$In spring the supply boat came, and there was someone on it who was not the supply man.

He was taller than she had pictured and shorter than he had described, and the dog came too, and the dog immediately saw a seagull and hid behind Mara's legs.

"He likes you," Ilan said.

"He's using me as a shield."

"That's how he shows it."

They stood on the jetty and did not know what to do with their hands. They had only ever had sixty seconds. Now they had a whole afternoon, a whole spring, and it was almost too much.

"Wind," Mara said finally, because she had to say something. "Light. South-westerly."

"Visibility?" Ilan asked.

She looked at him properly for the first time.

"Good," she said. "Very good."

At nine that night, out of habit, they both looked at the radio. Then Ilan turned it off, and they used the whole minute, and the one after it, and every one after that.$t$);

  -- -------------------------------------------------------------------
  insert into public.books (title, author, description, cover_color, category, license, tags, published)
  values ('Love Poems for Two', 'Various (public domain)',
          'Five classic love poems to read aloud to each other — one per night, or all at once.',
          '#880E4F', 'poetry', 'public_domain', '{poetry,classic,read-aloud}', true)
  returning id into b;
  insert into public.book_chapters (book_id, number, title, body) values
  (b, 1, 'Sonnet 18 — William Shakespeare (1609)', $t$Shall I compare thee to a summer's day?
Thou art more lovely and more temperate:
Rough winds do shake the darling buds of May,
And summer's lease hath all too short a date;
Sometime too hot the eye of heaven shines,
And often is his gold complexion dimm'd;
And every fair from fair sometime declines,
By chance or nature's changing course untrimm'd;
But thy eternal summer shall not fade,
Nor lose possession of that fair thou ow'st;
Nor shall Death brag thou wander'st in his shade,
When in eternal lines to time thou grow'st:
So long as men can breathe or eyes can see,
So long lives this, and this gives life to thee.$t$),
  (b, 2, 'Sonnet 43 — Elizabeth Barrett Browning (1850)', $t$How do I love thee? Let me count the ways.
I love thee to the depth and breadth and height
My soul can reach, when feeling out of sight
For the ends of being and ideal grace.
I love thee to the level of every day's
Most quiet need, by sun and candle-light.
I love thee freely, as men strive for right.
I love thee purely, as they turn from praise.
I love thee with the passion put to use
In my old griefs, and with my childhood's faith.
I love thee with a love I seemed to lose
With my lost saints. I love thee with the breath,
Smiles, tears, of all my life; and, if God choose,
I shall but love thee better after death.$t$),
  (b, 3, 'A Red, Red Rose — Robert Burns (1794)', $t$O my Luve is like a red, red rose
   That's newly sprung in June;
O my Luve is like the melody
   That's sweetly play'd in tune.

So fair art thou, my bonnie lass,
   So deep in luve am I;
And I will luve thee still, my dear,
   Till a' the seas gang dry.

Till a' the seas gang dry, my dear,
   And the rocks melt wi' the sun;
I will love thee still, my dear,
   While the sands o' life shall run.

And fare thee weel, my only luve!
   And fare thee weel awhile!
And I will come again, my luve,
   Though it were ten thousand mile.$t$),
  (b, 4, 'She Walks in Beauty — Lord Byron (1815)', $t$She walks in beauty, like the night
Of cloudless climes and starry skies;
And all that's best of dark and bright
Meet in her aspect and her eyes;
Thus mellowed to that tender light
Which heaven to gaudy day denies.

One shade the more, one ray the less,
Had half impaired the nameless grace
Which waves in every raven tress,
Or softly lightens o'er her face;
Where thoughts serenely sweet express,
How pure, how dear their dwelling-place.

And on that cheek, and o'er that brow,
So soft, so calm, yet eloquent,
The smiles that win, the tints that glow,
But tell of days in goodness spent,
A mind at peace with all below,
A heart whose love is innocent!$t$),
  (b, 5, 'Sonnet 116 — William Shakespeare (1609)', $t$Let me not to the marriage of true minds
Admit impediments. Love is not love
Which alters when it alteration finds,
Or bends with the remover to remove.
O no! it is an ever-fixed mark
That looks on tempests and is never shaken;
It is the star to every wand'ring bark,
Whose worth's unknown, although his height be taken.
Love's not Time's fool, though rosy lips and cheeks
Within his bending sickle's compass come;
Love alters not with his brief hours and weeks,
But bears it out even to the edge of doom.
If this be error and upon me proved,
I never writ, nor no man ever loved.$t$);

  -- -------------------------------------------------------------------
  insert into public.books (title, author, description, cover_color, category, license, tags, published)
  values ('52 Letters', 'Lovebird Originals',
          'An interactive book: each chapter is a prompt. You both write a letter, then reveal them together.',
          '#D81B60', 'interactive', 'original', '{interactive,letters,prompts}', true)
  returning id into b;
  insert into public.book_chapters (book_id, number, title, body) values
  (b, 1, 'The First Time I Noticed You', $t$Write about the very first moment you noticed your partner. Not when you fell for them — just when they first came into focus. What were they wearing? What did you think? What did you get wrong about them?

When you're done, answer the chapter question below. Your partner won't see your letter until they've written theirs.$t$),
  (b, 2, 'A Small Thing You Do', $t$Choose one small, ordinary thing your partner does that they probably don't know you love. The way they say goodnight. How they type when they're excited. The face they make at bad food.

Describe it so precisely that they'll recognise themselves instantly.$t$),
  (b, 3, 'Our Future Kitchen', $t$Imagine a kitchen you will share one day. What's on the fridge? Who cooks, who cleans, who steals food off the other's plate? What song is playing?

Be specific. Be ridiculous if you want to. This one is supposed to be fun.$t$),
  (b, 4, 'When It Was Hard', $t$Write about a moment in your relationship that was difficult — and what your partner did, or didn't do, that helped you through it.

Be honest and be kind. The goal isn't to reopen anything. It's to say: I saw what you did, and it mattered.$t$);
end $$;

-- ===== migrations/20261009000600_fix_invite_codes.sql =====
-- Fix: invite codes used pgcrypto's gen_random_bytes(), which Supabase installs in the
-- `extensions` schema (not on our functions' search_path), so create_circle failed.
-- Use gen_random_uuid() (built into Postgres 13+) as the randomness source instead.
create or replace function public.gen_invite_code()
returns text language plpgsql volatile set search_path = public, pg_catalog as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  -- bytes 0-5 and 10-11 of a v4 UUID are fully random (others carry version/variant bits)
  raw bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  idx int[] := array[0, 1, 2, 3, 4, 5, 10, 11];
  out text := '';
  i int;
begin
  foreach i in array idx loop
    out := out || substr(alphabet, (get_byte(raw, i) % 32) + 1, 1);
  end loop;
  return out;
end $$;
