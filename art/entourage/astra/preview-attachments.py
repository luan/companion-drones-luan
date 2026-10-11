"""Finish and review attachment sprites. Run with uv run --with pillow python."""
from pathlib import Path
import math
import json
from PIL import Image, ImageDraw, ImageFont
P=Path(__file__).parent
font_path='/System/Library/Fonts/Supplemental/Arial.ttf'
def label(im,xy,text,n=17):ImageDraw.Draw(im).text(xy,text,fill='#dde0d8',font=ImageFont.truetype(font_path,n))
def paste_center(out,im,x,y):out.alpha_composite(im,(round(x-im.width/2),round(y-im.height/2)))
for kind,count,cell in [('rotor',16,96),('landing',32,320)]:
    frames=[]
    atlas=Image.new('RGBA',(cell*8,cell*math.ceil(count/8)))
    for index in range(count):
        im=Image.open(P/f'{kind}-frames/{index:03d}.png').convert('RGBA').resize((cell,cell),Image.Resampling.LANCZOS)
        bbox=im.getbbox();assert bbox and min(bbox[0],bbox[1],cell-bbox[2],cell-bbox[3])>=3,(kind,index,bbox)
        atlas.alpha_composite(im,(index%8*cell,index//8*cell));frames.append(im)
    atlas.save(P/('rotor.png' if kind=='rotor' else 'landing-gear.png'))
    if kind=='rotor':
        # The hub is retained in the body; the center of every overlay is empty.
        assert all(im.getpixel((48,47))[3]==0 for im in frames)
        rotor_frames=frames
    else:gear_frames=frames
body=Image.open(P/'utility-review/064.png').convert('RGBA').resize((320,320),Image.Resampling.LANCZOS)
review=Image.new('RGBA',(1100,515),'#252b29')
label(review,(24,20),'UTILITY LANDING / SOUTH-FACING BODY',26)
label(review,(24,57),'Matched camera and anchor. Full-size design view above; 1x and 4x actual runtime scale below.',16)
for col,index in enumerate([0,10,21,31]):
    combined=gear_frames[index].copy();combined.alpha_composite(body)
    large=combined.resize((250,250),Image.Resampling.LANCZOS)
    paste_center(review,large,137+col*275,222)
    label(review,(30+col*275,94),['Stowed','Deploying','Extending','Ground contact'][col],18)
    native=combined.resize((44,44),Image.Resampling.LANCZOS)
    paste_center(review,native,54+col*275,423)
    paste_center(review,native.resize((176,176),Image.Resampling.NEAREST),172+col*275,423)
label(review,(25,492),'Sole plane z = -0.660458; calibrated for 0.25-tile altitude at utility scale 0.25 x 0.55.',14)
review.convert('RGB').save(P/'landing-preview.png')
gif=[]
# Duplicate endpoints briefly, then reverse for a clear deployment/retraction loop.
for index in list(range(32))+[31]*5+list(range(30,-1,-1))+[0]*5:
    combined=gear_frames[index].copy();combined.alpha_composite(body)
    out=Image.new('RGBA',(540,330),'#252b29')
    label(out,(20,15),'Utility landing: fixed south heading',20)
    paste_center(out,combined,180,186)
    native=combined.resize((44,44),Image.Resampling.LANCZOS)
    paste_center(out,native,430,119);paste_center(out,native.resize((132,132),Image.Resampling.NEAREST),430,240)
    gif.append(out.convert('RGB'))
gif[0].save(P/'landing-preview.gif',save_all=True,append_images=gif[1:],duration=45,loop=0,disposal=2)
rot=[]
for im in rotor_frames:
    out=Image.new('RGBA',(200,220),'#252b29');paste_center(out,im.resize((192,192),Image.Resampling.NEAREST),100,115);label(out,(12,8),'Isolated moving impeller',14);rot.append(out.convert('RGB'))
rot[0].save(P/'rotor-preview.gif',save_all=True,append_images=rot[1:],duration=50,loop=0,disposal=2)
norm=math.sqrt(6**2+8.82**2);cy=8.82/norm;cz=6/norm
manifest=json.loads((P/'manifest.json').read_text())
manifest['status']='design approved; full export supported; integration owned by primary agent'
manifest['camera']['screen_up_basis']=[0,cy,cz]
manifest['camera']['final_pixels_per_blender_unit']=320/2.6
manifest['camera']['native_tiles_per_blender_unit_at_main_scale']=(320/2.6)*.25/32
manifest['attachments']={
 'rotor':{'source':'rotor.blend','atlas':'rotor.png','frame_count':16,'line_length':8,'cell':[96,96],'render_size':[192,192],'orthographic_scale':.78,'camera_location':[0,-6,8.82],'camera_target':[0,0,0],'blades':9,'phase_step_radians':math.tau/(9*16),'rendered_parts':'moving impellers only; retained hub and duct mouth use holdout alpha','mouth_mask_radius':.128,'mouth_mask_z_above_blades':.065,'hub_mask_radius':.0355,'main_centers':[[-.63,-.38,.285],[.63,-.38,.285],[-.63,.39,.285],[.63,.39,.285]],'utility_centers':[[-.43,.10,.21375],[.43,.10,.21375]],'utility_rotor_extra_scale':.75,'screen_offset_formula':'pixels_x = rotated_x * 320/2.6; pixels_y = -(rotated_y * screen_up_y + (z - 0.18) * screen_up_z) * 320/2.6; rotate local XY by pi - orientation * 2pi, then apply sprite scale and utility scale'},
 'landing_gear':{'source':'landing-gear.blend','atlas':'landing-gear.png','frame_count':32,'line_length':8,'cell':[320,320],'render_size':[640,640],'orientation':.5,'rotation_radians':0,'anchor':'same center as utility body; no additional offset','layer':'behind body','mount_z':.18,'sole_z':.18-.25/(cz*((320/2.6)*.25*.55/32)),'landed_altitude_tiles':.25,'runtime_scale':.55,'deployment':'four articulated upper castings and telescopic lower struts; cubic eased poses; reverse frames for retract'}
}
manifest['limitations']=['Native runtime validation is owned by primary agent','Body preview views sample 16 headings; --full exports all 128 body headings or 512 combat direction/pose frames','Full body export excludes moving impellers; baked hubs remain']
(P/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Finished 16 rotor frames and 32 landing frames; clear alpha margins, all rotor hub centers transparent.')
print('Screen-up basis:',cy,cz)
