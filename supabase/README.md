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
| `20261110000000_group_chat` | Group chat messaging (0.6): messages, unread counts, chat RPCs, the Realtime channel, 30-day cleanup. Ships switched off |

## Local setup

1. Install the Supabase CLI and Docker, then run `supabase start`.
2. `supabase db reset` applies the migrations and `seed.sql` (Tec test hosts and games).
3. To sign in locally, create `official.masuno.app+local1@gmail.com` in Studio (Authentication → Add user, auto confirm on). The hook lets it in because `seed.sql` allowlists it.
4. `supabase test db` runs the pgTAP tests in `tests/database` (auth hook, game rules, RLS and grants, blocks, bans, reports, account deletion, group chat). CI runs the same on every PR that touches `supabase/` (`.github/workflows/database.yml`). The two-phone last-spot race stays a manual check in `docs/QA.md`.

## Hosted project checklist (masuno-dev, then masuno-prod)

Migrations don't carry dashboard settings, so do these on each project (B2, B12):

1. `supabase link --project-ref <ref>`, then `supabase db push` and `supabase functions deploy delete-account`.
2. **Auth → Hooks:** register `public.before_user_created` as the **Before User Created** hook.
3. **Auth → Providers → Azure:** client ID and secret from the Entra app; Azure Tenant URL `https://login.microsoftonline.com/organizations` until Tec's tenant is confirmed (O4), then lock it to Tec before real students sign in on prod. Never `common`.
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
   `update public.app_config set value = 'true' where key = 'chat_enabled';`, run `docs/QA.md` §6 with two phones, and
   set it back to `'false'` if anything fails. The app reads the switch at launch. 0.5 ignores it and keeps the
   read-only chat, so people on 0.5 don't see messages from people on 0.6.
9. **Prod only:** add GitHub repository secrets `PROD_SUPABASE_URL` and `PROD_SUPABASE_ANON_KEY` so `.github/workflows/keep-alive.yml` stops the free project from pausing, and run `supabase db dump` weekly into private storage (it contains personal data).

## Moderation

- New reports post to the team Discord (step 6 above). Act within 24 h and set `resolved_at`.
- Ban: `update public.profiles set banned_at = now() where id = '<user id>';`. Every write RPC then fails with `suspended`.
- Hide a chat message: `update private.chat_messages set deleted_at = now() where id = '<message id>';`. A message report has `message_id` and a copy of the text in `message_body`.
- Turn chat off everywhere: `update public.app_config set value = 'false' where key = 'chat_enabled';`.
- Add a filtered word: `insert into private.blocked_words (word) values ('<lowercase, no accents>');`.

## Production secrets

The Edge Function needs Supabase-managed `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`. Never put the service-role key, the Entra client secret or the webhook URL in the iOS app or in source control.

Run the two-session last-spot, RLS/block, suspension and account-deletion checks in `docs/QA.md` before release.
