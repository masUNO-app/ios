# Notifications plan

How masUNO sends push notifications: what we send, how group chat gets the Messages-style look,
and what the backend and app need. It builds on SPEC §8.6–8.7 and the 1.0 items B13–B16 and E16.
Where it differs, this doc is the proposal; fold the agreed parts back into SPEC.

**Status (Nov 15):** built on `feature/notif-service`, and still switched off. `app_config.push_enabled`
ships false, the same way chat does. Saved games and spot alerts sync through `bookmarks`, and the
phone keeps a local copy so a relaunch works before the network answers.

**Owners (SPEC N21):** Emilio owns the backend and `NotificationService`. Ethan owns the screens
and the notification extension. Arianna draws the primer and Settings rows. Ricardo checks the
copy and the Spanish.

---

## 1. Decisions in short

1. **One outbox, many producers.** Every notification is a row in `notification_outbox`. Triggers
   on `game_activity`, `games`, `chat_messages` and `rsvps`, plus a few cron jobs, write the rows. One
   Edge Function, `send-push`, drains the outbox to APNs. Rules (preferences, blocks, quiet hours,
   daily caps) live in one SQL function, so every kind follows them the same way.
2. **APNs directly, no third-party push service.** Token auth with one `.p8` key, which works for
   both the sandbox and production. No new vendor and no new privacy disclosure.
3. **Group chat uses communication notifications.** A Notification Service Extension turns each
   chat push into an `INSendMessageIntent`. iOS then shows it like a Messages group: the game's
   badge as the group picture, the sender's initials avatar, "Maya C." over the message, and grouped
   per game (§3).
4. **"Near you" means your campus and your sports.** Your location never leaves the phone (SPEC
   §8.8), so the server can't know how far you are. Every game is on your campus, which is walking
   distance by design. A distance filter on the phone is a later option (§9).
5. **Text is written on the server, in the phone's language.** The device reports its language
   when it registers. English and Spanish templates live in `send-push`. This replaces B18's
   separate Spanish work.
6. **Ask permission in context.** Ask after the first join or hosted game (SPEC C11), and on the
   "We're checking your account" screen for people waiting for approval. Never ask at launch.
7. **One switch for everything.** `app_config.push_enabled`, like `chat_enabled`, plus one switch
   per kind, so a noisy kind can be turned off without a release.

---

## 2. What we send

### 2.1 The list

| # | Kind | Example (en) | To | Sent when | Timing | Setting | Level |
|---|---|---|---|---|---|---|---|
| 1 | `game_cancelled` | **Sunday pickup soccer was cancelled** · Sam cancelled it. Find another game? | Everyone going (not the host) | Host cancels | Right away | Always on | Time Sensitive |
| 2 | `game_changed` | **Sunday pickup soccer changed** · Now 7:30 PM at Estadio Borregos | Everyone going (not the host) | Time, place or meet-up edited | 10 seconds after the first pending edit, merged | Always on | Active |
| 3 | `reminder` | **Starts in 30 min** · Volleyball at the arena · Meet by the north bleachers | Everyone going, host too | 25–35 min before start | Cron, every 5 min | Game reminders | Time Sensitive |
| 4 | `host_update` | **Ricardo G. joined** · Sunday pickup soccer · 2 spots left | Host | Join or leave | Merged per game for 10 seconds ("Ricardo G. and Maya C. joined") | Updates on games you host | Active |
| 5 | `game_full` | **Your game is full** · 10 of 10 going for Sunday pickup soccer | Host | Last spot taken | Replaces 4 for that game | Updates on games you host | Active |
| 6 | `spot_open` | **A spot opened** · After-work hoops · Today 7:30 PM | People who saved it with "Notify me" | A full game frees a spot, with or without auto-repost | Right away | A spot opens up | Time Sensitive |
| 7 | `interest_match` | **New basketball game at Tec** · After-work hoops · Today 7:30 PM · room for 4 | People on that campus with that sport in their interests | Game created | 10 seconds after creation; at most 2 a day | Games that match your sports | Passive |
| 8 | `chat_message` | *(Messages style)* **Sunday pickup soccer** · Maya C.: I'll bring the ball | Everyone going, except the sender | New message | Right away, then a 10-second batching window ("3 new messages") | Group chat messages | Active |
| 9 | `signup_approved` | **You're in** · Set up your profile and find a game. | The person waiting | `approve_signup` | Right away | Always on (asked for while waiting) | Active |
| 10 | `winback` | **4 games at Tec this week** · 2 basketball. Room for one more? | Inactive people who opted in | Daily job | 5 PM campus time, Tue–Thu; at most 1 every 14 days | Ideas to play (opt-in) | Passive |
| 11 | `saved_soon` | **Still room in After-work hoops** · Starts in 2 h · room for 3 | People who saved a game they haven't joined | 2 h before start | Cron | A spot opens up | Passive |

Kinds 1–7 are SPEC §8.7, with `game_full` split out. Kinds 8–11 are new: chat (SPEC Appendix A
item 8), approval (it removes the "Check again" wait, N36), win-back, and a nudge for saved games
that still have room.

### 2.2 Rules every kind follows

Checked in `private.claim_notifications` at send time, not only when the row is written, since
things change while a row waits:

- **Never** to the person who caused it (the sender, the host who edited, the one who joined).
- **Never** across a block, either way, using `private.blocked_pair`. Both claim protocols rebuild
  chat sender names, message bodies, counts and other-member names from currently visible messages,
  and filter every actor in a host roster summary. A block made after enqueue still applies.
- **Membership:** chat, reminders and game changes/cancellations require a current RSVP. A removed
  player does not receive queued member-only content.
- **Never** to banned accounts, or about a cancelled game (except `game_cancelled`) or a game that
  has started (except `chat_message`, until the chat closes 24 h after the end).
- **Preferences:** a setting that's off drops the row.
- **Quiet hours:** 22:00–08:00 in the campus's `universities.timezone`. Passive and Active kinds wait
  until 08:00 and are dropped if they've expired by then. Time Sensitive kinds still go.
- **Caps:** `interest_match` 2 a day; `winback` 1 every 14 days, stopping after 3 unopened. Every
  kind except chat and Time Sensitive ones: at most 6 a day in total.
- **Expiry:** each row has `expires_at` (game kinds: the start time; chat: 24 h; win-back: 1 day).
  Expired rows are dropped, and APNs gets the same value as `apns-expiration`.
- **Still true?** `spot_open` checks there's still a spot and you aren't already in.
  `interest_match` checks the game isn't full.

### 2.3 Tapping and actions

| Kind | Tap opens | Actions (long press) |
|---|---|---|
| Game kinds (1–7, 11) | `masuno://game/<id>` → Event detail | `spot_open`, `interest_match`, `saved_soon`: **Count me in** (joins in the background; needs the phone unlocked). `reminder`: **Directions** (opens Maps) |
| `chat_message` | `masuno://game/<id>/chat` → Group chat | **Reply** (text input, sends in the background) · **Mark as read** |
| `signup_approved` | The app (onboarding continues) | — |
| `winback` | `masuno://map` (filtered to your sports) | — |

---

## 3. Group chat: communication notifications

### 3.1 What people see

iOS 15 and later show messages from messaging apps with the sender's picture instead of the app
icon. For a group, the title is the group's name and the picture is the group's, with the app icon
in the corner. These notifications group per conversation, appear in CarPlay and Siri announcements,
and work with Focus ("allow notifications from people"). For masUNO:

- **Group name:** the game's title ("Sunday pickup soccer"). One conversation per game.
- **Group picture:** the game's sport badge: the pin from the map (sport color, emoji) drawn as a
  circle. It's what people already recognize the game by.
- **Sender:** "Maya C." with her initials avatar in her color, the same `PersonToken` look and
  palette as everywhere in the app, so a message notification looks like the chat itself.
- **Body:** the message, or "3 new messages" when merged (§3.4).

There are no profile photos (SPEC: later), so every picture is drawn on the phone; nothing is
downloaded. If Arianna prefers it, the group picture can be the chat header's stack of up to
three avatars instead of the sport badge. Decide on a device (§11).

### 3.2 How it works

```
send-push ──APNs──▶ phone ──▶ Notification Service Extension (masUNONotifications)
   payload has            1. Read sender, game and sport from the payload.
   mutable-content: 1     2. Draw the sender's avatar and the sport badge (UIGraphicsImageRenderer).
                          3. Build INPerson (sender) and INSendMessageIntent (group = game).
                          4. Donate INInteraction(intent:), direction .incoming.
                          5. content.updating(from: intent) → hand back to iOS.
```

The extension has about 30 seconds and a small memory budget. Drawing two 120 pt images is well
inside both. If it fails or runs out of time, iOS shows the plain alert from the payload ("Sunday
pickup soccer" / "Maya C.: I'll bring the ball"), so nothing is lost.

Sketch (the extension's `didReceive`):

```swift
let sender = INPerson(
    personHandle: INPersonHandle(value: p.senderID.uuidString, type: .unknown),
    nameComponents: nil, displayName: p.senderName,               // "Maya C."
    image: INImage(imageData: AvatarRenderer.person(id: p.senderID, initials: p.senderInitials)),
    contactIdentifier: nil, customIdentifier: p.senderID.uuidString)
let me = INPerson(personHandle: INPersonHandle(value: shared.myID, type: .unknown),
    nameComponents: nil, displayName: nil, image: nil, contactIdentifier: nil,
    customIdentifier: shared.myID, isMe: true)
let intent = INSendMessageIntent(
    recipients: [me] + p.others,                                  // > 1 recipient makes it a group
    outgoingMessageType: .outgoingMessageText, content: p.body,
    speakableGroupName: INSpeakableString(spokenPhrase: p.gameTitle),
    conversationIdentifier: p.gameID.uuidString,
    serviceName: nil, sender: sender, attachments: nil)
intent.setImage(INImage(imageData: AvatarRenderer.sport(p.sport)), forParameterNamed: \.speakableGroupName)
let interaction = INInteraction(intent: intent, response: nil)
interaction.direction = .incoming
try await interaction.donate()
contentHandler(try request.content.updating(from: intent))
```

`p.others` is up to two other members (ID, name) from the payload, enough for iOS to treat it as
a group. `shared.myID` comes from the App Group (§6.2).

### 3.3 What it needs

- **Capability "Communication Notifications"** on `com.masuno.app`
  (`com.apple.developer.usernotifications.communication`), and `NSUserActivityTypes` =
  `[INSendMessageIntent]` in the app's Info.plist.
- **A Notification Service Extension target**, `masUNONotifications`
  (`com.masuno.app.NotificationService`), linking `Intents`.
- **An App Group**, `group.com.masuno.app`, on the app and the extension.
- The extension draws avatars with the same palette and initials rules as `PersonSummary.color`
  and `PersonToken`. Move those into a small `Shared/` folder compiled into both targets, with the
  colors as values instead of asset-catalog names, so they can't drift.

### 3.4 Volume and privacy

- **Throttle:** the first message in a game reaches each member right away. More messages to the
  same person within 10 seconds merge into one row ("Maya C. and Sam L. · 3 new messages") that
  goes out when the 10 seconds are up, with `apns-collapse-id = chat:<game>` so it replaces the
  earlier banner instead of stacking. Busy chats stay readable without one buzz per message.
- **Read already?** At send time, skip anyone whose `chat_reads.last_read_at` is after the
  message. They were in the chat.
- **Open chat:** while you're in a game's chat, the app suppresses its banners
  (`willPresent`, §6.5).
- **Mute a game:** "Mute notifications" in the chat's menu (`rsvps.chat_muted`). The Settings
  switch turns off all chat pushes.
- **Message text goes through Apple's push service**, like every messaging app that shows
  previews. iOS's own "Show previews" setting still applies. A later option: send no text, and let
  the extension fetch the message with the signed-in session from a shared keychain (§9).
- **Chat must be on:** nothing is sent while `app_config.chat_enabled` is false.

---

## 4. How it fits together

```
 producers (in the same transaction as the write)          jobs (pg_cron)
 ─────────────────────────────────────────────            ──────────────────────────────
 game_activity insert  → cancelled / changed / host /      every 5 min  → reminder, saved_soon
                          full / interest_match            daily 17:00  → winback
 games update, seat opens → spot_open                    daily        → purge old rows
 chat_messages insert  → chat_message
 approve_signup        → signup_approved
            │
            ▼
   private.enqueue_notification(...)   one row per person; merges into a pending row with the
            │                          same merge key; drops it if the setting is off
            ▼
   notification_outbox  (not_before, expires_at, merge_key, collapse_id)
            │
   every 10 s: private.drain_if_due() → if any row is due, net.http_post → Edge Function send-push
            ▼
   send-push: claim ≤ 100 rows (skip locked) → final rules (§2.2) → text in the device's language
              → APNs over HTTP/2, one request per device → mark sent / retry / drop dead tokens
            ▼
   iPhone: plain alert, or the extension rewrites chat (§3) → tap → masuno:// link → screen
```

Why the pieces:

- **Writing in the same transaction** means a notification exists only if the change does. A
  rolled-back join never pings the host.
- **A 10-second drain that only calls the function when something is due** keeps chat close to
  real time without calling the function 8,640 times a day for nothing. pg_cron supports
  second-level schedules on Supabase (check the version on both projects). If it doesn't, use a
  1-minute job plus a `net.http_post` "kick" from the chat trigger.
- **`for update skip locked` and a 10-minute lease** (`locked_at`) let two runs overlap without
  sending anything twice.

---

## 5. Backend (Emilio)

### 5.1 Tables

One migration, `2026112x_notifications.sql`. Sketch:

```sql
-- One row per phone. Keyed on the token: signing in as someone else on the same phone moves it.
-- user_id references auth.users, not profiles, so people waiting for approval can register (§2.1 #9).
create table private.device_tokens (
    token        text primary key,
    user_id      uuid not null references auth.users(id) on delete cascade,
    environment  text not null check (environment in ('sandbox', 'production')),
    locale       text not null default 'en',          -- the phone's language when it registered
    app_version  text not null,
    updated_at   timestamptz not null default now()
);
create index on private.device_tokens (user_id);

create table public.notification_prefs (
    user_id         uuid primary key references public.profiles(id) on delete cascade,
    interest_match  boolean not null default true,
    spot_open       boolean not null default true,
    reminders       boolean not null default true,
    hosting         boolean not null default true,
    chat            boolean not null default true,
    winback         boolean not null default false,   -- opt-in (App Review 4.5.4, §8)
    updated_at      timestamptz not null default now()
);

-- Synced Saved (B15). notify = "Notify me if a spot opens".
create table public.bookmarks (
    event_id    uuid not null references public.games(id) on delete cascade,
    user_id     uuid not null references public.profiles(id) on delete cascade,
    notify      boolean not null default false,
    created_at  timestamptz not null default now(),
    primary key (event_id, user_id)
);

alter table public.rsvps add column chat_muted boolean not null default false;
alter table public.profiles add column last_seen_at timestamptz;   -- win-back; set by register_device

create table private.notification_outbox (
    id           bigint generated always as identity primary key,
    user_id      uuid not null references auth.users(id) on delete cascade,
    kind         text not null,
    event_id     uuid references public.games(id) on delete cascade,
    payload      jsonb not null default '{}',   -- names, counts, message IDs: what the text needs
    merge_key    text,                          -- pending rows with the same key merge (chat:<game>:<user>)
    collapse_id  text,                          -- apns-collapse-id: replaces the banner on the phone
    not_before   timestamptz not null default now(),
    expires_at   timestamptz not null,
    created_at   timestamptz not null default now(),
    locked_at    timestamptz,
    sent_at      timestamptz,
    dropped      text,                          -- why it wasn't sent: 'pref', 'blocked', 'cap', 'expired', …
    attempts     integer not null default 0,
    error        text
);
create unique index on private.notification_outbox (merge_key) where sent_at is null and dropped is null;
create index on private.notification_outbox (not_before) where sent_at is null and dropped is null;
create index on private.notification_outbox (user_id, kind, sent_at);   -- caps
```

`device_tokens` and the outbox stay in `private`: no client access. `notification_prefs` and
`bookmarks` are readable for your own rows only, and written through RPCs.

### 5.2 RPCs (`docs/API.md`)

| RPC | Purpose |
|---|---|
| `register_device(p_token, p_environment, p_locale, p_app_version)` | Upsert the token for `auth.uid()`; set `profiles.last_seen_at`. Allowed while waiting for approval. Called on every launch and foreground, at most once an hour |
| `unregister_device(p_token)` | Sign out: delete the row, so the next person on this phone doesn't get your pushes |
| `set_notification_prefs(...)` | Settings switches. Returns the row |
| `set_bookmark(p_game_id, p_on)` / `set_spot_alert(p_game_id, p_on)` | Synced Saved and "Notify me" (B15). Both return the `game_cards` row, with `is_bookmarked` and `spot_alert` added to the view. `set_winback` changes only the tips flag |
| `import_bookmarks(p_ids uuid[], p_alert_ids uuid[])` | One-time upload of the 0.x local Saved list on the first 1.0 launch |
| `set_chat_muted(p_game_id, p_muted)` | "Mute notifications" in a chat |
| `notification_opened(p_outbox_id)` | Tap tracking for the demo-day numbers (B17): opened rate per kind. No content |

### 5.3 Producers

All of them call one function, `private.enqueue_notification(user, kind, event, payload, merge_key,
collapse_id, not_before, expires_at)`. It drops the row if the setting is off; otherwise it merges
into a pending row with the same `merge_key` (adding a name, bumping a count) or inserts.

| Source | Kind | Notes |
|---|---|---|
| `game_activity` insert, `cancelled` | `game_cancelled` | Also drops pending rows for that game (reminder, changed, interest, spot, saved_soon) |
| `game_activity` insert, `time_or_place_changed` / `meet_point_updated` | `game_changed` | `not_before = now() + 10 seconds`, merge key `changed:<game>:<user>`: several edits make one push with the final values, read at send time |
| `game_activity` insert, `joined` / `left` | `host_update` | Merge key `host:<game>`, 10 seconds; one latest action per participant ID. If the join filled the game: `game_full` instead |
| `game_activity` insert, `created` | `interest_match` | Campus members with the sport in `interests`, minus the host and blocked pairs. `not_before = now() + 10 seconds`, so a game cancelled or edited right away doesn't go out. The cap is checked at send time |
| `games` update where a full game gains a free seat | `spot_open` | `bookmarks.notify` holders who aren't going, whether or not auto-repost bumps the pin. Clears their `notify` once sent: one alert per "Notify me" |
| `chat_messages` insert | `chat_message` | Members except the sender, not muted, not blocked. Merge key `chat:<game>:<user>`, `not_before` now for the first, +10 seconds after that (§3.4) |
| `private.approve_signup` | `signup_approved` | To every token of that auth user |
| cron, every 5 min | `reminder`, `saved_soon` | Games starting in 25–35 min (2 h for saved). Dedupe key includes `starts_at`, so a moved game reminds again at its new time |
| cron, daily | `winback` | `last_seen_at` over 10 days ago, opted in, campus has 2 or more open games in the next 3 days (in their sports, if any). Sent 17:00 campus time, Tue–Thu |

Triggers never fail the write. Like the Realtime pings, a failure raises a warning and returns
(`exception when others`).

Host summaries store `roster_changes` keyed by participant UUID, with each person's latest name
and `joined`/`left` action. New actions replace that person's earlier action instead of appending
names; two different people sharing a display name stay distinct. `joined` and `left` arrays are
also derived for sender compatibility. A departure invalidates any still-pending `game_full`
alert. The sender uses the current game context for the number of available spots.

Migration `20261118000000_reconcile_host_notification_roster.sql` repairs pending legacy host
summaries from their activity window and current RSVP membership. If a repaired row is already
claimed, its claim identity is preserved and a corrected resend is armed. Already-delivered
notifications cannot be rewritten by this queue repair.

### 5.4 `send-push` (Edge Function)

- **Claim:** service-role RPC `public.claim_notifications_v2(100)` applies §2.2 and returns the due rows that pass, each
  with its tokens and opaque `claim_token`. Completion/release must return that token; stale
  workers cannot change a newer attempt or delete its device tokens. Rows that fail get `dropped = '<reason>'`.
- **Text:** a TypeScript table of templates per kind and language (`en`, `es`), filled from the
  payload. Names are always "First L.".
- **APNs:** `POST https://api.push.apple.com/3/device/<token>` (`api.sandbox.push.apple.com` for
  `sandbox`), with headers `apns-topic: com.masuno.app`, `apns-push-type: alert`, `apns-priority`
  (10, or 5 for Passive kinds), `apns-expiration`, `apns-collapse-id`.
- **Token auth:** an ES256 JWT signed with the `.p8` key (`kid` = key ID, `iss` = team ID). Apple
  refuses a new token more than once every 20 minutes, and the function runs every few seconds.
  So keep the JWT in a private table, and only sign a new one when the stored one is 50 minutes old.
- **HTTP/2:** APNs only speaks HTTP/2. Deno's `fetch` negotiates it with ALPN; that's the first
  thing the 1-hour spike checks (§10, step 1). Fallback: `node:http2` in Deno.
- **Budgets:** at most 8 actual APNs requests across all rows/devices; each request and its body
  share a 5-second deadline. Stop starting work after a 25-second batch budget; unattempted
  devices produce retry results. SQL claims retain the ten-minute recovery lease.
- **Partial success:** a row is sent when at least one device accepts it, preserving the existing
  policy. Other transient device failures are not separately retried after row success.
- **Results:** `200` → `sent_at`. `410` or `400 BadDeviceToken` → delete the token. `429` / `5xx` →
  `attempts + 1` and `not_before = now() + 2^attempts min`, up to 3 attempts. Then `error`.
- **Secrets** (Supabase, never in the repo): `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`. The cron
  job calls the function with the service-role key from Vault, the same way the alerts read their
  webhook.

### 5.5 Payloads

Plain game kind:

```json
{
  "aps": {
    "alert": { "title": "A spot opened", "body": "After-work hoops · Today 7:30 PM" },
    "sound": "default", "thread-id": "game:6f1c…", "category": "SPOT_OPEN",
    "interruption-level": "time-sensitive", "relevance-score": 0.9,
    "target-content-id": "game:6f1c…"
  },
  "kind": "spot_open", "game_id": "6f1c…", "outbox_id": 4812
}
```

Chat (the extension rewrites it, §3):

```json
{
  "aps": {
    "alert": { "title": "Sunday pickup soccer", "body": "Maya C.: I'll bring the ball" },
    "sound": "default", "thread-id": "chat:6f1c…", "category": "CHAT",
    "mutable-content": 1
  },
  "kind": "chat_message", "game_id": "6f1c…", "outbox_id": 4813,
  "game": { "title": "Sunday pickup soccer", "sport": "soccer" },
  "sender": { "id": "a21b…", "name": "Maya C.", "initials": "MC" },
  "others": [{ "id": "c9d0…", "name": "Sam L." }, { "id": "e44f…", "name": "Nina P." }],
  "body": "I'll bring the ball", "count": 1
}
```

Keep payloads under APNs's 4 KB limit: chat bodies are at most 1,000 characters, and `others` holds
at most two people.

### 5.6 Housekeeping

- **Cron, daily:** delete outbox rows older than 30 days, sent or dropped. Delete tokens not
  refreshed in 90 days.
- **Account deletion:** tokens, preferences, bookmarks and outbox rows cascade.
  `delete_my_account_data` needs no change, but its pgTAP test should check them.
- **Switches:** `app_config.push_enabled` (off: claim nothing) and `app_config.push_kinds_off`
  (a list of kinds to drop). The dashboard checklist turns them on per project, like chat.

---

## 6. App (Ethan, with Emilio on `NotificationService`)

### 6.1 Project (`project.yml`)

- **App target:** an entitlements file with `aps-environment` (development for Debug, production for
  Release), Communication Notifications, Time Sensitive Notifications and the App Group. Add
  `NSUserActivityTypes: [INSendMessageIntent]`. No `remote-notification` background mode is needed:
  every push is a visible alert.
- **New target `masUNONotifications`:** type `app-extension`, the service-extension principal class,
  the App Group entitlement, embedded in the app, `TARGETED_DEVICE_FAMILY: "1"`, the same team and
  deployment target. Sources: `masUNONotifications/` plus `Shared/`.
- **`Shared/`**, compiled into both: `NotificationPayload` (Codable, the keys in §5.5),
  `AvatarRenderer` (initials avatar and sport badge with `UIGraphicsImageRenderer`), `AppGroupStore`
  (my ID, the chat on screen).
- Regenerate with `xcodegen generate`. The project isn't checked in, so the targets and entitlements live only in `project.yml`.

### 6.2 `NotificationService` (B16)

An `@Observable` service in `MasUno/Services`, created in `AppServices`, with a protocol so mocks work:

- `authorizationStatus`, refreshed on foreground. Settings shows "Notifications are off in iOS
  Settings · Open Settings" when it's `.denied`.
- `requestPermission()` → `requestAuthorization([.alert, .sound, .badge])`, then
  `UIApplication.shared.registerForRemoteNotifications()`.
- **Device token:** `MasUnoApp` gets a `@UIApplicationDelegateAdaptor`.
  `didRegisterForRemoteNotificationsWithDeviceToken` hands the hex token to the service, which calls
  `register_device` (environment from the build configuration, locale from
  `Locale.preferredLanguages`). It registers again on every launch, since tokens can change.
- **Sign out:** `unregister_device`. **Sign in:** register again.
- **App Group:** write `myID` on sign-in, and clear it on sign-out. Write `openChatID` while a chat is
  on screen.
- **Categories:** registered at launch: `CHAT` (Reply with text input, Mark as read), `SPOT_OPEN`,
  `INTEREST` and `SAVED_SOON` (Count me in, which needs the phone unlocked), `REMINDER` (Directions).

### 6.3 `NotificationRepository` (Data)

Next to the other protocols in `Repositories.swift`, with Live and Mock versions:
`registerDevice`, `unregisterDevice`, `fetchPrefs`, `setPrefs`, `setChatMuted`, `markOpened`.
Synced Saved goes on `GameRepository`: `setBookmark`, `setSpotAlert`, `importBookmarks`.
`GameStore` keeps its local `savedIDs` / `spotAlertIDs` as a cache and reads `is_bookmarked` /
`spot_alert` from `game_cards`.

### 6.4 Asking

- **Primer** (SPEC §7.5 step 4, Arianna's frame): after the first successful join or create, a sheet. "Know
  when your game changes or a spot opens", with **Turn on notifications** and **Not now**. "Not now"
  asks again after the next join, once only. It never shows if iOS has already been asked.
- **Waiting for approval:** "Want a heads-up when you're in?" under "We're checking your account".
- **Win-back opt-in:** a separate switch in the primer, off by default: "Tips when games match your
  sports". Apple asks for explicit opt-in for anything promotional (§8).

### 6.5 On the phone

- **Tapping** (`didReceive`): read `game_id` / `kind`, call `notification_opened`, and route through
  `AppViewModel.handle(_:)`. Add `masuno://game/<id>/chat` (a `.chat` route on top of `.game`) and
  `masuno://map`. A tap on a cold launch keeps the link until the session reaches `.signedIn`.
- **Actions:** Reply → `send_message` with a new `client_id`. Mark as read → `mark_chat_read`. Count
  me in → `join_game`; on `full`, post a local notification "Someone beat you to it". All run in
  the background with the stored Supabase session.
- **In the app** (`willPresent`): hide a chat banner for the chat on screen, and hide game kinds for
  the game on screen. Otherwise show it as a banner. `GameStore` refreshes that game, so the screen
  is current when you get there.
- **Clean-up:** opening a game or chat removes its delivered notifications (by `thread-id`).
- **Badge:** off in 1.0, so the server sends no `badge`. If it's wanted later, the count is the
  number of games with unread chat (`chat_unread`).

### 6.6 Settings (E16)

A "Notifications" section above Privacy & safety, in SPEC §7.6.7's order plus the new rows:
Games that match your sports · A spot opens up · Game reminders · Updates on games you host ·
Group chat messages · Tips to play (off). Cancellations, changes and "You're in" are always on;
a footnote says so.

---

## 7. Copy

Titles name the game; bodies carry what changed. No exclamation marks, as in the rest of the app.
Spanish is a first draft for Ricardo.

| Kind | English | Spanish |
|---|---|---|
| `game_cancelled` | **{game} was cancelled** · {host} cancelled it. Find another game? | **Se canceló {game}** · {host} lo canceló. ¿Buscas otro partido? |
| `game_changed` | **{game} changed** · Now {time} at {place} | **{game} cambió** · Ahora {time} en {place} |
| `reminder` | **Starts in 30 min** · {game} · {meet_point or place} | **Empieza en 30 min** · {game} · {meet_point or place} |
| `host_update` | **{name} joined** · {game} · {n} spots left | **{name} se unió** · {game} · quedan {n} lugares |
| `game_full` | **Your game is full** · {n} of {n} going for {game} | **Tu partido está lleno** · {n} de {n} van a {game} |
| `spot_open` | **A spot opened** · {game} · {when} | **Se abrió un lugar** · {game} · {when} |
| `interest_match` | **New {sport} game at {campus}** · {game} · {when} · room for {n} | **Nuevo partido de {sport} en {campus}** · {game} · {when} · hay lugar para {n} |
| `chat_message` | **{game}** · {name}: {body} | **{game}** · {name}: {body} |
| `signup_approved` | **You're in** · Set up your profile and find a game. | **Ya estás dentro** · Completa tu perfil y encuentra un partido. |
| `winback` | **{n} games at {campus} this week** · {k} {sport}. Room for one more? | **{n} partidos en {campus} esta semana** · {k} de {sport}. ¿Hay lugar para uno más? |
| `saved_soon` | **Still room in {game}** · Starts in 2 h · room for {n} | **Aún hay lugar en {game}** · Empieza en 2 h · hay lugar para {n} |

Times use the campus's time zone and the device's 12/24-hour style as reported at registration.

---

## 8. Privacy and App Review

- **Nothing new leaves the phone except the token.** Location stays on the phone. The privacy page
  already lists "(1.0) a notification token" (SPEC §10).
- **What passes through Apple:** first name and last initial, game titles and times, and chat text
  (§3.4). It's the same as what members see in the app.
- **Guideline 4.5.4:** notifications can't be required, and promotional ones need explicit opt-in
  with a way out. Everything here is about games you're in or chose to follow, except `winback`, so
  `winback` is off until you turn it on, in words that say what it is. Nothing in the app needs
  notifications to work.
- **App Privacy labels:** a device ID used for app functionality (the token). Not linked to
  tracking.
- **Review notes:** say how to see a push. With the review account, host a game starting in 35
  minutes; its reminder arrives within 5 minutes.

---

## 9. Later

- **Distance on the phone:** with Apple's notification filtering entitlement
  (`com.apple.developer.usernotifications.filtering`, by request), the extension could drop
  `interest_match` for games more than a walk away, using a location the app keeps in the App Group.
  Only worth it if campuses get big.
- **Private chat previews:** send no message text. The extension fetches it with a session kept in a
  shared keychain group, so the text never touches APNs.
- **Pictures:** attach a small image of the court with the open spot to `spot_open` and
  `interest_match` ("room for one more"), drawn in the extension with `ImageRenderer`.
- **Live Activity on game day:** from 1 h before start, the lock screen shows the countdown, spots
  left and the meet-up spot, updated by push.
- **Post-game:** "How was it? Play again with the same group?" to the host the next day, using the
  existing Play again.
- **Weekly digest** instead of `winback` for active people, if they ask for it.
- **Badge** for unread chats (§6.5).

---

## 10. Order of work

Fits SPEC's 1.0 calendar (beta Tue Dec 1, submit Tue Dec 8). SPEC budgets about 19 h (C6); this plan
is about 40 h. The cut line below keeps the beta on time.

| Step | What | Who | Est. | By |
|---|---|---|---|---|
| 0 | APNs key (`.p8`, Admin role, K6) into the password manager and Supabase secrets. Capabilities on `com.masuno.app`: Push, Communication, Time Sensitive, App Group. Bundle ID for the extension | Ethan + Admin | 1 h | Nov 20 |
| 1 | **Spike:** a 20-line `send-push` that sends one push to a dev build over HTTP/2 with token auth. Proves Deno and APNs before anything else is built | Emilio | 2 h | Nov 21 |
| 2 | Migration: tables, RPCs, `enqueue`, `claim`, drain job, switches; pgTAP for every producer (§5.3) and every rule (§2.2) | Emilio | 10 h | Nov 26 |
| 3 | `send-push` in full: templates en/es, JWT reuse, retries, token cleanup; Deno tests for the payloads | Emilio | 5 h | Nov 27 |
| 4 | App: delegate, `NotificationService`, `NotificationRepository` (+ mock), register/unregister, tap routing, categories, `willPresent` | Emilio + Ethan | 4 h | Nov 27 |
| 5 | Synced Saved and "Notify me" (B15), with the one-time import | Ethan | 2 h | Nov 28 |
| 6 | Screens: primer, Settings section, approval opt-in, Mute in chat (E16) | Ethan | 4 h | Nov 29 |
| 7 | **Beta cut:** kinds 1–7 and 9 on dev, then prod, then TestFlight | Both | — | **Dec 1** |
| 8 | Extension `masUNONotifications`, `Shared/` renderer, communication chat (kind 8), Reply action | Ethan | 6 h | Dec 4 |
| 9 | Chat producer and throttle; turn on chat push on prod | Emilio | 2 h | Dec 4 |
| 10 | QA pass (`docs/QA.md`, new §12), App Review notes, privacy labels | Both | 3 h | Dec 7 |
| 11 | After launch: `winback` and `saved_soon` (kinds 10–11), §9 items | — | 3 h + | Jan |

If time runs short, steps 8–9 (chat push) move to January, as SPEC had it. The rest of 1.0 doesn't
depend on them.

### Testing

- **Simulator:** `xcrun simctl push <udid> com.masuno.app masUNONotifications/Samples/chat.apns`
  delivers a payload without APNs. Keep one sample per kind next to the extension. Check that the
  simulator runs the extension for simulated pushes; if it doesn't, use a device.
- **pgTAP:** each producer writes the right rows for the right people; each rule in §2.2 drops what
  it should (block, mute, preference, quiet hours, cap, expired, full again, cancelled).
- **Device:** TestFlight against prod with two accounts, one round per kind. The two-phone setup from
  the last-spot race (QA §4) covers `spot_open` and `host_update`.
- **Communication look:** a real device, in light and dark, with Focus on and off, and with
  "Show previews: never".

---

## 11. Open questions

1. **Chat push in 1.0 or January?** The plan builds it after the beta cut. It's the most visible
   kind, and the most work.
2. **Group picture:** sport badge or avatar stack (§3.1)? Arianna, on a device.
3. **Win-back at all for launch?** It's off by default and needs its own opt-in. Wait for real
   numbers in January?
4. **Quiet hours:** fixed 22:00–08:00, or a Settings choice?
5. **Reminder time:** 30 min (SPEC), or let people pick 15/30/60?
6. **Host updates:** every join, or only milestones (first player, half full, full)? Every join
   merged per 5 min is the proposal.

---

## Sources

- Apple: [Implementing communication notifications](https://developer.apple.com/documentation/usernotifications/implementing-communication-notifications) · [INSendMessageIntent](https://developer.apple.com/documentation/intents/insendmessageintent) · [UNNotificationServiceExtension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension) · [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns) · [Establishing a token-based connection to APNs](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns) · [Generating a remote notification](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification) · [Testing notifications using the Push Notification Console / simctl](https://developer.apple.com/documentation/usernotifications/testing-notifications-using-the-push-notification-console) · [App Review Guidelines 4.5.4](https://developer.apple.com/app-store/review/guidelines/#push-notifications) · WWDC21 "Send communication and Time Sensitive notifications"
- Supabase: [Cron](https://supabase.com/docs/guides/cron) · [pg_net](https://supabase.com/docs/guides/database/extensions/pg_net) · [Edge Functions](https://supabase.com/docs/guides/functions) · [Vault](https://supabase.com/docs/guides/database/vault)
- masUNO: SPEC §7.6.7, §7.6.10, §8.3–8.8, Appendix A; `docs/API.md`; `supabase/migrations/` (`game_activity`, group chat, games Realtime)
