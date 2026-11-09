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
  # Avoid a tee pipe held open by a surviving Gradle/adb child after timeout.
  timeout --kill-after=10 "${NEXALINK_TEST_TIMEOUT:-420}" ./gradlew :app:connectedDebugAndroidTest "${args[@]}" > "${diagnostics}/gradle-${attempt}.log" 2>&1
  status=$?
  cat "${diagnostics}/gradle-${attempt}.log"
  if [ "${NEXALINK_CYCLE_TEST:-0}" = 1 ]; then
    adb exec-out run-as com.nexalink.app cat files/phase81-cycles.jsonl > "${diagnostics}/cycles.jsonl" 2> "${diagnostics}/cycles-pull.err"
    adb logcat -d -v raw -s NexaLinkCycle:I '*:S' > "${diagnostics}/cycles-logcat.log" 2>&1
    if ! grep -q '^{' "${diagnostics}/cycles.jsonl"; then
      sed -n 's/^RECORD=//p' "${diagnostics}/cycles-logcat.log" > "${diagnostics}/cycles.jsonl"
    fi
    if [ "$(wc -l < "${diagnostics}/cycles.jsonl")" -lt 100 ]; then
      echo "::notice title=PHASE81_CHECKPOINT_${NEXALINK_DIAGNOSTIC_LABEL}::$(tail -c 1800 "${diagnostics}/cycles-logcat.log" | base64 -w0)"
    fi
    python3 ../.github/scripts/summarize-cycles.py "${diagnostics}/cycles.jsonl" "${NEXALINK_DIAGNOSTIC_LABEL}" || status=1
  fi
  adb logcat -d -v threadtime > "${diagnostics}/logcat-${attempt}.log" 2>&1
  adb logcat -d -v brief -s Go:* > "${diagnostics}/go-${attempt}.log" 2>&1
  cp -R ../build/app/outputs/androidTest-results/connected "${diagnostics}/results-${attempt}" 2>/dev/null
  adb logcat -d -v brief -s TestRunner:I | grep -E 'started:|finished:|ignored:|assumption' > "${diagnostics}/tests-${attempt}.log"
  if [ "$status" -ne 0 ]; then
    # GitHub caps annotations per step. Keep full logs in the artifact and
    # reserve notices for concise failure, crash and cycle summaries.
    tail -c 1800 "${diagnostics}/gradle-${attempt}.log" | base64 -w0 | xargs -r -I{} echo "::notice title=INSTRUMENTED_FAILURE::{}"
    adb logcat -d -v brief | grep -Ei 'NexaLinkVPN|NexaLinkOwner|WireGuard|VpnService|VpnJni' > "${diagnostics}/vpn-${attempt}.log"
    adb logcat -b crash -d -v brief > "${diagnostics}/crash-${attempt}.log" 2>&1
    adb logcat -d -v brief | grep -Ei 'NexaLinkABI|fatal|signal [0-9]|abort message|native.bridge|libgojni|nativeloader|debuggerd' | tail -c 9000 > "${diagnostics}/selected-${attempt}.log"
    if grep -Eqi 'FATAL EXCEPTION|signal [0-9]+|fatal error|segmentation fault' "${diagnostics}/crash-${attempt}.log"; then
      echo "::notice title=INSTRUMENTED_CRASH::$(tail -c 1800 "${diagnostics}/crash-${attempt}.log" | base64 -w0)"
    fi
    break
  fi
done
printf '%s\n' "$status" > "${diagnostics}/exit-status.txt"
exit "$status"
