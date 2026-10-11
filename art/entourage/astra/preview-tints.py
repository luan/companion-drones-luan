"""Inspect neutral tint layers composited over packed body frames."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
P=Path(__file__).parent
ROOT=P.parents[2]
font_path='/System/Library/Fonts/Supplemental/Arial.ttf'
def text(out,xy,label,size=16):ImageDraw.Draw(out).text(xy,label,font=ImageFont.truetype(font_path,size),fill='#dce0da')
def center(out,im,x,y):out.alpha_composite(im,(round(x-im.width/2),round(y-im.height/2)))
def tint(mask,rgb):
    channels=mask.split()
    return Image.merge('RGBA',tuple(channels[i].point(lambda v,f=rgb[i]:round(v*f)) for i in range(3))+(channels[3],))
roles=[('Companion','entourage-body.png',320,80,80,'main-mask-preview/080.png'),('Utility / crafter','task-manager.png',320,80,44,'utility-mask-preview/080.png'),('Combat','combat-drone.png',256,320,45,'combat-mask-preview/320.png')]
colors=[None,(.86,.19,.11),(.12,.48,.86)]
out=Image.new('RGBA',(1040,1000),'#252b29')
text(out,(28,20),'PLAYER COLOR / SHADED PAINT LAYERS',27)
text(out,(28,58),'Offline composite of the actual tint masks. Bare machinery, optics, vents and rotors retain their colors.',15)
for c,label in enumerate(['Untinted base','Player red','Player blue']):text(out,(28+c*345,100),label,20)
for row,(label,name,cell,index,native,mask_path) in enumerate(roles):
    atlas=Image.open(ROOT/'sprites'/name).convert('RGBA');cols=atlas.width//cell
    base=atlas.crop((index%cols*cell,index//cols*cell,(index%cols+1)*cell,(index//cols+1)*cell))
    mask=Image.open(P/mask_path).convert('RGBA').resize((cell,cell),Image.Resampling.LANCZOS)
    # Significant paint alpha must sit on existing body geometry.
    outside=sum(1 for a,b in zip(mask.getchannel('A').getdata(),base.getchannel('A').getdata()) if a>64 and b<8)
    assert outside==0,(label,outside)
    opaque=[pixel for pixel in mask.getdata() if pixel[3]>240]
    spread=[max(p[:3])-min(p[:3]) for p in opaque]
    assert max(spread,default=0)<=2,(label,max(spread))
    values=sorted(p[0] for p in opaque)
    print(label,'paint grayscale p05/p95:',values[len(values)//20],values[len(values)*19//20],'occlusion/silhouette checked')
    y=145+row*285
    for col,color in enumerate(colors):
        combined=base.copy()
        if color:combined.alpha_composite(tint(mask,color))
        center(out,combined.resize((255,255),Image.Resampling.LANCZOS),160+col*345,y+120)
        small=combined.resize((native,native),Image.Resampling.LANCZOS)
        center(out,small,300+col*345,y+198)
        text(out,(28+col*345,y+248),label,16)
out.convert('RGB').save(P/'player-color-preview.png')
