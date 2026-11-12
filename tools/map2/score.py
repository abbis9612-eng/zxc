# تقييم كل مربع 5×5 كم: بلدة متوسطة، تضاريس (جبل ووديان)، طرق، تنوع أرض، بلا بحيرة كبيرة
import numpy as np, math, rasterio, pyarrow.parquet as pq, shapely
from scipy.ndimage import gaussian_filter
D = rasterio.open('dem.tif'); dem = D.read(1).astype(np.float32); dt = D.transform
C = rasterio.open('worldcover.tif'); wc = C.read(1); ct = C.transform
lat0 = 36.75; mx = 111320 * math.cos(math.radians(lat0)); my = 110540
inc = dem - gaussian_filter(dem, 8)          # الوديان: أخفض من محيطها (~250 م)
gy, gx = np.gradient(dem, 30); slope = np.degrees(np.arctan(np.hypot(gx, gy)))
b = pq.read_table('building.parquet', columns=['bbox']).to_pylist(); bx = np.array([(r['bbox']['xmin'] + r['bbox']['xmax']) / 2 for r in b]); by = np.array([(r['bbox']['ymin'] + r['bbox']['ymax']) / 2 for r in b])
s = pq.read_table('segment.parquet', columns=['geometry', 'subtype', 'class']).to_pylist()
rx, ry, rl = [], [], []
for r in s:
    if r['subtype'] != 'road': continue
    g = shapely.from_wkb(r['geometry']); c = g.centroid; rx.append(c.x); ry.append(c.y); rl.append(g.length * mx)
rx, ry, rl = map(np.array, (rx, ry, rl))
S = 5000; dlon = S / mx; dlat = S / my; res = []
for cx in np.arange(42.65 + dlon / 2, 43.28 - dlon / 2, 1000 / mx):
    for cy in np.arange(36.47 + dlat / 2, 37.03 - dlat / 2, 1000 / my):
        x0, x1, y0, y1 = cx - dlon / 2, cx + dlon / 2, cy - dlat / 2, cy + dlat / 2
        nb = int(((bx > x0) & (bx < x1) & (by > y0) & (by < y1)).sum())
        L = float(rl[(rx > x0) & (rx < x1) & (ry > y0) & (ry < y1)].sum()) / 1000
        c0, r0 = ~dt * (x0, y1); c1, r1 = ~dt * (x1, y0); e = dem[int(r0):int(r1), int(c0):int(c1)]; sl = slope[int(r0):int(r1), int(c0):int(c1)]; ic = inc[int(r0):int(r1), int(c0):int(c1)]
        a0, b0 = ~ct * (x0, y1); a1, b1 = ~ct * (x1, y0); w = wc[int(b0):int(b1), int(a0):int(a1)]
        rel = float(np.percentile(e, 98) - np.percentile(e, 2)); flat = float((sl < 6).mean()); wadi = float((ic < -10).mean()); water = float((w == 80).mean())
        p = np.bincount(w.ravel(), minlength=100)[[10, 20, 30, 40, 50, 60]] + 1e-9; p = p / p.sum(); ent = float(-(p * np.log(p)).sum())
        sc = (math.exp(-((math.log(max(nb, 1)) - math.log(1200)) / .8) ** 2)       # بلدة ~1200 بيت
              * min(1, rel / 250) * min(1, flat / .35) * min(1, wadi / .06) * min(1, L / 40) * (1 - min(1, water * 5)) * (.5 + ent / 2))
        res.append((sc, round(cx, 4), round(cy, 4), nb, round(L), round(rel), round(flat, 2), round(wadi, 3), round(water, 3), round(ent, 2)))
res.sort(reverse=True)
print('score  lon     lat     bldg roadkm relief flat wadi water landmix')
picked = []
for r in res:
    if all(abs(r[1] - q[1]) * mx > 4000 or abs(r[2] - q[2]) * my > 4000 for q in picked): picked.append(r)
    if len(picked) == 6: break
for r in picked: print(r)
