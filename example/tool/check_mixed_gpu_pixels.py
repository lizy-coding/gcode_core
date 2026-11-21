"""Check native mixed preview PNGs. Requires Pillow."""
import json
import sys
from hashlib import sha256
from pathlib import Path
from PIL import Image, ImageChops

rows = [
    '1111100000001', '1000000000000', '1000000000000', '1111000000000',
    '1000000000000', '1000000000000', '0000000000000', '1000000000011',
]

def image(path):
    return Image.open(path).convert('RGB')

def verify(path, *, mixed, progress):
    im = image(path)
    width, height = im.size
    min_x, max_y, span_x, span_y = (0, 8, 9, 8) if mixed else (2, 7, 6.5, 4)
    scale = min((width - 62) / span_x, (height - 62) / span_y)
    left, top = (width - span_x * scale) / 2, (height - span_y * scale) / 2
    errors = []
    for row, samples in enumerate(rows):
        for col, cell in enumerate(samples):
            x = round(left + (2 + .5 * (col + .5) - min_x) * scale)
            y = round(top + (max_y - 7 + .5 * (row + .5)) * scale)
            black = max(im.getpixel((x, y))) < 48
            index = 12 - col if row % 2 else col
            expected = cell == '1' and progress * 8 >= row + (index + .5) / 13
            if black != expected:
                errors.append([row, col, im.getpixel((x, y))])
    return errors

if len(sys.argv) < 2:
    raise SystemExit('Usage: check_mixed_gpu_pixels.py RUN_DIR [RUN_DIR ...]')

passed = True
for argument in sys.argv[1:]:
    folder = Path(argument)
    captures = sorted(folder.glob('mixed-full-*.png'))
    if len(captures) != 30:
        raise SystemExit(f'{folder}: expected 30 endpoint captures, got {len(captures)}')
    failures = {}
    for name, mixed, progress in [
        ('bitmap-zero.png', False, 0),
        ('bitmap-reverse-last.png', False, .95),
        ('bitmap-full.png', False, 1),
        ('mixed-outline.png', True, 0),
        ('mixed-bitmap.png', True, (.55 * 15 - 5) / 8),
    ] + [(path.name, True, 1) for path in captures]:
        mismatches = verify(folder / name, mixed=mixed, progress=progress)
        if mismatches:
            failures[name] = mismatches
    hashes = {sha256(image(p).tobytes()).hexdigest() for p in captures}
    rewind_matches = ImageChops.difference(
        image(folder / 'mixed-outline.png'),
        image(folder / 'mixed-rewind.png'),
    ).getbbox() is None
    passed = passed and not failures and len(hashes) == 1 and rewind_matches
    print(json.dumps({
        'run': str(folder),
        'centerPixelComparisons': 104 * (5 + len(captures)),
        'failures': failures,
        'uniqueEndpointPixelHashes': len(hashes),
        'outlineAndRewindIdentical': rewind_matches,
    }, ensure_ascii=False))

raise SystemExit(0 if passed else 1)
