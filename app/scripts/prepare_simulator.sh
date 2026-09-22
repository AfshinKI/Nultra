#!/bin/bash
set -euo pipefail
# Owner screen size. Default runtime matches CI; local installations may override.
simulator_runtime=${SIMULATOR_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-2}
preview_device=$(xcrun simctl create 'Nultra iPhone 13 mini' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini \
  "$simulator_runtime")
mkdir -p build
printf '%s\n' "$preview_device" > build/simulator-id
xcrun simctl boot "$preview_device"
echo "Started iPhone 13 mini simulator: $preview_device"
