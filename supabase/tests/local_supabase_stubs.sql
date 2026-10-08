-- Minimal stand-ins for Supabase-managed schemas so migrations and the
-- isolation suite can run on a plain Postgres (CI / local verification).
-- NOT deployed: on Supabase these objects already exist.
do $r$ begin create role anon nologin; exception when duplicate_object then null; end $r$;
do $r$ begin create role authenticated nologin; exception when duplicate_object then null; end $r$;
do $r$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $r$;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb default '{}'::jsonb,
  email_confirmed_at timestamptz,
  created_at timestamptz default now()
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create schema storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text not null,
  owner uuid,
  owner_id text default nullif(current_setting('request.jwt.claim.sub', true), ''),
  created_at timestamptz default now()
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;

create schema realtime;
create table realtime.messages (id bigserial primary key, topic text, payload jsonb);
alter table realtime.messages enable row level security;
create function realtime.topic() returns text language sql stable as $$
  select current_setting('realtime.topic', true)
$$;

grant usage on schema public, auth, storage, realtime to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated;
grant all on all tables in schema storage, realtime to authenticated, service_role;
grant all on all sequences in schema storage, realtime to authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
