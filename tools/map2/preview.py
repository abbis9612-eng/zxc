# معاينة البيانات الحقيقية: أنواع الأرض + الطرق + البيوت، لمنطقة بإحداثيات وحجم محددين
# الاستعمال: preview.py lon lat size_m px out.png
import sys, math, numpy as np, pyarrow.parquet as pq, shapely, rasterio
from PIL import Image, ImageDraw
lon0, lat0, size, PX, out = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
mx = 111320 * math.cos(math.radians(lat0)); my = 110540
x0, x1 = lon0 - size / 2 / mx, lon0 + size / 2 / mx; y0, y1 = lat0 - size / 2 / my, lat0 + size / 2 / my
s = PX / size
def P(lon, lat): return ((lon - lon0) * mx * s + PX / 2, PX / 2 - (lat - lat0) * my * s)
# أنواع الأرض (ESA WorldCover)
COL = {10: (92, 110, 64), 20: (150, 145, 100), 30: (186, 175, 128), 40: (170, 160, 105), 50: (170, 160, 150), 60: (205, 190, 160), 80: (90, 120, 140), 90: (110, 130, 110)}
with rasterio.open('worldcover.tif') as r:
    from rasterio.windows import from_bounds
    w = from_bounds(x0, y0, x1, y1, r.transform); a = r.read(1, window=w, boundless=True, fill_value=30)
rgb = np.zeros(a.shape + (3,), np.uint8)
for k, c in COL.items(): rgb[a == k] = c
im = Image.fromarray(rgb).resize((PX, PX), Image.NEAREST).convert('RGB')
# ظل التضاريس الحقيقي (الشمس من الشمال الغربي)
with rasterio.open('dem.tif') as r:
    from rasterio.windows import from_bounds as fb
    e = r.read(1, window=fb(x0, y0, x1, y1, r.transform), boundless=True).astype(np.float32)
gy, gx = np.gradient(e, 30); sl = np.arctan(np.hypot(gx, gy)); asp = np.arctan2(-gx, gy)
az, alt = math.radians(315), math.radians(40)
hs = np.clip(np.sin(alt) * np.cos(sl) + np.cos(alt) * np.sin(sl) * np.cos(az - asp), 0, 1)
hsi = Image.fromarray((hs * 255).astype(np.uint8)).resize((PX, PX), Image.BICUBIC)
arr = np.array(im).astype(np.float32) * (0.45 + 0.75 * np.array(hsi, np.float32)[..., None] / 255)
im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)); d = ImageDraw.Draw(im, 'RGBA')
def load(name, cols):
    t = pq.read_table(name, columns=cols + ['geometry', 'bbox']).to_pylist()
    return [r for r in t if r['bbox']['xmax'] >= x0 and r['bbox']['xmin'] <= x1 and r['bbox']['ymax'] >= y0 and r['bbox']['ymin'] <= y1]
# الطرق حسب صنفها بعرضها الحقيقي
W = {'motorway': 14, 'trunk': 12, 'primary': 10, 'secondary': 8, 'tertiary': 7, 'residential': 6, 'unclassified': 5, 'service': 4, 'track': 3.5, 'path': 1.5, 'footway': 1.5, 'living_street': 5}
roads = load('segment.parquet', ['class', 'subtype'])
nr = 0
for r in roads:
    if r['subtype'] != 'road': continue
    g = shapely.from_wkb(r['geometry']); wdt = W.get(r['class'], 4)
    pts = [P(x, y) for x, y in g.coords]
    paved = r['class'] not in ('track', 'path', 'footway', 'unclassified')
    d.line(pts, fill=(80, 70, 60, 160), width=max(1, int((wdt + 2) * s)), joint='curve')
    d.line(pts, fill=(95, 95, 92, 255) if paved else (214, 196, 160, 255), width=max(1, int(wdt * s)), joint='curve'); nr += 1
nb = 0
try:
    for r in load('building.parquet', ['class']):
        g = shapely.from_wkb(r['geometry'])
        for poly in (g.geoms if hasattr(g, 'geoms') else [g]):
            pts = [P(x, y) for x, y in poly.exterior.coords]
            d.polygon([(x + 2 * s, y + 3 * s) for x, y in pts], fill=(40, 30, 20, 90))
            d.polygon(pts, fill=(214, 204, 186, 255), outline=(90, 78, 62, 255)); nb += 1
except FileNotFoundError: pass
im.save(out); print(out, 'roads', nr, 'buildings', nb)
