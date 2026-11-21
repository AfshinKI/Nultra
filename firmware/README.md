# Switch firmware

Nultra 1.5.1 runs on the STM32WB05KZ. It controls a latching relay, measures battery voltage, remembers the relay state and serial number in an I²C EEPROM, and serves nearby controllers over Bluetooth LE.

## Build for one switch

Install Python 3.8 or later and the GNU Arm Embedded toolchain with newlib. The release was compiled and linked with Arm GCC 13.2. The SDK version used by this design is STM32CubeWB0 1.2.0. The following commands run from the firmware directory.

```sh
git clone --recursive --shallow-submodules --depth 1 --branch v1.2.0 https://github.com/STMicroelectronics/STM32CubeWB0.git ../../STM32CubeWB0
python3 tools/prepare_sdk.py ../../STM32CubeWB0
python3 tools/new_device.py
python3 tools/build.py
```

You can point `prepare_sdk.py` at the same version installed by STM32CubeMX. Keep the SDK checkout outside the public repository when preparing a release. For STM32CubeIDE, run the preparation and credential steps, then import the existing project in `BLE_Peripheral_Lite/STM32CubeIDE` and build the Release configuration. The checked-in C files contain the application logic and security handlers. CubeMX regeneration requires reapplying and reviewing those changes.

The build writes a device-specific `build/nultra.hex`. Use an ST-LINK with the board's SWD interface and STM32CubeProgrammer to program the image, verify it and reset the board. The firmware and its generated configuration both contain this device's credentials. Store them privately and build a fresh image for each additional switch. The credential generator refuses to overwrite an existing header.

## Pair and control

1. Read the six-digit pairing PIN and eight-character command password in `BLE_Peripheral_Lite/Core/Inc/device_credentials.h`. Give them to the switch owner privately.
2. Hold the physical button for two seconds and release it. The battery indicator flashes, and the device allows one pairing attempt during the next 60 seconds.
3. Connect from a controller, enter the command password and enter the pairing PIN when the operating system asks. A previously bonded controller can reconnect without pressing the button. The command password is required for each new connection.
4. Tap the physical button to toggle the relay. A two-second hold also displays the battery level, and a ten-second hold resets the processor on release.

An upgrade from the original firmware requires a new device-specific build. Erase the old Bluetooth bonds on the switch and controller during the upgrade, then pair again. Clearing the MCU's flash also removes its stored bonds. The external EEPROM holds the relay settings.

## Data on the air

Advertising includes the relay state and battery level in the local name. The relay, battery and serial/version values are readable over BLE. Configuring the relay and writing the serial number require an authenticated LE Secure Connections link and the command password for the current connection.

| Characteristic | Data |
| --- | --- |
| Relay | One byte, 0 for off or 1 for on |
| Relay notification | Relay state after authentication, otherwise 0xFF |
| Battery | Unsigned one-byte percentage |
| Serial/version | Reads return eight little-endian serial bytes followed by major, minor and patch. Authenticated writes accept eight serial bytes or the full eleven-byte value. The firmware preserves its version. |
| Command password | Eight ASCII bytes, write only |

## License and dependencies

The ST-derived application files in `BLE_Peripheral_Lite` carry ST's SLA0044. It permits source redistribution under its stated conditions and restricts execution to ST hardware. The independent Python tools use the repository's software license. The SDK, including its precompiled Bluetooth and crypto libraries, is obtained separately from ST under its component terms. [Application license](BLE_Peripheral_Lite/LICENSE.md) · [ST package and component licenses](https://github.com/STMicroelectronics/STM32CubeWB0/blob/v1.2.0/LICENSE.md)
