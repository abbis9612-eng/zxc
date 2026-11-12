# تجميع الصور في أطالس (صفحات 2048) مع قصّ الفراغ، وكتابة ملفات json للعبة
import json, os, glob, shutil
from PIL import Image
G = '/tmp/claude-0/-home-user-zxc/6f6fece3-c046-5882-9d45-337485949872/scratchpad/iso'
W = G + '/web'; os.makedirs(W + '/units', exist_ok=True); os.makedirs(W + '/blast', exist_ok=True); os.makedirs(W + '/scene', exist_ok=True)
SHADOWFIX = False
def pack(files, prefix, page=2048, scale=1.0):
    ims = []
    for f in files:
        im = Image.open(f).convert('RGBA')
        if SHADOWFIX:
            import numpy as np
            arr = np.asarray(im).astype(np.float32); lum = arr[..., :3].mean(2)
            sh = (lum < 14) & (arr[..., 3] > 0)                     # بكسلات الظل فقط (سوداء شبه شفافة)
            arr[sh, 3] *= .55; arr[sh, 0] = 52; arr[sh, 1] = 50; arr[sh, 2] = 62
            im = Image.fromarray(arr.clip(0, 255).astype(np.uint8), 'RGBA')
        if scale != 1: im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        bb = im.getbbox() or (0, 0, 1, 1); ims.append((im.crop(bb), bb[0], bb[1]))
    pages = []; frames = []; cur = None; x = y = rowh = 0
    for im, ox, oy in ims:
        w, h = im.size
        if cur is None or x + w > page:
            x = 0; y += rowh; rowh = 0
        if cur is None or y + h > page:
            cur = Image.new('RGBA', (page, page)); pages.append(cur); x = y = rowh = 0
        cur.paste(im, (x, y)); frames.append({'p': len(pages) - 1, 'x': x, 'y': y, 'w': w, 'h': h, 'ox': ox, 'oy': oy})
        x += w + 2; rowh = max(rowh, h + 2)
    names = []
    for i, pg in enumerate(pages):
        bb = pg.getbbox(); pg = pg.crop((0, 0, page, bb[3] if bb else 4)); n = f'{prefix}_{i}.webp'; pg.save(n, quality=86, method=6); names.append(os.path.basename(n))
    return {'pages': names, 'frames': frames}
# الوحدات
SHADOWFIX = True
for k in ('m1a1', 't72'):
    m = json.load(open(f'{G}/units/{k}/meta.json'))
    out = {'origin': m['origin'], 'pivot': m['pivot'], 'tpivot': m['tpivot'], 'len': m['len'], 'wid': m['wid'], 'res': m['res']}
    out['hull'] = pack(sorted(glob.glob(f'{G}/units/{k}/h*.png')), f'{W}/units/{k}_h')
    out['tur'] = pack(sorted(glob.glob(f'{G}/units/{k}/t*.png')), f'{W}/units/{k}_t')
    json.dump(out, open(f'{W}/units/{k}.json', 'w'))
SHADOWFIX = False
# الانفجار
bm = json.load(open(f'{G}/blastfr/meta.json')) if os.path.exists(f'{G}/blastfr/meta.json') else None
fr = sorted(glob.glob(f'{G}/blastfr/b*.png'))
times = json.load(open(G + '/../fx/isoanim.json'))['times'][:len(fr)]
first = Image.open(fr[0]); mpp_b = 66 / 2560 * 2
b = pack(fr, f'{W}/blast/blast'); b.update({'times': times, 'mpp': mpp_b, 'ox': (26 / mpp_b), 'oy': (34 / mpp_b)})
json.dump(b, open(f'{W}/blast/blast.json', 'w'))
print('OK pack')
