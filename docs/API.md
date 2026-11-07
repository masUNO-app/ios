# masUNO API contract

The boundary between the app and Supabase (SPEC §8.5), matched by the Swift protocols in
`MasUno/Data/` and the models in `MasUno/Models/`. A change to either side is one PR reviewed
by both coders. If this file and the spec disagree, this file wins.

**Status: frozen Fri Nov 6; sign-in amended the same day (SPEC N33).** Build the backend to this file. The
backend hasn't started, so there's nothing to migrate. The Swift side is built to this file (E5, B5) but hasn't
run against a real backend yet.

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
| Auth hook rejects the account, with message `email_not_allowed` | `.emailNotAllowed` |
| `ASWebAuthenticationSessionError.canceledLogin` (the person closes the web sheet) | None: back to Find your school, with no message |
| Callback says consent was denied or is required | `.schoolApprovalNeeded` (new) |
| Any other error from the web sheet or callback | `.signInFailed` (new) |
| `over_request_rate_limit` | `.tooManyAttempts` |
| `invalid_credentials` (review accounts) | `.invalidCredentials` |

OAuth failures come back in the callback URL's `error`, `error_code` and `error_description`, and
`auth.signInWithOAuth` throws them as `AuthError.pkceGrantCodeExchange`. B5 checks the exact text for a
hook rejection on `masuno-dev`. If admin consent is needed, Microsoft usually shows its own page in the
sheet, and closing it counts as a cancel, so `.schoolApprovalNeeded` only appears if Microsoft sends an
error back (B21 checks this).

## Reference data (readable by `anon`)

The version gate runs before sign-in, so these need a read policy for `anon`, not only `authenticated`.

| Table | Columns | Swift |
| --- | --- | --- |
| `app_config` | `key`, `value jsonb`; keys `min_supported_version`, `support_email`, `privacy_url` | `AppConfig` |
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

An append-only table the RPCs write to, not a view: `leave_game` deletes the `rsvps` row, and one
`material_change_at` can't tell a meet-up edit from a time change. System rows for group chat: `id`, `event_id`, `kind`, `actor_id?`, `actor_first_name?`,
`actor_last_initial?`, `actor_grad_year?`, `at`. Oldest first. Actor columns are null for a deleted
account or a blocked pair. `kind` is one of `created`, `joined`, `left`, `meet_point_updated`,
`time_or_place_changed`, `cancelled`.

### `my_profile` → `Profile`

Your own row, or none until `complete_profile` has run: `id`, `first_name`, `last_name`, `grad_year`,
`university_id`, `university_name`, `university_short_name`, `university_email_domain`, `center_lat`,
`center_lng` (→ `Profile.university`; the map opens here, so review accounts land on the demo campus),
`interests text[]`, `guidelines_accepted_at?`, `banned_at?`. `AuthService` uses the
last two to choose between `.needsGuidelines`, `.suspended` and `.signedIn`.

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

## Sign-in

1. Find your school reads `university_lookup`. `sso_provider` picks the provider and hint: `azure` →
   `.azure` with `domain_hint=<email_domain>`; `google` → `.google` with `hd=<email_domain>`.
2. School account, on supabase-swift v2 with its default PKCE flow:
   `auth.signInWithOAuth(provider: .azure, redirectTo: masuno://auth-callback, scopes: "openid email profile", queryParams: [(name: "domain_hint", value: <email_domain>)], configure: { $0.prefersEphemeralWebBrowserSession = true })`.
   The SDK opens `ASWebAuthenticationSession`, takes the callback scheme from `redirectTo`, finishes the exchange and
   returns the session. Don't call `start()` in `configure`; the SDK does. The app has no domain list of its own, and the school picked in the app
   isn't trusted: the auth hook checks the provider and the email on the server (SPEC §8.4). Set up profile
   fills in the name from `user_metadata`, editable (B21 confirms the keys).
3. Review account (only from **Use a review account**): `auth.signInWithPassword(email, password)`. Works only for
   `auth_allowlist` addresses. The app never calls `auth.signUp`, and the hook refuses any other address.
4. Next step from `my_profile`: no row → `.needsProfile` (You're verified comes first); `banned_at` set → `.suspended`;
   `guidelines_accepted_at` null → `.needsGuidelines`; otherwise `.signedIn`.

Review accounts: `auth_allowlist` has `email`, `note` and `university_id` (usually the demo campus), so
`complete_profile` can place them. They're either a Tec test account or a password account Emilio created
with the email already confirmed.

## Edge Functions

`delete-account`: `POST` with the user's JWT and no body. `204` on success, after which the app signs
out. Cancels upcoming hosted games, leaves joined games, keeps reports without the reporter, deletes
the auth user.
