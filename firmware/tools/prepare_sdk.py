"""Copy the STM32CubeWB0 1.2.0 dependencies used by the CubeIDE project."""
import argparse
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("sdk", type=Path, help="root of the extracted (or recursively cloned) vendor package")
sdk = parser.parse_args().sdk.resolve()
project = Path(__file__).resolve().parents[1] / "BLE_Peripheral_Lite"

try:
    release = ET.parse(sdk / "package.xml").find("PackDescription").get("Release")
except (OSError, AttributeError, ET.ParseError):
    raise SystemExit("Expected package.xml in the supplied STM32CubeWB0 directory.")
if release != "FW.WB0.1.2.0":
    raise SystemExit(f"Expected FW.WB0.1.2.0, found {release}.")

directories = (
    "Drivers/CMSIS/Include",
    "Drivers/CMSIS/Device/ST/STM32WB0X/Include",
    "Drivers/STM32WB0x_HAL_Driver/Inc",
    "Drivers/STM32WB0x_HAL_Driver/Src",
    "Drivers/BSP/STM32WB0x-nucleo",
    "Middlewares/ST/STM32_BLE",
    "Projects/Common/BLE",
    "Utilities/misc",
    "Utilities/lpm/tiny_lpm",
    "Utilities/trace/adv_trace",
)
for directory in directories:
    if not (sdk / directory).is_dir():
        raise SystemExit(f"Missing {directory}. For a Git checkout, initialize the SDK submodules.")
for directory in directories:
    shutil.copytree(sdk / directory, project / directory, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".git", "*.chm", "_htmresc"))
# Ubuntu's bare-metal GCC uses a different stdint.h guard from the one
# this SDK checks. Its standard types are already defined in config.h.
types = project / "Middlewares/ST/STM32_BLE/cryptolib/Inc/Common/types.h"
guard = "!defined(_STDINT_H) && !defined(__stdint_h) && !defined(_STDINT)"
types.write_text(types.read_text().replace("#if " + guard, "#if " + guard + " && !defined(_GCC_STDINT_H)"))
print("Prepared STM32CubeWB0 1.2.0 dependencies.")
