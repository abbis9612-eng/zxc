# توليد خريطة معركة 8×8 كم: الارتفاعات الحقيقية أساساً، وفوقها تفاصيل وحقول وطرق ووديان وقرى ومواد أرض وظلال
import json, math, os, sys, io, base64, heapq
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
from scipy import ndimage
sys.path.insert(0, '../sat'); os.chdir('../sat')
exec(open('compose.py').read().split('def build')[0])      # mosaic + elev
os.chdir('../p3d')
rng = np.random.default_rng(11)
FX0, FY0, FS = 1110, 930, 262                                # المنطقة بإحداثيات الحقل (≈ 8 كم)
os.chdir('../sat'); h = np.maximum(mosaic(13, FX0, FY0, FX0 + FS, FY0 + FS, 'e', elev), 0); SAT = mosaic(14, FX0, FY0, FX0 + FS, FY0 + FS, 's', rgb).astype(np.float64); os.chdir('../p3d')
SIZE = 8000.0
N = 1025                                                     # شبكة التفاصيل: 7.8 م
def up(a, n): return np.asarray(Image.fromarray(a.astype(np.float32)).resize((n, n), Image.BICUBIC))
H = up(ndimage.gaussian_filter(h, 1.0), N).astype(np.float64)
# ---------- تفاصيل طبيعية: ضوضاء متعددة الطبقات، أقوى على التلال (صخور وأخاديد) وأضعف على السهل
def noise(n, cell, seed):
    r = np.random.default_rng(seed); g = r.random((n // cell + 3, n // cell + 3))
    return ndimage.zoom(g, cell, order=3)[:n, :n]
def fbm(n, oct, seed):
    s = np.zeros((n, n)); a = 1.0; tot = 0
    for o in range(oct): cell = max(2, 128 >> o); s += a * (noise(n, cell, seed + o) - .5); tot += a; a *= .5
    return s / tot
gy, gx = np.gradient(H, SIZE / (N - 1)); slope = np.hypot(gx, gy)
rough = np.clip(slope * 6, .15, 1.0)
ridged = 1 - np.abs(fbm(N, 6, 3) * 2)
H += (fbm(N, 7, 7) * 9 + (ridged - .5) * 7) * rough + fbm(N, 5, 21) * 1.2
# ---------- الوديان الجافة: تجري حيث يجري الماء فعلاً (تراكم الجريان)
M = 257; hm = up(H, M).astype(np.float64)
order = np.argsort(-hm, axis=None); acc = np.ones(M * M); flat = hm.ravel()
nb = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
for idx in order:
    i, j = divmod(idx, M); best = None; bd = 0
    for di, dj in nb:
        a, b = i + di, j + dj
        if 0 <= a < M and 0 <= b < M:
            d = (flat[idx] - flat[a * M + b]) / math.hypot(di, dj)
            if d > bd: bd = d; best = a * M + b
    if best is not None: acc[best] += acc[idx]
acc = acc.reshape(M, M)
wadi = up(np.clip((np.log1p(acc) - 3.6) / 2.2, 0, 1), N)
H -= wadi * 3.5                                               # نحفر مجرى الوادي قليلاً
gy, gx = np.gradient(H, SIZE / (N - 1)); slope = np.hypot(gx, gy)
# ---------- طرق ترابية: أقصر طريق بأقل انحدار بين نقاط
G = 256; hs = up(H, G); sy_, sx_ = np.gradient(hs, SIZE / (G - 1)); sl = np.hypot(sx_, sy_)
cost = 1 + (sl * 40) ** 2 + up(wadi, G) * 3
def astar(a, b):
    dist = {a: 0}; prev = {}; pq = [(0, 0, a)]
    while pq:
        f_, d, u = heapq.heappop(pq)
        if u == b: break
        if d > dist[u]: continue
        for di, dj in nb:
            v = (u[0] + di, u[1] + dj)
            if 0 <= v[0] < G and 0 <= v[1] < G:
                nd = d + cost[v] * math.hypot(di, dj)
                if nd < dist.get(v, 1e18): dist[v] = nd; prev[v] = u; heapq.heappush(pq, (nd + math.hypot(v[0] - b[0], v[1] - b[1]), nd, v))
    p = [b]
    while p[-1] != a: p.append(prev[p[-1]])
    return p[::-1]
def low_flat(cands):
    return min(cands, key=lambda c: sl[c] * 30 + abs(hs[c] - np.percentile(hs, 25)) / 50)
# قرى في أماكن مستوية
cand = [(int(r), int(c)) for r, c in zip(rng.integers(20, G - 20, 400), rng.integers(20, G - 20, 400))]
villages = []
for target in [(200, 60), (190, 190), (70, 200), (120, 110)]:
    near = [c for c in cand if abs(c[0] - target[0]) < 40 and abs(c[1] - target[1]) < 40]
    if near: villages.append(low_flat(near))
roads = []
pts = [(G - 1, 120)] + villages + [(0, 140)]
for a, b in zip(pts[:-1], pts[1:]): roads.append(astar(a, b))
roads.append(astar(villages[0], villages[2]) if len(villages) > 2 else [])
# ---------- مواد الأرض (الأقنعة 2048): تراب، عشب يابس، حراثة، زرع | صخر، حصى، طريق
S = 2048; up2 = lambda a: up(a, S)
SL = up2(slope); WA = up2(wadi); Hn = up2((H - H.min()) / (H.max() - H.min()))
n1 = up2(fbm(N, 6, 41)); n2 = up2(fbm(N, 6, 57))
rock = np.clip((SL - .22) * 6 + n1 * 1.5, 0, 1)
gravel = np.clip(WA * 1.4 + np.clip(n2 - .25, 0, 1) * .6, 0, 1) * (1 - rock)
grass = np.clip(.55 + n1 * 1.2 - Hn * .3, 0, 1)
dirt = np.clip(.45 - n1 * 1.2 + n2 * .6, 0, 1)
# حقول: قطع مستطيلة مائلة على الأرض المستوية، حراثة أو زرع، بينها حدود ترابية
fields = Image.new('L', (S, S), 0); fd = ImageDraw.Draw(fields); ftype = Image.new('L', (S, S), 0); ft = ImageDraw.Draw(ftype)
ang = math.radians(rng.uniform(-25, 25))
for _ in range(900):
    cx, cy = rng.integers(0, S, 2)
    if SL[cy, cx] > .06 or WA[cy, cx] > .3: continue
    w, l = rng.uniform(25, 70), rng.uniform(40, 140)         # بالبكسل (3.9 م)
    a = ang + rng.normal(0, .08); ca, sa = math.cos(a), math.sin(a)
    poly = [(cx + ca * x - sa * y, cy + sa * x + ca * y) for x, y in [(-l / 2, -w / 2), (l / 2, -w / 2), (l / 2, w / 2), (-l / 2, w / 2)]]
    fd.polygon(poly, fill=255); t = rng.random(); ft.polygon(poly, fill=60 if t < .5 else 140 if t < .78 else 220)
F = np.asarray(fields.filter(ImageFilter.GaussianBlur(.8))) / 255 * (1 - np.clip(SL * 12 - .5, 0, 1)); T = np.asarray(ftype)
plow = F * (T == 60); wheat = F * (T == 140); stubble = F * (T == 220)
# حدود الحقول ترابية
edge = np.asarray(fields.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3))) / 255
road = Image.new('L', (S, S), 0); rd = ImageDraw.Draw(road)
for p in roads:
    if len(p) < 2: continue
    xy = [(c / (G - 1) * (S - 1), r / (G - 1) * (S - 1)) for r, c in p]
    rd.line(xy, fill=255, width=3, joint='curve')
road = np.asarray(road.filter(ImageFilter.GaussianBlur(.7))) / 255
grass = grass * (1 - F) + stubble; dirt = dirt * (1 - F) + edge * .8
W = np.stack([dirt, grass, plow, wheat, rock, gravel, road * 0], -1)
W = W / np.maximum(W.sum(-1, keepdims=True), 1e-3)
def png(a): b = io.BytesIO(); Image.fromarray(a).save(b, 'PNG', optimize=True); return 'data:image/png;base64,' + base64.b64encode(b.getvalue()).decode()
sp1 = np.asarray(Image.fromarray((np.clip(W[..., :3], 0, 1) * 255).astype(np.uint8)).resize((1024, 1024), Image.BOX)); sp2 = np.asarray(Image.fromarray((np.clip(W[..., 3:6], 0, 1) * 255).astype(np.uint8)).resize((1024, 1024), Image.BOX))   # بلا قناة شفافية: المتصفح يصفّر الألوان تحت الشفافية
# ---------- خريطة النتوء من التفاصيل الدقيقة، والظلال المحسوبة مسبقاً
Hd = up2(H) + up2(fbm(N, 7, 91)) * 0 ; px = SIZE / (S - 1)
dy, dx = np.gradient(Hd, px); nz = 1 / np.sqrt(dx * dx + dy * dy + 1)
nmap = np.stack([(-dx * nz + 1) / 2, (dy * nz + 1) / 2, (nz + 1) / 2], -1)   # الصورة: الصف الأول شمال
SUN = np.array([math.cos(math.radians(40)) * math.sin(math.radians(125)), math.cos(math.radians(40)) * -math.cos(math.radians(125)), math.sin(math.radians(40))])   # الشمس من الجنوب الشرقي، ارتفاع 40°
# ظل التلال: نمشي من كل نقطة باتجاه الشمس، فإن اعترضتها الأرض فهي في الظل
L = 512; hl = up(H, L); pl = SIZE / (L - 1); sh = np.ones((L, L))
yy, xx = np.mgrid[0:L, 0:L].astype(np.float64)
for s in range(1, 120):
    d = s * 1.5; x = xx + SUN[0] * d; y = yy - SUN[1] * d
    hz = ndimage.map_coordinates(hl, [y, x], order=1, mode='nearest')
    rise = hl + SUN[2] / math.hypot(SUN[0], SUN[1]) * d * pl
    sh = np.minimum(sh, np.clip(1 - (hz - rise) / 6, 0, 1))
# تظليل التجاويف (الوديان أغمق قليلاً)
ao = np.clip(1 - (ndimage.gaussian_filter(hl, 3) - hl) / 60, .7, 1.0)
light = up2(np.clip(.6 + .4 * ndimage.gaussian_filter(sh, .7), 0, 1) * ao)
# لون أساس من صورة القمر: نزيل منه إضاءة التصوير (نقسم على نسخته المموهة) ونبقي تنوّع الألوان
sat = np.stack([up(SAT[..., i], 1024) for i in range(3)], -1)
blur = ndimage.gaussian_filter(sat, (60, 60, 0))              # لكل قناة لوحدها: يبقى الفرق فقط بلا لون عام
tint = sat / np.maximum(blur, 1) * 128                      # 128 = لا تغيير
tint = (tint - 128) * .8 + 128
tint = np.clip(tint, 40, 230).astype(np.uint8)
def jpg(a, q=86, mode='L'): b = io.BytesIO(); Image.fromarray(a).convert(mode).save(b, 'JPEG', quality=q, optimize=True); return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()
# ---------- الارتفاعات للمجسم 513×513، والأجسام
MH = up(H, 513); hmin = float(MH.min())
q = np.clip(np.round((MH - hmin) * 10), 0, 65535).astype('<u2')
toW = lambda r, c, n: (c / (n - 1) * SIZE - SIZE / 2, SIZE / 2 - r / (n - 1) * SIZE)      # (x شرق، z شمال)
hAt = lambda x, z: float(ndimage.map_coordinates(MH, [[(SIZE / 2 - z) / SIZE * 512], [(x + SIZE / 2) / SIZE * 512]], order=1)[0])
objs = {'trees': [], 'rocks': [], 'bushes': [], 'houses': [], 'roads': [[[round(v, 1) for v in toW(r / (G - 1) * 512, c / (G - 1) * 512, 512)] for r, c in p[::2] + [p[-1]]] for p in roads if len(p) > 1]}
# أشجار على الوديان وحول القرى، وشجيرات على السهل، وصخور على المنحدرات
wr, wc = np.nonzero(up(wadi, 512) > .45)
for k in rng.choice(len(wr), min(2600, len(wr)), replace=False): x, z = toW(wr[k] + rng.random(), wc[k] + rng.random(), 512); objs['trees'].append([round(x, 1), round(z, 1), int(rng.integers(0, 3)), round(float(rng.uniform(.8, 1.3)), 2)])
s512 = up(slope, 512); rr, rc = np.nonzero(s512 > .3)
for k in rng.choice(len(rr), min(2500, len(rr)), replace=False): x, z = toW(rr[k] + rng.random(), rc[k] + rng.random(), 512); objs['rocks'].append([round(x, 1), round(z, 1), round(float(rng.uniform(.6, 2.2)), 2), round(float(rng.uniform(0, 6.28)), 2)])
br, bc = np.nonzero((s512 < .2) & (up(wadi, 512) < .2))
for k in rng.choice(len(br), 3500, replace=False): x, z = toW(br[k] + rng.random(), bc[k] + rng.random(), 512); objs['bushes'].append([round(x, 1), round(z, 1), round(float(rng.uniform(.6, 1.4)), 2)])
# القرى: بيوت بأفنية وأسوار، وبساتين زيتون بصفوف
for vi, (r, c) in enumerate(villages):
    vx, vz = toW(r / (G - 1) * 512, c / (G - 1) * 512, 512); n = [38, 24, 30, 16][vi % 4]; va = rng.uniform(0, 3.14)
    for i in range(n):
        for _ in range(20):
            d = rng.uniform(15, 230) ** 1 * (1 if i > 4 else .5); a = rng.uniform(0, 6.28); x, z = vx + math.cos(a) * d, vz + math.sin(a) * d
            if all(math.hypot(x - h_[0], z - h_[1]) > 26 for h_ in objs['houses']): break
        objs['houses'].append([round(x, 1), round(z, 1), round(va + rng.choice([0, 1.5708]) + rng.normal(0, .05), 3), int(rng.integers(0, 4)), round(float(rng.uniform(10, 16)), 1), round(float(rng.uniform(9, 14)), 1), round(float(rng.choice([3.4, 3.4, 6.6])), 1)])
    for rr_ in range(6):
        for cc in range(10):
            ox, oz = 260 + cc * 9, -60 + rr_ * 9; ca, sa = math.cos(va), math.sin(va)
            objs['trees'].append([round(vx + ca * ox - sa * oz, 1), round(vz + sa * ox + ca * oz, 1), 0, round(float(rng.uniform(.6, .8)), 2)])
meta = {'size': SIZE, 'n': 513, 'hmin': hmin, 'hmax': float(MH.max()), 'sun': SUN.tolist(), 'villages': [toW(r / (G - 1) * 512, c / (G - 1) * 512, 512) for r, c in villages]}
A = '/home/user/zxc/assets/battle/'
def tex(i, size=1024, q=84):
    im = Image.open(f'{A}{i}.jpg').convert('RGB').resize((size, size), Image.LANCZOS); b = io.BytesIO(); im.save(b, 'JPEG', quality=74, optimize=True); return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()
def cutout(i, size=256):
    im = Image.open(f'{A}{i}.jpg').convert('RGB'); a = np.asarray(im).astype(np.int16); mx, mn = a.max(2), a.min(2); bgish = (mn > 222) & ((mx - mn) < 22)
    lab, _ = ndimage.label(bgish); edge_ = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    al = Image.fromarray(np.where(np.isin(lab, list(edge_)), 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1)); rg = im.copy(); rg.putalpha(al)
    rg = rg.crop(al.point(lambda v: 255 if v > 20 else 0).getbbox()); rg.thumbnail((size, size), Image.LANCZOS)
    c_ = Image.new('RGBA', (size, size), (0, 0, 0, 0)); c_.paste(rg, ((size - rg.width) // 2, (size - rg.height) // 2)); b = io.BytesIO(); c_.save(b, 'PNG', optimize=True); return 'data:image/png;base64,' + base64.b64encode(b.getvalue()).decode()
data = {'meta': meta, 'h': base64.b64encode(q.tobytes()).decode(), 'splat1': png(sp1), 'splat2': png(sp2), 'normal': jpg((nmap * 255).astype(np.uint8), 90, 'RGB'), 'light': jpg((light * 255).astype(np.uint8), 88), 'tint': jpg(tint, 84, 'RGB'),
        'tex': {k: tex(i) for k, i in [('dirt', 51), ('grass', 52), ('plow', 53), ('wheat', 54), ('rock', 55), ('gravel', 56)]},
        'sprites': {k: cutout(i) for k, i in [('olive', 57), ('poplar', 58), ('eucal', 59), ('bush', 60), ('rocks', 61), ('roof1', 62), ('roof2', 63), ('roof3', 64), ('roof4', 65)]}, 'objs': objs}
js = 'const MAP = ' + json.dumps(data) + ';\n'
open('mapdata3d.js', 'w').write(js)
print('villages', len(villages), 'houses', len(objs['houses']), 'trees', len(objs['trees']), 'rocks', len(objs['rocks']), 'size', len(js) // 1024, 'KB', 'relief', round(MH.min()), round(MH.max()))
Image.fromarray((light * 255).astype(np.uint8)).resize((512, 512)).save('chk_light.png')
Image.fromarray(sp1[..., :3]).resize((512, 512)).save('chk_splat.png')
