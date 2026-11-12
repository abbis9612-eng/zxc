# رسم قطعة من الخريطة بالشكل النهائي من البيانات الحقيقية:
# أنواع الأرض (WorldCover) ← نسيج مصوّر بحجمه الحقيقي، وظل التضاريس (Copernicus)، والوديان من مجاري الماء،
# والطرق بعرضها ونوعها، والبيوت بأشكالها وظلها وسطوحها، والأشجار.
# الاستعمال: render_area.py lon lat size_m m_per_px out.png
import sys, math, json, numpy as np, rasterio, pyarrow.parquet as pq, shapely
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import map_coordinates, gaussian_filter, zoom as nzoom
lon0, lat0, SIZE, MPP, out = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), sys.argv[5]
N = int(round(SIZE / MPP)); MX = 111320 * math.cos(math.radians(lat0)); MY = 110540
x0, x1 = lon0 - SIZE / 2 / MX, lon0 + SIZE / 2 / MX; y0, y1 = lat0 - SIZE / 2 / MY, lat0 + SIZE / 2 / MY
rng = np.random.default_rng(3)
# إحداثيات كل بكسل بالأمتار (عالمية، حتى يتطابق النسيج بين القطع)
gx = (lon0 - 42.6) * MX - SIZE / 2 + (np.arange(N) + .5) * MPP
gy = (37.05 - lat0) * MY - SIZE / 2 + (np.arange(N) + .5) * MPP
GX, GY = np.meshgrid(gx, gy)
def noise(scale_m, seed, oct=4):
    # ضجيج سلس بالأمتار (لكسر التكرار وتنويع الألوان)
    r = np.random.default_rng(seed); acc = np.zeros((N, N), np.float32); amp = 1; tot = 0
    for o in range(oct):
        s = scale_m / (2 ** o); g = r.random((int(SIZE / s) + 3, int(SIZE / s) + 3)).astype(np.float32)
        acc += amp * map_coordinates(g, [(GY - GY[0, 0]) / s + 1, (GX - GX[0, 0]) / s + 1], order=1); tot += amp; amp *= .5
    return acc / tot
TEX = {}; INFO = json.load(open('tex/info.json'))
def tex(name, val=1.0):
    if name not in TEX:
        im = np.asarray(Image.open(f'tex/{name}.jpg').convert('RGB'), np.float32) / 255
        TEX[name] = (im, INFO[name]['scale_m'][0] / 1000)
    im, sm = TEX[name]; H = im.shape[0]
    u = ((GX / sm) * H).astype(np.int64) % H; v = ((GY / sm) * H).astype(np.int64) % H
    # عند البعد نصغّر النسيج (متوسط ألوانه) حتى لا يتكسر
    if MPP > sm / 64:
        k = max(1, int(H * MPP / sm / 2)); sm_im = np.asarray(Image.fromarray((im * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(k)), np.float32) / 255
        return sm_im[v, u]
    return im[v, u]
# ---------- الارتفاعات وظل التضاريس والوديان
with rasterio.open('dem.tif') as r:
    from rasterio.windows import from_bounds
    pad = .02; w = from_bounds(x0 - pad, y0 - pad, x1 + pad, y1 + pad, r.transform); dem = r.read(1, window=w, boundless=True).astype(np.float32); T = r.window_transform(w)
dem = gaussian_filter(dem, .7)
ci = (GX - ((T.c - 42.6) * MX)) / (T.a * MX); ri = (GY - ((37.05 - T.f) * MY)) / (-T.e * MY)
Z = map_coordinates(dem, [ri - .5, ci - .5], order=3)
dzy, dzx = np.gradient(Z, MPP); slope = np.degrees(np.arctan(np.hypot(dzx, dzy))); asp = np.arctan2(-dzx, dzy)
az, alt = math.radians(315), math.radians(45)
hs = np.clip(np.sin(alt) * np.cos(np.radians(slope)) + np.cos(alt) * np.sin(np.radians(slope)) * np.cos(az - asp), 0, 1)
# مجاري الماء (تراكم الجريان D8) على شبكة 30 م
def flowacc(d):
    h, w_ = d.shape; acc = np.ones_like(d); order = np.argsort(-d, axis=None)
    for idx in order:
        i, j = divmod(idx, w_); best = None; bd = 0
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                a, b = i + di, j + dj
                if (di or dj) and 0 <= a < h and 0 <= b < w_:
                    s = (d[i, j] - d[a, b]) / math.hypot(di, dj)
                    if s > bd: bd = s; best = (a, b)
        if best: acc[best] += acc[i, j]
    return acc
fa = flowacc(dem)
FA = map_coordinates(np.log1p(fa), [ri - .5, ci - .5], order=1)
wadi = np.clip((FA - 4.2) / 1.5, 0, 1) * np.clip(1 - slope / 25, 0, 1)
wadi *= np.clip(noise(30, 9) * 1.6 - .2, 0, 1) ** .5
# ---------- أنواع الأرض (بحدود طبيعية متعرجة بدل مربعات 10 م)
with rasterio.open('worldcover.tif') as r:
    w = from_bounds(x0 - pad, y0 - pad, x1 + pad, y1 + pad, r.transform); wc = r.read(1, window=w, boundless=True, fill_value=30); T2 = r.window_transform(w)
ci2 = (GX - ((T2.c - 42.6) * MX)) / (T2.a * MX); ri2 = (GY - ((37.05 - T2.f) * MY)) / (-T2.e * MY)
warp = 6 / 10
wx = (noise(25, 11) - .5) * 2 * warp * 2; wy = (noise(25, 12) - .5) * 2 * warp * 2
def cls_w(k, blur=0.9):
    m = gaussian_filter((wc == k).astype(np.float32), blur)
    return map_coordinates(m, [ri2 - .5 + wy, ci2 - .5 + wx], order=1)
W = {k: cls_w(k) for k in (10, 20, 30, 40, 50, 60, 80)}
# ---------- خلط النسيج
macro = noise(120, 21); mid = noise(18, 22)
grass = tex('withered_grass') * (1 - .45 * macro[..., None]) + tex('aerial_grass_rock') * (.45 * macro[..., None])
bare = tex('dry_ground_rocks') * (1 - mid[..., None] * .5) + tex('aerial_ground_rock') * (mid[..., None] * .5)
ang = math.radians(35); U = GX * math.cos(ang) + GY * math.sin(ang); V = -GX * math.sin(ang) + GY * math.cos(ang)
wj = (noise(60, 51) - .5) * 40
pu = np.floor((U + wj) / 160); pv = np.floor((V + wj * .5) / 70); pid = (pu * 7919 + pv * 104729) % 97
ptype = (pid % 3)
plough = tex('farm_soil') * .55 + tex('raked_dirt') * .45
plough = plough * (1 + .5 * (np.array([.62, .53, .42]) / plough.mean((0, 1)) - 1))   # أفتح، بلون تراب المنطقة
stubble = tex('withered_grass') * .7 + tex('dry_ground_01') * .3
fallow = tex('dry_ground_01') * .6 + tex('dry_mud_field_001') * .4
crop = plough * (ptype == 0)[..., None] + stubble * (ptype == 1)[..., None] + fallow * (ptype == 2)[..., None]
furrow = 1 + .08 * np.sin(V / .9 * 2 * math.pi) * (ptype == 0) * (MPP < 1.2)
crop *= furrow[..., None]
edge = np.minimum(np.abs(((U + wj) / 160) % 1 - .5), np.abs(((V + wj * .5) / 70) % 1 - .5))
crop *= (1 - .18 * (edge > .485))[..., None]      # حدود القطع (سواقي وممرات)
shrub = tex('sparse_grass') * .6 + tex('dry_ground_01') * .4
tree = tex('forest_ground_04')
built = tex('dry_ground_01') * .55 + tex('gravel_road') * .45
rock = tex('rocks_ground_02') * .5 + tex('aerial_rocks_02') * .5
water = np.zeros_like(rock) + np.array([.28, .36, .38])
tot = sum(W.values()) + 1e-6
col = (grass * W[30][..., None] + bare * W[60][..., None] + crop * W[40][..., None] + shrub * W[20][..., None] + tree * W[10][..., None] + built * W[50][..., None] + water * W[80][..., None]) / tot[..., None]
# الحقول: قطع بأشكال مستطيلة متجاورة بألوان مختلفة قليلاً (حصاد، حراثة، بور)
fld = noise(70, 31, oct=1); col *= (1 + (W[40] / tot * (np.floor(fld * 5) / 5 - .5) * .25))[..., None]
rk = np.clip((slope - 14) / 10, 0, 1) * .85
col = col * (1 - rk[..., None]) + rock * rk[..., None]
riv = tex('dry_river_pebbles') * .5 + tex('dry_riverbed_rock') * .5
col = col * (1 - wadi[..., None] * .85) + riv * (wadi[..., None] * .85)
col *= (.92 + .16 * noise(300, 41))[..., None]            # تنوع لوني واسع
col *= (.42 + .78 * hs)[..., None]                        # ظل التضاريس
lum = col.mean(2, keepdims=True); tone = np.array([1.08, .98, .82])
col = col * .55 + (lum * tone) * .45; col = col * 1.08
img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
# ---------- الطرق
def P(lon, lat): return ((lon - x0) * MX / MPP, (y1 - lat) * MY / MPP)
def load(name, cols):
    t = pq.read_table(name, columns=cols + ['geometry', 'bbox']).to_pylist()
    e = 200 / MX
    return [r for r in t if r['bbox']['xmax'] >= x0 - e and r['bbox']['xmin'] <= x1 + e and r['bbox']['ymax'] >= y0 - e and r['bbox']['ymin'] <= y1 + e]
WID = {'motorway': 15, 'trunk': 12, 'primary': 10, 'secondary': 8, 'tertiary': 7, 'residential': 6, 'living_street': 5, 'unclassified': 5, 'service': 4, 'track': 3.5, 'path': 1.4, 'footway': 1.4, 'steps': 1.4}
ASPH = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'residential', 'living_street'}
roads = [r for r in load('segment.parquet', ['class', 'subtype']) if r['subtype'] == 'road']
masks = {}
for kind in ('asph', 'gravel', 'dirt', 'edge', 'line'):
    masks[kind] = Image.new('L', (N, N), 0)
D = {k: ImageDraw.Draw(m) for k, m in masks.items()}
for r in roads:
    g = shapely.from_wkb(r['geometry']); pts = [P(x, y) for x, y in g.coords]; wdt = WID.get(r['class'], 4) / MPP
    kind = 'asph' if r['class'] in ASPH else ('gravel' if r['class'] in ('unclassified', 'service') else 'dirt')
    D['edge'].line(pts, fill=255, width=max(1, int(wdt + 3 / MPP)), joint='curve')
    D[kind].line(pts, fill=255, width=max(1, int(wdt)), joint='curve')
    if r['class'] in ('primary', 'secondary', 'trunk') and MPP < 1: D['line'].line(pts, fill=255, width=max(1, int(.15 / MPP)))
a = np.asarray(img, np.float32) / 255
def blend(mask, layer, soft=.6, alpha=1.0):
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(max(.4, soft / MPP))), np.float32)[..., None] / 255 * alpha
    return a * (1 - m) + layer * m
dust = tex('dry_ground_01') * .9
a = blend(masks['edge'], dust * (.42 + .78 * hs)[..., None], 1.2, .6)
a = blend(masks['dirt'], (tex('gravel_road') * .6 + tex('dry_ground_01') * .4) * 1.05 * (.45 + .7 * hs)[..., None], .5)
a = blend(masks['gravel'], tex('sandy_gravel') * .82 * (.45 + .7 * hs)[..., None], .3)
asph = (tex('asphalt_02') * .6 + tex('aerial_asphalt_01') * .4) * .95 + tex('dry_ground_01') * .15
a = blend(masks['asph'], asph * (.55 + .5 * hs)[..., None], .25)
if MPP < 1:
    dash = (np.sin((GX + GY) / 1.5) > .3)
    lm = np.asarray(masks['line'], np.float32) / 255 * dash
    a = a * (1 - lm[..., None] * .7) + np.array([.92, .9, .82]) * lm[..., None] * .7
img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert('RGBA')
# ---------- البيوت: ظل باتجاه الجنوب الشرقي حسب الارتفاع، وسطح بلون الخرسانة، وحاجز سطح، وخزان ماء
SH = ImageDraw.Draw(sh_l := Image.new('RGBA', (N, N), (0, 0, 0, 0)))
RF = ImageDraw.Draw(rf_l := Image.new('RGBA', (N, N), (0, 0, 0, 0)))
roofs = [(204, 196, 182), (190, 184, 172), (214, 208, 196), (176, 160, 140), (198, 186, 166), (168, 166, 160)]
blds = load('building.parquet', ['height', 'num_floors'])
for r in blds:
    g = shapely.from_wkb(r['geometry'])
    h = r['height'] or (r['num_floors'] or (1 if g.area * MX * MY < 120 else 2)) * 3.3
    ox, oy = h * .62 / MPP, h * .62 / MPP          # طول الظل ≈ الارتفاع × 0.87 باتجاه الجنوب الشرقي
    for poly in (g.geoms if hasattr(g, 'geoms') else [g]):
        pts = [P(x, y) for x, y in poly.exterior.coords]
        if max(abs(p[0]) for p in pts) > N * 2: continue
        # ظل: مضلع البيت مزاح + الجسر بينهما
        sp = [(x + ox, y + oy) for x, y in pts]
        SH.polygon(sp, fill=(25, 18, 10, 120))
        for (ax_, ay_), (bx_, by_) in zip(pts, pts[1:]): SH.polygon([(ax_, ay_), (bx_, by_), (bx_ + ox, by_ + oy), (ax_ + ox, ay_ + oy)], fill=(25, 18, 10, 120))
        c = roofs[int(abs(hash(r['geometry'][:20])) % len(roofs))]
        RF.polygon(pts, fill=c + (255,), outline=(120, 108, 92, 255))
        if MPP < 1.2:
            inner = poly.buffer(-.45 * 1 / MX / 1, join_style=2)
            if not inner.is_empty and inner.geom_type == 'Polygon':
                RF.line([P(x, y) for x, y in inner.exterior.coords], fill=(235, 230, 220, 255), width=max(1, int(.2 / MPP)))
            if g.area * MX * MY > 60 and MPP < .6:
                cx, cy = P(poly.centroid.x, poly.centroid.y); s = .9 / MPP
                tx, ty = cx + rng.uniform(-2, 2) / MPP, cy + rng.uniform(-2, 2) / MPP
                RF.ellipse([tx - s, ty - s, tx + s, ty + s], fill=(70, 80, 88, 255))     # خزان ماء
sh_l = sh_l.filter(ImageFilter.GaussianBlur(max(.3, .35 / MPP)))
img = Image.alpha_composite(img, sh_l); img = Image.alpha_composite(img, rf_l)
# ---------- الأشجار: تيجان بظل، في مناطق الأشجار وقرب البيوت والوديان
TR = ImageDraw.Draw(tr_l := Image.new('RGBA', (N, N), (0, 0, 0, 0)))
TS = ImageDraw.Draw(ts_l := Image.new('RGBA', (N, N), (0, 0, 0, 0)))
dens = (W[10] * .02 + wadi * .004 + W[20] * .002) / max(1, (1 / MPP) ** 2) * 16
n_try = int(N * N / max(1, int(4 / MPP) ** 2))
ii = rng.integers(0, N, n_try); jj = rng.integers(0, N, n_try)
for i, j in zip(ii, jj):
    if rng.random() < dens[i, j] * (4 / MPP) ** 2 / 16:
        rr = rng.uniform(1.6, 3.4) / MPP
        if rr < .8: continue
        TS.ellipse([j - rr + rr * .9, i - rr + rr * .9, j + rr + rr * .9, i + rr + rr * .9], fill=(20, 16, 8, 110))
        g_ = int(rng.uniform(70, 100)); TR.ellipse([j - rr, i - rr, j + rr, i + rr], fill=(g_ - 20, g_, g_ - 45, 255))
        TR.ellipse([j - rr * .7, i - rr * .75, j + rr * .2, i + rr * .1], fill=(g_ + 15, g_ + 30, g_ - 15, 200))
ts_l = ts_l.filter(ImageFilter.GaussianBlur(max(.3, .5 / MPP))); tr_l = tr_l.filter(ImageFilter.GaussianBlur(max(.2, .15 / MPP)))
img = Image.alpha_composite(img, ts_l); img = Image.alpha_composite(img, tr_l)
img.convert('RGB').save(out); print(out, N, 'px', len(roads), 'roads', len(blds), 'buildings')
