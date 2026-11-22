"""Photograph the populated Altium board for the build-files section.

Uses the Mitsuba installation and Altium OBJ/MTL described in render_product.py.
"""
import argparse
from pathlib import Path

import drjit as dr
import mitsuba as mi
import numpy as np
from PIL import Image

from render_product import ASSETS, axes, light, mesh_object, read_board, read_cell, surface


def photograph(obj, battery, dest, width, samples):
    board, palette = read_board(obj)
    cell, _ = read_cell(battery)
    top = np.array([1., 14., 1.4])
    look, right, up = axes(16, -37, 52)
    eye = top + look * 125
    scene = {"type": "scene", "integrator": {"type": "path", "max_depth": 8}}
    finishes = {mat: surface(mat, palette) for _, mat, _, _ in board + cell}
    for index, (part, mat, vertices, faces) in enumerate(board + cell):
        if part in {"pcb", "battery"}:
            scene[f"component-{index}"] = mesh_object(index, vertices, faces, finishes[mat])
    # The tripod looks across the packages. The point of focus is the MCU lead frame.
    height = round(width * 2 / 3)
    camera = mi.ScalarTransform4f.look_at(origin=eye.tolist(), target=top.tolist(), up=up.tolist())
    scene["camera"] = {
        "type": "thinlens", "to_world": camera, "fov": 21, "fov_axis": "x",
        "aperture_radius": 2.15, "focus_distance": float(np.linalg.norm(eye - [2.68, 15.46, 1.419])),
        "sampler": {"type": "independent"},
        "film": {"type": "hdrfilm", "width": width, "height": height, "rfilter": {"type": "tent"}},
    }
    back = min(float(v[:, 2].min()) for part, _, v, _ in board if part == "pcb")
    scene["bench"] = {
        "type": "rectangle",
        "to_world": mi.ScalarTransform4f.translate([0, 0, back - .08]) @ mi.ScalarTransform4f.scale([1000, 1000, 1]),
        "bsdf": {"type": "diffuse", "reflectance": {"type": "rgb", "value": [.031, .029, .030]}},
    }
    def panel(offset, scale, energy):
        x, y, z = offset
        return light(top, right*x + up*y + look*z, scale, energy)
    scene.update({
        "window": panel([70, 54, 83], [52, 53], [5.8, 5.50, 5.12]),
        "bounce": panel([-72, 17, 75], [48, 54], [.82, .90, 1.02]),
        "strip": panel([-48, 67, 52], [43, 6], [4.8, 4.45, 4.0]),
        "rim": panel([-25, -82, 33], [12, 35], [1.62, 1.32, 1.06]),
        "ambient": {"type": "constant", "radiance": {"type": "rgb", "value": [.074, .075, .080]}},
    })
    scene = mi.load_dict(scene)
    total = np.zeros((height, width, 3), dtype=np.float32)
    for start in range(0, samples, 8):
        batch = min(8, samples-start)
        total += np.asarray(mi.render(scene, spp=batch, seed=2431+start)) * batch
    linear = total / samples
    if mi.variant() == "cuda_ad_rgb":
        denoiser = mi.OptixDenoiser([width, height])
        linear = .985*np.asarray(denoiser(mi.TensorXf(linear))) + .015*linear
    rgb = np.maximum(0, linear)
    rgb = rgb / (1 + .22*rgb)
    srgb = np.where(rgb < .0031308, 12.92*rgb, 1.055*rgb**(1/2.4)-.055)
    Image.fromarray(np.uint8(np.clip(srgb*255+.5, 0, 255))).save(dest, quality=90, method=6)
    dr.flush_malloc_cache()


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("obj", type=Path)
    ap.add_argument("--battery", required=True, type=Path, help="Positioned AA mesh from prepare_render_battery.py")
    ap.add_argument("--dest", type=Path, default=ASSETS / "product" / "engineering.webp")
    ap.add_argument("--width", type=int, default=1440)
    ap.add_argument("--spp", type=int, default=160)
    ap.add_argument("--variant", choices=["cuda_ad_rgb", "llvm_ad_rgb"], default="cuda_ad_rgb")
    args = ap.parse_args()
    if args.width < 2 or args.spp < 1:
        ap.error("Width must be at least 2 pixels and sample count must be positive.")
    mi.set_variant(args.variant)
    photograph(args.obj, args.battery, args.dest, args.width, args.spp)
