#!/usr/bin/env bash
# Run the channel test even if VPN instrumentation failed; preserve both statuses.
set +e
bash .github/scripts/android-phase7-test.sh
vpn_status=$?
mkdir -p test-diagnostics
timeout 300 flutter test integration_test/engine_channel_test.dart -d emulator-5554 2>&1 | tee test-diagnostics/flutter-channel.log
flutter_status=${PIPESTATUS[0]}
printf '%s\n' "$flutter_status" > test-diagnostics/flutter-channel-status.txt
if [ "$flutter_status" -ne 0 ]; then
  echo "::notice title=FLUTTER_CHANNEL_FAILURE::$(tail -c 3000 test-diagnostics/flutter-channel.log | base64 -w0)"
fi
if [ "$vpn_status" -ne 0 ] || [ "$flutter_status" -ne 0 ]; then exit 1; fi
