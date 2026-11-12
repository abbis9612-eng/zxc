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
MD = json.load(open('../geo/baked/simdata.json')); MD['tiles'] = json.load(open('../geo/baked/tiles_meta.json'))
out_m2 = out.replace('/*__MAPDATA__*/', '', 1) if False else out
out_m2 = out_m2.replace("document.documentElement.dir='rtl';", "const MAP2 = " + json.dumps(MD, ensure_ascii=False) + ";\ndocument.documentElement.dir='rtl';", 1)
os.makedirs('pub/map', exist_ok=True)
for f in os.listdir('../geo/baked/tiles2'): shutil.copy('../geo/baked/tiles2/' + f, 'pub/map/' + f)
# بيانات الخريطة القديمة لا حاجة لها مع الخريطة الحقيقية: نستبدلها بقيم فارغة صغيرة
STUB = {'const SAT_TILES': 'const SAT_TILES=[];', 'const FIELD_IMG': "const FIELD_IMG='data:image/gif;base64,R0lGODlhAQABAAAAACw=';",
        'const MAP2D': 'const MAP2D={"roads":[],"houses":[],"trees":[],"walls":[],"mosques":[]};',
        'const HGRID': 'const HGRID={"x0":0,"y0":0,"cell":1,"w":2,"h":2,"H":"AAAAAAAAAAA="};', 'const GROUND': 'const GROUND={"tex":{"dirt":"","rock":""},"flora":[]};'}
for k, v in STUB.items():
    i = out_m2.find(k + '=') if out_m2.find(k + '=') >= 0 else out_m2.find(k + ' =')
    assert i >= 0, k
    j = out_m2.find('\n', i)
    out_m2 = out_m2[:i] + v + out_m2[j:]
out2 = '<meta charset="utf-8">\n' + out_m2.rstrip() + '\n<script src="pixi.min.js"></script>\n<script src="pixi_war.js"></script>\n'
open('pub/index.html', 'w').write(out2)
print('pub', len(out2), sum(os.path.getsize('pub/v2/' + f) for f in os.listdir('pub/v2')))
