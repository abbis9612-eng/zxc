import json, math, os, subprocess, numpy as np, base64, io
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageEnhance, ImageFilter
from scipy import ndimage
F=json.load(open('../terrain/field.json')); X0,Y0=F['x0'],F['y0']
FX0,FY0,FS=1120,960,340                       # المنطقة بإحداثيات الحقل: 340 بكسل ≈ 10.4 كم
def box(z):
    s=2**(z-11); return X0*s+FX0*s/2, Y0*s+FY0*s/2, FS*s/2
def mosaic(z, pre, ext, conv, dl):
    px0,py0,n=box(z); tx0,ty0,tx1,ty1=int(px0//256),int(py0//256),int((px0+n)//256),int((py0+n)//256)
    jobs=[(f'{pre}{z}_{tx}_{ty}.{ext}',dl(z,tx,ty)) for ty in range(ty0,ty1+1) for tx in range(tx0,tx1+1)]
    def get(j):
        f,u=j
        if not (os.path.exists(f) and os.path.getsize(f)>500): subprocess.run(['curl','-s','-m','40','-o',f,u])
    with ThreadPoolExecutor(8) as ex: list(ex.map(get,jobs))
    rows=[np.hstack([conv(Image.open(f'{pre}{z}_{tx}_{ty}.{ext}')) for tx in range(tx0,tx1+1)]) for ty in range(ty0,ty1+1)]
    a=np.vstack(rows); ox,oy=int(round(px0-tx0*256)),int(round(py0-ty0*256)); n=int(round(n)); return a[oy:oy+n,ox:ox+n]
rgb=lambda im: np.asarray(im.convert('RGB'))
def elev(im): a=np.asarray(im.convert('RGB')).astype(np.float64); return a[...,0]*256+a[...,1]+a[...,2]/256-32768
sat=mosaic(14,'s','jpg',rgb,lambda z,x,y:f'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2020_3857/default/g/{z}/{y}/{x}.jpg')
h=mosaic(13,'e','png',elev,lambda z,x,y:f'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png')
print('sat',sat.shape,'h',h.shape,h.min(),h.max())
im=Image.fromarray(sat); im=ImageEnhance.Contrast(im).enhance(1.08); im=ImageEnhance.Color(im).enhance(1.05).filter(ImageFilter.UnsharpMask(1.2,60,2))
im.save('sat.jpg',quality=82,optimize=True)
# شبكة الارتفاع 257×257 للمجسم، وبدقة كاملة للرؤية والحركة
hs=ndimage.gaussian_filter(h,0.8)
g=np.asarray(Image.fromarray(hs.astype(np.float32)).resize((257,257),Image.BILINEAR))
mpp=40075016.686*math.cos(math.radians(36.75))/(2**13*256)
size=FS*2*mpp
q=np.clip(np.round(g*4),0,65535).astype('<u2')   # ربع متر
json.dump({'size':size,'n':257,'hmin':float(g.min()),'hmax':float(g.max())},open('meta.json','w'))
open('h.bin','wb').write(q.tobytes())
print('size m',round(size),'grid',g.shape,round(g.min()),round(g.max()), os.path.getsize('sat.jpg')//1024,'KB')
# مواقع مهمة بالأمتار داخل المنطقة
def loc(fx,fy): return round((fx-FX0)*size/FS), round((fy-FY0)*size/FS)
print('line1',[loc(x,y) for x,y in [(1150,1080),(1240,1092),(1330,1084),(1420,1098)]],'alqosh',loc(1445,1147),'tr tanks',[loc(x,y) for x,y in [(1300,1025),(1120,1030)]])
