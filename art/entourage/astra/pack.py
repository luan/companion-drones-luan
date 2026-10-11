"""Pack the Blender exports into Factorio atlases, checking every cell's alpha bounds."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('bodies', type=Path)
parser.add_argument('rotors', type=Path)
parser.add_argument('gear', type=Path)
parser.add_argument('--masks', type=Path, required=True)
args = parser.parse_args()
source = Path(__file__).resolve().parent
repo = source.parents[2]
roles = [
    ('main', args.bodies / 'entourage', 'entourage.blend', 'entourage-body.png', 128, 320, 8),
    ('utility', args.bodies / 'manager', 'manager.blend', 'task-manager.png', 128, 320, 8),
    ('combat', args.bodies / 'combat', 'combat.blend', 'combat-drone.png', 512, 256, 16),
    ('main_mask', args.masks / 'entourage', 'entourage.blend', 'entourage-mask.png', 128, 320, 8),
    ('utility_mask', args.masks / 'manager', 'manager.blend', 'task-manager-mask.png', 128, 320, 8),
    ('combat_mask', args.masks / 'combat', 'combat.blend', 'combat-drone-mask.png', 512, 256, 16),
    ('rotor', args.rotors, 'rotor.blend', 'turbine.png', 16, 96, 8),
    ('landing', args.gear, 'landing-gear.blend', 'landing-gear.png', 32, 320, 8),
]
manifest = {'rendering': 'full-color RGBA, 2x supersampling, 16 samples',
            'bounds_checked': True, 'visual_acceptance': 'pending final in-game manual review', 'roles': {}}
for role, directory, model, output, frames, size, columns in roles:
    atlas = Image.new('RGBA', (columns * size, ((frames + columns - 1) // columns) * size))
    assert max(atlas.size) <= 8192, f'{role} exceeds Factorio sprite dimensions'
    assert len(list(directory.glob('*.png'))) == frames, f'{role} frame count mismatch'
    for index in range(frames):
        with Image.open(directory / f'{index:03d}.png') as raw:
            cell = raw.convert('RGBA').resize((size, size), Image.Resampling.LANCZOS)
        bounds = cell.getbbox()
        assert bounds and min(bounds[:2]) >= 2 and max(bounds[2:]) <= size - 2, (role, index, bounds)
        atlas.paste(cell, (index % columns * size, index // columns * size))
    destination = repo / 'sprites' / output
    atlas.save(destination)
    manifest['roles'][role] = {'source': 'astra/' + model,
        'source_sha256': hashlib.sha256((source / model).read_bytes()).hexdigest(),
        'sprite': output, 'frames': frames, 'columns': columns, 'cell': [size, size],
        'atlas': list(atlas.size), 'sprite_sha256': hashlib.sha256(destination.read_bytes()).hexdigest()}
    print(role, frames, atlas.size, destination)
# The icon keeps visible impellers; the game body relies on its separate moving overlays.
with Image.open(source / 'main-review' / '080.png') as image:
    icon = image.convert('RGBA')
    for output, size in [('drone-icon.png', 200), ('drone-map.png', 128)]:
        icon.resize((size, size), Image.Resampling.LANCZOS).save(repo / 'sprites' / output)
(repo / 'art/entourage/manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
