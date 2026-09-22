#!/bin/bash
# Source from bash or zsh. Respect explicit toolchain overrides; never load secrets.
nultra_root=$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)
export JAVA_HOME="${JAVA_HOME:-$nultra_root/.tools/jdk-17.0.20.1+1/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$nultra_root/.tools/android-sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$nultra_root/.tools/gh/gh_2.101.0_macOS_arm64/bin:$PATH"
unset nultra_root
