# Historical packaging notes

The archive preserves the following parts of the original packaging changes.

## iOS architecture check

The original package script used this command to check the device executable.

```sh
xcrun lipo "$binary" -verify_arch arm64
```

## Android build record

The Android package script produced a signed installation package. Signing setup and distribution artifacts were omitted during the archive import.

## iOS installation host compatibility

The original feasibility notes proposed checking Linux ARM userspace and binary compatibility before moving an installation service. They called for an owner-approved USB pairing trial and keeping the working installation available during testing. They recorded no successful migration. The archive omits local host configuration and deployment details.
