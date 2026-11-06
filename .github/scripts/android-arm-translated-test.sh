#!/usr/bin/env bash
# Android's native bridge translates ARM instructions on this x86_64 emulator.
# This tests ARM binaries, not an ARM CPU or a physical phone.
set -euo pipefail
mkdir -p test-diagnostics/arm-translation
adb shell getprop > test-diagnostics/arm-translation/device-properties.txt
adb shell getprop ro.product.cpu.abilist
adb shell getprop ro.dalvik.vm.native.bridge
status=0
for pair in 'arm64-v8a:arm64' 'armeabi-v7a:arm'; do
  abi=${pair%:*}; arch=${pair#*:}
  echo "Testing translated ARM ABI: $abi (Go $arch)"
  NEXALINK_DIAGNOSTIC_LABEL="arm-translated-$abi" NEXALINK_TEST_ABI="$abi" NEXALINK_GO_ARCH="$arch" \
    bash .github/scripts/android-instrumented-test.sh || status=1
done
exit "$status"
