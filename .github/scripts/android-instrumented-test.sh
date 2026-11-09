#!/usr/bin/env bash
# Run real JNI tests repeatedly; no success retry and no suppressed failures.
set +e
cd android || exit 1
diagnostics="../test-diagnostics/${NEXALINK_DIAGNOSTIC_LABEL:-android-29-x86_64}"
mkdir -p "$diagnostics"
status=0
for ((attempt=1; attempt<=${NEXALINK_ATTEMPTS:-3}; attempt++)); do
  echo "Android instrumentation attempt $attempt/${NEXALINK_ATTEMPTS:-3}"
  adb logcat -c
  if [ "${NEXALINK_CYCLE_TEST:-0}" = 1 ]; then adb logcat -G 16M 2>/dev/null || true; fi
  args=()
  if [ -n "${NEXALINK_TEST_CLASS:-}" ]; then
    args+=("-Pandroid.testInstrumentationRunnerArguments.class=${NEXALINK_TEST_CLASS}")
  elif [ -n "${NEXALINK_TEST_EXCLUDE:-}" ]; then
    args+=("-Pandroid.testInstrumentationRunnerArguments.notClass=${NEXALINK_TEST_EXCLUDE}")
  fi
  if [ -n "${NEXALINK_TEST_ABI:-}" ]; then
    args+=("-PnexalinkTestAbi=${NEXALINK_TEST_ABI}" "-Pandroid.testInstrumentationRunnerArguments.expectedGoArch=${NEXALINK_GO_ARCH}")
  fi
  timeout "${NEXALINK_TEST_TIMEOUT:-420}" ./gradlew :app:connectedDebugAndroidTest "${args[@]}" 2>&1 | tee "${diagnostics}/gradle-${attempt}.log"
  status=${PIPESTATUS[0]}
  if [ "${NEXALINK_CYCLE_TEST:-0}" = 1 ]; then
    adb exec-out run-as com.nexalink.app cat files/phase81-cycles.jsonl > "${diagnostics}/cycles.jsonl" 2> "${diagnostics}/cycles-pull.err"
    adb logcat -d -v raw -s NexaLinkCycle:I '*:S' > "${diagnostics}/cycles-logcat.log" 2>&1
    if ! grep -q '^{' "${diagnostics}/cycles.jsonl"; then
      sed -n 's/^RECORD=//p' "${diagnostics}/cycles-logcat.log" > "${diagnostics}/cycles.jsonl"
    fi
    echo "::notice title=PHASE81_CHECKPOINT_${NEXALINK_DIAGNOSTIC_LABEL}::$(tail -c 1800 "${diagnostics}/cycles-logcat.log" | base64 -w0)"
    if [ -s "${diagnostics}/cycles-pull.err" ]; then
      echo "::notice title=PHASE81_PULL_${NEXALINK_DIAGNOSTIC_LABEL}::$(tail -c 500 "${diagnostics}/cycles-pull.err" | base64 -w0)"
    fi
    python3 ../.github/scripts/summarize-cycles.py "${diagnostics}/cycles.jsonl" "${NEXALINK_DIAGNOSTIC_LABEL}" || status=1
  fi
  adb logcat -d -v threadtime > "${diagnostics}/logcat-${attempt}.log" 2>&1
  adb logcat -d -v brief -s Go:* > "${diagnostics}/go-${attempt}.log" 2>&1
  cp -R ../build/app/outputs/androidTest-results/connected "${diagnostics}/results-${attempt}" 2>/dev/null
  adb logcat -d -v brief -s TestRunner:I | grep -E 'started:|finished:|ignored:|assumption' > "${diagnostics}/tests-${attempt}.log"
  if [ "$status" -ne 0 ]; then
    rm -f /tmp/nexalink-{go,crash,selected,vpn}-part-*
    tail -c 1800 "${diagnostics}/gradle-${attempt}.log" | base64 -w0 | xargs -r -I{} echo "::notice title=INSTRUMENTED_FAILURE::{}"
    echo "::notice title=TEST_ABI::${NEXALINK_TEST_ABI:-host} ${NEXALINK_GO_ARCH:-host}"
    adb logcat -d -v brief | grep -Ei 'NexaLinkVPN|NexaLinkOwner|WireGuard|VpnService|VpnJni' > "${diagnostics}/vpn-${attempt}.log"
    tail -c 7200 "${diagnostics}/vpn-${attempt}.log" | split -b 1800 - /tmp/nexalink-vpn-part-
    for part in /tmp/nexalink-vpn-part-*; do
      [ -s "$part" ] && echo "::notice title=INSTRUMENTED_VPN_${part##*-}::$(base64 -w0 "$part")"
    done
    adb logcat -b crash -d -v brief > "${diagnostics}/crash-${attempt}.log" 2>&1
    adb logcat -d -v brief | grep -Ei 'NexaLinkABI|fatal|signal [0-9]|abort message|native.bridge|libgojni|nativeloader|debuggerd' | tail -c 9000 > "${diagnostics}/selected-${attempt}.log"
    head -c 7200 "${diagnostics}/crash-${attempt}.log" | split -b 1800 - /tmp/nexalink-crash-part-
    for part in /tmp/nexalink-crash-part-*; do
      [ -s "$part" ] && echo "::notice title=INSTRUMENTED_CRASH_${part##*-}::$(base64 -w0 "$part")"
    done
    tail -c 5400 "${diagnostics}/selected-${attempt}.log" | split -b 1800 - /tmp/nexalink-selected-part-
    for part in /tmp/nexalink-selected-part-*; do
      [ -s "$part" ] && echo "::notice title=INSTRUMENTED_SELECTED_${part##*-}::$(base64 -w0 "$part")"
    done
    head -c 7200 "${diagnostics}/go-${attempt}.log" | split -b 1800 - /tmp/nexalink-go-part-
    for part in /tmp/nexalink-go-part-*; do
      [ -s "$part" ] && echo "::notice title=INSTRUMENTED_GO_${part##*-}::$(base64 -w0 "$part")"
    done
    break
  fi
done
printf '%s\n' "$status" > "${diagnostics}/exit-status.txt"
exit "$status"
