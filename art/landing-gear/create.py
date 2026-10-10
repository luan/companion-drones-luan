"""Renderable landing gear for the existing companion torso; run inside Blender."""
from pathlib import Path
import math
import bpy
from mathutils import Vector

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
collection=bpy.data.collections.new('Landing Gear')
scene.collection.children.link(collection)
materials={}
for name,color in {'housing':(0.28,0.19,0.10),'steel':(0.29,0.32,0.33),'chrome':(0.58,0.61,0.61),'rubber':(0.045,0.045,0.04),'cyan':(0.07,0.54,0.59)}.items():
    material=bpy.data.materials.new(name)
    material.diffuse_color=(*color,1)
    materials[name]=material

def own(obj,name,material):
    obj.name=name
    for old in list(obj.users_collection): old.objects.unlink(obj)
    collection.objects.link(obj)
    obj.data.materials.append(materials[material])
    for polygon in obj.data.polygons: polygon.use_smooth = True
    return obj

def cylinder(name,a,b,radius,material):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=radius,depth=(b-a).length,location=(a+b)/2)
    obj=own(bpy.context.object,name,material)
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    obj['length']=(b-a).length
    return obj

def box(name,location,size,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=location)
    obj=own(bpy.context.object,name,material)
    obj.scale=size
    bevel=obj.modifiers.new('Rounded housing','BEVEL')
    bevel.width=.06; bevel.segments=4
    return obj

# Four short hydraulic struts with rounded joints, metal sleeves and rubber pads.
for leg,(sx,sy) in enumerate([(-1,-1),(1,-1),(-1,1),(1,1)]):
    for frame in range(1,7):
        extension=(frame-1)/5
        mount=Vector((sx*.34,sy*.25,.44))
        knee=Vector((sx*(.38+.23*extension),sy*(.28+.13*extension),.30))
        foot=Vector((sx*(.4+.34*extension),sy*(.29+.20*extension),.28*(1-extension)+.055))
        if frame==1:
            upper=cylinder(f'Upper strut {leg}',mount,knee,.075,'housing')
            lower=cylinder(f'Piston {leg}',knee,foot,.04,'chrome')
            sleeve=cylinder(f'Piston sleeve {leg}',knee,knee.lerp(foot,.48),.065,'steel')
            pad=box(f'Foot {leg}',foot,(.25,.19,.07),'rubber')
            plate=box(f'Foot plate {leg}',foot+Vector((0,0,.045)),(.21,.16,.04),'steel')
            bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=16,radius=.09,location=knee)
            joint=own(bpy.context.object,f'Knee {leg}','housing')
            light=box(f'Activity lamp {leg}',knee+Vector((0,0,.075)),(.055,.045,.025),'cyan')
            parts=[upper,lower,sleeve,pad,plate,joint,light]
        for obj,a,b in [(upper,mount,knee),(lower,knee,foot),(sleeve,knee,knee.lerp(foot,.48))]:
            obj.location=(a+b)/2
            obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
            obj.scale.z=(b-a).length/obj['length']
        pad.location=foot; plate.location=foot+Vector((0,0,.045))
        joint.location=knee; light.location=knee+Vector((0,0,.075))
        for obj in parts:
            obj.keyframe_insert('location',frame=frame)
            obj.keyframe_insert('rotation_euler',frame=frame)
            obj.keyframe_insert('scale',frame=frame)
scene.frame_start=1;scene.frame_end=6;scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).with_name('landing-gear.blend')))
