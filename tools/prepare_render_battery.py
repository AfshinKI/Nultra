"""Tessellate the original Pilha AA.STEP for offline product rendering.

Requires NumPy and cadquery-ocp-novtk 8.0.1.1. Run this once with the
original 14 mm × 50 mm cell STEP and an output .npz in a scratch directory.
The STEP and intermediate mesh are local rendering inputs.
"""

import argparse
from pathlib import Path

import numpy as np
from OCP.BRep import BRep_Tool
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.IFSelect import IFSelect_RetDone
from OCP.STEPControl import STEPControl_Reader
from OCP.TopAbs import TopAbs_FACE, TopAbs_REVERSED
from OCP.TopExp import TopExp_Explorer
from OCP.TopLoc import TopLoc_Location
from OCP.TopoDS import TopoDS


# Millimetres. Default occurrence in Nultra_Assembly / Nultra_Core.
# Local +Z is the positive button and maps toward board contact BT1.
OCCURRENCE = np.array([[1, 0, 0, 18.1780211],
                       [0, 0, 1, 14.7931664],
                       [0, -1, 0, 10.0321020]])
# The renderer centres the 36 × 65.151 mm board, then raises the OBJ by .87 mm.
BOARD_DATUM = np.array([-28.0, -43.4975, .87])
# Finish IDs consumed by render_product.py. The original STEP has no sleeve decal.
GRAPHITE, COPPER, NICKEL, INSULATOR = range(4)
SHOULDER_Z = 39.0


def clip_sleeve(triangle, upper):
    """Cut the cylindrical side at the sleeve colour boundary."""
    polygon = []
    for index, current in enumerate(triangle):
        previous = triangle[index - 1]
        current_in = (current[2] >= SHOULDER_Z) == upper
        previous_in = (previous[2] >= SHOULDER_Z) == upper
        if current_in != previous_in:
            t = (SHOULDER_Z - previous[2]) / (current[2] - previous[2])
            polygon.append(previous + t * (current - previous))
        if current_in:
            polygon.append(current)
    for i in range(1, len(polygon) - 1):
        yield [polygon[0], polygon[i], polygon[i + 1]]


def tessellate(source):
    reader = STEPControl_Reader()
    if reader.ReadFile(str(source)) != IFSelect_RetDone or not reader.TransferRoots():
        raise ValueError(f"Cannot read cell geometry from {source}")
    shape = reader.OneShape()
    BRepMesh_IncrementalMesh(shape, .025, False, .085, False)
    faces = TopExp_Explorer(shape, TopAbs_FACE)
    triangles, finishes = [], []
    while faces.More():
        face = TopoDS.Face(faces.Current())
        location = TopLoc_Location()
        mesh = BRep_Tool.Triangulation_s(face, location)
        if mesh is None:
            raise ValueError("STEP face has no triangulation")
        transform = location.Transformation()
        points = np.array([mesh.Node(i).Transformed(transform).Coord()
                           for i in range(1, mesh.NbNodes() + 1)])
        low, high = points[:, 2].min(), points[:, 2].max()
        radius = np.linalg.norm(points[:, :2], axis=1).max()
        # The two cylinder halves span the same plane and both need splitting.
        is_sleeve = high - low > 40
        if radius > 6.9:
            finish = COPPER if low > 40 else GRAPHITE
        elif low > 48.5 and radius > 4.8:
            finish = INSULATOR
        else:
            finish = NICKEL
        for i in range(1, mesh.NbTriangles() + 1):
            idx = np.array(mesh.Triangle(i).Get()) - 1
            triangle = points[idx[::-1] if face.Orientation() == TopAbs_REVERSED else idx]
            if is_sleeve:
                for upper, material in [(False, GRAPHITE), (True, COPPER)]:
                    for fragment in clip_sleeve(triangle, upper):
                        triangles.append(fragment)
                        finishes.append(material)
            else:
                triangles.append(triangle)
                finishes.append(finish)
        faces.Next()
    local, inverse = np.unique(np.round(np.reshape(triangles, (-1, 3)), 7), axis=0,
                               return_inverse=True)
    if not np.allclose(np.ptp(local, axis=0), [14, 14, 50], atol=.05):
        raise ValueError("Expected the Nultra assembly's 14 × 50 mm AA cell")
    xyz = local @ OCCURRENCE[:, :3].T + OCCURRENCE[:, 3] + BOARD_DATUM
    return xyz.astype(np.float32), inverse.reshape(-1, 3).astype(np.uint32), np.asarray(finishes, dtype=np.uint8)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cell_step", type=Path)
    parser.add_argument("output_npz", type=Path)
    args = parser.parse_args()
    vertices, indices, materials = tessellate(args.cell_step)
    np.savez_compressed(args.output_npz, positions=vertices, indices=indices, face_material=materials)
    print(f"{len(vertices)} vertices, {len(indices)} triangles, bounds in mm:",
          vertices.min(axis=0), vertices.max(axis=0))
