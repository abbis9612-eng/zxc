# بناء صفحة المعركة (المرحلة 9): الكود والبيانات الصغيرة داخل الصفحة، والصور والأصوات ملفات منفصلة في media/
# الاستعمال: من داخل prototype/: python3 build.py   ← الناتج في pub/ (index.html و media/)
import os, shutil
s = open('app2.html').read()
w = open('war.js').read()
a = s.index('// ================================================================== معركة دهوك')
b = s.index("home();\naddEventListener('resize', home, {once: true});")
s = s[:a] + w.rstrip() + "\n" + s[b:]
open('app2.html', 'w').write(s)
rd = lambda f: open('data/' + f + '.js').read()
data = "document.documentElement.dir='rtl';document.documentElement.lang='ar';\n" + rd('mapdata') + "\n" + rd('bsprites') + "\nconst SPR=BSPR;\n" + "\n".join(rd(f) for f in ['sounds', 'vfx', 'field', 'extra3', 'extra4', 'extra5'])
out = s.replace("/*__MAPDATA__*/", data, 1)
assert 'data:image' not in out and 'data:audio' not in out, 'بقيت صور أو أصوات مضمّنة'
os.makedirs('pub', exist_ok=True)
open('pub/index.html', 'w').write(out)
if os.path.isdir('pub/media'): shutil.rmtree('pub/media')
shutil.copytree('media', 'pub/media')
print('index.html', len(out), 'media', len(os.listdir('pub/media')))
