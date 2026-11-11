import numpy as np, json
from PIL import Image, ImageFilter
from scipy import ndimage
A='/home/user/zxc/assets/battle/'
def cut(i):
    im=Image.open(f'{A}{i}.jpg').convert('RGB'); a=np.asarray(im).astype(np.int16)
    mx,mn=a.max(2),a.min(2); bgish=(mn>226)&((mx-mn)<22)
    lab,n=ndimage.label(bgish)
    edge=set(np.unique(np.concatenate([lab[0],lab[-1],lab[:,0],lab[:,-1]])))-{0}
    bg=np.isin(lab,list(edge))
    alpha=Image.fromarray(np.where(bg,0,255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))
    rgba=im.copy(); rgba.putalpha(alpha)
    bbox=alpha.point(lambda v:255 if v>20 else 0).getbbox()
    return rgba.crop(bbox), bgish[bbox[1]:bbox[3],bbox[0]:bbox[2]] & ~bg[bbox[1]:bbox[3],bbox[0]:bbox[2]], a[bbox[1]:bbox[3],bbox[0]:bbox[2]]
meta={}
names={28:'hull_t72',29:'tur_t72',30:'hull_iqm',31:'tur_iqm',32:'hull_leo',33:'tur_leo',34:'hull_alt',35:'tur_alt',36:'mi35b',37:'t129b',38:'f16a',39:'m_ag',40:'m_rkt',41:'m_bm',42:'m_atgm'}
for i,n in names.items():
    rg,inner,a=cut(i)
    al=np.asarray(rg)[:,:,3]>128
    H,Wd=al.shape
    if n.startswith('hull'):
        # فتحة البرج: إما بيضاء مغلقة (28، 30) أو داكنة (32، 34)
        lum=a.mean(2)
        if inner.sum()>2000: m=inner
        else:
            dark=(lum<60)&al; dark[:int(H*.15)]=0; dark[int(H*.85):]=0
            lab,k=ndimage.label(dark); sizes=ndimage.sum(dark,lab,range(1,k+1)); m=lab==(1+int(np.argmax(sizes)))
        ys,xs=np.nonzero(m); cy,cx=ys.mean(),xs.mean(); dia=max(xs.max()-xs.min(), ys.max()-ys.min())
        meta[n]={'w':Wd,'h':H,'ringY':(H/2-cy)/H,'ringX':(cx-Wd/2)/H,'ringD':dia/H,'width':Wd/H}
        # نملأ الفتحة البيضاء بلون داكن حتى لا تظهر الأرض من تحتها
        arr=np.asarray(rg).copy()
        if inner.sum()>2000: arr[inner]=[40,36,30,255]
        rg=Image.fromarray(arr)
    elif n.startswith('tur'):
        widths=al.sum(1); body=widths>widths.max()*.45
        ys=np.nonzero(body)[0]; sub=al[ys.min():ys.max()+1]; yy,xx=np.nonzero(sub); cy=yy.mean()+ys.min(); cx=xx.mean()
        meta[n]={'w':Wd,'h':H,'pivY':(H/2-cy)/H,'pivX':(cx-Wd/2)/H,'bodyW':widths.max()/H,'bodyLen':(ys.max()-ys.min())/H}
    else: meta[n]={'w':Wd,'h':H}
    t=rg.copy(); t.thumbnail((256,256),Image.LANCZOS); t.save(f's3/{n}.webp',quality=88)
    print(n,rg.size,meta[n])
# المؤثرات على خلفية سوداء
fx={43:('blast_dust','a'),44:('backblast','a'),45:('launch_dust','a'),46:('dirt_hits','a'),47:('armor_sparks','l'),48:('dust_trail','a'),49:('smoke_screen','a'),50:('tank_fire','l')}
for i,(n,mode) in fx.items():
    im=Image.open(f'{A}{i}.jpg').convert('RGB'); a=np.asarray(im).astype(np.float32)/255
    if mode=='l':
        t=im.copy(); t.thumbnail((256,256),Image.LANCZOS); t.save(f's3/{n}.jpg',quality=85)
    else:
        m=a.max(2); al=np.clip((m-.04)*1.5,0,1); col=np.clip(a/np.maximum(m[...,None],.05),0,1)
        # تفتيح خفيف للون الغبار حتى لا يبدو رمادياً ميتاً
        out=np.dstack([col*255,al*255]).astype(np.uint8); t=Image.fromarray(out,'RGBA'); t.thumbnail((256,256),Image.LANCZOS); t.save(f's3/{n}.webp',quality=85)
    print(n)
json.dump(meta,open('s3/meta.json','w'),indent=0)
