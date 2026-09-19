#!/bin/bash
set -euo pipefail
# Exact owner screen size and OS. Boot starts before compilation to overlap setup.
preview_device=$(xcrun simctl create 'Nultra iPhone 13 mini' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini \
  com.apple.CoreSimulator.SimRuntime.iOS-26-2)
mkdir -p build
printf '%s\n' "$preview_device" > build/simulator-id
xcrun simctl boot "$preview_device"
echo "Started iPhone 13 mini simulator: $preview_device"
