# انفجار المحاكاة صوراً شفافة بالزاوية المائلة (دخان + تراب + توهج + ظل + كتل تراب)، لكل لحظة صورة، ومحور القاعدة ثابت
import sys, math, json, glob, os, numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates, gaussian_filter, zoom
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
MPP = 66 / 2560 * 2                         # نصف دقة المشهد (يكفي للدخان)
el, az = math.radians(40), math.radians(35)
dirv = np.array([math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)]); f = -dirv
right = np.cross(f, [0, 0, 1]); right /= np.linalg.norm(right); up = np.cross(right, f)
ax, az_ = math.radians(52), math.radians(-35)
Rx = np.array([[1, 0, 0], [0, math.cos(ax), -math.sin(ax)], [0, math.sin(ax), math.cos(ax)]]); Rz = np.array([[math.cos(az_), -math.sin(az_), 0], [math.sin(az_), math.cos(az_), 0], [0, 0, 1]])
L = Rz @ Rx @ np.array([0, 0, -1.]); toSun = -L / np.linalg.norm(L)
# نافذة الصورة حول نقطة الانفجار (بالمتر على مستوى الشاشة)
WL, WR, WU, WD = -26, 26, 34, 12
Wpx, Hpx = int((WR - WL) / MPP), int((WU + WD) / MPP)
U, Vv = np.meshgrid(WL + (np.arange(Wpx) + .5) * MPP, WU - (np.arange(Hpx) + .5) * MPP)
P0 = U[..., None] * right + Vv[..., None] * up
rng = np.random.default_rng(5); NZ3 = 48
def pn(s_):
    g = gaussian_filter(rng.random((NZ3,) * 3).astype(np.float32), s_, mode='wrap'); return (g - g.mean()) / (g.std() + 1e-6)
DN = pn(1.2) * .55 + pn(2.5) * .45
detail = lambda P: map_coordinates(DN, [((P[..., k] / .25) % NZ3) for k in range(3)], order=1, mode='wrap')
meta = {'mpp': MPP, 'w': Wpx, 'h': Hpx, 'ox': -WL / MPP, 'oy': WU / MPP, 'times': [], 'frames': []}
files = sorted(glob.glob(f'{src}/vol*.npz')); times = json.load(open(f'{src}/meta.json'))['times'] if os.path.exists(f'{src}/meta.json') else None
for fi, fn in enumerate(files):
    v = np.load(fn); S = v['S'].astype(np.float32); D = v['D'].astype(np.float32); T = v['T'].astype(np.float32); dx = float(v['dx'])
    NX, NY, NZ = S.shape; cx, cy = NX * .40, NX * .36
    sig = S * 1.6 + D * .75
    idxf = lambda P: np.stack([P[..., 0] / dx + cx, P[..., 1] / dx + cy, P[..., 2] / dx])
    gi, gj, gk = np.meshgrid(np.arange(NX), np.arange(NY), np.arange(NZ), indexing='ij'); acc = np.zeros_like(sig)
    for n in range(1, int(NX * 1.2)):
        s_ = map_coordinates(sig, np.stack([gi + toSun[0] * n, gj + toSun[1] * n, gk + toSun[2] * n]), order=1, mode='constant', cval=0)
        if s_.max() < 1e-4 and n > 20: break
        acc += s_ * dx * .6
    light = np.exp(-acc); mixd = D / (S + D + 1e-5)
    alb = np.stack([.16 + .58 * mixd, .145 + .48 * mixd, .13 + .37 * mixd], -1)
    emit = np.clip(T - 1.2, 0, None)[..., None] * np.array([1.7, .85, .35]) * 2.2
    Pc = P0 - 80 * f; ds = dx * .6
    col = np.zeros(U.shape + (3,), np.float32); Tr = np.ones(U.shape, np.float32)
    for n in range(int(160 / ds)):
        P = Pc + f * (n * ds); idx = idxf(P)
        if not ((idx[2] > -1) & (idx[2] < NZ)).any(): continue
        s_ = map_coordinates(sig, idx, order=1, mode='constant', cval=0)
        if s_.max() < 1e-5: continue
        s_ = s_ * np.clip(1 + .75 * detail(P), 0, 3); s_ = np.where(s_ > 0, s_ ** 1.25, 0); a = 1 - np.exp(-s_ * ds)
        li = map_coordinates(light, idx, order=1, mode='constant', cval=1)
        al = np.stack([map_coordinates(alb[..., k], idx, order=1, mode='nearest') for k in range(3)], -1)
        em = np.stack([map_coordinates(emit[..., k], idx, order=1, mode='constant', cval=0) for k in range(3)], -1)
        col += (Tr * a)[..., None] * (al * (.45 + 1.45 * li)[..., None]) + Tr[..., None] * em * ds * .5; Tr *= 1 - a
    alpha = 1 - Tr
    tg = -Pc[..., 2] / f[2]; G = Pc + f * tg[..., None]; accg = np.zeros(U.shape, np.float32)
    for n in range(1, 160): accg += map_coordinates(sig, idxf(G + toSun * (n * dx * .8)), order=1, mode='constant', cval=0) * dx * .8
    sh = (1 - np.exp(-accg)) * .62
    A = alpha + sh * (1 - alpha); rgb = col / np.maximum(A, 1e-4)[..., None]
    # كتل التراب
    for cxl, cyl, czl, sz in (v['cl'] if len(v['cl']) else []):
        if czl > 14 or math.hypot(cxl - cx * dx, cyl - cy * dx) > 22: continue
        Pw = np.array([cxl - cx * dx, cyl - cy * dx, czl]); px = (np.dot(Pw, right) - WL) / MPP; py = (WU - np.dot(Pw, up)) / MPP; r = (.06 + .17 * sz) / MPP
        if r < .6 or not (0 <= px < Wpx and 0 <= py < Hpx): continue
        yy, xx = np.ogrid[int(py - r - 1):int(py + r + 2), int(px - r - 1):int(px + r + 2)]; yy = np.clip(yy, 0, Hpx - 1); xx = np.clip(xx, 0, Wpx - 1)
        m = np.clip(r + .5 - np.hypot(yy - py, xx - px), 0, 1) * .85
        rgb[yy, xx] = rgb[yy, xx] * (1 - m[..., None]) + np.array([.22, .18, .14]) * m[..., None]; A[yy, xx] = np.maximum(A[yy, xx], m)
    img = np.dstack([np.clip(rgb, 0, 1), np.clip(A, 0, 1)])
    Image.fromarray((img * 255).astype(np.uint8), 'RGBA').save(f'{out}/b{fi:02d}.png'); meta['frames'].append(f'b{fi:02d}.png'); print('frame', fi, flush=True)
json.dump(meta, open(f'{out}/meta.json', 'w')); print('OK blast')
