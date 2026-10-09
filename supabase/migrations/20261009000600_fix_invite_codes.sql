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
