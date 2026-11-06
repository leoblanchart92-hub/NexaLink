#!/usr/bin/env bash
# A single successful run is insufficient: the JNI lifecycle has crashed
# intermittently on the emulator. Fail the job on the first unsuccessful run.
set +e
cd android || exit 1
status=0
for attempt in 1 2 3; do
  echo "Android instrumentation attempt $attempt/3"
  ./gradlew :app:connectedDebugAndroidTest 2>&1 | tee /tmp/nexalink-instrumented.log
  status=${PIPESTATUS[0]}
  [ "$status" -ne 0 ] && break
done
if [ "$status" -ne 0 ]; then
  tail -c 2000 /tmp/nexalink-instrumented.log | split -b 2000 - /tmp/nexalink-log-part-
  for part in /tmp/nexalink-log-part-*; do
    echo "::notice title=INSTRUMENTED_LOG_${part##*-}::$(base64 -w0 "$part")"
  done
  # Go's fatal runtime trace is written under the Go logcat tag, not
  # necessarily the Android crash buffer. Keep the first frames.
  adb logcat -d -v brief -s Go:* 2>&1 | head -c 12000 | split -b 2000 - /tmp/nexalink-go-part-
  for part in /tmp/nexalink-go-part-*; do
    [ -s "$part" ] && echo "::notice title=INSTRUMENTED_GO_${part##*-}::$(base64 -w0 "$part")"
  done
  for xml in ../build/app/outputs/androidTest-results/connected/*/*.xml; do
    if [ -f "$xml" ]; then echo "::notice title=INSTRUMENTED_XML::$(tail -c 2000 "$xml" | base64 -w0)"; fi
  done
fi
exit "$status"
