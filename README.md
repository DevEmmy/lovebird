# Lovebird ❤️

> Two people. One private world. A thousand ways to spend time together.

Lovebird is a private couples' app: chat, games, synced Movie Night, Read Together, Our Diary, Memories, Plans, date ideas, and an optional annual Couple of the Year celebration. One **Love Circle** holds exactly two people and nobody else can ever see inside.

| | |
|---|---|
| **App** | Flutter (iOS, Android, Web) · Riverpod · go_router |
| **Backend** | Supabase: Postgres with row-level security, Auth, Realtime, Storage, Edge Functions |
| **Calls** | LiveKit (voice/video) |
| **AI** | Claude via an edge function (optional; offline fallbacks built in) |

Start with **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**. It covers product decisions, gaps in the brief, legal and security risks, the data model and the user flows.

---

## Repository layout

```
lovebird/
├─ docs/ARCHITECTURE.md          decisions, risks, data model, flows, UI structure
├─ supabase/
│  ├─ migrations/                schema + RLS + RPCs + storage + realtime + seed library
│  ├─ functions/                 ai-assist · call-token · delete-account (Deno)
│  ├─ tests/isolation.sql        100 couple-isolation & security checks
│  └─ tests/run_local.sh         run the suite on any Postgres
└─ app/                          Flutter app
   ├─ lib/core                   theme, router, widgets, errors, config
   ├─ lib/data                   models + repositories/providers
   ├─ lib/state                  session, circle, realtime channel
   ├─ lib/features/…             one folder per feature
   ├─ test/                      unit tests (engines, formatting)
   └─ tool/setup_platforms.py    generates android/ios/web + permissions + deep link
```

---

## 1. Backend setup (≈15 min)

1. Create a project at [supabase.com](https://supabase.com) (free tier is fine).
2. Install the [Supabase CLI](https://supabase.com/docs/guides/cli), then:
   ```bash
   cd supabase
   supabase link --project-ref YOUR_REF
   supabase db push                         # applies all migrations
   ```
3. **Dashboard → Realtime → Settings:** turn **off** "Allow public access" so only the private `circle:{id}` channels work. The RLS policies on `realtime.messages` decide who can join.
4. **Scheduled jobs:** the migration enables `pg_cron` and schedules the daily purge of ended circles and the anniversary reminders. Check that they're listed under **Database → Cron**.
5. **Auth → URL configuration:** add `io.lovebird.app://login-callback` and your web URL as redirect URLs. Email confirmation is on by default.
6. **Edge functions:**
   ```bash
   supabase functions deploy ai-assist
   supabase functions deploy call-token
   supabase functions deploy delete-account
   supabase secrets set ANTHROPIC_API_KEY=...          # optional: AI date ideas, starters, recap story
   supabase secrets set LIVEKIT_URL=wss://... LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...   # optional: voice/video
   ```
   Everything works without these keys. AI buttons show a friendly "not switched on yet", and the call button explains that voice isn't set up.
7. **Make yourself an admin** in the SQL editor:
   ```sql
   insert into public.app_admins (user_id) select id from auth.users where email = 'you@example.com';
   ```

### Verify the security model
```bash
PGHOST=localhost PGUSER=postgres ./supabase/tests/run_local.sh
```
This runs 100 checks against a plain Postgres with stand-ins for the Supabase schemas, including:
- couple B can't read, write, upload, subscribe to or control anything belonging to couple A
- a third person can't join a circle
- hidden game answers stay sealed until both partners have answered
- admins can't read private content
- invite-code guessing is rate-limited
- the vote and competition rules hold
- ending a relationship and the 30-day purge both work

## 2. App setup

Requires Flutter ≥ 3.29.
```bash
cd app
python3 tool/setup_platforms.py      # runs `flutter create`, adds permissions + deep link
cp env.example.json env.json         # fill in SUPABASE_URL and SUPABASE_ANON_KEY
flutter pub get
flutter test
flutter run --dart-define-from-file=env.json
```
Web: `flutter run -d chrome --dart-define-from-file=env.json`.

**Try it with two people:** sign up two accounts, using two devices or one browser plus one incognito window. Create a Love Circle on one and join with the code on the other.

---

## What's built

**Phase 1 — Foundation**
- Landing page; sign-up with an 18+ date of birth that the database enforces; email/password auth and reset
- Profiles; create a Love Circle and invite your partner with an 8-character code that expires after 72 hours and works once
- Couple dashboard
- Private chat: text, photos, voice notes, replies, reactions, read/delivered receipts, typing, presence, optimistic sending with retry, delete for both
- 11 interactive games
- Date idea generator, with offline ideas plus AI
- Memories timeline and gallery
- Our Diary: 9 entry types, origin labels, and "Remember this?" suggestions
- Settings, privacy and data export

**Phase 2 — Together**
- Together Mode, with partner invites that appear anywhere in the app
- Movie Night with synced play/pause/seek, drift correction, a "waiting for buffering" signal, in-movie chat, floating reactions and voice/video via LiveKit
- Date Night: 9 guided dates, kept in step for both partners
- Talk starters, synced; Create Together prompts
- Our Plans, including gift ideas hidden from your partner
- Library: Lovebird originals, public-domain poetry, private uploads
- Read Together: progress, streaks, highlights with notifications and replies, sealed chapter reflections
- Book club schedule

**Phase 3 — Intelligence**
- AI date ideas, conversation starters, couple challenges and recap story. Only form inputs are sent to the AI, never chat or diary text.
- On-device diary suggestions with server-side frequency limits
- Yearly recap; anniversary card and reminders

**Phase 4 — Community**
- Couple of the Year:
  - admins configure phases, fees per currency, prizes, judges, criteria, terms and allowed countries
  - both partners must consent, and consent resets if the entry is edited
  - finalist profiles show only details both partners approved
  - voting is one vote per person, 18+, accounts at least 7 days old, never for your own entry and never purchasable
  - judge scoring and hybrid result calculation
- Moderation: reports carry only what the reporter chose to share; admin triage

**Phase 5 — Monetization:** service boundaries only (`PaymentsService`, `entitlements`, `is_premium`). No payment is taken anywhere.

## Before launch: decisions and to-dos
- ⚖️ **Legal review of Couple of the Year before any paid edition.** Paid entry plus a prize can count as a lottery in some places. The fee can be 0, and entry is limited to admin-approved countries. See ARCHITECTURE §3.1.
- 🔔 **Push notifications:** in-app notifications are built. To add mobile push, connect Firebase Cloud Messaging and a small function that sends a push for each `notifications` insert.
- 🎞️ **More films:** the catalog has four Creative Commons Blender films. Licensed partners plug in through `ContentProvider`.
- 🔐 **Optional:** end-to-end encrypted chat, as described in ARCHITECTURE §3.4.
- 📝 Write your Terms, Privacy Policy and competition T&Cs, and link them from sign-up.
