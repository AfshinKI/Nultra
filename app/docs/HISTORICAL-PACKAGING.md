# Historical packaging notes

The archive preserves the following parts of the original packaging changes.

## iOS architecture check

The original package script used this command to check the device executable.

```sh
xcrun lipo "$binary" -verify_arch arm64
```
