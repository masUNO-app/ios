# Supabase backend

Migration-first: deploy the schema before pointing a build at it. Never edit a migration that's
already applied to a shared project; add a new timestamped one. Only deploy production from `main`.

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

## Local setup

1. Install the Supabase CLI and Docker, then run `supabase start`.
2. `supabase db reset` applies the migrations and `seed.sql` (Tec test hosts and games).
3. To sign in locally, create `official.masuno.app+local1@gmail.com` in Studio (Authentication → Add user, auto confirm on). The hook lets it in because `seed.sql` allowlists it.
4. `supabase test db` runs the pgTAP tests in `tests/database` (auth hook, game rules, RLS and grants, blocks, bans, reports, account deletion, group chat, invites and the beta badge, the website waitlist sync). CI runs the same on every PR that touches `supabase/` (`.github/workflows/database.yml`). The two-phone last-spot race stays a manual check in `docs/QA.md`.

## Hosted project checklist (masuno-dev, then masuno-prod)

Migrations don't carry dashboard settings, so do these on each project (B2, B12):

1. `supabase link --project-ref <ref>`, then `supabase db push` and `supabase functions deploy delete-account`.
2. **Auth → Hooks:** register `public.before_user_created` as the **Before User Created** hook.
3. **Auth → Providers → Email:** on, with **Confirm email off** and sign-ups allowed. The app's Create account
   needs a session straight back from `signUp`; approval by hand replaces the confirmation email (N36).
   Sign-up alerts go to the report alerts' webhook (step 6) unless you add a separate one:
   `select vault.create_secret('<discord-webhook-url>', 'signup_alert_webhook_url');`.
   *School SSO, unused until a school approves it:* **Auth → Providers → Azure:** client ID and secret from the Entra app; Azure Tenant URL `https://login.microsoftonline.com/organizations` until Tec's tenant is confirmed (O4), then lock it to Tec before real students sign in on prod. Never `common`.
4. **Auth → URL Configuration:** add `masuno://auth-callback` to Redirect URLs.
5. **Auth → Users:** create the three allowlisted password accounts with "Auto confirm" on: `official.masuno.app+review1@gmail.com`, `+review2`, `+qa1`. Passwords go in the shared password manager.
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
   Join on the website with a school email and confirm the row appears in `private.signup_requests` with
   `source = 'website'`, and that the Sheet's "App status" fills in within a minute. Without the secrets,
   `waitlist_join` and `waitlist_export` refuse every call, nothing is pushed, and Postgres logs a warning on
   each change. To change the secret, update it in Vault (`select vault.update_secret(id, '<new>') from
   vault.secrets where name = 'waitlist_sync_secret';`) and in the Apps Script together.
10. **Prod only:** add GitHub repository secrets `PROD_SUPABASE_URL` and `PROD_SUPABASE_ANON_KEY` so `.github/workflows/keep-alive.yml` stops the free project from pausing, and run `supabase db dump` weekly into private storage (it contains personal data).

## Sign-up approvals

Students sign up with their school email and a password (N36). Each new one posts "New sign-up waiting for
approval" to the team Discord with two lines to paste into the SQL editor:

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

## Moderation

- New reports post to the team Discord (step 6 above). Act within 24 h and set `resolved_at`.
- Ban: `update public.profiles set banned_at = now() where id = '<user id>';`. Every write RPC then fails with `suspended`.
- Hide a chat message: `update private.chat_messages set deleted_at = now() where id = '<message id>';`. A message report has `message_id` and a copy of the text in `message_body`.
- Turn chat off everywhere: `update public.app_config set value = 'false' where key = 'chat_enabled';`.
- Add a filtered word: `insert into private.blocked_words (word) values ('<lowercase, no accents>');`.

## Production secrets

The Edge Function needs Supabase-managed `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`. Never put the service-role key, the Entra client secret, the webhook URL or the waitlist sync secret in the iOS app or in source control.

Run the two-session last-spot, RLS/block, suspension and account-deletion checks in `docs/QA.md` before release.
