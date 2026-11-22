# Nultra

Nultra is a Bluetooth LE wall switch designed for switch boxes without a neutral wire. One AA cell powers the control electronics. A faceplate button or the nearby iPhone and Android apps can operate the latching relay.

[Open the enclosure document in Onshape](https://cad.onshape.com/documents/3cb2e23a19093c4389ce2f07/w/3be343cdcd1e5951d1a37be1)

<img src="docs/assets/product/frames/046.webp" alt="Exploded Nultra switch, from front to back: faceplate, AA cell, carrier, populated circuit board and rear shell" width="460">

## Build and use a switch

| What you want to do | Where to start |
| --- | --- |
| Inspect, adapt or print the enclosure | [Mechanical design, STEP solids and printable STL files](hardware/mechanical/) |
| Study the circuit or inspect the original v2 manufacturing outputs | [Electronics, KiCad review findings and archived fabrication files](hardware/README.md#electronics) |
| Build firmware for the STM32WB05KZ and provision a switch | [Firmware build and pairing](firmware/README.md) |
| Control a switch from a phone | [iOS and Android setup](app/README.md) |

Start with the firmware guide when building a new unit. It generates a separate pairing PIN and command password for each switch. Keep the generated header and firmware image private. Owners upgrading older devices should provision fresh credentials, clear old Bluetooth bonds and pair their controllers again.

The KiCad project is an editable conversion with outstanding connectivity findings. For example, the archived v2 board assigns the positive battery contact to `VBATT`, but the corresponding numbered pad is missing in the conversion. Check the archived fabrication files before ordering a changed board. The STEP and STL files can be opened independently of SolidWorks. [Hardware notes](hardware/README.md)

## Project site

The 3D demo opens the Nultra iPhone app and taps Desk Lamp to light the room. On a fresh visit, the camera approaches the mounted switch. Three pairs of magnets release as the faceplate lifts away. The switch stays secured by two screws while a callout identifies the AA cell and shows its discharge profile. Then the screws back out, the uncovered switch comes forward, and the AA cell lifts out before the carrier, board and shell separate. [Interactive room renderer](docs/room.js) · [Path-traced teardown renderer](tools/render_wall_teardown.py) · [Room artwork and prompts](tools/room_artwork.md)

The camera identifies the printed antenna, Bluetooth CPU and SWD debug pads on the front of the PCB. It slows on the reverse to show the DC/DC converter, latching relay and AC load terminal. After one full tour, the callouts clear, the sequence rewinds to the room and the opening lamp demo loops. Scrolling takes over at the current view. The chapter buttons and slider also work with reduced motion. Replay tour starts the sequence again, using stills when reduced motion is enabled. Each demonstration below the tour has its own replay control for the tactile button, battery indicator, cell replacement or companion app. [Render script](tools/render_product.py) · [AA model preparation](tools/prepare_render_battery.py)

J5 carries SWDIO and SWCLK. U1 is the STM32WB05KZ Bluetooth MCU. On the opposite side, U4 is the TPS613221A boost converter and R5 is the Panasonic AGQ21TA2H latching relay. [V2 pad connections](hardware/electronics/fabrication/v2/Nultra-v2-pad-connections.csv) · [V2 bill of materials](hardware/electronics/fabrication/v2/Nultra-v2-BOM.csv)

The AA discharge graph uses the firmware’s voltage-to-charge lookup table, from 1.65 V at 100% to 0.65 V at 0%. The firmware requests a 2 ms pulse to change the latching relay, then disables the drive. The relay holds its position with its coil unpowered. The controller can sleep between radio events. [Battery estimate](firmware/BLE_Peripheral_Lite/Core/Src/main.c#L702) · [Relay drive](firmware/BLE_Peripheral_Lite/Core/Src/main.c#L887) · [Controller sleep](firmware/BLE_Peripheral_Lite/Core/Src/app_entry.c#L310)

The close-up in the build-files section was path traced from the Altium board and the positioned AA cell using a thin-lens camera focused on the microcontroller. [Board photograph renderer](tools/render_board_detail.py)

To preview the site locally, run `python -m http.server --bind 127.0.0.1 --directory docs 8000` from the repository root.

## Development history

Firmware development began in March 2025. The public archive preserves the original commit dates and merges. Device credentials and compiled firmware images were omitted from those revisions. [Browse the 2025 firmware commits](https://github.com/AfshinKI/Nultra/commits/d4c3cc2b9a1dbfadcdf72ec14c10238a79e72ddd/)

The September 2026 mobile app commits follow the iPhone and Android controllers through Bluetooth pairing, scenes and home-screen widgets. These archived revisions omit shared credentials and private distribution files. [Browse the mobile app commits](https://github.com/AfshinKI/Nultra/commits/8fd76693fbb15d21747a63de8b6250752ec708d2/)

## Licenses

The original Nultra hardware uses CERN-OHL-P-2.0. Original software and documentation use MIT. The ST-derived firmware files retain ST’s SLA0044 terms, including its ST-hardware restriction. The license notice identifies those files and other third-party materials. [License scope and notices](LICENSE)
