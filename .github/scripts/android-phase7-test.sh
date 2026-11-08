#!/usr/bin/env bash
# Separate processes for the two independent Go runtimes. Preserve failures from
# every suite; neither process separation nor a later success erases past crashes.
set +e
base=${NEXALINK_DIAGNOSTIC_LABEL:-android-29-x86_64}
status=0
NEXALINK_DIAGNOSTIC_LABEL="${base}-core" \
NEXALINK_TEST_EXCLUDE='com.nexalink.app.network.GuestVpnServiceInstrumentedTest,com.nexalink.app.network.OwnerVpnServiceInstrumentedTest' \
  bash .github/scripts/android-instrumented-test.sh || status=1
for role in Guest Owner; do
  NEXALINK_DIAGNOSTIC_LABEL="${base}-${role,,}" \
  NEXALINK_TEST_CLASS="com.nexalink.app.network.${role}VpnServiceInstrumentedTest" \
    bash .github/scripts/android-instrumented-test.sh || status=1
done
exit "$status"
