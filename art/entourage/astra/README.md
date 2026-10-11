# Entourage approved model family

Luan approved this design direction. Editable main, utility, combat, rotor, and
utility landing-gear sources are saved here. The models are integrated into the mod’s runtime atlases. Full native and Space
Age suites passed; final visual acceptance remains the in-game manual review.

`lineup.png` shows the family. `comparison.png` compares the original 3.2.1 torso
with the previous and approved models at native scale and 4x enlargement.
`turntable.gif` samples 16 headings. These are offline sprite previews, not game
captures. The enlarged lineup uses illustrative contact shadows.

## Body exports

Run from the repository root; substitute `manager` or `combat` for `entourage`:

```sh
blender --background --python art/entourage/astra/create.py -- entourage
blender --background --python art/entourage/astra/render.py -- \
  art/entourage/astra/entourage.blend /tmp/fresh-main-frames --full
```

`--full` renders 128 main/utility headings or 512 combat frames (128 headings,
four poses). It hides moving `Lift rotor` children while retaining hubs, ducts,
and their body geometry. Preview rendering retains the moving impellers.
The renderer preserves the approved physical orthographic camera, full-color
materials, soft alpha, and antialiasing. Output directories must be fresh.

Final body cells and scales: main 320px at 0.25; utility 320px at 0.25 with runtime
0.55; combat 256px at 0.175. Full body exports render at 640px before packing and
downsampling. `pack.py` validates every cell and packs the exports into the runtime sprites.
For example, put full body exports in MAIN/entourage, MAIN/manager and MAIN/combat:

```sh
python3 art/entourage/astra/pack.py MAIN ROTOR_FRAMES GEAR_FRAMES --masks MASKS
```

The packer also refreshes the icon, minimap image and source/sprite checksum manifest.

## Matching attachments

```sh
blender --background --python art/entourage/astra/create-attachments.py -- rotor
blender --background --python art/entourage/astra/create-attachments.py -- landing-gear
blender --background --python art/entourage/astra/render.py -- \
  art/entourage/astra/rotor.blend /tmp/fresh-rotor-frames --full
blender --background --python art/entourage/astra/render.py -- \
  art/entourage/astra/landing-gear.blend /tmp/fresh-gear-frames --full
```

Prepared candidate atlases:

- `rotor.png`: 16 phases, eight columns, 96px cells; `rotor-frames/` retains the
  192px renders. It contains moving impellers only. Holdout geometry removes the
  baked hub (radius 0.0355) and clips to radius 0.128 at the actual duct lip plane,
  0.065 units above the impeller. No blade can paint across the retained hub or
  foreground lip. Utility rotors additionally scale by 0.75.
- `landing-gear.png`: 32 poses, eight columns, 320px cells; `landing-frames/`
  retains the 640px renders. Four articulated upper castings and telescopic lower
  struts deploy with cubic easing. Read frames in reverse for retraction.
  `landing-preview.png` and `.gif` show them beneath the south-facing utility
  body, including its actual 44px runtime cell.

The landing overlay shares the utility body's center and camera and is drawn
behind it. Use utility runtime scale 0.55 and **no extra position offset**.
Orientation stays 0.5 (south, Blender root angle zero) during deployment and
crafting. The sole plane is z=-0.6604580411943624, calibrated to a final altitude
of 0.25 tiles. The main body's old folded gear is only a static model detail;
crafting landing is implemented by the utility attachment.

Exact camera vectors, projection equations, pod centers, sizes, animation counts,
and ground calibration are recorded in `manifest.json`. The isolated rotor
camera has the same view vector as the body camera: location (0,-6,8.82), target
(0,0,0), orthographic scale 0.78. Its 96px cell therefore has exactly the same
pixel density as the 320px body cell at orthographic scale 2.6.

`preview-attachments.py` downsamples retained attachment frames, packs the two
small atlases, verifies alpha margins and transparent hub centers, and refreshes
attachment previews and manifest. `review.py` refreshes the earlier body-review
images without overwriting integration metadata.

## Player-color paint masks

Append `--mask` to a body export, including `--full`, to render a matching RGBA
player-paint layer. The neutral grayscale material retains surface grain, bump,
and directional shading, with enough value for saturated runtime colors.
It covers the `armor` material, main overlapping cheek and rear shoulder plates,
and the utility rear shell. Combat wings use `armor`. Bare mechanisms, optical
lenses, vents, fasteners, warning marks, reactor parts, and rotors stay untinted.

Nonpaint geometry becomes a transparent holdout during mask rendering, preserving
its front-to-back occlusion rather than exposing paint behind hardware. The camera,
resolution, frame order, combat poses, and alpha edges match the base export.
Moving impellers are excluded. The editable body `.blend` sources are never changed.

`player-color-preview.png` shows red and blue sample tints over the actual packed
base sprites, including native-size examples. `preview-tints.py` rebuilds it from
the small four-angle mask probes and verifies grayscale channels and that paint
alpha stays within the body silhouette. It is an offline composite; in-game tint
propagation is wired to companion paint and owner color changes. Full native
checks cover the main body, utility workers, synchronized combat layers, and
escort expiry; final appearance is reviewed in the running game.
