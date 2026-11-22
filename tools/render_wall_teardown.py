"""Path trace Nultra's wall teardown and registered battery-service layers.

Use the Altium OBJ, placed Pilha AA mesh from prepare_render_battery.py and
Mitsuba/NumPy/Pillow environment described in render_product.py. Dimensions
and times match the WebGL room. All UVs in poses.json start at the top left.
"""
import argparse
import json
import math
import time
from pathlib import Path

import drjit as dr
import mitsuba as mi
import numpy as np
from PIL import Image, ImageFilter

import render_product as product

SEATS = np.array([[-12.5, 27.5, 20], [12.5, 27.5, 20], [12.5, -21.5, 20]])
# More samples along spinning fasteners and the front-to-back camera sweep.
# The curve is completely still during the reading interval.
STOPS = [(.238, .252, 2), (.252, .323, 17), (.323, .36, 8), (.36, .434, 1),
         (.434, .468, 79), (.468, .482, 5), (.482, .512, 7), (.512, .566, 11), (.566, .626, 11),
         (.626, .693, 14), (.693, .751, 14)]


def ramp(t, a, b):
    return product.eased((t-a)/(b-a))


def blend(a, b, t):
    return (1-t)*a+t*b


def posed(offset=(0, 0, 0), rot=None, pivot=(0, 0, 0)):
    m = np.eye(4)
    if rot is not None:
        m[:3, :3] = rot
    m[:3, 3] = np.array(offset) + pivot - m[:3, :3] @ pivot
    return m


def rotate(yaw=0, roll=0):
    look, right, up = product.axes(yaw, 0, roll)
    return np.column_stack([right, up, look])


def move(m, p):
    return np.asarray(p) @ m[:3, :3].T + m[:3, 3]


def pose(t, aspect, service=None):
    peel = ramp(t, .25, .323)
    clear = ramp(t, .32, .36)
    back = ramp(t, .434, .468)
    withdraw = ramp(t, .468, .483)
    away = ramp(t, .477, .51)
    lift = ramp(t, .49, .562)
    studio = ramp(t, .508, .574)
    cell = ramp(t, .566, .626)
    split = ramp(t, .626, .693)
    inspect = ramp(t, .695, .751)
    dz = 92*lift
    look, right, up = product.axes(blend(12+35*studio+split*9, 15, inspect),
                                   blend(9+4*studio, 7, inspect), blend(-5*studio, -8, inspect))
    shifts = {
        'plate': posed([67*peel+76*clear, 4*peel, 34*peel], rotate(151*peel, -5*peel), [0, 0, 20]),
        'carrier': posed([-124*inspect, 0, dz+15*split]),
        'shell': posed([135*inspect, 0, dz-88*split]),
        'pcb': posed([0, 0, dz-28*split]),
        'battery': posed([-24*split-85*inspect, 9*cell, dz+44*cell-12*split]),
        'box': posed([0, 0, 20]),
    }
    for name, side in [('lower', -1), ('upper', 1)]:
        # Front is +Z. A 3/8 inch screw disengages the tab 2 mm below
        # the carrier face after 7.55 mm of pitch-coupled travel.
        angle = side*19 + 360*7.55*back/(25.4/32)
        shifts[name] = posed([12*away, side*(41.65+100*away), 20.07+7.55*back+22*withdraw],
                              rotate(-22*withdraw, angle))
    visible = set(shifts)
    if clear == 1:
        visible.discard('plate')
    if away == 1:
        visible -= {'lower', 'upper'}
    if studio == 1:
        visible.discard('box')
    if inspect == 1:
        visible = {'pcb'}
    half = blend(blend(78, 71, ramp(t, .319, .354)), 76+6*split, cell)
    center = np.array([25*peel*(1-ramp(t, .319, .352)), 0, dz+11-14*split])+right*12.5*split
    if service:
        half = 73
        center = np.array([0, 0, 11])
        visible = {'carrier': {'carrier', 'shell', 'pcb', 'lower', 'upper'},
                   'seated': {'carrier', 'shell', 'pcb', 'lower', 'upper', 'battery'},
                   'plate': {'plate'}, 'cell': {'battery'}}[service]
    return shifts, visible, center, half, (look, right, up), studio, inspect


def circles(radius, z, n=96):
    a = np.arange(n)*2*math.pi/n
    return np.column_stack([radius*np.cos(a), radius*np.sin(a), np.full(n, z)])


def rounded(hw, hh, radius, z):
    points = []
    for i, (sx, sy) in enumerate([(1, 1), (-1, 1), (-1, -1), (1, -1)]):
        a = np.linspace(i*math.pi/2, (i+1)*math.pi/2, 11)
        points.extend(zip(sx*(hw-radius)+radius*np.cos(a), sy*(hh-radius)+radius*np.sin(a), np.full(len(a), z)))
    return np.array(points)


def installation_meshes():
    # Independent steel wall box and generic 6-32 device screws. Each face of
    # the cross recess has geometry, so the highlights rotate with the screw.
    groups = {}

    def strip(part, rings):
        dest = groups.setdefault(part, [])
        for a, b in zip(rings, rings[1:]):
            for i in range(len(a)):
                j = (i+1) % len(a)
                dest.extend([(a[i], a[j], b[i]), (b[i], a[j], b[j])])

    outer = rounded(25.5, 48.5, 3, 0)
    rear = rounded(22.8, 44.2, 2.8, -41)
    wall_rim = outer+[0, 0, 20.012]
    wall_outer = wall_rim*np.array([100, 100, 1])
    strip(('wall', 'paint'), [wall_outer, wall_rim])
    strip(('box', 'plaster'), [outer, rounded(25.25, 48.25, 2.75, -2.4)])
    strip(('box', 'zinc'), [rounded(25.25, 48.25, 2.75, -2.4), rounded(23.8, 46.65, 2.2, -2.45),
                            rounded(23.35, 46.2, 2.05, -3.6), rear, rear*np.array([0, 0, 1])])
    for y, radius in [(-13, 11.3), (19, 9.25)]:
        strip(('box', 'zinc'), [circles(r, z)+[0, y, -40.95] for r, z in [(radius+1, 0), (radius+.25, .58),
              (radius-.20, .04), (radius-.77, .47), (radius-1.08, .66), (0, .66)]])
    for side in [-1, 1]:
        a = circles(1, -2)
        outer_ear = a.copy()
        extent = np.minimum(7.2/np.maximum(.001, abs(a[:, 0])), 5/np.maximum(.001, abs(a[:, 1])))
        outer_ear[:, :2] *= extent[:, None]
        strip(('box', 'zinc'), [p+[0, side*41.65, 0] for p in
              [outer_ear, circles(1.87, -2), circles(1.59, -2.85), circles(1.57, -3.6)]])
    for name in ['upper', 'lower']:
        cross = np.array([[-.54, -2.25], [.54, -2.25], [.54, -.54], [2.25, -.54], [2.25, .54], [.54, .54],
                          [.54, 2.25], [-.54, 2.25], [-.54, .54], [-2.25, .54], [-2.25, -.54], [-.54, -.54]])
        points = np.concatenate([np.linspace(a, b, 8, endpoint=False) for a, b in zip(cross, np.roll(cross, -1, axis=0))])
        clock = np.arctan2(points[:, 1], points[:, 0])
        units = np.column_stack([np.cos(clock), np.sin(clock)])
        def ring(r, z):
            return np.column_stack([units*r, np.full(len(points), z)])
        def slot(s, z):
            return np.column_stack([points*s, np.full(len(points), z)])
        strip((name, 'steel'), [ring(r, z) for r, z in [(0, -9.525), (1.05, -9.45), (1.4, -9.08), (1.4, -.38), (1.7, -.07),
              (3.48, -.07), (3.77, .22), (3.76, .68), (3.57, 1.13), (3.23, 1.53), (2.70, 1.77)]] + [slot(1, 1.85)])
        strip((name, 'slot'), [slot(1, 1.85), slot(.79, 1.37), slot(.52, .54), slot(0, .44)])
        # The thread ridge wraps helically around the machine screw shank.
        theta = np.linspace(0, 20.8*math.pi, 526)
        z = -9.1+(25.4/32)*theta/(2*math.pi)
        spine = np.column_stack([np.cos(theta), np.sin(theta)])
        threads = [np.column_stack([r*spine, z+off]) for r, off in [(1.4, -.21), (1.72, -.03), (1.75, .025), (1.4, .22)]]
        dest = groups.setdefault((name, 'steel'), [])
        for a, b in zip(threads, threads[1:]):
            for i in range(len(a)-1):
                dest.extend([(a[i], a[i+1], b[i]), (b[i], a[i+1], b[i+1])])
    for part in ['plate', 'carrier']:
        sign = -1 if part == 'plate' else 1
        for seat in SEATS:
            strip((part, 'magnet'), [circles(r, sign*z, 50)+seat for r, z in
                  [(2.23, -.4), (2.23, -.02), (2.16, .09), (1.99, .14), (0, .14)]])
    meshes = []
    for (part, mat), triangles in groups.items():
        verts, indices = np.unique(np.round(np.asarray(triangles).reshape(-1, 3), 5), axis=0, return_inverse=True)
        meshes.append((part, mat, verts.astype(np.float32), indices.astype(np.uint32)))
    return meshes


def material(rgb, rough, metal):
    return mi.load_dict({'type': 'twosided', 'material': {'type': 'principled', 'base_color': {'type': 'rgb', 'value': rgb},
                                                      'roughness': rough, 'metallic': metal}})


def plaster_visibility(full, sensor, size):
    w, h = size
    # First hits on the receiving plaster occlude enclosure pieces
    # recessed behind it, even as the switch crosses the wall plane.
    wall = full['wall_0']
    # Area emitters are invisible to the beauty integrator but still
    # intersect explicit rays. Use the hardware and wall alone here.
    geometry = {'type': 'scene', **{k: v for k, v in full.items() if isinstance(v, mi.Shape)}}
    occluders = mi.load_dict(geometry)
    ids = dr.arange(mi.UInt32, w*h)
    x = ids%w
    y = ids // w
    occluded = dr.zeros(mi.Float, w*h)
    for sx, sy in [(.25, .25), (.75, .25), (.25, .75), (.75, .75)]:
        film = mi.Point2f((mi.Float(x)+sx)/w, (mi.Float(y)+sy)/h)
        ray, _ = sensor.sample_ray(0, 0, film, mi.Point2f(.5, .5))
        hit = occluders.ray_intersect(ray)
        occluded += dr.select(hit.shape == mi.ShapePtr(wall), .25, 0)
    return np.asarray(occluded).reshape(h, w, 1)


class Studio:
    def __init__(self, obj, cell_file):
        board, colors = product.read_board(obj)
        housing, self.anchors = product.read_housing()
        cell, self.anchors['battery'] = product.read_cell(cell_file)
        meshes = [('plate' if part in {'faceplate', 'wordmark'} else part, mat, v, idx) for part, mat, v, idx in housing]
        meshes.extend(layer for layer in board if layer[0] == 'pcb')
        meshes.extend(cell)
        surfaces = {m: product.surface(m, colors) for _, m, _, _ in meshes}
        surfaces.update({name: material(*spec) for name, spec in {
            'steel': ([.55, .59, .59], .23, .88), 'slot': ([.11, .125, .125], .33, .7),
            'magnet': ([.64, .65, .62], .18, .94), 'zinc': ([.36, .39, .39], .37, .72),
            'plaster': ([.34, .32, .28], .84, .01), 'paint': ([.76, .75, .72], .90, 0)}.items()})
        meshes.extend(installation_meshes())
        self.groups = {}
        self.solder_mask = surfaces['solder_t']
        for part, mat, verts, indices in meshes:
            self.groups.setdefault(part, []).append((mat, verts, indices, surfaces[mat]))
        self.board_points = np.concatenate([v for part, _, v, _ in board if part == 'pcb'])
        self.denoiser = {}
        self.wall_hold = None

    def render(self, scene, visible, shifts, inspect, size, spp, shadow=False):
        w, h = size
        full = dict(scene)
        if shadow:
            full['integrator'] = {'type': 'direct', 'hide_emitters': True, 'emitter_samples': 1, 'bsdf_samples': 1}
        n = min(32, spp) if shadow else spp
        mask = mi.load_dict({'type': 'mask', 'opacity': .87-.48*inspect, 'nested': self.solder_mask})
        for part in sorted(visible):
            for i, (mat, verts, indices, bsdf) in enumerate(self.groups[part]):
                key = f'{part}_{i}'
                xyz = move(shifts.get(part, np.eye(4)), verts).astype(np.float32)
                full[key] = product.mesh_object(key, xyz, indices, mask if mat == 'solder_t' else bsdf)
        compiled = mi.load_dict(full)
        total = None
        batch = max(1, min(8, 5000000 // (w*h)))
        for i in range(0, n, batch):
            count = min(batch, n-i)
            img = np.array(mi.render(compiled, spp=count, seed=791+i))*count
            total = img if total is None else total+img
        if shadow and 'wall' in visible and len(visible) > 1:
            return total/n, plaster_visibility(full, compiled.sensors()[0], size)
        return total/n

    def draw(self, t, size, spp, service=None):
        w, h = size
        aspect = w/h
        shifts, visible, center, half, axes, studio, inspect = pose(t, aspect, service)
        look, right, up = axes
        if inspect:
            board = move(shifts['pcb'], self.board_points)
            bx = board @ right
            by = board @ up
            board_center = right*(bx.min()+bx.max())/2+up*(by.min()+by.max())/2+look*np.mean(board @ look)
            center = blend(center, board_center, inspect)
            half = blend(half, max(np.ptp(bx)/aspect, np.ptp(by))*.59, inspect)
        half_w = half*aspect
        def uv(world):
            q = world-center
            return [round(float(.5+q @ right/(2*half_w)), 6), round(float(.5-q @ up/(2*half)), 6)]
        mount_datums = {'mount': [0, 0, 20], 'top': [0, 41.65, 20], 'right': [25.5, 0, 20]}
        points = {name: uv(np.array(p)) for name, p in mount_datums.items()}
        for key, part in [('battery', 'battery'), ('mcu', 'pcb'), ('debug', 'pcb')]:
            points[key] = uv(move(shifts[part], self.anchors[key]))
        points['magnets'] = [{'from': uv(move(shifts['carrier'], p)), 'to': uv(move(shifts['plate'], p))} for p in SEATS]
        camera = mi.ScalarTransform4f.look_at(origin=center+look*500, target=center, up=up)
        scene = {'type': 'scene', 'integrator': {'type': 'path', 'max_depth': 5, 'hide_emitters': True},
               'camera': {'type': 'orthographic', 'to_world': camera @ mi.ScalarTransform4f.scale([half_w, half_w, 1]),
                         'sampler': {'type': 'independent', 'sample_count': spp},
                         'film': {'type': 'hdrfilm', 'width': w, 'height': h, 'pixel_format': 'rgba', 'rfilter': {'type': 'tent'}}},
               'ambient': {'type': 'constant', 'radiance': {'type': 'rgb', 'value': [.13, .145, .14]}}}
        for name, pos, scale, energy, travel in [
            ('key', [-87, 113, 125], [82, 58], [3.8, 3.50, 3.20], 28), ('fill', [95, -36, 122], [64, 84], [1.15, 1.27, 1.31], 0),
            ('rim', [44, 90, -94], [30, 72], [2.45, 2.73, 2.65], 0), ('edge', [-112, -53, -71], [22, 75], [1.45, 1.26, .88], 0),
            ('strip', [-105, 10, 77], [8, 80], [2.6, 2.75, 2.82], 95)]:
            a, b, c = pos
            sweep = math.sin(4*math.pi/23)
            world = blend(np.array(pos), right*(a+sweep*travel)+up*b+look*c, inspect)
            scene[name] = product.light(center, world, scale, energy)
        rgba = self.render(scene, visible, shifts, inspect, size, spp)
        shadow = None
        if 'box' in visible and .36 < t <= .468 and self.wall_hold is not None:
            # Only the fasteners move inside the aperture during unthreading.
            # Their changing reflections and occlusion remain fully path traced.
            outside, opening, shadow = self.wall_hold
            rgba = blend(outside, rgba, opening)
        elif 'box' in visible:
            # A real perforated receiver occludes the outside of the flush box.
            # Compare lit plaster with and without hardware to export a neutral
            # shadow matte that can darken the room photograph underneath.
            bare = self.render(scene, {'wall'}, shifts, inspect, size, spp, shadow=True)
            installed, wall_hit = self.render(scene, visible | {'wall'}, shifts, inspect, size, spp, shadow=True)
            opening = (1-bare[:, :, 3:4].clip(0, 1))*(1-studio)
            isolated = self.render(scene, visible - {'box'}, shifts, inspect, size, spp)
            rgba = blend(isolated, rgba, opening)*(1-wall_hit)
            luminance = np.array([.213, .715, .072], np.float32)
            lit_wall = bare[:, :, :3] @ luminance
            shadowed_wall = installed[:, :, :3] @ luminance
            shade = np.clip(1 - shadowed_wall / np.maximum(lit_wall, .006), 0, 1) * bare[:, :, 3]
            matte = Image.fromarray(np.uint8(np.clip(shade, 0, 1)*255)).filter(ImageFilter.GaussianBlur(4.5*w/960))
            shadow = np.maximum(np.asarray(matte, dtype=np.float32)/255-.037, 0)*(1-studio)*.76
            # The wall itself extends beyond the transparent atlas. Taper the
            # penumbra before the crop boundary so a tile has no visible edge.
            dx = np.minimum(np.arange(w)+.5, w-.5-np.arange(w))/(w*.075)
            dy = np.minimum(np.arange(h)+.5, h-.5-np.arange(h))/(h*.075)
            shadow *= np.minimum(dx[None, :], dy[:, None]).clip(0, 1)
            if abs(t-.36) < 1e-6:
                self.wall_hold = (rgba.copy(), opening, shadow.copy())

        alpha = rgba[:, :, 3:4].clip(0, 1)
        beauty = np.ascontiguousarray(rgba[:, :, :3])
        if mi.variant() == 'cuda_ad_rgb':
            if size not in self.denoiser:
                self.denoiser[size] = mi.OptixDenoiser([w, h])
            beauty = .985*np.array(self.denoiser[size](mi.TensorXf(beauty)))+.015*beauty
        rgb = np.maximum(beauty/np.maximum(alpha, 1e-5), 0)
        rgb = rgb/(1+.22*rgb)
        rgb = np.where(rgb < .0031308, 12.92*rgb, 1.055*rgb**(1/2.4)-.055)
        if shadow is not None:
            opacity = alpha+(1-alpha)*shadow[:, :, None]
            rgb *= alpha/np.maximum(opacity, 1e-5)
            alpha = opacity
        pixels = (255*np.concatenate([rgb, alpha], axis=2).clip(0, 1)+.5).astype('uint8')
        image = Image.fromarray(pixels, 'RGBA')
        cleaned = image.convert('RGB').filter(ImageFilter.MedianFilter(3))
        cleaned.putalpha(image.getchannel('A'))
        x0, y0, x1, y1 = cleaned.getchannel('A').point(lambda a:255 if a > 128 else 0).getbbox()
        points['bounds'] = [round(x0/w, 6), round(y0/h, 6), round(x1/w, 6), round(y1/h, 6)]
        return cleaned, points


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('obj', type=Path)
    ap.add_argument('--battery', required=True, type=Path)
    ap.add_argument('--variant', choices=['cuda_ad_rgb', 'llvm_ad_rgb'], default='cuda_ad_rgb')
    ap.add_argument('--spp', type=int, default=112)
    ap.add_argument('--dest', type=Path, default=product.ASSETS)
    ap.add_argument('--shots', nargs='+', choices=['service', 'sequence'], default=['service', 'sequence'])
    ap.add_argument('--preview', type=float, nargs='+')
    ap.add_argument('--width', type=int, default=960)
    args = ap.parse_args()
    if args.spp < 1 or args.width < 4:
        ap.error('Samples must be positive and the render width must be at least four pixels.')
    mi.set_variant(args.variant)
    started = time.monotonic()
    studio = Studio(args.obj, args.battery)
    size = (args.width, round(args.width*3/4))
    if args.preview:
        args.dest.mkdir(parents=True, exist_ok=True)
        for t in args.preview:
            img, _ = studio.draw(t, size, args.spp)
            img.save(args.dest/f'pose-{t:.3f}.webp', quality=90, method=5)
            print(f'Preview {t:.3f}, elapsed {time.monotonic()-started:.1f}s', flush=True)
        return
    if 'service' in args.shots:
        out = args.dest/'features'
        out.mkdir(parents=True, exist_ok=True)
        for part in ['plate', 'carrier', 'cell', 'seated']:
            img, _ = studio.draw(.238, (720, 720), max(144, args.spp), part)
            img.save(out/f'service-{part}.webp', quality=92, method=5)
            print(f'Service {part}, elapsed {time.monotonic()-started:.1f}s', flush=True)
    if 'sequence' not in args.shots:
        return
    out = args.dest/'teardown'
    out.mkdir(parents=True, exist_ok=True)
    timeline = [float(t) for a, b, n in STOPS for t in np.linspace(a, b, n, endpoint=False)]+[STOPS[-1][1]]
    posters = {min(range(len(timeline)), key=lambda i:abs(timeline[i]-t)): name for t, name in
             [(.303, "magnetic"), (.36, "mounted"), (.684, "exploded")]}
    frames = []
    still = None
    for i, t in enumerate(timeline):
        tile = i%4
        if not tile:
            atlas = Image.new('RGBA', (2*size[0], 2*size[1]))
        if abs(t-.434) < 1e-6 and still:
            img, points = still
        else:
            img, points = studio.draw(t, size, max(112, args.spp) if abs(t-.36) < 1e-6 else args.spp)
        if abs(t-.36) < 1e-6:
            still = img, points
        if i in posters:
            img.save(out/f'{posters[i]}.webp', quality=91, method=5)
        file = f'{i//4:03d}.webp'
        frames.append({'t': round(t, 7), 'sheet': file, 'tile': tile, **points})
        atlas.paste(img, ((tile%2)*size[0], (tile // 2)*size[1]))
        if tile == 3 or i == len(timeline)-1:
            atlas.save(out/file, quality=87, method=5)
            print(f'{file}: {i+1}/{len(timeline)} poses, elapsed {time.monotonic()-started:.1f}s', flush=True)
    manifest = {'width': size[0], 'height': size[1], 'columns': 2, 'rows': 2, 'frames': frames}
    (out / 'poses.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')


if __name__ == '__main__':
    main()
