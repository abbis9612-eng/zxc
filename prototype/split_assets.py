# نقل لمرة واحدة: يُخرج كل صورة وصوت مضمّن (data URI) من ملفات بيانات المرحلة 9 إلى ملفات حقيقية في media/،
# ويكتب ملفات البيانات نفسها في data/ بمسارات بدل المحتوى المضمّن. الاستعمال: python3 split_assets.py <مجلد ملفات البيانات القديمة>
import re, sys, os, base64, hashlib
SRC = sys.argv[1]
EXT = {'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'audio/mpeg': 'mp3'}
os.makedirs('media', exist_ok=True); os.makedirs('data', exist_ok=True)
seen = {}
def rep(m):
    mime, b64 = m.group(1), m.group(2)
    raw = base64.b64decode(b64)
    name = hashlib.sha1(raw).hexdigest()[:12] + '.' + EXT[mime]
    if name not in seen:
        open('media/' + name, 'wb').write(raw); seen[name] = len(raw)
    return 'media/' + name
for f in ['mapdata', 'bsprites', 'sounds', 'vfx', 'field', 'extra3', 'extra4', 'extra5']:
    s = open(f'{SRC}/{f}.js').read()
    out = re.sub(r'data:([a-z]+/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=]+)', rep, s)
    open(f'data/{f}.js', 'w').write(out)
    print(f, len(s), '->', len(out))
print('files', len(seen), 'bytes', sum(seen.values()))
