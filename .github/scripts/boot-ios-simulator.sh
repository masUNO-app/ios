#!/bin/bash
set -eo pipefail

mkdir -p artifacts
xcrun simctl list runtimes --json > artifacts/simulator-runtimes.json
xcrun simctl list devices available --json > artifacts/simulator-devices.json

# The runner image already has devices for its installed runtimes. Reuse one to avoid
# paying for an additional fresh device's migration before every test run.
simulator=$(python3 - <<'PY'
import json
import os
from pathlib import Path

runtime = os.environ["SIMULATOR_RUNTIME"]
devices = json.loads(Path("artifacts/simulator-devices.json").read_text())["devices"].get(runtime, [])
matches = [device for device in devices if device.get("deviceTypeIdentifier") == os.environ["SIMULATOR_DEVICE_TYPE"]]
matches.sort(key=lambda device: device.get("state") != "Booted")
if matches:
    print(matches[0]["udid"])
PY
)
if [[ -z "$simulator" ]]; then
  simulator=$(xcrun simctl create 'masUNO CI' "$SIMULATOR_DEVICE_TYPE" "$SIMULATOR_RUNTIME")
fi
echo "SIMULATOR=$simulator" >> "$GITHUB_ENV"
xcrun simctl bootstatus "$simulator" -b 2>&1 | tee artifacts/simulator-boot.log
