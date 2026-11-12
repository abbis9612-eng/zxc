// ================================================================== عرض المعركة على كرت الرسوميات (PixiJS 8 / WebGL)
// المحاكاة كما هي (war.js). هذا الملف يرسم العالم فقط: الأرض، والمركبات بحجمها الحقيقي، والمقذوفات، والانفجارات، والدخان.
// الكانفس القديم (#wc) يبقى فوقه شفافاً للعلامات والأسماء واللمس.
(function(){
if (!window.PIXI) return;
const P = PIXI, M2W = 1 / 30;               // متر ← وحدة عالم (كل وحدة عالم 30 متراً)
const PX = window.PXW = {ok: false};
/*__V2META__*/
const VEH = V2META.veh, FX = V2META.fx;
// أي نموذج لكل وحدة
const MODEL = {iq: {qaqaa: 'm1a1', t72: 't72old', bmp1: 'bmp1'}, tr: {leopard2a4: 'leo2a4', altay: 'leo2a4', acv15: 'acv15'}};
// أحجام حقيقية بالأمتار للصور القديمة (أطول بُعد في الصورة)
const REAL = {atgm: 7, mg: 7, mortar: 7, sniper: 6, arty: 11, mlrs: 9, ad: 10, heli: 18, jet: 15, drone: 12, recon: 17, squad: 3.2};   // المشاة مكبّرون قليلاً حتى يُروا (مثل ألعاب الحرب الاحترافية)
// الجسيمات: أحجامها القديمة كانت على مقياس الأيقونات الكبيرة، فنصغّرها للحجم الحقيقي
const PS = {launch_dust: .05, smoke_screen: .04, smoke_oil: .05, dust_trail: .03, smoke_light: .03, intercept: .03};
const PSD = .025;
let R = null, stage, world, L = {}, T = {}, ready = false, gfx, ovGfx;
const TEXC = new WeakMap();
function tex(k){
  const im = (typeof img === 'function') ? img(k) : null; if (!im || !im.complete || !im.width) return null;
  let t = TEXC.get(im); if (!t) { t = P.Texture.from(im); TEXC.set(im, t); } return t;
}
function ctex(cv){ let t = TEXC.get(cv); if (!t) { t = P.Texture.from(cv); TEXC.set(cv, t); } return t; }
// مجمّع صور لكل طبقة: نرسم بأسلوب «فوري» مثل الكانفس، والصور غير المستعملة تُخفى
function pool(name){ const c = new P.Container(); c.label = name; c._i = 0; c._list = []; return c; }
function begin(c){ c._i = 0; }
function end(c){ for (let i = c._i; i < c._list.length; i++) c._list[i].visible = false; }
function put(c, t, x, y, w, h, rot = 0, a = 1, blend = 'normal', tint = 0xffffff, ax = .5, ay = .5){
  if (!t || a <= 0.003) return null;
  let s = c._list[c._i]; if (!s) { s = new P.Sprite(t); c.addChild(s); c._list.push(s); }
  c._i++; s.visible = true; if (s.texture !== t) s.texture = t;
  s.anchor.set(ax, ay); s.position.set(x, y); s.rotation = rot; s.width = w; s.height = h; s.alpha = a; s.blendMode = blend; s.tint = tint;
  return s;
}
// نسيج أرض دقيق يتكرر بلا حواف: رمل بحبيبات وحصى صغيرة وتموج خفيف (512 بكسل = 12 متراً)
function groundTex(){
  const N = 512, cv = document.createElement('canvas'); cv.width = cv.height = N; const x = cv.getContext('2d'), d = x.createImageData(N, N);
  let s = 7; const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647;
  const oct = (g) => { const a = new Float32Array(g * g); for (let i = 0; i < a.length; i++) a[i] = rnd(); return a; };
  const layers = [[8, .35], [32, .3], [128, .2], [512, .15]].map(([g, w]) => [g, w, oct(g)]);
  const sample = (a, g, u, v) => { const X = u * g, Y = v * g, i = Math.floor(X), j = Math.floor(Y), fx = X - i, fy = Y - j, sm = t => t * t * (3 - 2 * t);
    const A = a[(j % g) * g + (i % g)], B = a[(j % g) * g + ((i + 1) % g)], C = a[((j + 1) % g) * g + (i % g)], D = a[((j + 1) % g) * g + ((i + 1) % g)];
    return (A + (B - A) * sm(fx)) * (1 - sm(fy)) + (C + (D - C) * sm(fx)) * sm(fy); };
  for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
    let v = 0; for (const [g, w, a] of layers) v += sample(a, g, i / N, j / N) * w;
    const k = (j * N + i) * 4, b = 228 + (v - .5) * 70;
    d.data[k] = b; d.data[k + 1] = b * .97; d.data[k + 2] = b * .92; d.data[k + 3] = 255;
  }
  x.putImageData(d, 0, 0);
  // حصى صغيرة بظلها
  for (let n = 0; n < 900; n++) { const px = rnd() * N, py = rnd() * N, r = .6 + rnd() * rnd() * 3.2, c = 150 + rnd() * 70;
    for (const [ox, oy] of [[0, 0], [N, 0], [0, N], [-N, 0], [0, -N]]) { x.fillStyle = 'rgba(60,45,30,.35)'; x.beginPath(); x.arc(px + ox + r * .5, py + oy + r * .7, r, 0, 7); x.fill(); x.fillStyle = `rgb(${c},${c * .95},${c * .88})`; x.beginPath(); x.arc(px + ox, py + oy, r, 0, 7); x.fill(); } }
  return cv;
}
// ---------- التهيئة
PX.init = async function(){
  if (ready || PX.busy) return; PX.busy = true;
  const host = document.getElementById('war'), wcv = document.getElementById('wc');
  const cv = document.createElement('canvas'); cv.id = 'wgl';
  cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;z-index:0;display:block;pointer-events:none';
  host.insertBefore(cv, wcv); wcv.style.position = 'relative'; wcv.style.zIndex = 1; wcv.style.background = 'transparent';
  R = await P.autoDetectRenderer({canvas: cv, width: host.clientWidth || 400, height: host.clientHeight || 800, resolution: Math.min(devicePixelRatio || 1, 1.75), autoDensity: true, backgroundColor: 0x1a1712, preference: 'webgl', antialias: false});
  stage = new P.Container(); world = new P.Container(); stage.addChild(world);
  for (const k of ['map', 'detail', 'feat', 'decal', 'shadow', 'unit', 'wreckfx', 'partmid', 'proj', 'fxsh', 'fx', 'air', 'parttop']) {
    L[k] = k === 'detail' ? null : (k === 'feat' ? new P.Graphics() : pool(k));
    if (L[k]) world.addChild(L[k]);
    if (k === 'decal') { gfx = new P.Graphics(); world.addChild(gfx); }
  }
  // نسيج الأرض الدقيق: يظهر عند التقريب فقط
  L.detail = new P.TilingSprite({texture: P.Texture.from(groundTex()), width: 10, height: 10}); L.detail.blendMode = 'multiply'; world.addChildAt(L.detail, 1);
  // صور المركبات والانفجار
  // نحمّل الصور بعنصر صورة عادي (يعمل من ملف محلي أو من الشبكة)
  const load = u => new Promise((ok, bad) => { const im = new Image(); im.onload = () => { const t = P.Texture.from({resource: im, autoGenerateMipmaps: true}); ok(t); }; im.onerror = () => bad(new Error('تعذر تحميل ' + u)); im.src = u; });
  for (const k in VEH) { T[k + '_hull'] = await load(`v2/${k}_hull.webp`); T[k + '_turret'] = await load(`v2/${k}_turret.webp`); }
  const fa = await load('v2/fx_h155.webp'), fs = await load('v2/fx_h155_sh.webp');
  T.fx = []; T.fxs = [];
  for (let i = 0; i < FX.n; i++) { const fr = new P.Rectangle((i % FX.cols) * FX.frame, Math.floor(i / FX.cols) * FX.frame, FX.frame, FX.frame); T.fx.push(new P.Texture({source: fa.source, frame: fr})); T.fxs.push(new P.Texture({source: fs.source, frame: fr})); }
  ovGfx = null; ready = PX.ok = true; PX.busy = false;
  MT.clear();   /* نعيد بناء قطع الخريطة بلا نقش الحبيبات القديم */
  window.ZMAX = 250; ZMAX = 250;
};
// ---------- الانفجارات: تسلسل صور المحاكاة الفيزيائية بدل كرة النار القديمة
const FXL = [];
PX.boom = function(x, y, big){
  // حجم الانفجار حسب العيار: 155 ملم = 1، هاون أصغر، والبالستي أكبر
  const sc = big >= 1.9 ? 1.7 : big >= 1.3 ? 1 : big >= .9 ? .62 : .38;
  FXL.push({x, y, t: 0, sc: sc * (.88 + Math.random() * .24), ts: .9 + Math.random() * .2});
  if (FXL.length > 60) FXL.shift();
};
function drawFX(dt){
  const c = L.fx; begin(c); begin(L.fxsh);
  const tm = FX.times, last = tm[tm.length - 1];
  for (const f of FXL) {
    f.t += dt * f.ts; const t = f.t; if (t > last + 4) continue;
    let a = 0, b = 0, w = 0;
    if (t >= tm[0]) { let j = 1; while (j < tm.length && tm[j] < t) j++; if (j >= tm.length) { a = b = tm.length - 1; } else { a = j - 1; b = j; w = (t - tm[a]) / (tm[b] - tm[a]); } }
    const fade = t > last ? Math.max(0, 1 - (t - last) / 4) : 1, S = FX.size_m * M2W * f.sc * Math.min(12, EX(30, 46));
    for (const [i, al] of [[a, 1 - w], [b, w]]) {
      if (al <= .01) continue;
      put(L.fxsh, T.fxs[i], f.x, f.y, S, S, 0, al * fade * .55, 'normal', 0xffffff, FX.cx, FX.cy);
      put(c, T.fx[i], f.x, f.y, S, S, 0, al * fade, 'normal', 0xffffff, FX.cx, FX.cy);
    }
  }
  end(c); end(L.fxsh);
  while (FXL.length && FXL[0].t > last + 4) FXL.shift();
}
// ---------- الخريطة: نفس قطع الخريطة المبنية، كصور على كرت الرسوميات
function drawMap(cam, Wd, Hd){
  const c = L.map; begin(c); MT_BUDGET = 3;
  const want = cam.k * WDPR, res = Math.pow(2, Math.max(-1, Math.min(4, Math.ceil(Math.log2(want) - .15))));
  const x0 = cam.x - Wd / 2 / cam.k, y0 = cam.y - Hd / 2 / cam.k, x1 = cam.x + Wd / 2 / cam.k, y1 = cam.y + Hd / 2 / cam.k;
  const fs = 512 / res, e = .6 / cam.k;
  for (let j = Math.floor(y0 / fs); j * fs < y1; j++) for (let i = Math.floor(x0 / fs); i * fs < x1; i++) {
    let t = mapTile(res, i, j), fx = i * fs, fy = j * fs, fw = fs;
    if (!t) for (const r2 of [res / 2, res / 4, res / 8]) { const f2 = 512 / r2, i2 = Math.floor(i * fs / f2), j2 = Math.floor(j * fs / f2), t2 = MT.get(r2 + ':' + i2 + ':' + j2); if (t2) { t = t2; fx = i2 * f2; fy = j2 * f2; fw = f2; break; } }
    if (t) put(c, ctex(t), fx - e, fy - e, fw + 2 * e, fw + 2 * e, 0, 1, 'normal', 0xffffff, 0, 0);
  }
  end(c);
  // نسيج الأرض الدقيق: قطعة النسيج = 8 أمتار، ويظهر تدريجياً بعد تقريب ×10
  const d = L.detail, a = Math.max(0, Math.min(.9, (cam.k - 10) / 40));
  d.visible = a > 0; if (d.visible) { d.position.set(x0, y0); d.width = x1 - x0; d.height = y1 - y0; const s = 12 * M2W / d.texture.width; d.tileScale.set(s, s); const tw = d.texture.width, md = v => ((v % tw) + tw) % tw; d.tilePosition.set(md(-x0 / s), md(-y0 / s));   /* باقي القسمة: أرقام صغيرة تحفظ دقة كرت الرسوميات */ d.alpha = a; }
}
// المباني والطرق والأشجار حادة عند التقريب الكبير (أدق من قطع الخريطة)
function drawFeat(cam, Wd, Hd){
  const g = L.feat; g.clear(); if (cam.k < 14) return;
  const x0 = cam.x - Wd / 2 / cam.k - 2, y0 = cam.y - Hd / 2 / cam.k - 2, x1 = cam.x + Wd / 2 / cam.k + 2, y1 = cam.y + Hd / 2 / cam.k + 2, lw = 1 / cam.k;
  for (const r of MAP2D.roads) {
    if (r.bb[2] < x0 || r.bb[0] > x1 || r.bb[3] < y0 || r.bb[1] > y1) continue;
    const w = r.w * FEAT.road; g.moveTo(r.p[0][0], r.p[0][1]); for (let i = 1; i < r.p.length; i++) g.lineTo(r.p[i][0], r.p[i][1]);
    g.stroke({width: w + 3 * lw, color: 0x6e5f4a, alpha: .45, cap: 'round', join: 'round'});
    g.moveTo(r.p[0][0], r.p[0][1]); for (let i = 1; i < r.p.length; i++) g.lineTo(r.p[i][0], r.p[i][1]);
    g.stroke({width: w, color: r.town ? 0xcfc6b4 : r.w > 2 ? 0x8f8a80 : 0xd8cbab, alpha: 1, cap: 'round', join: 'round'});
  }
  const cx0 = Math.floor(x0 / MCELL), cx1 = Math.floor(x1 / MCELL), cy0 = Math.floor(y0 / MCELL), cy1 = Math.floor(y1 / MCELL);
  const each = (kind, f) => { for (let cy = cy0; cy <= cy1; cy++) for (let cx = cx0; cx <= cx1; cx++) { const a = MGRID.get(kind + cx + ',' + cy); if (a) for (const o of a) if (o[0] > x0 && o[0] < x1 && o[1] > y0 && o[1] < y1) f(o); } };
  const rect = (x, y, w, h, r) => { const c = Math.cos(r), s = Math.sin(r), pts = []; for (const [a, b] of [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]]) pts.push(x + a * c - b * s, y + a * s + b * c); return pts; };
  const RC = [0xcdc3ad, 0xb9b2a4, 0xd9d4c8, 0xa8846a, 0xc2ab88];
  each('walls', wl => { g.poly(rect(wl[0], wl[1], wl[2] * FEAT.wall, wl[3] * FEAT.wall, wl[4])).stroke({width: .3 * M2W, color: 0x786854, alpha: .9}); });
  each('houses', h => { const w = h[2] * FEAT.house, l = h[3] * FEAT.house, sh = 3.5 * M2W; g.poly(rect(h[0] + sh * .54, h[1] + sh * .84, w, l, h[4])).fill({color: 0x281e14, alpha: .35}); });
  each('houses', h => {
    const w = h[2] * FEAT.house, l = h[3] * FEAT.house;
    g.poly(rect(h[0], h[1], w, l, h[4])).fill({color: RC[h[5]]}).stroke({width: Math.max(.08 * M2W, .8 * lw), color: 0x463a2c, alpha: .8});
    g.poly(rect(h[0], h[1], w - .5 * M2W, l - .5 * M2W, h[4])).stroke({width: .25 * M2W, color: 0xffffff, alpha: .3});   // حاجز السطح
    if (h[5] !== 3) g.circle(h[0] + Math.cos(h[4]) * w * .2, h[1] + Math.sin(h[4]) * w * .2, .6 * M2W).fill({color: 0x3c3c3c, alpha: .6});   // خزان ماء
  });
  each('trees', t => { const r = t[2] * FEAT.tree; g.circle(t[0] + r * .5, t[1] + r * .75, r).fill({color: 0x281e14, alpha: .3}); g.circle(t[0], t[1], r).fill({color: 0x4c5a32}); g.circle(t[0] - r * .3, t[1] - r * .3, r * .55).fill({color: 0x6f8048, alpha: .8}); });
}
// ---------- الوحدات بحجمها الحقيقي
const SUNX = .54, SUNY = .84;     // اتجاه الظل (الشمس من الشمال الغربي، ارتفاع 50°)
const FORM = [[0, 0], [-55, -45], [55, -45]];   // فصيل الدبابات: إسفين، بالأمتار (يمين، أمام)
const SQ = [[-30, 0], [-21, 6], [-12, -3], [-4, 5], [5, -4], [13, 5], [22, -2], [31, 4]];   // فصيل المشاة: خط متباعد
const WRECKS = [];
let CAMK = 1;
const EX = (m, px) => Math.max(1, px / (m * M2W * CAMK));   // كم نكبّر حتى يبقى المجسم مرئياً
function unitN(u, n){ const d = UT[u.t]; return u.dead ? 0 : Math.max(1, Math.ceil(n * u.hp / d.hp - 1e-6)); }
function vehAt(u, i, list){ const [r, f] = list[i], c = Math.cos(u.ang), s = Math.sin(u.ang); return {x: u.x + (c * f - s * r) * M2W, y: u.y + (s * f + c * r) * M2W}; }
function drawVehicle(m, x, y, ang, ta, recoil, burnt, ex = 1){
  const V = VEH[m], S = 256 * V.mpp * M2W * ex, ox = (V.px - 128) * V.mpp * M2W * ex, oy = (V.py - 128) * V.mpp * M2W * ex;
  const tint = burnt ? 0x3a3430 : 0xffffff;
  put(L.unit, T[m + '_hull'], x, y, S, S, ang + Math.PI / 2, 1, 'normal', tint);
  // البرج يدور حول حلقته؛ ظله على البدن والأرض
  const c = Math.cos(ang + Math.PI / 2), s = Math.sin(ang + Math.PI / 2), rx = x + c * ox - s * oy, ry = y + s * ox + c * oy;
  const tp = (V.px) / 256, tq = (V.py) / 256, rec = (recoil || 0) * .4 * M2W;
  const tr = ta + Math.PI / 2, bx = rx - Math.sin(ta + Math.PI / 2) * -rec, by = ry + Math.cos(ta + Math.PI / 2) * -rec;
  put(L.unit, T[m + '_turret'], bx + 1.1 * M2W * ex * SUNX, by + 1.1 * M2W * ex * SUNY, S, S, tr, .32, 'normal', 0x000000, tp, tq);
  put(L.unit, T[m + '_turret'], bx, by, S, S, tr, 1, 'normal', tint, tp, tq);
}
function drawUnits(cam){
  CAMK = cam.k;
  begin(L.unit); begin(L.air); begin(L.wreckfx);
  const vis = (x, y, m = 2) => Math.abs(x - cam.x) * cam.k < innerWidth / 2 + m * cam.k + 40 && Math.abs(y - cam.y) * cam.k < innerHeight / 2 + m * cam.k + 40;
  for (const w of WRECKS) if (vis(w.x, w.y)) drawVehicle(w.m, w.x, w.y, w.ang, w.ta, 0, true, EX(VEH[w.m].len, 22));
  for (const u of W.units) {
    if (u.gone || UT[u.t].air) continue;
    const d = UT[u.t], m = (MODEL[u.side] || {})[u.spr];
    if (m && (u.t === 'tank' || u.t === 'ifv')) {
      const n = unitN(u, 3); u.vn = u.vn ?? 3;
      // مركبة خرجت من القتال: تبقى حطاماً محترقاً مكانها
      while (u.vn > n) { u.vn--; const p = vehAt(u, u.vn, FORM); WRECKS.push({m, x: p.x, y: p.y, ang: u.ang, ta: u.ta + (Math.random() - .5), t: W.t}); PX.boom(p.x, p.y, .5); if (WRECKS.length > 80) WRECKS.shift(); }
      const ex = EX(VEH[m].len, 38);
      if (ex > 2.5) { if (n && vis(u.x, u.y)) drawVehicle(m, u.x, u.y, u.ang, u.ta, u.recoil, false, ex); }   // من بعيد: مركبة واحدة مكبّرة تمثل الفصيل
      else for (let i = 0; i < n; i++) { const p = vehAt(u, i, FORM); if (vis(p.x, p.y)) drawVehicle(m, p.x, p.y, u.ang, u.ta, i === 0 ? u.recoil : 0, false, ex); }
      continue;
    }
    if (u.dead || !vis(u.x, u.y)) continue;
    if (u.t === 'squad' && EX(30, 40) > 2.5) {   // من بعيد: صورة الفصيل كاملة
      const t = tex(u.spr), S = 30 * M2W * EX(30, 40); if (t) { put(L.unit, t, u.x + S * .05, u.y + S * .07, S, S, u.ang + Math.PI / 2, .3, 'normal', 0); put(L.unit, t, u.x, u.y, (u.prone || u.sup > 55) ? S * .86 : S, (u.prone || u.sup > 55) ? S * .86 : S, u.ang + Math.PI / 2); }
      continue;
    }
    if (u.t === 'squad') {
      const n = unitN(u, 8), k = u.prone || u.sup > 55 ? 'prone' : (u.side === 'tr' ? 'soldier_tr' : 'soldier'), t = tex(k) || tex('soldier');
      const S = REAL.squad * M2W * (k === 'prone' ? 1.25 : 1);
      for (let i = 0; i < n; i++) { const p = vehAt(u, i, SQ); put(L.unit, t, p.x + .25 * M2W * SUNX, p.y + .25 * M2W * SUNY, S, S, u.ang + Math.PI / 2, .3, 'normal', 0); put(L.unit, t, p.x, p.y, S, S, u.ang + Math.PI / 2); }
      continue;
    }
    const t = tex(u.spr); if (!t) continue;
    const S = (REAL[u.t] || 8) * M2W * EX(REAL[u.t] || 8, 34), ar = t.width / t.height, w = ar >= 1 ? S : S * ar, h = ar >= 1 ? S / ar : S;
    put(L.unit, t, u.x + S * .1 * SUNX, u.y + S * .1 * SUNY, w, h, u.ang + Math.PI / 2, .35, 'normal', 0);
    put(L.unit, t, u.x, u.y, w, h, u.ang + Math.PI / 2, u.retreat ? .85 : 1);
  }
  // الطائرات والمروحيات: ظلها على الأرض يبتعد بارتفاعها
  for (const u of W.units) {
    if ((u.dead && !(u.falling > 0)) || u.gone || !UT[u.t].air) continue;
    const t = tex(u.spr); if (!t) continue;
    const S = (REAL[u.t] || 14) * M2W * EX(REAL[u.t] || 14, 44), ar = t.width / t.height, w = ar >= 1 ? S : S * ar, h = ar >= 1 ? S / ar : S, alt = u.alt * 1.2 * M2W * 30 / 30;
    put(L.air, t, u.x + alt * SUNX * 0.6, u.y + alt * SUNY * 0.6, w, h, u.ang + Math.PI / 2, .25, 'normal', 0);
    put(L.air, t, u.x, u.y, w, h, u.ang + Math.PI / 2);
  }
  end(L.unit); end(L.air); end(L.wreckfx);
}
// ---------- الحطام والحفر والسواتر بحجمها الحقيقي
const PROPS = {trench: .1, sandbags: .1, checkpoint: .1, twall: .1, depot: .1, hospital: .1, shed: .1, berm: .1};
function drawDecals(cam){
  const c = L.decal; begin(c); gfx.clear();
  for (const p of W.props) { const t = tex(p.k); if (!t) continue; const S = p.s * (PROPS[p.k] || .1), ar = t.width / t.height; put(c, t, p.x, p.y, ar >= 1 ? S : S * ar, ar >= 1 ? S / ar : S, p.rot); }
  for (const d of W.decals) { if (d.k === 'hulk') continue; const t = tex(d.k); if (!t) continue; const S = d.s * .02; put(c, t, d.x, d.y, S, S, d.rot, Math.min(1, (d.a || .5) * 1.4)); }
  end(c);
}
// ---------- المقذوفات: قذائف الدبابات والمدفعية لا تُرى في الجو، فقط نقطة التتبّع والصواريخ
function drawProj(cam){
  const c = L.proj; begin(c); const g = PX.pg || (PX.pg = (() => { const x = new P.Graphics(); x.blendMode = 'add'; world.addChildAt(x, world.getChildIndex(L.proj) + 1); return x; })()); g.clear();
  for (const p of W.proj) {
    if (p.t < 0 || p.done) continue;
    const q = projPos(p), x = q.x, y = q.y;
    if (p.k === 'tracer' || p.k === 'shell') {
      const r = Math.hypot(p.x1 - p.x0, p.y1 - p.y0) || 1, ux = (p.x1 - p.x0) / r, uy = (p.y1 - p.y0) / r;
      const Lm = Math.min((p.k === 'shell' ? 30 : 18) * M2W, 26 / cam.k), wdt = 1.3 / cam.k;
      const col = p.k === 'shell' ? 0xfff2d0 : p.side === 'iq' ? 0xffd27a : 0xff9a7a;
      g.moveTo(x - ux * Lm, y - uy * Lm).lineTo(x, y).stroke({width: wdt, color: col, alpha: .9, cap: 'round'});
    } else if (p.k === 'arty' || p.k === 'bullet') {
    } else {
      const kp = Math.max(0, q.k - .02), px = p.x0 + (p.x1 - p.x0) * kp, py = p.y0 + (p.y1 - p.y0) * kp;
      const ang = Math.atan2(y - py, x - px) || Math.atan2(p.y1 - p.y0, p.x1 - p.x0);
      const key = {atgm: 'm_atgm', hrkt: 'm_rkt', rkt: 'm_rkt', bm: 'm_bm', agm: 'm_ag', int: 'm_rkt'}[p.k];
      const size = {atgm: 3.5, hrkt: 2.5, rkt: 3.2, bm: 8, agm: 4, int: 3.5}[p.k] * M2W;
      const burning = p.k === 'agm' ? p.t >= p.drop : p.k === 'rkt' ? q.k < .5 : p.k === 'bm' ? q.k < .7 : true;
      const S = Math.max(size * (1 + q.alt / 420), 7 / cam.k), bx = x - Math.cos(ang) * S * .55, by = y - Math.sin(ang) * S * .55;
      if (burning) { const lx = p.lx ?? bx, ly = p.ly ?? by, n = Math.min(4, 1 + Math.ceil(Math.hypot(bx - lx, by - ly) / (S * .6))); for (let i = 0; i < n; i++) wp('smoke_light', lx + (bx - lx) * i / n, ly + (by - ly) * i / n, {s0: S * 30 * .6, s1: S * 30 * (p.k === 'bm' ? 3 : 2), a0: .45, life: p.k === 'bm' || p.k === 'rkt' ? 4 : 2, vx: 1, vy: -.6, layer: 'top'}); } p.lx = bx; p.ly = by;
      const t = tex(key);
      if (q.alt > 1) put(c, t, x + q.alt * .02 * SUNX, y + q.alt * .02 * SUNY, S, S, ang + Math.PI / 2, .2, 'normal', 0);
      put(c, t, x, y, S, S, ang + Math.PI / 2);
      if (burning) { put(c, tex('exhaust'), bx - Math.cos(ang) * S * .2, by - Math.sin(ang) * S * .2, S * 1.2, S * 1.2, ang - Math.PI / 2, 1, 'add'); put(c, tex('flare'), bx, by, S * .9, S * .9, 0, .8, 'add'); }
    }
  }
  end(c);
}
// ---------- الجسيمات (نفس نظامها القديم، بأحجام حقيقية)
const ADDP = {fireball: 1, sparks: 1, muzzle: 1, exhaust: 1, intercept: 1, tracers: 1, ground_fire: 1, rifle_flash: 1, vehicle_fire: 1, flare: 1, armor_sparks: 1, tank_fire: 1};
function drawParts(dt, layer, cam){
  const c = layer === 'mid' ? L.partmid : L.parttop; begin(c);
  const vw = innerWidth / 2 / cam.k, vh = innerHeight / 2 / cam.k;
  for (const p of W.parts) {
    if (p.layer !== layer) continue;
    if (p.delay > 0) { p.delay -= dt; continue; }
    p.t += dt; const k = p.t / p.life; if (k >= 1) continue;
    const e = 1 - Math.pow(1 - k, 2); p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.vr * dt;
    const sz = p.s0 + (p.s1 - p.s0) * e, al = p.a0 + (p.a1 - p.a0) * k;
    if (al <= 0 || Math.abs(p.x - cam.x) > vw + sz || Math.abs(p.y - cam.y) > vh + sz) continue;
    const G = Math.min(30, EX(10, 38)); put(c, tex(p.img), p.x, p.y, sz * G, sz * G, p.rot, Math.min(1, al), ADDP[p.img] ? 'add' : 'normal');
  }
  end(c);
  if (layer === 'top') W.parts = W.parts.filter(p => p.delay > 0 || p.t < p.life);
}
// ---------- طبقة العلامات فوق العالم (الكانفس القديم، شفاف)
function drawOverlay(dt){
  const c = wctx, cv = wc(), Wd = cv.clientWidth, Hd = cv.clientHeight, cam = W.cam;
  c.setTransform(WDPR, 0, 0, WDPR, 0, 0); c.clearRect(0, 0, Wd, Hd);
  const sx = x => (x - cam.x) * cam.k + Wd / 2, sy = y => (y - cam.y) * cam.k + Hd / 2;
  const ia = 0;   // الرموز العسكرية بزر ⌗ فقط؛ العرض العادي مجسمات
  for (const u of W.units) {
    if (u.dead || u.gone || u.t === 'jet' || u.t === 'drone' || u.t === 'recon') continue;
    const x = sx(u.x), y = sy(u.y); if (x < -30 || x > Wd + 30 || y < -30 || y > Hd + 30) continue;
    const d = UT[u.t], selected = W.sel && W.sel.includes(u.id);
    if (ia > 0) c2Symbol(c, u, x, y, ia * (u.retreat ? .7 : .95));
    else { c.fillStyle = u.side === 'iq' ? '#e2b04f' : '#d0473b'; c.strokeStyle = 'rgba(0,0,0,.6)'; c.lineWidth = 1; c.beginPath(); c.arc(x - 16, y - 16, 3, 0, 7); c.fill(); c.stroke(); }
    if (selected) { c.strokeStyle = 'rgba(255,230,150,.95)'; c.lineWidth = 1.6; c.beginPath(); c.arc(x, y, Math.max(18, 70 * M2W * cam.k), 0, 7); c.stroke();
      if (u.manual) { const f = u.focus && W.units.find(v => v.id === u.focus && !v.dead), g = f || u.manual; c.setLineDash([4, 4]); c.strokeStyle = f ? 'rgba(230,90,70,.9)' : 'rgba(255,230,150,.7)'; c.beginPath(); c.moveTo(x, y); c.lineTo(sx(g.x), sy(g.y)); c.stroke(); c.setLineDash([]); } }
    if (u.hp < d.hp || selected) { const bw = 18, yy = y + Math.max(16, 60 * M2W * cam.k); c.fillStyle = 'rgba(0,0,0,.65)'; c.fillRect(x - bw / 2 - 1, yy, bw + 2, 4); c.fillStyle = u.hp > d.hp * .5 ? '#5fae7b' : '#d4574a'; c.fillRect(x - bw / 2, yy + 1, bw * u.hp / d.hp, 2); }
  }
  c.font = '700 13px "IBM Plex Sans Arabic", sans-serif'; c.textAlign = 'center'; c.direction = 'rtl';
  for (const tw of TOWNS) {
    const x = sx(tw.x), y0 = sy(tw.y); if (x < -60 || x > Wd + 60 || y0 < -40 || y0 > Hd + 40) continue;
    const y = y0 - tw.r * cam.k - 8;
    c.lineWidth = 4; c.strokeStyle = 'rgba(5,9,13,.85)'; c.fillStyle = '#f3ede0'; c.strokeText(tw.n, x, y); c.fillText(tw.n, x, y);
    if (tw.obj) { const v = W.ctl[tw.id] / 100; c.fillStyle = 'rgba(5,9,13,.85)'; c.fillRect(x - 26, y + 5, 52, 7); c.fillStyle = '#c0473b'; c.fillRect(x - 25, y + 6, 50, 5); c.fillStyle = '#d2a24c'; c.fillRect(x - 25, y + 6, 50 * v, 5); }
  }
  // مسطرة المقياس
  const m = cam.k < 3 ? 1000 : cam.k < 12 ? 200 : cam.k < 40 ? 50 : 10, L_ = m * M2W * cam.k;
  c.fillStyle = 'rgba(5,9,13,.6)'; c.fillRect(12, Hd * .38 - 22, L_ + 16, 22); c.fillStyle = '#f3ede0'; c.fillRect(20, Hd * .38 - 8, L_, 2); c.font = '600 11px sans-serif'; c.textAlign = 'left'; c.direction = 'ltr'; c.fillText(m >= 1000 ? m / 1000 + ' km' : m + ' m', 20, Hd * .38 - 11);
}
// ---------- الرسم الكامل لكل إطار
PX.draw = function(dt){
  if (!ready) { drawWar(dt); return; }
  const host = document.getElementById('war'), Wd = host.clientWidth, Hd = host.clientHeight, cam = W.cam;
  if (R.width !== Math.round(Wd * R.resolution) || R.height !== Math.round(Hd * R.resolution)) R.resize(Wd, Hd);
  if (W.follow) { const f = W.units.filter(u => u.side === 'iq' && ground(u) && (u.t === 'tank' || u.t === 'ifv' || u.t === 'squad')); if (f.length) { const ty = Math.min(...f.map(u => u.y)) + 70, tx = f.reduce((s, u) => s + u.x, 0) / f.length; cam.x += (tx - cam.x) * Math.min(1, dt * .8); cam.y += (ty - cam.y) * Math.min(1, dt * .8); } }
  world.scale.set(cam.k); world.position.set(Wd / 2 - cam.x * cam.k, Hd / 2 - cam.y * cam.k);
  drawMap(cam, Wd, Hd); drawFeat(cam, Wd, Hd); drawDecals(cam);
  drawParts(dt, 'mid', cam); drawUnits(cam); drawProj(cam); drawFX(dt); drawParts(dt, 'top', cam);
  R.render(stage);
  drawOverlay(dt);
};
PX.show = on => { const cv = document.getElementById('wgl'); if (cv) cv.style.display = on ? 'block' : 'none'; };
})();
