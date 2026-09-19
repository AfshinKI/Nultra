#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/nultra-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -module-cache-path "$check_dir/cache" Nultra/Models/*.swift scripts/check_protocol.swift -o "$check_dir/protocol-checks"
"$check_dir/protocol-checks"
swiftc -typecheck -target arm64-apple-macosx13.0 -module-cache-path "$check_dir/cache" Nultra/Models/*.swift Nultra/Bluetooth/*.swift Nultra/Views/*.swift Nultra/Intents/*.swift Nultra/App/*.swift
plutil -lint Nultra.xcodeproj/project.pbxproj Nultra/Info.plist
