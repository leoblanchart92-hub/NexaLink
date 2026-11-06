#!/usr/bin/env bash
set +e
cd android || exit 1
./gradlew :app:connectedDebugAndroidTest 2>&1 | tee /tmp/nexalink-instrumented.log
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  tail -c 16000 /tmp/nexalink-instrumented.log | split -b 2000 - /tmp/nexalink-log-part-
  for part in /tmp/nexalink-log-part-*; do
    echo "::notice title=INSTRUMENTED_LOG_${part##*-}::$(base64 -w0 "$part")"
  done
  adb logcat -b crash -d -v brief 2>&1 | tail -c 12000 | split -b 2000 - /tmp/nexalink-crash-part-
  for part in /tmp/nexalink-crash-part-*; do
    [ -s "$part" ] && echo "::notice title=INSTRUMENTED_CRASH_${part##*-}::$(base64 -w0 "$part")"
  done
  for xml in ../build/app/outputs/androidTest-results/connected/*/*.xml; do
    if [ -f "$xml" ]; then echo "::notice title=INSTRUMENTED_XML::$(tail -c 2000 "$xml" | base64 -w0)"; fi
  done
fi
exit "$status"
