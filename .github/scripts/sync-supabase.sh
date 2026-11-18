#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_ACCESS_TOKEN:?Set the SUPABASE_ACCESS_TOKEN repository secret}"
: "${SUPABASE_PROJECT_REF:?Set the DEV_SUPABASE_PROJECT_REF and PROD_SUPABASE_PROJECT_REF repository variables}"
if [[ ! "$SUPABASE_PROJECT_REF" =~ ^[a-z]{20}$ ]]; then
  echo '::error::The Supabase project reference must contain 20 lowercase letters.'
  exit 1
fi

# Preview and apply the same history. Fail on drift instead of repairing history
# automatically. Seeds and hosted Auth/Vault settings are managed separately.
supabase db push --remote="$SUPABASE_PROJECT_REF" --dry-run --skip-vault --yes
supabase db push --remote="$SUPABASE_PROJECT_REF" --skip-vault --yes
# SQL must be installed before the sender that depends on it. Retain JWT verification.
supabase functions deploy --remote="$SUPABASE_PROJECT_REF" --use-api --yes
