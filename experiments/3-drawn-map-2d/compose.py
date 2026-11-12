import json, math, numpy as np, sys
from PIL import Image, ImageFilter, ImageEnhance
F=json.load(open('../terrain/field.json')); X0,Y0=F['x0'],F['y0']
def mosaic(z, fx0, fy0, fx1, fy1, pre, conv):
    s=2**(z-11); px0,py0=X0*s+fx0*s/2, Y0*s+fy0*s/2; px1,py1=X0*s+fx1*s/2, Y0*s+fy1*s/2
    tx0,ty0,tx1,ty1=int(px0//256),int(py0//256),int(px1//256),int(py1//256)
    rows=[]
    for ty in range(ty0,ty1+1):
        rows.append(np.hstack([conv(Image.open(f'{pre}{z}_{tx}_{ty}.{"jpg" if pre=="s" else "png"}')) for tx in range(tx0,tx1+1)]))
    a=np.vstack(rows); ox,oy=int(round(px0-tx0*256)),int(round(py0-ty0*256)); w,h=int(round(px1-px0)),int(round(py1-py0))
    return a[oy:oy+h,ox:ox+w]
rgb=lambda im: np.asarray(im.convert('RGB')).astype(np.float64)
def elev(im):
    a=rgb(im); return a[...,0]*256+a[...,1]+a[...,2]/256-32768
def build(z, box, out, q):
    sat=mosaic(z,*box,'s',rgb)/255; h=np.maximum(mosaic(z,*box,'e',elev),0)
    from scipy.ndimage import gaussian_filter; h=gaussian_filter(h,1.2)
    px=40075016.686*math.cos(math.radians(36.75))/(2**z*256)
    gy,gx=np.gradient(h,px); az,alt=math.radians(315),math.radians(40)
    slope=np.arctan(np.hypot(gx,gy)*1.8); aspect=np.arctan2(-gx,gy)
    shade=np.clip(np.sin(alt)*np.cos(slope)+np.cos(alt)*np.sin(slope)*np.cos(az-aspect),0,1)
    rel=np.clip(1+1.15*(shade-np.median(shade)),.5,1.45)[...,None]
    o=np.clip(sat*rel,0,1)
    o=o**1.08                                      # تعميق الظلال قليلاً
    o=(o-.5)*1.12+.5                               # تباين
    im=Image.fromarray((np.clip(o,0,1)*255).astype(np.uint8))
    im=ImageEnhance.Color(im).enhance(1.04).filter(ImageFilter.UnsharpMask(1.0,70,2))
    im.save(out,quality=q,optimize=True,progressive=True); print(out, im.size)
    return h
build(12,(0,0,F['w'],F['h']),'base.jpg',74)
build(13,(560,380,1960,2180),'hi.jpg',62)
