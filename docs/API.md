# masUNO API contract

The boundary between the app and Supabase (SPEC §8.5), matched by the Swift protocols in
`MasUno/Data/` and the models in `MasUno/Models/`. A change to either side is one PR reviewed
by both coders. If this file and the spec disagree, this file wins.

**Status: draft for Ethan and Emilio to freeze Fri Nov 6, noon.** The choices that go beyond
the rev. 7 spec are listed under [Needs Emilio's OK](#needs-emilios-ok).

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
| `not_authenticated` | `.notAuthenticated` | No valid session. Any RPC except `sign_in_method`. |
| `suspended` | `.suspended` | `banned_at` is set. Any write RPC. The app shows the suspended screen. |
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

Client-only: `.offline` (no connection) and `.unknown(code)`.

### Auth errors

These come from Supabase Auth and the auth hook, not from RPCs. `AuthService` (B5) maps them.

| Source | `DomainError` |
| --- | --- |
| Auth hook rejects the address, with message `email_not_allowed` | `.emailNotAllowed` |
| Wrong code | `.codeInvalid` |
| Expired code | `.codeExpired` |
| `over_email_send_rate_limit`, `over_request_rate_limit` | `.tooManyAttempts` |
| `invalid_credentials` (review accounts) | `.invalidCredentials` |

Supabase may report wrong and expired codes with the same `otp_expired` error. B5 checks this on
`masuno-dev`; if they can't be told apart, both show the wrong-code message.

## Reference data (readable by `anon`)

The version gate runs before sign-in, so these need a read policy for `anon`, not only `authenticated`.

| Table | Columns | Swift |
| --- | --- | --- |
| `app_config` | `key`, `value jsonb`; keys `min_supported_version`, `support_email`, `privacy_url` | `AppConfig` |
| `activities` | `slug`, `kind`, `label_en`, `label_es`, `emoji`, `sort_order`, `postable`, `interest_selectable`, `active` | `Activity` |

`activities` is seeded with the slugs `basketball`, `tennis`, `soccer`, `volleyball`, `padel`,
which `Activity.builtIn` repeats as the offline fallback.

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

`event_id`, `user_id`, `first_name`, `last_initial`, `grad_year`, `role`, `joined_at`.
Excludes anyone in a blocked pair with the reader. `going_count` still counts them.
`fetchAttendees` orders host first, then by `joined_at`.

### `game_activity` → `GameActivityEntry`

System rows for group chat: `id`, `event_id`, `kind`, `actor_id?`, `actor_first_name?`,
`actor_last_initial?`, `actor_grad_year?`, `at`. Oldest first. Actor columns are null for a deleted
account or a blocked pair. `kind` is one of `created`, `joined`, `left`, `meet_point_updated`,
`time_or_place_changed`, `cancelled`.

### `my_profile` → `Profile`

Your own row, or none until `complete_profile` has run: `id`, `first_name`, `last_name`, `grad_year`,
`university_name`, `interests text[]`, `guidelines_accepted_at?`, `banned_at?`. `AuthService` uses the
last two to choose between `.needsGuidelines`, `.suspended` and `.signedIn`.

## RPCs

Game writes return the updated `game_cards` row, so the app never needs a second fetch.

| RPC | Returns | Errors |
| --- | --- | --- |
| `sign_in_method(p_email text)` | `text`: `otp` or `password`. Anonymous. | — |
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

## Sign-in

1. `sign_in_method(email)` comes first, because review accounts are Gmail aliases. `password` shows the
   password field. For `otp`, the app checks for `@tec.mx`, then sends the code.
2. Code: `auth.signInWithOTP(email)`, then `auth.verifyOTP(email, token, type: .email)`.
3. Password: `auth.signInWithPassword(email, password)`.
4. Next step from `my_profile`: no row → `.needsProfile`; `guidelines_accepted_at` null →
   `.needsGuidelines`; `banned_at` set → `.suspended`; otherwise `.signedIn`.

## Edge Functions

`delete-account`: `POST` with the user's JWT and no body. `204` on success, after which the app signs
out. Cancels upcoming hosted games, leaves joined games, keeps reports without the reporter, deletes
the auth user.

## Needs Emilio's OK

Choices that go beyond the rev. 7 spec. The Swift side and the mocks already assume them.

1. **`game_activity` can't be a view over `rsvps`.** `leave_game` deletes the row, so "left" rows would
   have nothing to read, and the single `material_change_at` can't tell a meet-up edit from a time
   change. Proposal: an append-only table written by the RPCs, exposed under the same name and columns.
2. **Blocked people need `my_blocks()`.** RLS hides `profiles` across a blocked pair, so Settings ›
   Blocked people couldn't otherwise show the names it needs for Undo.
3. **`create_game` returns `game_cards`**, not `uuid`, so every game write works the same way.
4. **New codes:** `not_authenticated` and `suspended` on every RPC that needs them, and `not_found` on
   `update_game`, `cancel_game` and `leave_game`. Rev. 7 didn't list a code for these cases.
5. **New `game_cards` columns:** `host_grad_year` and `sort_at`.
6. **`app_config` and `activities` are readable by `anon`**, for the version gate.
7. **Review accounts:** `auth_allowlist` has no way to attach an account to the demo campus, and
   `complete_profile` can't derive a university from a Gmail address. Your call how to solve it (for
   example a `university_id` column on the allowlist); the app doesn't depend on the answer.
