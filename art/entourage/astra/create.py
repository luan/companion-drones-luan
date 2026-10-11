"""Editable industrial drone candidates. Blender --background --python create.py -- ROLE.

Candidate-only: no game atlas or runtime file is written. Local forward is -Y.
"""
from pathlib import Path
import math
import sys
import bpy
from mathutils import Vector

OUT = Path(__file__).parent
ROLE = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else 'entourage'
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
collection = bpy.data.collections.new('Entourage')
scene.collection.children.link(collection)
bpy.ops.object.empty_add()
root = bpy.context.object
root.name = 'Airframe rotation'
M = {}
for name, color, metal, rough in [
    ('cast steel', (.115,.138,.132), .75,.38),
    ('armor', (.14,.165,.147), .48,.56),
    ('edge steel', (.24,.27,.25), .8,.35),
    ('graphite', (.025,.033,.032), .65,.43),
    ('rubber', (.010,.014,.013), .1,.65),
    ('heat shield', (.10,.074,.045), .7,.54),
    ('warning', (.23,.185,.072), .45,.52),
    ('cyan', (.02,.42,.46), .25,.23),
    ('red', (.36,.045,.016), .25,.3),
    ('plasma', (.035,.19,.48), .05,.3),
    ('plasma-core', (.38,.72,1), 0,.2),
]:
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    n=m.node_tree.nodes;links=m.node_tree.links;p=n.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    if name in ('cyan','red','plasma','plasma-core'):
        p.inputs['Emission Color'].default_value=(*color,1)
        p.inputs['Emission Strength'].default_value=1.6 if name in ('cyan','red') else 3
    elif name != 'rubber':
        noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=38;noise.inputs['Detail'].default_value=3
        ramp=n.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position=.18;ramp.color_ramp.elements[0].color=(*(c*.7 for c in color),1)
        ramp.color_ramp.elements[1].position=.84;ramp.color_ramp.elements[1].color=(*(c*1.16 for c in color),1)
        links.new(noise.outputs['Fac'],ramp.inputs[0]);links.new(ramp.outputs[0],p.inputs['Base Color'])
        bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.1;bump.inputs['Distance'].default_value=.004
        links.new(noise.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs[0],p.inputs['Normal'])
    M[name]=m

def own(o,name,mat,smooth=True):
    o.name=name
    for c in list(o.users_collection): c.objects.unlink(o)
    collection.objects.link(o);o.parent=root
    o.data.materials.append(M[mat])
    if hasattr(o.data,'polygons'):
        for f in o.data.polygons:f.use_smooth=smooth
    return o

def mesh(name,verts,faces,mat,bevel=0,smooth=True):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    o=bpy.data.objects.new(name,data);collection.objects.link(o);own(o,name,mat,smooth)
    if bevel:
        b=o.modifiers.new('Radiused edges','BEVEL');b.width=bevel;b.segments=3
        o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o

def box(name,p,s,mat='cast steel',bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=own(bpy.context.object,name,mat,False);o.scale=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    b=o.modifiers.new('Machined radius','BEVEL');b.width=bevel;b.segments=4
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return o

def ellipsoid(name,p,s,mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48,ring_count=24,location=p)
    o=own(bpy.context.object,name,mat);o.scale=s;return o

def cylinder(name,p,r,d,mat='cast steel',axis=(0,0,1),vertices=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=d,location=p)
    o=own(bpy.context.object,name,mat);o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler()
    b=o.modifiers.new('Machined edge','BEVEL');b.width=min(.012,r*.15);b.segments=2
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');return o

def link(name,a,b,r,mat='cast steel'):
    a,b=Vector(a),Vector(b);return cylinder(name,(a+b)/2,r,(b-a).length,mat,b-a)

def torus(name,p,r,t,mat='edge steel',axis=(0,0,1)):
    bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=12,major_radius=r,minor_radius=t,location=p)
    o=own(bpy.context.object,name,mat);o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler();return o

def tube(name,pts,r,mat):
    data=bpy.data.curves.new(name,'CURVE');data.dimensions='3D';data.resolution_u=12
    data.bevel_depth=r;data.bevel_resolution=3
    s=data.splines.new('BEZIER');s.bezier_points.add(len(pts)-1)
    for b,p in zip(s.bezier_points,pts):b.co=p;b.handle_left_type=b.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,data);collection.objects.link(o);own(o,name,mat);return o

def bolt(p,r=.016,axis=(0,0,1)):
    cylinder('Recess washer',p,r*1.4,.008,'graphite',axis)
    cylinder('Hex fastener',Vector(p)+Vector(axis)*.008,r,.015,'edge steel',axis,6)

def shell(name,p,s,theta,phi,mat='armor'):
    # Individual compound-curved cast plates, separated by real dark seams.
    verts=[];faces=[];nu,nv=24,12
    for j in range(nv+1):
        b=phi[0]+(phi[1]-phi[0])*j/nv
        for i in range(nu+1):
            a=theta[0]+(theta[1]-theta[0])*i/nu
            verts.append((p[0]+s[0]*math.sin(b)*math.cos(a),p[1]+s[1]*math.sin(b)*math.sin(a),p[2]+s[2]*math.cos(b)))
    for j in range(nv):
        for i in range(nu):
            a=j*(nu+1)+i;faces.append((a,a+1,a+nu+2,a+nu+1))
    o=mesh(name,verts,faces,mat)
    solid=o.modifiers.new('Cast thickness','SOLIDIFY');solid.thickness=.019
    bevel=o.modifiers.new('Soft panel lip','BEVEL');bevel.width=.008;bevel.segments=3
    return o

def panel(name,outline,z,thickness,mat='armor'):
    verts=[(x,y,z) for x,y in outline]+[(x,y,z+thickness) for x,y in outline];n=len(outline)
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    faces +=[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,verts,faces,mat,.025,False)

def eye(p,r=.06):
    cylinder('Optical socket',p,r*1.55,.065,'graphite',(0,-1,.08))
    torus('Optical ring',(p[0],p[1]-.038,p[2]),r*1.15,.012,'edge steel',(0,-1,.08))
    lens=ellipsoid('Recessed cyan optic',(p[0],p[1]-.040,p[2]),(r,.016,r),'cyan')

def pod(x,y,scale=1):
    # Cast nacelle with a rounded rectangular outer envelope and a true open duct.
    rings=[(-.12,.13,.16),(-.07,.205,.25),(.18,.225,.27),(.30,.196,.23),(.35,.158,.158),(.28,.132,.132)]
    verts=[];faces=[];n=48
    for j,(z,rx,ry) in enumerate(rings):
        power=.77 if j<4 else 1
        for k in range(n):
            a=k*math.tau/n;c=math.cos(a);d=math.sin(a)
            verts.append((x+rx*scale*math.copysign(abs(c)**power,c),y+ry*scale*math.copysign(abs(d)**power,d),z*scale))
    for j in range(len(rings)-1):
        for k in range(n):faces.append((j*n+k,j*n+(k+1)%n,(j+1)*n+(k+1)%n,(j+1)*n+k))
    mesh('Cast open lift nacelle',verts,faces,'cast steel',.006)
    cylinder('Deep duct shadow',(x,y,.26*scale),.131*scale,.01,'rubber')
    torus('Duct cast rim',(x,y,.35*scale),.157*scale,.013*scale,'edge steel')
    torus('Inner duct liner',(x,y,.30*scale),.132*scale,.007*scale,'heat shield')
    bpy.ops.object.empty_add(location=(x,y,.285*scale));rotor=bpy.context.object;rotor.name='Lift rotor';rotor.parent=root
    for k in range(9):
        a=k*math.tau/9
        vane=box('Recessed impeller',(x+.070*scale*math.cos(a),y+.070*scale*math.sin(a),.285*scale),(.135*scale,.024*scale,.012*scale),'cast steel',.003);vane.rotation_euler.z=a+.48
        bpy.context.view_layer.update()
        position=vane.matrix_world.copy();vane.parent=rotor;vane.matrix_world=position
    cylinder('Duct hub',(x,y,.30*scale),.034*scale,.023*scale,'heat shield')
    for sign in [-1,1]:
        box('Nacelle split armor',(x+sign*.209*scale,y,.10*scale),(.038*scale,.29*scale,.18*scale),'armor',.025*scale)
        for yy in [-.08,-.035,.01,.055,.10]:
            box('Engine cooling recess',(x+sign*.23*scale,y+yy*scale,.10*scale),(.009*scale,.020*scale,.09*scale),'graphite',.004)
        for yy in [-.16,.16]:bolt((x+sign*.14*scale,y+yy*scale,.297*scale),.012*scale)
    cylinder('Exposed lower engine',(x,y,-.09*scale),.137*scale,.12*scale,'heat shield',vertices=16)
    for z in [-.12,-.075,-.035]:torus('Lower engine cooling fin',(x,y,z*scale),.14*scale,.011*scale,'cast steel')
    cylinder('Lift glow',(x,y,-.153*scale),.064*scale,.016*scale,'cyan')

def mechanical_arm(x,y):
    a=(x*.62,y*.86,.15);b=(x,y,.04);c=(x*.97,y*.96,-.13)
    link('Landing upper casting',a,b,.046,'cast steel');link('Landing ram',a,(x*.94,y*.98,.0),.019,'edge steel')
    cylinder('Landing knee',b,.065,.075,'graphite',(0,1,0));cylinder('Knee axle',b,.033,.084,'edge steel',(0,1,0))
    link('Folded lower landing link',b,c,.037,'cast steel')
    box('Folded landing shoe',c,(.12,.19,.041),'graphite',.03)

if ROLE=='entourage':
    ellipsoid('Pressure hull',(0,.0,.23),(.51,.64,.35),'graphite')
    ellipsoid('Structural belly',(0,.035,.035),(.43,.55,.21),'cast steel')
    # Large uninterrupted forehead, paired shoulder shells and rear service shell.
    shell('Center forehead plate',(0,-.01,.23),(.523,.671,.37),(math.pi*1.32,math.pi*1.68),(.08,1.49),'armor')
    for lo,hi in [(math.pi+.045,math.pi*1.305),(math.pi*1.695,math.tau-.045)]:
        shell('Overlapping cheek plate',(0,-.01,.22),(.523,.675,.345),(lo,hi),(.38,1.54),'cast steel')
        shell('Cheek brow armor',(0,-.01,.23),(.535,.68,.38),(lo+.02,hi-.02),(.38,.69),'armor')
    shell('Port shoulder',(0,0,.23),(.526,.666,.369),(.06,math.pi/2-.05),(.08,1.55),'cast steel')
    shell('Starboard shoulder',(0,0,.23),(.526,.666,.369),(math.pi/2+.05,math.pi-.06),(.08,1.55),'cast steel')
    # Narrow cast seam band divides the dome without turning it into a crate.
    tube('Crown seam rim',[(-.48,0,.38),(-.3,0,.545),(0,0,.60),(.3,0,.545),(.48,0,.38)],.013,'edge steel')
    for x in [-.36,-.19,.19,.36]:bolt((x,.025,.23+.366*math.sqrt(1-(x/.526)**2)),.014)
    for x in [-.63,.63]:
        for y in [-.38,.39]:
            link('Short cast outrigger',(x*.60,y*.85,.12),(x,y,.15),.089,'cast steel')
            pod(x,y)
            tube('Braided lift feed',[(x*.60,y*.7,.26),(x*.76,y*.9,.24),(x,y,.23)],.023,'rubber')
    # Front optical bank follows the hull curve; no protruding cuboid face.
    ellipsoid('Optical hood',(0,-.558,.29),(.27,.15,.19),'cast steel')
    eye((-.060,-.689,.31),.047);eye((.075,-.688,.31),.028)
    box('Optical brow',(0,-.68,.442),(.30,.07,.035),'armor',.025)
    for x in [-.21,.21]:bolt((x,-.641,.32),.014,(0,-1,.1))
    for sign in [-1,1]:
        mount=box('Optics side mount',(sign*.224,-.638,.245),(.065,.17,.18),'heat shield',.021)
        cylinder('Optics pivot pin',(sign*.259,-.647,.286),.027,.025,'edge steel',(1,0,0),8)
        box('Front hydraulic block',(sign*.25,-.565,.07),(.17,.19,.17),'heat shield',.033)
        cylinder('Front hydraulic clevis',(sign*.25,-.67,.085),.050,.064,'cast steel',(0,-1,0),12)
        tube('Front protected umbilical',[(sign*.31,-.51,.21),(sign*.37,-.58,.11),(sign*.25,-.66,.045)],.025,'rubber')
        link('Front ram',(sign*.33,-.51,.03),(sign*.33,-.51,-.15),.018,'edge steel')
    box('Lower optical frame',(0,-.66,.165),(.34,.09,.045),'cast steel',.013)
    for x in [-.105,-.07,-.035,0,.035,.07,.105]:box('Front cooling teeth',(x,-.685,.157),(.019,.015,.028),'graphite',.004)

    # Shoulder gills and curved protected feed lines add layered engineering.
    for sign in [-1,1]:
        tube('Protected shoulder line',[(sign*.39,-.39,.30),(sign*.51,-.15,.26),(sign*.51,.22,.23),(sign*.35,.48,.24)],.021,'heat shield')
        for y in [-.19,-.11,-.03,.05,.13]:
            g=box('Side cooling louver',(sign*.485,y,.30),(.07,.032,.13),'graphite',.008);g.rotation_euler.y=sign*.5
        for y in [-.36,0,.35]:mechanical_arm(sign*.43,y)
    box('Rear radiator frame',(0,.34,.558),(.44,.31,.035),'graphite',.025).rotation_euler.x=-.5
    for y in [.22,.26,.30,.34,.38,.42,.46]:
        fin=box('Radiator blades',(0,y,.587-(y-.34)*.52),(.38,.021,.032),'cast steel',.007);fin.rotation_euler.x=-.5
    for x in [-.235,.235]:
        cylinder('Rear power connector',(x,.525,.32),.064,.08,'heat shield',(0,1,.3))
        tube('Armored power loop',[(x,.56,.30),(x,.64,.16),(x*.55,.58,.05)],.035,'graphite')
    # A flush service cap closes the three-way crown seam.
    cylinder('Crown service gasket',(0,-.005,.609),.075,.018,'graphite')
    cylinder('Crown service cap',(0,-.005,.625),.060,.016,'cast steel')
    box('Service cap keyway',(0,-.005,.636),(.060,.012,.008),'graphite',.004)
    # Front plate boundary: meaningful curved seams and their fasteners.
    for sign in [-1,1]:
        pts=[]
        for k in range(13):
            a=math.pi+(.22+1.12*k/12) if sign<0 else math.tau-(.22+1.12*k/12)
            pts.append((.548*math.sin(.96)*math.cos(a),-.01+.692*math.sin(.96)*math.sin(a),.23+.39*math.cos(.96)))
        tube('Forehead lower panel seam',pts,.010,'graphite')
        for k in [2,7,11]:bolt(pts[k],.012)
        # Exposed joint castings break the lower silhouette into machinery.
        for y in [-.23,.05,.31]:
            x=sign*.48
            cylinder('Underframe joint block',(x,y,.10),.086,.12,'heat shield',(1,0,0),12)
            cylinder('Underframe axle',(x+sign*.068,y,.10),.040,.018,'edge steel',(1,0,0),8)
            link('Short armored actuator',(x,y,.06),(x+sign*.07,y-.03,-.08),.027,'cast steel')
        tube('Lower perimeter conduit',[(sign*.33,-.44,.03),(sign*.49,-.28,-.02),(sign*.49,.18,-.02),(sign*.33,.49,.04)],.027,'rubber')
        tube('Bright hydraulic return',[(sign*.38,-.38,.02),(sign*.48,-.23,.02),(sign*.48,.19,.02)],.012,'edge steel')
    # Asymmetric replaceable equipment breaks the idealized smooth envelope.
    bracket=box('Rear cooling manifold saddle',(-.29,.33,.53),(.27,.20,.075),'heat shield',.024);bracket.rotation_euler.x=-.32
    for x in [-.385,-.30,-.215]:
        cylinder('Raised rear heat exchanger',(x,.345,.59),.037,.16,'cast steel',(0,.8,.6),12)
        torus('Heat exchanger lip',(x,.408,.636),.035,.009,'heat shield',(0,.8,.6))
        cylinder('Heat exchanger bore',(x,.412,.639),.026,.012,'rubber',(0,.8,.6))
    ellipsoid('Side drive cover',(.485,.035,.31),(.083,.23,.105),'heat shield')
    for y in [-.10,-.02,.06,.14]:
        box('Side drive strap',(.545,y,.323),(.025,.025,.145),'cast steel',.008).rotation_euler.y=.22
    cylinder('Whip socket',(.30,.24,.52),.041,.055,'heat shield')
    tube('Flexible antenna',[(.30,.24,.55),(.31,.28,.77),(.34,.32,.94)],.007,'edge steel')
    for x in [-.26,.26]:
        stripe=box('Muted service marking',(x,-.345,.515),(.034,.11,.007),'warning',.008);stripe.rotation_euler.x=.6;stripe.rotation_euler.y=x*1.1
elif ROLE=='manager':
    ellipsoid('Utility belly',(0,0,.16),(.34,.40,.22),'graphite')
    shell('Utility front hood',(0,.015,.18),(.35,.43,.25),(math.pi+.03,math.tau-.03),(.10,1.57),'armor')
    shell('Utility rear shell',(0,.015,.18),(.345,.413,.255),(.03,math.pi-.03),(.1,1.57),'cast steel')
    tube('Utility hood seam',[(-.33,0,.285),(-.20,0,.405),(0,0,.449),(.20,0,.405),(.33,0,.285)],.011,'graphite')
    for sign in [-1,1]:
        box('Utility arm clevis',(sign*.21,-.28,.13),(.12,.14,.15),'heat shield',.029)
        cylinder('Utility shoulder pivot',(sign*.268,-.29,.14),.044,.03,'edge steel',(1,0,0),8)
        tube('Utility shoulder cable',[(sign*.29,-.05,.28),(sign*.32,-.2,.20),(sign*.2,-.31,.13)],.018,'rubber')
    for x in [-.43,.43]:
        pod(x,.10,.75)
        link('Compact outrigger',(x*.50,.10,.13),(x,.10,.16),.07)
    panel('Rear tool cassette',[(-.19,.09),(.19,.09),(.17,.31),(-.17,.31)],.39,.033,'graphite')
    for y in [.135,.19,.245]:box('Tool cassette rib',(0,y,.437),(.29,.021,.025),'edge steel',.008)
    eye((0,-.40,.25),.051)
    for sign in [-1,1]:
        a=(sign*.19,-.22,.13);b=(sign*.31,-.46,-.025);c=(sign*.16,-.65,-.035)
        link('Manipulator upper casting',a,b,.052)
        link('Hydraulic bright rod',(sign*.205,-.27,.16),(sign*.29,-.44,.035),.019,'edge steel')
        cylinder('Manipulator elbow',b,.062,.072,'graphite',(0,1,0))
        link('Manipulator forearm',b,c,.041,'edge steel')
        for dy in [-.04,.04]:
            link('Pincer finger',(c[0],c[1]+dy,c[2]),(c[0]-sign*.07,c[1]+dy,c[2]-.05),.019,'graphite')
        tube('Tool pressure hose',[a,(sign*.35,-.36,.04),b,c],.012,'rubber')
        box('Utility service mark',(sign*.235,-.08,.367),(.055,.18,.009),'warning',.009).rotation_euler.y=sign*.55
    cylinder('Utility antenna socket',(.17,.24,.43),.025,.035,'graphite')
    link('Utility aerial',(.17,.24,.45),(.18,.29,.64),.006,'edge steel')
elif ROLE=='combat':
    # Flattened manta outline, swept armored shoulders, deeply recessed weapon rails.
    outline=[(0,-.80),(.17,-.42),(.43,-.13),(.57,.39),(.37,.31),(.23,.49),(-.23,.49),(-.37,.31),(-.57,.39),(-.43,-.13),(-.17,-.42)]
    panel('Manta underframe',outline,.105,.075,'graphite')
    ellipsoid('Armored central fuselage',(0,-.10,.205),(.185,.60,.15),'cast steel')
    for sign in [-1,1]:
        wing=[(sign*.06,-.59),(sign*.21,-.35),(sign*.40,-.07),(sign*.52,.31),(sign*.35,.245),(sign*.23,.37),(sign*.13,.19)]
        if sign<0:wing.reverse()
        panel('Swept shoulder armor',wing,.20,.095,'armor')
        # Engine envelope is a tapered elliptical loft along the flight axis.
        verts=[];faces=[];rings=[(-.08,.074),(.02,.112),(.30,.116),(.46,.087)]
        for y,r in rings:
            for k in range(32):
                a=k*math.tau/32;verts.append((sign*.30+r*math.cos(a),y,.27+r*.78*math.sin(a)))
        for j in range(3):
            for k in range(32):faces.append((j*32+k,j*32+(k+1)%32,(j+1)*32+(k+1)%32,(j+1)*32+k))
        mesh('Tapered plasma engine',verts,faces,'heat shield',.008)
        verts=[];faces=[]
        for j,(y,r) in enumerate([(-.045,.073),(.06,.117),(.23,.118),(.34,.108)]):
            for k in range(17):
                a=.12+math.pi*.93*k/16
                verts.append((sign*.30+r*math.cos(a),y,.27+r*.90*math.sin(a)))
        for j in range(3):
            for k in range(16):
                a=j*17+k;faces.append((a,a+1,a+18,a+17))
        shroud=mesh('Sculpted reactor heat shroud',verts,faces,'cast steel',.008)
        wall=shroud.modifiers.new('Shroud thickness','SOLIDIFY');wall.thickness=.013
        for y in [.03,.085,.14,.195,.25]:
            slot=box('Reactor dorsal vent',(sign*.30,y,.382),(.092,.025,.01),'graphite',.005)
        for k in range(8):
            a=k*math.tau/8
            flap=box('Segmented exhaust flap',(sign*.30+.09*math.cos(a),.43,.27+.09*math.sin(a)),(.043,.085,.014),'edge steel',.007)
            flap.rotation_euler.y=-a

        torus('Deep exhaust lip',(sign*.30,.465,.27),.084,.016,'edge steel',(0,1,0))
        cylinder('Plasma nozzle',(sign*.30,.469,.27),.068,.022,'plasma-core',(0,1,0))
        for name,r,d,mat in [('Plasma plume',.062,.28,'plasma'),('Plasma core',.027,.21,'plasma-core')]:
            bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=r,radius2=.002,depth=d)
            o=own(bpy.context.object,name,mat);o.rotation_euler.x=-math.pi/2;o.location=(sign*.30,.48+d/2,.27);o['depth']=d;o['nozzle_y']=.48
        link('Recessed twin weapon',(sign*.265,-.24,.16),(sign*.265,-.61,.16),.034,'graphite')
        torus('Weapon muzzle',(sign*.265,-.62,.16),.031,.009,'edge steel',(0,1,0))
        cylinder('Weapon aperture',(sign*.265,-.63,.16),.019,.015,'red',(0,1,0))
        for y in [-.10,-.015,.07]:
            g=box('Wing heat slit',(sign*.40,y,.307),(.09,.022,.011),'graphite',.005);g.rotation_euler.z=-sign*.46
        for x,y in [(sign*.21,-.25),(sign*.45,.22)]:bolt((x,y,.302),.012)
    ellipsoid('Dorsal reactor',(0,.12,.29),(.125,.27,.09),'graphite')
    for y in [-.025,.035,.095,.155,.215]:box('Dorsal reactor louver',(0,y,.365),(.18,.022,.026),'edge steel',.006)
    box('Recessed targeting slit',(0,-.44,.32),(.115,.028,.033),'red',.008)
else:
    raise ValueError(ROLE)

for frame in range(1,129):
    root.rotation_euler.z=math.pi-(frame-1)*math.tau/128
    root.keyframe_insert('rotation_euler',frame=frame)
scene.frame_start=1;scene.frame_end=128;scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(ROLE+'.blend')))
