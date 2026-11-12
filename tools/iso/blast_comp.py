# تصوير حجم الانفجار المحاكى (دخان، تراب، حرارة) من زاوية الكاميرا المائلة نفسها، وتركيبه على صورة المشهد مع ظله على الأرض
import sys, math, numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates, zoom
base, vol, out = sys.argv[1], sys.argv[2], sys.argv[3]
BX, BY = float(sys.argv[4]), float(sys.argv[5])          # موضع الانفجار في العالم (م)
K = float(sys.argv[6]) if len(sys.argv) > 6 else 1.0      # تكبير الحجم (1 = 155 ملم)
img = np.asarray(Image.open(base).convert('RGB'), np.float32) / 255
H, W = img.shape[:2]
# الكاميرا (مطابقة لـ street.py)
el, az = math.radians(40), math.radians(35); MPP = 62 / W
dirv = np.array([math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)]); f = -dirv
right = np.cross(f, [0, 0, 1]); right /= np.linalg.norm(right); up = np.cross(right, f)
tgt = np.array([0, 2, 0.])
# الشمس: دوران (52°، 0، -35°) لاتجاه (0،0،-1)
ax, az_ = math.radians(52), math.radians(-35)
Rx = np.array([[1, 0, 0], [0, math.cos(ax), -math.sin(ax)], [0, math.sin(ax), math.cos(ax)]]); Rz = np.array([[math.cos(az_), -math.sin(az_), 0], [math.sin(az_), math.cos(az_), 0], [0, 0, 1]])
L = Rz @ Rx @ np.array([0, 0, -1.]); toSun = -L / np.linalg.norm(L)
v = np.load(vol); S = v['S'].astype(np.float32); D = v['D'].astype(np.float32); T = v['T'].astype(np.float32); dx = float(v['dx']) * K
NX, NY, NZ = S.shape; cx, cy = NX * .40, NX * .36
sig = (S * 1.6 + D * .75) / K
# تفاصيل دقيقة: ضجيج ثلاثي الأبعاد متكرر (كتل متكورة بحجم 0.4-2 م) يضرب الكثافة، ثم شحذ
from scipy.ndimage import gaussian_filter
rng = np.random.default_rng(5); NZ3 = 48
def pnoise(sz, s_):
    g = gaussian_filter(rng.random((NZ3, NZ3, NZ3)).astype(np.float32), s_, mode='wrap'); g = (g - g.mean()) / (g.std() + 1e-6); return g
DN = pnoise(48, 1.2) * .55 + pnoise(48, 2.5) * .45; DN_M = .25   # متر لكل خلية ضجيج
def detail(P):
    c = [((P[..., k] / DN_M) % NZ3) for k in range(3)]
    return map_coordinates(DN, c, order=1, mode='wrap')
def to_idx(P):  # عالم ← فهرس الشبكة
    return np.stack([(P[..., 0] - BX) / dx + cx, (P[..., 1] - BY) / dx + cy, P[..., 2] / dx])
# ضوء الشمس الواصل لكل خلية: سير نحو الشمس
gi, gj, gk = np.meshgrid(np.arange(NX), np.arange(NY), np.arange(NZ), indexing='ij')
acc = np.zeros_like(sig); step = 1.0
for n in range(1, int(NX * 1.2)):
    c = np.stack([gi + toSun[0] * n * step, gj + toSun[1] * n * step, gk + toSun[2] * n * step])
    s_ = map_coordinates(sig, c, order=1, mode='constant', cval=0)
    if s_.max() < 1e-4 and n > 20: break
    acc += s_ * step * dx * .6
light = np.exp(-acc)
mixd = D / (S + D + 1e-5)
alb = np.stack([.16 + .58 * mixd, .145 + .48 * mixd, .13 + .37 * mixd], -1)
emit = np.clip(T - 1.2, 0, None)[..., None] * np.array([1.7, .85, .35]) * 2.2
# ---- السير عبر المشهد لكل بكسل في نافذة حول الانفجار
c0 = np.array([BX, BY, 0.]); pc = (np.dot(c0 - tgt, right) / MPP + W / 2, -np.dot(c0 - tgt, up) / MPP + H / 2)
ext = NX * dx * .75; R = int(ext / MPP) + 40
x0, x1 = int(max(0, pc[0] - R)), int(min(W, pc[0] + R)); y0, y1 = int(max(0, pc[1] - R * 1.7)), int(min(H, pc[1] + R * .6))
SUB = 2
us = np.arange(x0, x1, SUB); vs = np.arange(y0, y1, SUB); U, Vv = np.meshgrid(us, vs)
P0 = tgt + ((U - W / 2) * MPP)[..., None] * right + (-(Vv - H / 2) * MPP)[..., None] * up       # نقطة على مستوى الصورة عند الهدف
# بداية الشعاع: نرجع للخلف 120 م نحو الكاميرا، ثم نسير للأمام
Pc = P0 - 120 * f
ds = dx * .6; nstep = int(240 / ds)
col = np.zeros(U.shape + (3,), np.float32); Tr = np.ones(U.shape, np.float32)
ground_hit = np.zeros(U.shape + (3,), np.float32)
for n in range(nstep):
    P = Pc + f * (n * ds)
    idx = to_idx(P)
    inside = (idx[0] > -1) & (idx[0] < NX) & (idx[1] > -1) & (idx[1] < NY) & (idx[2] > -1) & (idx[2] < NZ)
    if not inside.any(): continue
    s_ = map_coordinates(sig, idx, order=1, mode='constant', cval=0)
    s_ = s_ * np.clip(1 + .75 * detail(P), 0, 3)
    s_ = np.where(s_ > 0, s_ ** 1.25, 0)
    a = 1 - np.exp(-s_ * ds)
    li = map_coordinates(light, idx, order=1, mode='constant', cval=1)
    al = np.stack([map_coordinates(alb[..., k], idx, order=1, mode='nearest') for k in range(3)], -1)
    em = np.stack([map_coordinates(emit[..., k], idx, order=1, mode='constant', cval=0) for k in range(3)], -1)
    lit = al * (.45 + 1.45 * li)[..., None]
    col += (Tr * a)[..., None] * lit + Tr[..., None] * em * ds * .5
    Tr *= 1 - a
alpha = 1 - Tr
# ظل الدخان على الأرض: لكل بكسل نقطة الأرض (z=0) على شعاعه، ثم عتمة الطريق نحو الشمس
t_g = -Pc[..., 2] / f[2]; G = Pc + f * t_g[..., None]
accg = np.zeros(U.shape, np.float32)
for n in range(1, 200):
    Q = G + toSun * (n * dx * .8); idx = to_idx(Q)
    accg += map_coordinates(sig, idx, order=1, mode='constant', cval=0) * dx * .8
shadow = 1 - np.exp(-accg)
# ---- التركيب
reg = img[y0:y1:SUB, x0:x1:SUB][:U.shape[0], :U.shape[1]]
reg = reg * (1 - .62 * shadow[..., None])
reg = reg * (1 - alpha[..., None]) + col
full_reg = zoom(reg, (SUB, SUB, 1), order=1)[: y1 - y0, : x1 - x0]
out_img = img.copy(); out_img[y0:y0 + full_reg.shape[0], x0:x0 + full_reg.shape[1]] = full_reg
# كتل التراب الطائرة: نقاط داكنة بظلها
for cxl, cyl, czl, sz in v['cl'] if len(v['cl']) else []:
    Pw = np.array([(cxl - cx * float(v['dx'])) * K + BX, (cyl - cy * float(v['dx'])) * K + BY, czl * K])
    px = np.dot(Pw - tgt, right) / MPP + W / 2; py = -np.dot(Pw - tgt, up) / MPP + H / 2; r = (.06 + .17 * sz) / MPP
    if r < 1 or not (0 <= px < W and 0 <= py < H): continue
    yy, xx = np.ogrid[int(py - r - 1):int(py + r + 2), int(px - r - 1):int(px + r + 2)]
    yy = np.clip(yy, 0, H - 1); xx = np.clip(xx, 0, W - 1)
    m = np.clip(r + .5 - np.hypot(yy - py, xx - px), 0, 1)[..., None]
    out_img[yy, xx] = out_img[yy, xx] * (1 - m * .85) + np.array([.22, .18, .14]) * m * .85
Image.fromarray((np.clip(out_img, 0, 1) * 255).astype(np.uint8)).save(out); print('ok', out, (x0, y0, x1, y1))
