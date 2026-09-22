#!/bin/bash
set -u
cd "$(dirname "$0")/.."
source scripts/local_env.sh
missing=0
check() {
  if "$@"; then echo "OK: $*"; else echo "MISSING/BLOCKED: $*"; missing=1; fi
}
sw_vers
df -h .
check java -version
check test -f "$ANDROID_HOME/platforms/android-35/android.jar"
check test -x "$ANDROID_HOME/build-tools/35.0.0/apksigner"
check test -x "$ANDROID_HOME/emulator/emulator"
check test -d "$ANDROID_HOME/system-images/android-35/google_apis/arm64-v8a"
check test -f android/signing/nultra-release.jks
check test -f android/signing/password
check gh --version
check python3 --version
check xcodebuild -version
check xcrun --sdk iphoneos --show-sdk-version
echo 'Hosted fallback uses Xcode 26.2; current local installation uses Xcode 27.0.'
echo 'With Xcode installed, also check: xcrun simctl list runtimes'
echo 'Authentication is separate: gh auth status (do not print tokens).'
exit "$missing"
