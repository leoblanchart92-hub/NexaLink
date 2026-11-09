#!/usr/bin/env bash
# Separate processes for the two independent Go runtimes. Preserve failures from
# every suite; neither process separation nor a later success erases past crashes.
set +e
base=${NEXALINK_DIAGNOSTIC_LABEL:-android-29-x86_64}
status=0
NEXALINK_DIAGNOSTIC_LABEL="${base}-core" \
NEXALINK_TEST_EXCLUDE='com.nexalink.app.network.GuestVpnServiceInstrumentedTest,com.nexalink.app.network.OwnerVpnServiceInstrumentedTest,com.nexalink.app.network.GuestCycleInstrumentedTest' \
  bash .github/scripts/android-instrumented-test.sh || status=1
# Host-only fixture: UDP binds strictly to loopback; no Internet forwarding.
mkdir -p test-diagnostics
fixture_bin="${RUNNER_TEMP:-/tmp}/nexalink-vpn-fixture"
fixture_log="test-diagnostics/${base}-fixture.log"
(cd gateway && go build -o "$fixture_bin" ./testfixture) || exit 1
"$fixture_bin" > "$fixture_log" 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null; wait "$fixture_pid" 2>/dev/null' EXIT
for i in {1..100}; do
  grep -q '^READY ' "$fixture_log" && break
  kill -0 "$fixture_pid" 2>/dev/null || break
  sleep 0.1
done
if ! grep -q '^READY ' "$fixture_log"; then
  echo "VPN test fixture failed to start"; cat "$fixture_log"; status=1
fi
for role in Guest Owner; do
  NEXALINK_DIAGNOSTIC_LABEL="${base}-${role,,}" \
  NEXALINK_TEST_CLASS="com.nexalink.app.network.${role}VpnServiceInstrumentedTest" \
    bash .github/scripts/android-instrumented-test.sh || status=1
  if [ "$role" = Guest ]; then
    echo "::notice title=TEST_PEER_${base}::$(tail -c 5000 "$fixture_log" | base64 -w0)"
  fi
done
# Run the 100-cycle test once on supported x86_64 emulators, preserving every failure.
if [ "$(adb shell getprop ro.build.version.sdk | tr -d '\r')" -ge 29 ]; then
  NEXALINK_DIAGNOSTIC_LABEL="${base}-cycles" NEXALINK_TEST_CLASS='com.nexalink.app.network.GuestCycleInstrumentedTest' \
  NEXALINK_ATTEMPTS=1 NEXALINK_TEST_TIMEOUT=3900 NEXALINK_CYCLE_TEST=1 \
    bash .github/scripts/android-instrumented-test.sh || status=1
fi
exit "$status"
