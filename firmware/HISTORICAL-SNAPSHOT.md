# Historical firmware snapshot

This tree reconstructs the corresponding 2025 firmware revision for public review.
The public-history import retained application source, CubeMX project files and
the original author and commit dates. The import omitted the vendor SDK, workspace
metadata and prebuilt images. It replaced the shared device credentials with a
locally generated header and removed workstation paths and an unused address override.
The SDK setup and provisioning scripts and the accompanying ST application license
were added at import time. The original firmware developers did not author those
import changes in 2025.

From this directory, run `python tools/prepare_sdk.py <STM32CubeWB0-v1.2.0-directory>`
and `python tools/new_device.py` before building the STM32CubeIDE project. Keep the
device header and the resulting image private. For newly programmed switches, use
the current public firmware and its current pairing and upgrade instructions.

ST application files retain the ST terms in BLE_Peripheral_Lite/LICENSE.md.
The prepared SDK has component-specific notices. The later provisioning and SDK
preparation scripts use the public project's MIT software license.
