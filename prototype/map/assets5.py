import json, base64, io, re
from PIL import Image
# قطع صورة القمر عالية الدقة: 512 بكسل لكل قطعة (256 بكسل عالم)
im=Image.open('hi_g.jpg'); T=512; tiles=[]
for ty in range(0,im.height,T):
    row=[]
    for tx in range(0,im.width,T):
        b=io.BytesIO(); im.crop((tx,ty,min(tx+T,im.width),min(ty+T,im.height))).save(b,'JPEG',quality=55,optimize=True)
        row.append('data:image/jpeg;base64,'+base64.b64encode(b.getvalue()).decode())
    tiles.append(row)
old=open('../mock/extra4.js').read()
G=json.loads(old[old.index('const GROUND=')+13:old.index(';\nObject.assign(BSPR')])
rest=old[old.index('Object.assign(BSPR'):]
rest='\n'.join(l for l in rest.split('\n') if not l.startswith('Object.assign(SND,{"real_'))+'\n'
H=json.load(open('../mock/hgrid.json'))
R='/home/user/zxc/assets/sounds/real/'
real={k:'data:audio/mpeg;base64,'+base64.b64encode(open(R+f,'rb').read()).decode() for k,f in [('real_tank','tank_cannon.mp3'),('real_strike','strike_impact.mp3'),('real_rockets_in','rockets_incoming.mp3'),('real_battle','battle_field.mp3'),('real_hmg','heavy_mg.mp3'),('real_bursts','combat_bursts.mp3'),('real_impact','rocket_impact.mp3')]}
js='const SAT_TILES='+json.dumps(tiles)+';\nconst SAT_BOX=[560,380,1400,1800];\nconst HGRID='+json.dumps(H)+';\n'
js+='const GROUND='+json.dumps({'tex':{'dirt':G['tex']['dirt'],'rock':G['tex']['rock']},'flora':G['flora']})+';\n'+rest+'Object.assign(SND,'+json.dumps(real)+');\n'
open('../mock/extra4.js','w').write(js); print(len(js)//1024,'KB', len(tiles),'x',len(tiles[0]))
