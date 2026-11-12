import re
s=open('app2.html').read()
w=open('war.js').read()
a=s.index('// ================================================================== معركة دهوك')
b=s.index("home();\naddEventListener('resize', home, {once: true});")
s=s[:a]+w.rstrip()+"\n"+s[b:]
open('app2.html','w').write(s)
rd=lambda f: open(f).read()
out=s.replace("/*__MAPDATA__*/","document.documentElement.dir='rtl';document.documentElement.lang='ar';\n"+rd('mapdata.js')+"\n"+rd('bsprites.js')+"\nconst SPR=BSPR;\n"+rd('sounds.js')+"\n"+rd('vfx.js')+"\n"+rd('field.js')+"\n"+rd('extra3.js')+"\n"+rd('extra4.js')+"\n"+rd('extra5.js'),1)
open('command-room.html','w').write(out)
print(len(out))
# ---- العرض الجديد (PixiJS): ملفات منفصلة بجانب الصفحة
import json, os, shutil
V2 = '../v2'
meta = {'veh': json.load(open(f'{V2}/veh.json')), 'fx': json.load(open(f'{V2}/fx_h155.json'))}
pw = open('pixi_war.js').read().replace('/*__V2META__*/', 'const V2META = ' + json.dumps(meta) + ';')
os.makedirs('pub/v2', exist_ok=True)
open('pub/pixi_war.js', 'w').write(pw)
shutil.copy(f'{V2}/pixi.min.js', 'pub/pixi.min.js')
for f in os.listdir(V2):
    if f.endswith('.webp'): shutil.copy(f'{V2}/{f}', f'pub/v2/{f}')
out2 = '<meta charset="utf-8">\n' + out.rstrip() + '\n<script src="pixi.min.js"></script>\n<script src="pixi_war.js"></script>\n'
open('pub/index.html', 'w').write(out2)
print('pub', len(out2), sum(os.path.getsize('pub/v2/' + f) for f in os.listdir('pub/v2')))
