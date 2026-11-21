"""Render the product site's transparent WebP photography from an Altium OBJ/MTL.

Requires Python 3.12, mitsuba==3.9.1, numpy and Pillow. Example:
    python tools/render_product.py /path/to/Nultra.obj --battery /path/to/placed-cell.npz

The source OBJ is an offline input. GitHub Pages serves the finished renders.
Use --variant llvm_ad_rgb on a CPU with LLVM, or cuda_ad_rgb with NVIDIA OptiX.
"""
import argparse
import json
import math
import shutil
from collections import defaultdict
from pathlib import Path

import drjit as dr
import mitsuba as mi
import numpy as np
from PIL import Image, ImageFilter

ASSETS = Path(__file__).resolve().parents[1] / "docs" / "assets"
FRAME_COUNT = 73
TRAVEL = {"faceplate": 107, "wordmark": 107, "battery": 62, "carrier": 16, "pcb": -29, "shell": -85}


def read_board(obj):
    vertices = []
    faces = defaultdict(list)
    colors = {}
    with obj.open(encoding="utf-8-sig") as src:
        for line in src:
            tag, _, rest = line.strip().partition(" ")
            if tag == "mtllib":
                for row in obj.with_name(rest).read_text().splitlines():
                    key, _, value = row.partition(" ")
                    if key == "newmtl":
                        material = value.strip()
                    elif key == "Kd":
                        colors[material] = tuple(map(float, value.split()[:3]))
            elif tag == "v":
                vertices.append(tuple(map(float, rest.split()[:3])))
            elif tag == "g":
                group = rest
            elif tag == "o":
                name = rest
            elif tag == "usemtl":
                material = rest
            elif tag == "f":
                indices = [int(item.split("/")[0]) for item in rest.split()]
                indices = [v-1 if v > 0 else len(vertices)+v for v in indices]
                # Nets and large copper pours sit under the translucent solder mask.
                finish = "traces" if material == "copper" and (group == "Nets" or name == "PolyRegion") else material
                if group == "Components" and name == "*" and material == "copper":
                    finish = "antenna"
                for i in range(1, len(indices)-1):
                    faces[finish].append((indices[0], indices[i], indices[i+1]))
    # This Altium OBJ uses cm. Align the PCB top with the existing enclosure's PCB datum.
    xyz = np.asarray(vertices, dtype=np.float32) * 10
    xyz[:, 2] += .87
    meshes = []
    for material, triangles in faces.items():
        ids, remap = np.unique(np.asarray(triangles, dtype=np.uint32).ravel(), return_inverse=True)
        meshes.append(("pcb", material, xyz[ids].copy(), remap.astype(np.uint32)))
    return meshes, colors


def read_housing():
    pieces = json.loads((ASSETS / "switch.json").read_text())["parts"]
    meshes = [(p["id"], p["id"], np.asarray(p["positions"], dtype=np.float32).reshape(-1, 3),
               np.asarray(p["indices"], dtype=np.uint32)) for p in pieces if p["id"] != "pcb"]
    anchors = {p["id"]: np.asarray(p["anchor"], dtype=float) for p in pieces}
    anchors["pcb"] = np.array([2.6, 15.3, 1.4])  # MCU on the populated face.
    anchors["mcu"] = np.array([2.68,15.46,1.419])  # U1, upper package face.
    anchors["testpoint"] = np.array([7.74,21.81,2.00])  # J3, packaged test point.
    anchors["antenna"] = np.array([-4.005,26.611,.784])  # Interior of the IFA_CC2430DB copper arm.
    return meshes, anchors


def read_cell(path):
    # prepare_render_battery.py tessellates the supplied STEP in its saved position.
    with np.load(path, allow_pickle=False) as data:
        xyz = data["positions"].astype(np.float32)
        triangles = data["indices"].reshape(-1, 3)
        assigned = data["face_material"].reshape(-1)
    finishes = ("cell-body", "cell-copper", "cell-pole", "cell-seal")
    if len(assigned) != len(triangles) or not set(np.unique(assigned)).issubset(range(len(finishes))):
        raise ValueError("Expected one indexed battery finish per triangle")
    meshes = []
    for n, finish in enumerate(finishes):
        selected = triangles[assigned == n]
        if selected.size:
            vertices, indices = np.unique(selected.ravel(), return_inverse=True)
            meshes.append(("battery", finish, xyz[vertices].copy(), indices.astype(np.uint32)))
    center = (xyz.min(axis=0) + xyz.max(axis=0)) / 2
    anchor = center.copy()
    anchor[2] = xyz[:, 2].max() - .8
    return meshes, anchor


def srgb_to_linear(c):
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def surface(name, colors):
    # Linear reflectances under studio light. White solder mask, black silkscreen
    # and plated pads follow the source MTL. Metal package finishes have a broad highlight.
    finishes = {
        "solder_t": ((.70, .71, .65), .27, .04), "solder_b": ((.70, .71, .65), .27, .04),
        "core": ((.18, .15, .090), .34, .04), "traces": ((.40, .42, .35), .32, .18),
        "copper": ((.88, .61, .255), .23, .86), "silk_t": ((.014, .018, .017), .48, 0),
        "antenna": ((.94, .63, .24), .23, .87),
        "silk_b": ((.014, .018, .017), .48, 0),
        "faceplate": ((.76, .77, .72), .24, .06), "wordmark": ((.055, .059, .051), .34, .1),
        "carrier": ((.24, .27, .25), .31, .08), "shell": ((.16, .18, .17), .33, .09),
        "mat_29": ((.57, .61, .60), .23, .88), "mat_30": ((.78, .81, .79), .21, .90),
        "mat_31": ((.70, .72, .69), .20, .93), "mat_17": ((.20,.22,.19),.27,.15),
        "mat_27": ((.033, .037, .036), .40, .07),
        "cell-body": ((.035, .036, .034), .28, .58),
        "cell-copper": ((.69, .33, .125), .21, .78),
        "cell-pole": ((.65, .68, .65), .21, .86),
        "cell-seal": ((.055, .056, .046), .50, .03),
    }
    if name in finishes:
        rgb, rough, metal = finishes[name]
    else:
        rgb = srgb_to_linear(np.asarray(colors[name])) * .82
        rough, metal = (.23, .75) if name in {"mat_18","mat_20","mat_23","mat_24","mat_28","mat_37"} else (.34,.10)
    return mi.load_dict({"type": "twosided", "material": {"type": "principled",
                         "base_color": {"type": "rgb", "value": list(rgb)},
                         "roughness": rough, "metallic": metal}})


def mesh_object(index, xyz, faces, material):
    props = mi.Properties()
    props["bsdf"] = material
    mesh = mi.Mesh(f"surface-{index}", len(xyz), len(faces)//3, props)
    params = mi.traverse(mesh)
    params["vertex_positions"] = xyz.ravel()
    params["faces"] = faces
    params.update()
    return mesh


def normalized(v):
    return v / np.linalg.norm(v)


def axes(yaw, pitch, roll):
    y, p, r = np.radians([yaw, pitch, roll])
    look = np.array([math.sin(y)*math.cos(p), math.sin(p), math.cos(y)*math.cos(p)])
    right = normalized(np.cross([0, 1, 0], look))
    up = normalized(np.cross(look, right))
    return look, right*math.cos(r) + up*math.sin(r), up*math.cos(r) - right*math.sin(r)


def light(center, position, scale, radiance):
    position = center + position
    transform = mi.ScalarTransform4f.look_at(origin=position.tolist(), target=center.tolist(), up=[0,1,0])
    return {"type":"rectangle", "to_world":transform @ mi.ScalarTransform4f.scale([*scale,1]),
            "emitter":{"type":"area", "radiance":{"type":"rgb","value":radiance}}}


def eased(value):
    t = max(0.,min(1.,value))
    return t*t*(3.-2.*t)


def assembly_offsets(index):
    # Remove the faceplate by itself. Hold the rest in its installed position for
    # the reveal, then lift the cell out in front of the carrier before opening the back.
    front = eased((index-18)/12)
    cell = eased((index-32)/10)
    back = eased((index-36)/10)
    face_travel = 67*front + (TRAVEL["faceplate"]-67)*eased((index-32)/14)
    return {"faceplate":face_travel, "wordmark":face_travel, "battery":TRAVEL["battery"]*cell,
            "carrier":TRAVEL["carrier"]*back, "pcb":TRAVEL["pcb"]*back, "shell":TRAVEL["shell"]*back}


def shot_layout(meshes, shot, size, index):
    width, height = size
    aspect = width/height
    orbit = eased(index/18)
    peel = eased((index-18)/12) if shot == "sequence" else 0.
    back = eased((index-36)/10) if shot == "sequence" else 0.
    inspect = eased((index-46)/26) if shot == "sequence" else 0.
    if shot == "sequence":
        look, right, up = axes(-43+76*orbit+23*peel+2*back-37*inspect,
                               13+5*orbit-4*peel+2*inspect, -15+7*orbit+6*peel-9*inspect)
    elif shot == "hero":
        look, right, up = axes(35, 19, 27)
    else:
        look, right, up = axes(28, 30, -23)
    displayed = meshes if shot == "sequence" else [layer for layer in meshes if layer[0] in {"pcb", "battery"}]
    layers = []
    offsets = assembly_offsets(index if shot=="sequence" else 0)
    shifts = {part:np.array([0,0,distance],dtype=np.float32) for part,distance in offsets.items()}
    for part,delta in {"faceplate":(-145,0,8),"wordmark":(-145,0,8),"carrier":(-115,0,7),
                       "shell":(150,0,-16),"battery":(-4,0,TRAVEL["pcb"]-TRAVEL["battery"])}.items():
        shifts[part] += np.array(delta,dtype=np.float32)*inspect
    for part, _, xyz, _ in displayed:
        layers.append(xyz+np.array([0,0,offsets[part]],dtype=np.float32))
    xyz = np.concatenate(layers)
    xs, ys = xyz @ right, xyz @ up
    half_w = max(np.ptp(xs), np.ptp(ys)*aspect) / 2
    half_w *= 1.15 if shot == "sequence" else 1.08
    center = right*(xs.min()+xs.max())/2 + up*(ys.min()+ys.max())/2 + look*np.mean(xyz @ look)
    if inspect:
        center = (1-inspect)*center + inspect*np.array([2.,18.,1.+TRAVEL["pcb"]])
        half_w = (1-inspect)*half_w + inspect*24.
    if shot == "detail":
        center = np.array([2, 15, 1.2])
        half_w = 21.0
    return displayed, shifts, inspect, look, right, up, center, half_w


def project_anchors(anchors, shifts, right, up, center, half_w, aspect):
    projected = {}
    for key, anchor in anchors.items():
        if key == "wordmark":
            continue
        relative = anchor + shifts.get(key,shifts["pcb"]) - center
        projected[key] = [round(.5+float(relative @ right)/(2*half_w),5),
                          round(.5-float(relative @ up)*aspect/(2*half_w),5)]
    return projected


def render(meshes, colors, anchors, target_file, shot, size, samples, index=0):
    width, height = size
    displayed, shifts, inspect, look, right, up, center, half_w = shot_layout(meshes,shot,size,index)
    scene = {"type":"scene", "integrator":{"type":"path","max_depth":5,"hide_emitters":True}}
    # Fade the Altium solder mask for the inspection camera so the etched antenna is visible.
    mask = mi.load_dict({"type":"mask","opacity":.87-.64*inspect,"nested":colors["solder_t"]})
    for i,(part, mat, xyz, tri) in enumerate(displayed):
        scene[f"shape-{i}"] = mesh_object(i,xyz+shifts[part],tri,mask if mat=="solder_t" else colors[mat])
    camera = mi.ScalarTransform4f.look_at(origin=(center+look*450).tolist(), target=center.tolist(), up=up.tolist())
    # Feather the main light across the PCB and give the AA sleeve an edge reflection.
    scene.update({
        "camera":{"type":"orthographic","to_world":camera @ mi.ScalarTransform4f.scale([half_w,half_w,1]),
              "sampler":{"type":"independent","sample_count":samples},
              "film":{"type":"hdrfilm","width":width,"height":height,"pixel_format":"rgba","rfilter":{"type":"tent"}}},
        "key":light(center,[-87,113,125],[82,58],[3.8,3.50,3.20]),
        "fill":light(center,[95,-36,122],[64,84],[1.15,1.27,1.31]),
        "rim":light(center,[44,90,-94],[30,72],[2.45,2.73,2.65]),
        "edge":light(center,[-112,-53,-71],[22,75],[1.45,1.26,.88]),
        "strip":light(center,[-105,10,77],[8,80],[2.6,2.75,2.82]),
        "ambient":{"type":"constant","radiance":{"type":"rgb","value":[.13,.145,.14]}}
    })
    scene = mi.load_dict(scene)
    # Bounded render batches fit consumer GPUs; a fixed sample pattern suppresses shimmer.
    total = None
    batch = max(1, min(8, 5500000 // (width*height)))
    for first in range(0, samples, batch):
        n = min(batch, samples-first)
        image = np.array(mi.render(scene, spp=n, seed=791+first), copy=True)
        if total is None:
            total = image*n
        else:
            total += image*n
    rgba = total / samples
    alpha = np.clip(rgba[:,:,3:4],0,1)
    beauty = np.ascontiguousarray(rgba[:,:,:3])
    if mi.variant() == "cuda_ad_rgb":
        denoiser = mi.OptixDenoiser([width,height])
        denoised = denoiser(mi.TensorXf(beauty))
        beauty = np.array(denoised)*.98 + .02*beauty
    rgb = np.maximum(beauty / np.maximum(alpha,1e-5),0)
    rgb = rgb / (1 + .22*rgb)
    rgb = np.where(rgb < .0031308,12.92*rgb,1.055*rgb**(1/2.4)-.055)
    pixels = np.uint8(255*np.clip(np.concatenate([rgb,alpha],axis=2),0,1)+.5)
    target_file.parent.mkdir(parents=True,exist_ok=True)
    image = Image.fromarray(pixels)
    cleaned = image.convert("RGB").filter(ImageFilter.MedianFilter(3))
    cleaned.putalpha(image.getchannel("A"))
    cleaned.save(target_file,quality=84 if shot == "sequence" else 91,method=5)
    if shot != "sequence" and width >= 768:
        mobile = cleaned.resize((768,round(height*768/width)),Image.Resampling.LANCZOS)
        mobile.save(target_file.with_name(f"{shot}-768.webp"),quality=85,method=5)
    del scene
    dr.flush_malloc_cache()
    return project_anchors(anchors,shifts,right,up,center,half_w,width/height)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("obj", type=Path)
    ap.add_argument("--battery", required=True, type=Path, help="Positioned AA mesh from prepare_render_battery.py")
    ap.add_argument("--variant", default="cuda_ad_rgb", choices=["cuda_ad_rgb","llvm_ad_rgb","scalar_rgb"])
    ap.add_argument("--dest",type=Path,default=ASSETS/"product")
    ap.add_argument("--shots",nargs="+",choices=["hero","detail","sequence"], default=["hero","detail","sequence"])
    ap.add_argument("--frames",nargs="+",type=int,default=list(range(FRAME_COUNT)))
    ap.add_argument("--spp",type=int,help="Override the default sampling rate")
    ap.add_argument("--scale",type=float,default=1)
    args = ap.parse_args()
    if args.scale<=0 or args.spp is not None and args.spp<1 or any(f not in range(FRAME_COUNT) for f in args.frames):
        ap.error(f"Raster scale and samples must be positive; frame indices must be 0–{FRAME_COUNT-1}.")
    mi.set_variant(args.variant)
    board, materials = read_board(args.obj)
    housing, anchors = read_housing()
    cell, anchors["battery"] = read_cell(args.battery)
    meshes = housing + board + cell
    finishes = {mat:surface(mat,materials) for _,mat,_,_ in meshes}
    for shot in args.shots:
        w,h = {"hero":(1440,1200),"detail":(1440,960),"sequence":(1056,864)}[shot]
        dim = (round(w*args.scale),round(h*args.scale))
        coordinates = {}
        for i in args.frames if shot=="sequence" else [0]:
            dest = args.dest/"frames"/f"{i:03d}.webp" if shot=="sequence" else args.dest/f"{shot}.webp"
            if shot=="sequence" and i in (31,32) and "30" in coordinates:
                # Freeze the shot after removing the front, including its fine reflections.
                shutil.copyfile(dest.with_name("030.webp"),dest)
                coordinates[str(i)] = coordinates["30"]
            else:
                samples = (256 if i==0 else 88) if shot=="sequence" else 160
                coordinates[str(i)] = render(meshes,finishes,anchors,dest,shot,dim,args.spp or samples,i)
            print(f"{dest.name} ({dest.stat().st_size:,} bytes)",flush=True)
        if shot=="sequence" and len(coordinates)==FRAME_COUNT:
            (args.dest/"anchors.json").write_text(json.dumps(coordinates,separators=(",",":"))+"\n")


if __name__ == "__main__":
    main()
