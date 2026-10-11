"""Full-color Factorio sprites: physical orthographic projection and antialiasing.

Candidate preview renderer adapted from ../render.py.
Run inside Blender with -- SOURCE OUTPUT [--preview | --full] [--views 16] [--mask]. Does not change the source.
The pixel-art export is deliberately bypassed: Factorio needs soft alpha and shading.
"""
import argparse
from pathlib import Path
import math
import sys
import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--preview', action='store_true')
parser.add_argument('--views', type=int, default=16)
parser.add_argument('--full', action='store_true', help='Export every frame; body atlases exclude moving impellers')
parser.add_argument('--mask', action='store_true', help='Render neutral shaded player-paint layers with hardware occlusion')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
args.output.mkdir(parents=True, exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(args.source.resolve()))
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.taa_render_samples = 16
rotor_asset = args.source.stem == 'rotor'
landing = args.source.stem == 'landing-gear'
scene.render.resolution_x = scene.render.resolution_y = 192 if rotor_asset else 640
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.use_compositing = scene.render.use_sequencer = False
scene.world = bpy.data.worlds.new('Studio fill')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.32, .35, .38, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .4
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'

if args.mask:
    if rotor_asset or landing:
        parser.error('--mask applies only to main, utility, and combat bodies')
    # Structural shells share cast steel with mechanisms in the source. These
    # named outer plates are paintable; the underlying machinery remains bare.
    paint_panels = ('Overlapping cheek plate', 'Port shoulder',
                    'Starboard shoulder', 'Utility rear shell')
    paint = bpy.data.materials['armor'].copy()
    paint.name = 'Neutral player paint'
    shader = paint.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (.7, .7, .7, 1)
    shader.inputs['Metallic'].default_value = .15
    shader.inputs['Roughness'].default_value = .56
    for node in paint.node_tree.nodes:
        if node.type == 'VALTORGB':
            for element, value in zip(node.color_ramp.elements, [.56, .85]):
                element.color = (value, value, value, 1)
    occluder = bpy.data.materials.new('Retained hardware holdout')
    occluder.use_nodes = True
    nodes = occluder.node_tree.nodes
    nodes.clear()
    output = nodes.new('ShaderNodeOutputMaterial')
    holdout = nodes.new('ShaderNodeHoldout')
    occluder.node_tree.links.new(holdout.outputs[0], output.inputs['Surface'])
    for obj in bpy.data.objects:
        if obj.type not in {'MESH', 'CURVE'}:
            continue
        painted = any(mat and mat.name == 'armor' for mat in obj.data.materials)
        painted = painted or obj.name.startswith(paint_panels)
        obj.data.materials.clear()
        obj.data.materials.append(paint if painted else occluder)
    # Neutral illumination yields equal RGB channels for multiplicative tint.
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.35, .35, .35, 1)

camera = bpy.data.objects.new('Factorio camera', bpy.data.cameras.new('Factorio camera'))
scene.collection.objects.link(camera)
camera.data.type = 'ORTHO'
camera.data.ortho_scale = .78 if rotor_asset else 2.6
# Keep the body camera's exact view vector when centering an isolated rotor.
camera.location = (0, -6, 8.82) if rotor_asset else (0, -6, 9)
combat = args.source.stem == 'combat'
target = Vector((0, 0, 0 if rotor_asset else .18))
camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera = camera
for name, location, energy, size in [
    ('Key', (-3, -4, 7), 350, 4), ('Fill', (4, -1, 4), 90, 5), ('Rim', (1, 4, 5), 160, 3),
]:
    lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, 'AREA'))
    scene.collection.objects.link(lamp)
    lamp.location = location
    lamp.rotation_euler = (-lamp.location).to_track_quat('-Z', 'Y').to_euler()
    lamp.data.energy, lamp.data.size = energy, size

root = bpy.data.objects.get('Airframe rotation')
if rotor_asset:
    bpy.data.objects['Rotor phase'].animation_data_clear()
count = 16 if rotor_asset else 32 if landing else 512 if combat else 128
if root:
    root.animation_data_clear()
if (args.full or args.mask) and root:
    for rotor in [obj for obj in bpy.data.objects if obj.name.startswith('Lift rotor')]:
        for child in rotor.children_recursive:
            child.hide_render = True
if args.preview:
    indices = [0, 4, 8, 12] if rotor_asset else [0, 10, 21, 31] if landing else [0, 256, 320, 323] if combat else [0, 32, 64, 80]
elif args.full:
    indices = range(count)
else:
    indices = [i * (count // args.views) + (i % 4 if combat else 0) for i in range(args.views)]
for index in indices:
    if root:
        # Factorio orientation zero is north, then clockwise.
        root.rotation_euler.z = math.pi - (index // 4 if combat else index) * math.tau / 128
    if landing:
        scene.frame_set(index + 1)
    if rotor_asset:
        # Nine identical impellers: one blade interval closes the 16-phase loop.
        bpy.data.objects['Rotor phase'].rotation_euler.z = index * math.tau / (9 * 16)
    for rotor in [obj for obj in bpy.data.objects if obj.name.startswith('Lift rotor')]:
        rotor.rotation_euler.z = index * .31
    if combat:
        pulse = [0.85, 1.05, 0.95, 1.15][index % 4]
        root.rotation_euler.x = [0, .035, 0, -.035][index % 4]
        root.rotation_euler.y = [.04, 0, -.04, 0][index % 4]
        for flame in [obj for obj in bpy.data.objects if obj.name.startswith(('Plasma plume', 'Plasma core'))]:
            flame.scale.z = pulse
            flame.location.y = flame['nozzle_y'] + flame['depth'] * pulse / 2
    scene.render.filepath = str((args.output / f'{index:03d}.png').resolve())
    bpy.ops.render.render(write_still=True)
