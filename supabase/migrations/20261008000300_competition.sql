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
