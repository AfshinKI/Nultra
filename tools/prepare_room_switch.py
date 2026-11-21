"""Pack the closed enclosure from the site's CAD meshes for the WebGL room.

Run with standard-library Python. Vertices are signed hundredths of a millimeter.
The room shader converts them back to their original CAD units before placement.
"""
import json
import struct
from pathlib import Path


def main():
    assets = Path(__file__).resolve().parents[1] / 'docs' / 'assets'
    parts = json.loads((assets / 'switch.json').read_text(encoding='utf-8'))['parts']
    shells = [next(p for p in parts if p['id'] == name)
              for name in ('faceplate', 'wordmark', 'carrier', 'shell')]
    dest = assets / 'room' / 'switch.bin'
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open('wb') as out:
        out.write(b'NCR1')
        for mesh in shells:
            vertices = [round(x * 100) for x in mesh['positions']]
            faces = mesh['indices']
            out.write(struct.pack('<II', len(vertices) // 3, len(faces)))
            out.write(struct.pack(f'<{len(vertices)}h', *vertices))
            out.write(struct.pack(f'<{len(faces)}H', *faces))


if __name__ == '__main__':
    main()
