"""Build the CubeIDE project with the GNU Arm Embedded toolchain on PATH."""
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

firmware = Path(__file__).resolve().parents[1]
project = firmware / "BLE_Peripheral_Lite"
ide = project / "STM32CubeIDE"
build = firmware / "build"
build.mkdir(exist_ok=True)

if not (project / "Core/Inc/device_credentials.h").is_file():
    raise SystemExit("Run tools/new_device.py for this switch before building.")
if not shutil.which("arm-none-eabi-gcc"):
    raise SystemExit("Add the GNU Arm Embedded toolchain to PATH.")
if not (project / "Middlewares/ST/STM32_BLE/stack/lib/stm32wb0x_ble_stack.a").is_file():
    raise SystemExit("Run tools/prepare_sdk.py with STM32CubeWB0 1.2.0 before building.")

# CubeIDE links external sources into virtual project folders. Use those same
# sources and include directories so both entry points compile the same code.
sources = sorted((ide / "Application").rglob("*.c")) + sorted((ide / "Application").rglob("*.s"))
for uri in ET.parse(ide / ".project").findall(".//linkedResources/link/locationURI"):
    path = str(uri.text)
    if path.startswith("PARENT-1-PROJECT_LOC/") and path.lower().endswith((".c", ".s")):
        sources.append(project / path.split("/", 1)[1])
options = ET.parse(ide / ".cproject").find(".//tool[@name='MCU/MPU GCC Compiler']")
includes = options.find(".//option[@valueType='includePath']")
defines = options.find(".//option[@valueType='definedSymbols']")
flags = ["-mcpu=cortex-m0plus", "-mthumb", "-mfloat-abi=soft"]
cflags = ["-Os", "-ffunction-sections", "-fdata-sections", "-std=gnu11", "-fstack-usage"]
cflags += ["-D" + e.get("value") for e in defines if e.get("value") != "DEBUG"]
cflags += ["-I" + str((ide / "Debug" / e.get("value")).resolve()) for e in includes]
objects = []
for source in sources:
    obj = build / source.relative_to(project).with_suffix(".o")
    obj.parent.mkdir(parents=True, exist_ok=True)
    objects.append(str(obj))
    subprocess.run(["arm-none-eabi-gcc", *flags, *cflags, "-x",
                    "c" if source.suffix == ".c" else "assembler-with-cpp",
                    "-c", str(source), "-o", str(obj)], check=True)
stack = project / "Middlewares/ST/STM32_BLE"
elf = build / "nultra.elf"
subprocess.run(["arm-none-eabi-gcc", *flags, "-T", str(ide / "STM32WB05KZVX_FLASH.ld"),
                "-Wl,--gc-sections,-z,noexecstack", "-Wl,--start-group", *objects,
                str(stack / "stack/lib/stm32wb0x_ble_stack.a"), str(stack / "cryptolib/libcrypto.a"),
                "-lc", "-lm", "-lnosys", "-Wl,--end-group", "--specs=nano.specs", "--specs=nosys.specs",
                "-o", str(elf)], check=True)
subprocess.run(["arm-none-eabi-objcopy", "-O", "ihex", str(elf), str(elf.with_suffix(".hex"))], check=True)
subprocess.run(["arm-none-eabi-size", str(elf)], check=True)
