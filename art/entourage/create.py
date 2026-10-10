"""Entourage industrial airframe. Run inside Blender; sources stay editable."""
from pathlib import Path
import math
import bpy
from mathutils import Vector
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
collection=bpy.data.collections.new('Entourage');scene.collection.children.link(collection)
materials={}
for name,color,metal in [('housing',(.40,.28,.14),.35),('steel',(.14,.17,.17),.475),('chrome',(.38,.43,.41),.6),('cyan',(.02,.48,.55),.3),('rubber',(.018,.021,.019),.05)]:
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 shader=m.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(*color,1)
 shader.inputs['Metallic'].default_value=metal;shader.inputs['Roughness'].default_value=.48
 if name=='cyan':
  shader.inputs['Emission Color'].default_value=(*color,1);shader.inputs['Emission Strength'].default_value=.65
 materials[name]=m
bpy.ops.object.empty_add();root=bpy.context.object;root.name='Airframe rotation'
def own(obj,name,material,smooth=False):
 obj.name=name
 for old in list(obj.users_collection):old.objects.unlink(obj)
 collection.objects.link(obj);obj.data.materials.append(materials[material]);obj.parent=root
 for face in obj.data.polygons:face.use_smooth=smooth
 return obj
def box(name,pos,size,mat):
 bpy.ops.mesh.primitive_cube_add(size=1,location=pos)
 obj=own(bpy.context.object,name,mat);obj.scale=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 bevel=obj.modifiers.new('Machined edges','BEVEL');bevel.width=.016;bevel.segments=2
 return obj
def cylinder(name,pos,radius,depth,mat,vertices=32):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=pos)
 return own(bpy.context.object,name,mat,vertices>8)
def pipe(name,a,b,r,mat):
 a,b=Vector(a),Vector(b);obj=cylinder(name,(a+b)/2,r,(b-a).length,mat)
 obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return obj
def ring(name,pos,major,minor,mat):
 bpy.ops.mesh.primitive_torus_add(major_segments=40,minor_segments=8,location=pos,major_radius=major,minor_radius=minor)
 return own(bpy.context.object,name,mat,True)
chassis=cylinder('Octagonal cast chassis',(0,0,.10),.59,.48,'steel',8);chassis.scale.y=.83
armor=cylinder('Bronze segmented armor',(0,0,.25),.555,.23,'housing',8);armor.scale.y=.83
bpy.ops.mesh.primitive_cone_add(vertices=8,radius1=.51,radius2=.40,depth=.12,location=(0,0,.37))
cap=own(bpy.context.object,'Sloped armored shoulders','housing');cap.scale.y=.83
for angle in range(0,360,45):
 a=math.radians(angle)
 cylinder('Armor bolt',(.44*math.cos(a),.36*math.sin(a),.438),.026,.017,'steel',6)
 pipe('Panel seam',(.48*math.cos(a),.40*math.sin(a),.435),(.29*math.cos(a),.24*math.sin(a),.435),.008,'steel')
box('Cooling grille frame',(0,.09,.445),(.30,.38,.035),'steel')
for y in [-.05,0,.05,.10,.15,.20,.25]:box('Radiator fin',(0,y,.475),(.26,.018,.02),'chrome')
for x in [-.34,.34]:
 box('Service hatch',(x,0,.449),(.14,.26,.022),'housing')
 for y in [-.09,.09]:cylinder('Hatch bolt',(x,y,.47),.014,.012,'chrome',6)
box('Optics armored hood',(0,-.43,.21),(.38,.13,.22),'chrome')
box('Dark optics recess',(0,-.509,.21),(.31,.026,.15),'rubber')
for x,r in [(-.075,.05),(.075,.032)]:
 lens=cylinder('Cyan optical lens',(x,-.535,.21),r,.025,'cyan');lens.rotation_euler.x=math.pi/2
for x,y in [(-.66,-.29),(.66,-.29),(-.66,.29),(.66,.29)]:
 pipe('Engine support',(x*.63,y,.06),(x,y,.06),.075,'chrome')
 cylinder('Thruster cast shroud',(x,y,.12),.205,.32,'steel')
 cylinder('Bronze engine armor',(x,y,.16),.197,.20,'housing')
 ring('Upper engine lip',(x,y,.275),.174,.028,'chrome')
 cylinder('Dark turbine throat',(x,y,.259),.15,.026,'rubber')
 for a in range(0,360,45):
  blade=box('Turbine vane',(x+.075*math.cos(math.radians(a)),y+.075*math.sin(math.radians(a)),.28),(.095,.012,.016),'steel')
  blade.rotation_euler.z=math.radians(a)+.3
 cylinder('Turbine hub',(x,y,.289),.035,.025,'chrome')
 ring('Lower thrust collar',(x,y,-.04),.17,.021,'steel')
 for a in range(0,360,90):
  cylinder('Engine casing bolt',(x+.185*math.cos(math.radians(a)),y+.185*math.sin(math.radians(a)),.275),.012,.014,'chrome',6)
 for dy in [-.08,0,.08]:box('Engine warning stripe',(x,y+dy,.285),(.035,.022,.012),'housing')
 cylinder('Thrust activity',(x,y,-.068),.08,.013,'cyan')
for x in [-.39,.39]:
 pipe('Side hydraulic pipe',(x,-.26,.28),(x,-.10,.28),.037,'chrome')
 pipe('Side hydraulic hose',(x,-.10,.28),(x,.22,.28),.038,'rubber')
 for y in [-.26,-.10,.22]:ring('Hose collar',(x,y,.28),.039,.009,'chrome').rotation_euler.x=math.pi/2
box('Rear power cell',(0,.40,.18),(.31,.12,.22),'steel')
for x in [-.10,0,.10]:box('Rear status light',(x,.471,.23),(.035,.015,.035),'cyan')
for frame in range(1,65):
 root.rotation_euler.z=-(frame-1)*2*math.pi/64;root.keyframe_insert('rotation_euler',frame=frame)
scene.frame_start=1;scene.frame_end=64;scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).with_name('entourage.blend')))
