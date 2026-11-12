# بيانات المحاكاة للساحة الجديدة: ارتفاعات (30 م)، وأنواع أرض (10 م)، والأهداف — بإحداثيات اللعبة (وحدة = 30 م، المركز 100,100)
import json, base64, math, numpy as np, shapely
from PIL import Image, ImageDraw
from scipy.ndimage import map_coordinates
import bake_map as B
def g(wx, wy): return wx / B.UNIT + B.GC, wy / B.UNIT + B.GC          # عالم بالمتر ← إحداثيات اللعبة
# ---- الارتفاعات: كل وحدة لعبة (30 م)
n = int(2 * B.HALF / B.UNIT) + 1; ws = -B.HALF + np.arange(n) * B.UNIT
X, Y = np.meshgrid(ws, ws)
lon = B.CLON + (B.RT[0] * X - B.UP[0] * Y) / B.MX; lat = B.CLAT + (B.RT[1] * X - B.UP[1] * Y) / B.MY
r, c = B.rc(B.DT, lon, lat); Z = map_coordinates(B.DEMS, [r - .5, c - .5], order=1).astype(np.float32)
hq = np.clip(np.round(Z * 2), 0, 65535).astype('<u2')
hgrid = {'x0': B.GC - B.HALF / B.UNIT, 'y0': B.GC - B.HALF / B.UNIT, 'cell': 1, 'w': n, 'h': n, 'H': base64.b64encode(hq.tobytes()).decode()}
# ---- أنواع الأرض كل 10 م
M = 10; m = int(2 * B.HALF / M); ws2 = -B.HALF + (np.arange(m) + .5) * M; X2, Y2 = np.meshgrid(ws2, ws2)
lon2 = B.CLON + (B.RT[0] * X2 - B.UP[0] * Y2) / B.MX; lat2 = B.CLAT + (B.RT[1] * X2 - B.UP[1] * Y2) / B.MY
r2, c2 = B.rc(B.WT, lon2, lat2); wc = B.wc[np.clip(r2.astype(int), 0, B.wc.shape[0] - 1), np.clip(c2.astype(int), 0, B.wc.shape[1] - 1)]
rr, cc = B.rc(B.DT, lon2, lat2); Zt = map_coordinates(B.DEMS, [rr - .5, cc - .5], order=1)
gy_, gx_ = np.gradient(Zt, M); slope = np.degrees(np.arctan(np.hypot(gx_, gy_)))
fa = map_coordinates(B.FA, [rr - .5, cc - .5], order=1)
T = np.zeros((m, m), np.uint8)                       # 0 أرض مفتوحة (عشب/شجيرات/بور)
T[wc == 40] = 3; T[wc == 10] = 8; T[wc == 80] = 6; T[wc == 50] = 0
T[(fa > 5.0) & (slope < 20)] = 7                     # قاع وادٍ
T[slope > 18] = 4                                    # منحدر صخري وعر
img = Image.new('L', (m, m), 255); d = ImageDraw.Draw(img)
P = lambda x, y: ((x + B.HALF) / M, (y + B.HALF) / M)
for poly, h, rid in B.BLDS:
    for p in (poly.geoms if hasattr(poly, 'geoms') else [poly]): d.polygon([P(x, y) for x, y in p.exterior.coords], fill=5)
for gm, cls in B.ROADS:
    kind = 1 if cls in B.ASPH else 2
    d.line([P(x, y) for x, y in gm.coords], fill=kind, width=max(1, round(B.WID.get(cls, 4) / M)))
R_ = np.asarray(img); T = np.where(R_ != 255, R_, T).astype(np.uint8)
terr = {'x0': B.GC - B.HALF / B.UNIT, 'y0': B.GC - B.HALF / B.UNIT, 'cell': M / B.UNIT, 'w': m, 'h': m, 'T': base64.b64encode(T.tobytes()).decode()}
print('terrain classes', np.bincount(T.ravel(), minlength=9))
# ---- الأهداف
tx, ty = B.geo2w(42.8868, 36.9095)
best = None
for wx in range(int(tx) - 1400, int(tx) + 1401, 30):
    for wy in range(int(ty) - 1500, int(ty) - 700, 30):   # التلة: 0.7-1.5 كم شمال البلدة
        z = float(map_coordinates(Z, [[(wy + B.HALF) / B.UNIT], [(wx + B.HALF) / B.UNIT]], order=1)[0])
        if not best or z > best[0]: best = (z, wx, wy)
# المفرق: نقطة التقاء أكثر الطرق الرئيسية غرب البلدة
from collections import Counter
ends = Counter()
for gm, cls in B.ROADS:
    if cls in ('trunk', 'primary', 'secondary', 'tertiary'):
        for x, y in (gm.coords[0], gm.coords[-1]): ends[(round(x / 25) * 25, round(y / 25) * 25)] += 1
cand = [(k, v) for k, v in ends.items() if v >= 3 and tx - 2200 < k[0] < tx - 300 and ty - 900 < k[1] < ty + 1300]
cand.sort(key=lambda kv: (-kv[1], abs(kv[0][1] - ty)))
xr = cand[0][0] if cand else (tx - 900, ty)
OBJ = [{'id': 'town', 'n': 'شزي', 'x': g(tx, ty)[0], 'y': g(tx, ty)[1], 'r': 20},
       {'id': 'hill', 'n': 'التلة', 'x': g(best[1], best[2])[0], 'y': g(best[1], best[2])[1], 'r': 12, 'elev': round(best[0])},
       {'id': 'xroad', 'n': 'المفرق', 'x': g(*xr)[0], 'y': g(*xr)[1], 'r': 10}]
print(json.dumps(OBJ, ensure_ascii=False))
json.dump({'hgrid': hgrid, 'terr': terr, 'obj': OBJ, 'half': B.HALF / B.UNIT, 'gc': B.GC, 'battle_half': (B.HALF - 200) / B.UNIT}, open('baked/simdata.json', 'w'))
print('elev min/max', float(Z.min()), float(Z.max()))
