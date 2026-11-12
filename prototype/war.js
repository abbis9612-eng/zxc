// ================================================================== معركة دهوك: محاكاة قتال على أرض حقيقية
// الإحداثيات بكسلات صورة الأرض (كل بكسل نحو 30 متراً). الزمن ثوانٍ من زمن المعركة (300 ثانية = 5 دقائق بسرعة ×1).
// أحجام الوحدات مكبّرة عن الحقيقة حتى تُرى، لكن المسافات بينها حقيقية: الدبابة ترمي من 2-2.5 كم، والطائرة تطلق من 12 كم.
const W_IMG = new Image(); W_IMG.src = FIELD_IMG;          // صورة القمر الصناعي للمنطقة كلها (Sentinel-2)
// صورة القمر عالية الدقة مقسومة 48 قطعة، تُحمَّل القطعة فقط حين تظهر، ونحتفظ بآخر 20 قطعة
const TILE = 256, TILES = new Map();
const MCELL = 32, MGRID = new Map();
for (const k of ['houses', 'trees', 'walls']) for (const o of MAP2D[k]) { const key = k + ((o[0] / MCELL) | 0) + ',' + ((o[1] / MCELL) | 0); let a = MGRID.get(key); if (!a) MGRID.set(key, a = []); a.push(o); }
const ROOF = ['#cdc3ad', '#b9b2a4', '#d9d4c8', '#a8846a', '#c2ab88'];
for (const r of MAP2D.roads) { let a = 1e9, b = 1e9, c = -1e9, d = -1e9; for (const p of r.p) { a = Math.min(a, p[0]); b = Math.min(b, p[1]); c = Math.max(c, p[0]); d = Math.max(d, p[1]); } r.bb = [a, b, c, d]; }
for (const m of MAP2D.mosques) { const key = 'mosques' + ((m[0] / MCELL) | 0) + ',' + ((m[1] / MCELL) | 0); let a = MGRID.get(key); if (!a) MGRID.set(key, a = []); a.push(m); }
// حبيبات أرض ناعمة تُرسم فوق الأرضية عند التقريب (نقش يتكرر، رسمة واحدة)
const GRAIN = (() => { const c = document.createElement('canvas'); c.width = c.height = 128; const x = c.getContext('2d'), d = x.createImageData(128, 128); let s = 9; const r = () => (s = (s * 16807) % 2147483647) / 2147483647; for (let i = 0; i < d.data.length; i += 4) { const v = r(), big = r() < .03; const g = big ? 0 : v < .5 ? 0 : 255; d.data[i] = d.data[i + 1] = d.data[i + 2] = g; d.data[i + 3] = big ? 70 : Math.abs(v - .5) * 70; } x.putImageData(d, 0, 0); return c; })();
let GRAINP = null;
// الطرق والمباني والأشجار: مرسومة بخطوط حادة فوق الأرضية، تبقى واضحة مهما قرّبت
// ---------- الخريطة كقطع جاهزة: كل قطعة 512 بكسل تُرسم مرة واحدة بدقة تناسب التقريب، ثم تُلصق كل إطار
const MT = new Map(); let MT_BUDGET = 0;
function mapTile(res, i, j){
  const key = res + ':' + i + ':' + j; let t = MT.get(key);
  if (t) { MT.delete(key); MT.set(key, t); return t; }
  if (MT_BUDGET <= 0) return null;
  const fs = 512 / res, x0 = i * fs, y0 = j * fs, x1 = x0 + fs, y1 = y0 + fs;
  // صور الأرضية المطلوبة يجب أن تكون محمّلة قبل بناء القطعة
  if (!W_IMG.complete) return null;
  const [bx, by, bw, bh] = SAT_BOX, need = [];
  if (res > 1 && x1 > bx && x0 < bx + bw && y1 > by && y0 < by + bh) for (let tj = Math.floor((Math.max(y0, by) - by) / TILE); tj * TILE < Math.min(y1, by + bh) - by; tj++) for (let ti = Math.floor((Math.max(x0, bx) - bx) / TILE); ti * TILE < Math.min(x1, bx + bw) - bx; ti++) { const s = satTile(ti, tj); if (!s) return null; need.push([ti, tj, s]); }
  MT_BUDGET--;
  const cv = document.createElement('canvas'); cv.width = cv.height = 512; const c = cv.getContext('2d');
  c.setTransform(res, 0, 0, res, -x0 * res, -y0 * res);
  c.fillStyle = '#b9ad8f'; c.fillRect(x0, y0, fs, fs);
  const cx0 = Math.max(0, x0), cy0 = Math.max(0, y0), cx1 = Math.min(FIELD.w, x1), cy1 = Math.min(FIELD.h, y1);
  if (cx1 > cx0 && cy1 > cy0) c.drawImage(W_IMG, cx0, cy0, cx1 - cx0, cy1 - cy0, cx0, cy0, cx1 - cx0, cy1 - cy0);
  for (const [ti, tj, s] of need) c.drawImage(s, bx + ti * TILE, by + tj * TILE, s.width / 2, s.height / 2);
  drawMapFeatures(c, {k: res / WDPR}, x0 - 4, y0 - 4, x1 + 4, y1 + 4);
  MT.set(key, cv); if (MT.size > 56) MT.delete(MT.keys().next().value);
  return cv;
}
function drawMapTiles(c, cam, Wd, Hd){
  MT_BUDGET = 3;
  const want = cam.k * WDPR, res = Math.pow(2, Math.max(-1, Math.min(4, Math.ceil(Math.log2(want) - .15))));
  const x0 = cam.x - Wd / 2 / cam.k, y0 = cam.y - Hd / 2 / cam.k, x1 = cam.x + Wd / 2 / cam.k, y1 = cam.y + Hd / 2 / cam.k;
  const fs = 512 / res, e = .6 / cam.k;
  for (let j = Math.floor(y0 / fs); j * fs < y1; j++) for (let i = Math.floor(x0 / fs); i * fs < x1; i++) {
    let t = mapTile(res, i, j);
    if (t) { c.drawImage(t, i * fs - e, j * fs - e, fs + 2 * e, fs + 2 * e); continue; }
    // القطعة لم تُبنَ بعد: نستعمل قطعة أخشن موجودة، أو الأرضية الخام
    let done = false;
    for (const r2 of [res / 2, res / 4, res * 2]) { const f2 = 512 / r2, i2 = Math.floor(i * fs / f2), j2 = Math.floor(j * fs / f2), t2 = MT.get(r2 + ':' + i2 + ':' + j2); if (t2) { const sx = (i * fs - i2 * f2) * r2, sy = (j * fs - j2 * f2) * r2, sw = fs * r2; c.drawImage(t2, sx, sy, Math.min(512, sw), Math.min(512, sw), i * fs - e, j * fs - e, fs + 2 * e, fs + 2 * e); done = true; break; } }
    if (!done && W_IMG.complete) { const a = Math.max(0, i * fs), b = Math.max(0, j * fs), cc = Math.min(FIELD.w, (i + 1) * fs), d = Math.min(FIELD.h, (j + 1) * fs); if (cc > a && d > b) c.drawImage(W_IMG, a, b, cc - a, d - b, a, b, cc - a, d - b); }
  }
}
function drawMapFeatures(c, cam, x0, y0, x1, y1){
  const k = cam.k, lw = 1 / k;
  // الطرق: حافة داكنة ثم سطح ترابي فاتح
  if (k > 1.6) { const GP = c.createPattern(GRAIN, 'repeat'); GP.setTransform(new DOMMatrix().scale(10 / 128)); c.globalAlpha = Math.min(.9, (k - 1.6) * .5); c.fillStyle = GP; c.fillRect(x0, y0, x1 - x0, y1 - y0); c.globalAlpha = 1; }
  c.lineCap = 'round'; c.lineJoin = 'round';
  for (const pass of [0, 1]) for (const r of MAP2D.roads) {
    if (r.bb[2] < x0 || r.bb[0] > x1 || r.bb[3] < y0 || r.bb[1] > y1 || (r.town && k < .9)) continue;
    const w = r.w * (k < 1 ? 1.4 : 1);
    if (pass === 0) { c.strokeStyle = r.town ? 'rgba(110,98,82,.35)' : 'rgba(92,78,58,.55)'; c.lineWidth = w + 1.2 * lw * 2; } else { c.strokeStyle = r.town ? '#cfc6b4' : r.w > 2 ? '#e2d6b8' : '#d8cbab'; c.lineWidth = w; }
    c.beginPath(); r.p.forEach((p, i) => i ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1])); c.stroke();
  }
  if (k > 1.2) { c.setLineDash([1.2, 1.6]); c.strokeStyle = 'rgba(255,255,255,.55)'; c.lineWidth = .18; for (const r of MAP2D.roads) if (r.w > 2) { c.beginPath(); r.p.forEach((p, i) => i ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1])); c.stroke(); } c.setLineDash([]); }
  const cx0 = Math.floor(x0 / MCELL), cx1 = Math.floor(x1 / MCELL), cy0 = Math.floor(y0 / MCELL), cy1 = Math.floor(y1 / MCELL);
  const each = (kind, f) => { for (let cy = cy0; cy <= cy1; cy++) for (let cx = cx0; cx <= cx1; cx++) { const a = MGRID.get(kind + cx + ',' + cy); if (a) for (const o of a) f(o); } };
  // ظلال المباني والأشجار أولاً (الشمس من الشمال الغربي)
  c.fillStyle = 'rgba(40,30,20,.32)';
  each('houses', h => { c.save(); c.translate(h[0] + .22, h[1] + .28); c.rotate(h[4]); c.fillRect(-h[2] / 2, -h[3] / 2, h[2], h[3]); c.restore(); });
  if (k > .9) each('trees', t => { c.beginPath(); c.arc(t[0] + t[2] * .55, t[1] + t[2] * .7, t[2], 0, 7); c.fill(); });
  // أسوار الأفنية
  if (k > 1.4) { c.strokeStyle = 'rgba(120,104,84,.9)'; c.lineWidth = .12; each('walls', wl => { c.save(); c.translate(wl[0], wl[1]); c.rotate(wl[4]); c.strokeRect(-wl[2] / 2, -wl[3] / 2, wl[2], wl[3]); c.restore(); }); }
  // السطوح: لون السطح، وحافة داكنة، وحاجز سطح فاتح من الداخل
  each('houses', h => {
    c.save(); c.translate(h[0], h[1]); c.rotate(h[4]); const w = h[2], l = h[3];
    c.fillStyle = ROOF[h[5]]; c.fillRect(-w / 2, -l / 2, w, l);
    if (k > 1.8) { c.strokeStyle = 'rgba(255,255,255,.35)'; c.lineWidth = .06; c.strokeRect(-w / 2 + .07, -l / 2 + .07, w - .14, l - .14); if (h[5] !== 3) { c.fillStyle = 'rgba(60,60,60,.45)'; c.fillRect(w * .12, -l * .3, w * .16, w * .16); } }
    c.strokeStyle = 'rgba(70,58,44,.75)'; c.lineWidth = Math.max(.05, .8 * lw); c.strokeRect(-w / 2, -l / 2, w, l);
    c.restore();
  });
  // الجوامع: بناء مربع بقبة ومئذنة
  each('mosques', m => { c.save(); c.translate(m[0], m[1]); c.rotate(m[2]); c.fillStyle = 'rgba(40,30,20,.32)'; c.fillRect(-1.1, -1.1, 2.6, 2.6); c.fillStyle = '#e6dfcf'; c.fillRect(-1.3, -1.3, 2.6, 2.6); c.strokeStyle = 'rgba(70,58,44,.75)'; c.lineWidth = Math.max(.05, .8 * lw); c.strokeRect(-1.3, -1.3, 2.6, 2.6);
    const g = c.createRadialGradient(-.3, -.3, .1, 0, 0, .9); g.addColorStop(0, '#9fd1c9'); g.addColorStop(1, '#3f7f78'); c.fillStyle = g; c.beginPath(); c.arc(0, 0, .85, 0, 7); c.fill(); c.fillStyle = '#f2ece0'; c.beginPath(); c.arc(1.05, -1.05, .28, 0, 7); c.fill(); c.stroke(); c.restore(); });
  // الأشجار: تاج أخضر داكن بلمعة من جهة الشمس
  if (k > .9) each('trees', t => { const g = c.createRadialGradient(t[0] - t[2] * .35, t[1] - t[2] * .35, 0, t[0], t[1], t[2]); g.addColorStop(0, '#7d8f4f'); g.addColorStop(1, '#3f4f2a'); c.fillStyle = g; c.beginPath(); c.arc(t[0], t[1], t[2], 0, 7); c.fill(); });
}
function satTile(i, j){
  const k = i + ',' + j; let t = TILES.get(k);
  if (t) { TILES.delete(k); TILES.set(k, t); return t.complete ? t : null; }
  if (!SAT_TILES[j] || !SAT_TILES[j][i]) return null;
  t = new Image(); t.src = SAT_TILES[j][i]; TILES.set(k, t);
  if (TILES.size > 20) { const old = TILES.keys().next().value; TILES.get(old).src = ''; TILES.delete(old); }
  return null;
}
// تفاصيل الأرض عند التقريب: نسيجان يتكرران (رسمتان لكل إطار)
const DET = new Image(); DET.src = GROUND.tex.dirt; const DET2 = new Image(); DET2.src = GROUND.tex.rock; let DETP = null, DETP2 = null;
// ارتفاعات منطقة القتال بدقة 120 م (بدل 250 م)
const HG = (() => { const b = Uint8Array.from(atob(HGRID.H), c => c.charCodeAt(0)), v = new DataView(b.buffer), a = new Float32Array(HGRID.w * HGRID.h); for (let i = 0; i < a.length; i++) a[i] = v.getUint16(i * 2, true) / 2; return a; })();
// أشجار وشجيرات وصخور في أماكنها من صورة القمر
const FLORA_K = ['olive', 'poplar', 'eucal', 'bush', 'rocks'], FLORA_S = [3.4, 2.8, 3.8, 2.2, 2.6];
const WS = {}; for (const k in BSPR) { const im = new Image(); im.src = BSPR[k]; WS[k] = im; }
const KM = 33;
function hAt(x, y){
  const gx = (x - HGRID.x0) / HGRID.cell, gy = (y - HGRID.y0) / HGRID.cell;
  if (gx >= 0 && gy >= 0 && gx < HGRID.w - 1 && gy < HGRID.h - 1) { const i = gx | 0, j = gy | 0, fx = gx - i, fy = gy - j, W_ = HGRID.w, a = HG[j * W_ + i], b = HG[j * W_ + i + 1], c = HG[(j + 1) * W_ + i], d = HG[(j + 1) * W_ + i + 1]; return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy; } const i = Math.max(0, Math.min(FIELD.hh - 1, Math.floor(y / 8))), j = Math.max(0, Math.min(FIELD.hw - 1, Math.floor(x / 8))); return FIELD.H[i * FIELD.hw + j]; }
// المدن بمواقعها الحقيقية
const TOWNS = [
  {id: 'duhok', n: 'دهوك', x: 1165, y: 667, r: 75, obj: true, houses: 9, mosque: 2},
  {id: 'simele', n: 'سميل', x: 731, y: 700, r: 55, obj: true, houses: 5, mosque: 1},
  {id: 'alqosh', n: 'ألقوش', x: 1445, y: 1147, r: 55, obj: true, houses: 4, mosque: 1},
  {id: 'baadra', n: 'باعذرا', x: 1762, y: 1256, r: 40, houses: 3},
  {id: 'telkaif', n: 'تلكيف', x: 1509, y: 2029, r: 55, houses: 5, mosque: 1},
];
// أنواع الوحدات (المدى بالبكسل، والسرعة بكسل/ثانية، hold = مسافة الوقوف والرمي نسبة للمدى، minD = أقرب مسافة لعدو صامد)
const UT = {
  tank:   {hp: 100, arm: 2, rng: 2.6 * KM, rof: 3.6, ds: 22, dh: 46, acc: .55, spd: (12 / 30),  sz: 13, cost: 3,   snd: 'tank_cannon', fx: 'shell', veh: 1, turn: .9, hold: .85, minD: 1.5 * KM},
  ifv:    {hp: 70,  arm: 1, rng: 1.8 * KM, rof: 1.5, ds: 16, dh: 14, acc: .5,  spd: (13 / 30),  sz: 11, cost: 2,   snd: 'hmg', fx: 'tracer', veh: 1, turn: 1.2, hold: .9, minD: 1.1 * KM},
  squad:  {hp: 60,  arm: 0, rng: 1.0 * KM, rof: 1.1, ds: 9,  dh: 2,  acc: .45, spd: (1.6 / 30), sz: 15, cost: 1,   snd: 'ak47', fx: 'tracer', inf: 1, hold: 1, minD: .8 * KM},
  atgm:   {hp: 40,  arm: 0, rng: 3.5 * KM, rof: 10,  ds: 4,  dh: 72, acc: .62, spd: (1.3 / 30), sz: 10, cost: 1.5, snd: 'atgm_launch', fx: 'atgm', heavyOnly: true, ammo: 4, inf: 1, hold: .9, minD: 1.5 * KM},
  mg:     {hp: 40,  arm: 0, rng: 1.4 * KM, rof: .55, ds: 6,  dh: 1,  acc: .4,  spd: (1.3 / 30), sz: 10, cost: 1,   snd: 'hmg2', fx: 'tracer', softOnly: true, inf: 1, hold: .95, minD: .8 * KM},
  mortar: {hp: 40,  arm: 0, rng: 5 * KM,   rof: 4.5, ds: 14, dh: 8,  acc: .35, spd: (1.2 / 30),   sz: 10, cost: 1,   snd: 'artillery2', fx: 'indirect', ind: true, area: 16, ammo: 40, inf: 1, hold: .8, minD: 2 * KM},
  sniper: {hp: 30,  arm: 0, rng: 1.6 * KM, rof: 4.5, ds: 32, dh: 0,  acc: .7,  spd: (1.3 / 30), sz: 9,  cost: 1,   snd: 'rifle', fx: 'none', softOnly: true, inf: 1, hold: .95, minD: 1 * KM},
  arty:   {hp: 60,  arm: 1, rng: 25 * KM,  rof: 8,   ds: 24, dh: 16, acc: .3,  spd: (8 / 30), sz: 15, cost: 2,   snd: 'artillery', fx: 'indirect', ind: true, area: 22, veh: 1, turn: .6, hold: .3, minD: 4 * KM},
  mlrs:   {hp: 50,  arm: 1, rng: 0,        rof: 99,  ds: 0,  dh: 0,  acc: 0,   spd: (10 / 30),   sz: 15, cost: 2,   veh: 1, turn: .8, hold: 0, minD: 5 * KM},
  ad:     {hp: 60,  arm: 1, rng: 0,        rof: 99,  ds: 0,  dh: 0,  acc: 0,   spd: (8 / 30), sz: 14, cost: 2,   airRng: 22 * KM, veh: 1, turn: .6, hold: 0, minD: 4 * KM},
  heli:   {hp: 70,  arm: 1, rng: 4.5 * KM, rof: 2.2, ds: 14, dh: 40, acc: .55, spd: (60 / 30),  sz: 20, cost: 3,   snd: 'heli_gun', fx: 'heli', air: true, alt: 24, hold: .8, minD: 3 * KM},
  drone:  {hp: 30,  arm: 1, rng: 0, rof: 99, ds: 0, dh: 0, acc: 0, spd: (45 / 30), sz: 16, cost: 0, air: true, alt: 55},
  recon:  {hp: 30,  arm: 1, rng: 0, rof: 99, ds: 0, dh: 0, acc: 0, spd: (35 / 30), sz: 18, cost: 0, air: true, alt: 60},
  jet:    {hp: 40,  arm: 1, rng: 0, rof: 99, ds: 0, dh: 0, acc: 0, spd: (250 / 30), sz: 28, cost: 0, air: true, alt: 95},
};
const SPRITE = {
  iq: {tank: ['qaqaa', 't72'], ifv: ['bmp1'], squad: ['squad_iq'], atgm: ['atgm_team'], mg: ['mg_team'], mortar: ['mortar'], sniper: ['sniper'], arty: ['samsama'], mlrs: ['mlrs_iq'], ad: ['pantsir'], heli: ['mi35b'], recon: ['ch4'], jet: ['f16a'], drone: ['ch4']},
  tr: {tank: ['leopard2a4', 'altay'], ifv: ['acv15'], squad: ['squad_tr'], atgm: ['atgm_team'], mg: ['mg_team'], mortar: ['mortar'], sniper: ['sniper'], arty: ['firtina'], mlrs: ['firtina'], ad: ['ad_truck'], heli: ['t129b'], drone: ['tb2'], recon: ['tb2'], jet: ['f16a']}
};
const NAME = {tank: 'دبابة', ifv: 'مدرعة', squad: 'فصيل مشاة', atgm: 'فريق مضاد دروع', mg: 'فريق رشاش', mortar: 'هاون', sniper: 'قناصة', arty: 'مدفعية', mlrs: 'راجمة صواريخ', ad: 'دفاع جوي', heli: 'مروحية', drone: 'مسيّرة', recon: 'مسيّرة استطلاع', jet: 'مقاتلة'};
const PREP = 150;   // ثواني التمهيد الناري قبل تقدم الدروع (دقيقتان ونصف)
const BATTLE = 3600; // مدة المعركة بزمنها الحقيقي: ساعة (استعمل التسريع)

let W = null;   // حالة المعركة
let wraf = 0, wlast = 0, wspeed = 1;
function wrand(){ W.seed = (W.seed * 1664525 + 1013904223) >>> 0; return W.seed / 4294967296; }
const ground = u => !u.dead && !UT[u.t].air;
const angDiff = (a, b) => Math.atan2(Math.sin(b - a), Math.cos(b - a));

function mkUnit(side, t, x, y, o = {}){
  const d = UT[t], spr = SPRITE[side][t];
  const ang = side === 'iq' ? -Math.PI / 2 : Math.PI / 2;
  const u = Object.assign({id: W.nid++, ammo: d.ammo ?? -1, side, t, x, y, hp: d.hp, mor: 100, sup: 0, cd: wrand() * d.rof, ang, ta: ang, v: 0, path: [], pi: 0, retreat: false, dead: false, home: {x, y}, lastHit: -99, lastShot: -99, trk: {x, y}, dustT: 0, recoil: 0, alt: d.alt || 0, spr: spr[W.nid % spr.length]}, o);
  W.units.push(u); return u;
}
function setupWar(){
  W = {losC: new Map(), sel: [], aim: null, t: 0, seed: 20261011, nid: 1, units: [], proj: [], parts: [], decals: [], props: [], fly: [], smokes: [], log: [], order: 'attack', phase: 'prep', end: null,
    stats: {iq: {lost: {}, fired: 0}, tr: {lost: {}, fired: 0}, msl: 0, trMsl: 0, jetsLost: 0},
    uses: {air: 2, msl: 3, res: 1}, cool: {air: 0, msl: 0}, ctl: {duhok: 0, simele: 0, alqosh: 0}, trMslT: 300, droneT: 360, follow: true,
    cam: {x: 1250, y: 1400, k: 2.6}};
  // خط الدفاع التركي الأول على السلسلة الجنوبية، والثاني عند مدخل دهوك
  const line1 = [[1060, 1088], [1150, 1080], [1240, 1092], [1330, 1084], [1420, 1098]];
  const line2 = [[1080, 820], [1170, 812], [1260, 826]];
  for (const [x, y] of line1.concat(line2)) { W.props.push({k: 'trench', x, y: y + 6, s: 34, rot: 0, trench: true}); W.props.push({k: 'sandbags', x: x + 16, y: y - 3, s: 8, rot: 0}); }
  W.props.push({k: 'checkpoint', x: 1175, y: 900, s: 9, rot: 0}); W.props.push({k: 'twall', x: 1175, y: 894, s: 8, rot: 0});
  W.props.push({k: 'depot', x: 1260, y: 1680, s: 12, rot: 0}); W.props.push({k: 'hospital', x: 1180, y: 1700, s: 10, rot: 0}); W.props.push({k: 'shed', x: 1272, y: 1694, s: 5, rot: .3});
  W.props.push({k: 'depot', x: 1210, y: 560, s: 11, rot: 0}); W.props.push({k: 'twall', x: 1210, y: 552, s: 9, rot: 0});
  for (const [x, y] of [[1130, 520], [1220, 515]]) W.props.push({k: 'berm', x, y: y + 6, s: 10, rot: 0});
  // آثار حرب سابقة على الطرق: سيارات محروقة ومتروكة
  for (const [k, x, y, r] of [['car_burnt', 1200, 1180, .4], ['car_burnt', 1330, 1000, 2.1], ['pickup', 1100, 1300, 1.2], ['car', 1385, 1210, 3.0], ['car_burnt', 1160, 880, .9], ['pickup', 1260, 960, 2.6]]) W.props.push({k, x, y, s: 2.6, rot: r});
  // تركيا: دفاع متدرج في الخنادق، ودروع خلفها للهجوم المضاد
  line1.forEach(([x, y], i) => { mkUnit('tr', 'squad', x - 6, y, {dug: true}); if (i % 2 === 0) mkUnit('tr', 'atgm', x + 14, y + 2, {dug: true}); });
  mkUnit('tr', 'mg', 1195, 1086, {dug: true}); mkUnit('tr', 'mg', 1375, 1090, {dug: true}); mkUnit('tr', 'sniper', 1290, 1072, {dug: true});
  mkUnit('tr', 'tank', 1120, 1030); mkUnit('tr', 'tank', 1300, 1025); mkUnit('tr', 'ifv', 1210, 1020);
  mkUnit('tr', 'squad', 1430, 1140); mkUnit('tr', 'squad', 1460, 1160); mkUnit('tr', 'ifv', 1440, 1115); mkUnit('tr', 'tank', 1480, 1105);
  line2.forEach(([x, y]) => { mkUnit('tr', 'squad', x - 6, y, {dug: true}); mkUnit('tr', 'atgm', x + 16, y, {dug: true}); });
  mkUnit('tr', 'tank', 1140, 760); mkUnit('tr', 'tank', 1210, 755); mkUnit('tr', 'ifv', 1180, 705);
  mkUnit('tr', 'squad', 1150, 660); mkUnit('tr', 'squad', 1190, 690); mkUnit('tr', 'mg', 1170, 640); mkUnit('tr', 'mortar', 1200, 610);
  mkUnit('tr', 'squad', 731, 700); mkUnit('tr', 'atgm', 750, 715); mkUnit('tr', 'tank', 760, 680);
  mkUnit('tr', 'arty', 1130, 520); mkUnit('tr', 'arty', 1220, 515); mkUnit('tr', 'ad', 1260, 600); mkUnit('tr', 'heli', 1230, 560);
  // العراق: ثلاث مجموعات على خط الانطلاق، على بعد 11 كم من الخط التركي الأول
  const east = [[1445, 1147], [1300, 840], [1170, 680]], center = [[1220, 1085], [1180, 830], [1165, 670]], west = [[960, 1000], [760, 720]];
  const grp = (pts, list, x0, y0, g) => list.forEach(([t, dx, dy]) => mkUnit('iq', t, x0 + dx, y0 + dy, {grp: g, path: pts.map(([x, y]) => ({x: x + dx * .4, y: y + dy * .2}))}));
  grp(center, [['tank', -36, 0], ['tank', 0, -6], ['tank', 36, 0], ['ifv', -18, 26], ['ifv', 18, 26], ['squad', -40, 46], ['squad', 0, 50], ['squad', 40, 46], ['atgm', 0, 72], ['mg', -26, 76], ['sniper', 26, 76], ['mortar', -12, 100], ['mortar', 12, 100]], 1220, 1260, 'الوسط');
  grp(east, [['tank', -28, 0], ['tank', 8, -6], ['tank', 44, 4], ['ifv', 0, 26], ['squad', -22, 46], ['squad', 22, 46], ['atgm', 0, 68], ['mortar', 0, 92]], 1500, 1280, 'الشرق');
  grp(west, [['tank', -18, 0], ['tank', 18, 0], ['ifv', 0, 24], ['squad', -18, 44], ['squad', 18, 44]], 980, 1240, 'الغرب');
  mkUnit('iq', 'arty', 1180, 1760); mkUnit('iq', 'arty', 1260, 1770); mkUnit('iq', 'arty', 1340, 1760);
  mkUnit('iq', 'mlrs', 1140, 1820); mkUnit('iq', 'mlrs', 1380, 1825);
  mkUnit('iq', 'ad', 1300, 1480);
  mkUnit('iq', 'heli', 1200, 1460, {grp: 'المروحيات'}); mkUnit('iq', 'heli', 1460, 1470, {grp: 'المروحيات'});
  mkUnit('iq', 'recon', 1250, 1250, {orbit: {x: 1240, y: 1060, r: 110}, oa: 0});
  for (const u of W.units) u.start = {x: u.x, y: u.y};
  W.init = {iq: strength('iq'), tr: strength('tr')};
  wlog('المرحلة الأولى: مسيّرة الاستطلاع تكشف المواقع والمدفعية تبدأ التمهيد الناري. الدروع تنتظر على خط الانطلاق.', 'iq');
}
function nearestEnemy(u){ let best = null, bd = 1e9; for (const v of W.units) { if (v.side === u.side || !ground(v)) continue; const r = dist(u, v); if (r < bd) { bd = r; best = v; } } return best ? {v: best, d: bd} : null; }
function localStr(side, at, R){ let s = 0; for (const v of W.units) if (v.side === side && ground(v) && dist(v, at) < R) s += UT[v.t].cost * v.hp / UT[v.t].hp; return s; }
function strength(side){ let s = 0; for (const u of W.units) if (u.side === side && !u.dead && UT[u.t].cost) s += UT[u.t].cost * u.hp / UT[u.t].hp; return s; }
function wlog(t, side){ W.log.unshift({t, side, at: W.t}); if (W.log.length > 30) W.log.pop(); const el = document.getElementById('wlog'); if (el) el.innerHTML = W.log.slice(0, 3).map((l, i) => `<div style="opacity:${1 - i * .28};color:${l.side === 'iq' ? 'var(--mine)' : l.side === 'tr' ? '#e07b6e' : 'var(--text)'}">${l.t}</div>`).join(''); }
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
function inTown(u){ for (const t of TOWNS) if (Math.hypot(u.x - t.x, u.y - t.y) < t.r) return t; return null; }
function slopeShade(x, y){ const e = 6, gx = (hAt(x + e, y) - hAt(x - e, y)) / (2 * e * 30), gy = (hAt(x, y + e) - hAt(x, y - e)) / (2 * e * 30); return Math.max(0, Math.min(1, .7 + (gx + gy) * -1.6)); }   // الشمس من الشمال الغربي
function cover(u){ let c = 1; if (u.dug && !u.moving) c *= .5; if (inTown(u)) c *= .6; if (UT[u.t].inf && u.sup > 50) c *= .7; return c; }
// الستار الدخاني يحجب الرؤية: الرمي من خلاله يضعف كثيراً
function smoked(a, b){
  for (const s of W.smokes) {
    const dx = b.x - a.x, dy = b.y - a.y, L = dx * dx + dy * dy || 1, k = Math.max(0, Math.min(1, ((s.x - a.x) * dx + (s.y - a.y) * dy) / L));
    if (Math.hypot(a.x + dx * k - s.x, a.y + dy * k - s.y) < s.r) return true;
  }
  return false;
}
// رأس السبطانة: للدبابة من البرج، ولغيرها من مقدمة الوحدة
function muzzleOf(u){
  const d = UT[u.t], T = TANKS[u.spr];
  if (u.t === 'tank' && T) { const rx = u.x + Math.cos(u.ang) * T.ringY * d.sz, ry = u.y + Math.sin(u.ang) * T.ringY * d.sz, L = (.5 - T.pivY) * T.turS * d.sz; return {x: rx + Math.cos(u.ta) * L, y: ry + Math.sin(u.ta) * L}; }
  return {x: u.x + Math.cos(u.ta) * d.sz * .5, y: u.y + Math.sin(u.ta) * d.sz * .5};
}

// ------------------------------------------------------------------ الجزيئات بإحداثيات العالم
function wp(img, x, y, o){ if (W.parts.length > 850) return; W.parts.push(Object.assign({img, x, y, vx: 0, vy: 0, s0: 10, s1: 20, a0: 1, a1: 0, rot: wrand() * 6.28, vr: (wrand() - .5) * .5, t: 0, life: 1, delay: 0, layer: 'top'}, o)); }
function wboom(x, y, big = 1, snd = true){
  const r = Math.max(10 * big, 9 / W.cam.k * big); (W.flashes = W.flashes || []).push({x, y, r: 34 * big, t: .45}); c2Mark(x, y, 'boom', 14 * big);
  wp('flare', x, y, {s0: r * 1.4, s1: r * 2.4, a0: 1, life: .18, vr: 0});
  wp('fireball', x, y, {s0: r * .7, s1: r * 2.1, life: .75, vr: 0});
  wp('fireball', x + (wrand() - .5) * r * .5, y + (wrand() - .5) * r * .5, {s0: r * .5, s1: r * 1.5, life: .6, delay: .08, vr: 0});
  wp('sparks', x, y, {s0: r * .8, s1: r * 2.4, life: .5});
  wp('shock', x, y, {s0: r * .5, s1: r * 2.6, a0: .55, life: .9, layer: 'mid', vr: 0});
  wp('launch_dust', x, y, {s0: r * .8, s1: r * 2.6, a0: .55, life: 2.6, layer: 'mid', vx: 2, vy: -2});
  for (let i = 0; i < 1 + big; i++) wp('smoke_dark', x + (wrand() - .5) * r * .5, y + (wrand() - .5) * r * .5, {s0: r * .5, s1: r * (1.6 + wrand() * .6), a0: .75, life: 3.2 + wrand() * 1.5, delay: .12 + i * .08, vx: 2 + wrand() * 3, vy: -3 - wrand() * 4, layer: 'mid'});
  if (big >= .8) { if (W.decals.length > 300) W.decals.shift(); W.decals.push({k: big > 1.2 ? 'crater_big' : 'crater_small', x, y, s: big > 1.6 ? 8 : big > 1.2 ? 6 : 4, rot: wrand() * 6.28, a: .5}); }
  if (snd) { wsound(big > 1.3 ? 'explosion_big' : big > .8 ? 'explosion_med' : 'explosion_med2', x, y, .6 + big * .15); if (big > 1.2 && wrand() < .4) wsound('debris', x, y, .35, .4); }
  // الانفجار يثبّت من حوله
  for (const v of W.units) if (ground(v)) { const d = Math.hypot(v.x - x, v.y - y); if (d < r * 3) v.sup = Math.min(100, v.sup + 35 * (1 - d / (r * 3))); }
}
// ------------------------------------------------------------------ الصوت بموضعه: يسار ويمين حسب الشاشة، ويخفت ويُكتم بالبعد
let sndBudget = 0;
const SNDS = {iq: {squad: 'ak_close', mg: 'pkm_close', ifv: 'cannon30', sniper: 'sniper2', mortar: 'mortar_launch'}, tr: {squad: 'g3', mg: 'm2', ifv: 'm2', sniper: 'sniper2', mortar: 'mortar_launch'}};
const FAR = {tank_cannon: 'tank_far_shot', tank_close_shot: 'tank_far_shot', ak_close: 'ak_far', g3: 'ak_far', pkm_close: 'mg_far', m2: 'mg_far', cannon30: 'mg_far', dshk: 'mg_far', artillery: 'arty_far', mlrs: 'mlrs_far', explosion_big: 'boom_echo'};
const ALT = {artillery: ['arty_c1', 'arty_c2', 'arty_c3', 'cannon_real'], arty_far: ['arty_f1', 'arty_f2', 'arty_f3'], mortar_launch: ['mort_1', 'mort_2', 'mort_3', 'mort_4', 'mort_t'], rpg2: ['rpg2', 'rpg_real'], cracks: ['bullet_crack', 'bullet_crack', 'cracks'], jet_flyby: ['jet_pass'], tank_cannon: ['tank_cannon', 'tank_close_shot', 'real_tank'], explosion_big: ['explosion_big', 'real_strike'], dshk: ['dshk', 'real_hmg'], ak_close: ['ak_close', 'real_bursts'], explosion_med: ['explosion_med', 'boom_close', 'range_blast'], ricochet: ['rico_1', 'rico_2', 'ricochet2'], rocket_one: ['rocket_one', 'rocket_one2']};
const NODELAY = {radio: 1, missile_alert: 1, jet_high: 1, war_horn: 1, cracks: 1, shouts: 1};
// المستمع في مركز الشاشة، وارتفاعه بحسب التقريب (كلما ابتعدت الكاميرا ابتعد المستمع)
function listenerDist(x, y){ const c = W.cam, g = Math.hypot(x - c.x, y - c.y) * 30, h = 1100 / c.k; return Math.hypot(g, h); }
function wsound(k, x, y, vol = .7, delay = 0, rate){
  if (sndBudget > 14) return;
  const c = W.cam, d = listenerDist(x, y);                      // بالأمتار
  if (d > 30000) return;
  sndBudget++;
  if (d > 1600 && FAR[k]) { k = FAR[k]; vol *= 1.5; }
  if (ALT[k]) k = ALT[k][Math.floor(Math.random() * ALT[k].length)];
  // الضوء يصل فوراً، والصوت بسرعة 343 م/ث: انفجار على 3 كم تراه ثم تسمعه بعد 9 ثوانٍ
  const travel = NODELAY[k] ? 0 : d / 343;
  const sx = (x - c.x) * c.k + innerWidth / 2;
  play(k, {vol: vol * Math.min(1.3, 700 / (d + 250)) + .02, x: Math.max(0, Math.min(innerWidth, sx)), dist: Math.min(1, d / 7000), delay: (delay + travel) / Math.max(1, wspeed), rate, echo: Math.max(0, Math.min(.55, (d - 700) / 6000))});
}

// ------------------------------------------------------------------ المحاكاة
function los(a, b){
  if (UT[a.t].air || UT[b.t].air || dist(a, b) < .5 * KM) return true;
  const key = a.id < b.id ? a.id * 4096 + b.id : b.id * 4096 + a.id, c = W.losC.get(key);
  if (c && W.t - c.t < 1.5) return c.v;
  const ha = hAt(a.x, a.y) + 4, hb = hAt(b.x, b.y) + 3, n = Math.max(4, Math.ceil(dist(a, b) / 3)); let v = true;
  for (let i = 1; i < n; i++) { const k = i / n, h = hAt(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k); if (h > ha + (hb - ha) * k + 6) { v = false; break; } }
  W.losC.set(key, {v, t: W.t}); return v;
}
function pickTarget(u, d){
  if (u.focus) { const f = W.units.find(v => v.id === u.focus && !v.dead); if (f && dist(u, f) <= d.rng && !(d.heavyOnly && !UT[f.t].arm) && !(d.softOnly && UT[f.t].arm)) return f; if (!f) u.focus = null; }
  let best = null, bs = -1;
  for (const v of W.units) {
    if (v.side === u.side || !ground(v)) continue;
    const r = dist(u, v); if (r > d.rng * (1 + Math.max(0, hAt(u.x, u.y) - hAt(v.x, v.y)) / 600)) continue;
    if (!d.ind && !los(u, v)) continue;
    const hv = UT[v.t].arm > 0;
    if (d.heavyOnly && !hv) continue; if (d.softOnly && hv) continue;
    let sc = 1 / (r + 20); if (d.dh > d.ds && hv) sc *= 3; if (d.ds >= d.dh && !hv) sc *= 2; if (v.t === 'atgm' || v.t === 'arty') sc *= 1.5; if (smoked(u, v)) sc *= .3;
    if (sc > bs) { bs = sc; best = v; }
  }
  return best;
}
// المدفعية تحتاج من يرى الهدف: وحدة صديقة قريبة، أو مسيّرة استطلاع فوقه
function spotted(side, v){ for (const u of W.units) if (u.side === side && !u.dead && dist(u, v) < (u.t === 'recon' ? 6 : 4) * KM && (u.t === 'recon' || los(u, v))) return true; return false; }
function fire(u, v){
  const d = UT[u.t]; W.stats[u.side].fired++; u.lastShot = W.t; const snd = (SNDS[u.side] || {})[u.t] || d.snd;
  const r = dist(u, v), hv = UT[v.t].arm > 0;
  let p = d.acc * (1 - r / (d.rng * 1.6)) * cover(v) * (1 - u.sup / 140);
  if (hAt(v.x, v.y) - hAt(u.x, u.y) > 60) p *= .8;
  if (v.moving) p *= .85; if (u.moving) p *= .6; if (smoked(u, v)) p *= .35;
  const hit = wrand() < p;
  const dmg = (UT[v.t].arm === 2 ? d.dh : UT[v.t].arm === 1 ? (d.ds + d.dh) / 2 : d.ds) * (.7 + wrand() * .6);
  if (d.ind) {
    // مدفعية وهاون: القذيفة تعلو ثم تنزل، والصفير يسبق السقوط
    const tx = v.x + (wrand() - .5) * 24, ty = v.y + (wrand() - .5) * 24, dur = u.t === 'mortar' ? 10 + r / KM * 5 : 8 + r / KM * 2.5; /* هاون: قوس عالٍ بطيء. 155 ملم: نحو 45 ث لـ 15 كم */
    W.proj.push({k: 'arty', x0: u.x, y0: u.y, x1: tx, y1: ty, t: 0, dur, peak: u.t === 'mortar' ? 70 : 140, side: u.side, area: d.area, soft: d.ds, hard: d.dh});
    const m = muzzleOf(u);
    wp('muzzle', m.x, m.y, {s0: d.sz * .8, s1: d.sz * 1.2, life: .16, rot: u.ta + Math.PI / 2, vr: 0});
    wp('blast_dust', m.x, m.y, {s0: d.sz * .8, s1: d.sz * 3, a0: .75, life: 2.2, layer: 'mid'});
    u.recoil = 1;
    wsound(snd, u.x, u.y, u.t === 'mortar' ? .4 : .55);
    wsound(u.t === 'mortar' ? 'mortar_in' : 'incoming', tx, ty, .45, Math.max(0, dur - (u.t === 'mortar' ? 1.4 : 1.8)) - listenerDist(tx, ty) / 343);
    return;
  }
  const m = muzzleOf(u), fx = d.fx;
  const miss = hit ? 0 : 1, mx = miss * (wrand() - .5) * 28, my = miss * (wrand() - .5) * 28;
  if (fx === 'shell') {
    // طلقة الدبابة: وميض، وحلقة غبار حول الدبابة، وارتداد البرج، وقذيفة مضيئة سريعة
    W.proj.push({k: 'shell', x0: m.x, y0: m.y, x1: v.x + mx, y1: v.y + my, t: 0, dur: Math.max(.05, r / (1700 / 30)), target: v, hit, dmg, side: u.side, by: u.t}); /* 1,700 م/ث */
    wp('muzzle', m.x, m.y, {s0: d.sz * .7, s1: d.sz * 1.1, life: .12, rot: u.ta + Math.PI / 2, vr: 0});
    wp('blast_dust', m.x, m.y, {s0: d.sz * .9, s1: d.sz * 2.8, a0: .8, life: 1.8, layer: 'mid', vr: 0});
    wp('smoke_light', m.x, m.y, {s0: d.sz * .4, s1: d.sz * 1.6, a0: .4, life: 2, vx: 2, vy: -2, layer: 'mid'});
    u.recoil = 1;
    wsound(snd, u.x, u.y, .55);
    if (listenerDist(v.x, v.y) < 600) wsound('cracks', v.x, v.y, .5, r / (1700 / 30));
  } else if (fx === 'tracer' && u.t === 'squad' && UT[v.t].arm && r < .7 * KM && wrand() < .25) {
    // المشاة يطلقون آر بي جي على المدرعات القريبة
    W.proj.push({k: 'hrkt', x0: m.x, y0: m.y, x1: v.x + mx, y1: v.y + my, t: 0, dur: Math.max(.15, r / (200 / 30)), target: v, hit, dmg: 48 * (.7 + wrand() * .6), side: u.side, by: 'rpg'}); /* آر بي جي ~200 م/ث */
    wp('backblast', u.x - Math.cos(u.ta) * 5, u.y - Math.sin(u.ta) * 5, {s0: 6, s1: 16, a0: .8, life: 1.4, rot: u.ta + Math.PI / 2, vr: 0, layer: 'mid'}); wsound('rpg2', u.x, u.y, .5);
  } else if (fx === 'tracer') {
    // رشقة: عدة طلقات مضيئة متتابعة، وغبار حيث تسقط
    const n = u.t === 'mg' ? 5 : 3;
    for (let i = 0; i < n; i++) W.proj.push({k: 'tracer', x0: m.x, y0: m.y, x1: v.x + mx + (wrand() - .5) * 10, y1: v.y + my + (wrand() - .5) * 10, t: -i * .07, dur: Math.max(.05, r / ((u.t === 'ifv' ? 1000 : 800) / 30)), target: i === 0 ? v : null, hit: i === 0 && hit, dmg, side: u.side, by: u.t});
    wp('rifle_flash', m.x, m.y, {s0: 4, s1: 6, life: .1, vr: 0});
    if (wrand() < .55) wsound(snd, u.x, u.y, .38);
    // من يقف قرب الهدف يسمع الرصاص يطقطق فوقه، وفي القتال القريب تُرمى قنابل يدوية
    if (wrand() < .35 && listenerDist(v.x, v.y) < 500) wsound('cracks', v.x, v.y, .4, r / ((u.t === 'ifv' ? 1000 : 800) / 30));
    if (u.t === 'squad' && r < .55 * KM && wrand() < .08) { wboom(v.x + (wrand() - .5) * 6, v.y + (wrand() - .5) * 6, .25, false); wsound('grenade', v.x, v.y, .45); if (hit) damage(v, 12, u.side); }
  } else if (fx === 'atgm') {
    // صاروخ مضاد دروع: عصفة غبار خلف الرامي، وصاروخ بطيء يتمايل ووراءه دخان
    W.proj.push({k: 'atgm', x0: m.x, y0: m.y, x1: v.x + mx, y1: v.y + my, t: 0, dur: Math.max(.3, r / (280 / 30)), target: v, hit, dmg, side: u.side, by: u.t}); /* مضاد دروع ~280 م/ث */
    const bx = u.x - Math.cos(u.ta) * 7, by = u.y - Math.sin(u.ta) * 7;
    wp('backblast', bx, by, {s0: 10, s1: 26, a0: .85, life: 1.8, rot: u.ta + Math.PI / 2, vr: 0, layer: 'mid'});
    wp('muzzle', m.x, m.y, {s0: 5, s1: 8, life: .12, rot: u.ta + Math.PI / 2, vr: 0});
    wsound('atgm_launch', u.x, u.y, .5);
  } else if (fx === 'heli') {
    // المروحية: صاروخ موجّه على الدروع، وصواريخ غير موجهة على المشاة، ورشاشها إذا كان العدو قريباً
    if (hv) { W.proj.push({k: 'atgm', x0: u.x, y0: u.y, x1: v.x + mx, y1: v.y + my, t: 0, dur: Math.max(.3, r / (400 / 30)), target: v, hit, dmg: dmg * 1.2, side: u.side, by: u.t, alt0: u.alt}); wsound('atgm_launch', u.x, u.y, .5); }
    else if (r < 2 * KM) { for (let i = 0; i < 6; i++) W.proj.push({k: 'tracer', x0: u.x, y0: u.y, x1: v.x + (wrand() - .5) * 14, y1: v.y + (wrand() - .5) * 14, t: -i * .05, dur: Math.max(.05, r / (900 / 30)), target: i === 0 ? v : null, hit: i === 0 && hit, dmg: dmg * .6, side: u.side, by: u.t}); wsound('heli_gun', u.x, u.y, .5); }
    else { for (let i = 0; i < 4; i++) W.proj.push({k: 'hrkt', x0: u.x + (i % 2 ? 3 : -3), y0: u.y, x1: v.x + (wrand() - .5) * 26, y1: v.y + (wrand() - .5) * 26, t: -i * .12, dur: Math.max(.2, r / (600 / 30)), target: i === 0 ? v : null, hit: i === 0 && hit, dmg, side: u.side, by: u.t, alt0: u.alt}); wsound('rocket_salvo', u.x, u.y, .5); }
  } else {
    // قناص: طلقة واحدة بلا خط مضيء
    W.proj.push({k: 'bullet', x0: m.x, y0: m.y, x1: v.x + mx, y1: v.y + my, t: 0, dur: Math.max(.05, r / (850 / 30)), target: v, hit, dmg, side: u.side, by: u.t});
    wsound(snd, u.x, u.y, .35);
  }
}
function damage(v, dmg, by, kind){
  if (v.dead) return;
  // قذيفة الدبابة قد ترتد عن الدرع الأمامي فلا تخترق
  if (kind === 'shell' && UT[v.t].arm === 2 && wrand() < .3) { dmg *= .25; wsound('ricochet', v.x, v.y, .35); }
  v.hp -= dmg; v.mor -= 10 + dmg * .25; v.lastHit = W.t; v.sup = Math.min(100, v.sup + 30);
  if (v.hp <= 0) { kill(v, by); return; }
  // الدبابة المصابة تطلق قنابل دخان وتتراجع خلفها
  if (UT[v.t].veh && v.hp < UT[v.t].hp * .6 && !v.smokeUsed && (v.t === 'tank' || v.t === 'ifv')) {
    v.smokeUsed = true; W.smokes.push({x: v.x, y: v.y, r: 18, until: W.t + 90});
    for (let i = 0; i < 5; i++) wp('smoke_screen', v.x + Math.cos(v.ta + (i - 2) * .5) * 10, v.y + Math.sin(v.ta + (i - 2) * .5) * 10, {s0: 8, s1: 42, a0: .65, a1: 0, life: 22, delay: i * .1, vx: 1, vy: -.6, vr: .05, layer: 'top'});
    wsound('smoke_pop', v.x, v.y, .45);
  }
}
function kill(v, by){
  v.dead = true; v.hp = 0;
  const L = W.stats[v.side].lost; L[v.t] = (L[v.t] || 0) + 1;
  for (const u of W.units) if (u.side === v.side && !u.dead && dist(u, v) < 70) u.mor -= 8;
  const d = UT[v.t];
  if (d.air) { v.falling = 1.8; v.vfall = d.spd * .5; wsound('explosion_big', v.x, v.y, .8); wlog(`أُسقطت ${NAME[v.t]} ${v.side === 'tr' ? 'تركية' : 'عراقية'}`, by); return; }
  if (d.arm > 0) {
    wboom(v.x, v.y, 1.4);
    const T = TANKS[v.spr];
    if (T) {
      // نصف الدبابات المدمرة ينفجر مخزن ذخيرتها فيطير البرج
      W.decals.push({k: 'hulk', spr: T.hull, x: v.x, y: v.y, s: d.sz, rot: v.ang + Math.PI / 2, a: 1, burn: 45});
      if (wrand() < .5) { W.fly.push({spr: T.tur, x: v.x, y: v.y, vx: (wrand() - .5) * 18, vy: (wrand() - .5) * 18, alt: 0, va: 55, rot: v.ta + Math.PI / 2, vr: (wrand() - .5) * 9, s: d.sz * T.turS}); wsound('cookoff', v.x, v.y, .55, .3); }
      else W.decals.push({k: 'hulk', spr: T.tur, x: v.x + Math.cos(v.ang) * T.ringY * d.sz, y: v.y + Math.sin(v.ang) * T.ringY * d.sz, s: d.sz * T.turS, rot: v.ta + Math.PI / 2, a: 1, off: T.pivY * d.sz * T.turS});
    } else W.decals.push({k: v.t === 'arty' || v.t === 'ad' || v.t === 'mlrs' ? 'wreck_truck' : 'wreck_apc', x: v.x, y: v.y, s: d.sz * 1.05, rot: v.ang + Math.PI / 2, a: 1, burn: 35});
    wlog(`${by === 'iq' ? 'دُمّرت' : 'خسرنا'} ${NAME[v.t]} ${v.side === 'tr' ? 'تركية' : 'عراقية'}${inTown(v) ? ' في ' + inTown(v).n : ''}`, by);
  } else if (wrand() < .4) wlog(`${NAME[v.t]} ${v.side === 'tr' ? 'تركي' : 'عراقي'} خارج القتال`, by);
}

// حركة واقعية: المركبة تتسارع وتلتف بقوس وتسير باتجاه مقدمتها، والجنود يمشون مباشرة
function drive(u, d, goal, sp, dt){
  u.moving = false;
  if (!goal) { u.v = Math.max(0, u.v - .12 * dt); if (u.v > .01 && d.veh) { u.x += Math.cos(u.ang) * u.v * dt; u.y += Math.sin(u.ang) * u.v * dt; u.moving = true; } return; }
  const dx = goal.x - u.x, dy = goal.y - u.y, r = Math.hypot(dx, dy);
  if (r < 3) { u.v = Math.max(0, u.v - 6 * dt); return; }
  let f = 1;
  if (!d.air) { const h0 = hAt(u.x, u.y), h1 = hAt(u.x + dx / r * 6, u.y + dy / r * 6), sl = (h1 - h0) / 180; if (sl > 0) f *= Math.max(.5, 1 - sl * 1.5); else f *= Math.min(1.12, 1 - sl * .4); }
  if (u.retreat) f *= W.trCollapse && u.side === 'tr' ? 1.8 : 1.3;
  if (d.inf && u.sup > 55 && !u.retreat) f *= .25;   // تحت النار: الجنود ينبطحون ويزحفون
  const want = Math.atan2(dy, dx);
  if (d.veh) {
    const df = angDiff(u.ang, want); u.ang += Math.max(-d.turn * dt, Math.min(d.turn * dt, df));
    const target = sp * f * Math.max(.2, Math.cos(Math.min(Math.abs(df), 1.4))) * Math.min(1, r / 6);
    u.v += Math.max(-.12 * dt, Math.min(.05 * dt, target - u.v)); /* تسارع دبابة حقيقي: نحو 1.5 م/ث² */
    u.x += Math.cos(u.ang) * u.v * dt; u.y += Math.sin(u.ang) * u.v * dt; u.moving = u.v > .02;
  } else {
    u.ang += angDiff(u.ang, want) * Math.min(1, dt * 4); const st = Math.min(r, sp * f * dt);
    u.x += dx / r * st; u.y += dy / r * st; u.moving = st > 0; u.v = sp * f;
  }
  if (u.moving && d.veh && !d.air) {
    if (dist(u, u.trk) > 9) { if (W.decals.length > 300) W.decals.shift(); W.decals.push({k: 'tracks', x: (u.x + u.trk.x) / 2, y: (u.y + u.trk.y) / 2, s: d.sz * .9, rot: Math.atan2(u.y - u.trk.y, u.x - u.trk.x) + Math.PI / 2, a: .3}); u.trk = {x: u.x, y: u.y}; }
    u.dustT -= dt; if (u.dustT <= 0 && u.v > .12) { u.dustT = 1.2; const bx = u.x - Math.cos(u.ang) * d.sz * .6, by = u.y - Math.sin(u.ang) * d.sz * .6; wp('dust_trail', bx, by, {s0: d.sz * 1.2, s1: d.sz * 2.4, a0: .45, life: 1.8, rot: u.ang + Math.PI / 2, vr: 0, vx: 1.5, vy: -1, layer: 'mid'}); }
  }
}

function stepWar(dt){
  W.t += dt; sndBudget = Math.max(0, sndBudget - dt * 14);
  W.cool.air = Math.max(0, W.cool.air - dt); W.cool.msl = Math.max(0, W.cool.msl - dt);
  W.smokes = W.smokes.filter(s => s.until > W.t);
  // المراحل: تمهيد ناري ثم تقدم بالتناوب
  if (W.phase === 'prep' && (W.t >= PREP || W.order !== 'attack')) {
    W.phase = 'advance';
    if (W.order === 'attack') {
      wlog('المرحلة الثانية: الدروع تتقدم وتغطي المشاة بالنار، والتقدم بالتناوب. الهاون يطلق ستاراً دخانياً.', 'iq'); wsound('radio', W.cam.x, W.cam.y, .4);
      // ستار دخاني أمام الخط التركي الأول يغطي اقتراب المشاة
      for (const x of [1120, 1220, 1320]) { W.smokes.push({x, y: 1150, r: 30, until: W.t + 150}); for (let i = 0; i < 4; i++) wp('smoke_screen', x + (i - 1.5) * 16, 1150 + (wrand() - .5) * 10, {s0: 10, s1: 60, a0: .6, life: 45, delay: 1.5 + i * .2, vx: 1.2, vy: -.5, vr: .04, layer: 'top'}); }
    }
  }
  for (const u of W.units) {
    if (u.dead || u.t === 'jet' || u.t === 'drone' || u.t === 'recon') continue;
    const d = UT[u.t];
    if (W.t - u.lastHit > 4) u.mor = Math.min(100, u.mor + dt * 3);
    u.sup = Math.max(0, u.sup - dt * (W.t - u.lastHit > 2 ? 12 : 3));
    u.recoil = Math.max(0, u.recoil - dt * 4);
    if (!u.retreat && u.mor < 22) { u.retreat = true; if (wrand() < .5) wlog(`${NAME[u.t]} ${u.side === 'tr' ? 'تركي' : 'عراقي'} ينسحب بعد خسائر`, u.side === 'tr' ? 'iq' : 'tr'); }
    if (u.retreat && u.mor > 60) u.retreat = false;
    // الهدف: البرج يدور نحوه، والدبابة تقف وقفة قصيرة لترمي بدقة
    u.cd -= dt * (1 / (1 + u.sup / 100));
    let tgt = null;
    if (d.rng > 0) { tgt = pickTarget(u, d); if (tgt && d.ind && !spotted(u.side, tgt)) tgt = null; }
    const aim = tgt ? Math.atan2(tgt.y - u.y, tgt.x - u.x) : u.ang;
    u.ta += Math.max(-1.3 * dt, Math.min(1.3 * dt, angDiff(u.ta, aim)));
    if (!d.veh || u.t !== 'tank') u.ta = d.inf || d.air ? aim : u.ta;
    if (d.inf || d.air) u.ang = tgt && !u.moving ? aim : u.ang;
    const aligned = Math.abs(angDiff(u.ta, aim)) < .1;
    let halt = false;
    if (tgt && u.ammo === 0) tgt = null;
    if (tgt && u.cd <= 0 && aligned) {
      if (u.t === 'tank' && u.v > .12) halt = true;
      else { fire(u, tgt); if (u.ammo > 0) u.ammo--; u.cd = d.rof * (.8 + wrand() * .4) * (u.retreat ? 1.6 : 1); }
    } else if (tgt && u.t === 'tank' && u.cd < .8 && aligned) halt = true;
    // الحركة
    let goal = null, sp = d.spd;
    if (d.inf && u.side === 'iq') { const n0 = nearestEnemy(u); u.mounted = !n0 || n0.d > 3.5 * KM; if (u.mounted) sp = 12 / 30; }
    const order = u.side === 'iq' ? W.order : (W.trCollapse ? 'retreat' : 'hold');
    const ne = nearestEnemy(u);
    const broken = ne && (ne.v.retreat || ne.v.mor < 30), pinned = ne && ne.v.sup > 55;
    // هل نتقدم؟ نقف على مسافة الرمي ونضرب، ونتقدم فقط إذا انكسر العدو أو ثُبّت تحت نارنا، بالتناوب
    let mayAdvance = !(u.side === 'iq' && W.phase === 'prep');
    if (ne && !d.air && mayAdvance) {
      const stand = Math.max(d.rng * d.hold, d.minD);
      const bound = (Math.floor(W.t / 8) + u.id) % 2 === 0;
      const fr = localStr(u.side, u, 5 * KM), en = localStr(ne.v.side, u, 5 * KM);
      if (ne.d < stand && !broken && !(pinned && bound) && fr < en * 3) mayAdvance = false;
      if (ne.d < stand * 1.3 && !broken && !bound) mayAdvance = false;
      if (broken && ne.d < 5 * KM && (u.side === 'iq' ? order === 'attack' : !u.dug)) { goal = {x: ne.v.x, y: ne.v.y}; sp *= .8; }
    }
    if (u.manual) {
      const f = u.focus && W.units.find(v => v.id === u.focus && !v.dead);
      if (f) goal = dist(u, f) > d.rng * .85 ? {x: f.x, y: f.y} : null;
      else goal = dist(u, u.manual) > 5 ? u.manual : null;
    } else if (u.retreat || order === 'retreat') goal = u.side === 'iq' ? u.start : {x: u.x, y: 280};
    else if (u.side === 'iq' && order === 'attack' && u.path.length && !goal && !d.air) {
      while (u.pi < u.path.length - 1 && dist(u, u.path[u.pi]) < 24) u.pi++;
      goal = mayAdvance ? u.path[u.pi] : null;
      if (goal && tgt) sp *= u.t === 'tank' || u.t === 'ifv' ? .6 : .45;
    } else if (u.side === 'tr' && !u.dug && (u.t === 'tank' || u.t === 'ifv')) {
      const e = W.units.filter(v => v.side === 'iq' && ground(v) && dist(u, v) < 6 * KM);
      const f = W.units.filter(v => v.side === 'tr' && ground(v) && dist(u, v) < 6 * KM);
      if (e.length && f.length > e.length * 1.3 && mayAdvance) { const n = e.sort((a, b) => dist(u, a) - dist(u, b))[0]; goal = {x: n.x, y: n.y}; sp *= .7; if (!u.ca) { u.ca = 1; wlog('هجوم مضاد تركي بالدروع', 'tr'); } }
    }
    if (d.air && u.side === 'iq' && order === 'attack' && !u.manual && W.phase !== 'prep') {
      // المروحيات تبقى خلف الدروع وتضرب من بعيد
      const lead = W.units.filter(v => v.side === 'iq' && ground(v) && (v.t === 'tank' || v.t === 'ifv'));
      if (lead.length) { const ly = Math.min(...lead.map(v => v.y)); goal = {x: lead.reduce((s, v) => s + v.x, 0) / lead.length + (u.id % 2 ? 40 : -40), y: ly + 70}; }
    }
    // إذا اقترب عدو صامد جداً (خارج المدن) نتراجع قليلاً إلى مسافة الرمي بدل الالتحام
    let backing = false;
    if (ne && !d.air && !u.dug && !u.manual && !inTown(u) && !broken && ne.d < d.minD * .7) { backing = true; goal = {x: u.x + (u.x - ne.v.x) / ne.d * 30, y: u.y + (u.y - ne.v.y) / ne.d * 30}; sp *= .5; }
    // لا التحام: لا نقترب من عدو صامد أقرب من الحد الأدنى
    if (goal && !u.retreat && order !== 'retreat') {
      const gx = goal.x - u.x, gy = goal.y - u.y, gr = Math.hypot(gx, gy) || 1;
      for (const v of W.units) {
        if (v.side === u.side || !ground(v)) continue;
        const ex = v.x - u.x, ey = v.y - u.y, er = Math.hypot(ex, ey), md = (v.retreat || v.mor < 30) ? (d.veh ? 1.2 * KM : .7 * KM) : (d.air ? d.rng * .7 : d.minD);
        if (er > md * 1.4) continue;
        const toward = (gx * ex + gy * ey) / (gr * (er || 1));
        if (toward > .2 && er < md) { goal = null; break; }
        if (toward > .2) sp *= .5;
      }
    }
    if (goal && !(u.side === 'tr' || order !== 'hold' || u.retreat || u.manual)) goal = null;
    if (halt && !backing) goal = null;
    drive(u, d, goal, sp, dt);
    if (u.dug && u.moving && dist(u, u.home) > 25) u.dug = false;
  }
  // تباعد: الوحدات لا تتراكب، والأعداء لا يتداخلون أبداً
  const gr = W.units.filter(ground);
  for (let i = 0; i < gr.length; i++) for (let j = i + 1; j < gr.length; j++) {
    const a = gr[i], b = gr[j], dx = b.x - a.x, dy = b.y - a.y, r = Math.hypot(dx, dy) || .01;
    const min = a.side === b.side ? (UT[a.t].sz + UT[b.t].sz) * .62 : 20;
    if (r < min) { const push = (min - r) / 2, ux = dx / r, uy = dy / r; if (!a.dug) { a.x -= ux * push; a.y -= uy * push; } if (!b.dug) { b.x += ux * push; b.y += uy * push; } }
  }
  for (const u of gr) {
    if (u.dug) continue;
    for (const h of W.decals) if (h.k === 'hulk' || h.k === 'wreck_apc' || h.k === 'wreck_truck') { const dx = u.x - h.x, dy = u.y - h.y, r = Math.hypot(dx, dy) || .01, m = (h.s + UT[u.t].sz) * .45; if (r < m) { u.x += dx / r * (m - r); u.y += dy / r * (m - r); } }
    if (UT[u.t].veh) for (const p of W.props) if (p.trench) { const dx = u.x - p.x, dy = u.y - p.y; if (Math.abs(dx) < p.s * .55 && Math.abs(dy) < 7) u.y = p.y + (dy < 0 ? -7 : 7); }
  }
  stepProj(dt);
  stepAir(dt);
  // البرج الطائر من الدبابة المنفجرة
  for (const f of W.fly) { f.x += f.vx * dt; f.y += f.vy * dt; f.alt += f.va * dt; f.va -= 70 * dt; f.rot += f.vr * dt; if (f.alt <= 0 && f.va < 0) { f.done = true; W.decals.push({k: 'hulk', spr: f.spr, x: f.x, y: f.y, s: f.s, rot: f.rot, a: 1}); wp('launch_dust', f.x, f.y, {s0: 6, s1: 22, a0: .6, life: 1.6, layer: 'mid'}); } }
  W.fly = W.fly.filter(f => !f.done);
  // السيطرة على المدن
  for (const tw of TOWNS) if (tw.obj) {
    let a = 0, b = 0;
    for (const u of W.units) if (ground(u) && !u.retreat && Math.hypot(u.x - tw.x, u.y - tw.y) < tw.r) { if (u.side === 'iq') a += UT[u.t].cost; else b += UT[u.t].cost; }
    const before = W.ctl[tw.id];
    if (a > 0 && b === 0) W.ctl[tw.id] = Math.min(100, W.ctl[tw.id] + dt * 6 * Math.min(2, a / 3));
    else if (b > 0 && a === 0) W.ctl[tw.id] = Math.max(0, W.ctl[tw.id] - dt * 4);
    if (before < 100 && W.ctl[tw.id] >= 100) { wlog(`قواتنا تسيطر على ${tw.n}`, 'iq'); wsound('war_horn', tw.x, tw.y, .5); }
    if (before === 0 && W.ctl[tw.id] > 0) wlog(`قواتنا تقتحم ${tw.n}`, 'iq');
  }
  const sTr = strength('tr') / W.init.tr, sIq = strength('iq') / W.init.iq;
  if (!W.trCollapse && sTr < .4) { W.trCollapse = true; wlog('انهيار الدفاع التركي: القوات تنسحب شمالاً', 'iq'); }
  if (!W.end) {
    if (W.ctl.duhok >= 100) endWar('win');
    else if (sIq < .25) endWar('lose');
    else if (W.t >= BATTLE) endWar('time');
  }
  // الحطام المحترق
  for (const dc of W.decals) if (dc.burn > 0) { dc.burn -= dt; dc.bt = (dc.bt || 0) - dt; if (dc.bt <= 0) { dc.bt = .45; wp('smoke_oil', dc.x, dc.y, {s0: 6, s1: 40, a0: .6, life: 3.4, vx: 5, vy: -7, layer: 'top'}); if (dc.burn > 20) wp('tank_fire', dc.x + (wrand() - .5) * 3, dc.y + (wrand() - .5) * 3, {s0: dc.s * .6, s1: dc.s * 1.1, a0: .9, life: .7, vr: 0}); } }
}

// ------------------------------------------------------------------ المقذوفات
// الارتفاع: الصاروخ يصعد ثم ينزل. نرسمه أكبر كلما علا، وظله يبتعد عنه
function projPos(p){
  const k = Math.max(0, Math.min(1, p.t / p.dur));
  const x = p.x0 + (p.x1 - p.x0) * k, y = p.y0 + (p.y1 - p.y0) * k;
  let alt = 0;
  if (p.peak) alt = Math.sin(k * Math.PI) * p.peak;
  else if (p.alt0) alt = p.alt0 * (1 - k);
  if (p.k === 'agm') alt = p.t < p.drop ? p.alt0 - (p.t / p.drop) * 8 : (p.alt0 - 8) * (1 - (p.t - p.drop) / (p.dur - p.drop));
  return {x, y, alt, k};
}
function stepProj(dt){
  for (const p of W.proj) {
    if (p.k === 'agm') { p.t += dt; if (!p.lit && p.t >= p.drop) { p.lit = true; const q = projPos(p); wsound('jet_release', q.x, q.y, .5); wsound('missile_fly', q.x, q.y, .35, .2); } }
    else p.t += dt;
    if (p.t < p.dur || p.done) continue;
    p.done = true;
    if (p.intercepted) continue;
    if (p.k === 'arty' || p.k === 'rkt' || p.k === 'bm' || p.k === 'agm') {
      const big = {arty: p.area > 18 ? 1.1 : .8, rkt: 1.25, bm: 2.1, agm: 1.7}[p.k];
      wboom(p.x1, p.y1, big);
      const A = {arty: p.area, rkt: 30, bm: 60, agm: 34}[p.k], soft = {arty: p.soft, rkt: 45, bm: 90, agm: 70}[p.k], hard = {arty: p.hard, rkt: 30, bm: 80, agm: 110}[p.k];
      for (const v of W.units) if (ground(v) && v.side !== p.side) { const r = Math.hypot(v.x - p.x1, v.y - p.y1); if (r < A) damage(v, (UT[v.t].arm ? hard : soft) * (1 - r / A) * cover(v) * 1.3, p.side); }
    } else if (p.k === 'int') {
      const m = p.vs; if (!m || m.done) continue;
      if (p.ok) { m.intercepted = true; m.done = true; if (m.jet) kill(m.jet, p.side); wp('intercept', p.x1, p.y1, {s0: 10, s1: 40, life: .7}); wp('smoke_dark', p.x1, p.y1, {s0: 8, s1: 30, a0: .55, life: 2.2, vx: 3, vy: -2, layer: 'top'}); wsound('intercept', p.x1, p.y1, .6); }
      else wp('intercept', p.x1, p.y1, {s0: 6, s1: 20, life: .5});
    } else {
      const v = p.target;
      if (v && p.hit && !v.dead) {
        damage(v, p.dmg, p.side, p.k); c2Mark(p.x1, p.y1, 'hit');
        if (UT[v.t].arm) { wp('armor_sparks', p.x1, p.y1, {s0: 5, s1: 16, life: .35}); if (p.k !== 'tracer' && p.k !== 'bullet') wsound('armor_hit', p.x1, p.y1, .45); else if (wrand() < .3) wsound('metal_hits', p.x1, p.y1, .3); }
        if (p.k === 'atgm' || p.k === 'hrkt' || (p.k === 'shell' && wrand() < .5)) wboom(p.x1, p.y1, .5, p.k !== 'shell');
      } else if (v) v.sup = Math.min(100, v.sup + (p.k === 'tracer' || p.k === 'bullet' ? 9 : 18));
      if (!p.hit || !v) {
        // الطلقة الخاطئة تثير غباراً حيث تسقط
        if (p.k === 'tracer' || p.k === 'bullet') { if (wrand() < .5) wp('dirt_hits', p.x1, p.y1, {s0: 4, s1: 9, a0: .8, life: .5, layer: 'mid'}); }
        else if (p.k === 'hrkt') wboom(p.x1, p.y1, .45, false);
        else { wp('dirt_hits', p.x1, p.y1, {s0: 6, s1: 16, a0: .9, life: .9, layer: 'mid'}); wp('launch_dust', p.x1, p.y1, {s0: 5, s1: 18, a0: .5, life: 1.5, layer: 'mid'}); }
      }
    }
  }
  W.proj = W.proj.filter(p => !p.done);
}

// ------------------------------------------------------------------ الجو: مقاتلات ومسيّرات ودفاع جوي وصواريخ بعيدة
const tg_y_exit = j => (j.drone ? j.drone.y : 1200) - 10 * KM;
function stepAir(dt){
  for (const j of W.units) {
    if (j.dead && !(j.falling > 0)) continue;
    if (j.falling > 0) { j.falling -= dt; j.x += Math.cos(j.ang) * j.vfall * dt; j.y += Math.sin(j.ang) * j.vfall * dt; j.alt = Math.max(0, j.alt - dt * j.alt * 1.2); j.ang += dt * 2.5; wp('smoke_dark', j.x, j.y, {s0: 5, s1: 24, a0: .6, life: 1.8, layer: 'top'}); if (j.falling <= 0) { wboom(j.x, j.y, 1.4); j.gone = true; } continue; }
    if (j.t === 'jet') {
      // المقاتلة: تطير عالياً، تطلق صواريخها من نحو 12 كم، ثم تنعطف وتعود
      const sp = UT.jet.spd;
      if (j.phase === 'in') {
        const dx = j.rx - j.x, dy = j.ry - j.y, r = Math.hypot(dx, dy); j.ang = Math.atan2(dy, dx);
        if (!j.fired && r < 12) { j.phase = 'out'; j.outT = 0; if (j.id % 2) wlog('المقاتلات أطلقت صواريخها من 10 كم وتنعطف عائدة دون أن تدخل مدى العدو', 'iq'); wsound('jet_flyby', j.x, j.y, .7); j.fired = true; for (let i = 0; i < 2; i++) { const tx = j.tx + (wrand() - .5) * 22, ty = j.ty + (wrand() - .5) * 22, rr = Math.hypot(tx - j.x, ty - j.y); W.proj.push({k: 'agm', x0: j.x + (i ? 4 : -4), y0: j.y, x1: tx, y1: ty, t: -i * .4, dur: 1 + rr / (330 / 30), drop: 1, alt0: j.alt, side: j.side}); } }
      } else {
        j.outT += dt; const want = Math.PI / 2 + (j.side === 'iq' ? 0 : Math.PI);
        j.ang += (j.id % 2 ? 1 : -1) * Math.min(.18 * dt, Math.abs(angDiff(j.ang, want))); /* نصف قطر انعطاف نحو 1.4 كم */
        if (j.outT > 70) { j.dead = true; j.gone = true; }
      }
      j.x += Math.cos(j.ang) * sp * dt; j.y += Math.sin(j.ang) * sp * dt;
      continue;
    }
    if (j.t === 'recon') {
      // مسيّرة الاستطلاع تدور فوق خطوط العدو وتكشفها للمدفعية
      j.oa += dt * UT.recon.spd / j.orbit.r; const o = j.orbit; const gx = o.x + Math.cos(j.oa) * o.r, gy = o.y + Math.sin(j.oa) * o.r * .6;
      const dx = gx - j.x, dy = gy - j.y, r = Math.hypot(dx, dy) || 1; j.ang = Math.atan2(dy, dx); j.x += dx / r * Math.min(r, UT.recon.spd * dt); j.y += dy / r * Math.min(r, UT.recon.spd * dt);
      if (W.phase !== 'prep' && !j.moved) { j.moved = true; o.y -= 230; }
      continue;
    }
    if (j.t === 'drone') {
      // بيرقدار: تقترب حتى 3 كم، تطلق صاروخاً صغيراً، ثم تعود شمالاً
      const tg = j.drone;
      if (!j.fired && tg && !tg.dead) {
        const dx = tg.x - j.x, dy = tg.y - j.y, r = Math.hypot(dx, dy); j.ang = Math.atan2(dy, dx);
        if (r > 4 * KM) { j.x += dx / r * UT.drone.spd * dt; j.y += dy / r * UT.drone.spd * dt; }
        else { j.fired = true; W.proj.push({k: 'atgm', x0: j.x, y0: j.y, x1: tg.x, y1: tg.y, t: 0, dur: r / (240 / 30), target: tg, hit: wrand() < .65, dmg: 70, side: j.side, alt0: j.alt}); wsound('missile_fly', j.x, j.y, .4); }
      } else { j.ang += angDiff(j.ang, -Math.PI / 2) * Math.min(1, dt); j.x += Math.cos(j.ang) * UT.drone.spd * dt; j.y += Math.sin(j.ang) * UT.drone.spd * dt; if (j.y < tg_y_exit(j)) { j.dead = true; j.gone = true; } }
    }
  }
  // الدفاع الجوي: يعترض الصواريخ والطائرات المعادية في مداه
  for (const a of W.units) {
    if (a.dead || a.t !== 'ad') continue;
    a.cd -= dt; if (a.cd > 0) continue;
    const threats = W.proj.filter(p => (p.k === 'rkt' || p.k === 'bm' || p.k === 'agm') && p.side !== a.side && !p.intercepted && !p.engaged && p.t > .25 * p.dur && Math.hypot(p.x1 - a.x, p.y1 - a.y) < UT.ad.airRng);
    const air = W.units.filter(j => !j.dead && j.side !== a.side && (j.t === 'jet' || j.t === 'drone' || j.t === 'recon') && !j.engaged && dist(j, a) < UT.ad.airRng);
    const m = threats[0] || null, jet = !m ? air[0] : null;
    if (m) { m.engaged = true; const k = Math.min(.95, m.t / m.dur + .3); const x = m.x0 + (m.x1 - m.x0) * k, y = m.y0 + (m.y1 - m.y0) * k; W.proj.push({k: 'int', x0: a.x, y0: a.y, x1: x, y1: y, t: 0, dur: Math.max(.3, (k - m.t / m.dur) * m.dur), peak: 40, side: a.side, vs: m, ok: wrand() < .45}); wsound('missile_pass', a.x, a.y, .35); a.cd = 1.1; a.ta = Math.atan2(y - a.y, x - a.x); }
    else if (jet) { jet.engaged = true; const ok = wrand() < (jet.t === 'jet' ? .25 : .5); const lead = {x: jet.x + Math.cos(jet.ang) * UT[jet.t].spd * 8, y: jet.y + Math.sin(jet.ang) * UT[jet.t].spd * 8}; W.proj.push({k: 'int', x0: a.x, y0: a.y, x1: lead.x, y1: lead.y, t: 0, dur: Math.max(1, Math.hypot(lead.x - a.x, lead.y - a.y) / (1000 / 30)), peak: 40, side: a.side, vs: {done: false, jet: ok ? jet : null}, ok}); if (ok && jet.t === 'jet') W.stats.jetsLost++; a.cd = 2.2; }
  }
  // الراجمات: تتجه للهدف وتتهيأ ثم تطلق بالتتابع، ثم تغيّر موقعها حتى لا تُكشف
  for (const m of W.units) {
    if (m.dead || m.t !== 'mlrs' || !m.job) continue;
    const jb = m.job; jb.t += dt;
    if (jb.st === 'aim') { const want = Math.atan2(jb.ty - m.y, jb.tx - m.x); m.ang += Math.max(-.8 * dt, Math.min(.8 * dt, angDiff(m.ang, want))); m.ta = m.ang; if (jb.t > 2.2 && Math.abs(angDiff(m.ang, want)) < .05) { jb.st = 'fire'; jb.t = 0; jb.n = 0; wsound('mlrs', m.x, m.y, .65); } }
    else if (jb.st === 'fire') {
      while (jb.n < jb.count && jb.t >= jb.n * .5) { /* صاروخ كل نصف ثانية (غراد: 40 في 20 ث) */
        const back = UT.mlrs.sz * .3, x0 = m.x - Math.cos(m.ang) * back + (wrand() - .5) * 3, y0 = m.y - Math.sin(m.ang) * back + (wrand() - .5) * 3;
        const tx = jb.tx + (wrand() - .5) * 46, ty = jb.ty + (wrand() - .5) * 46, r = Math.hypot(tx - x0, ty - y0);
        W.proj.push({k: 'rkt', x0, y0, x1: tx, y1: ty, t: 0, dur: 10 + r / KM * 1.5, peak: 120 + r * .08, side: m.side}); /* غراد: نحو 40 ث لـ 20 كم */
        wp('fireball', x0, y0, {s0: 5, s1: 14, life: .3, vr: 0});
        wp('launch_dust', x0, y0, {s0: 12, s1: 52, a0: .75, life: 4.5, vx: 2 + wrand() * 2, vy: -1.5, layer: 'mid'});
        if (jb.n % 2 === 0) wsound('rocket_one', x0, y0, .45);
        jb.n++;
      }
      if (jb.n >= jb.count) { jb.st = 'scoot'; jb.t = 0; m.manual = {x: m.x + (m.id % 2 ? 40 : -40), y: m.y + 25}; }
    } else if (jb.st === 'scoot' && jb.t > 8) { m.job = null; m.manual = null; }
  }
  // صواريخ تركية دورية من خارج الخريطة، ومسيّرة بيرقدار
  W.trMslT -= dt;
  if (W.trMslT <= 0 && !W.trCollapse) { W.trMslT = 240; const tg = densest('iq'); if (tg) { for (let i = 0; i < 4; i++) { const x0 = 1150 + i * 25, y0 = 180, tx = tg.x + (wrand() - .5) * 40, ty = tg.y + (wrand() - .5) * 40, r = Math.hypot(tx - x0, ty - y0); W.proj.push({k: 'bm', x0, y0, x1: tx, y1: ty, t: -i * .8, dur: 70, peak: 300, side: 'tr'}); } wlog('تركيا تطلق 4 صواريخ باليستية على قواتنا', 'tr'); W.stats.trMsl += 4; wsound('real_rockets_in', tg.x, tg.y, .6, 58); } }
  W.droneT -= dt;
  if (W.droneT <= 0 && !W.trCollapse) { W.droneT = 300; const tgs = W.units.filter(v => v.side === 'iq' && ground(v) && v.t === 'tank'); if (tgs.length) { const tg = tgs[Math.floor(wrand() * tgs.length)]; mkUnit('tr', 'drone', tg.x + 60, tg.y - 9 * KM, {drone: tg}); wlog('مسيّرة بيرقدار تركية تتجه نحو دروعنا', 'tr'); wsound('drone', tg.x, tg.y, .4); } }
}
function densest(side){
  let best = null, bn = 0;
  for (const u of W.units) { if (u.side !== side || !ground(u)) continue; let n = 0; for (const v of W.units) if (v.side === side && ground(v) && dist(u, v) < 60) n += UT[v.t].cost; if (n > bn) { bn = n; best = u; } }
  return best ? {x: best.x, y: best.y} : null;
}
// ------------------------------------------------------------------ أوامر اللاعب
function wOrder(k){
  if (!W || W.end) return;
  if (k === 'attack' || k === 'hold' || k === 'retreat') {
    for (const u of W.units) if (u.side === 'iq') { u.manual = null; u.focus = null; }
    if (k === 'attack' && W.phase === 'prep' && W.order === 'attack') { W.t = Math.max(W.t, PREP - .01); wlog('أمر: إنهاء التمهيد وبدء التقدم الآن', 'iq'); }
    else wlog({attack: 'أمر: هجوم شامل', hold: 'أمر: تثبيت المواقع والرد بالنار', retreat: 'أمر: انسحاب منظم إلى خط البداية'}[k], 'iq');
    W.order = k; wsound('radio', W.cam.x, W.cam.y, .35);
  }
  if ((k === 'msl' || k === 'air') && W.aim === k) { W.aim = null; hint(''); syncWarUI(); return; }
  if ((k === 'msl' || k === 'air') && !W.aim && ((k === 'msl' && W.uses.msl > 0 && W.cool.msl <= 0) || (k === 'air' && W.uses.air > 0 && W.cool.air <= 0))) { W.aim = k; hint(k === 'air' ? 'اضغط على الخريطة: هدف الضربة الجوية' : 'اضغط على الخريطة: هدف الراجمات'); syncWarUI(); return; }
  if (k === 'msl-go' && W.uses.msl > 0) {
    const tg = W.aimAt || densest('tr'), L = W.units.filter(u => u.side === 'iq' && u.t === 'mlrs' && !u.dead && !u.job);
    if (tg && L.length) { W.uses.msl--; W.cool.msl = 300; /* إعادة تلقيم الراجمة دقائق */ for (const m of L) m.job = {st: 'aim', t: 0, tx: tg.x, ty: tg.y, count: 6}; W.stats.msl += 6 * L.length; wlog(`الراجمات تتجه نحو الهدف وتتهيأ للإطلاق: ${6 * L.length} صاروخاً`, 'iq'); wsound('radio', W.cam.x, W.cam.y, .35); }
  }
  if (k === 'air-go' && W.uses.air > 0) {
    const tg = W.aimAt || densest('tr');
    if (tg) {
      W.uses.air--; W.cool.air = 360; wlog('ضربة جوية: مقاتلتا F-16 تقتربان على ارتفاع عالٍ وتطلقان من 10 كم', 'iq'); wsound('jet_high', tg.x, tg.y + 300, .5);
      for (let i = 0; i < 2; i++) { const x0 = tg.x - 30 + i * 60, y0 = tg.y + 14 * KM; const rx = tg.x - 20 + i * 40, ry = tg.y + 10 * KM; mkUnit('iq', 'jet', x0, y0 + i * 30, {phase: 'in', rx, ry, tx: tg.x + (i - .5) * 16, ty: tg.y, ang: -Math.PI / 2}); }
    }
  }
  if (k === 'res' && W.uses.res > 0) { W.uses.res--; const c = [[1220, 1085], [1180, 830], [1165, 670]]; for (const [t, dx] of [['tank', -28], ['tank', 8], ['tank', 44], ['ifv', -10], ['squad', -28], ['squad', 28]]) { const u = mkUnit('iq', t, 1240 + dx, 1420 + (t === 'squad' ? 36 : 0), {grp: 'الاحتياط', path: c.map(([x, y]) => ({x: x + dx * .4, y}))}); u.start = {x: u.x, y: u.y}; } wlog('دفع الاحتياط: 3 دبابات ومدرعة وفصيلا مشاة', 'iq'); }
  syncWarUI();
}
function syncWarUI(){
  const mmss = s => s >= 60 ? `${Math.floor(s / 60)}:${String(Math.ceil(s % 60)).padStart(2, '0')} د` : `${Math.ceil(s)} ث`;
  const set = (id, txt, dis) => { const b = document.getElementById(id); if (b) { b.querySelector('small').textContent = txt; b.disabled = dis; } };
  set('wo-air', W.uses.air ? (W.cool.air > 0 ? `بعد ${mmss(W.cool.air)}` : `باقي ${W.uses.air}`) : 'نفدت', !W.uses.air || W.cool.air > 0);
  set('wo-msl', W.uses.msl ? (W.cool.msl > 0 ? `بعد ${mmss(W.cool.msl)}` : `باقي ${W.uses.msl}`) : 'نفدت', !W.uses.msl || W.cool.msl > 0);
  set('wo-res', W.uses.res ? '6 وحدات' : 'استُخدم', !W.uses.res);
  set('wo-attack', W.phase === 'prep' && W.order === 'attack' ? `تمهيد ${mmss(PREP - W.t)}` : 'تقدم', false);
  for (const k of ['attack', 'hold', 'retreat']) { const b = document.getElementById('wo-' + k); if (b) b.classList.toggle('on', W.order === k); }
  for (const k of ['air', 'msl']) { const b = document.getElementById('wo-' + k); b.classList.toggle('on', W.aim === k); if (W.aim === k) b.disabled = false; }
  W.sel = W.sel.filter(id => W.units.some(u => u.id === id && !u.dead)); selUI();
  const m = Math.floor(W.t / 60), s = Math.floor(W.t % 60);
  document.getElementById('wtime').textContent = `${m}:${String(s).padStart(2, '0')} / ${BATTLE / 60}:00`;
  const cnt = side => W.units.filter(u => u.side === side && !u.dead && u.t === 'tank').length;
  document.getElementById('wforce').innerHTML = `<span style="color:var(--mine)">دبابات ${cnt('iq')}</span> · <span style="color:#e07b6e">${cnt('tr')} دبابات</span>`;
  document.getElementById('wobj').innerHTML = TOWNS.filter(t => t.obj).map(t => `<div class="wob"><span>${t.n}</span><div class="meter"><i style="width:${W.ctl[t.id]}%;background:var(--mine)"></i></div></div>`).join('');
}
function endWar(kind){
  W.end = kind; stopLoops(); play(kind === 'win' ? 'victory' : 'defeat', {vol: .7, rate: 1});
  const L = s => Object.entries(W.stats[s].lost).map(([t, n]) => `${n} ${NAME[t]}`).join('، ') || 'لا شيء';
  const title = {win: 'نصر: دهوك تحت سيطرتك', lose: 'فشل الهجوم: قواتنا انهارت', time: 'انتهى الوقت دون حسم'}[kind];
  const got = TOWNS.filter(t => t.obj && W.ctl[t.id] >= 100).map(t => t.n);
  document.getElementById('wres').innerHTML = `<div class="mbox"><h3>${title}</h3>
    <div class="delta"><b style="color:var(--mine)">${got.length}</b><span>مدن سيطرنا عليها<small>${got.join('، ') || 'لا شيء'}</small></span></div>
    <div class="delta"><b style="color:var(--bad)">−</b><span>خسائرنا<small>${L('iq')}</small></span></div>
    <div class="delta"><b style="color:var(--good)">+</b><span>خسائر العدو<small>${L('tr')}</small></span></div>
    <div class="delta"><b>${W.stats.msl}</b><span>صواريخ أطلقناها<small>والعدو أطلق ${W.stats.trMsl}، و${W.stats.jetsLost ? W.stats.jetsLost + ' مقاتلة لنا أُسقطت' : 'لم نخسر مقاتلات'}</small></span></div>
    <p class="tag" style="text-align:right">في اللعبة الحقيقية: المدن المأخوذة تنتقل إليك على الخريطة، والخسائر تُخصم من جيشك، والصواريخ من مخزونك.</p>
    <div class="act"><div class="btn"><button class="pri" onclick="startWar()">أعد المعركة</button><small>نفس الظروف</small></div><div class="btn"><button onclick="closeWar()">رجوع للخريطة</button><small></small></div></div></div>`;
  document.getElementById('wres').classList.add('on');
}

// ------------------------------------------------------------------ الرسم
const wc = () => document.getElementById('wc');
let wctx = null;
let WDPR = Math.min(devicePixelRatio || 1, 1.75), fpsN = 0, fpsT = 0, lowN = 0;
function wResize(){ const c = wc(), r = c.getBoundingClientRect(), d = WDPR; c.width = r.width * d; c.height = r.height * d; wctx = c.getContext('2d'); wctx.setTransform(d, 0, 0, d, 0, 0); }
const ADDW = {fireball: 1, sparks: 1, muzzle: 1, exhaust: 1, intercept: 1, tracers: 1, ground_fire: 1, rifle_flash: 1, vehicle_fire: 1, flare: 1, armor_sparks: 1, tank_fire: 1};
function img(k){ return WS[k] || VI[k]; }
const SHD = {};
function shadowOf(k){ if (SHD[k]) return SHD[k]; const im = img(k); if (!im || !im.complete || !im.width) return null; const cv = document.createElement('canvas'); cv.width = im.width; cv.height = im.height; const x = cv.getContext('2d'); x.drawImage(im, 0, 0); x.globalCompositeOperation = 'source-in'; x.fillStyle = '#000'; x.fillRect(0, 0, cv.width, cv.height); SHD[k] = cv; return cv; }
function shade(c, k, x, y, s, rot, a, oy = 0){ const sh = shadowOf(k); if (!sh) return; const w = s * sh.width / Math.max(sh.width, sh.height), h = s * sh.height / Math.max(sh.width, sh.height); c.save(); c.translate(x, y); c.rotate(rot); c.globalAlpha = a; c.drawImage(sh, -w / 2, -h / 2 + oy, w, h); c.restore(); }
function drawWar(dt){
  const c = wctx, Wd = wc().clientWidth, Hd = wc().clientHeight, cam = W.cam;
  if (W.follow) { const f = W.units.filter(u => u.side === 'iq' && ground(u) && (u.t === 'tank' || u.t === 'ifv' || u.t === 'squad')); if (f.length) { const ty = Math.min(...f.map(u => u.y)) + 70, tx = f.reduce((s, u) => s + u.x, 0) / f.length; cam.x += (tx - cam.x) * Math.min(1, dt * .8); cam.y += (ty - cam.y) * Math.min(1, dt * .8); } }
  c.fillStyle = '#1a1712'; c.fillRect(0, 0, Wd, Hd);
  c.save(); c.translate(Wd / 2, Hd / 2); c.scale(cam.k, cam.k); c.translate(-cam.x, -cam.y);
  drawMapTiles(c, cam, Wd, Hd);
  const vis = (x, y, m = 80) => Math.abs(x - cam.x) * cam.k < Wd / 2 + m * cam.k && Math.abs(y - cam.y) * cam.k < Hd / 2 + m * cam.k;
  const spr = (k, x, y, s, rot, a = 1, comp, oy = 0) => { const im = img(k); if (!im || !im.complete || !im.width) return; const w = s * im.width / Math.max(im.width, im.height), h = s * im.height / Math.max(im.width, im.height); c.save(); c.translate(x, y); c.rotate(rot); c.globalAlpha = a; if (comp) c.globalCompositeOperation = comp; c.drawImage(im, -w / 2, -h / 2 + oy, w, h); c.restore(); };
  // جسم طائر: ظله على الأرض يبتعد كلما ارتفع، وهو يكبر قليلاً
  const airSpr = (k, x, y, s, rot, alt, a = 1) => { shade(c, k, x + alt * .35, y + alt * .55, s, rot, .22); spr(k, x, y, s * (1 + alt / 420), rot, a); };
  if (false) for (const f of GROUND.flora) if (vis(f[0], f[1], 10)) { const k = FLORA_K[f[2]], s = FLORA_S[f[2]]; if (cam.k > 3) shade(c, k, f[0] + s * .25, f[1] + s * .35, s, 0, .32); spr(k, f[0], f[1], s, (f[0] * 7 + f[1]) % 6.28); }
  for (const p of W.props) if (vis(p.x, p.y)) { shade(c, p.k, p.x + 1.2, p.y + 1.6, p.s, p.rot, .3); spr(p.k, p.x, p.y, p.s, p.rot); }
  for (const d of W.decals) if (vis(d.x, d.y)) {
    if (d.k === 'hulk') { spr(d.spr, d.x, d.y, d.s, d.rot, 1, null, d.off || 0); shade(c, d.spr, d.x, d.y, d.s, d.rot, .62, d.off || 0); }
    else spr(d.k, d.x, d.y, d.s, d.rot, d.a);
  }
  // وميض الانفجار يضيء الأرض حوله لحظة
  if (W.flashes) { c.globalCompositeOperation = 'lighter'; for (const f of W.flashes) { f.t -= dt; if (f.t <= 0 || !vis(f.x, f.y)) continue; const g = c.createRadialGradient(f.x, f.y, 0, f.x, f.y, f.r); g.addColorStop(0, `rgba(255,170,80,${f.t * 1.6})`); g.addColorStop(1, 'rgba(255,120,40,0)'); c.fillStyle = g; c.fillRect(f.x - f.r, f.y - f.r, f.r * 2, f.r * 2); } c.globalCompositeOperation = 'source-over'; W.flashes = W.flashes.filter(f => f.t > 0); }
  drawWParts(dt, 'mid');
  // الوحدات الأرضية
  for (const u of W.units) {
    if (!ground(u) || u.gone || !vis(u.x, u.y)) continue;
    const d = UT[u.t], s = d.sz, T = u.t === 'tank' && TANKS[u.spr];
    // هالة داكنة تفصل الوحدة عن ألوان الأرض
    c.globalAlpha = .5; c.drawImage(HALO, u.x - s * .7 + .6, u.y - s * .7 + .8, s * 1.4, s * 1.4); c.globalAlpha = 1;
    if (T) {
      // هيكل الدبابة ثم برجها، البرج يدور حول حلقته ويرتد عند الإطلاق
      const rx = u.x + Math.cos(u.ang) * T.ringY * s, ry = u.y + Math.sin(u.ang) * T.ringY * s, ts = s * T.turS;
      shade(c, T.hull, u.x + 1.6, u.y + 2.2, s, u.ang + Math.PI / 2, .38);
      spr(T.hull, u.x, u.y, s, u.ang + Math.PI / 2, u.retreat ? .85 : 1);
      shade(c, T.tur, rx + 1.8, ry + 2.4, ts, u.ta + Math.PI / 2, .3, T.pivY * ts + u.recoil * 1.2);
      spr(T.tur, rx, ry, ts, u.ta + Math.PI / 2, 1, null, T.pivY * ts + u.recoil * 1.2);
      const sh = slopeShade(u.x, u.y); if (sh < .6) shade(c, T.hull, u.x, u.y, s, u.ang + Math.PI / 2, (.6 - sh) * .9);
    } else {
      shade(c, u.spr, u.x + 1.6, u.y + 2.2, s, u.ang + Math.PI / 2, .35);
      spr(u.spr, u.x, u.y, s, u.ang + Math.PI / 2, d.inf && u.sup > 55 ? .8 : u.retreat ? .85 : 1);
    }
  }
  for (const u of W.units) if (W.sel && W.sel.includes(u.id) && !u.dead) {
    c.strokeStyle = 'rgba(255,230,150,.95)'; c.lineWidth = 1.6 / cam.k; c.beginPath(); c.arc(u.x, u.y, UT[u.t].sz * .7, 0, 7); c.stroke();
    if (u.manual) { const f = u.focus && W.units.find(v => v.id === u.focus && !v.dead); const g = f || u.manual; c.setLineDash([4 / cam.k, 4 / cam.k]); c.strokeStyle = f ? 'rgba(230,90,70,.9)' : 'rgba(255,230,150,.7)'; c.beginPath(); c.moveTo(u.x, u.y); c.lineTo(g.x, g.y); c.stroke(); c.setLineDash([]); }
  }
  // البرج الطائر
  for (const f of W.fly) airSpr(f.spr, f.x, f.y, f.s, f.rot, f.alt);
  // المقذوفات
  for (const p of W.proj) {
    if (p.t < 0 || p.done) continue;
    const q = projPos(p), x = q.x, y = q.y;
    if (p.k === 'tracer' || p.k === 'shell') {
      const sh = p.k === 'shell', L = sh ? 12 : 7, r = Math.hypot(p.x1 - p.x0, p.y1 - p.y0) || 1, ux = (p.x1 - p.x0) / r, uy = (p.y1 - p.y0) / r;
      c.lineCap = 'round'; c.globalCompositeOperation = 'lighter';
      c.strokeStyle = sh ? 'rgba(255,200,120,.4)' : (p.side === 'iq' ? 'rgba(255,180,60,.45)' : 'rgba(255,90,60,.5)'); c.lineWidth = sh ? 3.6 : 2.4;
      c.beginPath(); c.moveTo(x - ux * L, y - uy * L); c.lineTo(x, y); c.stroke();
      c.strokeStyle = sh ? 'rgba(255,250,230,1)' : (p.side === 'iq' ? 'rgba(255,225,150,1)' : 'rgba(255,170,130,1)'); c.lineWidth = sh ? 1.4 : 1;
      c.beginPath(); c.moveTo(x - ux * L * .8, y - uy * L * .8); c.lineTo(x, y); c.stroke();
      c.lineCap = 'butt'; c.globalCompositeOperation = 'source-over';
    } else if (p.k === 'arty') {
      // قذيفة المدفعية: نقطة مضيئة صغيرة عالية وظلها على الأرض
      c.fillStyle = 'rgba(0,0,0,.25)'; c.beginPath(); c.arc(x + q.alt * .35, y + q.alt * .55, 1.2, 0, 7); c.fill();
      c.fillStyle = 'rgba(255,236,190,.95)'; c.beginPath(); c.arc(x, y, .8 + q.alt / 400, 0, 7); c.fill();
    } else if (p.k === 'bullet') {
    } else {
      // صواريخ: صورة الصاروخ الحقيقية، ولهب المحرك، وخط دخان
      const kp = Math.max(0, q.k - .02), px = p.x0 + (p.x1 - p.x0) * kp, py = p.y0 + (p.y1 - p.y0) * kp;
      const ang = Math.atan2(y - py, x - px) || Math.atan2(p.y1 - p.y0, p.x1 - p.x0);
      const wob = p.k === 'atgm' ? Math.sin(p.t * 16) * 1.2 : 0, nx = -Math.sin(ang) * wob, ny = Math.cos(ang) * wob;
      const key = {atgm: 'm_atgm', hrkt: 'm_rkt', rkt: 'm_rkt', bm: 'm_bm', agm: 'm_ag', int: 'm_rkt'}[p.k];
      const size = {atgm: 5, hrkt: 4.5, rkt: 7, bm: 13, agm: 8, int: 5}[p.k];
      const burning = p.k === 'agm' ? p.t >= p.drop : p.k === 'rkt' ? q.k < .5 : p.k === 'bm' ? q.k < .7 : true;
      const X = x + nx, Y = y + ny, S = Math.max(size * (1 + q.alt / 420), 9 / cam.k), bx = X - Math.cos(ang) * S * .55, by = Y - Math.sin(ang) * S * .55;
      if (burning) { const lx = p.lx ?? bx, ly = p.ly ?? by, n = Math.min(5, 1 + Math.ceil(Math.hypot(bx - lx, by - ly) / (S * .5))); for (let i = 0; i < n; i++) wp('smoke_light', lx + (bx - lx) * i / n, ly + (by - ly) * i / n, {s0: S * .4, s1: S * (p.k === 'bm' ? 2.2 : 1.6), a0: .45, life: p.k === 'bm' || p.k === 'rkt' ? 3 : 1.6, vx: 1.5, vy: -1, layer: 'top'}); } p.lx = bx; p.ly = by;
      if (false) wp('smoke_light', bx, by, {s0: S * .4, s1: S * (p.k === 'bm' ? 2.2 : 1.6), a0: .5, life: p.k === 'bm' || p.k === 'rkt' ? 3 : 1.6, vx: 1.5, vy: -1, layer: 'top'});
      if (q.alt > 1) shade(c, key, x + q.alt * .35, y + q.alt * .55, size, ang + Math.PI / 2, .2);
      spr(key, X, Y, S, ang + Math.PI / 2);
      if (burning) { spr('exhaust', bx - Math.cos(ang) * S * .2, by - Math.sin(ang) * S * .2, S * 1.2, ang - Math.PI / 2, 1, 'lighter'); spr('flare', bx, by, S * .9, 0, .8, 'lighter'); }
    }
  }
  // الطائرات والمروحيات والمسيّرات بارتفاعها وظلها
  for (const u of W.units) {
    if ((u.dead && !(u.falling > 0)) || u.gone || !UT[u.t].air) continue;
    const d = UT[u.t];
    airSpr(u.spr, u.x, u.y, d.sz, u.ang + Math.PI / 2, u.alt);
    if (u.t === 'heli') {
      // المروحة تدور: قرص شفاف وشفرات تومض
      const R = d.sz * .52 * (1 + u.alt / 420), ra = W.t * 31 + u.id;
      c.save(); c.translate(u.x, u.y - d.sz * .08);
      c.fillStyle = 'rgba(20,20,20,.12)'; c.beginPath(); c.arc(0, 0, R, 0, 7); c.fill();
      c.strokeStyle = 'rgba(25,25,25,.55)'; c.lineWidth = .9;
      for (let b = 0; b < 5; b++) { const a = ra + b * Math.PI * 2 / 5; c.beginPath(); c.moveTo(0, 0); c.lineTo(Math.cos(a) * R, Math.sin(a) * R); c.stroke(); }
      c.restore();
    }
  }
  drawWParts(dt, 'top');
  c.restore();
  // علامات الوحدات على الشاشة: نقطة الطرف، وشريط القوة للمصاب أو المحدد
  for (const u of W.units) {
    if (u.dead || u.gone || u.t === 'jet' || u.t === 'drone' || u.t === 'recon') continue;
    const d = UT[u.t], sx = (u.x - cam.x) * cam.k + Wd / 2, sy = (u.y - cam.y) * cam.k + Hd / 2, R = d.sz * cam.k * .5;
    if (sx < -20 || sx > Wd + 20 || sy < -20 || sy > Hd + 20) continue;
    c.fillStyle = u.side === 'iq' ? '#e2b04f' : '#d0473b'; c.strokeStyle = 'rgba(0,0,0,.6)'; c.lineWidth = 1;
    c.beginPath(); c.arc(sx - R * .75, sy - R * .75, 2.6, 0, 7); c.fill(); c.stroke();
    if (u.hp < d.hp || (W.sel && W.sel.includes(u.id))) { const bw = 16; c.fillStyle = 'rgba(0,0,0,.65)'; c.fillRect(sx - bw / 2 - 1, sy + R + 2, bw + 2, 4); c.fillStyle = u.hp > d.hp * .5 ? '#5fae7b' : '#d4574a'; c.fillRect(sx - bw / 2, sy + R + 3, bw * u.hp / d.hp, 2); }
  }
  c.font = '700 13px "IBM Plex Sans Arabic", sans-serif'; c.textAlign = 'center'; c.direction = 'rtl';
  for (const tw of TOWNS) {
    const sx = (tw.x - cam.x) * cam.k + Wd / 2, sy = (tw.y - cam.y) * cam.k + Hd / 2; if (sx < -60 || sx > Wd + 60 || sy < -40 || sy > Hd + 40) continue;
    const y = sy - tw.r * cam.k - 8;
    c.lineWidth = 4; c.strokeStyle = 'rgba(5,9,13,.85)'; c.fillStyle = '#f3ede0'; c.strokeText(tw.n, sx, y); c.fillText(tw.n, sx, y);
    if (tw.obj) { const v = W.ctl[tw.id] / 100; c.fillStyle = 'rgba(5,9,13,.85)'; c.fillRect(sx - 26, y + 5, 52, 7); c.fillStyle = '#c0473b'; c.fillRect(sx - 25, y + 6, 50, 5); c.fillStyle = '#d2a24c'; c.fillRect(sx - 25, y + 6, 50 * v, 5); c.setLineDash([4, 4]); c.strokeStyle = 'rgba(243,237,224,.35)'; c.lineWidth = 1; c.beginPath(); c.arc(sx, sy, tw.r * cam.k, 0, 7); c.stroke(); c.setLineDash([]); }
  }
}
const PL = {};
// ظل ناعم يتلاشى للخارج تحت كل وحدة (يُرسم مرة واحدة ويُعاد استعماله)
const HALO = (() => { const c = document.createElement('canvas'); c.width = c.height = 64; const x = c.getContext('2d'), g = x.createRadialGradient(32, 32, 4, 32, 32, 32); g.addColorStop(0, 'rgba(10,8,6,.85)'); g.addColorStop(.55, 'rgba(10,8,6,.45)'); g.addColorStop(1, 'rgba(10,8,6,0)'); x.fillStyle = g; x.fillRect(0, 0, 64, 64); return c; })();
function drawWParts(dt, layer){
  const c = wctx, M = c.getTransform(), cv = wc(), hw = Math.ceil(cv.width / 2), hh = Math.ceil(cv.height / 2), cam = W.cam;
  let off = PL[layer]; if (!off) off = PL[layer] = document.createElement('canvas'); if (off.width !== hw || off.height !== hh) { off.width = hw; off.height = hh; }
  const o = off.getContext('2d'); o.setTransform(1, 0, 0, 1, 0, 0); o.clearRect(0, 0, hw, hh);
  const vw = cv.clientWidth / 2 / cam.k, vh = cv.clientHeight / 2 / cam.k, maxS = 520 / cam.k;   // لا تكبر النفثة أكثر من 520 بكسل على الشاشة
  let any = false; const add = [];
  for (const p of W.parts) {
    if (p.layer !== layer) continue;
    if (p.delay > 0) { p.delay -= dt; continue; }
    p.t += dt; const k = p.t / p.life; if (k >= 1) continue;
    const e = 1 - Math.pow(1 - k, 2); p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.vr * dt;
    let sz = p.s0 + (p.s1 - p.s0) * e; const al = p.a0 + (p.a1 - p.a0) * k; const im = img(p.img); if (!im || !im.complete || al <= 0) continue;
    if (Math.abs(p.x - cam.x) > vw + sz || Math.abs(p.y - cam.y) > vh + sz) continue;   // خارج الشاشة
    sz = Math.min(sz, maxS);
    if (ADDW[p.img]) { add.push(p, sz, al, im); continue; }
    any = true;
    const cs = Math.cos(p.rot), sn = Math.sin(p.rot), A = M.a / 2, B = M.b / 2, C = M.c / 2, D = M.d / 2, E = M.e / 2, F = M.f / 2;
    o.globalAlpha = Math.max(0, Math.min(1, al));
    o.setTransform(A * cs + C * sn, B * cs + D * sn, C * cs - A * sn, D * cs - B * sn, A * p.x + C * p.y + E, B * p.x + D * p.y + F); o.drawImage(im, -sz / 2, -sz / 2, sz, sz);
  }
  if (any) { c.setTransform(1, 0, 0, 1, 0, 0); c.globalAlpha = 1; c.drawImage(off, 0, 0, cv.width, cv.height); }
  c.globalCompositeOperation = 'lighter';
  for (let i = 0; i < add.length; i += 4) {
    const p = add[i], sz = add[i + 1], cs = Math.cos(p.rot), sn = Math.sin(p.rot);
    c.globalAlpha = Math.max(0, Math.min(1, add[i + 2]));
    c.setTransform(M.a * cs + M.c * sn, M.b * cs + M.d * sn, M.c * cs - M.a * sn, M.d * cs - M.b * sn, M.a * p.x + M.c * p.y + M.e, M.b * p.x + M.d * p.y + M.f); c.drawImage(add[i + 3], -sz / 2, -sz / 2, sz, sz);
  }
  c.setTransform(M); c.globalAlpha = 1; c.globalCompositeOperation = 'source-over';
  if (layer === 'top') W.parts = W.parts.filter(p => p.delay > 0 || p.t < p.life);
}

// ------------------------------------------------------------------ أصوات المحركات بحسب قربها من الكاميرا
function engineSounds(){
  if (!W || typeof actx === 'undefined' || !actx) return;
  const c = W.cam, R = innerWidth / c.k * .7;
  const near = f => { let best = 1e9; for (const u of W.units) if (!u.dead && f(u)) best = Math.min(best, Math.hypot(u.x - c.x, u.y - c.y)); return Math.max(0, 1 - best / R); };
  const set = (k, v) => { const L = LOOPS[k]; if (L) L.g.gain.setTargetAtTime(v, actx.currentTime, .4); };
  set('tank_pass', .55 * near(u => u.moving && (u.t === 'tank' || u.t === 'ifv')));
  set('tank_idle', .35 * near(u => !u.moving && u.t === 'tank'));
  set('track_loop', .45 * near(u => u.moving && (u.t === 'tank' || u.t === 'ifv')));
  set('wheeled', .35 * near(u => u.moving && (u.t === 'arty' || u.t === 'mlrs' || u.t === 'ad')));
  // صيحات الجنود حين يكون المشاة في اشتباك قريب من الكاميرا
  if (Math.random() < .05 && near(u => UT[u.t].inf && W.t - u.lastShot < 2) > .5) play('shouts', {vol: .28});
  set('tank_tracks', .08 + .2 * near(u => u.moving && UT[u.t].veh));
  set('footsteps', .3 * near(u => u.moving && UT[u.t].inf));
  set('helicopter', .06 + .5 * near(u => u.t === 'heli'));
  set('jet_high', .6 * near(u => u.t === 'jet'));
  { let best = null, bd = 1e12; for (const u of W.units) if (u.t === 'jet' && !u.dead) { const d = listenerDist(u.x, u.y); if (d < bd) { bd = d; best = u; } }
    const L = LOOPS.jet_high; if (best && L && L.src) { const pd = W.jetPrevD ?? bd, pt = W.jetPrevT ?? W.t, dtg = Math.max(.01, W.t - pt), vr = (bd - pd) / dtg; L.src.playbackRate.setTargetAtTime(Math.max(.7, Math.min(1.45, 343 / (343 + vr))), actx.currentTime, .2); W.jetPrevD = bd; W.jetPrevT = W.t; } else { W.jetPrevD = null; W.jetPrevT = null; } }
}

// ------------------------------------------------------------------ الحلقة والتحكم
function warLoop(now){
  const cv = wc(); if (cv && (Math.abs(cv.width - cv.clientWidth * WDPR) > 2 || Math.abs(cv.height - cv.clientHeight * WDPR) > 2)) wResize();
  const real = Math.min(.05, (now - wlast) / 1000); wlast = now;
  const dt = real * wspeed;
  if (W && !W.end && wspeed > 0) { let left = dt; while (left > 0) { const s = Math.min(wspeed > 8 ? .12 : .05, left); stepWar(s); left -= s; } }
  if (W) { (C2MODE ? drawC2 : drawWar)(real * (wspeed || 0) || 0.0001); if ((W.uiT = (W.uiT || 0) - real) <= 0) { W.uiT = .25; syncWarUI(); engineSounds(); } }
  fpsN++; fpsT += real;
  if (fpsT >= 1) { const f = Math.round(fpsN / fpsT), el = document.getElementById('wfps'); if (el) { el.textContent = f + ' fps'; el.style.color = f >= 55 ? '#6fbf86' : f >= 40 ? '#e2b04f' : '#e0705f'; } if (f < 45) lowN++; else lowN = 0; if (lowN >= 3 && WDPR > 1) { WDPR = Math.max(1, WDPR - .25); wResize(); lowN = 0; } fpsN = 0; fpsT = 0; }
  wraf = requestAnimationFrame(warLoop);
}
function startWar(){
  document.getElementById('wres').classList.remove('on');
  stopLoops(); setupWar(); wspeed = 4; document.querySelectorAll('[data-wsp]').forEach(x => x.classList.toggle('on', x.dataset.wsp === '4'));
  audioInit(); ['front_ambience','tank_tracks','tank_close','footsteps','tank_cannon','hmg','hmg2','ak47','rifle','artillery','artillery2','explosion_big','explosion_med','explosion_med2','intercept','missile_pass','mlrs','jet_flyby','jet_high','drone','helicopter','war_horn','victory','defeat','atgm_launch','missile_fly','jet_release','armor_hit','ricochet','debris','rocket_one','incoming','rocket_salvo','heli_gun','cookoff','radio','smoke_pop','missile_alert','ak_close','ak_far','pkm_close','mg_far','m2','g3','sniper2','cannon30','tank_close_shot','tank_far_shot','mortar_launch','mortar_in','arty_far','cracks','metal_hits','ricochet2','rocket_one2','mlrs_far','boom_echo','boom_close','arty_c1','arty_c2','arty_c3','cannon_real','arty_f1','arty_f2','arty_f3','mort_1','mort_2','mort_3','mort_4','mort_t','rpg_real','rico_1','rico_2','bullet_crack','jet_pass','range_blast','track_loop','helicopter_chinook','real_battle','real_tank','real_strike','real_rockets_in','real_hmg','real_bursts','shouts','tank_idle','wheeled','grenade','rpg2','tank_pass'].forEach(k => setTimeout(() => load(k), 5));
  setTimeout(() => { sloop('front_ambience', .25); sloop('tank_tracks', .08); sloop('tank_pass', 0); sloop('track_loop', 0); sloop('tank_idle', 0); sloop('wheeled', 0); sloop('real_battle', .16); sloop('footsteps', 0); sloop('helicopter', .06); sloop('jet_high', 0); }, 600);
  wResize(); syncWarUI();
}
function war(){ document.getElementById('war').classList.add('on'); startWar(); cancelAnimationFrame(wraf); wlast = performance.now(); wraf = requestAnimationFrame(warLoop); }
function closeWar(){ document.getElementById('war').classList.remove('on'); document.getElementById('wres').classList.remove('on'); cancelAnimationFrame(wraf); stopLoops(); W = null; }
addEventListener('resize', () => { if (W) wResize(); });
// لمس: نقرة = تحديد أو أمر، وسحب = تحريك الكاميرا، وإصبعان = تكبير
(function(){
  const pts = new Map(); let pinch = 0, last = null;
  const c = wc();
  let down = null, moved = 0;
  c.addEventListener('pointerdown', e => { c.setPointerCapture(e.pointerId); pts.set(e.pointerId, e); last = e; if (pts.size === 1) { down = {x: e.clientX, y: e.clientY, t: performance.now()}; moved = 0; } if (pts.size === 2) { const [a, b] = [...pts.values()]; pinch = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY); } });
  c.addEventListener('pointermove', e => { if (!W || !pts.has(e.pointerId)) return; pts.set(e.pointerId, e);
    if (pts.size === 2 && pinch) { const [a, b] = [...pts.values()]; const d = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY); W.cam.k = Math.max(.4, Math.min(6, W.cam.k * d / pinch)); pinch = d; W.follow = false; moved = 99; return; }
    moved += Math.abs(e.clientX - last.clientX) + Math.abs(e.clientY - last.clientY);
    if (moved < 10) { last = e; return; }
    W.cam.x -= (e.clientX - last.clientX) / W.cam.k; W.cam.y -= (e.clientY - last.clientY) / W.cam.k; last = e; W.follow = false; document.getElementById('wfollow').classList.remove('on'); });
  c.addEventListener('pointerup', e => { pts.delete(e.pointerId); if (pts.size < 2) pinch = 0; if (down && moved < 10 && performance.now() - down.t < 600 && pts.size === 0) { const r = c.getBoundingClientRect(); wTap(e.clientX - r.left, e.clientY - r.top); } if (pts.size === 0) down = null; });
  c.addEventListener('pointercancel', e => { pts.delete(e.pointerId); pinch = 0; });
  c.addEventListener('wheel', e => { e.preventDefault(); if (W) { W.cam.k = Math.max(.4, Math.min(6, W.cam.k * (e.deltaY < 0 ? 1.15 : 1 / 1.15))); } }, {passive: false});
})();
document.querySelectorAll('[data-wsp]').forEach(b => b.onclick = () => { wspeed = +b.dataset.wsp; document.querySelectorAll('[data-wsp]').forEach(x => x.classList.toggle('on', x === b)); });
document.getElementById('wfollow').onclick = () => { if (W) { W.follow = !W.follow; document.getElementById('wfollow').classList.toggle('on', W.follow); } };
document.getElementById('wzin').onclick = () => { if (W) W.cam.k = Math.min(6, W.cam.k * 1.4); };
document.getElementById('wzout').onclick = () => { if (W) W.cam.k = Math.max(.4, W.cam.k / 1.4); };
document.getElementById('wclose').onclick = closeWar;
document.getElementById('wquick').onclick = () => { if (!W || W.end) return; let n = 0; while (!W.end && n < 20000) { stepWar(.15); n++; } };

// ------------------------------------------------------------------ التحكم المباشر: تحديد وحدة ثم أمرها
function hint(t){ const el = document.getElementById('whint'); el.textContent = t; el.hidden = !t; }
function wTap(sx, sy){
  if (!W || W.end) return;
  const cv = wc(), x = (sx - cv.clientWidth / 2) / W.cam.k + W.cam.x, y = (sy - cv.clientHeight / 2) / W.cam.k + W.cam.y;
  if (W.aim) { W.aimAt = {x, y}; const k = W.aim; W.aim = null; hint(''); wOrder(k + '-go'); W.aimAt = null; wp('flare', x, y, {s0: 8, s1: 24, life: .8}); return; }
  const R = Math.max(10, 20 / W.cam.k);
  let hitU = null, bd = R;
  for (const u of W.units) { if (u.dead || u.t === 'jet' || u.t === 'drone' || u.t === 'recon') continue; const r = Math.hypot(u.x - x, u.y - y); if (r < bd) { bd = r; hitU = u; } }
  if (hitU && hitU.side === 'iq') {
    if (W.sel.length === 1 && W.sel[0] === hitU.id && hitU.grp) W.sel = W.units.filter(u => u.side === 'iq' && !u.dead && u.grp === hitU.grp).map(u => u.id);
    else W.sel = [hitU.id];
    selUI(); return;
  }
  if (!W.sel.length) return;
  const sel = W.units.filter(u => W.sel.includes(u.id) && !u.dead);
  wsound('radio', W.cam.x, W.cam.y, .25);
  if (hitU && hitU.side === 'tr') {
    for (const u of sel) { u.focus = hitU.id; u.manual = {x: hitU.x, y: hitU.y}; }
    wlog(`أمر: ${sel.length > 1 ? sel.length + ' وحدات تهاجم' : NAME[sel[0].t] + ' تهاجم'} ${NAME[hitU.t]} للعدو`, 'iq');
  } else {
    const cx = sel.reduce((s, u) => s + u.x, 0) / sel.length, cy = sel.reduce((s, u) => s + u.y, 0) / sel.length;
    for (const u of sel) { u.focus = null; u.manual = {x: x + (u.x - cx) * .7, y: y + (u.y - cy) * .7}; }
    wp('flare', x, y, {s0: 5, s1: 14, life: .6});
    wlog(`أمر: ${sel.length > 1 ? sel.length + ' وحدات تتحرك' : NAME[sel[0].t] + ' تتحرك'} إلى النقطة المحددة`, 'iq');
  }
}
function selUI(){
  const box = document.getElementById('wsel'), sel = W.units.filter(u => W.sel.includes(u.id) && !u.dead);
  if (!sel.length) { box.hidden = true; return; }
  box.hidden = false;
  const u = sel[0], d = UT[u.t];
  document.getElementById('wsel-t').textContent = sel.length > 1 ? `${sel.length} وحدات · مجموعة ${u.grp || ''}` : `${NAME[u.t]} · قوة ${Math.round(u.hp / d.hp * 100)}% · معنويات ${Math.round(u.mor)}${u.sup > 55 ? ' · تحت النار' : ''}`;
  document.getElementById('wsel-s').textContent = sel.length > 1 ? 'اضغط مكاناً للتحرك أو عدواً للهجوم' : `المدى ${(d.rng / KM).toFixed(1)} كم · اضغط مكاناً أو عدواً · اضغطها ثانية لتحديد مجموعتها`;
}
document.getElementById('wsel-x').onclick = () => { if (W) { W.sel = []; selUI(); } };
document.getElementById('wsel-free').onclick = () => { if (W) { for (const u of W.units) if (W.sel.includes(u.id)) { u.manual = null; u.focus = null; } W.sel = []; selUI(); wlog('الوحدات المحددة تعود للخطة', 'iq'); } };
// ================================================================== شاشة غرفة القيادة: خريطة القمر الحقيقية ورموز عسكرية قياسية (نظام الناتو APP-6)
// قواتنا: مستطيل أزرق. العدو: معيّن أحمر. العدو لا يظهر إلا إذا رأته قواتنا، وإلا يبقى آخر موقع معروف له باهتاً.
let C2MODE = false;
const C2 = {friend: '#7fd3f7', friendFill: 'rgba(128,224,255,.92)', hostile: '#ff6b5e', hostileFill: 'rgba(255,128,128,.92)', ink: '#06121a', grid: 'rgba(160,220,255,.16)', gridTxt: 'rgba(190,230,255,.55)'};
// من يرى العدو؟ نحسبها مرتين في الثانية
function c2Visibility(){
  if ((W.visT = (W.visT || 0) - .05) > 0) return; W.visT = .5;
  for (const v of W.units) {
    if (v.side !== 'tr' || v.dead || v.t === 'jet') continue;
    const air = UT[v.t].air;
    v.vis = air ? W.units.some(u => u.side === 'iq' && !u.dead && dist(u, v) < 8 * KM) : spotted('iq', v);
    if (v.vis) v.last = {x: v.x, y: v.y, t: W.t};
  }
}
// علامة الانفجار والإصابة على الخريطة
function c2Mark(x, y, kind, r = 12){ (W.marks = W.marks || []).push({x, y, kind, r, t: 0, life: kind === 'kill' ? 6 : kind === 'boom' ? 1.6 : .8}); }
// رسم رمز وحدة بحجم ثابت على الشاشة
function c2Symbol(c, u, sx, sy, alpha = 1, unknown = false){
  const fr = u.side === 'iq', t = u.t, S = 12;
  c.save(); c.globalAlpha = alpha; c.translate(sx, sy); c.lineJoin = 'round';
  // الإطار: مستطيل للصديق، معيّن للعدو، ورباعي ورقي للمجهول
  c.beginPath();
  if (unknown) { for (let i = 0; i < 4; i++) { const a = i * Math.PI / 2; c.arc(Math.cos(a) * 6, Math.sin(a) * 6, 7, a - 1.3, a + 1.3); } c.closePath(); c.fillStyle = 'rgba(255,240,140,.9)'; }
  else if (fr) { c.rect(-S, -S * .68, S * 2, S * 1.36); c.fillStyle = C2.friendFill; }
  else { c.moveTo(0, -S * 1.05); c.lineTo(S * 1.05, 0); c.lineTo(0, S * 1.05); c.lineTo(-S * 1.05, 0); c.closePath(); c.fillStyle = C2.hostileFill; }
  if (UT[t] && UT[t].air && !unknown) { c.restore(); c.save(); c.globalAlpha = alpha; c.translate(sx, sy); c.beginPath(); if (fr) { c.moveTo(-S, S * .6); c.lineTo(-S, -S * .1); c.arc(0, -S * .1, S, Math.PI, 0); c.lineTo(S, S * .6); c.closePath(); } else { c.moveTo(-S, S * .6); c.lineTo(-S, 0); c.lineTo(0, -S * 1.05); c.lineTo(S, 0); c.lineTo(S, S * .6); c.closePath(); } c.fillStyle = fr ? C2.friendFill : C2.hostileFill; }
  c.fill(); c.lineWidth = 1.6; c.strokeStyle = C2.ink; c.stroke();
  if (unknown) { c.fillStyle = C2.ink; c.font = '700 11px sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText('?', 0, 1); c.restore(); return; }
  // أيقونة النوع داخل الإطار
  const w = fr ? S : S * .62, h = fr ? S * .68 : S * .62;
  c.beginPath(); c.lineWidth = 1.4; c.strokeStyle = C2.ink; c.fillStyle = C2.ink;
  const X = () => { c.moveTo(-w, -h); c.lineTo(w, h); c.moveTo(w, -h); c.lineTo(-w, h); };
  const oval = (rx, ry) => { c.ellipse(0, 0, rx, ry, 0, 0, 7); };
  switch (t) {
    case 'tank': oval(w * .62, h * .5); break;                                   // دروع
    case 'ifv': oval(w * .62, h * .5); c.moveTo(w * .62, 0); X(); break;          // مشاة ميكانيكية
    case 'squad': X(); break;                                                     // مشاة
    case 'atgm': c.moveTo(-w, h); c.lineTo(0, -h); c.lineTo(w, h); break;        // مضاد دروع
    case 'mg': X(); c.stroke(); c.beginPath(); c.font = '700 7px sans-serif'; c.textAlign = 'center'; c.fillText('MG', 0, h + 7); break;
    case 'sniper': X(); c.stroke(); c.beginPath(); c.font = '700 7px sans-serif'; c.textAlign = 'center'; c.fillText('SN', 0, h + 7); break;
    case 'mortar': c.arc(0, h * .55, 2, 0, 7); c.moveTo(0, h * .3); c.lineTo(0, -h * .8); c.moveTo(-3, -h * .45); c.lineTo(0, -h * .8); c.lineTo(3, -h * .45); break;
    case 'arty': c.arc(0, 0, 2.6, 0, 7); c.fill(); break;                         // مدفعية
    case 'mlrs': c.arc(0, h * .25, 2.4, 0, 7); c.fill(); c.beginPath(); c.moveTo(-4, -1); c.lineTo(0, -h * .8); c.lineTo(4, -1); break;   // راجمة صواريخ
    case 'ad': c.arc(0, h, w * .7, Math.PI, 0); break;                            // دفاع جوي
    case 'heli': c.moveTo(-w * .7, -h * .3); c.lineTo(w * .7, h * .5); c.lineTo(w * .7, -h * .3); c.lineTo(-w * .7, h * .5); c.closePath(); break;   // جناح دوّار
    case 'jet': case 'drone': case 'recon': c.moveTo(-w * .8, 0); c.lineTo(0, -h * .5); c.lineTo(w * .8, 0); c.moveTo(0, -h * .5); c.lineTo(0, h * .6); if (t !== 'jet') { c.stroke(); c.beginPath(); c.font = '700 6px sans-serif'; c.textAlign = 'center'; c.fillText('UAV', 0, h + 6); } break;
  }
  c.stroke();
  // مستوى الوحدة فوق الإطار: فصيل ••• وفريق •
  if (!UT[t].air) { const n = t === 'squad' || t === 'tank' || t === 'ifv' ? 3 : 1; for (let i = 0; i < n; i++) { c.beginPath(); c.arc((i - (n - 1) / 2) * 4.5, -S * (fr ? .68 : 1.05) - 4, 1.5, 0, 7); c.fill(); } }
  c.restore();
}
function drawC2(dt){
  const c = wctx, Wd = wc().clientWidth, Hd = wc().clientHeight, cam = W.cam;
  c2Visibility();
  if (W.follow) { const f = W.units.filter(u => u.side === 'iq' && ground(u) && (u.t === 'tank' || u.t === 'ifv' || u.t === 'squad')); if (f.length) { const ty = Math.min(...f.map(u => u.y)) + 70, tx = f.reduce((s, u) => s + u.x, 0) / f.length; cam.x += (tx - cam.x) * Math.min(1, dt * .8); cam.y += (ty - cam.y) * Math.min(1, dt * .8); } }
  c.fillStyle = '#061016'; c.fillRect(0, 0, Wd, Hd);
  c.save(); c.translate(Wd / 2, Hd / 2); c.scale(cam.k, cam.k); c.translate(-cam.x, -cam.y);
  const x0 = Math.max(0, cam.x - Wd / 2 / cam.k - 2), y0 = Math.max(0, cam.y - Hd / 2 / cam.k - 2), x1 = Math.min(FIELD.w, cam.x + Wd / 2 / cam.k + 2), y1 = Math.min(FIELD.h, cam.y + Hd / 2 / cam.k + 2);
  if (W_IMG.complete && x1 > x0 && y1 > y0) c.drawImage(W_IMG, x0, y0, x1 - x0, y1 - y0, x0, y0, x1 - x0, y1 - y0);
  { const [bx, by, bw, bh] = SAT_BOX, hx0 = Math.max(x0, bx), hy0 = Math.max(y0, by), hx1 = Math.min(x1, bx + bw), hy1 = Math.min(y1, by + bh);
    if (hx1 > hx0 && hy1 > hy0) for (let j = Math.floor((hy0 - by) / TILE); j * TILE < hy1 - by; j++) for (let i = Math.floor((hx0 - bx) / TILE); i * TILE < hx1 - bx; i++) { const t = satTile(i, j); if (t) c.drawImage(t, bx + i * TILE, by + j * TILE, t.width / 2, t.height / 2); } }
  // تعتيم خفيف بلون شاشات القيادة حتى تبرز الرموز
  c.fillStyle = 'rgba(3,16,26,.38)'; c.fillRect(x0, y0, x1 - x0, y1 - y0);
  // شبكة الكيلومترات
  const step = cam.k > 1.6 ? KM : 5 * KM; c.strokeStyle = C2.grid; c.lineWidth = 1 / cam.k; c.beginPath();
  for (let x = Math.floor(x0 / step) * step; x < x1; x += step) { c.moveTo(x, y0); c.lineTo(x, y1); }
  for (let y = Math.floor(y0 / step) * step; y < y1; y += step) { c.moveTo(x0, y); c.lineTo(x1, y); }
  c.stroke();
  // خنادق العدو المعروفة: خط متعرج أحمر
  c.strokeStyle = 'rgba(255,107,94,.85)'; c.lineWidth = 2 / cam.k;
  for (const p of W.props) if (p.trench) { const L = p.s * .5; c.beginPath(); for (let i = 0; i <= 8; i++) { const x = p.x - L + i * L / 4, y = p.y - 4 + (i % 2 ? -2 : 2); i ? c.lineTo(x, y) : c.moveTo(x, y); } c.stroke(); }
  // الستار الدخاني: دائرة مخططة
  for (const s of W.smokes) { c.save(); c.beginPath(); c.arc(s.x, s.y, s.r, 0, 7); c.fillStyle = 'rgba(220,225,230,.18)'; c.fill(); c.clip(); c.strokeStyle = 'rgba(230,235,240,.35)'; c.lineWidth = 1 / cam.k; c.beginPath(); for (let d = -s.r * 2; d < s.r * 2; d += 5) { c.moveTo(s.x + d, s.y - s.r); c.lineTo(s.x + d + s.r * 2, s.y + s.r); } c.stroke(); c.restore(); }
  // حلقة مدى الوحدة المحددة
  for (const u of W.units) if (W.sel && W.sel.includes(u.id) && !u.dead) {
    const d = UT[u.t]; if (d.rng) { c.setLineDash([6 / cam.k, 5 / cam.k]); c.strokeStyle = 'rgba(127,211,247,.55)'; c.lineWidth = 1.2 / cam.k; c.beginPath(); c.arc(u.x, u.y, d.rng, 0, 7); c.stroke(); c.setLineDash([]); }
    if (u.manual) { const f = u.focus && W.units.find(v => v.id === u.focus && !v.dead), g = f || u.manual; c.strokeStyle = f ? 'rgba(255,107,94,.9)' : 'rgba(127,211,247,.9)'; c.lineWidth = 2 / cam.k; c.beginPath(); c.moveTo(u.x, u.y); c.lineTo(g.x, g.y); c.stroke(); const a = Math.atan2(g.y - u.y, g.x - u.x), L = 7 / cam.k; c.beginPath(); c.moveTo(g.x, g.y); c.lineTo(g.x - Math.cos(a - .4) * L, g.y - Math.sin(a - .4) * L); c.moveTo(g.x, g.y); c.lineTo(g.x - Math.cos(a + .4) * L, g.y - Math.sin(a + .4) * L); c.stroke(); }
  }
  // خطوط النار والمقذوفات
  for (const p of W.proj) {
    if (p.t < 0 || p.done) continue;
    const q = projPos(p), col = p.side === 'iq' ? '127,211,247' : '255,107,94';
    if (p.k === 'tracer' || p.k === 'shell' || p.k === 'bullet') { c.strokeStyle = `rgba(${col},${p.k === 'shell' ? .75 : .4})`; c.lineWidth = (p.k === 'shell' ? 1.6 : 1) / cam.k; c.beginPath(); c.moveTo(p.x0, p.y0); c.lineTo(q.x, q.y); c.stroke(); }
    else {
      // قذائف وصواريخ بعيدة: خط متقطع إلى نقطة السقوط، ودائرة السقوط المتوقع
      const far = p.k === 'arty' || p.k === 'rkt' || p.k === 'bm' || p.k === 'agm';
      if (far) { c.setLineDash([4 / cam.k, 4 / cam.k]); c.strokeStyle = `rgba(${col},.45)`; c.lineWidth = 1 / cam.k; c.beginPath(); c.moveTo(q.x, q.y); c.lineTo(p.x1, p.y1); c.stroke(); c.setLineDash([]); c.strokeStyle = `rgba(${col},.8)`; c.beginPath(); c.arc(p.x1, p.y1, (p.k === 'bm' ? 14 : p.k === 'agm' ? 10 : 7) * (1 + .15 * Math.sin(W.t * 8)), 0, 7); c.stroke(); }
      else { c.strokeStyle = `rgba(${col},.6)`; c.lineWidth = 1.2 / cam.k; c.beginPath(); c.moveTo(p.x0, p.y0); c.lineTo(q.x, q.y); c.stroke(); }
      c.fillStyle = p.k === 'int' ? '#ffe28a' : `rgb(${col})`; c.beginPath(); c.arc(q.x, q.y, 2.6 / cam.k, 0, 7); c.fill();
    }
  }
  c.restore();
  // ---------- طبقة الشاشة: علامات الانفجار، والرموز، وأسماء المدن (بحجم ثابت)
  const S2 = (x, y) => [(x - cam.x) * cam.k + Wd / 2, (y - cam.y) * cam.k + Hd / 2];
  W.marks = (W.marks || []).filter(m => (m.t += dt) < m.life);
  for (const m of W.marks) {
    const [sx, sy] = S2(m.x, m.y), k = m.t / m.life;
    if (m.kind === 'boom') { c.strokeStyle = `rgba(255,170,80,${1 - k})`; c.lineWidth = 2; c.beginPath(); c.arc(sx, sy, 4 + k * Math.max(14, m.r * cam.k), 0, 7); c.stroke(); c.fillStyle = `rgba(255,200,120,${(1 - k) * .5})`; c.beginPath(); c.arc(sx, sy, 3 + (1 - k) * 4, 0, 7); c.fill(); }
    else if (m.kind === 'hit') { c.strokeStyle = `rgba(255,230,140,${1 - k})`; c.lineWidth = 1.5; c.beginPath(); c.moveTo(sx - 5, sy - 5); c.lineTo(sx + 5, sy + 5); c.moveTo(sx + 5, sy - 5); c.lineTo(sx - 5, sy + 5); c.stroke(); }
  }
  // الوحدات المدمرة: رمز رمادي عليه علامة ×
  for (const u of W.units) {
    if (!u.dead || u.gone || UT[u.t].air || (u.side === 'tr' && !u.last)) continue;
    const [sx, sy] = S2(u.x, u.y); if (sx < -20 || sx > Wd + 20 || sy < -20 || sy > Hd + 20) continue;
    c2Symbol(c, u, sx, sy, .35); c.strokeStyle = 'rgba(20,20,20,.8)'; c.lineWidth = 2; c.beginPath(); c.moveTo(sx - 12, sy - 9); c.lineTo(sx + 12, sy + 9); c.moveTo(sx + 12, sy - 9); c.lineTo(sx - 12, sy + 9); c.stroke();
  }
  for (const u of W.units) {
    if (u.dead || u.gone) continue;
    let x = u.x, y = u.y, a = 1, unk = false;
    if (u.side === 'tr' && !u.vis) { if (!u.last || W.t - u.last.t > 90) continue; x = u.last.x; y = u.last.y; a = .5; unk = W.t - u.last.t > 20; }
    const [sx, sy] = S2(x, y); if (sx < -24 || sx > Wd + 24 || sy < -24 || sy > Hd + 24) continue;
    const d = UT[u.t];
    // خط اتجاه الحركة وسرعتها
    if (u.moving && (u.side === 'iq' || u.vis)) { const L = 8 + Math.min(18, (d.spd || 10) * .8); c.strokeStyle = u.side === 'iq' ? C2.friend : C2.hostile; c.lineWidth = 1.5; c.beginPath(); c.moveTo(sx, sy); c.lineTo(sx + Math.cos(u.ang) * L, sy + Math.sin(u.ang) * L); c.stroke(); }
    c2Symbol(c, u, sx, sy, a, unk);
    if (W.sel && W.sel.includes(u.id)) { c.strokeStyle = '#fff'; c.lineWidth = 1.5; c.strokeRect(sx - 16, sy - 13, 32, 26); }
    if (a === 1) {
      // شريط القوة، وعلامة «تحت النار»، وسهم الانسحاب
      const bw = 22, f = u.hp / d.hp; c.fillStyle = 'rgba(0,0,0,.6)'; c.fillRect(sx - bw / 2 - 1, sy + 13, bw + 2, 4); c.fillStyle = f > .6 ? '#6fd08c' : f > .3 ? '#e2c04f' : '#e0604f'; c.fillRect(sx - bw / 2, sy + 14, bw * f, 2);
      if (u.sup > 55) { c.fillStyle = '#ffd34d'; c.font = '700 12px sans-serif'; c.textAlign = 'left'; c.fillText('!', sx + 14, sy - 6); }
      if (u.retreat) { c.fillStyle = '#ffd34d'; c.font = '700 11px sans-serif'; c.textAlign = 'right'; c.fillText('↩', sx - 14, sy - 6); }
    }
  }
  // أسماء المدن وأشرطة السيطرة
  c.font = '700 13px "IBM Plex Sans Arabic", sans-serif'; c.textAlign = 'center'; c.direction = 'rtl';
  for (const tw of TOWNS) {
    const [sx, sy] = S2(tw.x, tw.y); if (sx < -60 || sx > Wd + 60 || sy < -40 || sy > Hd + 40) continue;
    const y = sy - tw.r * cam.k - 8;
    c.setLineDash([4, 4]); c.strokeStyle = 'rgba(190,230,255,.35)'; c.lineWidth = 1; c.beginPath(); c.arc(sx, sy, tw.r * cam.k, 0, 7); c.stroke(); c.setLineDash([]);
    c.lineWidth = 4; c.strokeStyle = 'rgba(3,10,16,.9)'; c.fillStyle = '#e9f4fa'; c.strokeText(tw.n, sx, y); c.fillText(tw.n, sx, y);
    if (tw.obj) { const v = W.ctl[tw.id] / 100; c.fillStyle = 'rgba(3,10,16,.85)'; c.fillRect(sx - 26, y + 5, 52, 7); c.fillStyle = C2.hostile; c.fillRect(sx - 25, y + 6, 50, 5); c.fillStyle = C2.friend; c.fillRect(sx - 25, y + 6, 50 * v, 5); }
  }
  // أرقام الشبكة على الحافة
  c.font = '10px monospace'; c.fillStyle = C2.gridTxt; c.textAlign = 'left'; c.direction = 'ltr';
  for (let x = Math.floor(x0 / step) * step; x < x1; x += step) { const [sx] = S2(x, 0); if (sx > 4 && sx < Wd - 20) c.fillText(String(Math.round(x / KM)).padStart(2, '0'), sx + 2, Hd - 150); }
  for (let y = Math.floor(y0 / step) * step; y < y1; y += step) { const [, sy] = S2(0, y); if (sy > 120 && sy < Hd - 160) c.fillText(String(Math.round(y / KM)).padStart(2, '0'), Wd - 18, sy - 2); }
  c.direction = 'rtl';
  // الجزيئات لا تُرسم هنا، لكن تتقدم وتنتهي
  for (const p of W.parts) { if (p.delay > 0) p.delay -= dt; else p.t += dt; }
  W.parts = W.parts.filter(p => p.delay > 0 || p.t < p.life);
}
document.getElementById('wc2').onclick = () => { C2MODE = !C2MODE; document.getElementById('wc2').classList.toggle('on', C2MODE); document.getElementById('wc2').textContent = C2MODE ? '⌗' : '▣'; };
