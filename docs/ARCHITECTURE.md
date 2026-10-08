# Lovebird — Architecture & Product Decisions

> Two people. One private world. A thousand ways to spend time together. ❤️

This document covers steps 1–9 of the brief's development process (§60): analysis, gaps, risks, stack, trade-offs, data model, flows and UI structure. Read it before changing the schema.

---

## 1. Product analysis

Lovebird is a **two-member private space** (the *Love Circle*) with five kinds of activity: **talk** (chat, voice), **play** (games), **watch** (Movie Night), **read** (Library, Read Together), and **keep** (Memories, Diary, Plans, Special Dates). All five share one retention loop (§55):

```
enter → choose together → do it (synced) → memorable moment → suggest saving → diary/memories → return
```

So the architecture rests on three primitives that every feature reuses:

| Primitive | What it is | Used by |
|---|---|---|
| **Circle scope** | every private row carries `circle_id`, and RLS checks active membership | everything |
| **Shared session** | a row (`together_sessions`, `game_sessions`, `movie_sessions`, `reading_sessions`) + a Realtime channel `circle:{id}` | games, movie, reading, Together Mode |
| **Sealed answer** | a response row the partner cannot read until they've answered too, **enforced in Postgres** | games, chapter reflections, Couple Quiz |

---

## 2. Missing requirements I filled in (decisions you should confirm)

| Gap in the brief | Decision taken |
|---|---|
| Can a user be in two Love Circles at once? | **No.** One *active* membership per user, enforced by a partial unique index. Prevents the "secret second circle" problem and keeps the product honest to "two people". |
| What happens to shared content when a relationship ends? | Circle becomes `ended`: **read-only** for both former partners for a **30-day export window**, then purged by a scheduled job. During the window, either partner can immediately delete content *they* authored. Neither partner can delete the other's authored content (it is theirs too). Account is untouched. |
| What if a partner deletes their account? | Their membership ends → circle ends using the same rules above. The other partner is notified neutrally. |
| Invitation lifetime | 8-character code, single use, **expires after 72 h**, creator can revoke; join attempts are **rate-limited (10/hour/user)** to stop code guessing. |
| Age | **18+ to use Lovebird** (relationship + intimate media). Date of birth collected at sign-up, enforced by a DB constraint, not just the UI. |
| "Hidden answers, reveal simultaneously" | Enforced server-side: RLS only returns a partner's answer for a round once your own answer exists. Peeking via the API is impossible. |
| Diary auto-suggestions reading private chat | **Done on-device**, not by an AI on the server. Private messages are never sent to an AI model by default. Suggestion frequency capped (max 1 per 24 h per circle, logged in `suggestion_log`). |
| Admin access to private content | **Admins cannot read messages, diary, memories or media.** Reports carry a snapshot the *reporter* chose to submit (consented disclosure). This is deliberate: no "god mode" over intimate data. |
| Push notifications | In-app notifications + per-type preferences ship now. FCM push is a configuration step (needs your Firebase project) – see README. |

---

## 3. Problems in the brief and what I did instead (§60: "do not blindly follow")

### 3.1 Paid-entry contest with a prize is legally risky ⚠️
"Pay to enter + prize + winner chosen by vote" can be classified as an **illegal lottery / unlicensed promotion** depending on jurisdiction:
- **USA**: prize + consideration (fee) + chance = lottery. Popularity voting is not clearly "skill"; several states restrict paid-entry contests altogether.
- **Nigeria**: prize promotions generally need approval (FCCPC / National Lottery Regulatory Commission framework).
- **EU/UK**: consumer-protection & gambling rules vary.

**What's built:** fee is **per-competition, per-currency, admin-configured, and can be 0**. Each competition has an **allowed-countries list**, an **18+ gate**, published terms/criteria/dates/prize before entry, and a **free alternative entry flag** (`free_entry_available`). Winner selection defaults to **Judges** (skill-based, published weighted criteria), with community voting as a weighted input only. **Get legal review before launching a paid edition.** Payment capture is deliberately *not* wired (Phase 5 boundary).

### 3.2 Movie Night cannot sync Netflix/Prime/Disney+
None of them offer a public API for synchronized playback; Teleparty-style approaches inject into their web players, which breaks their ToS. **Built:** synced playback of public-domain / Creative-Commons films (Blender Open Movies, archive.org), plus "bring your own link" for content the user has rights to (with a rights confirmation). A `ContentProvider` interface leaves room for licensed integrations later.

### 3.3 Voice/video calls need media infrastructure
Peer-to-peer WebRTC fails on many mobile networks without TURN servers. **Built:** a `CallService` backed by **LiveKit** (open-source SFU; LiveKit Cloud free tier for the MVP). An edge function mints short-lived room tokens only for circle members, scoped to the room `circle-{id}`.

### 3.4 "Encryption at rest" vs. features
Full end-to-end encryption of chat would block server-side search, moderation snapshots and multi-device history. **Built:** TLS in transit, Supabase disk encryption at rest, private storage buckets with signed URLs (1 h), strict RLS. E2EE for chat is listed as a post-MVP option, and the message table is shaped so `body` can later hold ciphertext.

### 3.5 Copyrighted books
**Built:** library seeded only with original Lovebird stories and public-domain poems. `books.license` is a required enum (`public_domain | original | licensed | user_authorized`), and the reader refuses to show `licensed` books unless `license_ref` is set by an admin.

### 3.6 Couple of the Year: comparing relationships
The copy everywhere says "**celebrating**" stories, never "best couple". Finalists' public profiles show only fields both partners explicitly approved (`*_approved` consent per partner), and expire after the celebration window.

---

## 4. Security risks & mitigations

| Risk | Mitigation |
|---|---|
| Couple A reads couple B's data | RLS on **every** table via `is_circle_member(circle_id)` (security-definer, stable). Isolation test suite in `supabase/tests/isolation.sql` attempts every cross-circle read/write. |
| Third person joins an existing circle | `join_circle` RPC locks the circle row, checks `member_count < 2`; trigger `enforce_two_members` rejects a third insert even if an RPC is bypassed. |
| Invite-code brute force | 8 chars × 31-symbol alphabet (~8.5×10¹¹), 72 h expiry, single use, 10 attempts/h/user logged in `join_attempts`. |
| Peeking at hidden answers | RLS `sealed until answered` policy on `game_responses` and `reading_reflections`. |
| Media URL leakage | Private buckets; storage policies check the first path segment is a circle the caller belongs to; clients only get 1-hour signed URLs. |
| Writing to an ended circle | Insert/update policies require `circle_is_active(circle_id)`. |
| Admin abuse | `app_admins` table; admin policies cover only competitions, library, reports, announcements. No admin policy exists on messages/diary/memories/media. |
| Vote manipulation | One vote per user per competition (unique), voter must be 18+, email-confirmed, account ≥ 7 days old, cannot vote for own entry; votes are never purchasable (no price column exists). |
| AI cost abuse | Edge function checks membership + per-circle daily quota (`ai_usage`). API key only on the server. |
| Self-escalation | `profiles.role` does not exist; admin is a separate table writable only by service role. Users cannot update `circle_members.role`, `circles.status`, etc. directly — only through RPCs. |

---

## 5. Recommended stack (and why)

| Concern | Choice | Why |
|---|---|---|
| App | **Flutter 3.x** (iOS, Android, Web) | your choice; one codebase, mobile-first |
| State/routing | Riverpod 2, go_router | mainstream, testable, low ceremony |
| Backend | **Supabase** | Postgres + RLS gives DB-level authorization (§41 "never rely on frontend"), Auth, Realtime, Storage, Edge Functions in one; generous free tier; no lock-in (it's Postgres) |
| Auth | Supabase Auth (email+password, email confirmation, reset) | Google/Apple sign-in can be enabled later in dashboard |
| Realtime | Supabase Realtime: Postgres changes (durable state) + Broadcast (ephemeral: typing, playback ticks) + Presence (online) | |
| Files | Supabase Storage (private buckets) with client-side image compression | |
| Voice/video | LiveKit | see 3.3 |
| Video sync | own protocol over Broadcast (`play/pause/seek` with position + server-ish timestamp; drift correction > 1.5 s) | |
| Push | Firebase Cloud Messaging (config step) | |
| AI | Claude via edge function (`ai-date-ideas`), with an offline curated engine as fallback | ideas still work with no AI key |
| Payments (Phase 5) | Paystack (NGN/Africa) + Stripe (rest) behind a `PaymentsService` boundary | |
| Analytics | PostHog (self-hostable, privacy-friendly) — event names only, never content | |
| Monitoring | Sentry for Flutter + edge functions | |

---

## 6. Data model

Separate concepts, as required in §40: **User account** (`auth.users` + `profiles`) ≠ **Love Circle** (`circles`) ≠ **Membership** (`circle_members`) ≠ **Shared content** (rows keyed by `circle_id` + `author_id`).

```
auth.users 1─1 profiles
profiles 1─* circle_members *─1 circles          (≤2 active members, ≤1 active circle per user)
circles 1─* invitations
circles 1─* messages ─* message_reactions;  chat_reads (per-user, private last-read marker)
circles 1─* media (storage objects metadata)
circles 1─* memories, diary_entries, plans → plan_items, special_dates
circles 1─* together_sessions
circles 1─* game_sessions 1─* game_responses       (sealed)
circles 1─* movie_sessions
books 1─* book_chapters      (global catalog, license-tracked)
circles 1─* circle_books (shared library / book club) 1─* reading_progress, highlights, reading_reflections (sealed)
circles 1─* notifications, suggestion_log, ai_usage
reports (reporter-scoped)
competitions 1─* competition_fees, competition_prizes, competition_entries ─* competition_votes, competition_scores
competition_judges, app_admins, announcements
```

Full DDL: `supabase/migrations/`.

---

## 7. Key user flows

**Onboarding:** Landing → Sign up (name, email, password, DOB 18+) → confirm email → *Create a Love Circle* (get code + share sheet) **or** *Join with code* → waiting screen ("Waiting for your person…", realtime) → partner joins → Circle active → Dashboard.

**Together Mode:** Together tab → "What should we do together?" → pick Play/Watch/Read/Talk/Date/Create/Surprise → creates `together_sessions` row → partner receives invitation (notification + realtime banner) → both land in the same activity; presence shows who's there; if one drops, the session waits and resumes.

**Sealed game round:** Round prompt shown to both → each answers → "Waiting for David…" → when both rows exist, RLS reveals both → reveal animation + reactions → *Next round* (either partner) → after game end: if a "moment" heuristic fires (matching streak, many 😂 reactions) → "You two really need to remember this one 😂 — Add to Our Diary?"

**End relationship:** More → Relationship → End relationship → explanation screen (what happens to chat, diary, memories; 30-day export; account kept) → type partner's name to confirm → `end_circle()` → neutral notice to partner → user returns to "Create or join" state.

---

## 8. UI structure

```
Mobile bottom nav:   Home | Chat | Together | Memories | More
Desktop/tablet:      NavigationRail (same 5) + content (+ chat side panel in Movie Night)

Home       dashboard: couple header, days together, countdowns, current activity, quick actions, recent memories, reading progress, upcoming plans
Chat       thread, composer (text/photo/voice/emoji), reactions, replies, receipts, typing, presence
Together   Together Mode launcher · Games · Movie Night · Date Night · Date Ideas · Library/Read Together · Challenges
Memories   Timeline/Gallery · Our Diary · Special Dates · Our Year recap
More       Profile · Our Plans · Relationship settings · Notifications · Privacy · Couple of the Year · Report · Admin (if admin) · Sign out
```

Design system: rose/blush palette with warm neutrals ("plum ink" text on "cream" surfaces). Pink is used for actions, highlights and identity, never as body-text colour. All text/background pairs are ≥ 4.5:1. See `lib/core/theme`.

---

## 9. Phasing (what's in this codebase)

| Phase | Status in this build |
|---|---|
| 1 Foundation | ✅ complete |
| 2 Together Experience | ✅ Together Mode, Movie Night sync, games, plans, library, Read Together, book club schedule; voice via LiveKit (needs LiveKit keys) |
| 3 Intelligence | ✅ AI date ideas (+ offline engine), conversation starters, diary suggestions (on-device), challenges, yearly recap, anniversary card |
| 4 Community | ✅ Couple of the Year: config, consented entry, finalist profiles, voting with anti-abuse, judge scoring, admin. Payment capture intentionally stubbed. |
| 5 Monetization | 🧱 boundaries only: `PaymentsService`, `entitlements` table, feature flags. No paid features. |
