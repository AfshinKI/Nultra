# Historical packaging notes

The archive preserves the following parts of the original packaging changes.

## iOS architecture check

The original package script used this command to check the device executable.

```sh
xcrun lipo -verify_arch arm64 "$binary"
```
