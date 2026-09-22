# Local builds and zero-runner releases

The default is local development, local validation, and GitHub CLI asset uploads.
Uploading release assets through `gh` does not execute an Actions runner. No
self-hosted Actions service, Homebrew, Docker, or Android Studio is required.
The manual workflow is an explicitly authorized fallback while Xcode is unavailable.

## Machine audit — 2026-09-22 (after upgrade)

- Apple M1 MacBook Air, 8 GB RAM, now running macOS 27.0.
- Xcode 27.0 (27A266a) is selected at `/Applications/Xcode.app/Contents/Developer`; its license has been accepted. iPhoneOS 27.0 SDK and iOS 27.0 simulator runtime are available.
- About 69 GiB disk space was free before validation builds.
- Project-local Java 17, Android SDK 35, build tools 35.0.0, emulator tools, Gradle cache, and the existing private signing key remain installed.
- Project-local GitHub CLI is now authenticated as AfshinKI using the macOS keyring (verified before v0.11.0 work). Xcode/Apple sign-in is separate from GitHub CLI authentication.
- Hosted fallback remains pinned to Xcode 26.2/iOS 26.2. Local checks on iOS 27 do not establish exact iOS 26.2 UI parity.

Run Android and iOS emulators sequentially on this 8 GB Mac. Keep signing files private.
Build Swift tests outside this Desktop checkout: file-provider Finder metadata on
`.build/` caused a code-signing failure. A scratch directory under `/private/tmp`
avoids that issue; it may be cleared by the OS, so keep durable release artifacts
in `dist/` and record validation results in this document.

Xcode also waited on coordinated reads of the Desktop project. The successful
readiness build used a temporary source copy outside Desktop. For future sustained
development, prefer a checkout outside any cloud/file-provider-managed folder.
When using a temporary copy, copy current `Nultra/`, `NultraWidgets/`, `Shared/`,
`Tests/`, `UITests/`, `Nultra.xcodeproj/`, `scripts/`, and `Package.swift`, excluding
`xcuserdata` and caches; preserve uncommitted source edits, omit private signing
files, and record the original source SHA and working-tree state. Keep build
products outside Desktop and copy verified release artifacts back only afterward.
Do not treat a clean temporary copy as proof that the original working tree is clean.


```sh
source scripts/local_env.sh
bash scripts/local_doctor.sh
# After Xcode installation:
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcrun simctl list runtimes
# Sign in interactively if needed; never paste a token into source/logs:
gh auth status
```

## Development validation

```sh
source scripts/local_env.sh
bash scripts/check.sh
python3 -m unittest discover -s distribution/tests -v
# Android changes (no signing secret required):
android/gradlew -p android testDebugUnitTest lintRelease assembleDebug
# Full Xcode required:
swift test --scratch-path /private/tmp/nultra-swift-build
bash scripts/build_ipa.sh
```

For iOS UI changes, reuse an existing iPhone 13 mini simulator from
`xcrun simctl list devices`. If none exists, `bash scripts/prepare_simulator.sh`
creates one on iOS 26.2 and records its ID in `build/simulator-id`. On this Mac, use
`SIMULATOR_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0 bash scripts/prepare_simulator.sh`
to explicitly select the installed runtime. Boot an existing device if necessary.
Use a fresh result path per run (or move the previous result bundle first):

```sh
device=$(cat build/simulator-id)
xcodebuild -project Nultra.xcodeproj -scheme Nultra -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -destination-timeout 180 \
  -derivedDataPath /private/tmp/nultra-simulator-build -resultBundlePath "build/UI-$(date +%s).xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

For Android UI/background changes, boot a disposable API 35 emulator. Confirm
`adb devices` lists only that emulator before running:

```sh
android/gradlew -p android connectedDebugAndroidTest
# After building the signed release APK:
python3 scripts/android_smoke.py
```

The smoke script clears Nultra data. Never target the owner's daily phone.
Local socket/ADB sandbox failures require an appropriately permitted local run;
they are not missing SDKs and do not justify a hosted build.

## Prepare a release locally

Bump both platform versions/build numbers and write `docs/releases/vX.X.X.md`.
Merge reviewed changes into main, then use a clean checkout of that exact remote
main commit. Finish relevant UI/hardware checks and record outcomes, including
unverified physical behavior. Do not claim skipped checks passed.

Run from the repository root in a dedicated bash shell, without shell tracing:

```sh
set -euo pipefail
source scripts/local_env.sh
git fetch origin main
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
export SOURCE_SHA=$(git rev-parse HEAD)
export RELEASE_TAG=$(python3 scripts/check_release_version.py)
# Check remote releases/tags first; a published version must never be replaced.
bash scripts/check.sh
python3 -m unittest discover -s distribution/tests -v
swift test --scratch-path /private/tmp/nultra-swift-build
bash scripts/build_ipa.sh
# Scoped environment prevents the password remaining exported in the shell.
(
  export NULTRA_KEYSTORE="$PWD/android/signing/nultra-release.jks"
  export NULTRA_STORE_PASSWORD="$(cat android/signing/password)"
  bash scripts/build_apk.sh
)
python3 scripts/prepare_release.py --tag "$RELEASE_TAG"
python3 scripts/verify_ipa.py dist/Nultra.ipa
(cd dist && shasum -a 256 -c Nultra.ipa.sha256 && shasum -a 256 -c Nultra.apk.sha256)
```

Stop on any failure. Confirm IPA/APK version and build numbers match the intended
release, the Android pinned certificate passes, and source is still clean/unchanged.
Capture source SHA, Xcode/Java versions, and test results alongside build info.
For changed Android UI, run the smoke on this exact APK before upload. If source
changes, invalidate affected test/build evidence and rebuild before publishing.

## Upload without Actions

These commands perform publication only when the user has requested a release.
Use the same shell and artifacts from the successful preparation above. Check
that HEAD still equals SOURCE_SHA and the checkout remains clean. If the tag
already exists, verify it resolves to SOURCE_SHA before proceeding. Abort for a
published release. A failed attempt may reuse a draft only after checking its
`targetCommitish` equals SOURCE_SHA; never clobber stable assets.

```sh
test "$(git rev-parse HEAD)" = "$SOURCE_SHA"
test -z "$(git status --porcelain)"
  --target "$SOURCE_SHA" --draft --title "$RELEASE_TAG" \
  --notes-file "docs/releases/$RELEASE_TAG.md"
  dist/Nultra.ipa dist/Nultra.ipa.sha256 dist/Nultra-transfer.zip \
  dist/BUILD-INFO.txt dist/release.json dist/Nultra-Update-Server.zip \
  dist/Nultra.apk dist/Nultra.apk.sha256 dist/android-release.json \
  dist/ANDROID-BUILD-INFO.txt
```

Download the draft assets to a fresh temporary directory with `gh release download`.
Compare SHA-256 values for **all ten assets** against local originals and confirm
the release targets SOURCE_SHA. Only after verification:

```sh
```

The existing Pi polling service can discover the published release normally.
Do not alter its credentials or deploy server changes as part of routine uploads.

## Hosted fallback and budget

`.github/workflows/ios.yml` accepts only manual dispatch, with
`hosted_build_ack=true`. Labels, merges, pushes, and tags trigger no builds.
Without the acknowledgement, no job allocates a runner. Publication defaults off;
diagnostics can select one platform; iOS simulator tests default off. A hosted
release still validates/builds both platforms. Existing caches and seven-day
artifact retention remain. Rerun only failed jobs when necessary.

At the supplied historical 10× assumption, 175 macOS + 81 Linux minutes equals
1,831 included minutes (91.55% of 2,000). This is an estimate, not a verified account
bill. Current [GitHub billing docs](https://example.invalid)
list per-runner prices and separate storage; use the account usage export/dashboard
for actual allowance consumption. Local build plus CLI publication targets **zero
Actions runner minutes**, independently of billing multipliers. Other account
workflows and metered features can still consume allowance.

## Verification of this policy change

On 2026-09-22, local verification passed 1,300 portable Swift protocol checks,
widget/scene checks, macOS type-checking, plist validation, all 11 distribution
unit tests, and Android `testDebugUnitTest lintRelease assembleDebug` (offline,
using the existing cache; 8 seconds). The environment helper was checked in both
bash and zsh. At that initial audit, full iPhoneOS and simulator validation were blocked by missing
Xcode. See the updated machine audit above. No release was published and no hosted workflow was dispatched.

## Xcode 27 readiness verification — 2026-09-22

Source application revision: `530c750` (v0.10.0), with local policy/tooling changes.
After accepting Xcode setup, 34 Swift unit tests and 11 distribution tests passed.
Android unit tests, release lint, and debug assembly passed after the OS upgrade.
The local iPhone Release build succeeded with Xcode 27.0; the IPA passed arm64,
iPhoneOS, version 0.10.0 (10), minimum iOS 16.0, and signature/package checks.
A verified copy is in ignored `dist/readiness-xcode27/` (validation build, not a new release).

On the iPhone 13 mini/iOS 27.0 simulator, six of seven UI tests passed initially.
The scene test read the outer Form accessibility row after tapping its inner switch;
it now waits for the actual switch value. The focused scene rerun passed, including
member-only power control and deletion. All seven behaviors have therefore passed
across the full run and focused rerun; the full suite was not repeated after this
test-only fix. No application logic changed. This does not prove exact iOS 26.2

The initial failed run stalled during post-test diagnostic collection and was stopped
after its test summary was saved; the focused rerun exited successfully.
Full-run log: `/private/tmp/nultra-ui-readiness-clean.log`.
Focused passing result: `/private/tmp/nultra-scene-readiness.xcresult`.
Temporary source snapshot: `/private/tmp/nultra-readiness-source-dfnzi3kl`.
These temporary paths may be cleared by macOS. Policy/docs and test changes remain
uncommitted. GitHub CLI sign-in is still needed for uploads; no hosted workflow
was dispatched and no release was published during verification.
