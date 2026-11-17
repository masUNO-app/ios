#!/bin/bash
set -euo pipefail

runtime_available() {
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
available = any(r["version"] == "18.6" and r["buildversion"] == "22G86" and r["isAvailable"]
                for r in json.load(sys.stdin)["runtimes"])
sys.exit(0 if available else 1)
'
}

if runtime_available; then
  exit 0
fi

# Xcode 26.6's -downloadPlatform lookup cannot find this legacy runtime. Pin Apple's
# universal 18.6 MobileAsset instead. URL, digest and public archive key come from Apple's
# com.apple.MobileAsset.iOSSimulatorRuntime catalog (build 22G86, posted 2025-07-29).
# This is the same signed runtime used by Xcode's Components installer, with no login needed.
runtime_workdir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ios18-runtime.XXXXXX")
trap 'rm -rf "$runtime_workdir"' EXIT
archive="$runtime_workdir/iOS-18.6.aar"
curl --fail --location --retry 3 --output "$archive" \
  'https://updates.cdn-apple.com/2025/mobileassets/043-18341/791B091D-2B91-47E1-9FCD-0C115650A8F4/com_apple_MobileAsset_iOSSimulatorRuntime/BA59E4A4-296E-40D2-8551-66E0F7881682.aar'
echo "72611400d7cb342548057b9d28c3ac0e027718796babf84545454a07f0a523cd  $archive" | shasum -a 256 -c -
/usr/bin/aa extract -i "$archive" -d "$runtime_workdir/extracted" \
  -key-value 'base64:Fx/EgjGjPyFgJ6DDXUfzd/i/UJ6kDJmtGLbba7gPess='
# Reclaim the downloaded archive before importing the extracted disk image.
rm "$archive"
xcrun simctl runtime add "$runtime_workdir/extracted/AssetData/043-18670-100.dmg"
runtime_available
