#!/usr/bin/env python3
"""Package the generated artwork into Apple's required iPhone icon sizes."""
import json
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1] / "Nultra/Assets.xcassets"
source = root / "BrandMark.imageset/BrandMark.png"
info = {"author": "xcode", "version": 1}
(root / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
(root / "BrandMark.imageset/Contents.json").write_text(json.dumps({"images": [{"filename": "BrandMark.png", "idiom": "universal"}], "info": info}, indent=2) + "\n")
images = []
for points, scales, idiom in [(20, [2, 3], "iphone"), (29, [2, 3], "iphone"), (40, [2, 3], "iphone"), (60, [2, 3], "iphone"), (1024, [1], "ios-marketing")]:
    for scale in scales:
        pixels = points * scale
        filename = f"Icon-{points}@{scale}x.png"
        subprocess.run(["sips", "-z", str(pixels), str(pixels), str(source), "--out", str(root / "AppIcon.appiconset" / filename)], check=True, stdout=subprocess.DEVNULL)
        images.append({"filename": filename, "idiom": idiom, "size": f"{points}x{points}", "scale": f"{scale}x"})
(root / "AppIcon.appiconset/Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
print(f"Packaged {len(images)} opaque iPhone icons")
