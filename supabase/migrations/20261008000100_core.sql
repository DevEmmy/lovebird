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
returns text language plpgsql volatile as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := gen_random_bytes(8);
  out text := '';
  i int;
begin
  for i in 0..7 loop
    out := out || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
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
