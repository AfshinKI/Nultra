"""Render the scroll sequence and its projected CAD label anchors.

Run from any directory with Python 3.12, mitsuba==3.9.1, numpy and Pillow.
"""
import argparse
import json
import math
from pathlib import Path

import drjit as dr
import mitsuba as mi
import numpy as np
from PIL import Image, ImageFilter

mi.set_variant("llvm_ad_rgb")
ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs" / "assets"
DEST = ASSETS / "assembly"
COUNT = 49
WIDTH, HEIGHT = 920, 820
COLORS = {
    "faceplate": [0.80, 0.81, 0.80], "wordmark": [0.045, 0.05, 0.052],
    "carrier": [0.23, 0.28, 0.30], "shell": [0.09, 0.115, 0.135],
    "pcb": [0.025, 0.185, 0.105], "pads": [0.80, 0.53, 0.16],
    "traces": [0.064, 0.32, 0.166]
}
TRAVEL = {"faceplate": 62, "wordmark": 62, "carrier": 13, "pcb": -26, "shell": -67}


def unit(vector):
    return vector / np.linalg.norm(vector)


def camera(progress):
    yaw = math.radians(34 + 20 * progress)
    pitch = math.radians(16 + 2 * progress)
    direction = np.array([math.sin(yaw)*math.cos(pitch), math.sin(pitch), math.cos(yaw)*math.cos(pitch)])
    right = unit(np.cross([0, 1, 0], direction))
    up = unit(np.cross(direction, right))
    roll = math.radians(-10 + 5 * progress)
    right, up = right*math.cos(roll) + up*math.sin(roll), up*math.cos(roll) - right*math.sin(roll)
    target = np.array([0., 0., 10. + 2 * progress])
    half_w = 79 + 27 * progress
    half_h = half_w * HEIGHT / WIDTH
    return direction, right, up, target, half_w, half_h


def light(position, size, strength):
    transform = mi.ScalarTransform4f.look_at(origin=position, target=[0, 0, 0], up=[0, 1, 0])
    return {"type": "rectangle", "to_world": transform @ mi.ScalarTransform4f.scale([size, size, 1]),
            "emitter": {"type": "area", "radiance": {"type": "rgb", "value": strength}}}


def mesh(data, travel):
    verts = np.asarray(data["positions"], dtype=np.float32).reshape(-1, 3).copy()
    verts[:, 2] += travel
    faces = np.asarray(data["indices"], dtype=np.uint32).reshape(-1, 3)
    material = mi.load_dict({"type": "twosided", "material": {"type": "roughplastic", "alpha": 0.24,
                            "diffuse_reflectance": {"type": "rgb", "value": COLORS[data["id"]]}}})
    props = mi.Properties()
    props["bsdf"] = material
    obj = mi.Mesh(data["id"], len(verts), len(faces), props)
    params = mi.traverse(obj)
    params["vertex_positions"] = verts.ravel()
    params["faces"] = faces.ravel()
    params.update()
    return obj


def render(parts, index, samples):
    p = index / (COUNT - 1)
    direction, right, up, target, half_w, half_h = camera(p)
    cam = mi.ScalarTransform4f.look_at(origin=(target + direction*450).tolist(), target=target.tolist(), up=up.tolist())
    scene = {
        "type": "scene",
        "integrator": {"type": "path", "max_depth": 4, "hide_emitters": True},
        "sensor": {"type": "orthographic", "to_world": cam @ mi.ScalarTransform4f.scale([half_w,half_w,1]),
                   "sampler": {"type":"independent", "sample_count": samples},
                   "film": {"type":"hdrfilm", "width":WIDTH, "height":HEIGHT, "pixel_format":"rgba",
                            "rfilter": {"type": "tent"}}},
        "key": light([-70, 155, 180], 110, [2.6, 2.45, 2.25]),
        "softbox": light([130, 25, 115], 100, [1.02, 1.2, 1.45]),
        "rim": light([35, 140, -155], 110, [2.2, 2.4, 2.6]),
        "ambient": {"type":"constant","radiance":{"type":"rgb","value":[0.16,0.18,0.21]}}
    }
    anchors = {}
    for part in parts:
        travel = TRAVEL[part["id"]] * p
        for layer in [part, *part.get("details", [])]:
            scene[layer["id"]] = mesh(layer, travel)
        a = np.array(part["anchor"]) + [0,0,travel] - target
        anchors[part["id"]] = [round(float(0.5 + np.dot(a,right)/(2*half_w)),5),
                               round(float(0.5 - np.dot(a,up)/(2*half_h)),5)]
    output = np.asarray(mi.render(mi.load_dict(scene), spp=samples, seed=791))
    alpha = np.clip(output[:,:,3:4], 0, 1)
    rgb = np.clip(output[:,:,:3] / np.maximum(alpha, 1e-6), 0, 5)
    # A fixed, gentle shoulder preserves definition in the white printed face.
    rgb = rgb / (1 + 0.32*rgb)
    srgb = np.where(rgb <= 0.0031308, 12.92*rgb, 1.055*np.maximum(rgb,0)**(1/2.4)-0.055)
    rgba = np.concatenate([np.clip(srgb,0,1),alpha], axis=2)
    image = Image.fromarray(np.uint8(rgba*255 + 0.5))
    softened = image.convert("RGB").filter(ImageFilter.MedianFilter(size=3))
    color = Image.blend(image.convert("RGB"), softened, 0.72)
    color.putalpha(image.getchannel("A"))
    color.save(DEST/f"{index:02d}.webp", quality=88, method=4)
    return anchors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=80)
    parser.add_argument("--frames", type=int, nargs="+", default=list(range(COUNT)))
    args = parser.parse_args()
    parts = json.loads((ASSETS / "switch.json").read_text())["parts"]
    DEST.mkdir(exist_ok=True)
    dr.set_thread_count(min(16, dr.thread_count()))
    anchors = {}
    for i in args.frames:
        if not 0 <= i < COUNT:
            parser.error("frame index outside sequence")
        anchors[str(i)] = render(parts, i, args.samples)
        print(f"Rendered {i:02d}", flush=True)
    if len(anchors) == COUNT:
        (DEST / "anchors.json").write_text(json.dumps(anchors,separators=(",",":"))+"\n")
