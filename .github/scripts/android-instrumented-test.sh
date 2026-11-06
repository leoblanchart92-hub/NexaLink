#!/usr/bin/env bash
# Run real JNI tests repeatedly; no success retry and no suppressed failures.
set +e
cd android || exit 1
mkdir -p ../test-diagnostics
status=0
for attempt in 1 2 3; do
  echo "Android instrumentation attempt $attempt/3"
  adb logcat -c
  timeout 300 ./gradlew :app:connectedDebugAndroidTest 2>&1 | tee "../test-diagnostics/gradle-${attempt}.log"
  status=${PIPESTATUS[0]}
  adb logcat -d -v threadtime > "../test-diagnostics/logcat-${attempt}.log" 2>&1
  adb logcat -d -v brief -s Go:* > "../test-diagnostics/go-${attempt}.log" 2>&1
  cp -R ../build/app/outputs/androidTest-results/connected "../test-diagnostics/results-${attempt}" 2>/dev/null
  if [ "$status" -ne 0 ]; then
    tail -c 1800 "../test-diagnostics/gradle-${attempt}.log" | base64 -w0 | xargs -r -I{} echo "::notice title=INSTRUMENTED_FAILURE::{}"
    head -c 12000 "../test-diagnostics/go-${attempt}.log" | split -b 1800 - /tmp/nexalink-go-part-
    for part in /tmp/nexalink-go-part-*; do
      [ -s "$part" ] && echo "::notice title=INSTRUMENTED_GO_${part##*-}::$(base64 -w0 "$part")"
    done
    break
  fi
done
exit "$status"
