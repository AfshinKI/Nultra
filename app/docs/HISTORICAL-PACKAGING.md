# Historical packaging notes

The archive preserves the following parts of the original packaging changes.

## iOS architecture check

The original package script used this command to check the device executable.

```sh
xcrun lipo "$binary" -verify_arch arm64
```

## Android build record

The Android package script produced a signed installation package. Signing setup and distribution artifacts were omitted during the archive import.
