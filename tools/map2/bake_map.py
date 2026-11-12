# خَبز ساحة المعركة الحقيقية: قطع أرض مرسومة مسبقاً بثلاث دقات + شبكة ارتفاعات + شبكة أنواع أرض + الأهداف
# الإطار: مدوّر 45° (الشمال الشرقي = أعلى الشاشة)، المركز 700 م جنوب غرب بلدة شزي.
# وحدة اللعبة = 30 م. مركز الساحة في اللعبة (100، 100). الساحة القتالية 5 كم، والمخبوز 6 كم.
import sys, os, math, json, base64, numpy as np, rasterio, pyarrow.parquet as pq, shapely
from shapely.affinity import affine_transform
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import map_coordinates, gaussian_filter
CLON, CLAT = 42.87409, 36.89927     # 1.6 كم جنوب غرب البلدة
MX = 111320 * math.cos(math.radians(CLAT)); MY = 110540
TH = math.radians(45); UP = (math.sin(TH), math.cos(TH)); RT = (math.cos(TH), -math.sin(TH))
HALF = 3600; UNIT = 30; GC = 120          # نصف المخبوز بالمتر (7.2 كم)، ومتر لكل وحدة، ومركز اللعبة
OUT = 'baked'; os.makedirs(OUT + '/tiles', exist_ok=True)
def w2g(wx, wy):  # عالم (م، y للأسفل) ← جغرافي
    gx = RT[0] * wx - UP[0] * wy; gy = RT[1] * wx - UP[1] * wy
    return CLON + gx / MX, CLAT + gy / MY
# جغرافي ← عالم (للرسم المتجه): معكوس الدوران
def g2w_coeffs():
    # gx = a*wx + b*wy ; gy = c*wx + d*wy  →  معكوس المصفوفة
    a, b, c, d = RT[0], -UP[0], RT[1], -UP[1]; det = a * d - b * c
    ia, ib, ic, id_ = d / det, -b / det, -c / det, a / det
    # lon,lat → gx = (lon-CLON)*MX, gy = (lat-CLAT)*MY
    return ia * MX, ib * MY, ic * MX, id_ * MY, -(ia * MX * CLON + ib * MY * CLAT), -(ic * MX * CLON + id_ * MY * CLAT)
GA, GB, GCc, GD, GE, GF = g2w_coeffs()
def geo2w(lon, lat): return GA * lon + GB * lat + GE, GCc * lon + GD * lat + GF
# ---------- البيانات
DEM = rasterio.open('dem.tif'); dem = DEM.read(1).astype(np.float32); DT = DEM.transform
WC = rasterio.open('worldcover.tif'); wc = WC.read(1); WT = WC.transform
def rc(T, lon, lat): c, r = ~T * (lon, lat); return r, c
# تراكم الجريان (الوديان) مرة واحدة لمنطقة الساحة
def area_window(T, arr, pad_m=1500):
    lons, lats = zip(*[w2g(x, y) for x in (-HALF - pad_m, HALF + pad_m) for y in (-HALF - pad_m, HALF + pad_m)])
    r0, c0 = rc(T, min(lons), max(lats)); r1, c1 = rc(T, max(lons), min(lats))
    return int(r0), int(r1) + 1, int(c0), int(c1) + 1
r0, r1, c0, c1 = area_window(DT, dem)
sub = gaussian_filter(dem[r0:r1, c0:c1], .7)
def flowacc(d):
    h, w_ = d.shape; acc = np.ones_like(d); order = np.argsort(-d, axis=None)
    for idx in order:
        i, j = divmod(int(idx), w_); best = None; bd = 0
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                a, b = i + di, j + dj
                if (di or dj) and 0 <= a < h and 0 <= b < w_:
                    s = (d[i, j] - d[a, b]) / math.hypot(di, dj)
                    if s > bd: bd = s; best = (a, b)
        if best: acc[best] += acc[i, j]
    return acc
FA = np.zeros_like(dem); FA[r0:r1, c0:c1] = np.log1p(flowacc(sub)); DEMS = dem.copy(); DEMS[r0:r1, c0:c1] = sub
print('flow done', sub.shape, flush=True)
segs = pq.read_table('segment.parquet', columns=['geometry', 'bbox', 'class', 'subtype']).to_pylist()
blds = pq.read_table('building.parquet', columns=['geometry', 'bbox', 'height', 'num_floors']).to_pylist()
lons, lats = zip(*[w2g(x, y) for x in (-HALF - 300, HALF + 300) for y in (-HALF - 300, HALF + 300)])
BB = (min(lons), min(lats), max(lons), max(lats))
inb = lambda r: r['bbox']['xmax'] >= BB[0] and r['bbox']['xmin'] <= BB[2] and r['bbox']['ymax'] >= BB[1] and r['bbox']['ymin'] <= BB[3]
segs = [r for r in segs if inb(r) and r['subtype'] == 'road']; blds = [r for r in blds if inb(r)]
def to_w(g): return affine_transform(g, [GA, GB, GCc, GD, GE, GF])
ROADS = [(to_w(shapely.from_wkb(r['geometry'])), r['class']) for r in segs]
BLDS = []
for r in blds:
    g = shapely.from_wkb(r['geometry']); area = g.area * MX * MY
    h = r['height'] or (r['num_floors'] or (1 if area < 120 else 2)) * 3.3
    BLDS.append((to_w(g), h, int(abs(hash(r['geometry'][:24])) % 997)))
print('roads', len(ROADS), 'buildings', len(BLDS), flush=True)
# ---------- ضجيج عالمي ثابت (بلا حواف بين القطع)
def hnoise(X, Y, s, seed):
    i = np.floor(X / s).astype(np.int64); j = np.floor(Y / s).astype(np.int64); fx = X / s - i; fy = Y / s - j
    def h(a, b): v = (a * 374761393 + b * 668265263 + seed * 2147483647) & 0xffffffff; v = (v ^ (v >> 13)) * 1274126177 & 0xffffffff; return ((v ^ (v >> 16)) & 0xffff) / 65535.0
    sx = fx * fx * (3 - 2 * fx); sy = fy * fy * (3 - 2 * fy)
    return (h(i, j) * (1 - sx) + h(i + 1, j) * sx) * (1 - sy) + (h(i, j + 1) * (1 - sx) + h(i + 1, j + 1) * sx) * sy
def noise(X, Y, s, seed, oct=4):
    acc = 0; amp = 1; tot = 0
    for o in range(oct): acc = acc + amp * hnoise(X, Y, s / 2 ** o, seed + o); tot += amp; amp *= .5
    return (acc / tot).astype(np.float32)
INFO = json.load(open('tex/info.json')); TEX = {}
def texload(n):
    if n not in TEX:
        im = np.asarray(Image.open(f'tex/{n}.jpg').convert('RGB'), np.float32) / 255; TEX[n] = {0: im}; TEX[n]['sm'] = INFO[n]['scale_m'][0] / 1000
    return TEX[n]
def tex(n, X, Y, mpp):
    t = texload(n); sm = t['sm']; H = t[0].shape[0]
    if sm / mpp < 28:   # القطعة صغيرة جداً على الشاشة: معدل لونها (التكرار يظهر نقشاً)
        if 'mean' not in t: t['mean'] = t[0].reshape(-1, 3).mean(0)
        return np.broadcast_to(t['mean'], X.shape + (3,)).copy()
    k = max(0, int(math.log2(max(1, H * mpp / sm))))           # مستوى تصغير مناسب (mipmap)
    if k not in t: t[k] = np.asarray(Image.fromarray((t[0] * 255).astype(np.uint8)).resize((H >> k, H >> k), Image.BOX), np.float32) / 255
    im = t[k]; h = im.shape[0]
    u = (np.floor(X / sm * h).astype(np.int64)) % h; v = (np.floor(Y / sm * h).astype(np.int64)) % h
    return im[v, u]
ROOF = [(204, 196, 182), (190, 184, 172), (214, 208, 196), (176, 160, 140), (198, 186, 166), (168, 166, 160)]
WID = {'motorway': 15, 'trunk': 12, 'primary': 10, 'secondary': 8, 'tertiary': 7, 'residential': 6, 'living_street': 5, 'unclassified': 5, 'service': 4, 'track': 3.5, 'path': 1.4, 'footway': 1.4, 'steps': 1.4}
ASPH = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'residential', 'living_street'}
def render(wx0, wy0, size, mpp):
    N = int(round(size / mpp)); xs = wx0 + (np.arange(N) + .5) * mpp; ys = wy0 + (np.arange(N) + .5) * mpp
    X, Y = np.meshgrid(xs, ys)
    lon = CLON + (RT[0] * X - UP[0] * Y) / MX; lat = CLAT + (RT[1] * X - UP[1] * Y) / MY
    r, c = rc(DT, lon, lat)
    Z = map_coordinates(DEMS, [r - .5, c - .5], order=3)
    dzy, dzx = np.gradient(Z, mpp); slope = np.degrees(np.arctan(np.hypot(dzx, dzy))); asp = np.arctan2(-dzx, dzy)
    az, alt = math.radians(315), math.radians(45)
    hs = np.clip(np.sin(alt) * np.cos(np.radians(slope)) + np.cos(alt) * np.sin(np.radians(slope)) * np.cos(az - asp), 0, 1)
    fa = map_coordinates(FA, [r - .5, c - .5], order=1)
    wadi = np.clip((fa - 4.2) / 1.5, 0, 1) * np.clip(1 - slope / 25, 0, 1) * np.clip(noise(X, Y, 30, 9) * 1.6 - .2, 0, 1) ** .5
    r2, c2 = rc(WT, lon, lat); wx_ = (noise(X, Y, 25, 11) - .5) * 1.2; wy_ = (noise(X, Y, 25, 12) - .5) * 1.2
    def cw(k):
        # وزن النوع: تنعيم داخل نافذة محلية من خريطة 10 م
        m = (wc == k).astype(np.float32)
        return map_coordinates(m, [r2 - .5 + wy_, c2 - .5 + wx_], order=1)
    Wt = {k: cw(k) for k in (10, 20, 30, 40, 50, 60, 80)}
    Wt = {k: gaussian_filter(v, max(.5, 6 / mpp)) for k, v in Wt.items()}
    T = lambda n: tex(n, X, Y, mpp)
    macro = noise(X, Y, 120, 21); mid = noise(X, Y, 18, 22)
    grass = T('withered_grass') * (1 - .45 * macro[..., None]) + T('aerial_grass_rock') * (.45 * macro[..., None])
    bare = T('dry_ground_rocks') * (1 - mid[..., None] * .5) + T('aerial_ground_rock') * (mid[..., None] * .5)
    # قطع زراعية غير منتظمة: خلايا متعرجة بأحجام مختلفة
    ang = math.radians(10); U = X * math.cos(ang) + Y * math.sin(ang); V = -X * math.sin(ang) + Y * math.cos(ang)
    # قطع زراعية: شبكة ثابتة (140×60 م) بحدود متعرجة قليلاً، وبعض القطع مقسومة نصين
    wj = (noise(X, Y, 220, 51) - .5) * 30
    Uu, Vv = U + wj, V + wj * .5
    pu = np.floor(Uu / 140); pv = np.floor(Vv / 60)
    hsh = ((pu * 73856093).astype(np.int64) ^ (pv * 19349663).astype(np.int64)) & 0xffff
    split = (hsh % 3 == 0) & ((Uu / 140) % 1 > .5)
    pid = (hsh + split * 7) % 97
    ptype = pid % 4
    plough = T('farm_soil') * .5 + T('raked_dirt') * .5; plough = plough * (1 + .7 * (np.array([.66, .58, .47]) / plough.mean((0, 1)) - 1))
    stubble = T('withered_grass') * .65 + T('dry_ground_01') * .35
    fallow = T('dry_ground_01') * .6 + T('dry_mud_field_001') * .4
    crop = plough * (ptype == 0)[..., None] + stubble * ((ptype == 1) | (ptype == 3))[..., None] + fallow * (ptype == 2)[..., None]
    crop *= (1 + .08 * np.sin(Vv / .9 * 2 * math.pi) * (ptype == 0) * (mpp < 1.2))[..., None]
    edge = np.minimum(np.abs((Uu / 140) % 1 - .5), np.abs((Vv / 60) % 1 - .5))
    crop *= (1 - .12 * (edge > .485))[..., None]
    shrub = T('sparse_grass') * .6 + T('dry_ground_01') * .4
    tree = T('forest_ground_04'); built = T('dry_ground_01') * .55 + T('gravel_road') * .45
    rock = T('rocks_ground_02') * .5 + T('aerial_rocks_02') * .5; water = np.zeros_like(rock) + np.array([.28, .36, .38])
    tot = sum(Wt.values()) + 1e-6
    col = (grass * Wt[30][..., None] + bare * Wt[60][..., None] + crop * Wt[40][..., None] + shrub * Wt[20][..., None] + tree * Wt[10][..., None] + built * Wt[50][..., None] + water * Wt[80][..., None]) / tot[..., None]
    rk = np.clip((slope - 14) / 10, 0, 1) * .85 * np.clip(noise(X, Y, 40, 61) * 1.5, 0, 1)
    col = col * (1 - rk[..., None]) + rock * rk[..., None]
    riv = T('dry_river_pebbles') * .5 + T('dry_riverbed_rock') * .5
    col = col * (1 - wadi[..., None] * .85) + riv * (wadi[..., None] * .85)
    col *= (.92 + .16 * noise(X, Y, 300, 41))[..., None]
    lum = col.mean(2, keepdims=True); col = (col * .55 + lum * np.array([1.08, .98, .82]) * .45) * 1.08
    col *= (.42 + .78 * hs)[..., None]
    a = np.clip(col, 0, 1)
    # ---- الطرق
    Pt = lambda x, y: ((x - wx0) / mpp, (y - wy0) / mpp)
    masks = {k: Image.new('L', (N, N), 0) for k in ('asph', 'gravel', 'dirt', 'edge', 'line')}
    D = {k: ImageDraw.Draw(m) for k, m in masks.items()}
    box = shapely.box(wx0 - 50, wy0 - 50, wx0 + size + 50, wy0 + size + 50)
    for g, cls in ROADS:
        if not g.intersects(box): continue
        pts = [Pt(x, y) for x, y in g.coords]; wdt = WID.get(cls, 4) / mpp
        kind = 'asph' if cls in ASPH else ('gravel' if cls in ('unclassified', 'service') else 'dirt')
        D['edge'].line(pts, fill=255, width=max(1, int(wdt + 3 / mpp)), joint='curve'); D[kind].line(pts, fill=255, width=max(1, int(wdt)), joint='curve')
        if cls in ('primary', 'secondary', 'trunk') and mpp < 1: D['line'].line(pts, fill=255, width=max(1, int(.15 / mpp)))
    def blend(mask, layer, soft=.6, alpha=1.0):
        nonlocal a
        m = np.asarray(mask.filter(ImageFilter.GaussianBlur(max(.4, soft / mpp))), np.float32)[..., None] / 255 * alpha
        a = a * (1 - m) + layer * m
    shade = (.45 + .7 * hs)[..., None]
    blend(masks['edge'], T('dry_ground_01') * .9 * (.42 + .78 * hs)[..., None], 1.2, .6)
    blend(masks['dirt'], (T('gravel_road') * .6 + T('dry_ground_01') * .4) * 1.05 * shade, .5)
    blend(masks['gravel'], T('sandy_gravel') * .82 * shade, .3)
    blend(masks['asph'], ((T('asphalt_02') * .6 + T('aerial_asphalt_01') * .4) * .95 + T('dry_ground_01') * .15) * (.55 + .5 * hs)[..., None], .25)
    if mpp < 1:
        lm = np.asarray(masks['line'], np.float32) / 255 * (np.sin((X + Y) / 1.5) > .3)
        a = a * (1 - lm[..., None] * .7) + np.array([.92, .9, .82]) * lm[..., None] * .7
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert('RGBA')
    # ---- البيوت: ظل، وسطح، وحاجز، وخزان ماء
    sh_l = Image.new('RGBA', (N, N), (0, 0, 0, 0)); rf_l = Image.new('RGBA', (N, N), (0, 0, 0, 0)); SH = ImageDraw.Draw(sh_l); RF = ImageDraw.Draw(rf_l)
    rng = np.random.default_rng(int(wx0 * 7 + wy0 * 13) & 0xffff)
    for g, h, rid in BLDS:
        if not g.intersects(box): continue
        o = h * .62 / mpp
        for poly in (g.geoms if hasattr(g, 'geoms') else [g]):
            pts = [Pt(x, y) for x, y in poly.exterior.coords]
            SH.polygon([(x + o, y + o) for x, y in pts], fill=(25, 18, 10, 120))
            for (ax_, ay_), (bx_, by_) in zip(pts, pts[1:]): SH.polygon([(ax_, ay_), (bx_, by_), (bx_ + o, by_ + o), (ax_ + o, ay_ + o)], fill=(25, 18, 10, 120))
            RF.polygon(pts, fill=ROOF[rid % len(ROOF)] + (255,), outline=(120, 108, 92, 255))
            if mpp < 1.2:
                inner = poly.buffer(-.45, join_style=2)
                if not inner.is_empty and inner.geom_type == 'Polygon': RF.line([Pt(x, y) for x, y in inner.exterior.coords], fill=(235, 230, 220, 255), width=max(1, int(.2 / mpp)))
                if poly.area > 60 and mpp < .8:
                    cx, cy = Pt(poly.centroid.x, poly.centroid.y); s = .9 / mpp; tx, ty = cx + (rid % 5 - 2) / mpp, cy + (rid % 3 - 1) / mpp
                    RF.ellipse([tx - s, ty - s, tx + s, ty + s], fill=(70, 80, 88, 255))
    img = Image.alpha_composite(img, sh_l.filter(ImageFilter.GaussianBlur(max(.3, .35 / mpp)))); img = Image.alpha_composite(img, rf_l)
    # ---- الأشجار
    tr_l = Image.new('RGBA', (N, N), (0, 0, 0, 0)); ts_l = Image.new('RGBA', (N, N), (0, 0, 0, 0)); TR = ImageDraw.Draw(tr_l); TS = ImageDraw.Draw(ts_l)
    step = max(1, int(4 / mpp)); dens = (Wt[10] * .5 + wadi * .08 + Wt[20] * .04 + Wt[50] * .05)
    for i in range(0, N, step):
        for j in range(0, N, step):
            if rng.random() < dens[i, j] * .35:
                rr = rng.uniform(1.6, 3.4) / mpp
                if rr < .7: continue
                ii, jj = i + rng.uniform(0, step), j + rng.uniform(0, step)
                TS.ellipse([jj - rr * .1, ii - rr * .1, jj + rr * 1.9, ii + rr * 1.9], fill=(20, 16, 8, 110))
                gg = int(rng.uniform(70, 100)); TR.ellipse([jj - rr, ii - rr, jj + rr, ii + rr], fill=(gg - 20, gg, gg - 45, 255)); TR.ellipse([jj - rr * .7, ii - rr * .75, jj + rr * .2, ii + rr * .1], fill=(gg + 15, gg + 30, gg - 15, 200))
    img = Image.alpha_composite(img, ts_l.filter(ImageFilter.GaussianBlur(max(.3, .5 / mpp)))); img = Image.alpha_composite(img, tr_l.filter(ImageFilter.GaussianBlur(max(.2, .15 / mpp))))
    return img.convert('RGB'), Z, slope, wadi, Wt
if __name__ == '__main__':
    mode = sys.argv[1]
    if mode == 'test':
        im, *_ = render(-700, -1500, 500, .5); im.save(OUT + '/test.png'); print('test ok')
    if mode == 'l0':      # الساحة كاملة 6 كم بدقة 4 م
        im, *_ = render(-HALF, -HALF, 2 * HALF, 4); im.save(OUT + '/tiles/l0.webp', quality=86); print('l0 ok', flush=True)
    if mode in ('l1', 'l2'):
        TOWN_WY = -1600; L2C = TOWN_WY + 700        # مركز L2: بين البلدة والخط الأمامي
        if mode == 'l1': size, mpp, n, ox, oy = 600, 1, 12, -HALF, -HALF
        else: size, mpp, n, ox, oy = 300, .5, 12, -1800, L2C - 1800
        done = 0; rows = range(int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else range(n)
        for j in rows:
            for i in range(n):
                f = f'{OUT}/tiles/{mode}_{i}_{j}.webp'
                if os.path.exists(f): continue
                im, *_ = render(ox + i * size, oy + j * size, size, mpp); im.save(f, quality=84); done += 1
            print(mode, 'row', j, flush=True)
        print(mode, 'ok', done)
        json.dump({'l0': {'size': 2 * HALF / UNIT}, 'l1': {'n': 12, 'tile': 600 / UNIT, 'x0': 0, 'y0': 0}, 'l2': {'n': 12, 'tile': 300 / UNIT, 'x0': (HALF - 1800) / UNIT, 'y0': (HALF + L2C - 1800) / UNIT}}, open(OUT + '/tiles_meta.json', 'w'))
