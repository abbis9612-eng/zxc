# خريطة معركة مرسومة واضحة (2D): أرضية هادئة الألوان من الارتفاعات الحقيقية، وعناصر مرسومة بخطوط حادة
# الوحدة: بكسل الحقل (≈30 م). الأرضية بدقة 2 بكسل لكل بكسل حقل في منطقة القتال، و1 لبقية المنطقة.
import json, math, io, base64, heapq
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
exec(open('compose.py').read().split('def build')[0])     # mosaic + elev + rgb
F = json.load(open('../terrain/field.json'))
rng = np.random.default_rng(5)
BOX = (560, 380, 1960, 2180)                                  # منطقة القتال
TOWNS = [('duhok', 1165, 667, 75), ('simele', 731, 700, 55), ('alqosh', 1445, 1147, 55), ('baadra', 1762, 1256, 40), ('telkaif', 1509, 2029, 55)]

def noise(shape, cell, seed):
    r = np.random.default_rng(seed); g = r.random((shape[0] // cell + 3, shape[1] // cell + 3))
    return ndimage.zoom(g, cell, order=3)[:shape[0], :shape[1]]

def paint(z, box, scale, satz):
    """يرسم الأرضية: z = مستوى بلاطات الارتفاع، scale = بكسل صورة لكل بكسل حقل"""
    h = np.maximum(mosaic(z, *box, 'e', elev), 0).astype(np.float64)
    sat = mosaic(satz, *box, 's', rgb).astype(np.float64)
    H, Wd = int((box[3] - box[1]) * scale), int((box[2] - box[0]) * scale)
    h = np.asarray(Image.fromarray(h.astype(np.float32)).resize((Wd, H), Image.BICUBIC)).astype(np.float64)
    sat = np.stack([np.asarray(Image.fromarray(sat[..., i].astype(np.uint8)).resize((Wd, H), Image.BILINEAR)) for i in range(3)], -1).astype(np.float64)
    h = ndimage.gaussian_filter(h, 1.2 * scale)
    px = 30.0 / scale
    gy, gx = np.gradient(h, px); slope = np.hypot(gx, gy)
    az, alt = math.radians(315), math.radians(42)
    sl = np.arctan(slope * 1.4); asp = np.arctan2(-gx, gy)
    shade = np.clip(np.sin(alt) * np.cos(sl) + np.cos(alt) * np.sin(sl) * np.cos(az - asp), 0, 1)
    shade = (shade - np.sin(alt)) * 1.35 + 1.0                  # 1 = مستوٍ
    # ألوان هادئة: سهل رملي فاتح، تلال أغمق قليلاً، صخر رمادي على المنحدرات
    hn = np.clip((h - 250) / 900, 0, 1)
    plain = np.array([206, 194, 164.]); hill = np.array([178, 162, 128.]); rock = np.array([158, 150, 140.]); high = np.array([196, 188, 172.])
    col = plain * (1 - hn[..., None]) + hill * hn[..., None]
    col = col * (1 - np.clip((hn[..., None] - .7) * 3, 0, 1)) + high * np.clip((hn[..., None] - .7) * 3, 0, 1)
    rk = np.clip((slope - .22) * 3.5, 0, .85)[..., None]; col = col * (1 - rk) + rock * rk
    # تنوع من صورة القمر بقوة خفيفة: الحقول الخضراء والمحروثة تظهر كبقع هادئة
    lum = sat.mean(-1, keepdims=True); green = np.clip((sat[..., 1:2] - sat[..., :1]) / 18, 0, 1) * np.clip((140 - lum) / 60, 0, 1)
    dark = np.clip((150 - lum) / 70, 0, 1) * (1 - green)
    col = col * (1 - green * .55) + np.array([150, 160, 112.]) * green * .55
    col = col * (1 - dark * .22) + np.array([150, 128, 100.]) * dark * .22
    # ماء: البحيرة
    water = (sat[..., 2] > sat[..., 0] * .95) & (lum[..., 0] < 95) & (slope < .06)
    water = ndimage.binary_opening(water, iterations=2); water = ndimage.binary_closing(water, iterations=2)
    # ضوضاء أرضية ناعمة جداً
    n = noise((H, Wd), int(40 * scale), 1) * .06 + noise((H, Wd), int(6 * scale), 2) * .05
    col = col * (1 + n[..., None] - .055)
    col = col * shade[..., None]
    wcol = np.array([92, 128, 142.]); wsh = ndimage.distance_transform_edt(water)
    wc = wcol * (1 - np.clip(wsh / (6 * scale), 0, 1)[..., None] * .25) + np.array([70, 104, 122.]) * np.clip(wsh / (6 * scale), 0, 1)[..., None] * .25
    col = np.where(water[..., None], wc, col)
    # حافة الماء رملية فاتحة
    edge = ndimage.binary_dilation(water, iterations=max(1, int(scale))) & ~water
    col[edge] = col[edge] * .4 + np.array([214, 204, 178.]) * .6
    return np.clip(col, 0, 255).astype(np.uint8), h, slope, water

# ---------- منطقة القتال بدقة عالية
img, h2, sl2, water2 = paint(13, BOX, 2, 13)
Hh, Ww = h2.shape
# الوديان الجافة من تراكم الجريان (على شبكة 4 بكسل حقل)
G = 4; hm = ndimage.zoom(h2, 1 / (2 * G), order=1); M0, M1 = hm.shape
order = np.argsort(-hm, axis=None); acc = np.ones(hm.size); flat = hm.ravel(); down = -np.ones(hm.size, int)
nb = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
for idx in order:
    i, j = divmod(idx, M1); best = -1; bd = 0
    for di, dj in nb:
        a, b = i + di, j + dj
        if 0 <= a < M0 and 0 <= b < M1:
            d = (flat[idx] - flat[a * M1 + b]) / math.hypot(di, dj)
            if d > bd: bd = d; best = a * M1 + b
    down[idx] = best
    if best >= 0: acc[best] += acc[idx]
wd = ImageDraw.Draw(wimg := Image.new('L', (Ww, Hh), 0))
for idx in range(hm.size):
    if acc[idx] < 40 or down[idx] < 0: continue
    i, j = divmod(idx, M1); k, l = divmod(down[idx], M1)
    w = 1 + min(5, math.log(acc[idx] / 40 + 1) * 1.6)
    wd.line([((j + .5) * 2 * G, (i + .5) * 2 * G), ((l + .5) * 2 * G, (k + .5) * 2 * G)], fill=int(min(255, 90 + acc[idx] / 8)), width=int(w))
wad = np.asarray(wimg.filter(ImageFilter.GaussianBlur(1.6))).astype(np.float64) / 255
# مجرى الوادي: حصى فاتح في الوسط وحافة أغمق، وعليه خط ماء موسمي رفيع في الكبيرة
col = img.astype(np.float64)
col = col * (1 - wad[..., None] * .5) + np.array([196, 184, 156.]) * wad[..., None] * .5
core = np.asarray(wimg.point(lambda v: 255 if v > 200 else 0).filter(ImageFilter.GaussianBlur(.8))).astype(np.float64) / 255
col = col * (1 - core[..., None] * .55) + np.array([110, 140, 150.]) * core[..., None] * .55
img = np.clip(col, 0, 255).astype(np.uint8)
print('base', img.shape)

# ---------- العناصر المرسومة (بكسل الحقل)
hf = ndimage.zoom(h2, .5, order=1); sf = ndimage.zoom(sl2, .5, order=1); wf = ndimage.zoom(water2.astype(float), .5, order=0) > .5
FH, FW = hf.shape
def inb(x, y): return 0 <= x < FW and 0 <= y < FH
def H_(x, y): return hf[int(min(FH - 1, max(0, y))), int(min(FW - 1, max(0, x)))]
# طرق: أقصر مسار بأقل انحدار بين المدن (شبكة 3 بكسل)
R = 3; Rh, Rw = FH // R, FW // R; slR = sf[::R, ::R][:Rh, :Rw]; wR = wf[::R, ::R][:Rh, :Rw]
cost = 1 + (slR * 30) ** 2 + wR * 400
def astar(a, b):
    dist = {a: 0}; prev = {}; pq = [(0, 0, a)]
    while pq:
        _, d, u = heapq.heappop(pq)
        if u == b: break
        if d > dist[u]: continue
        for di, dj in nb:
            v = (u[0] + di, u[1] + dj)
            if 0 <= v[0] < Rh and 0 <= v[1] < Rw:
                nd = d + cost[v] * math.hypot(di, dj)
                if nd < dist.get(v, 1e18): dist[v] = nd; prev[v] = u; heapq.heappush(pq, (nd + math.hypot(v[0] - b[0], v[1] - b[1]), nd, v))
    p = [b]
    while p[-1] != a: p.append(prev[p[-1]])
    return p[::-1]
def toR(x, y): return (int((y - BOX[1]) / R), int((x - BOX[0]) / R))
def fromR(p): return [round(BOX[0] + p[1] * R + R / 2, 1), round(BOX[1] + p[0] * R + R / 2, 1)]
def smooth(pts, it=3):
    P = [list(p) for p in pts]
    for _ in range(it):
        for i in range(1, len(P) - 1): P[i] = [(P[i - 1][0] + P[i][0] * 2 + P[i + 1][0]) / 4, (P[i - 1][1] + P[i][1] * 2 + P[i + 1][1]) / 4]
    return [[round(a, 1), round(b, 1)] for a, b in P[::2] + [P[-1]]]
T = {t[0]: t for t in TOWNS}
# قرى إضافية على أرض مستوية قرب الوديان
villages = []
for _ in range(4000):
    x, y = rng.uniform(620, 1900), rng.uniform(450, 2120)
    lx, ly = int((x - BOX[0])), int((y - BOX[1]))
    if not inb(lx, ly) or sf[ly, lx] > .06 or wf[ly, lx]: continue
    if any(math.hypot(x - t[1], y - t[2]) < t[3] + 60 for t in TOWNS) or any(math.hypot(x - v[0], y - v[1]) < 110 for v in villages): continue
    villages.append((round(x, 1), round(y, 1), int(rng.integers(14, 30))))
    if len(villages) >= 22: break
roads = []
main = [('telkaif', 'alqosh'), ('alqosh', 'duhok'), ('duhok', 'simele'), ('alqosh', 'baadra'), ('telkaif', 'simele')]
for a, b in main:
    p = astar(toR(T[a][1], T[a][2]), toR(T[b][1], T[b][2])); roads.append({'w': 2.4, 'p': smooth([fromR(q) for q in p])})
for v in villages:
    near = min(TOWNS + [(None, *u[:2], 0) for u in villages if u is not v], key=lambda t: math.hypot(t[1] - v[0], t[2] - v[1]))
    p = astar(toR(v[0], v[1]), toR(near[1], near[2])); roads.append({'w': 1.1, 'p': smooth([fromR(q) for q in p])})
# المدن والقرى: شوارع متعامدة، وعلى جانبي كل شارع بيوت متلاصقة بأفنية، وجامع بقبة
houses = []; walls = []; mosques = []
def okpt(x, y, smax=.16):
    lx, ly = int(x - BOX[0]), int(y - BOX[1]); return inb(lx, ly) and not wf[ly, lx] and sf[ly, lx] < smax
def settlement(cx, cy, r, ang, street_gap, dens):
    ca, sa = math.cos(ang), math.sin(ang); P = lambda u, v: (cx + ca * u - sa * v, cy + sa * u + ca * v)
    n = int(r / street_gap)
    for k in range(-n, n + 1):                       # شوارع بالاتجاهين
        for horiz in (0, 1):
            seg = []
            for t in np.arange(-r, r + .1, 1.5):
                u, v = (t, k * street_gap) if horiz else (k * street_gap, t)
                x, y = P(u, v)
                if math.hypot(u, v) < r * (.85 + .15 * math.sin(u * .3 + v * .2)) and okpt(x, y): seg.append([round(x, 1), round(y, 1)])
                elif len(seg) > 2: roads.append({'w': .7 if street_gap < 8 else .9, 'p': seg, 'town': 1}); seg = []
                else: seg = []
            if len(seg) > 2: roads.append({'w': .7 if street_gap < 8 else .9, 'p': seg, 'town': 1})
    # كتل البيوت بين الشوارع
    for gu in np.arange(-r, r, street_gap):
        for gv in np.arange(-r, r, street_gap):
            for iu in np.arange(.9, street_gap - .9, 1.7):
                for iv in (1.0, street_gap - 1.0):
                    u, v = gu + iu, gv + iv
                    if math.hypot(u, v) > r * (.8 + .2 * rng.random()) or rng.random() > dens: continue
                    x, y = P(u, v)
                    if not okpt(x, y): continue
                    w, l = rng.uniform(1.15, 1.55), rng.uniform(1.2, 1.7)
                    houses.append([round(x, 2), round(y, 2), round(w, 2), round(l, 2), round(ang + rng.normal(0, .02), 3), int(rng.choice([0, 0, 1, 2, 2, 4, 3]))])
                    if rng.random() < .3: walls.append([round(x, 2), round(y, 2), round(w + .7, 2), round(l + .7, 2), houses[-1][4]])
    for _ in range(max(1, int(r / 25))):
        u, v = rng.uniform(-r * .4, r * .4), rng.uniform(-r * .4, r * .4); x, y = P(u, v)
        if okpt(x, y): mosques.append([round(x, 2), round(y, 2), round(ang, 3)])
for name, x, y, r in TOWNS:
    settlement(x, y, r * .8, rng.uniform(-.35, .35), 7 if name == 'duhok' else 6, .9)
for v in villages: settlement(v[0], v[1], 8 + v[2] * .35, rng.uniform(0, 3.1), 6, .55)
# أشجار: على الوديان، وبساتين بصفوف حول القرى
trees = []
wf2 = ndimage.zoom(wad, .5, order=1)
ys, xs = np.nonzero(wf2 > .45)
for k in rng.choice(len(ys), min(5000, len(ys)), replace=False): trees.append([round(BOX[0] + xs[k] + rng.random(), 2), round(BOX[1] + ys[k] + rng.random(), 2), round(float(rng.uniform(.25, .45)), 2)])
for v in villages + [(t[1], t[2], 0) for t in TOWNS]:
    ox, oy = v[0] + rng.uniform(-40, 40), v[1] + rng.uniform(-40, 40); a = rng.uniform(0, 3.1); ca, sa = math.cos(a), math.sin(a)
    for i in range(int(rng.integers(5, 10))):
        for j in range(int(rng.integers(6, 14))):
            dx, dy = i * .9, j * .9; x, y = ox + ca * dx - sa * dy, oy + sa * dx + ca * dy
            lx, ly = int(x - BOX[0]), int(y - BOX[1])
            if inb(lx, ly) and not wf[ly, lx] and sf[ly, lx] < .1: trees.append([round(x, 2), round(y, 2), .3])
# حقول بخطوط حراثة على الأرض المستوية (مرسومة في الأرضية)
fimg = Image.fromarray(img); fd = ImageDraw.Draw(fimg, 'RGBA')
for _ in range(2600):
    x, y = rng.uniform(BOX[0], BOX[2]), rng.uniform(BOX[1], BOX[3]); lx, ly = int(x - BOX[0]), int(y - BOX[1])
    if not inb(lx, ly) or sf[ly, lx] > .045 or wf[ly, lx] or wf2[ly, lx] > .2: continue
    if any(math.hypot(x - t[1], y - t[2]) < t[3] for t in TOWNS): continue
    a = rng.normal(.2, .25) + rng.choice([0, 1.5708]); ca, sa = math.cos(a), math.sin(a); w, l = rng.uniform(5, 14), rng.uniform(8, 22)
    poly = [((x + ca * px_ - sa * py_ - BOX[0]) * 2, (y + sa * px_ + ca * py_ - BOX[1]) * 2) for px_, py_ in [(-l / 2, -w / 2), (l / 2, -w / 2), (l / 2, w / 2), (-l / 2, w / 2)]]
    kind = rng.random()
    c = (128, 104, 76, 70) if kind < .4 else (150, 160, 100, 62) if kind < .65 else (220, 206, 168, 55)
    fd.polygon(poly, fill=c)
    for s in np.arange(-w / 2 + .5, w / 2, .8):                                         # خطوط الحراثة
        p0 = ((x + ca * (-l / 2) - sa * s - BOX[0]) * 2, (y + sa * (-l / 2) + ca * s - BOX[1]) * 2); p1 = ((x + ca * (l / 2) - sa * s - BOX[0]) * 2, (y + sa * (l / 2) + ca * s - BOX[1]) * 2)
        fd.line([p0, p1], fill=(0, 0, 0, 14))
    fd.polygon(poly, outline=(110, 92, 70, 60))
img = np.asarray(fimg)
# ---------- البلاطات والملف
T512 = 512; tiles = []
for ty in range(0, img.shape[0], T512):
    row = []
    for tx in range(0, img.shape[1], T512):
        b = io.BytesIO(); Image.fromarray(img[ty:ty + T512, tx:tx + T512]).save(b, 'JPEG', quality=72, optimize=True); row.append('data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode())
    tiles.append(row)
# بقية المنطقة بدقة أقل وبنفس الألوان
img1, *_ = paint(12, (0, 0, F['w'], F['h']), 1, 12)
b = io.BytesIO(); Image.fromarray(img1).save(b, 'JPEG', quality=72, optimize=True); base1 = 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()
Image.fromarray(img).resize((Ww // 4, Hh // 4)).save('../map2d_prev.jpg', quality=85)
Image.fromarray(img[1300:2300, 1000:1900]).save('../map2d_crop.jpg', quality=85)
out = {'roads': roads, 'houses': houses, 'walls': walls, 'trees': trees, 'villages': villages, 'mosques': mosques}
json.dump({'tiles': tiles, 'base': base1, 'feat': out}, open('map2d.json', 'w'))
print('mosques', len(mosques), 'roads', len(roads), 'houses', len(houses), 'walls', len(walls), 'trees', len(trees), 'villages', len(villages), 'tiles', len(tiles), 'x', len(tiles[0]))
