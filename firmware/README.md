# Nultra Firmware

This repository contains firmware for the Nultra product, based on an STM32WB-series MCU and a BLE peripheral example derived from ST's "BLE_Peripheral_Lite" reference application. The firmware implements a battery-powered BLE peripheral that exposes a small GATT service for a relay switch, battery level, and serial/version information. It also supports a physical button, EEPROM-backed settings, and relay control.

Table of contents
- Project summary
- Hardware
- Features
- Pins and peripherals
- Build and flash (toolchain notes)
- BLE usage and behaviour
- File layout and important sources
- Troubleshooting and notes

Project summary
This firmware implements:
- Bluetooth LE peripheral (based on STM32Cube's BLE stack)
- A simple custom GATT service (relay switch, VBATT, serial/version)
- Local name advertising which encodes relay state and battery percentage (e.g. `Nultra0XXX`)
- Button-controlled relay (short press toggles, long press shows battery LED sequence, very long press reserved for reset/DFU)
- Relay state and serial number stored in an external I2C EEPROM (AT24Cxx style)
- Battery monitoring via ADC with a piecewise mapping to percentage

Hardware
- Target: STM32WB0-series Nucleo (STM32WB0 Nucleo board referenced in example)
- External I2C EEPROM (AT24C01D / AT24Cxx family) used for storing serial number and relay state
- Relay driver pins on GPIOB
- Two user LEDs on GPIOA (red/green used for status)
- A user button (active low) on a GPIO input

Features and behavior
- BLE advertising name shows device name plus a 3-digit battery percentage and relay state encoded. The code constructs name bytes like `Nultra0XXX` or `Nultra1XXX` where the 7th character is `0` or `1` for relay OFF/ON and the last three characters are battery percentage digits.
- When connected via a BLE client (ST BLE Toolbox / custom app), the device exposes a small profile with:
	- Relay switch characteristic (read/write/notify)
	- VBATT (battery) characteristic (16-bit, percentage)
	- Serial/version characteristic (8 bytes serial + 3 bytes version)
- Short button press toggles the relay and stores state to EEPROM.
- Long button press triggers a timer-driven LED blink sequence showing battery level.
- Very long press is reserved for reset/DFU flow (commented in code).

Pins and peripherals (from `Core/Src/main.c`)
- ADC1: reads battery voltage on ADC_CHANNEL_VINM3
- I2C1: talks to the EEPROM (timing 0x00303D5B)
- TIM16: used for LED blink sequence
- IWDG: watchdog is used and refreshed in main loop
- RADIO: BLE radio peripheral initialization

GPIO summary (names used in code)
- Relay control: `relay_en_Pin`, `relay_set_Pin`, `relay_reset_Pin` (GPIOB)
- LEDs: `led_r_Pin`, `led_g_Pin` (GPIOA)
- Button: `button_Pin` (GPIOA, pull-up)
- EEPROM enable pin: `ee_en_Pin` (active low)

How to build and flash
This repository contains an STM32CubeIDE / Makefile build in `STM32CubeIDE/` (Debug folder) and a pre-built `Binary/` hex file. Typical build/flash workflows:

1) STM32CubeIDE (recommended for local development)
- Open `BLE_Peripheral_Lite.ioc` in STM32CubeIDE (project in `BLE_Peripheral_Lite/`)
- Build the project (Project → Build)
- Flash using the built-in debugger or a ST-LINK adapter (Run → Debug or Run → External Tools)

2) CLI (makefile present in `STM32CubeIDE/Debug`)
- If you prefer command-line, use the provided `makefile` in `STM32CubeIDE/Debug`. Example (Windows PowerShell):

```powershell
cd BLE_Peripheral_Lite/STM32CubeIDE/Debug
make all
# Flashing depends on toolchain (OpenOCD, st-flash, ST-Link CLI)
```

3) Flash a prebuilt image
- A prebuilt hex file is available at `BLE_Peripheral_Lite/Binary/BLE_Peripheral_Lite.hex`. You can flash it with `STM32_Programmer_CLI` or `st-flash`.

Example using STMicro's STM32_Programmer_CLI (replace COM port / interface as needed):

```powershell
# Example: using ST-Link over SWD (windows). Adjust paths for your setup.
STM32_Programmer_CLI -c port=SWD -w "<path-to-your-local-build>.hex" -v -rst
```

BLE usage
- Advertising name: updates periodically to include relay state and battery percent. The code constructs a local name buffer and calls `UpdateAdvDataName()` (an internal helper) to update advertisement data.
- Smartphone apps: compatible with ST BLE Toolbox / ST BLE Sensor apps for test and manual toggling.
- Behavior: notifications for the relay switch are sent periodically and when the switch changes.

File layout and important sources
- `BLE_Peripheral_Lite/` — main example project derived from ST examples. Contains project files, binary and debug outputs.
	- `Core/Src/main.c` — application main loop, peripherals init, button handling, battery monitoring, EEPROM helpers, relay control. (Primary source read for this README.)
	- `Core/Inc/*.h` — hardware config headers and macros used by the app
	- `STM32_BLE/` — BLE middleware and application glue (profiles, server implementation). Many BLE-specific sources are in this folder.
- `Binary/` — prebuilt hex images

Troubleshooting and notes
- If BLE advertising name doesn't change: ensure `UpdateAdvDataName()` is implemented and called by the BLE stack glue. On some example projects this function is part of the BLE middlewares.
- EEPROM I2C errors: check `ee_en_Pin` wiring and that the EEPROM's write-protect or chip-select lines are correctly connected. The code toggles `ee_en_Pin` low to enable the EEPROM before I2C operations.
- ADC battery reads look inverted in code (`adc_value = 4096 - adc_value`) — verify external front-end and ADC reference before trusting values.
- Watchdog resets: the code uses IWDG; if debug sessions halt execution the watchdog may reset the MCU. Pause or disable IWDG for stepwise debugging if needed.

Assumptions and TODOs
- The README is based on static inspection of `Core/Src/main.c` and the project's example README. Some BLE glue sources and header files were not opened; names like `UpdateAdvDataName()`, `PERIPHERAL_LITE_SERVER_UpdateValue()` are referenced in code and are expected to be present in the BLE middleware.
- If you want, I can:
	- extend this README with exact build steps for OpenOCD or ST-Link CLI for your environment,
	- add a sample mobile client snippet (Android/iOS) showing how to subscribe to notifications and toggle the relay,
	- extract and document exact GATT characteristic UUIDs from the BLE middleware.

License
Check the `Drivers/` and `Middlewares/` folders for license files from ST and any third-party code. The project contains ST-provided drivers and example code; ensure you comply with their licensing when distributing.
