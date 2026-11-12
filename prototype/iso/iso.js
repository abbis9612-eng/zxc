// ================================================================== تجربة الزاوية المائلة: شارع، دبابات، مدفعية
// كل شيء مصوّر مسبقاً في Blender بنفس الكاميرا والشمس. العالم بالأمتار؛ الشاشة بنقاط صورة المشهد.
(async function(){
const P = PIXI;
const META = await (await fetch('scene/scene.json')).json();
const UM = {m1a1: await (await fetch('units/m1a1.json')).json(), t72: await (await fetch('units/t72.json')).json()};
const BM = await (await fetch('blast/blast.json')).json();
const MPP = META.mpp, SW = META.W, SH = META.H, TGT = META.tgt, RT = META.right, UP = META.up;
const F = (() => { const c = [RT[1] * UP[2] - RT[2] * UP[1], RT[2] * UP[0] - RT[0] * UP[2], RT[0] * UP[1] - RT[1] * UP[0]]; return c.map(v => -v); })();   // اتجاه نظر الكاميرا
// عالم ← نقطة في صورة المشهد
const proj = (x, y, z = 0) => { const d = [x - TGT[0], y - TGT[1], z - TGT[2]]; return [(d[0] * RT[0] + d[1] * RT[1] + d[2] * RT[2]) / MPP + SW / 2, -(d[0] * UP[0] + d[1] * UP[1] + d[2] * UP[2]) / MPP + SH / 2]; };
// نقطة صورة ← أرض (z=0)
const unproj = (sx, sy) => { const u = (sx - SW / 2) * MPP, v = -(sy - SH / 2) * MPP; const q = [TGT[0] + u * RT[0] + v * UP[0], TGT[1] + u * RT[1] + v * UP[1], TGT[2] + u * RT[2] + v * UP[2]]; const t = -q[2] / F[2]; return [q[0] + F[0] * t, q[1] + F[1] * t]; };
const app = new P.Application();
await app.init({resizeTo: window, backgroundColor: 0x1a1712, antialias: false, resolution: Math.min(devicePixelRatio || 1, 2), autoDensity: true, preference: 'webgl'});
document.body.appendChild(app.canvas);
const world = new P.Container(); app.stage.addChild(world);
const ground = new P.Sprite(await P.Assets.load('scene/ground.webp')); world.addChild(ground);
const decals = new P.Container(); world.addChild(decals);
const sorted = new P.Container(); sorted.sortableChildren = true; world.addChild(sorted);
const fxTop = new P.Container(); world.addChild(fxTop);
const lines = new P.Graphics(); fxTop.addChild(lines);
for (const s of META.sprites) { const sp = new P.Sprite(await P.Assets.load('scene/' + s.f)); sp.position.set(s.x, s.y); sp.zIndex = s.z; sorted.addChild(sp); }
// أطالس المركبات والانفجار
async function atlas(json, dir){ const pages = await Promise.all(json.pages.map(p => P.Assets.load(dir + p))); return json.frames.map(fr => ({tex: new P.Texture({source: pages[fr.p].source, frame: new P.Rectangle(fr.x, fr.y, fr.w, fr.h)}), ox: fr.ox, oy: fr.oy})); }
const UA = {}; for (const k in UM) UA[k] = {hull: await atlas(UM[k].hull, 'units/'), tur: await atlas(UM[k].tur, 'units/')};
const BA = await atlas(BM, 'blast/');
// توهج (فوهة، وميض) يُرسم بالكود
const glow = (() => { const c = document.createElement('canvas'); c.width = c.height = 128; const x = c.getContext('2d'), g = x.createRadialGradient(64, 64, 0, 64, 64, 64); g.addColorStop(0, 'rgba(255,250,220,1)'); g.addColorStop(.25, 'rgba(255,200,110,.9)'); g.addColorStop(.6, 'rgba(255,120,40,.35)'); g.addColorStop(1, 'rgba(255,90,20,0)'); x.fillStyle = g; x.fillRect(0, 0, 128, 128); return P.Texture.from(c); })();
const scorch = (() => { const c = document.createElement('canvas'); c.width = c.height = 128; const x = c.getContext('2d'), g = x.createRadialGradient(64, 64, 0, 64, 64, 64); g.addColorStop(0, 'rgba(18,14,10,.95)'); g.addColorStop(.45, 'rgba(30,24,18,.75)'); g.addColorStop(1, 'rgba(60,50,40,0)'); x.fillStyle = g; x.fillRect(0, 0, 128, 128); return P.Texture.from(c); })();
// ---------- الوحدات
const ND = 32, step = Math.PI * 2 / ND;
const dirIdx = a => ((Math.round(a / step) % ND) + ND) % ND;
const units = [];
function mkTank(kind, side, x, y, a){
  const u = {kind, side, x, y, a, ta: a, hp: 100, dead: false, cd: 3 + Math.random() * 3, goal: null, burn: 0, recoil: 0};
  u.hull = new P.Sprite(); u.tur = new P.Sprite(); u.box = new P.Container(); u.box.addChild(u.hull, u.tur); sorted.addChild(u.box); units.push(u); return u;
}
const me = mkTank('m1a1', 'iq', 1.6, -32, 0);
mkTank('t72', 'tr', -1.8, 26, Math.PI); mkTank('t72', 'tr', 2.2, 35, Math.PI);
function drawUnit(u){
  const A = UA[u.kind], M = UM[u.kind], k = dirIdx(u.a), kt = dirIdx(u.ta), [sx, sy] = proj(u.x, u.y);
  const h = A.hull[k]; u.hull.texture = h.tex; u.hull.position.set(sx - (M.origin[0] - h.ox), sy - (M.origin[1] - h.oy));
  const t = A.tur[kt], pv = M.pivot[k], rc = u.recoil * .35 / MPP;
  u.tur.texture = t.tex; u.tur.position.set(sx + (pv[0] - M.origin[0]) - (M.tpivot[0] - t.ox) + Math.sin(u.ta) * rc * .7, sy + (pv[1] - M.origin[1]) - (M.tpivot[1] - t.oy) + Math.cos(u.ta) * rc * .4);
  const tint = u.dead ? 0x3a3530 : 0xffffff; u.hull.tint = tint; u.tur.tint = tint;
  u.box.zIndex = sy + 6;
}
// ---------- الانفجارات
const blasts = [];
function boom(x, y, scale = 1){
  const sp = new P.Sprite(); sorted.addChild(sp); const [sx, sy] = proj(x, y);
  blasts.push({sp, sx, sy, t: 0, sc: scale * BM.mpp / MPP});
  const d = new P.Sprite(scorch); d.anchor.set(.5); const r = 3.2 * scale / MPP; d.width = r * 2; d.height = r * 1.25; d.position.set(sx, sy); d.alpha = .85; decals.addChild(d);
  flash(x, y, 1.6, 9 * scale); shake = Math.max(shake, 8 * scale);
  for (const u of units) if (!u.dead) { const r_ = Math.hypot(u.x - x, u.y - y); if (r_ < 8 * scale) hit(u, 70 * (1 - r_ / (8 * scale))); }
}
function stepBlasts(dt){
  for (const b of blasts) {
    b.t += dt; let i = 0; while (i < BM.times.length - 1 && BM.times[i + 1] <= b.t) i++;
    const fr = BA[i], fade = b.t > BM.times[BM.times.length - 1] ? Math.max(0, 1 - (b.t - BM.times[BM.times.length - 1]) / 3) : 1;
    b.sp.texture = fr.tex; b.sp.scale.set(b.sc); b.sp.position.set(b.sx - (BM.ox - fr.ox) * b.sc, b.sy - (BM.oy - fr.oy) * b.sc); b.sp.alpha = fade; b.sp.zIndex = b.sy + 2;
    if (fade <= 0) { b.sp.destroy(); b.done = true; }
  }
  for (let i = blasts.length - 1; i >= 0; i--) if (blasts[i].done) blasts.splice(i, 1);
}
const flashes = [];
function flash(x, y, z, sizeM){ const s = new P.Sprite(glow); s.anchor.set(.5); s.blendMode = 'add'; const [sx, sy] = proj(x, y, z); s.position.set(sx, sy); s.width = s.height = sizeM / MPP; fxTop.addChild(s); flashes.push({s, t: 0, life: .14}); }
// ---------- القتال
const tracers = [];
function hit(u, dmg){ if (u.dead) return; u.hp -= dmg; if (u.hp <= 0) { u.dead = true; u.burn = 1; flash(u.x, u.y, 2, 14); } }
function fire(u, v){
  const ang = u.ta, L = UM[u.kind].len * .55, tx = u.x - Math.sin(ang) * L, ty = u.y + Math.cos(ang) * L;
  flash(tx, ty, 2.3, 7); u.recoil = 1;
  const ok = Math.random() < .6, ex = v.x + (ok ? 0 : (Math.random() - .5) * 10), ey = v.y + (ok ? 0 : (Math.random() - .5) * 10);
  tracers.push({x0: tx, y0: ty, x1: ex, y1: ey, t: 0, dur: Math.max(.05, Math.hypot(ex - tx, ey - ty) / 1700 * 3), v: ok ? v : null, dmg: u.kind === 'm1a1' ? 60 : 28});   /* درع الأبرامز الأمامي يصمد أمام قذائف T-72 */
}
// ---------- اللمس: نقرة = تحريك دبابتك، سحب = تحريك الكاميرا، إصبعان = تقريب
const minS = () => Math.max(innerWidth / (SW * .8), innerHeight / (SH * .8));
let cam = {x: proj(0, -18)[0], y: proj(0, -18)[1], s: .3}, shake = 0, follow = true;
const pts = new Map(); let pinch0 = 0, moved = false, last = null;
app.canvas.addEventListener('pointerdown', e => { pts.set(e.pointerId, e); moved = false; last = e; if (pts.size === 2) { const [a, b] = [...pts.values()]; pinch0 = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY); } });
app.canvas.addEventListener('pointermove', e => { if (!pts.has(e.pointerId)) return; pts.set(e.pointerId, e);
  if (pts.size === 2) { const [a, b] = [...pts.values()], d = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY); cam.s = Math.max(minS(), Math.min(1.1, cam.s * d / pinch0)); pinch0 = d; moved = true; return; }
  if (last && Math.hypot(e.clientX - last.clientX, e.clientY - last.clientY) > 4) { moved = true; follow = false; cam.x -= (e.clientX - last.clientX) / cam.s; cam.y -= (e.clientY - last.clientY) / cam.s; last = e; } });
app.canvas.addEventListener('pointerup', e => { pts.delete(e.pointerId); if (!moved && pts.size === 0) { const sx = (e.clientX - innerWidth / 2) / cam.s + cam.x, sy = (e.clientY - innerHeight / 2) / cam.s + cam.y; const [x, y] = unproj(sx, sy); if (!me.dead) me.goal = {x, y}; follow = true; ping(sx, sy); } });
app.canvas.addEventListener('wheel', e => { e.preventDefault(); cam.s = Math.max(minS(), Math.min(1.1, cam.s * (e.deltaY < 0 ? 1.12 : 1 / 1.12))); }, {passive: false});
const pings = [];
function ping(sx, sy){ pings.push({sx, sy, t: 0}); }
// ---------- الحلقة
let artT = 3, fpsN = 0, fpsT = 0;
const hud = document.getElementById('hud');
app.ticker.add(tk => {
  const dt = Math.min(.05, tk.deltaMS / 1000);
  for (const u of units) {
    if (u.dead) { u.burn += dt; if (Math.random() < dt * 6) { const [sx, sy] = proj(u.x, u.y, 2); } drawUnit(u); continue; }
    // الحركة: تدور ثم تمشي، أبطأ في المنعطف
    if (u.goal) { const dx = u.goal.x - u.x, dy = u.goal.y - u.y, r = Math.hypot(dx, dy); if (r < 1.5) u.goal = null; else { const want = Math.atan2(-dx, dy); let da = Math.atan2(Math.sin(want - u.a), Math.cos(want - u.a)); u.a += Math.max(-.7 * dt, Math.min(.7 * dt, da)); const sp = 6 * Math.max(.15, Math.cos(Math.min(1.4, Math.abs(da)))); u.x -= Math.sin(u.a) * sp * dt; u.y += Math.cos(u.a) * sp * dt; } }
    // البرج نحو أقرب عدو حي
    let tgt = null, bd = 1e9; for (const v of units) if (v.side !== u.side && !v.dead) { const d = Math.hypot(v.x - u.x, v.y - u.y); if (d < bd) { bd = d; tgt = v; } }
    if (tgt && bd < 90) { const want = Math.atan2(-(tgt.x - u.x), tgt.y - u.y); const da = Math.atan2(Math.sin(want - u.ta), Math.cos(want - u.ta)); u.ta += Math.max(-1.2 * dt, Math.min(1.2 * dt, da)); u.cd -= dt; if (u.cd <= 0 && Math.abs(da) < .05) { fire(u, tgt); u.cd = 7 + Math.random(); } }
    else { const da = Math.atan2(Math.sin(u.a - u.ta), Math.cos(u.a - u.ta)); u.ta += Math.max(-1.2 * dt, Math.min(1.2 * dt, da)); }
    u.recoil = Math.max(0, u.recoil - dt * 3); drawUnit(u);
  }
  // المقذوفات
  lines.clear();
  for (const t of tracers) { t.t += dt; const k = Math.min(1, t.t / t.dur); const x = t.x0 + (t.x1 - t.x0) * k, y = t.y0 + (t.y1 - t.y0) * k, [a, b] = proj(x, y, 2.2), kb = Math.max(0, k - .25), [c, d] = proj(t.x0 + (t.x1 - t.x0) * kb, t.y0 + (t.y1 - t.y0) * kb, 2.2); lines.moveTo(c, d).lineTo(a, b).stroke({width: 3, color: 0xfff0c0, alpha: .9}); if (k >= 1 && !t.done) { t.done = true; flash(t.x1, t.y1, 1, 5); if (t.v) hit(t.v, t.dmg); } }
  for (let i = tracers.length - 1; i >= 0; i--) if (tracers[i].done) tracers.splice(i, 1);
  for (const f of flashes) { f.t += dt; f.s.alpha = Math.max(0, 1 - f.t / f.life); if (f.t > f.life) { f.s.destroy(); f.done = true; } }
  for (let i = flashes.length - 1; i >= 0; i--) if (flashes[i].done) flashes.splice(i, 1);
  for (const g of pings) { g.t += dt; const k = g.t / .7; if (k < 1) lines.circle(g.sx, g.sy, (10 + 40 * k) / cam.s * .4).stroke({width: 3 / cam.s, color: 0xffe08a, alpha: 1 - k}); }
  while (pings.length && pings[0].t > .7) pings.shift();
  // مدفعية العدو: قذيفة 155 كل بضع ثوانٍ قرب دبابتك أو على الشارع
  artT -= dt; if (artT <= 0) { artT = 8 + Math.random() * 7; const near = Math.random() < .35 && !me.dead, a = Math.random() * 6.28, r = 12 + Math.random() * 18; boom(near ? me.x + Math.cos(a) * r : (Math.random() - .5) * 30, near ? me.y + Math.sin(a) * r : -30 + Math.random() * 60, .85 + Math.random() * .3); }
  stepBlasts(dt);
  // الكاميرا
  if (follow && !me.dead) { const [sx, sy] = proj(me.x, me.y); cam.x += (sx - cam.x) * Math.min(1, dt * 1.5); cam.y += (sy - 120 - cam.y) * Math.min(1, dt * 1.5); }
  cam.s = Math.max(minS(), cam.s); const hw = innerWidth / 2 / cam.s, hh = innerHeight / 2 / cam.s; cam.x = Math.max(hw, Math.min(SW - hw, cam.x)); cam.y = Math.max(hh, Math.min(SH - hh, cam.y));
  shake = Math.max(0, shake - dt * 30); const jx = (Math.random() - .5) * shake, jy = (Math.random() - .5) * shake;
  world.scale.set(cam.s); world.position.set(innerWidth / 2 - cam.x * cam.s + jx, innerHeight / 2 - cam.y * cam.s + jy);
  fpsN++; fpsT += dt; if (fpsT >= 1) { hud.textContent = Math.round(fpsN / fpsT) + ' fps · دبابتك ' + Math.max(0, Math.round(me.hp)) + '% · العدو ' + units.filter(u => u.side === 'tr' && !u.dead).length; fpsN = 0; fpsT = 0; }
});
window.ISO = {units, boom, cam, proj, me};
})();
