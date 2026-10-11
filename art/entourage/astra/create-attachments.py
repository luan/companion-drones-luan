"""Create isolated dynamic attachments from the approved model materials.

Blender --background --python create-attachments.py -- rotor|landing-gear
"""
from pathlib import Path
import math
import sys
import bpy
from mathutils import Vector
P=Path(__file__).parent
ROLE=sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.open_mainfile(filepath=str(P/('entourage.blend' if ROLE=='rotor' else 'manager.blend')))
scene=bpy.context.scene
body_root=bpy.data.objects['Airframe rotation']
body_root.animation_data_clear();body_root.rotation_euler=(0,0,0)
bpy.context.view_layer.update()
bpy.context.preferences.filepaths.save_version=0
if ROLE=='rotor':
    source=bpy.data.objects['Lift rotor']
    center=source.matrix_world.translation.copy()
    blades=list(source.children)
    for blade in blades:
        matrix=blade.matrix_world.copy();blade.parent=None;blade.matrix_world=matrix
        blade.location-=center
    for obj in list(bpy.data.objects):
        if obj not in blades:bpy.data.objects.remove(obj,do_unlink=True)
    bpy.ops.object.empty_add();root=bpy.context.object;root.name='Rotor phase'
    for blade in blades:blade.parent=root
    # The baked hub sits above the impellers. Punch out its silhouette so the
    # overlay cannot paint moving blades over that retained body geometry.
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=.0355,depth=.023,location=(0,0,.015))
    hub=bpy.context.object;hub.name='Baked hub occlusion (holdout)'
    bevel=hub.modifiers.new('Machined hub edge','BEVEL');bevel.width=.0051;bevel.segments=2
    hub.modifiers.new('Hub normals','WEIGHTED_NORMAL')
    for f in hub.data.polygons:f.use_smooth=True
    m=bpy.data.materials.new('Invisible retained hub');m.use_nodes=True
    nodes=m.node_tree.nodes;nodes.clear();out=nodes.new('ShaderNodeOutputMaterial');hold=nodes.new('ShaderNodeHoldout');m.node_tree.links.new(hold.outputs[0],out.inputs['Surface']);hub.data.materials.append(m)
    # Mask at the actual top mouth plane, not at the lower impeller plane.
    # This also removes the foreground strip otherwise hidden by the cast lip.
    vertices=[];faces=[]
    for radius in [.128,.4]:
        for i in range(96):
            a=i*math.tau/96;vertices.append((radius*math.cos(a),radius*math.sin(a),.065))
    for i in range(96):faces.append((i,(i+1)%96,(i+1)%96+96,i+96))
    data=bpy.data.meshes.new('Duct mouth alpha mask');data.from_pydata(vertices,[],faces);data.update()
    mask=bpy.data.objects.new('Retained duct rim occlusion (holdout)',data);scene.collection.objects.link(mask);mask.data.materials.append(m)
    scene.frame_start=1;scene.frame_end=16
    for frame in range(1,17):
        root.rotation_euler.z=(frame-1)*math.tau/(9*16)
        root.keyframe_insert('rotation_euler',frame=frame)
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(P/'rotor.blend'))
    raise SystemExit
if ROLE!='landing-gear':raise ValueError(ROLE)
for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
collection=bpy.data.collections.new('Utility landing gear');scene.collection.children.link(collection)
materials={n:bpy.data.materials[n] for n in ['cast steel','edge steel','graphite','rubber','heat shield','armor']}

def own(obj,name,material):
    obj.name=name
    for c in list(obj.users_collection):c.objects.unlink(obj)
    collection.objects.link(obj);obj.data.materials.append(materials[material])
    for face in obj.data.polygons:face.use_smooth=True
    return obj

def cylinder(name,p,r,d,material,axis=(0,0,1),vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=d,location=p)
    o=own(bpy.context.object,name,material);o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler()
    bevel=o.modifiers.new('Machined radius','BEVEL');bevel.width=min(.008,r*.18);bevel.segments=3
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return o

def box(name,p,size,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=own(bpy.context.object,name,material);o.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    bevel=o.modifiers.new('Cast edges','BEVEL');bevel.width=.015;bevel.segments=3
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return o

def aim(o,a,b,length):
    o.location=(a+b)/2;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();o.scale.z=(b-a).length/length

def key(o,frame):
    for attr in ['location','rotation_euler','scale']:o.keyframe_insert(attr,frame=frame)

# Ground plane compensates exactly for a 0.25-tile hover offset at utility scale.
up_z=6/math.sqrt(6**2+8.82**2)
units_to_tiles=(320/2.6)*.25*.55/32
sole_z=.18-.25/(up_z*units_to_tiles)
for leg,(sx,sy) in enumerate([(-1,-1),(1,-1),(-1,1),(1,1)]):
    mount=Vector((sx*.215,sy*.205,.18))
    prefix=f'Leg {leg+1} '
    mount_block=box(prefix+'belly clevis',mount,(.115,.09,.075),'heat shield')
    mount_pin=cylinder(prefix+'mount pin',mount,.031,.125,'edge steel',(1,0,0),8)
    upper=box(prefix+'upper casting',(0,0,0),(.069,.054,.255),'cast steel')
    inset=box(prefix+'upper armor rib',(0,0,0),(.038,.015,.18),'armor')
    knee=cylinder(prefix+'knee casting',(0,0,0),.052,.080,'heat shield',(0,1,0),12)
    pin=cylinder(prefix+'knee axle',(0,0,0),.025,.094,'edge steel',(0,1,0),8)
    sleeve=cylinder(prefix+'telescopic sleeve',(0,0,0),.040,.185,'cast steel')
    collar=cylinder(prefix+'sleeve collar',(0,0,0),.047,.030,'heat shield')
    piston=cylinder(prefix+'polished ram',(0,0,0),.022,.20,'edge steel')
    boot=cylinder(prefix+'ankle boot',(0,0,0),.038,.085,'graphite')
    ankle=cylinder(prefix+'foot pivot',(0,0,0),.033,.094,'heat shield',(1,0,0),12)
    sole=box(prefix+'rubber sole',(0,0,0),(.16,.20,.035),'rubber')
    shoe=box(prefix+'cast foot',(0,0,0),(.145,.177,.035),'cast steel')
    toe=box(prefix+'toe plate',(0,0,0),(.12,.035,.014),'edge steel')
    parts=[upper,inset,knee,pin,sleeve,collar,piston,boot,ankle,sole,shoe,toe]
    for frame in range(1,33):
        t=(frame-1)/31;e=t*t*(3-2*t)
        # The cast upper link holds its length; the lower link telescopes.
        folded=Vector((sx*.025,-sy*.20,-.156)).normalized()
        deployed=Vector((sx*.17,sy*.075,-.175)).normalized()
        knee_pos=mount+folded.lerp(deployed,e).normalized()*.255
        folded_direction=Vector((-sx*.03,sy*.21,-.025)).normalized()
        deployed_direction=Vector((sx*.035,sy*.08,-.60)).normalized()
        direction=folded_direction.lerp(deployed_direction,e).normalized()
        deployed_knee=mount+deployed*.255
        # Bottom of the rubber sole, rather than its center, reaches ground.
        end_length=(sole_z+.0175-deployed_knee.z)/deployed_direction.z
        length=.215+(end_length-.215)*e
        foot=knee_pos+direction*length
        aim(upper,mount,knee_pos,.255)
        inset.rotation_euler=upper.rotation_euler;inset.location=(mount+knee_pos)/2+Vector((sx*.039,0,0))
        knee.location=pin.location=knee_pos
        aim(sleeve,knee_pos,knee_pos+direction*.185,.185)
        collar.location=knee_pos+direction*.17;collar.rotation_euler=direction.to_track_quat('Z','Y').to_euler()
        aim(piston,knee_pos+direction*.17,foot,.20)
        aim(boot,foot-direction*.085,foot,.085)
        ankle.location=foot+Vector((0,0,.025))
        sole.location=foot;shoe.location=foot+Vector((0,0,.032))
        toe.location=foot+Vector((0,sy*.068,.055))
        for obj in parts:key(obj,frame)
scene.frame_start=1;scene.frame_end=32;scene.frame_set(1)
scene['utility_ground_sole_z']=sole_z
scene['utility_hover_tiles']=.25
scene['fixed_orientation']=.5
bpy.ops.wm.save_as_mainfile(filepath=str(P/'landing-gear.blend'))
print('Utility landing sole z:',sole_z)
