// ================================================================== معركة دهوك: محاكاة قتال على أرض حقيقية
// الإحداثيات بكسلات صورة الأرض (كل بكسل نحو 30 متراً). الزمن ثوانٍ من زمن المعركة (300 ثانية = 5 دقائق بسرعة ×1).
const W_IMG = new Image(); W_IMG.src = FIELD_IMG;
const WS = {}; for (const k in BSPR) { const im = new Image(); im.src = BSPR[k]; WS[k] = im; }
const KM = 33;
function hAt(x, y){ const i = Math.max(0, Math.min(FIELD.hh - 1, Math.floor(y / 8))), j = Math.max(0, Math.min(FIELD.hw - 1, Math.floor(x / 8))); return FIELD.H[i * FIELD.hw + j]; }
// المدن بمواقعها الحقيقية
const TOWNS = [
  {id: 'duhok', n: 'دهوك', x: 1165, y: 667, r: 75, obj: true, houses: 9, mosque: 2},
  {id: 'simele', n: 'سميل', x: 731, y: 700, r: 55, obj: true, houses: 5, mosque: 1},
  {id: 'alqosh', n: 'ألقوش', x: 1445, y: 1147, r: 55, obj: true, houses: 4, mosque: 1},
  {id: 'baadra', n: 'باعذرا', x: 1762, y: 1256, r: 40, houses: 3},
  {id: 'telkaif', n: 'تلكيف', x: 1509, y: 2029, r: 55, houses: 5, mosque: 1},
];
// أنواع الوحدات: أرقام مبسطة من أداء حقيقي (المدى بالبكسل، والسرعة بكسل/ثانية)
const UT = {
  tank:   {hp: 100, arm: 2, rng: 2.6 * KM, rof: 3.2, ds: 22, dh: 46, acc: .55, spd: 8, sz: 26, cost: 3, snd: 'tank_cannon', fx: 'shell'},
  ifv:    {hp: 70,  arm: 1, rng: 1.6 * KM, rof: 1.5, ds: 16, dh: 14, acc: .5,  spd: 8.5, sz: 22, cost: 2, snd: 'hmg', fx: 'tracer'},
  squad:  {hp: 60,  arm: 0, rng: 0.9 * KM, rof: 1.1, ds: 9,  dh: 2,  acc: .45, spd: 5, sz: 30, cost: 1, snd: 'ak47', fx: 'tracer'},
  atgm:   {hp: 40,  arm: 0, rng: 3.5 * KM, rof: 6.5, ds: 4,  dh: 72, acc: .62, spd: 4.4, sz: 20, cost: 1.5, snd: 'rpg', fx: 'atgm', heavyOnly: true},
  mg:     {hp: 40,  arm: 0, rng: 1.2 * KM, rof: .55, ds: 6,  dh: 1,  acc: .4,  spd: 4.4, sz: 22, cost: 1, snd: 'hmg2', fx: 'tracer', softOnly: true},
  mortar: {hp: 40,  arm: 0, rng: 5 * KM,   rof: 4.5, ds: 14, dh: 8,  acc: .35, spd: 2.4, sz: 20, cost: 1, snd: 'artillery', fx: 'indirect', ind: true, area: 18},
  sniper: {hp: 30,  arm: 0, rng: 1.5 * KM, rof: 4.5, ds: 32, dh: 0,  acc: .7,  spd: 4.4, sz: 18, cost: 1, snd: 'rifle', fx: 'none', softOnly: true},
  arty:   {hp: 60,  arm: 1, rng: 25 * KM,  rof: 7.5, ds: 24, dh: 16, acc: .3,  spd: 2.2, sz: 30, cost: 2, snd: 'artillery', fx: 'indirect', ind: true, area: 24},
  ad:     {hp: 60,  arm: 1, rng: 0,        rof: 99,  ds: 0,  dh: 0,  acc: 0,   spd: 2.2, sz: 28, cost: 2, airRng: 22 * KM},
  drone:  {hp: 30,  arm: 1, rng: 0, rof: 99, ds: 0, dh: 0, acc: 0, spd: 26, sz: 32, cost: 0, air: true},
  heli:   {hp: 70,  arm: 1, rng: 3 * KM,   rof: 1.6, ds: 14, dh: 30, acc: .5,  spd: 9,   sz: 42, cost: 3, snd: 'hmg', fx: 'rocket', air: true},
};
const SPRITE = {
  iq: {tank: ['qaqaa', 't72'], ifv: ['bmp1'], squad: ['squad_iq'], atgm: ['atgm_team'], mg: ['mg_team'], mortar: ['mortar'], sniper: ['sniper'], arty: ['samsama'], ad: ['pantsir'], heli: ['mi35']},
  tr: {tank: ['leopard2a4', 'altay'], ifv: ['acv15'], squad: ['squad_tr'], atgm: ['atgm_team'], mg: ['mg_team'], mortar: ['mortar'], sniper: ['sniper'], arty: ['firtina'], ad: ['ad_truck'], heli: ['t129']}
};
const NAME = {tank: 'دبابة', ifv: 'مدرعة', squad: 'فصيل مشاة', atgm: 'فريق مضاد دروع', mg: 'فريق رشاش', mortar: 'هاون', sniper: 'قناصة', arty: 'مدفعية', ad: 'دفاع جوي', heli: 'مروحية'};
const SIDE_NAME = {iq: 'العراق', tr: 'تركيا'};

let W = null;   // حالة المعركة
let wraf = 0, wlast = 0, wspeed = 1;
function wrand(){ W.seed = (W.seed * 1664525 + 1013904223) >>> 0; return W.seed / 4294967296; }

function mkUnit(side, t, x, y, o = {}){
  const d = UT[t], spr = SPRITE[side][t];
  const u = Object.assign({id: W.nid++, side, t, x, y, hp: d.hp, mor: 100, cd: wrand() * d.rof, ang: side === 'iq' ? -Math.PI / 2 : Math.PI / 2, path: [], pi: 0, retreat: false, dead: false, home: {x, y}, lastHit: -99, trk: {x, y}, spr: spr[W.nid % spr.length]}, o);
  W.units.push(u); return u;
}
function setupWar(){
  W = {t: 0, seed: 20261011, nid: 1, units: [], proj: [], parts: [], decals: [], props: [], log: [], order: 'attack', end: null,
    stats: {iq: {lost: {}, fired: 0}, tr: {lost: {}, fired: 0}, msl: 0, mslInt: 0, trMsl: 0, trInt: 0, jetsLost: 0},
    uses: {air: 2, msl: 3, res: 1}, cool: {air: 0, msl: 0}, ctl: {duhok: 0, simele: 0, alqosh: 0}, trMslT: 55, droneT: 70, follow: true,
    cam: {x: 1250, y: 1380, k: 1.7}};
  // المباني في المدن بمواقع ثابتة
  for (const tw of TOWNS) {
    for (let i = 0; i < tw.houses; i++) { const a = i * 2.4 + tw.x * .01, rr = tw.r * (.25 + (i % 3) * .25); W.props.push({k: i % 4 === 3 ? 'ruins' : 'houses', x: tw.x + Math.cos(a) * rr, y: tw.y + Math.sin(a) * rr, s: 56, rot: (i % 4) * Math.PI / 2}); }
    for (let i = 0; i < (tw.mosque || 0); i++) W.props.push({k: 'mosque', x: tw.x + 14 - i * 30, y: tw.y - 10 + i * 22, s: 34, rot: 0});
  }
  // خط الدفاع التركي الأول على السلسلة الجنوبية، والثاني عند مدخل دهوك
  const line1 = [[1060, 1088], [1150, 1080], [1240, 1092], [1330, 1084], [1420, 1098]];
  const line2 = [[1080, 820], [1170, 812], [1260, 826]];
  for (const [x, y] of line1.concat(line2)) { W.props.push({k: 'trench', x, y: y + 10, s: 60, rot: 0, dug: true}); W.props.push({k: 'sandbags', x: x + 26, y: y - 6, s: 22, rot: 0}); }
  W.props.push({k: 'checkpoint', x: 1175, y: 900, s: 30, rot: 0});
  W.props.push({k: 'depot', x: 1260, y: 1640, s: 40, rot: 0}); W.props.push({k: 'hospital', x: 1180, y: 1660, s: 34, rot: 0});
  W.props.push({k: 'depot', x: 1210, y: 560, s: 36, rot: 0});
  W.dug = line1.concat(line2).map(([x, y]) => ({x, y}));
  // تركيا: دفاع متدرج
  line1.forEach(([x, y], i) => { mkUnit('tr', 'squad', x, y, {dug: true}); if (i % 2 === 0) mkUnit('tr', 'atgm', x + 18, y + 4, {dug: true}); });
  mkUnit('tr', 'mg', 1195, 1086, {dug: true}); mkUnit('tr', 'mg', 1375, 1090, {dug: true}); mkUnit('tr', 'sniper', 1290, 1070, {dug: true});
  mkUnit('tr', 'tank', 1120, 1040); mkUnit('tr', 'tank', 1300, 1035); mkUnit('tr', 'ifv', 1210, 1030);
  mkUnit('tr', 'squad', 1430, 1140); mkUnit('tr', 'squad', 1460, 1160); mkUnit('tr', 'ifv', 1440, 1120); mkUnit('tr', 'tank', 1480, 1110);
  line2.forEach(([x, y]) => { mkUnit('tr', 'squad', x, y, {dug: true}); mkUnit('tr', 'atgm', x + 20, y, {dug: true}); });
  mkUnit('tr', 'tank', 1140, 760); mkUnit('tr', 'tank', 1210, 755); mkUnit('tr', 'ifv', 1180, 700);
  mkUnit('tr', 'squad', 1150, 660); mkUnit('tr', 'squad', 1190, 690); mkUnit('tr', 'mg', 1170, 640); mkUnit('tr', 'mortar', 1200, 610);
  mkUnit('tr', 'squad', 731, 700); mkUnit('tr', 'atgm', 750, 715); mkUnit('tr', 'tank', 760, 680);
  mkUnit('tr', 'arty', 1130, 520); mkUnit('tr', 'arty', 1220, 515); mkUnit('tr', 'ad', 1260, 600); mkUnit('tr', 'heli', 1230, 560);
  // العراق: ثلاث مجموعات على خط البداية جنوب السلسلة
  const east = [[1445, 1147], [1300, 840], [1170, 680]], center = [[1220, 1085], [1180, 830], [1165, 670]], west = [[960, 1000], [760, 720]];
  const grp = (pts, list, x0, y0) => list.forEach(([t, dx, dy]) => mkUnit('iq', t, x0 + dx, y0 + dy, {path: pts.map(([x, y]) => ({x: x + dx * .4, y: y + dy * .2}))}));
  grp(center, [['tank', -40, 0], ['tank', 0, -8], ['tank', 40, 0], ['ifv', -20, 30], ['ifv', 20, 30], ['squad', -45, 50], ['squad', 0, 55], ['squad', 45, 50], ['atgm', 0, 80], ['mg', -30, 85], ['sniper', 30, 85]], 1220, 1460);
  grp(east, [['tank', -30, 0], ['tank', 10, -6], ['tank', 50, 4], ['ifv', 0, 30], ['squad', -25, 50], ['squad', 25, 50], ['atgm', 0, 75]], 1500, 1480);
  grp(west, [['tank', -20, 0], ['tank', 20, 0], ['ifv', 0, 28], ['squad', -20, 50], ['squad', 20, 50]], 980, 1440);
  mkUnit('iq', 'mortar', 1240, 1560); mkUnit('iq', 'mortar', 1470, 1570);
  mkUnit('iq', 'arty', 1180, 1700); mkUnit('iq', 'arty', 1260, 1710); mkUnit('iq', 'arty', 1340, 1700);
  mkUnit('iq', 'ad', 1300, 1620);
  mkUnit('iq', 'heli', 1200, 1600, {path: center.map(([x, y]) => ({x, y: y + 90}))}); mkUnit('iq', 'heli', 1460, 1620, {path: east.map(([x, y]) => ({x, y: y + 90}))});
  for (const u of W.units) { u.start = {x: u.x, y: u.y}; }
  W.init = {iq: strength('iq'), tr: strength('tr')};
  wlog('صدر أمر الهجوم: ثلاث مجموعات عراقية تتقدم نحو ألقوش ودهوك وسميل.', 'iq');
}
function strength(side){ let s = 0; for (const u of W.units) if (u.side === side && !u.dead) s += UT[u.t].cost * u.hp / UT[u.t].hp; return s; }
function wlog(t, side){ W.log.unshift({t, side, at: W.t}); if (W.log.length > 30) W.log.pop(); const el = document.getElementById('wlog'); if (el) el.innerHTML = W.log.slice(0, 3).map((l, i) => `<div style="opacity:${1 - i * .28};color:${l.side === 'iq' ? 'var(--mine)' : l.side === 'tr' ? '#e07b6e' : 'var(--text)'}">${l.t}</div>`).join(''); }
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
function inTown(u){ for (const t of TOWNS) if (Math.hypot(u.x - t.x, u.y - t.y) < t.r) return t; return null; }
function cover(u){ let c = 1; if (u.dug && !u.moving) c *= .5; if (inTown(u)) c *= .6; return c; }

// ------------------------------------------------------------------ الجزيئات بإحداثيات العالم
function wp(img, x, y, o){ if (W.parts.length > 420) return; W.parts.push(Object.assign({img, x, y, vx: 0, vy: 0, s0: 10, s1: 20, a0: 1, a1: 0, rot: wrand() * 6.28, vr: (wrand() - .5) * .5, t: 0, life: 1, delay: 0, layer: 'top'}, o)); }
function wboom(x, y, big = 1, snd = true){
  const r = 16 * big;
  wp('fireball', x, y, {s0: r * .5, s1: r * 1.7, life: .55, vr: 0});
  wp('sparks', x, y, {s0: r * .6, s1: r * 2, life: .45});
  wp('shock', x, y, {s0: r * .5, s1: r * 2.4, a0: .6, life: .9, layer: 'mid', vr: 0});
  for (let i = 0; i < 2 + big; i++) wp('smoke_dark', x + (wrand() - .5) * r * .5, y + (wrand() - .5) * r * .5, {s0: r * .4, s1: r * (1.3 + wrand() * .6), a0: .75, life: 2.4 + wrand() * 1.5, delay: .12 + i * .08, vx: 2 + wrand() * 3, vy: -3 - wrand() * 4, layer: 'mid'});
  if (W.decals.length > 260) W.decals.shift();
  W.decals.push({k: big > 1.2 ? 'crater_big' : 'crater_small', x, y, s: r * 1.3, rot: wrand() * 6.28, a: .85});
  if (snd) wsound(big > 1.3 ? 'explosion_big' : big > .8 ? 'explosion_med' : 'explosion_med2', x, y, .6 + big * .15);
}
// ------------------------------------------------------------------ الصوت بموضعه: يسار ويمين حسب الشاشة، ويخفت ويُكتم بالبعد
let sndBudget = 0;
function wsound(k, x, y, vol = .7){
  if (sndBudget > 9) return; sndBudget++;
  const c = W.cam, sx = (x - c.x) * c.k + innerWidth / 2, d = Math.hypot(x - c.x, y - c.y) * c.k / innerWidth;
  if (d > 2.2) return;
  play(k, {vol: vol * Math.max(.15, 1 - d * .4), x: Math.max(0, Math.min(innerWidth, sx)), dist: Math.min(1, d * .6)});
}

// ------------------------------------------------------------------ المحاكاة
function enemiesOf(u){ return W.units.filter(v => v.side !== u.side && !v.dead && !v.air && !(UT[v.t].air)); }
function pickTarget(u, d){
  let best = null, bs = -1;
  for (const v of W.units) {
    if (v.side === u.side || v.dead || UT[v.t].air) continue;
    const r = dist(u, v); if (r > d.rng * (1 + Math.max(0, hAt(u.x, u.y) - hAt(v.x, v.y)) / 600)) continue;
    const hv = UT[v.t].arm > 0;
    if (d.heavyOnly && !hv) continue; if (d.softOnly && hv) continue;
    let sc = 1 / (r + 20); if (d.dh > d.ds && hv) sc *= 3; if (d.ds >= d.dh && !hv) sc *= 2; if (v.t === 'atgm' || v.t === 'arty') sc *= 1.5;
    if (sc > bs) { bs = sc; best = v; }
  }
  return best;
}
// المدفعية تحتاج من يرى الهدف: عدو قريب من أي وحدة صديقة
function spotted(side, v){ for (const u of W.units) if (u.side === side && !u.dead && dist(u, v) < 4 * KM) return true; return false; }
function fire(u, v){
  const d = UT[u.t]; W.stats[u.side].fired++;
  u.ang = Math.atan2(v.y - u.y, v.x - u.x);
  const r = dist(u, v), hv = UT[v.t].arm > 0;
  let p = d.acc * (1 - r / (d.rng * 1.6)) * cover(v);
  if (hAt(v.x, v.y) - hAt(u.x, u.y) > 60) p *= .8;
  if (v.moving) p *= .85;
  const hit = wrand() < p;
  const dmg = (UT[v.t].arm === 2 ? d.dh : UT[v.t].arm === 1 ? (d.ds + d.dh) / 2 : d.ds) * (.7 + wrand() * .6);
  if (d.ind) {
    const tx = v.x + (wrand() - .5) * 26, ty = v.y + (wrand() - .5) * 26;
    W.proj.push({k: 'shell', x0: u.x, y0: u.y, x1: tx, y1: ty, t: 0, dur: 2.6 + r / 300, side: u.side, dmg, area: d.area, soft: d.ds, hard: d.dh});
    if (u.t === 'arty') { wp('muzzle', u.x + Math.cos(u.ang) * 14, u.y + Math.sin(u.ang) * 14, {s0: 14, s1: 20, life: .18, rot: u.ang + Math.PI / 2, vr: 0}); wp('smoke_light', u.x, u.y, {s0: 10, s1: 40, a0: .5, life: 2, vx: 3, vy: -3, layer: 'mid'}); }
  } else {
    const fx = d.fx;
    W.proj.push({k: fx, x0: u.x, y0: u.y, x1: v.x + (hit ? 0 : (wrand() - .5) * 30), y1: v.y + (hit ? 0 : (wrand() - .5) * 30), t: 0, dur: fx === 'atgm' ? 1.4 : fx === 'rocket' ? .8 : .25, target: v, hit, dmg, side: u.side});
    if (fx === 'shell') { wp('muzzle', u.x + Math.cos(u.ang) * d.sz * .55, u.y + Math.sin(u.ang) * d.sz * .55, {s0: 10, s1: 15, life: .16, rot: u.ang + Math.PI / 2, vr: 0}); wp('smoke_light', u.x + Math.cos(u.ang) * d.sz * .7, u.y + Math.sin(u.ang) * d.sz * .7, {s0: 6, s1: 22, a0: .45, life: 1.4, vx: 2, vy: -2, layer: 'mid'}); }
    if (fx === 'tracer') wp('rifle_flash', u.x + Math.cos(u.ang) * d.sz * .4, u.y + Math.sin(u.ang) * d.sz * .4, {s0: 5, s1: 7, life: .1, vr: 0});
  }
  if (d.snd && wrand() < (d.rof < 1 ? .25 : .7)) wsound(d.snd, u.x, u.y, .45);
}
function damage(v, dmg, by){
  if (v.dead) return;
  v.hp -= dmg; v.mor -= 10 + dmg * .25; v.lastHit = W.t;
  if (v.hp <= 0) kill(v, by);
}
function kill(v, by){
  v.dead = true; v.hp = 0;
  const L = W.stats[v.side].lost; L[v.t] = (L[v.t] || 0) + 1;
  for (const u of W.units) if (u.side === v.side && !u.dead && dist(u, v) < 70) u.mor -= 8;
  if (UT[v.t].arm > 0 && !UT[v.t].air) {
    wboom(v.x, v.y, 1.6);
    W.decals.push({k: v.t === 'tank' ? 'wreck_tank' : v.t === 'arty' || v.t === 'ad' ? 'wreck_truck' : 'wreck_apc', x: v.x, y: v.y, s: UT[v.t].sz * 1.05, rot: v.ang + Math.PI / 2, a: 1, burn: 40});
    wlog(`${by === 'iq' ? 'دُمّرت' : 'خسرنا'} ${NAME[v.t]} ${v.side === 'tr' ? 'تركية' : 'عراقية'}${inTown(v) ? ' في ' + inTown(v).n : ''}`, by);
  } else if (UT[v.t].air) {
    v.falling = 1.6; wsound('explosion_big', v.x, v.y, .8); wlog(`أُسقطت ${NAME[v.t]} ${v.side === 'tr' ? 'تركية' : 'عراقية'}`, by);
  } else if (wrand() < .4) wlog(`${NAME[v.t]} ${v.side === 'tr' ? 'تركي' : 'عراقي'} خارج القتال`, by);
}

function stepWar(dt){
  W.t += dt; sndBudget = Math.max(0, sndBudget - dt * 14);
  W.cool.air = Math.max(0, W.cool.air - dt); W.cool.msl = Math.max(0, W.cool.msl - dt);
  // الوحدات
  for (const u of W.units) {
    if (u.dead || u.jetPath || u.t === 'drone') continue;
    const d = UT[u.t];
    if (W.t - u.lastHit > 4) u.mor = Math.min(100, u.mor + dt * 3);
    if (!u.retreat && u.mor < 22) { u.retreat = true; if (wrand() < .5) wlog(`${NAME[u.t]} ${u.side === 'tr' ? 'تركي' : 'عراقي'} ينسحب بعد خسائر`, u.side === 'tr' ? 'iq' : 'tr'); }
    if (u.retreat && u.mor > 60) u.retreat = false;
    // اختيار الهدف وإطلاق النار
    u.cd -= dt;
    let tgt = null;
    if (d.rng > 0) { tgt = pickTarget(u, d); if (tgt && d.ind && !spotted(u.side, tgt)) tgt = null; }
    if (tgt && u.cd <= 0) { fire(u, tgt); u.cd = d.rof * (.8 + wrand() * .4) * (u.retreat ? 1.6 : 1); }
    // الحركة
    let goal = null, sp = d.spd;
    const order = u.side === 'iq' ? W.order : (W.trCollapse ? 'retreat' : 'hold');
    if (u.retreat || order === 'retreat') goal = u.side === 'iq' ? u.start : {x: u.x, y: 280};
    else if (u.side === 'iq' && order === 'attack' && u.path.length) {
      while (u.pi < u.path.length - 1 && dist(u, u.path[u.pi]) < 26) u.pi++;
      goal = u.path[u.pi];
      if (tgt && !d.air) sp *= u.t === 'tank' || u.t === 'ifv' ? .7 : .4;
    } else if (u.side === 'tr' && !u.dug && (u.t === 'tank' || u.t === 'ifv')) {
      // هجوم مضاد محلي: الدروع التركية تتقدم نحو عدو قريب إذا كان الميزان المحلي لصالحها
      const e = enemiesOf(u).filter(v => dist(u, v) < 6 * KM);
      const f = W.units.filter(v => v.side === 'tr' && !v.dead && dist(u, v) < 6 * KM);
      if (e.length && f.length > e.length * 1.3 && !tgt) { const n = e.sort((a, b) => dist(u, a) - dist(u, b))[0]; goal = {x: n.x, y: n.y}; sp *= .7; if (!u.ca) { u.ca = 1; wlog('هجوم مضاد تركي بالدروع', 'tr'); } }
    }
    if (d.air && u.side === 'iq' && order === 'attack') {
      // المروحيات تتبع مقدمة القوات من الخلف
      const lead = W.units.filter(v => v.side === 'iq' && !v.dead && !UT[v.t].air && (v.t === 'tank' || v.t === 'ifv'));
      if (lead.length) { const ly = Math.min(...lead.map(v => v.y)); goal = {x: lead.reduce((s, v) => s + v.x, 0) / lead.length, y: ly + 90}; }
    }
    u.moving = false;
    if (goal && (u.side === 'tr' || order !== 'hold' || u.retreat)) {
      const dx = goal.x - u.x, dy = goal.y - u.y, r = Math.hypot(dx, dy);
      if (r > 4) {
        let f = 1;
        if (!d.air) { const h0 = hAt(u.x, u.y), h1 = hAt(u.x + dx / r * 8, u.y + dy / r * 8); if (h0 > 900) f *= u.t === 'squad' || u.t === 'atgm' ? .7 : .45; if (h1 > h0 + 8) f *= .7; }
        if (u.retreat) f *= 1.2;
        const st = Math.min(r, sp * f * dt);
        u.x += dx / r * st; u.y += dy / r * st; u.moving = true;
        if (!tgt) u.ang += Math.atan2(Math.sin(Math.atan2(dy, dx) - u.ang), Math.cos(Math.atan2(dy, dx) - u.ang)) * Math.min(1, dt * 3);
        if ((u.t === 'tank' || u.t === 'ifv' || u.t === 'arty') && dist(u, u.trk) > 12) { if (W.decals.length > 260) W.decals.shift(); W.decals.push({k: 'tracks', x: (u.x + u.trk.x) / 2, y: (u.y + u.trk.y) / 2, s: 16, rot: Math.atan2(u.y - u.trk.y, u.x - u.trk.x) + Math.PI / 2, a: .35}); u.trk = {x: u.x, y: u.y}; }
      }
    }
    if (u.dug && u.moving && dist(u, u.home) > 30) u.dug = false;
  }
  // المقذوفات
  for (const p of W.proj) {
    p.t += dt; if (p.t < p.dur || p.done) continue; p.done = true;
    if (p.k === 'shell') {
      wboom(p.x1, p.y1, p.area > 20 ? 1.1 : .8);
      for (const v of W.units) if (!v.dead && v.side !== p.side && !UT[v.t].air) { const r = Math.hypot(v.x - p.x1, v.y - p.y1); if (r < p.area) damage(v, (UT[v.t].arm ? p.hard : p.soft) * (1 - r / p.area) * cover(v) * 1.4, p.side); }
    } else if (p.k === 'msl' || p.k === 'bomb') {
      if (p.intercepted) continue;
      wboom(p.x1, p.y1, p.k === 'bomb' ? 1.7 : 2);
      for (const v of W.units) if (!v.dead && v.side !== p.side && !UT[v.t].air) { const r = Math.hypot(v.x - p.x1, v.y - p.y1); if (r < 34) damage(v, (UT[v.t].arm ? 55 : 60) * (1 - r / 40) * cover(v), p.side); }
    } else if (p.k === 'int') {
      const m = p.vs; if (!m || m.done) continue;
      if (p.ok) { m.intercepted = true; m.done = true; if (m.jet) { kill(m.jet, p.side); } wp('intercept', p.x1, p.y1, {s0: 12, s1: 46, life: .7}); wp('smoke_dark', p.x1, p.y1, {s0: 10, s1: 34, a0: .55, life: 2.2, vx: 3, vy: -2, layer: 'mid'}); wsound('intercept', p.x1, p.y1, .6); }
      else wp('intercept', p.x1, p.y1, {s0: 8, s1: 24, life: .5});
    } else if (p.target) {
      if (p.hit) { damage(p.target, p.dmg, p.side); if (p.k === 'shell' || p.k === 'atgm' || p.k === 'rocket') { wp('sparks', p.x1, p.y1, {s0: 8, s1: 18, life: .35}); if (p.k !== 'shell' || wrand() < .5) wboom(p.x1, p.y1, .55, wrand() < .5); } }
      else if (p.k !== 'tracer') wboom(p.x1, p.y1, .45, false);
    }
  }
  W.proj = W.proj.filter(p => !p.done);
  // الطائرات (ضربة جوية): تدخل من الجنوب وتخرج من الشمال
  for (const j of W.units) if (j.jetPath && !j.dead) {
    j.jt += dt; const k = j.jt / j.jdur;
    j.x = j.jx0 + (j.jx1 - j.jx0) * k; j.y = j.jy0 + (j.jy1 - j.jy0) * k; j.ang = Math.atan2(j.jy1 - j.jy0, j.jx1 - j.jx0);
    if (!j.dropped && Math.hypot(j.x - j.tx, j.y - j.ty) < 40) { j.dropped = true; for (let b = 0; b < 3; b++) W.proj.push({k: 'bomb', x0: j.x, y0: j.y, x1: j.tx + (wrand() - .5) * 40, y1: j.ty + (wrand() - .5) * 40, t: 0, dur: .9 + b * .25, side: 'iq'}); }
    if (k >= 1) { j.dead = true; j.gone = true; }
  }
  for (const u of W.units) if (u.falling > 0) { u.falling -= dt; u.y += dt * 20; u.ang += dt * 4; wp('smoke_dark', u.x, u.y, {s0: 6, s1: 26, a0: .6, life: 1.6, layer: 'mid'}); if (u.falling <= 0) { wboom(u.x, u.y, 1.5); u.gone = true; } }
  // الدفاع الجوي: يطلق صواريخ اعتراض على الصواريخ والطائرات المعادية في مداه
  for (const a of W.units) {
    if (a.dead || a.t !== 'ad') continue;
    a.cd -= dt; if (a.cd > 0) continue;
    const threats = W.proj.filter(p => (p.k === 'msl') && p.side !== a.side && !p.intercepted && !p.engaged && p.t > .25 * p.dur && Math.hypot(p.x1 - a.x, p.y1 - a.y) < UT.ad.airRng);
    const jets = W.units.filter(j => !j.dead && j.side !== a.side && (j.jetPath || j.t === 'drone') && !j.engaged && dist(j, a) < UT.ad.airRng);
    const m = threats[0] || null, jet = !m ? jets[0] : null;
    if (m) { m.engaged = true; const k = Math.min(.95, m.t / m.dur + .35), x = m.x0 + (m.x1 - m.x0) * k, y = m.y0 + (m.y1 - m.y0) * k; W.proj.push({k: 'int', x0: a.x, y0: a.y, x1: x, y1: y, t: 0, dur: Math.max(.3, (k - m.t / m.dur) * m.dur), side: a.side, vs: m, ok: wrand() < (a.side === 'tr' ? .5 : .45)}); W.stats[a.side === 'tr' ? 'mslIntTry' : 'trIntTry'] = 1; wsound('missile_pass', a.x, a.y, .35); a.cd = 1.1; }
    else if (jet) { jet.engaged = true; const ok = wrand() < (jet.t === 'drone' ? .55 : .28); const lead = {x: jet.x + Math.cos(jet.ang) * 60, y: jet.y + Math.sin(jet.ang) * 60}; const fake = {done: false, jet: ok ? jet : null}; W.proj.push({k: 'int', x0: a.x, y0: a.y, x1: lead.x, y1: lead.y, t: 0, dur: 1.2, side: a.side, vs: fake, ok}); if (ok && jet.jetPath) W.stats.jetsLost++; a.cd = 2.2; }
  }
  // صواريخ تركية دورية، ومسيّرة بيرقدار
  W.trMslT -= dt;
  if (W.trMslT <= 0 && !W.trCollapse) { W.trMslT = 60; const tg = densest('iq'); if (tg) { salvo('tr', {x: 1180, y: 380}, tg, 5); wlog('تركيا تطلق رشقة من 5 صواريخ على قواتنا', 'tr'); W.stats.trMsl += 5; } }
  W.droneT -= dt;
  if (W.droneT <= 0 && !W.trCollapse) { W.droneT = 75; const tgs = W.units.filter(v => v.side === 'iq' && !v.dead && v.t === 'tank'); if (tgs.length) { const tg = tgs[Math.floor(wrand() * tgs.length)]; const d = mkUnit('tr', 'heli', 1200, 300, {t: 'drone', spr: 'tb2', drone: tg, hp: 30}); d.t = 'drone'; wlog('مسيّرة بيرقدار تركية تتجه نحو دروعنا', 'tr'); wsound('drone', tg.x, tg.y, .4); } }
  for (const d of W.units) if (d.t === 'drone' && !d.dead) {
    const tg = d.drone; if (!tg || tg.dead) { d.dead = true; d.gone = true; continue; }
    const dx = tg.x - d.x, dy = tg.y - d.y, r = Math.hypot(dx, dy); d.ang = Math.atan2(dy, dx);
    if (r > 90) { d.x += dx / r * 26 * dt; d.y += dy / r * 26 * dt; }
    else if (!d.fired) { d.fired = true; W.proj.push({k: 'atgm', x0: d.x, y0: d.y, x1: tg.x, y1: tg.y, t: 0, dur: 1.2, target: tg, hit: wrand() < .7, dmg: 70, side: 'tr'}); setTimeout(() => { if (W && !d.dead) { d.dead = true; d.gone = true; } }, 2500); }
  }
  // السيطرة على المدن
  for (const tw of TOWNS) if (tw.obj) {
    let a = 0, b = 0;
    for (const u of W.units) if (!u.dead && !UT[u.t].air && u.t !== 'drone' && !u.retreat && Math.hypot(u.x - tw.x, u.y - tw.y) < tw.r) { if (u.side === 'iq') a += UT[u.t].cost; else b += UT[u.t].cost; }
    const before = W.ctl[tw.id];
    if (a > 0 && b === 0) W.ctl[tw.id] = Math.min(100, W.ctl[tw.id] + dt * 6 * Math.min(2, a / 3));
    else if (b > 0 && a === 0) W.ctl[tw.id] = Math.max(0, W.ctl[tw.id] - dt * 4);
    if (before < 100 && W.ctl[tw.id] >= 100) { wlog(`قواتنا تسيطر على ${tw.n}`, 'iq'); wsound('war_horn', tw.x, tw.y, .5); }
    if (before === 0 && W.ctl[tw.id] > 0) wlog(`قواتنا تدخل ${tw.n}`, 'iq');
  }
  // انهيار الدفاع التركي
  const sTr = strength('tr') / W.init.tr, sIq = strength('iq') / W.init.iq;
  if (!W.trCollapse && sTr < .4) { W.trCollapse = true; wlog('انهيار الدفاع التركي: القوات تنسحب شمالاً', 'iq'); }
  // انتهاء المعركة
  if (!W.end) {
    if (W.ctl.duhok >= 100) endWar('win');
    else if (sIq < .25) endWar('lose');
    else if (W.t >= 300) endWar('time');
  }
  // الجزيئات والحطام المحترق
  for (const dc of W.decals) if (dc.burn > 0) { dc.burn -= dt; dc.bt = (dc.bt || 0) - dt; if (dc.bt <= 0) { dc.bt = .5; wp('smoke_oil', dc.x, dc.y, {s0: 8, s1: 46, a0: .6, life: 3.4, vx: 5, vy: -7, layer: 'mid'}); wp('vehicle_fire', dc.x + (wrand() - .5) * 5, dc.y + (wrand() - .5) * 5, {s0: 10, s1: 15, a0: .85, life: .6, vr: 0}); } }
}
function densest(side){
  let best = null, bn = 0;
  for (const u of W.units) { if (u.side !== side || u.dead || UT[u.t].air) continue; let n = 0; for (const v of W.units) if (v.side === side && !v.dead && dist(u, v) < 60) n += UT[v.t].cost; if (n > bn) { bn = n; best = u; } }
  return best ? {x: best.x, y: best.y} : null;
}
function salvo(side, from, tg, n){
  wsound(side === 'iq' ? 'mlrs' : 'ballistic_launch', from.x, from.y, .7);
  for (let i = 0; i < n; i++) W.proj.push({k: 'msl', x0: from.x + (i % 3 - 1) * 8, y0: from.y, x1: tg.x + (wrand() - .5) * 50, y1: tg.y + (wrand() - .5) * 50, t: -i * .25, dur: 4.2, side});
}
// ------------------------------------------------------------------ أوامر اللاعب
function wOrder(k){
  if (!W || W.end) return;
  if (k === 'attack' || k === 'hold' || k === 'retreat') { W.order = k; wlog({attack: 'أمر: هجوم شامل', hold: 'أمر: تثبيت المواقع والرد بالنار', retreat: 'أمر: انسحاب منظم إلى خط البداية'}[k], 'iq'); }
  if (k === 'msl' && W.uses.msl > 0 && W.cool.msl <= 0) { const tg = densest('tr'); if (tg) { W.uses.msl--; W.cool.msl = 25; salvo('iq', {x: 1300, y: 1960}, tg, 8); W.stats.msl += 8; wlog('رشقة من 8 صواريخ على أكبر تجمع للعدو', 'iq'); } }
  if (k === 'air' && W.uses.air > 0 && W.cool.air <= 0) {
    const tg = densest('tr'); if (tg) { W.uses.air--; W.cool.air = 40; wlog('ضربة جوية: 4 مقاتلات F-16 تتجه إلى الهدف', 'iq'); wsound('jet_flyby', tg.x, tg.y, .8);
      for (let i = 0; i < 4; i++) { const x0 = tg.x - 90 + i * 60, j = mkUnit('iq', 'heli', x0, 2200 + i * 40, {jetPath: true, jt: 0, jdur: 9, jx0: x0, jy0: 2200 + i * 40, jx1: tg.x - 90 + i * 60 + 40, jy1: -150, tx: tg.x + (i - 1.5) * 20, ty: tg.y, spr: 'f16', hp: 40}); j.t = 'heli'; } }
  }
  if (k === 'res' && W.uses.res > 0) { W.uses.res--; const c = [[1220, 1085], [1180, 830], [1165, 670]]; for (const [t, dx] of [['tank', -30], ['tank', 10], ['tank', 50], ['ifv', -10], ['squad', -30], ['squad', 30]]) { const u = mkUnit('iq', t, 1240 + dx, 1600 + (t === 'squad' ? 40 : 0), {path: c.map(([x, y]) => ({x: x + dx * .4, y}))}); u.start = {x: u.x, y: u.y}; } wlog('دفع الاحتياط: 3 دبابات ومدرعة وفصيلا مشاة', 'iq'); }
  syncWarUI();
}
function syncWarUI(){
  const set = (id, txt, dis) => { const b = document.getElementById(id); if (b) { b.querySelector('small').textContent = txt; b.disabled = dis; } };
  set('wo-air', W.uses.air ? (W.cool.air > 0 ? `بعد ${Math.ceil(W.cool.air)} ث` : `باقي ${W.uses.air}`) : 'نفدت', !W.uses.air || W.cool.air > 0);
  set('wo-msl', W.uses.msl ? (W.cool.msl > 0 ? `بعد ${Math.ceil(W.cool.msl)} ث` : `باقي ${W.uses.msl}`) : 'نفدت', !W.uses.msl || W.cool.msl > 0);
  set('wo-res', W.uses.res ? '6 وحدات' : 'استُخدم', !W.uses.res);
  for (const k of ['attack', 'hold', 'retreat']) { const b = document.getElementById('wo-' + k); if (b) b.classList.toggle('on', W.order === k); }
  const m = Math.floor(W.t / 60), s = Math.floor(W.t % 60);
  document.getElementById('wtime').textContent = `${m}:${String(s).padStart(2, '0')} / 5:00`;
  const cnt = side => W.units.filter(u => u.side === side && !u.dead && (u.t === 'tank')).length;
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
    <div class="delta"><b>${W.stats.msl}</b><span>صواريخ أطلقناها<small>والعدو أطلق ${W.stats.trMsl}، وأسقطنا ${W.stats.jetsLost ? W.stats.jetsLost + ' مقاتلة لنا أُسقطت' : 'لم نخسر مقاتلات'}</small></span></div>
    <p class="tag" style="text-align:right">في اللعبة الحقيقية: المدن المأخوذة تنتقل إليك على الخريطة، والخسائر تُخصم من جيشك، والصواريخ من مخزونك.</p>
    <div class="act"><div class="btn"><button class="pri" onclick="startWar()">أعد المعركة</button><small>نفس الظروف</small></div><div class="btn"><button onclick="closeWar()">رجوع للخريطة</button><small></small></div></div></div>`;
  document.getElementById('wres').classList.add('on');
}

// ------------------------------------------------------------------ الرسم
const wc = () => document.getElementById('wc');
let wctx = null;
function wResize(){ const c = wc(), r = c.getBoundingClientRect(), d = Math.min(devicePixelRatio || 1, 2); c.width = r.width * d; c.height = r.height * d; wctx = c.getContext('2d'); wctx.setTransform(d, 0, 0, d, 0, 0); }
const ADDW = {fireball: 1, sparks: 1, muzzle: 1, exhaust: 1, intercept: 1, tracers: 1, ground_fire: 1, rifle_flash: 1, vehicle_fire: 1, flare: 1};
function img(k){ return WS[k] || VI[k]; }
const SHD = {};
function shadowOf(k){ if (SHD[k]) return SHD[k]; const im = img(k); if (!im || !im.complete || !im.width) return null; const cv = document.createElement('canvas'); cv.width = im.width; cv.height = im.height; const x = cv.getContext('2d'); x.drawImage(im, 0, 0); x.globalCompositeOperation = 'source-in'; x.fillStyle = '#000'; x.fillRect(0, 0, cv.width, cv.height); SHD[k] = cv; return cv; }
function shade(c, k, x, y, s, rot, a){ const sh = shadowOf(k); if (!sh) return; const w = s * sh.width / Math.max(sh.width, sh.height), h = s * sh.height / Math.max(sh.width, sh.height); c.save(); c.translate(x, y); c.rotate(rot); c.globalAlpha = a; c.drawImage(sh, -w / 2, -h / 2, w, h); c.restore(); }
function drawWar(dt){
  const c = wctx, Wd = wc().clientWidth, Hd = wc().clientHeight, cam = W.cam;
  // متابعة المعركة: الكاميرا تتجه نحو مقدمة القوات العراقية
  if (W.follow) { const f = W.units.filter(u => u.side === 'iq' && !u.dead && !UT[u.t].air && (u.t === 'tank' || u.t === 'ifv' || u.t === 'squad')); if (f.length) { const ty = Math.min(...f.map(u => u.y)) + 60, tx = f.reduce((s, u) => s + u.x, 0) / f.length; cam.x += (tx - cam.x) * Math.min(1, dt * .8); cam.y += (ty - cam.y) * Math.min(1, dt * .8); } }
  c.fillStyle = '#1a1712'; c.fillRect(0, 0, Wd, Hd);
  c.save(); c.translate(Wd / 2, Hd / 2); c.scale(cam.k, cam.k); c.translate(-cam.x, -cam.y);
  if (W_IMG.complete) c.drawImage(W_IMG, 0, 0, FIELD.w, FIELD.h);
  const vis = (x, y, m = 80) => Math.abs(x - cam.x) * cam.k < Wd / 2 + m * cam.k && Math.abs(y - cam.y) * cam.k < Hd / 2 + m * cam.k;
  const spr = (k, x, y, s, rot, a = 1, comp) => { const im = img(k); if (!im || !im.complete || !im.width) return; const w = s * im.width / Math.max(im.width, im.height), h = s * im.height / Math.max(im.width, im.height); c.save(); c.translate(x, y); c.rotate(rot); c.globalAlpha = a; if (comp) c.globalCompositeOperation = comp; c.drawImage(im, -w / 2, -h / 2, w, h); c.restore(); };
  // ظلال المباني ثم المباني
  for (const p of W.props) if (vis(p.x, p.y)) { shade(c, p.k, p.x + 3, p.y + 4, p.s, p.rot, .3); spr(p.k, p.x, p.y, p.s, p.rot); }
  for (const d of W.decals) if (vis(d.x, d.y)) spr(d.k, d.x, d.y, d.s, d.rot, d.a);
  // الوحدات الأرضية
  for (const u of W.units) {
    if (u.dead || u.gone || UT[u.t].air || u.t === 'drone' || u.jetPath || !vis(u.x, u.y)) continue;
    const d = UT[u.t], s = d.sz;
    shade(c, u.spr, u.x + 2.5, u.y + 3.5, s, u.ang + Math.PI / 2, .35);
    spr(u.spr, u.x, u.y, s, u.ang + Math.PI / 2, u.retreat ? .8 : 1);
    // علامة الطرف وشريط الصحة
    c.fillStyle = u.side === 'iq' ? '#d2a24c' : '#c0473b'; c.beginPath(); c.arc(u.x - s * .45, u.y - s * .45, 2.6, 0, 7); c.fill();
    if (cam.k > .8 && u.hp < d.hp) { c.fillStyle = 'rgba(0,0,0,.6)'; c.fillRect(u.x - 9, u.y + s * .55, 18, 3); c.fillStyle = u.hp > d.hp * .5 ? '#5fae7b' : '#d4574a'; c.fillRect(u.x - 9, u.y + s * .55, 18 * u.hp / d.hp, 3); }
  }
  drawWParts(dt, 'mid');
  // المقذوفات
  for (const p of W.proj) {
    if (p.t < 0) continue; const k = Math.min(1, p.t / p.dur);
    const x = p.x0 + (p.x1 - p.x0) * k, y = p.y0 + (p.y1 - p.y0) * k;
    if (p.k === 'tracer') { const x2 = p.x0 + (p.x1 - p.x0) * Math.max(0, k - .25), y2 = p.y0 + (p.y1 - p.y0) * Math.max(0, k - .25); c.strokeStyle = p.side === 'iq' ? 'rgba(255,210,120,.95)' : 'rgba(255,150,110,.95)'; c.lineWidth = 1.2; c.beginPath(); c.moveTo(x2, y2); c.lineTo(x, y); c.stroke(); }
    else if (p.k === 'shell') { if (p.dur < 1) { c.strokeStyle = 'rgba(255,240,200,.9)'; c.lineWidth = 1.6; c.beginPath(); c.moveTo(x - (p.x1 - p.x0) * .06, y - (p.y1 - p.y0) * .06); c.lineTo(x, y); c.stroke(); } else { const hy = y - Math.sin(k * Math.PI) * 60; c.fillStyle = 'rgba(255,230,180,.9)'; c.beginPath(); c.arc(x, hy, 1.4, 0, 7); c.fill(); } }
    else if (p.k === 'atgm' || p.k === 'rocket') { const ang = Math.atan2(p.y1 - p.y0, p.x1 - p.x0); if (wrand() < .5) wp('smoke_light', x, y, {s0: 3, s1: 12, a0: .45, life: 1.2, layer: 'mid'}); c.fillStyle = '#fff2c0'; c.beginPath(); c.arc(x, y, 1.8, 0, 7); c.fill(); spr('exhaust', x - Math.cos(ang) * 4, y - Math.sin(ang) * 4, 8, ang - Math.PI / 2, .9, 'lighter'); }
    else if (p.k === 'msl' || p.k === 'int' || p.k === 'bomb') {
      if (p.k === 'msl' && p.intercepted) continue;
      const arc = p.k === 'msl' ? Math.sin(k * Math.PI) * 140 : 0, hy = y - arc;
      const kp = Math.max(0, k - .02), px0 = p.x0 + (p.x1 - p.x0) * kp, py0 = p.y0 + (p.y1 - p.y0) * kp - (p.k === 'msl' ? Math.sin(kp * Math.PI) * 140 : 0);
      const ang = Math.atan2(hy - py0, x - px0);
      if (p.k !== 'bomb' && wrand() < .8) wp('smoke_light', x, hy, {s0: 4, s1: 18, a0: p.k === 'int' ? .4 : .55, life: 1.6, vx: 2, vy: -1, layer: 'mid'});
      spr('exhaust', x - Math.cos(ang) * 5, hy - Math.sin(ang) * 5, p.k === 'int' ? 8 : 12, ang - Math.PI / 2, .95, 'lighter');
      c.save(); c.translate(x, hy); c.rotate(ang); c.fillStyle = p.k === 'int' ? '#dfeaff' : '#e9e6dc'; c.fillRect(-5, -1.3, 8, 2.6); c.restore();
    }
  }
  // الطائرات والمروحيات والمسيّرات (ظل على الأرض بعيد عنها)
  for (const u of W.units) {
    if ((u.dead && !(u.falling > 0)) || u.gone || !(UT[u.t].air || u.t === 'drone' || u.jetPath)) continue;
    const s = u.jetPath ? 48 : u.t === 'drone' ? 32 : 42, h = u.jetPath ? 40 : 22;
    shade(c, u.spr, u.x + h * .6, u.y + h, s, u.ang + Math.PI / 2, .25);
    spr(u.spr, u.x, u.y, s, u.ang + Math.PI / 2);
    if (u.t === 'heli' && !u.jetPath) { c.strokeStyle = 'rgba(30,30,30,.35)'; c.lineWidth = 1; c.beginPath(); c.arc(u.x, u.y, s * .5, 0, 7); c.stroke(); }
  }
  drawWParts(dt, 'top');
  c.restore();
  // أسماء المدن وأشرطة السيطرة بحجم ثابت على الشاشة
  c.font = '700 13px "IBM Plex Sans Arabic", sans-serif'; c.textAlign = 'center'; c.direction = 'rtl';
  for (const tw of TOWNS) {
    const sx = (tw.x - cam.x) * cam.k + Wd / 2, sy = (tw.y - cam.y) * cam.k + Hd / 2; if (sx < -60 || sx > Wd + 60 || sy < -40 || sy > Hd + 40) continue;
    const y = sy - tw.r * cam.k - 8;
    c.lineWidth = 4; c.strokeStyle = 'rgba(5,9,13,.85)'; c.fillStyle = '#f3ede0'; c.strokeText(tw.n, sx, y); c.fillText(tw.n, sx, y);
    if (tw.obj) { const v = W.ctl[tw.id] / 100; c.fillStyle = 'rgba(5,9,13,.85)'; c.fillRect(sx - 26, y + 5, 52, 7); c.fillStyle = '#c0473b'; c.fillRect(sx - 25, y + 6, 50, 5); c.fillStyle = '#d2a24c'; c.fillRect(sx - 25, y + 6, 50 * v, 5); c.setLineDash([4, 4]); c.strokeStyle = 'rgba(243,237,224,.35)'; c.lineWidth = 1; c.beginPath(); c.arc(sx, sy, tw.r * cam.k, 0, 7); c.stroke(); c.setLineDash([]); }
  }
}
function drawWParts(dt, layer){
  const c = wctx;
  for (const p of W.parts) {
    if (p.layer !== layer) continue;
    if (p.delay > 0) { p.delay -= dt; continue; }
    p.t += dt; const k = p.t / p.life; if (k >= 1) continue;
    const e = 1 - Math.pow(1 - k, 2); p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.vr * dt;
    const sz = p.s0 + (p.s1 - p.s0) * e, al = p.a0 + (p.a1 - p.a0) * k; const im = img(p.img); if (!im || !im.complete || al <= 0) continue;
    c.save(); c.globalCompositeOperation = ADDW[p.img] ? 'lighter' : 'source-over'; c.globalAlpha = Math.max(0, Math.min(1, al)); c.translate(p.x, p.y); c.rotate(p.rot); c.drawImage(im, -sz / 2, -sz / 2, sz, sz); c.restore();
  }
  if (layer === 'top') W.parts = W.parts.filter(p => p.delay > 0 || p.t < p.life);
}

// ------------------------------------------------------------------ الحلقة والتحكم
function warLoop(now){
  const cv = wc(); if (cv && (Math.abs(cv.width - cv.clientWidth * Math.min(devicePixelRatio || 1, 2)) > 2 || Math.abs(cv.height - cv.clientHeight * Math.min(devicePixelRatio || 1, 2)) > 2)) wResize();
  const real = Math.min(.05, (now - wlast) / 1000); wlast = now;
  const dt = real * wspeed;
  if (W && !W.end && wspeed > 0) { let left = dt; while (left > 0) { const s = Math.min(.05, left); stepWar(s); left -= s; } }
  if (W) { drawWar(real * (wspeed || 0) || 0.0001); if ((W.uiT = (W.uiT || 0) - real) <= 0) { W.uiT = .25; syncWarUI(); } }
  wraf = requestAnimationFrame(warLoop);
}
function startWar(){
  document.getElementById('wres').classList.remove('on');
  stopLoops(); setupWar(); wspeed = 1; document.querySelectorAll('[data-wsp]').forEach(x => x.classList.toggle('on', x.dataset.wsp === '1'));
  audioInit(); ['front_ambience','tank_tracks','tank_cannon','hmg','hmg2','ak47','rpg','rifle','artillery','explosion_big','explosion_med','explosion_med2','intercept','missile_pass','mlrs','ballistic_launch','jet_flyby','drone','helicopter','war_horn','victory','defeat'].forEach(k => setTimeout(() => load(k), 5));
  setTimeout(() => { sloop('front_ambience', .3); sloop('tank_tracks', .18); sloop('helicopter', .12); }, 600);
  wResize(); syncWarUI();
}
function war(){ document.getElementById('war').classList.add('on'); startWar(); cancelAnimationFrame(wraf); wlast = performance.now(); wraf = requestAnimationFrame(warLoop); }
function closeWar(){ document.getElementById('war').classList.remove('on'); document.getElementById('wres').classList.remove('on'); cancelAnimationFrame(wraf); stopLoops(); W = null; }
addEventListener('resize', () => { if (W) wResize(); });
// لمس: سحب وتكبير بإصبعين، والسحب يوقف المتابعة التلقائية
(function(){
  const el = () => wc(); const pts = new Map(); let pinch = 0, last = null;
  document.addEventListener('DOMContentLoaded', () => {});
  const attach = () => {
    const c = el();
    c.addEventListener('pointerdown', e => { c.setPointerCapture(e.pointerId); pts.set(e.pointerId, e); last = e; if (pts.size === 2) { const [a, b] = [...pts.values()]; pinch = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY); } });
    c.addEventListener('pointermove', e => { if (!W || !pts.has(e.pointerId)) return; pts.set(e.pointerId, e);
      if (pts.size === 2 && pinch) { const [a, b] = [...pts.values()]; const d = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY); W.cam.k = Math.max(.3, Math.min(4, W.cam.k * d / pinch)); pinch = d; W.follow = false; return; }
      W.cam.x -= (e.clientX - last.clientX) / W.cam.k; W.cam.y -= (e.clientY - last.clientY) / W.cam.k; last = e; if (Math.abs(e.movementX) + Math.abs(e.movementY) > 1) { W.follow = false; document.getElementById('wfollow').classList.remove('on'); } });
    c.addEventListener('pointerup', e => { pts.delete(e.pointerId); if (pts.size < 2) pinch = 0; });
    c.addEventListener('pointercancel', e => { pts.delete(e.pointerId); pinch = 0; });
    c.addEventListener('wheel', e => { e.preventDefault(); if (W) { W.cam.k = Math.max(.3, Math.min(4, W.cam.k * (e.deltaY < 0 ? 1.15 : 1 / 1.15))); } }, {passive: false});
  };
  attach();
})();
document.querySelectorAll('[data-wsp]').forEach(b => b.onclick = () => { wspeed = +b.dataset.wsp; document.querySelectorAll('[data-wsp]').forEach(x => x.classList.toggle('on', x === b)); });
document.getElementById('wfollow').onclick = () => { if (W) { W.follow = !W.follow; document.getElementById('wfollow').classList.toggle('on', W.follow); } };
document.getElementById('wzin').onclick = () => { if (W) W.cam.k = Math.min(4, W.cam.k * 1.4); };
document.getElementById('wzout').onclick = () => { if (W) W.cam.k = Math.max(.3, W.cam.k / 1.4); };
document.getElementById('wclose').onclick = closeWar;
document.getElementById('wquick').onclick = () => { if (!W || W.end) return; let n = 0; while (!W.end && n < 6000) { stepWar(.05); n++; } };
