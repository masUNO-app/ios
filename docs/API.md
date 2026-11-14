# masUNO API contract

The boundary between the app and Supabase (SPEC §8.5), matched by the Swift protocols in
`MasUno/Data/` and the models in `MasUno/Models/`. A change to either side is one PR reviewed
by both coders. If this file and the spec disagree, this file wins.

**Status: frozen Fri Nov 6; sign-in amended the same day (SPEC N33) and again Nov 11 (SPEC N36: email and
password with manual approval; school SSO kept but unused).** The backend (PR #12) and the live
repositories (B7) are built to this file and checked against `masuno-dev` by `LiveIntegrationTests`. From here
on, a change is a new migration plus the matching Swift change.

## Conventions

- All writes go through RPCs. Reads go through the views below, with RLS applied.
- RPC parameters are prefixed `p_`, so they can't clash with column names in plpgsql.
- RPCs are `security definer`, pin `search_path`, and check `auth.uid()` and `is_active()` first.
- Views use `security_invoker = true`; without it they run as their owner and skip RLS.
- Timestamps are `timestamptz`, sent as ISO 8601. IDs are `uuid`.
- The client sends `null`, not `''`, for an empty optional text. Limits apply after trimming.

## Errors

An RPC fails with `raise exception '<code>'`, so PostgREST returns the code as `message`
(`{"code":"P0001","message":"full"}`). The message is exactly the code, with nothing else in it.
`DomainError(serverCode:)` translates it; an unknown code shows a generic message.

| Code | `DomainError` | Meaning |
| --- | --- | --- |
| `not_authenticated` | `.notAuthenticated` | No valid session. Any RPC. |
| `suspended` | `.suspended` | `banned_at` is set. Any write RPC. The app shows the suspended screen. |
| `pending_approval` | `.pendingApproval` | The account signed up with a password and the team hasn't approved it yet (N36). Any write RPC, including `complete_profile`. The app shows "We're checking your account". |
| `full` | `.full` | No spots left. |
| `cancelled` | `.cancelled` | The game is cancelled. |
| `ended` | `.ended` | The game has ended. |
| `blocked` | `.blocked` | The host or someone going is in a blocked pair with you. |
| `not_found` | `.notFound` | No such game, or a block hides it from you. |
| `not_allowed` | `.notAllowed` | You aren't the host, or the host tried to leave. |
| `limit_reached` | `.limitReached` | Already hosting 3 upcoming games. |
| `capacity_below_going` | `.capacityBelowGoing` | Players set below the number going. |
| `invalid_time` | `.invalidTime` | Start isn't in the future and within 7 days. |
| `invalid_text` | `.invalidText` | The text filter rejected a title, note, meet-up spot or name. |
| `invalid_input` | `.invalidInput` | Anything else out of range or malformed. |
| `chat_rules_required` | `.chatRulesRequired` | `send_message` before `accept_chat_rules`. The app shows "Before you chat". |
| `chat_disabled` | `.chatDisabled` | `send_message` while `app_config.chat_enabled` isn't `true`. |
| `rate_limited` | `.rateLimited` | More than 20 messages in a minute, or more than 5 wrong invite codes in an hour (`redeem_invite`). |
| `invalid_invite` | `.invalidInvite` | `redeem_invite`: no such code, already used, your own, or its member is banned (1.0). |

`redeem_invite` returns `invalid_invite` and `rate_limited` as its result instead of raising them, so the
wrong-try count isn't rolled back (Invites and the waitlist, below). The app maps them the same way.

Client-only: `.offline` (no connection) and `.unknown(code)`.

### Auth errors

These come from Supabase Auth and the auth hook, not from RPCs. `AuthService` (B5) maps them.

| Source | `DomainError` |
| --- | --- |
| Auth hook rejects the account, with message `email_not_allowed` | `.emailNotAllowed` |
| `ASWebAuthenticationSessionError.canceledLogin` (the person closes the web sheet) | None: back to Find your school, with no message |
| Callback says consent was denied or is required | `.schoolApprovalNeeded` (new) |
| Any other error from the web sheet or callback | `.signInFailed` (new) |
| `over_request_rate_limit` | `.tooManyAttempts` |
| `invalid_credentials` | `.invalidCredentials` |
| `user_already_exists` or `email_exists` on sign-up | `.emailTaken` (new, N36) |
| `weak_password` on sign-up | `.weakPassword` (new, N36) |

OAuth failures come back in the callback URL's `error`, `error_code` and `error_description`, and
`auth.signInWithOAuth` throws them as `AuthError.pkceGrantCodeExchange`. B5 checks the exact text for a
hook rejection on `masuno-dev`. If admin consent is needed, Microsoft usually shows its own page in the
sheet, and closing it counts as a cancel, so `.schoolApprovalNeeded` only appears if Microsoft sends an
error back (B21 checks this).

## Reference data (readable by `anon`)

The version gate runs before sign-in, so these need a read policy for `anon`, not only `authenticated`.

| Table | Columns | Swift |
| --- | --- | --- |
| `app_config` | `key`, `value jsonb`; string keys `min_supported_version`, `support_email`, `privacy_url`; boolean key `chat_enabled` (0.6; 0.5 skips it) | `AppConfig` |
| `university_lookup` | see below | `University` |
| `activities` | `slug`, `kind`, `label_en`, `label_es`, `emoji`, `sort_order`, `postable`, `interest_selectable`, `active` | `Activity` |

`university_lookup` is a view used by Find your school: every campus with an `sso_provider` that isn't `is_demo`, open or closed.
Columns: `id`, `name`, `short_name`, `email_domain`, `sso_provider`, `tenant_id`, `signup_enabled`,
`center_lat`, `center_lng` → `University`. This is how the launch campus stays data (SPEC §8.10). Closed
campuses stay listed so their existing accounts can sign back in; the auth hook stops new accounts there.
With exactly one row where `signup_enabled` is true, onboarding names that campus; otherwise the copy stays generic.
`tenant_id` is a record: Supabase sets the Azure tenant once per project, so the app doesn't send it.
Because views use `security_invoker`, `anon` needs a policy that hides `is_demo` rows and a column-level
grant limited to these columns, so `student_email_pattern` stays private.

`activities` is seeded with the slugs `basketball`, `tennis`, `soccer`, `volleyball`, `padel`,
which `Activity.builtIn` repeats as the offline fallback.

## Guests (1.0)

Added by `20261113000000_guest_games` (SPEC R7-15). Signed out, people browse the map and game details,
but names stay with verified students (SPEC §8.8): no host or attendees, no host's note, no meet-up spot,
no chat. Joining, saving, hosting and Who's going need an account. This is the only game read `anon` has;
`game_cards`, `games` and `rsvps` stay closed to it.

`guest_games(p_university uuid)` → `GameRepository.fetchGuestGames(campus:)`, as `Game` with `host` set to
`PersonSummary.hidden`. Callable by `anon` and `authenticated`.

| Column | Type | Swift |
| --- | --- | --- |
| `id` | `uuid` | `id` |
| `activity_slug` | `text` | `activity` |
| `title` | `text` | `title` |
| `starts_at`, `duration_minutes`, `ends_at` | `timestamptz`, `int`, `timestamptz` | `startsAt`, `durationMinutes`, `endsAt` |
| `capacity`, `going_count`, `spots_left` | `int`, `int`, `int` | `capacity`, `goingCount`; `spots_left` as in `game_cards` |
| `place_name`, `place_address`, `lat`, `lng` | `text`, `text`, `float8`, `float8` | `place` |
| `reposted_at`, `created_at` | `timestamptz?`, `timestamptz` | `repostedAt`, `createdAt` |
| `sort_at` | `timestamptz` | `coalesce(reposted_at, created_at)`; rows come newest first |

Rows are the ones `fetchMapGames` reads for a student on that campus: not cancelled, not ended, not full,
starting within 7 days. A campus that `university_lookup` doesn't list (the hidden demo campus) or that has
`signup_enabled` off returns no rows, not an error. No `my_role`, `has_blocked_attendee` or `auto_repost`:
nothing comes back per viewer.

The app only ever calls `guest_games` with a campus from `university_lookup` where `signup_enabled`. With
one such campus it opens the map on it (no picker); with several it shows **Which campus?** first. Guests
do not listen on `campus:<id>:games`; they re-read `guest_games` on foreground and pull.

## Views

### `game_cards` → `Game`

One row per game. The view doesn't hide cancelled, ended or full games, because Event detail shows
them and game RPCs return them. RLS hides games whose host is in a blocked pair with the reader.

| Column | Type | Swift |
| --- | --- | --- |
| `id` | `uuid` | `id` |
| `host_id`, `host_first_name`, `host_last_initial`, `host_grad_year` | `uuid`, `text`, `char(1)`, `int` | `host` |
| `activity_slug` | `text` | `activity` |
| `title` | `text` | `title` |
| `starts_at`, `duration_minutes`, `ends_at` | `timestamptz`, `int`, `timestamptz` | `startsAt`, `durationMinutes`, `endsAt` |
| `capacity`, `going_count` | `int`, `int` | `capacity`, `goingCount` |
| `spots_left` | `int` | computed in Swift; available for filtering |
| `notes` | `text?` | `notes` |
| `place_name`, `place_address`, `lat`, `lng` | `text`, `text`, `float8`, `float8` | `place` |
| `meet_point` | `text?` | `meetPoint` |
| `material_change_at`, `cancelled_at` | `timestamptz?` | `materialChangeAt`, `cancelledAt` |
| `auto_repost`, `reposted_at` | `bool`, `timestamptz?` | `autoRepost`, `repostedAt` |
| `created_at` | `timestamptz` | `createdAt` |
| `sort_at` | `timestamptz` | `coalesce(reposted_at, created_at)`; used for ordering |
| `my_role` | `text?` (`host`, `player`) | `myRole` |
| `my_joined_at` | `timestamptz?` | `myJoinedAt` |
| `has_blocked_attendee` | `bool` | `hasBlockedAttendee` |

How `GameRepository` reads it:

| Method | PostgREST query |
| --- | --- |
| `fetchMapGames` | `cancelled_at=is.null&ends_at=gt.<now>&starts_at=lt.<now+7d>&spots_left=gt.0&order=sort_at.desc` |
| `fetchMyGames` | `my_role=not.is.null&ends_at=gt.<now-14d>` |
| `fetchGame` | `id=eq.<id>`; no row means `not_found` |
| `fetchGames` | `id=in.(<ids>)` |

### `game_attendees` → `Attendee`

`event_id`, `user_id`, `first_name`, `last_initial`, `grad_year`, `role`, `joined_at`, `is_beta_tester` (1.0;
missing on an older server, read as `false`). Excludes anyone in a blocked pair with the reader. `going_count` still counts them.
`fetchAttendees` orders host first, then by `joined_at`.

### `game_activity` → `GameActivityEntry`

A view over an append-only table the RPCs write to (`private.game_activity`): `leave_game` deletes the
`rsvps` row, and one `material_change_at` can't tell a meet-up edit from a time change. Only people in the
game can read its rows. System rows for group chat: `id`, `event_id`, `kind`, `actor_id?`, `actor_first_name?`,
`actor_last_initial?`, `actor_grad_year?`, `at`. Oldest first. Actor columns are null for a deleted
account or a blocked pair. `kind` is one of `created`, `joined`, `left`, `meet_point_updated`,
`time_or_place_changed`, `cancelled`.

### `my_profile` → `Profile`

Your own row, or none until `complete_profile` has run: `id`, `first_name`, `last_name`, `grad_year`,
`university_id`, `university_name`, `university_short_name`, `university_email_domain`, `center_lat`,
`center_lng` (→ `Profile.university`; the map opens here, so review accounts land on the demo campus),
`interests text[]`, `guidelines_accepted_at?`, `banned_at?`, `chat_rules_accepted_at?` (0.6), `is_beta_tester` (1.0;
missing on an older server, read as `false`). `AuthService` uses
`guidelines_accepted_at` and `banned_at` to choose between `.needsGuidelines`, `.suspended` and `.signedIn`.

## RPCs

Game writes return the updated `game_cards` row, so the app never needs a second fetch.

| RPC | Returns | Errors |
| --- | --- | --- |
| `complete_profile(p_first_name text, p_last_name text, p_grad_year int, p_interests text[], p_locale text)` | `my_profile` | `invalid_text`, `invalid_input` |
| `accept_guidelines()` | `void` | — |
| `create_game(p_activity_slug text, p_title text, p_starts_at timestamptz, p_duration_minutes int, p_capacity int, p_notes text, p_place_name text, p_place_address text, p_lat float8, p_lng float8, p_meet_point text, p_auto_repost bool)` | `game_cards` | `invalid_time`, `invalid_text`, `limit_reached`, `invalid_input` |
| `update_game(p_id uuid, …same as create_game)` | `game_cards` | `not_found`, `not_allowed`, `cancelled`, `ended`, `capacity_below_going`, `invalid_time`, `invalid_text`, `invalid_input` |
| `cancel_game(p_id uuid)` | `game_cards` | `not_found`, `not_allowed`, `ended` |
| `join_game(p_id uuid)` | `game_cards` | `full`, `cancelled`, `ended`, `blocked`, `not_found` |
| `leave_game(p_id uuid)` | `game_cards` | `not_found`, `not_allowed`, `ended` |
| `report(p_user_id uuid, p_game_id uuid, p_reason text, p_note text)` | `void` | `invalid_input` |
| `block(p_user_id uuid)`, `unblock(p_user_id uuid)` | `void` | `invalid_input` |
| `my_blocks()` | set of `user_id`, `first_name`, `last_initial`, `grad_year`, newest first | — |

Rules the signatures don't show:

- **`complete_profile`** sets the campus only when it creates the profile: from
  `auth_allowlist.university_id` if the address is listed (including a Tec test account used for App
  Review), otherwise from the domain of the email in `auth.users`. Edits never change it.
- **`update_game`** checks the time window only when `p_starts_at` changes, so a host can still fix
  the meet-up spot once a game has started. It sets `material_change_at` when the time, place or
  meet-up spot changes. If a full game gains a spot and `auto_repost` is on, it sets `reposted_at`.
- **`join_game`** locks the row, and is idempotent: if you're already in, including as host, it
  returns the row unchanged.
- **`leave_game`** locks the row, and returns the row unchanged if you aren't in the game. If the game
  was full, isn't cancelled and has `auto_repost` on, it sets `reposted_at`.
- **`cancel_game`** is a soft cancel. Calling it on a game that's already cancelled returns the row.
- **`report`** takes exactly one of `p_user_id` and `p_game_id`. `p_reason` is one of `harassment`,
  `inappropriate`, `spam`, `unsafe`, `other`.
- **`block`** returns `invalid_input` for yourself or an unknown user; blocking twice is a no-op.

## Group chat (0.6)

Added by `20261110000000_group_chat` (B20). Nothing 0.5 reads or calls changes. System rows stay in
`game_activity`; this section is messages.

**The switch:** `app_config.chat_enabled` is `false` until someone sets it to `true` on that project. Off or
missing, the app shows the read-only chat with no composer, and `send_message` answers `chat_disabled`.

### `game_messages` → `ChatMessage`

`id`, `event_id`, `sender_id`, `sender_first_name`, `sender_last_initial`, `sender_grad_year`, `body`,
`client_id`, `created_at`. Only people in the game can read its rows, and leaving the game closes it.
Messages from a sender in a blocked pair with the reader, and messages a moderator hid, are left out.

| Method | PostgREST query |
| --- | --- |
| `fetchMessages(before:limit:)` | `event_id=eq.<id>&order=created_at.desc&limit=50`, plus `created_at=lte.<oldest>` for an older page |
| `fetchMessages(since:)` | `event_id=eq.<id>&created_at=gte.<newest − 5 s>&order=created_at` |

### `chat_unread`

`event_id`, `unread_count`: one row per game with messages from other people since you last opened its
chat. Games with none have no row.

### RPCs

| RPC | Returns | Errors |
| --- | --- | --- |
| `send_message(p_game_id uuid, p_body text, p_client_id uuid)` | `game_messages` | `not_found`, `not_allowed`, `chat_disabled`, `cancelled`, `ended`, `chat_rules_required`, `invalid_text`, `rate_limited`, `invalid_input` |
| `accept_chat_rules()` | `void` | — |
| `mark_chat_read(p_game_id uuid)` | `void` | — |
| `report_message(p_message_id uuid, p_reason text, p_note text)` | `void` | `invalid_input` |

- **`send_message`** needs you to be in the game (`not_allowed` otherwise). It refuses a cancelled game and
  one that ended more than 24 hours ago (`ended`). The body is trimmed and goes through the same text filter
  as titles, which also refuses links; the limit is 1000 characters. `p_client_id` is the app's own ID for the
  send: sending it again returns the first message, so a retry never posts twice.
- **`mark_chat_read`** does nothing if you aren't in the game.
- **`report_message`** files a report against the sender with the message text copied in. You can't report
  your own message or one you can't see. Reasons are the same as `report`.
- Deleting an account deletes its messages. Message text is deleted 30 days after its game ended.

### Realtime

Each new message or `game_activity` row sends a Broadcast on the private channel `game:<game id>:chat`
(the ID in lowercase), with event `message` or `activity` and payload `{"id": "<row id>"}`. Only people in
the game can join the channel. The payload has no content on purpose: the app reads `game_messages` or
`game_activity` when a ping arrives, so membership and blocks are checked in one place. The app also
checks every 15 seconds while a chat is open, in case the channel is down.

### Game changes

Every statement that writes `games` or `rsvps` sends a Broadcast with event `changed` on the private channel
`campus:<university_id>:games`, once per campus it touched, with `{"ids": [<game IDs>]}`. Over 50 games, the
payload is `{}`: re-read everything on screen. Only that campus's signed-in, unbanned people can listen. The IDs
say which games changed, not how, so the app re-reads those through the RLS views (and the map, if one it
didn't hold might belong there). Bursts are debounced, each phone waits a random extra moment so a campus's
re-reads don't arrive together, and the app also re-reads when it comes back to the foreground.

## Sign-in

Email and password, with each new account approved by hand (SPEC N36). School SSO is below as "kept, unused".

1. **Create account:** `auth.signUp(email, password)`. The Before User Created hook lets through a school
   address at an open campus (`universities.email_domain`, `signup_enabled`, not `is_demo`, `student_email_pattern`)
   and refuses anything else with `email_not_allowed`. For a school address it also adds a row to
   `private.signup_requests` and posts "New sign-up waiting for approval" to the team Discord. "Confirm email" is
   off, so `signUp` returns a session straight away. The app checks 8 characters before sending.
2. **Sign in:** `auth.signInWithPassword(email, password)`, for students and for the `auth_allowlist` accounts.
3. **Next step:** `my_profile` first. No row → RPC `signup_status()` (returns `'pending'` or `'approved'`, raises
   `not_authenticated`): `'pending'` → `.pendingApproval` ("We're checking your account"), otherwise
   `.needsProfile`. With a row: `banned_at` set → `.suspended`; `guidelines_accepted_at` null →
   `.needsGuidelines`; otherwise `.signedIn`.
4. **While pending:** every write RPC raises `pending_approval`, so there's no profile, and without a profile RLS
   shows nothing. The app asks again (`AuthService.refreshStatus()`) on "Check again" and whenever it comes back
   to the front. Once approved it shows "You're in", then Set up profile. From 1.0 this wait is the waitlist,
   and a member's invite code ends it without the team (Invites and the waitlist, below).
5. **Approving** is the team's job, in the SQL editor: `select private.approve_signup('<email>');` or
   `select private.reject_signup('<email>');` (deletes the unapproved account). Both lines are in the Discord
   alert. See `supabase/README.md`, "Sign-up approvals".

There's no password reset email: Sign in links to Contact us, and the team resets a password in the dashboard.

Allowlisted accounts (`auth_allowlist`: `email`, `note`, `university_id`, usually the demo campus) never wait
for approval, and `complete_profile` places them on their campus. They're password accounts Emilio created
with the email already confirmed.

### School SSO (kept, unused)

Tec IT hasn't approved the Entra app, so nothing in the app opens this path. The code stays for the day a
school does: `AuthService.signIn(at:)`, `OnboardingViewModel.continueWithSchool()` and `FindSchoolStep`, plus
the SSO branch of the hook.

1. Find your school reads `university_lookup`. `sso_provider` picks the provider and hint: `azure` →
   `.azure` with `domain_hint=<email_domain>`; `google` → `.google` with `hd=<email_domain>`.
2. School account, on supabase-swift v2 with its default PKCE flow:
   `auth.signInWithOAuth(provider: .azure, redirectTo: masuno://auth-callback, scopes: "openid email profile", queryParams: [(name: "domain_hint", value: <email_domain>)], configure: { $0.prefersEphemeralWebBrowserSession = true })`.
   The SDK opens `ASWebAuthenticationSession`, takes the callback scheme from `redirectTo`, finishes the exchange and
   returns the session. Don't call `start()` in `configure`; the SDK does. The school picked in the app
   isn't trusted: the auth hook checks the provider and the email on the server (SPEC §8.4). An SSO account
   needs no approval.

## Invites and the waitlist (1.0)

Added by `20261114000000_invites_and_beta` (SPEC N37). masUNO is invite-only, like early Gmail. A sign-up
without a code waits for the team exactly as in Sign-in above; the app calls that wait the waitlist. A
member's invite code lets a waiting account in at once, with no approval: typed on Create account (the app
calls `redeem_invite` straight after `signUp`) or later on the waitlist. Each code works once. Every member
has 3; the team gives more with `private.grant_invites` (`supabase/README.md`). Allowlisted accounts and SSO
never wait, so codes don't matter to them.

| RPC | Returns | Errors |
| --- | --- | --- |
| `my_invites()` | set of `code text`, `created_at timestamptz`, `redeemed_at timestamptz?`, `redeemer_first_name text?`, `redeemer_last_initial char(1)?`, oldest first | `pending_approval`, `suspended` |
| `redeem_invite(p_code text)` | `text`: `'approved'`, `'invalid_invite'` or `'rate_limited'` | `not_authenticated` |
| `waitlist_position()` | `int?` | `not_authenticated` |

- **`my_invites`** → `ProfileRepository.fetchInvites()`, as `Invite`. It creates any codes you're still owed
  up to your allowance, so it's never empty for a member with a profile. Codes are 8 characters from
  `A–Z` and `2–9` without `0`, `O`, `1` or `I`; the app shows them as `ABCD-EFGH`. The redeemer's name is
  null until they've set up a profile, or if either of you blocked the other. No emails, ever.
- **`redeem_invite`** → `AuthService.redeemInvite(_:)`. Works while pending (it's the one write that does).
  Spaces, dashes and case in `p_code` don't matter. An account that isn't waiting gets `'approved'` and nothing
  changes. More than 5 wrong codes in an hour answers `'rate_limited'` until the hour is up, even for a good
  code. On success the code is marked used, the request is approved with `invited_by` set, and the team gets
  an FYI ("joined with Ana G.'s invite"), not an approval request. The refusals are returned, not raised: a
  raise would roll back the wrong-try count with the rest of the call. The app throws them as
  `.invalidInvite` and `.rateLimited`, then `refreshStatus()` moves `.pendingApproval` on.
- **`waitlist_position`** → `AuthService.waitlistPosition()`: your place among requests nobody has approved,
  by sign-up time (1 is next), or null when you aren't waiting. From `20261115000000_waitlist_sync` the line
  includes school emails that joined on the website, and a website join's time is your sign-up time
  (Website waitlist sync, below). Same shape, so the app doesn't change.

Server-side columns, none readable by the app: `profiles.invite_allowance` (default 3),
`private.invites` (`code`, `inviter_id`, `created_at`, `redeemed_email`, `redeemed_at`) and, on
`private.signup_requests`, `invited_by`, `invite_attempts` and `invite_attempt_at`.

## Beta tester (1.0)

Also in `20261114000000_invites_and_beta`. The first time a signed-in member opens a TestFlight build, the app
calls `mark_beta_tester()` and the profile keeps a badge for good: on your Me card (`my_profile.is_beta_tester`)
and next to your name in Who's going (`game_attendees.is_beta_tester`).

| RPC | Returns | Errors |
| --- | --- | --- |
| `mark_beta_tester()` | `my_profile` | `pending_approval`, `suspended` |

It sets `profiles.beta_tester_at` once; later calls keep the first time. Others can read only the boolean
(`profiles.is_beta_tester`, a column grant), never when. The app decides it's on TestFlight by itself, so a
modified client could claim the badge: accepted, since it grants nothing.

## Website waitlist sync (1.0)

Added by `20261115000000_waitlist_sync` (SPEC N38). The website's waitlist (the "Waitlist" tab of a Google
Sheet, written by the website's Apps Script) and the app's are one queue: `private.signup_requests`, keyed by
lower-case email. The Sheet mirrors it both ways. A school email that joins on the website gets a request
straight away, so it keeps its place when the person signs up in the app; any other email stays in the
Sheet only, as launch news. The app calls none of this.

Every call carries one shared secret (at least 32 characters): Vault `waitlist_sync_secret` here, Script
Property `WAITLIST_SYNC_SECRET` in the Apps Script. Vault `waitlist_sync_url` is the Apps Script web app's
`/exec` URL. Without both, nothing is pushed and both RPCs refuse every call (`supabase/README.md`, hosted
checklist).

| RPC (`anon`) | Returns |
| --- | --- |
| `waitlist_join(p_secret text, p_email text, p_joined_at timestamptz, p_source text)` | `jsonb`: `{"ok": true, "status": "waiting" \| "approved" \| "member" \| "not_school", "position": int \| null}`, or `{"ok": false, "error": "bad_secret" \| "invalid_input"}` |
| `waitlist_export(p_secret text)` | `jsonb` array of rows (below), in line order; `[]` without the right secret |

- **`waitlist_join`**, from the Apps Script when someone joins on the website (and again for rows the hourly
  heal finds unsynced): `POST /rest/v1/rpc/waitlist_join` with the anon key. `p_source` must be `'website'`
  (or null); anything else is `invalid_input`. `not_school` stores nothing: the address isn't at an open,
  non-demo campus or fails its `student_email_pattern` (the same check as the auth hook), isn't an email, or
  is over 254 characters. Otherwise a request exists afterwards: a new one has `source = 'website'` and
  `requested_at = p_joined_at`; an existing one (from either side) moves to `p_joined_at` only if that's
  earlier. A missing join time, one in the future, or one before 2026 counts as now. No Discord alert: the
  "New sign-up waiting for approval" alert comes when the person creates their account in the app, which
  keeps the website's `requested_at` and `source`. An allowlisted address, or one that already has an account
  without a request (SSO, or from before N36), gets no request, since one would make it wait; it answers
  `approved` or `member`. Refusals are returned, never raised.
- **Status:** `member` when the address has an account with a profile ("In the app"), `approved` when approved
  without a profile yet, `waiting` otherwise. **Position:** the place among unapproved requests by
  `requested_at`, then email, 1 is next; null unless waiting. It's the same count as `waitlist_position()`.
- **Push:** after every statement that inserts, updates or deletes requests, `net.http_post` to
  `waitlist_sync_url` with `{"action": "sync", "secret": "...", "rows": [...]}`, one request per statement
  (approving everyone in one `update` sends one). A new profile pushes its request too, as `member`.
  Wrong-invite-code counts send nothing; a rejected (deleted) request goes as `"status": "removed"`. pg_net
  sends after commit, fire and forget: a failure or missing Vault entry logs a warning and never blocks the
  write. A deleted account isn't pushed; the hourly export corrects it.
- **Row** (push and export): `email`, `status` (`waiting` / `approved` / `member`, or `removed` in a push),
  `requested_at` and `approved_at` (ISO 8601 UTC to the second, `"2026-11-14T15:04:05Z"`, or null), `source`
  (`website` / `app`), `invited_by` (the inviter's first name and last initial, `"Ana G."`, or null) and
  `position` (as above). `position` is an addition to the website contract; the Sheet may ignore it.

These are the only RPCs `anon` can call that write without a session, and the only way in for the website.
They're safe because the secret is the gate: without it `waitlist_join` stores nothing and `waitlist_export`
returns nothing, and the answers say nothing about whether an address is on the list. The secret is compared
by its SHA-256 hash, so timing says nothing about it, and at 32 or more random characters it can't be
guessed. With the secret, a caller can only add school addresses to the waitlist (never approve, and never
make an existing account wait) and read the list, which is what the Sheet holds anyway. Keep it out of the
app and source control; the anon key is public by design.

## Edge Functions

`delete-account`: `POST` with the user's JWT and no body. `204` on success, after which the app signs
out. Leaves joined games (freeing the spots), deletes the auth user along with the games they host,
and keeps reports without the reporter.
