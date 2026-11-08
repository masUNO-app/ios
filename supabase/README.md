# Supabase backend

This directory contains the complete initial backend for masUNO. It is intentionally migration-first: deploy the schema before pointing a build at it.

## Local setup

1. Install the Supabase CLI and run `supabase start`.
2. Apply the migration with `supabase db reset` locally, then `supabase db push` from main for a hosted project.
3. Deploy account deletion with `supabase functions deploy delete-account`.
4. In Supabase Auth, configure the Azure provider, set the redirect URL to `masuno://auth-callback`, and register `public.before_user_created` as the **Before User Created** hook.
5. Insert the real campus (and a hidden demo campus plus allowlisted review accounts) before release. The migration only seeds sports and safe placeholder app-config values.

## Production secrets

The Edge Function needs Supabase-managed `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`. Never put the service-role key in the iOS app or in source control.

## Contract coverage

The migration implements the views, RLS, security-definer RPCs, auth hook, reference data, blocks/reports, append-only game activity, race-safe RSVP changes, auto-repost, and profile/account privacy specified in `docs/API.md`.

- Never edit a migration already applied to a shared project; add a new timestamped migration.
- Only deploy production from main.
- Run the two-session last-spot, RLS/block, suspension, and account-deletion checks in `docs/QA.md` before release.
