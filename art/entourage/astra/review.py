"""Compose candidate renders with native-size comparisons; uv run --with pillow python review.py."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
import json
P=Path(__file__).parent
REPO=P.parents[2]
BASE=Path('/Users/luan/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/data/base')
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
def font(n):return ImageFont.truetype(FONT,n)
def label(im,xy,t,n=16,c='#c3c7c1'):ImageDraw.Draw(im).text(xy,t,font=font(n),fill=c)
def source_frame(name,size,index):
    im=Image.open(REPO/'sprites'/name).convert('RGBA');cols=im.width//size
    return im.crop((index%cols*size,index//cols*size,(index%cols+1)*size,(index//cols+1)*size))
def paste_center(im,s,center):im.alpha_composite(s,(int(center[0]-s.width/2),int(center[1]-s.height/2)))
def ground(w,h):
    tile=Image.open(BASE/'graphics/terrain/stone-path/stone-path-4.png').convert('RGB').crop((0,0,256,256)).resize((128,128),Image.Resampling.LANCZOS)
    im=Image.new('RGBA',(w,h))
    for x in range(0,w,128):
        for y in range(0,h,128):im.paste(tile,(x,y))
    im=ImageEnhance.Brightness(im).enhance(.55);return im
roles=[('Companion','main-review','entourage-body.png',320,80,80),('Utility / crafter','utility-review','task-manager.png',320,80,44),('Combat','combat-final','combat-drone.png',256,320,45)]
# This is the native torso art used directly by the original version, without a player tint.
a=Image.open(BASE/'graphics/entity/spidertron/torso/spidertron-body.png').convert('RGBA');i=40
original=a.crop((i%8*132,i//8*138,(i%8+1)*132,(i//8+1)*138)).resize((40,41),Image.Resampling.LANCZOS)
comparison=Image.new('RGBA',(1110,890),'#1d2324')
label(comparison,(30,22),'ENTOURAGE  /  MODEL REVIEW',27,'#eceee7')
label(comparison,(30,61),'Exact runtime size at 1x, plus a 4x pixel enlargement. Candidate sprites are not installed.',15)
for col,title in enumerate(['ORIGINAL 3.2.1','CURRENT SANDBOX','CANDIDATE']):label(comparison,(30+col*365,105),title,18,'#eceee7')
# Native and fourfold main comparison.
current=source_frame('entourage-body.png',320,80).resize((80,80),Image.Resampling.LANCZOS)
proposed=Image.open(P/'main-review/080.png').convert('RGBA').resize((80,80),Image.Resampling.LANCZOS)
for col,im in enumerate([original,current,proposed]):
    tile=ground(340,290);paste_center(tile,im,(60,66));paste_center(tile,im.resize((im.width*4,im.height*4),Image.Resampling.NEAREST),(201,155));comparison.alpha_composite(tile,(20+col*365,138))
    label(comparison,(32+col*365,440),['Native Spidertron torso, 0.3 scale','320px cell, 0.25 scale','Same 320px cell / 0.25 scale'][col],14)
label(comparison,(30,485),'UTILITY / CRAFTER',18,'#eceee7');label(comparison,(30,675),'COMBAT',18,'#eceee7')
label(comparison,(30,535),'No standalone utility model',15);label(comparison,(30,559),'in the 3.2.1 reference.',15)
label(comparison,(30,725),'No standalone combat model',15);label(comparison,(30,749),'in the 3.2.1 reference.',15)
for row,(_,directory,name,size,index,native) in enumerate(roles[1:]):
    for col in [1,2]:
        im=source_frame(name,size,index) if col==1 else Image.open(P/directory/('080.png' if row==0 else '322.png')).convert('RGBA')
        im=im.resize((native,native),Image.Resampling.LANCZOS)
        tile=ground(340,155);paste_center(tile,im,(59,71));paste_center(tile,im.resize((native*4,native*4),Image.Resampling.NEAREST),(218,77));comparison.alpha_composite(tile,(20+col*365,505+row*190))
label(comparison,(30,855),'Utility: 320 x 0.25 x 0.55 = 44px cell   |   Combat: 256 x 0.175 = 44.8px cell',14)
comparison.convert('RGB').save(P/'comparison.png')
# A transparent source is presented over real Factorio stone-path pixels, with illustrative contact shadows.
hero=Image.new('RGBA',(1110,530),'#1d2324')
label(hero,(30,20),'ENTOURAGE  /  PROPOSED MODEL FAMILY',27,'#eceee7')
label(hero,(30,58),'Editable Blender models. Enlarged design view; final-size comparison is on the separate sheet.',15)
for col,(title,directory,_,_,_,native) in enumerate(roles):
    tile=ground(350,360)
    source=Image.open(P/directory/('322.png' if col==2 else '080.png')).convert('RGBA')
    crop=source.crop(source.getbbox());crop.thumbnail((292,276),Image.Resampling.LANCZOS)
    shadow=Image.new('RGBA',tile.size);dr=ImageDraw.Draw(shadow);dr.ellipse((83,207,295,279),fill=(0,0,0,130));shadow=shadow.filter(ImageFilter.GaussianBlur(13));tile.alpha_composite(shadow)
    paste_center(tile,crop,(175,163));hero.alpha_composite(tile,(20+col*365,96))
    label(hero,(30+col*365,474),title,21,'#eceee7')
    label(hero,(30+col*365,505),['Curved armor / exposed machinery','Paired jointed tools / shared worker model','Swept armor / shrouded plasma engines'][col],13)
hero.convert('RGB').save(P/'lineup.png')
# Direction turntable only: no motion or landing behavior is claimed.
frames=[]
paths=[sorted((P/r[1]).glob('*.png')) for r in roles]
for i in range(16):
    out=Image.new('RGBA',(720,260),'#1d2324')
    for col,(title,_,_,_,_,native) in enumerate(roles):
        tile=ground(232,205);im=Image.open(paths[col][i]).convert('RGBA').resize((native,native),Image.Resampling.LANCZOS)
        paste_center(tile,im.resize((native*3,native*3),Image.Resampling.NEAREST),(116,105));out.alpha_composite(tile,(4+col*240,38));label(out,(12+col*240,10),title,17)
    frames.append(out.convert('RGB'))
frames[0].save(P/'turntable.gif',save_all=True,append_images=frames[1:],duration=130,loop=0,disposal=2)
