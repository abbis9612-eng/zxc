import numpy as np, json, math, base64, io
from PIL import Image, ImageFilter
from scipy import ndimage
A='/home/user/zxc/assets/battle/'
# 1) خريطة أنواع الأرض من صورة القمر والانحدار: كل بكسل = 2 بكسل عالم
hi=np.asarray(Image.open('hi.jpg').convert('RGB').resize((700,900),Image.BOX)).astype(np.float64)
R,G,B=hi[...,0],hi[...,1],hi[...,2]; r,g,b=R,G,B; lum=(r+g+b)/3; sat=hi.max(2)-hi.min(2)
F=json.load(open('../terrain/field.json')); H=np.array(F['H'],dtype=np.float64).reshape(F['hh'],F['hw'])
# الارتفاع على شبكة الخريطة (كل خلية 8 بكسل عالم) ثم إلى دقة الخريطة (2 بكسل عالم)
Hz=np.pad(ndimage.zoom(H,4,order=1),((0,40),(0,40)),mode='edge'); Hs=Hz[380//2:380//2+900, 560//2:560//2+700]
gy,gx=np.gradient(Hs,60.0); slope=np.hypot(gx,gy)
cls=np.zeros(lum.shape,np.uint8)                 # 0 تراب
cls[(lum>150)&(sat>45)]=1                       # 1 عشب يابس فاتح
cls[(lum<120)&(sat>25)&(slope<.08)]=2           # 2 أرض محروثة داكنة
cls[(G>R*0.95)&(G>B*1.15)]=3                    # 3 حنطة خضراء
cls[slope>.12]=4                                 # 4 صخور على المنحدرات
cls[(sat<42)&(lum>100)]=5                         # 5 حصى/مناطق مبنية
cls[(B>R*0.92)&(lum<95)]=6                       # 6 ماء: بلا نسيج
cls=ndimage.median_filter(cls,3)
print('classes',np.bincount(cls.flatten(),minlength=6))
Image.fromarray(cls).save('cls.png',optimize=True)
# 2) أنسجة تفصيل: تمرير عالٍ (التفاصيل فقط حول الرمادي) حتى تحافظ صورة القمر على لونها
tex={}
for i,n in zip(range(51,57),['dirt','grass','plow','wheat','rock','gravel']):
    im=Image.open(f'{A}{i}.jpg').convert('L').resize((256,256),Image.LANCZOS); a=np.asarray(im).astype(np.float64)
    # نجعله متصل الأطراف: مزج مع نسخة مزاحة بنصف الحجم
    s=a.shape[0]; sh=np.roll(np.roll(a,s//2,0),s//2,1); yy,xx=np.mgrid[0:s,0:s]; w=np.minimum(np.minimum(xx,s-1-xx),np.minimum(yy,s-1-yy))/(s/2); w=np.clip(w*2,0,1)
    a=a*w+sh*(1-w)
    hp=a-ndimage.gaussian_filter(a,4,mode='wrap'); v=np.clip(hp*2.6,-127,127)
    # أسود شفاف حيث التفصيل أغمق، وأبيض شفاف حيث أفتح: يُرسم بالمزج العادي (أسرع على الهاتف)
    rgba=np.zeros(a.shape+(4,),np.uint8); rgba[...,:3]=np.where(v[...,None]>0,255,0); rgba[...,3]=np.clip(np.abs(v)*1.6,0,255)
    b=io.BytesIO(); Image.fromarray(rgba,'RGBA').save(b,'WEBP',quality=72); tex[n]='data:image/webp;base64,'+base64.b64encode(b.getvalue()).decode()
# 3) عناصر الأرض على خلفية بيضاء
def cut(i):
    im=Image.open(f'{A}{i}.jpg').convert('RGB'); a=np.asarray(im).astype(np.int16)
    mx,mn=a.max(2),a.min(2); bgish=(mn>222)&((mx-mn)<22)
    lab,n=ndimage.label(bgish); edge=set(np.unique(np.concatenate([lab[0],lab[-1],lab[:,0],lab[:,-1]])))-{0}
    bg=np.isin(lab,list(edge)); al=Image.fromarray(np.where(bg,0,255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))
    rg=im.copy(); rg.putalpha(al); rg=rg.crop(al.point(lambda v:255 if v>20 else 0).getbbox()); rg.thumbnail((160,160),Image.LANCZOS)
    b=io.BytesIO(); rg.save(b,'WEBP',quality=85); return 'data:image/webp;base64,'+base64.b64encode(b.getvalue()).decode()
props={n:cut(i) for i,n in [(57,'olive'),(58,'poplar'),(59,'eucal'),(60,'bush'),(61,'rocks'),(62,'house1'),(63,'house2'),(65,'house_ruin'),(68,'car'),(69,'pickup'),(70,'car_burnt'),(72,'shed'),(73,'twall'),(74,'berm')]}
# 4) أماكن الأشجار والشجيرات والصخور من صورة القمر نفسها
rng=np.random.default_rng(7); trees=[]
green=(G>R*1.0)&(G>B*1.2)&(lum<130)
ys,xs=np.nonzero(green); idx=rng.choice(len(ys),min(420,len(ys)),replace=False) if len(ys) else []
for k in idx: trees.append([int(560+xs[k]*2+rng.integers(-1,2)),int(380+ys[k]*2+rng.integers(-1,2)),int(rng.integers(0,3))])
ys,xs=np.nonzero(slope>.14); idx=rng.choice(len(ys),min(260,len(ys)),replace=False)
for k in idx: trees.append([int(560+xs[k]*2),int(380+ys[k]*2),3+int(rng.integers(0,2))])
print('props placed',len(trees))
b=io.BytesIO(); Image.open('cls.png').save(b,'PNG',optimize=True)
out={'clsmap':'data:image/png;base64,'+base64.b64encode(b.getvalue()).decode(),'tex':tex,'flora':trees}
js='const SAT_HI="data:image/jpeg;base64,'+base64.b64encode(open('hi.jpg','rb').read()).decode()+'";\nconst SAT_BOX=[560,380,1400,1800];\n'
js+='const GROUND='+json.dumps(out)+';\nObject.assign(BSPR,'+json.dumps(props)+');\n'
snd={41:'ak_close',42:'ak_far',43:'pkm_close',44:'mg_far',45:'dshk',46:'m2',47:'g3',48:'sniper2',49:'cannon30',50:'tank_close_shot',51:'tank_far_shot',52:'mortar_launch',53:'mortar_in',54:'arty_far',55:'cracks',56:'debris2',57:'metal_hits',58:'ricochet2',60:'rocket_one2',61:'mlrs_far',62:'boom_echo',63:'boom_close',64:'battle_far',65:'shouts',66:'tank_idle',67:'wheeled',68:'grenade',69:'rpg2',70:'tank_pass'}
S={v:'data:audio/mpeg;base64,'+base64.b64encode(open(f'/home/user/zxc/assets/sounds/{k}.mp3','rb').read()).decode() for k,v in snd.items()}
js+='Object.assign(SND,'+json.dumps(S)+');\n'
open('../mock/extra4.js','w').write(js); print('extra4',len(js)//1024,'KB')
# الحقل: صورة القمر الأساسية بدل الأرض المرسومة
f=open('../mock/field.js').read(); import re
i=f.index('FIELD_IMG'); j=f.index('"',f.index('"',i)+1)
