"""Film the AA exchange in its installed wall box, using the original product CAD.

Use the Mitsuba environment and positioned AA input from render_wall_teardown.py.
The encoder is FFmpeg with libx264 (or the binary supplied by imageio-ffmpeg).
"""
import argparse
import math
import shutil
import subprocess
from pathlib import Path

import mitsuba as mi
import numpy as np
from PIL import Image, ImageFilter

import render_product as product
from render_wall_teardown import Studio, move, posed, ramp, rotate

WIDTH, HEIGHT = 960, 648
FPS, SECONDS = 24, 8
POSTER_TIME = 4.75
BOTTOM_CONTACT = np.array([-9.822, -27.8, 10.9])


def tilt(degrees):
    angle = math.radians(degrees)
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def parts_at(t):
    # Pull the plate clear of the plaster before turning over its long edge.
    progress = min(t, max(0, 7.55 - t))
    pull = ramp(progress, .30, .92)
    turn = ramp(progress, .76, 1.72)
    # Reserve clearance for the far lower corner as the full-width plate turns.
    corner_clearance = 2.5 * ramp(progress, 1.13, 1.22) * (1 - ramp(progress, 1.34, 1.44))
    plate = posed([3*pull + 78*turn, 6*turn, 29*pull + 14*turn + corner_clearance],
                  rotate(146*turn, -5*turn), [0, 0, 20])

    if t < 3.85:
        tip = ramp(t, 2.02, 2.68)
        clear = ramp(t, 2.39, 3.02)
        depart = ramp(t, 2.89, 3.70)
        offset = [-15*clear - 145*depart, 4*clear + 50*depart, 21*clear + 14*depart]
        cell = posed(offset, rotate(0, 9*clear + 9*depart) @ tilt(19*tip), BOTTOM_CONTACT)
        cell_name = 'old'
    else:
        arrive = 1 - ramp(t, 3.92, 4.68)
        align = 1 - ramp(t, 4.65, 5.25)
        tip = 1 - ramp(t, 5.26, 5.68)
        offset = [-128*arrive - 36*align, -54*arrive - 2*align, 24*align + 7*tip]
        cell = posed(offset, rotate(0, 11*align - 8*arrive) @ tilt(19*tip), BOTTOM_CONTACT)
        cell_name = 'fresh'
    return plate, cell_name, cell


def textured_wall(vertices, faces, color):
    props = mi.Properties()
    props['bsdf'] = color
    mesh = mi.Mesh('painted plaster', len(vertices), len(faces)//3, props, has_vertex_texcoords=True)
    params = mi.traverse(mesh)
    params['vertex_positions'] = vertices.ravel()
    params['faces'] = faces
    # Project one continuous patch of photographed plaster across the aperture.
    uv = np.column_stack([.5 + vertices[:, 0]/267, .5 - vertices[:, 1]/177])
    params['vertex_texcoords'] = uv.astype(np.float32).ravel()
    params.update()
    return mesh


class ServiceFilm:
    def __init__(self, obj, battery, size):
        self.size = size
        self.studio = Studio(obj, battery)
        self.installation = {}
        look, _, up = product.axes(20, 7, 0)
        center = np.array([0., 0., 18.])
        half_height = 70.
        half_width = half_height * size[0] / size[1]
        camera = mi.ScalarTransform4f.look_at(origin=center + 425*look, target=center, up=up)
        film = {'type': 'hdrfilm', 'width': size[0], 'height': size[1], 'pixel_format': 'rgb', 'rfilter': {'type': 'tent'}}
        self.scene = {
            'type': 'scene', 'integrator': {'type': 'path', 'max_depth': 5, 'hide_emitters': True},
            'camera': {'type': 'orthographic', 'to_world': camera @ mi.ScalarTransform4f.scale([half_width, half_width, 1]),
                       'sampler': {'type': 'independent'}, 'film': film},
            'ambient': {'type': 'constant', 'radiance': {'type': 'rgb', 'value': [.25, .265, .27]}},
            'window': product.light(center, np.array([-91, 100, 152]), [88, 69], [4.95, 4.65, 4.25]),
            'fill': product.light(center, np.array([96, -24, 160]), [80, 72], [1.65, 1.79, 1.9]),
            'strip': product.light(center, np.array([-102, 11, 76]), [12, 72], [2.3, 2.5, 2.65]),
        }
        with Image.open(product.ASSETS / 'features/plaster.webp') as source:
            wall_photo = np.array(source.convert('RGB'), dtype=np.uint8)
        texture = {'type': 'bitmap', 'bitmap': mi.Bitmap(wall_photo), 'wrap_mode': 'clamp'}
        paint = mi.load_dict({'type': 'diffuse', 'reflectance': texture})
        wall_v, wall_i = self.studio.groups['wall'][0][1:3]
        self.installation['wall'] = textured_wall(wall_v, wall_i, paint)
        for part in ['box', 'pcb', 'carrier', 'shell', 'upper', 'lower']:
            matrix = posed()
            if part == 'box':
                matrix = posed([0, 0, 20])
            elif part in ('upper', 'lower'):
                sign = 1 if part == 'upper' else -1
                matrix = posed([0, sign*41.65, 20.07], rotate(0, sign*19))
            self.installation.update(self.meshes(part, matrix))
        self.new_band = product.surface('cell-pole', {})
        self.denoiser = mi.OptixDenoiser(list(size)) if mi.variant() == 'cuda_ad_rgb' else None

    def meshes(self, group, matrix, fresh=False):
        shapes = {}
        for index, (name, verts, faces, material) in enumerate(self.studio.groups[group]):
            if fresh and name == 'cell-copper':
                material = self.new_band
            key = f'{group}_{index}'
            xyz = move(matrix, verts).astype(np.float32)
            shapes[key] = product.mesh_object(key, xyz, faces, material)
        return shapes

    def frame(self, pose, samples):
        plate, cell_name, cell = pose
        geometry = {**self.installation, **self.meshes('plate', plate), **self.meshes('battery', cell, cell_name == 'fresh')}
        scene = mi.load_dict({**self.scene, **geometry})
        summed = np.zeros((self.size[1], self.size[0], 3), dtype=np.float32)
        for first in range(0, samples, 8):
            count = min(8, samples - first)
            summed += np.array(mi.render(scene, spp=count, seed=541 + first)) * count
        linear = summed / samples
        if self.denoiser is not None:
            linear = .98 * np.asarray(self.denoiser(mi.TensorXf(linear))) + .02 * linear
        linear = np.maximum(linear, 0)
        linear = linear / (1 + .22*linear)
        rgb = np.where(linear < .0031308, 12.92*linear, 1.055*linear**(1/2.4) - .055)
        return Image.fromarray(np.uint8(np.clip(rgb, 0, 1)*255 + .5)).filter(ImageFilter.MedianFilter(3))


def encode(film, samples, destination):
    encoder = shutil.which('ffmpeg')
    if not encoder:
        from imageio_ffmpeg import get_ffmpeg_exe
        encoder = get_ffmpeg_exe()
    width, height = film.size
    target = destination / 'aa-replacement.mp4'
    command = [encoder, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
               '-s', f'{width}x{height}', '-r', str(FPS), '-i', '-', '-an', '-c:v', 'libx264', '-crf', '18',
               '-preset', 'slow', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(target)]
    last_key = None
    closed = None
    with subprocess.Popen(command, stdin=subprocess.PIPE) as stream:
        for frame_no in range(FPS*SECONDS):
            t = frame_no/FPS
            pose = parts_at(t)
            key = (pose[0].tobytes(), pose[1], pose[2].tobytes())
            if key != last_key:
                if frame_no and closed is not None and np.array_equal(pose[0], np.eye(4)):
                    image = closed
                else:
                    image = film.frame(pose, samples)
                if frame_no == 0:
                    closed = image
                last_key = key
                pixels = image.tobytes()
            stream.stdin.write(pixels)
            if frame_no == round(POSTER_TIME*FPS):
                image.save(destination / 'aa-replacement.webp', quality=90, method=6)
            if frame_no % (FPS*2) == 0:
                print(f'Film {t:.0f} / {SECONDS}s', flush=True)
        stream.stdin.close()
        if stream.wait() != 0:
            raise RuntimeError('The H.264 encoder did not finish.')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('obj', type=Path)
    ap.add_argument('--battery', required=True, type=Path)
    ap.add_argument('--dest', type=Path, default=product.ASSETS / 'features')
    ap.add_argument('--samples', type=int, default=128)
    ap.add_argument('--variant', choices=['cuda_ad_rgb', 'llvm_ad_rgb'], default='cuda_ad_rgb')
    ap.add_argument('--proof', type=float, nargs='+', help='Render selected times at half size')
    args = ap.parse_args()
    if args.samples < 1:
        ap.error('The sample count must be positive.')
    mi.set_variant(args.variant)
    film = ServiceFilm(args.obj, args.battery, (WIDTH//2, HEIGHT//2) if args.proof else (WIDTH, HEIGHT))
    args.dest.mkdir(parents=True, exist_ok=True)
    if args.proof:
        for t in args.proof:
            film.frame(parts_at(t), args.samples).save(args.dest / f'{t:05.2f}.png')
    else:
        encode(film, args.samples, args.dest)


if __name__ == '__main__':
    main()
