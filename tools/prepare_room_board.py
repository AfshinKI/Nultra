"""Pack a lightweight populated PCB from the Altium OBJ for the installed switch.

Run with Python 3 and the same Nultra.obj and companion MTL used by
render_product.py. Dimensions in the binary are hundredths of a millimetre.
"""
import argparse
import json
import struct
from collections import defaultdict
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[1] / "docs" / "assets"


def materials(obj):
    result = {}
    for line in obj.with_suffix(".mtl").read_text().splitlines():
        key, _, value = line.partition(" ")
        if key == "newmtl":
            name = value.strip()
        elif key == "Kd":
            result[name] = tuple(round(float(v) * 255) for v in value.split())
    return result


def populated_board(obj):
    vertices = []
    components = defaultdict(set)
    colors = materials(obj)
    for line in obj.open(encoding="utf-8-sig"):
        tag, _, value = line.strip().partition(" ")
        if tag == "v":
            x, y, z = map(float, value.split()[:3])
            # A 0.18 mm grid resolves package edges and solder leads at wall scale.
            vertices.append(tuple(round(round(n / .18) * 18) for n in (x * 10, y * 10, z * 10 + .87)))
        elif tag == "g":
            group = value
        elif tag == "usemtl":
            finish = value
        elif tag == "f" and group not in {"Board", "Nets", "No Net", "Components", "Silk"}:
            points = [vertices[int(item.partition("/")[0]) - 1] for item in value.split()]
            if group in {"J6", "J7"} and min(p[0] for p in points) > 2000:
                continue  # The export parks its two loose terminal fasteners beside the board.
            for i in range(1, len(points) - 1):
                tri = (points[0], points[i], points[i + 1])
                if len(set(tri)) == 3:
                    components[colors[finish]].add(tri)
    board = next(m for m in json.loads((ASSETS / "switch.json").read_text())["parts"] if m["id"] == "pcb")
    for layer, color in zip([board, *board["details"]], [(201, 203, 187), (143, 151, 131), (201, 158, 88)]):
        xyz = list(zip(*[iter(layer["positions"])] * 3))
        for indices in zip(*[iter(layer["indices"])] * 3):
            components[color].add(tuple(tuple(round(v * 100) for v in xyz[i]) for i in indices))
    return components


def pack(components, dest):
    payload = bytearray(b"NCB1")
    for color, triangles in sorted(components.items()):
        tris = sorted(triangles)
        # Decoding uses flat-shaded triangles and WebGL 1 unsigned-short indices.
        for start in range(0, len(tris), 16000):
            points = [p for tri in tris[start:start + 16000] for p in tri]
            vertices = list(dict.fromkeys(points))
            index = {p: i for i, p in enumerate(vertices)}
            payload += struct.pack("<3BxII", *color, len(vertices), len(points))
            payload += b"".join(struct.pack("<3h", *p) for p in vertices)
            payload += struct.pack(f"<{len(points)}H", *(index[p] for p in points))
    dest.write_bytes(payload)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("obj", type=Path)
    args = parser.parse_args()
    pack(populated_board(args.obj), ASSETS / "room" / "board.bin")
