# Supabase backend

Migration-first: deploy the schema before pointing a build at it. Never edit a migration that's
already applied to a shared project; add a new timestamped one. The sync workflow deploys both
projects from same-repository PRs and from `main`, as requested for this project.

| Migration | What it adds |
| --- | --- |
| `20261107000000_initial_backend` | Tables, RLS, views, RPCs, auth hook, sports and app config |
| `20261109000000_review_fixes` | PR #12 review fixes: grants, campus checks, account deletion, `game_activity` view |
| `20261109000100_text_filter` | English + Spanish word filter in `private.clean_text` |
| `20261109000200_campuses_and_demo` | Tec, the hidden demo campus and its daily refresh, allowlisted review/QA addresses |
| `20261109000300_report_alerts` | Report alerts to the team chat |
| `20261111000000_password_signup_approval` | Sign-up with a school email and a password, approved by hand (N36): `private.signup_requests`, the Discord alert, `approve_signup` / `reject_signup`, `signup_status()`, `pending_approval` |
| `20261110000000_group_chat` | Group chat messaging (0.6): messages, unread counts, chat RPCs, the Realtime channel, 30-day cleanup. Ships switched off |
| `20261112000000_games_realtime` | Live game lists (1.0 refresh): a Realtime ping on `campus:<id>:games` naming the games or spots that changed, so open phones on that campus re-read just those |
| `20261113000000_guest_games` | Guest browsing (1.0, R7-15): `guest_games(p_university)`, a campus's open games without names, notes or meet-up spots, the only game read `anon` has |
| `20261114000000_invites_and_beta` | Invite-only with a waitlist and the beta tester badge (1.0, N37): `private.invites`, 3 codes per member, `my_invites()`, `redeem_invite(p_code)`, `waitlist_position()`, `private.grant_invites`, the invite FYI alert, `mark_beta_tester()` and `is_beta_tester` on `my_profile` and `game_attendees` |
| `20261115000000_waitlist_sync` | One waitlist with the website (N38): `signup_requests.source`, `waitlist_join` and `waitlist_export` for the website's Apps Script (anon, secret-checked), the push to the Sheet on every change, website joins in `waitlist_position()`, and the approval alert when a website email creates its account |

| `20261116000000_notifications` | Push notifications: device tokens, preferences, synced bookmarks, the outbox, producers, claim and cron. Ships switched off |
| `20261119000000_security_fixes` | Security review fixes: RSVPs, `has_blocked_attendee` and `join_game` no longer reveal a blocker's games; banned accounts read nothing; allowlisted password sign-ups wait for approval; sign-up alerts mask emails; device tokens bound to their install; signed-out callers limited to `guest_games` and the waitlist RPCs |
| `20261122000000_notification_order_and_latency` | Ordered v2 claims and APNs sends per phone, ten-second batching, five/ten-second retries |
| `20261120000000_chat_push_blocks` | Chat pushes no longer name a member who's in a blocked pair with the recipient (`private.chat_others`) |
| `20261121000000_block_privacy` | Host/player blocks remove active RSVPs in either direction, old block pairs are reconciled, activity RLS hides blocked actors, and both notification claim protocols recheck all queued identities and current membership |
| `20261123000000_chat_mentions` | Group chat @mentions: `chat_messages.mentions`, `send_message(…, p_mentions)` (old signature replaced, defaulted), `mentions` on `game_messages`, and the `chat_mention` push, which ignores the chat switch, mute and quiet hours but not blocks, membership, `chat_enabled` or reads (NOTIF §3.5) |
| `20261124000000_delete_signup_request` | Deleting an account also deletes its `private.signup_requests` row, so the email doesn't outlive the account; the Sheet hears 'removed' |

## Local setup

1. Install the Supabase CLI and Docker, then run `supabase start`.
2. `supabase db reset` applies the migrations and `seed.sql` (Tec test hosts and games).
3. To sign in locally, create `official.masuno.app+local1@gmail.com` in Studio (Authentication → Add user, auto confirm on). The hook lets it in because `seed.sql` allowlists it.
4. `supabase test db` runs the pgTAP tests in `tests/database` (auth hook, game rules, RLS and grants, blocks, bans, reports, account deletion, group chat and mentions, invites and the beta badge, the website waitlist sync). CI runs the same on every PR that touches `supabase/` (`.github/workflows/database.yml`). The two-phone last-spot race stays a manual check in `docs/QA.md`.

### Notification test tooling

Use Node 26, matching CI. Run `npm ci --ignore-scripts --prefix supabase/functions`, then
`npm --prefix supabase/functions run check` and `npm --prefix supabase/functions test`.
The scoped TypeScript project supplies Node types for the tests and shared helpers, including
their `node:` imports. Deno Edge entrypoints remain checked separately with
`deno check --no-lock supabase/functions/send-push/index.ts`.

## Automatic hosted sync

[Sync Supabase](../.github/workflows/backend-sync.yml) replaces the old keep-awake job.
Database/pgTAP/concurrency tests and Edge Function checks run first, then it applies pending
migrations and deploys all local Edge Functions:

- **masuno-dev** on every PR (opened, pushed to, reopened), daily at 15:00 UTC from `main`, and on
  manual runs. Try database changes there from any branch.
- **masuno-prod** only when a PR is **merged into `main` or `path-to-1.0`**, after dev succeeds, from
  the merged commit. Pushing to a branch or a PR, including the open path-to-1.0 → main PR, never
  touches prod. To deploy prod by hand, run the workflow from `main` or `path-to-1.0` with
  "Also deploy masuno-prod" ticked.
- The daily run also reads prod's migration history, without changing it, so prod doesn't pause.

PRs from forks run validation only because GitHub does not expose deployment credentials to them.

Repository configuration (Settings → Secrets and variables → Actions):

- Secret `SUPABASE_ACCESS_TOKEN`: a Supabase deployment token with access to both projects,
  including database migration and Edge Function deployment permissions. Store it directly in
  GitHub; never commit it or put it in a workflow log.
- Variable `DEV_SUPABASE_PROJECT_REF`: `glpzvcddfezmwnkpfiml`.
- Variable `PROD_SUPABASE_PROJECT_REF`: `lfgmjurmiyhzfruegeji`.

The workflow serializes runs and stops production deployment if dev fails. It previews migration
history before applying it and never resets the databases, changes recorded migration history,
loads seed data, or overwrites hosted Auth/Vault settings. Existing APNs and webhook secrets stay
in Supabase. Since PRs deploy to the shared projects, keep applied migrations in subsequent PRs
and merge them promptly: a later checkout missing an already-applied migration fails on history
drift and requires restoring that migration file, rather than an automatic history repair.

## Hosted project checklist (masuno-dev, then masuno-prod)

Migrations don't carry dashboard settings, so do these on each project (B2, B12):

1. `supabase link --project-ref <ref>`, then `supabase migration list --remote` and
   `supabase db push --remote --dry-run`. Review the pending migrations, apply them with
   `supabase db push --remote`, then `supabase functions deploy delete-account`.
   CLI v3 defaults database commands to the local stack; `--remote` explicitly selects the linked project.
   Also `supabase functions deploy send-push`. Set secrets `APNS_KEY_P8`, `APNS_KEY_ID` and `APNS_TEAM_ID`
   (never commit them). In the SQL editor:
   `select vault.create_secret('<service-role-key>', 'service_role_key');` (the legacy `service_role` JWT,
   exactly the function's `SUPABASE_SERVICE_ROLE_KEY`: send-push compares the two and refuses anything else) and
   `select vault.create_secret('https://<ref>.supabase.co/functions/v1/send-push', 'send_push_url');`.
   Leave `push_enabled` false until a phone has registered and `docs/QA.md` §12 passes, then
   `update public.app_config set value = 'true' where key = 'push_enabled';`.
2. **Auth → Hooks:** register `public.before_user_created` as the **Before User Created** hook.
3. **Auth → Providers → Email:** on, with **Confirm email off** and sign-ups allowed, and **Minimum password
   length 8** (the app checks the same; `config.toml` only sets it locally). The app's Create account
   needs a session straight back from `signUp`; approval by hand replaces the confirmation email (N36).
   Sign-up alerts go to the report alerts' webhook (step 6) unless you add a separate one:
   `select vault.create_secret('<discord-webhook-url>', 'signup_alert_webhook_url');`.
   *School SSO, unused until a school approves it:* **Auth → Providers → Azure:** client ID and secret from the Entra app; Azure Tenant URL `https://login.microsoftonline.com/organizations` until Tec's tenant is confirmed (O4), then lock it to Tec before real students sign in on prod. Never `common`.
4. **Auth → URL Configuration:** add `masuno://auth-callback` to Redirect URLs.
5. **Auth → Users:** create the three allowlisted password accounts with "Auto confirm" on: `official.masuno.app+review1@gmail.com`, `+review2`, `+qa1`. Passwords go in the shared password manager.
   Accounts made here skip the sign-up hook, so they're in straight away. The addresses are public in a
   migration, so anyone signing up with one from the app waits for approval: reject any such request you
   didn't make.
   App Review often tests Delete account. If a review account is deleted, create it again here the same
   way before the next submission, and check it still lands on the demo campus.
6. **Report alerts (Discord) — set up on masuno-dev and masuno-prod (Nov 11).** On a new project,
   create a Discord channel webhook (Channel settings → Integrations → Webhooks → New Webhook),
   then in the SQL editor run
   `select vault.create_secret('<discord-webhook-url>', 'report_alert_webhook_url');` and
   `select vault.create_secret('https://supabase.com/dashboard/project/<ref>/editor', 'report_alert_dashboard_url');`.
   File a test report and confirm the alert arrives within a minute. Without the first secret,
   reports still save and Postgres logs a warning.
7. Check **Integrations → Cron** shows `refresh-demo-campus` (daily, 00:15 Monterrey) and `purge-old-chat` (daily, 00:45).
8. **Group chat (0.6).** `db push` leaves it off. Check **Realtime → Policies** lists "game members receive chat
   broadcasts" on `realtime.messages`; if the push logged "realtime.messages is missing", open Realtime once in the
   dashboard and run that `create policy` block from the migration by hand. Then turn chat on with
   `update public.app_config set value = 'true' where key = 'chat_enabled';`, run `docs/QA.md` §8 with two phones, and
   set it back to `'false'` if anything fails. The app reads the switch at launch. 0.5 ignores it and keeps the
   read-only chat, so people on 0.5 don't see messages from people on 0.6.
9. **Website waitlist sync (N38).** In the SQL editor, make one random secret of 32 or more characters
   (for example `select encode(extensions.gen_random_bytes(32), 'hex');`) and store it with the Apps
   Script's web app URL:
   `select vault.create_secret('<random 32+ chars>', 'waitlist_sync_secret');` and
   `select vault.create_secret('https://script.google.com/macros/s/<deployment id>/exec', 'waitlist_sync_url');`.
   Give the same secret to whoever deploys the website's Apps Script (Script Property `WAITLIST_SYNC_SECRET`,
   with `SUPABASE_URL` and `SUPABASE_ANON_KEY`), through the password manager, never in chat or a repo.
   Use the production project for the live website; dev needs a separate Sheet and deployment so its
   test accounts never enter the production waitlist. In the website repo's updated `apps-script/Code.gs`,
   run `checkSync()` to validate the properties without creating a signup, then `setupSync()` to add
   headers, install the hourly trigger and reconcile existing rows. Approve the Google permissions.
   Publish a new version of the existing Apps Script deployment to keep its `/exec` URL unchanged.
   Join on the website with a school email and confirm the row appears in `private.signup_requests` with
   `source = 'website'`, and that the Sheet's "App status" fills in within a minute. Without the secrets,
   `waitlist_join` and `waitlist_export` refuse every call, nothing is pushed, and Postgres logs a warning on
   each change. To change the secret, update it in Vault (`select vault.update_secret(id, '<new>') from
   vault.secrets where name = 'waitlist_sync_secret';`) and in the Apps Script together.
10. **Prod only:** add GitHub repository secrets `PROD_SUPABASE_URL` and `PROD_SUPABASE_ANON_KEY` so `.github/workflows/keep-alive.yml` stops the free project from pausing, and run `supabase db dump` weekly into private storage (it contains personal data).

## Sign-up approvals

Students sign up with their school email and a password (N36). Each new one posts "New sign-up waiting for
approval" to the team Discord with a masked address (`a•••@tec.mx`) and two lines to paste into the SQL
editor. The lines name the request by its id and look the email up there, so no address is stored in Discord.
By email, when you have it:

- Approve: `select private.approve_signup('<email>');`
- Reject: `select private.reject_signup('<email>');` deletes the unapproved account, so the address can ask again.
- Everyone still waiting: `select email, requested_at from private.signup_requests where approved_at is null order by requested_at;`
- Approve everyone waiting: `update private.signup_requests set approved_at = now() where approved_at is null;` (one statement, so the Sheet gets one update instead of one per person)
- Approve someone who joined on the website before they have an account: `select private.approve_signup('<email>');` works the same. When they create their account in the app it goes straight in, with no alert.

The website's waitlist is the same queue (N38). A school email that joins on the website appears here with
`source = 'website'` and the time it joined, which is its place in line; there's no alert, because there's no
account to approve yet. When the person creates their account in the app, the usual alert arrives, and the
request keeps its website time and source. Rejecting a website request that has no account just removes it
(and its Sheet row says "Removed"). Non-school emails stay in the Sheet as launch news and never appear here.

Nobody checks that the person owns the address: there's no confirmation email (no custom SMTP yet). Approve
only addresses you can vouch for. If the alert doesn't arrive, the request is still in the table and
Postgres logs a warning. A forgotten password is reset in **Auth → Users**.

### Invites (1.0)

Sign-up is invite-only from 1.0 (N37): the wait above is the waitlist, and a member's invite code skips it.
Every member has 3 codes in the app. When someone uses one, the same channel gets an FYI instead of a
request: "<email> joined with Ana G.'s invite." The account is approved already, so the "waiting for
approval" alert its sign-up posted a moment earlier needs nothing.

- Give someone more codes: `select private.grant_invites('<email>', 5);` (they show up the next time the person opens their invites).
- Who invited whom: `select email, invited_by, approved_at from private.signup_requests where invited_by is not null order by approved_at desc;`
- A member's codes: `select code, redeemed_email, redeemed_at from private.invites where inviter_id = '<user id>';`

More than 5 wrong codes in an hour locks that account's redeeming until the hour is up. Banning a member
stops their unused codes working.

**Master codes** (`20261125000000_master_invites`) work for any number of people, typed in the same field
as a member's code, so every app version takes them. Each use posts "<email> joined with the team code
MASUNO (3 used)". Anyone with a school email who sees one gets in, so give it a limit or an end date when
it's going somewhere public. Letters (no accents) and digits, 4 to 32 of them; case, spaces and dashes don't matter.

- Make one: `select private.create_master_invite('MASUNO');`, or with a limit, an end date and a note:
  `select private.create_master_invite('POSTERS', 50, now() + interval '30 days', 'launch posters');`
- Turn one off (people it let in stay in): `select private.revoke_master_invite('POSTERS');`
- How they're doing: `select m.code, m.note, m.max_uses, m.expires_at, m.revoked_at, count(u.id) as uses from private.master_invites m left join private.master_invite_uses u using (code) group by m.code order by m.created_at;`
- Who used one: `select email, redeemed_at from private.master_invite_uses where code = 'POSTERS' order by redeemed_at;`

## Moderation

- New reports post to the team Discord (step 6 above). Act within 24 h and set `resolved_at`.
- Ban: `update public.profiles set banned_at = now() where id = '<user id>';`. Every write RPC then fails with `suspended`, and reads return nothing but the account's own profile, blocks, bookmarks and preferences.
- Hide a chat message: `update private.chat_messages set deleted_at = now() where id = '<message id>';`. A message report has `message_id` and a copy of the text in `message_body`.
- Turn chat off everywhere: `update public.app_config set value = 'false' where key = 'chat_enabled';`.
- Add a filtered word: `insert into private.blocked_words (word) values ('<lowercase, no accents>');`.

## Production secrets

The Edge Function needs Supabase-managed `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`. Never put the service-role key, the Entra client secret, the webhook URL or the waitlist sync secret in the iOS app or in source control.

Run the two-session last-spot, RLS/block, suspension and account-deletion checks in `docs/QA.md` before release.

## Build 2 delivery protocol rollout

`20261117000000_delivery_fencing_and_realtime.sql` is a forward migration. Apply it before
publishing the updated `send-push` function: that function requires `claim_notifications_v2`
and `complete_notifications_v2`. The migration keeps legacy wrappers so the existing sender
continues to operate during the transition. Do not deploy the new sender ahead of the SQL.
Keep `verify_jwt = true`; the sender also compares the bearer token directly with its configured
service-role key.

A v2 claim includes an opaque `claim_token`. Every completion/release includes that token;
expired or duplicate workers cannot complete a newer attempt or remove its device tokens.
Legacy-to-legacy claims retain their earlier limitations, so finish deploying the v2 sender.
Actual APNs sends have a global cap of 8, a 5-second request/body deadline, and a 25-second
batch budget. Each phone has a sequential lane; a retry holds its later alerts. The SQL claim
lease remains ten minutes for worker recovery, with stale attempts fenced by claim tokens. A row succeeds if at least one device succeeds, preserving the previous policy.

The user-authorized activation on 2026-11-16 deployed this protocol to both projects, in dev →
prod order. Forward migration `20261116000100_align_campus_realtime.sql` first repaired dev's
recorded-migration-12 drift (old all-campus triggers/policy), then migration 17 installed fencing,
then the matching sender was deployed. Applied migration history was not rewritten.

Both projects now have chat/push enabled and active scheduled jobs. Production uses a Production
APNs key and dev uses a separate Sandbox key for `com.masuno.app`; keys remain outside the repo
and are installed as Edge secrets. Each dispatcher uses its own project's service-role JWT in
Vault. Gateway JWT verification remains enabled. Public config/auth checks and authenticated
sender checks pass; actual phone notification delivery still needs a registered device.
Dev is intentionally not connected to the production waitlist Sheet; configuring a dev Sheet
requires a separate Apps Script deployment.
See [QA.md](../docs/QA.md) for the remaining physical-device and two-phone delivery checks.

## Security migration rollout

The security migration uses version `20261119000000` because hosted projects already record
`20261117000000` for delivery fencing and `20261118000000` for host-roster reconciliation.
Apply it from the combined release history, retaining those previously deployed migration files.
A legacy device token with no install hash can be bound only by its current account; old clients
can still refresh their own registration and must unregister before switching accounts.

## Notification latency and ordering

Migration `20261122000000_notification_order_and_latency.sql` removes the old two-to-five-minute
batching delays: the first chat notification is immediately eligible; follow-ups, roster summaries,
game edits, and new-game alerts use at most ten seconds of batching. New messages keep an existing
pending deadline instead of continually postponing it. The ten-second drain schedule remains the
fallback for due rows. Retriable APNs errors back off five then ten seconds; unattempted rows behind
an earlier retry do not consume attempts. Scheduled reminders, quiet hours, preferences, and caps
retain their existing rules.

V2 claims use recipient locks and check earlier pending rows, preventing overlapping workers from
submitting later alerts first. Delivery keeps the returned order per device and parallelizes across
phones. APNs acceptance order is controlled here; arrival timing on a disconnected or sleeping
phone remains controlled by Apple. Confirm physical-device latency and display order in QA.
