# محاكاة انفجار قذيفة شديدة الانفجار على أرض ترابية: سوائل ثلاثية الأبعاد + كتل تراب طائرة
# الناتج: إطارات من فوق (لون + شفافية) وظل على الأرض، بأزمنة حقيقية
import numpy as np, json, sys, time, os
from scipy.ndimage import map_coordinates, gaussian_filter, zoom
from scipy.fft import dctn, idctn

P = dict(
    name='h155', NX=128, NZ=80, dx=1.0,        # متر لكل خلية
    blastR=5.0, blastV=70.0, T0=9.0,           # نصف قطر العصفة، وسرعتها م/ث، والحرارة الابتدائية
    soot=1.0, dust=3.0,                        # كمية السخام (TNT ناقص الأكسجين) والتراب
    clods=300, clodV=(14, 55),                 # كتل التراب الطائرة وسرعتها
    wind=(0.8, 2.5), buoy=3.2, Tdecay=0.35,     # ريح م/ث، وطفو، وزمن تبرد الغاز
    settle=0.35, vort=0.9,                     # سرعة ترسب التراب، وقوة الدوامات
    times=[0.03, 0.06, 0.1, 0.15, 0.22, 0.3, 0.4, 0.52, 0.66, 0.82, 1.0, 1.25, 1.5, 1.8, 2.2, 2.7, 3.3, 4.0, 4.8, 5.8, 7.0, 8.4, 10, 12, 14.5, 17.5, 21, 25, 30],
    seed=7)
if len(sys.argv) > 1: P.update(json.loads(open(sys.argv[1]).read()))
rng = np.random.default_rng(P['seed'])
NX, NZ, dx = P['NX'], P['NZ'], P['dx']
sh = (NX, NX, NZ)
f32 = np.float32
u = np.zeros(sh, f32); v = np.zeros(sh, f32); w = np.zeros(sh, f32)
T = np.zeros(sh, f32); S = np.zeros(sh, f32); D = np.zeros(sh, f32)
X, Y, Z = np.meshgrid(np.arange(NX, dtype=f32), np.arange(NX, dtype=f32), np.arange(NZ, dtype=f32), indexing='ij')
cx, cy = NX * .40, NX * .36; Zc = Z + .5
R = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2 + Zc ** 2) * dx

# ---- العصفة: كرة غاز حار تندفع للخارج وللأعلى، ومعها تراب الحفرة
br = P['blastR']
core = np.clip(1 - R / br, 0, 1) ** 1.2
shell = np.exp(-((R - br * 1.4) / (br * .6)) ** 2) * (R < br * 2.6)
nx_, ny_, nz_ = (X - cx) * dx / (R + 1e-3), (Y - cy) * dx / (R + 1e-3), Zc * dx / (R + 1e-3)
V = P['blastV'] * (core + shell * .8)
u += V * nx_; v += V * ny_; w += V * (nz_ * 1.3 + .25 * core)
T += P['T0'] * core
noise = gaussian_filter(rng.random(sh).astype(f32), 1.5); noise = (noise - noise.min()) / (np.ptp(noise) + 1e-6)
S += P['soot'] * (core * .9 + shell * .4) * (.5 + noise)
D += P['dust'] * (np.exp(-((R - br * .9) / (br * .7)) ** 2) * (Zc * dx < br * 1.6)) * (.4 + noise)
# حلقة غبار أرضية تزحف للخارج
rr = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) * dx
ring = np.exp(-((rr - br * 1.8) / (br * .7)) ** 2) * np.exp(-Zc * dx / 2.0)
D += P['dust'] * .55 * ring * (.3 + noise)
u += ring * 22 * (X - cx) * dx / (rr + 1e-3); v += ring * 22 * (Y - cy) * dx / (rr + 1e-3)

# ---- كتل التراب: مقذوفات بالستية بمخروط، تترك أثراً وتنفث غباراً حين تسقط
nC = P['clods']
az = rng.random(nC) * 2 * np.pi
el = np.radians(rng.uniform(25, 82, nC))
sp = rng.uniform(*P['clodV'], nC) * (1 - .4 * (el > np.radians(70)))
cp = np.stack([np.full(nC, cx * dx) + np.cos(az) * .8, np.full(nC, cy * dx) + np.sin(az) * .8, np.full(nC, .5)], 1).astype(f32)
cv = np.stack([np.cos(az) * np.cos(el) * sp, np.sin(az) * np.cos(el) * sp, np.sin(el) * sp], 1).astype(f32)
csz = rng.uniform(.3, 1, nC).astype(f32)
alive = np.ones(nC, bool)
landed = []   # مواضع سقوط الكتل: تُرسم بقعاً من التراب حول الحفرة

def deposit(F, pos, amt):
    i = np.clip((pos / dx).astype(int), 0, [NX - 1, NX - 1, NZ - 1])
    np.add.at(F, (i[:, 0], i[:, 1], i[:, 2]), amt)

def advect(F, uu, vv, ww, dt, mode='nearest'):
    c = np.stack([X - uu * dt / dx, Y - vv * dt / dx, Z - ww * dt / dx])
    return map_coordinates(F, c, order=1, mode=mode, cval=0).astype(f32)

# حل معادلة بواسون بتحويل جيب التمام (حدود نيومان) — سريع ودقيق
kx = 2 * (np.cos(np.pi * np.arange(NX) / NX) - 1); kz = 2 * (np.cos(np.pi * np.arange(NZ) / NZ) - 1)
LAM = (kx[:, None, None] + kx[None, :, None] + kz[None, None, :]).astype(np.float64); LAM[0, 0, 0] = 1
def project(u, v, w):
    div = (np.gradient(u, axis=0) + np.gradient(v, axis=1) + np.gradient(w, axis=2))
    ph = idctn(dctn(div, type=2, norm='ortho') / LAM, type=2, norm='ortho').astype(f32)
    return u - np.gradient(ph, axis=0), v - np.gradient(ph, axis=1), w - np.gradient(ph, axis=2)

def vorticity(u, v, w, eps, dt):
    gx = lambda F, a: np.gradient(F, axis=a)
    ox = gx(w, 1) - gx(v, 2); oy = gx(u, 2) - gx(w, 0); oz = gx(v, 0) - gx(u, 1)
    mag = np.sqrt(ox * ox + oy * oy + oz * oz)
    Nx, Ny, Nz = gx(mag, 0), gx(mag, 1), gx(mag, 2); n = np.sqrt(Nx * Nx + Ny * Ny + Nz * Nz) + 1e-5
    Nx /= n; Ny /= n; Nz /= n
    return u + eps * (Ny * oz - Nz * oy) * dt / dx, v + eps * (Nz * ox - Nx * oz) * dt / dx, w + eps * (Nx * oy - Ny * ox) * dt / dx

# ---- العرض من فوق: امتصاص وتشتت ضوء الشمس، والسخام أسود والتراب بلون أرض المنطقة
SUN = np.array([.55, .35, .76]); SUN /= np.linalg.norm(SUN)
SOIL = np.array([.60, .51, .40], f32); SOOT = np.array([.13, .12, .11], f32)
def render(S, D, T, cl, tnow):
    up = 2
    s = zoom(S, (up, up, 1), order=1); d = zoom(D, (up, up, 1), order=1); t = zoom(T, (up, up, 1), order=1)
    # تفاصيل دقيقة: ضجيج يكسر نعومة الشبكة
    # تفاصيل «القرنبيط»: ضجيج بطبقتين بحجمين، وحواف أحدّ للكثافة
    n1 = zoom(gaussian_filter(np.random.default_rng(3).random((NX, NX, NZ)).astype(f32), 1.6), (up, up, 1), order=1)
    n2 = gaussian_filter(np.random.default_rng(5).random(s.shape).astype(f32), .9)
    n1 = (n1 - n1.mean()) / (n1.std() + 1e-6); n2 = (n2 - n2.mean()) / (n2.std() + 1e-6)
    det = np.clip(1 + .38 * n1 + .22 * n2, .15, 2.2)
    sig = ((s * 1.6 + d * .75) * det) ** 1.25 * dx            # الكثافة الضوئية لكل خلية
    nz = sig.shape[2]
    # الضوء الواصل لكل خلية من الشمس (إزاحة طبقة بطبقة باتجاه الشمس)
    tau = np.zeros_like(sig); acc = np.zeros(sig.shape[:2], f32)
    ox, oy = -SUN[0] / SUN[2] * up, -SUN[1] / SUN[2] * up
    for z in range(nz - 1, -1, -1):
        tau[:, :, z] = acc
        acc = acc + sig[:, :, z]
        acc = map_coordinates(acc, np.mgrid[0:acc.shape[0], 0:acc.shape[1]].astype(f32) + np.array([ox, oy], f32)[:, None, None], order=1, mode='constant')
    shadow = 1 - np.exp(-acc)                      # ظل السحابة على الأرض
    Ts = np.exp(-tau)
    mixd = d / (s + d + 1e-5)
    alb = SOOT[None, None, None, :] * (1 - mixd[..., None]) + SOIL[None, None, None, :] * mixd[..., None]
    light = (.32 + .95 * Ts)[..., None] * alb
    emit = np.clip(t - 1.2, 0, None)[..., None] * np.array([1.7, .95, .45], f32) * 2.6   # توهج الغاز الحار
    col = np.zeros(sig.shape[:2] + (3,), f32); Tc = np.ones(sig.shape[:2], f32)
    for z in range(nz - 1, -1, -1):
        a = 1 - np.exp(-sig[:, :, z])
        col += (Tc * a)[..., None] * light[:, :, z] + np.sqrt(Tc)[..., None] * emit[:, :, z] * dx
        Tc *= 1 - a
    alpha = 1 - Tc
    # كتل التراب في الجو: نقاط ناعمة داكنة، وظلها على الأرض
    H = col.shape[0]
    for p, sz in cl:
        ci, cj, h = p[0] / dx * up, p[1] / dx * up, p[2] / dx * up
        r = 1.1 + 1.6 * sz
        for (oi, oj, k, tgt) in ((0, 0, .85 * sz + .1, 'c'), (h * SUN[0] / SUN[2], h * SUN[1] / SUN[2], .35 * sz, 's')):
            i0, j0 = ci + oi, cj + oj
            I = slice(max(0, int(i0 - r - 1)), min(H, int(i0 + r + 2))); J = slice(max(0, int(j0 - r - 1)), min(H, int(j0 + r + 2)))
            if I.start >= I.stop or J.start >= J.stop: continue
            gi, gj = np.mgrid[I, J]; m = np.clip(1 - np.hypot(gi - i0, gj - j0) / r, 0, 1) * k
            if tgt == 'c':
                col[I, J] = col[I, J] * (1 - m[..., None]) + np.array([.26, .21, .16]) * m[..., None]; alpha[I, J] = alpha[I, J] + (1 - alpha[I, J]) * m
            else:
                shadow[I, J] = shadow[I, J] + (1 - shadow[I, J]) * m
    # حواف ناعمة حتى لا يُقطع الدخان عند حدود الشبكة
    e = np.clip((np.minimum(np.arange(H), np.arange(H)[::-1]) - H * .03) / (H * .14), 0, 1) ** 1.5
    edge = np.outer(e, e); alpha *= edge; shadow *= edge
    # الوميض: أول أجزاء الثانية، ضوء شديد لا يحجبه الدخان
    fl = np.exp(-tnow / .045)
    if fl > .02:
        fi_ = gaussian_filter(t.sum(2), 2.5); fi_ = fi_ / (fi_.max() + 1e-6)
        k = np.clip(fi_ * 1.6 * fl, 0, 1)
        col = col * (1 - k[..., None]) + np.array([1, .93, .75]) * k[..., None]; alpha = alpha + (1 - alpha) * k
    rgb = col / np.maximum(alpha, 1e-4)[..., None]
    return np.clip(rgb, 0, 1), np.clip(alpha, 0, 1), np.clip(shadow, 0, 1)

out = f"out_{P['name']}"; os.makedirs(out, exist_ok=True)
from PIL import Image
t, fi, times, t0 = 0.0, 0, P['times'], time.time()
meta = []
while fi < len(times):
    vmax = float(max(np.abs(u).max(), np.abs(v).max(), np.abs(w).max(), np.abs(cv).max() if alive.any() else 0)) + 1e-3
    dt = min(.12, 2.0 * dx / vmax, times[fi] - t + 1e-6)
    # قوى: طفو الغاز الحار، وثقل التراب، والريح، واحتكاك الهواء
    w += (P['buoy'] * T - .25 * D) * dt
    u += (P['wind'][0] - u) * .35 * dt; v += (P['wind'][1] * np.clip(Zc * dx / 12, .3, 1) - v) * .35 * dt; w -= w * .25 * dt
    u, v, w = vorticity(u, v, w, P['vort'], dt)
    w[:, :, 0] = np.maximum(w[:, :, 0], 0)
    u, v, w = project(u, v, w)
    u, v, w = advect(u, u, v, w, dt), advect(v, u, v, w, dt), advect(w, u, v, w, dt)
    S = advect(S, u, v, w, dt, 'constant'); T = advect(T, u, v, w, dt, 'constant') * np.exp(-dt / P['Tdecay'])
    D = advect(D, u, v, w - P['settle'], dt, 'constant'); D[:, :, 0] *= np.exp(-dt * 1.5)
    S *= np.exp(-dt / 14); D *= np.exp(-dt / 22)
    # الكتل
    if alive.any():
        cv[alive, 2] -= 9.81 * dt; cv[alive] *= (1 - .02 * dt * np.linalg.norm(cv[alive], axis=1, keepdims=True) / 10)
        cp[alive] += cv[alive] * dt
        deposit(D, cp[alive], (.012 * csz[alive] * dt * 60).astype(f32))
        hit = alive & (cp[:, 2] <= 0)
        if hit.any():
            pts = cp[hit].copy(); pts[:, 2] = .5
            deposit(D, pts, (.25 * csz[hit]).astype(f32)); landed.extend([(float(p[0]), float(p[1]), float(s)) for p, s in zip(cp[hit], csz[hit])])
            alive &= ~hit
    t += dt
    if t >= times[fi] - 1e-4:
        if os.environ.get('DUMP'): np.savez_compressed(f'{out}/vol{fi:02d}.npz', S=S.astype(np.float16), D=D.astype(np.float16), T=T.astype(np.float16), cl=np.array([[*cp[i], csz[i]] for i in np.where(alive)[0]] or np.zeros((0, 4))), dx=dx)
        rgb, a, shd = render(S, D, T, [(cp[i], csz[i]) for i in np.where(alive)[0]], t)
        img = np.dstack([rgb, a]); Image.fromarray((img * 255).astype(np.uint8), 'RGBA').save(f'{out}/f{fi:02d}.png')
        Image.fromarray((shd * 255).astype(np.uint8), 'L').save(f'{out}/s{fi:02d}.png')
        meta.append(round(times[fi], 3)); print(f'frame {fi} t={t:.2f}s  wall={time.time() - t0:.0f}s', flush=True); fi += 1
json.dump({'times': meta, 'size_m': NX * dx, 'px': NX * 2, 'landed': landed, 'P': {k: P[k] for k in P if k != 'times'}}, open(f'{out}/meta.json', 'w'))
print('done', time.time() - t0)
