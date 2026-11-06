#!/usr/bin/env bash
set +e
cd android || exit 1
./gradlew :app:connectedDebugAndroidTest 2>&1 | tee /tmp/nexalink-instrumented.log
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  echo "::notice title=INSTRUMENTED_LOG::$(tail -c 24000 /tmp/nexalink-instrumented.log | base64 -w0)"
  for xml in app/build/outputs/androidTest-results/connected/*/*.xml; do
    if [ -f "$xml" ]; then echo "::notice title=INSTRUMENTED_XML::$(base64 -w0 "$xml")"; fi
  done
fi
exit "$status"
