#!/bin/bash
# Runs the accessibility audit (AccessibilityAuditUITests), and once more after a simulator stall.
#
# On iOS 27 runners the simulator sometimes stops answering partway through the audit's ~40 app
# launches: a launch logs "App event loop idle notification not received" and the test is killed at
# its time allowance (Nov 24 detail screens, Nov 26 form screens). xcodebuild doesn't retry a test
# killed that way, so this script does: it reboots the simulator and runs only the tests that failed.
# A failure without a stall sign is a real audit finding and fails at once, and a real finding
# fails the retry too.
set -o pipefail

test_runs=(build/Build/Products/*.xctestrun)
[[ -f "${test_runs[0]}" && ${#test_runs[@]} -eq 1 ]] || { echo "::error::Expected one .xctestrun in build/Build/Products"; exit 1; }
mkdir -p artifacts

audit() {
  local attempt=$1
  shift
  xcodebuild test-without-building -xctestrun "${test_runs[0]}" \
    -destination "id=$SIMULATOR" -destination-timeout 60 \
    -resultBundlePath "artifacts/audit-$attempt.xcresult" "$@" \
    -parallel-testing-enabled NO -collect-test-diagnostics never \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 240 \
    -maximum-test-execution-time-allowance 300 \
    -enableCodeCoverage NO CODE_SIGNING_ALLOWED=NO \
    2>&1 | tee "artifacts/audit-$attempt.log"
}

suite=masUNOUITests/AccessibilityAuditUITests
audit 1 "-only-testing:$suite" && exit 0

first=artifacts/audit-1.log
stall='exceeded execution time allowance|App event loop idle notification not received|Failed to terminate com\.masuno\.app|Timed out while evaluating UI query'
if ! grep -qE "$stall" "$first"; then
  echo "::error::The accessibility audit has findings (no simulator stall in the log), so it isn't retried."
  exit 1
fi

failed=$(grep -oE "AccessibilityAuditUITests (test[A-Za-z0-9]+)\]' (failed|exceeded)" "$first" | awk '{print $2}' | tr -d "]'" | sort -u)
args=()
for test in $failed; do args+=("-only-testing:$suite/$test"); done
# Nothing named (the runner itself fell over): the whole audit again.
[[ ${#args[@]} -gt 0 ]] || args=("-only-testing:$suite")

echo "::warning::The simulator stalled during the accessibility audit. Rebooting it and running again: ${failed:-all of it}"
xcrun simctl shutdown "$SIMULATOR" || true
xcrun simctl boot "$SIMULATOR"
xcrun simctl bootstatus "$SIMULATOR" -b
audit 2 "${args[@]}"
