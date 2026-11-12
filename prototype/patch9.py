# ساحة المعركة الحقيقية (5×5 كم حول بلدة شزي): أهداف جديدة، وتوزيع جديد، وأرض تؤثر في القتال
w = open('war.js').read()
def rep(a, b, cnt=1):
    global w
    assert a in w, 'MISSING: ' + a[:90]
    w = w.replace(a, b) if cnt == 0 else w.replace(a, b, cnt)
# ---------- 1) الارتفاعات من الخريطة الجديدة
rep("const HG = (() => { const b = Uint8Array.from(atob(HGRID.H)",
    "const HGRIDN = (typeof MAP2 !== 'undefined') ? MAP2.hgrid : HGRID;\nconst HG = (() => { const HGRID = HGRIDN; const b = Uint8Array.from(atob(HGRID.H)")
rep("function hAt(x, y){\n  const gx = (x - HGRID.x0) / HGRID.cell, gy = (y - HGRID.y0) / HGRID.cell;",
    "function hAt(x, y){\n  const HGRID = HGRIDN, gx = (x - HGRID.x0) / HGRID.cell, gy = (y - HGRID.y0) / HGRID.cell;")
# ---------- 2) أنواع الأرض: سرعة، واحتماء، وحجب رؤية
rep("// المدن بمواقعها الحقيقية",
"""// أنواع الأرض كل 10 م: 0 مفتوحة، 1 إسفلت، 2 ترابي/حصو، 3 حقل، 4 منحدر صخري، 5 بيوت، 6 ماء، 7 قاع وادٍ، 8 أشجار
const TERR = (typeof MAP2 !== 'undefined') ? (() => { const t = MAP2.terr; return {x0: t.x0, y0: t.y0, cell: t.cell, w: t.w, h: t.h, T: Uint8Array.from(atob(t.T), c => c.charCodeAt(0))}; })() : null;
function terAt(x, y){ if (!TERR) return 0; const i = Math.floor((x - TERR.x0) / TERR.cell), j = Math.floor((y - TERR.y0) / TERR.cell); return (i < 0 || j < 0 || i >= TERR.w || j >= TERR.h) ? 0 : TERR.T[j * TERR.w + i]; }
const TSPD_V = [.9, 1.25, 1.05, .72, .45, .6, .05, .65, .7];     // المركبات: الإسفلت أسرع، والحقل المحروث والصخر والوادي أبطأ
const TSPD_I = [1, 1.05, 1, .9, .7, .85, .2, .9, .9];            // المشاة
const TCOV = [1, 1, 1, .95, .85, .55, 1, .7, .8];                // الاحتماء: البيوت، والوادي يخفي، والأشجار
// المدن بمواقعها الحقيقية""")
rep("const TOWNS = [", "const TOWNS = (typeof MAP2 !== 'undefined') ? MAP2.obj.map(o => Object.assign({obj: true, houses: 4}, o)) : [")
rep("function cover(u){ let c = 1; if (u.dug && !u.moving) c *= .5; if (inTown(u)) c *= .6;",
    "function cover(u){ let c = 1; if (u.dug && !u.moving) c *= .5; if (TERR) c *= TCOV[terAt(u.x, u.y)] || 1; else if (inTown(u)) c *= .6;")
rep("function inTown(u){ for (const t of TOWNS) if (", "function inTown(u){ if (TERR) return terAt(u.x, u.y) === 5 ? TOWNS[0] : null; for (const t of TOWNS) if (")
# الرؤية: البيوت والأشجار تحجب (ارتفاع البيت ~7 م والشجرة ~6 م)
rep("for (let i = 1; i < n; i++) { const k = i / n, h = hAt(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k);",
    "for (let i = 1; i < n; i++) { const k = i / n, px = a.x + (b.x - a.x) * k, py = a.y + (b.y - a.y) * k, tt = TERR ? terAt(px, py) : 0, h = hAt(px, py) + (tt === 5 ? 7 : tt === 8 ? 6 : 0);")
rep("const ha = hAt(a.x, a.y) + 4, hb = hAt(b.x, b.y) + 3, n = Math.max(4, Math.ceil(dist(a, b) / 3));",
    "const ha = hAt(a.x, a.y) + 4, hb = hAt(b.x, b.y) + 3, n = Math.max(4, Math.ceil(dist(a, b) / (TERR ? 1.5 : 3)));")
# السرعة حسب نوع الأرض، وحدود الساحة
rep("  if (u.retreat) f *= W.trCollapse && u.side === 'tr' ? 1.8 : 1.3;",
    "  if (TERR && !d.air) { const tt = terAt(u.x, u.y); f *= d.veh ? TSPD_V[tt] : TSPD_I[tt]; }\n  if (u.retreat) f *= W.trCollapse && u.side === 'tr' ? 1.8 : 1.3;")
rep("    u.x += Math.cos(u.ang) * u.v * dt; u.y += Math.sin(u.ang) * u.v * dt; u.moving = u.v > .02;\n  } else {",
    "    u.x += Math.cos(u.ang) * u.v * dt; u.y += Math.sin(u.ang) * u.v * dt; u.moving = u.v > .02;\n    if (TERR) { u.x = Math.max(3, Math.min(197, u.x)); u.y = Math.max(-60, Math.min(230, u.y)); }\n  } else {")
# ---------- 3) الأهداف: البلدة، والتلة، والمفرق
rep("ctl: {duhok: 0, simele: 0, alqosh: 0}", "ctl: Object.fromEntries(TOWNS.filter(t => t.obj).map(t => [t.id, 0]))")
rep("if (W.ctl.duhok >= 100) endWar('win');", "if (W.ctl[TOWNS[0].id] >= 100) endWar('win');")
# ---------- 4) التوزيع الجديد (إن وُجدت الخريطة الحقيقية)
a = w.index("  // خط الدفاع التركي الأول على السلسلة الجنوبية"); b = w.index("  for (const u of W.units) u.start = {x: u.x, y: u.y};", a)
old = w[a:b]
new = """  if (typeof MAP2 !== 'undefined') { setupMap2(); } else {
""" + old + """  }
"""
w = w[:a] + new + w[b:]
rep("function nearestEnemy(u){", """// ---- ساحة شزي (وحدة = 30 م، مركز الساحة 100,100، الشمال الشرقي للأعلى). المهاجم من السهل الجنوبي، والمدافع في البلدة والتلة
function setupMap2(){
  const [T, H, X] = TOWNS;
  W.cam = {x: 100, y: 165, k: 6};
  // خنادق: خط أمامي على أطراف البلدة الجنوبية، وخط داخل البلدة، ومواقع على التلة والمفرق
  const line1 = [[78, 101], [90, 99], [102, 98], [114, 99], [126, 102]];
  for (const [x, y] of line1) { W.props.push({k: 'trench', x, y: y + 1.5, s: 34, rot: 0, trench: true}); W.props.push({k: 'sandbags', x: x + 4, y: y - .8, s: 8, rot: 0}); }
  for (const [x, y] of [[H.x - 3, H.y + 3], [H.x + 4, H.y + 4], [X.x, X.y + 3]]) W.props.push({k: 'trench', x, y, s: 30, rot: 0, trench: true});
  W.props.push({k: 'checkpoint', x: X.x + 2, y: X.y, s: 9, rot: 0});
  for (const [k, x, y, r] of [['car_burnt', 96, 120, .4], ['car_burnt', 108, 140, 2.1], ['pickup', 84, 112, 1.2], ['car', 101, 92, 3.0], ['car_burnt', 92, 78, .9]]) W.props.push({k, x, y, s: 2.6, rot: r});
  // تركيا: الخط الأمامي
  line1.forEach(([x, y], i) => { mkUnit('tr', 'squad', x - 1.5, y, {dug: true}); if (i % 2 === 0) mkUnit('tr', 'atgm', x + 3.5, y + .5, {dug: true}); });
  mkUnit('tr', 'mg', 96, 99, {dug: true}); mkUnit('tr', 'mg', 120, 100, {dug: true}); mkUnit('tr', 'sniper', 104, 92, {dug: true});
  mkUnit('tr', 'tank', 92, 90); mkUnit('tr', 'tank', 112, 90); mkUnit('tr', 'ifv', 102, 88);
  // البلدة
  for (const [x, y] of [[92, 76], [104, 74], [98, 68]]) { mkUnit('tr', 'squad', x, y, {dug: true}); }
  mkUnit('tr', 'atgm', 100, 80, {dug: true}); mkUnit('tr', 'mg', 108, 78, {dug: true});
  mkUnit('tr', 'tank', 94, 64); mkUnit('tr', 'tank', 108, 64); mkUnit('tr', 'ifv', 101, 60); mkUnit('tr', 'mortar', 100, 54);
  // التلة والمفرق
  mkUnit('tr', 'squad', H.x - 3, H.y + 3, {dug: true}); mkUnit('tr', 'atgm', H.x + 4, H.y + 4, {dug: true}); mkUnit('tr', 'sniper', H.x, H.y + 1, {dug: true}); mkUnit('tr', 'mortar', H.x + 2, H.y - 6);
  mkUnit('tr', 'squad', X.x - 1, X.y + 3, {dug: true}); mkUnit('tr', 'atgm', X.x + 3, X.y + 3, {dug: true}); mkUnit('tr', 'tank', X.x + 2, X.y - 4);
  // احتياط الهجوم المضاد شرقاً
  mkUnit('tr', 'squad', 138, 88); mkUnit('tr', 'squad', 142, 92); mkUnit('tr', 'ifv', 140, 84); mkUnit('tr', 'tank', 146, 86);
  // الإسناد التركي من خارج الساحة (شمالاً)
  mkUnit('tr', 'arty', 88, -40); mkUnit('tr', 'arty', 112, -42); mkUnit('tr', 'ad', 110, 10); mkUnit('tr', 'heli', 118, 8);
  // العراق: ثلاث مجموعات على خط الانطلاق جنوب الساحة
  const C = [[100, 150], [100, 112], [T.x, T.y + 4]], Ww = [[74, 150], [X.x, X.y + 2], [T.x - 6, T.y + 2]], E = [[132, 150], [126, 104], [H.x, H.y + 2]];
  const sc = .25;
  const grp = (pts, list, x0, y0, g) => list.forEach(([t, dx, dy]) => mkUnit('iq', t, x0 + dx * sc, y0 + dy * sc, {grp: g, path: pts.map(([x, y]) => ({x: x + dx * sc * .5, y: y + dy * sc * .3}))}));
  grp(C, [['tank', -36, 0], ['tank', 0, -6], ['tank', 36, 0], ['ifv', -18, 26], ['ifv', 18, 26], ['squad', -40, 46], ['squad', 0, 50], ['squad', 40, 46], ['atgm', 0, 72], ['mg', -26, 76], ['sniper', 26, 76], ['mortar', -12, 100], ['mortar', 12, 100]], 100, 184, 'الوسط');
  grp(E, [['tank', -28, 0], ['tank', 8, -6], ['tank', 44, 4], ['ifv', 0, 26], ['squad', -22, 46], ['squad', 22, 46], ['atgm', 0, 68], ['mortar', 0, 92]], 136, 186, 'الشرق');
  grp(Ww, [['tank', -18, 0], ['tank', 18, 0], ['ifv', 0, 24], ['squad', -18, 44], ['squad', 18, 44]], 68, 186, 'الغرب');
  // الإسناد العراقي من خارج الساحة (جنوباً)
  mkUnit('iq', 'arty', 86, 236); mkUnit('iq', 'arty', 100, 240); mkUnit('iq', 'arty', 114, 236);
  mkUnit('iq', 'mlrs', 92, 250); mkUnit('iq', 'mlrs', 108, 252);
  mkUnit('iq', 'ad', 100, 214);
  mkUnit('iq', 'heli', 84, 205, {grp: 'المروحيات'}); mkUnit('iq', 'heli', 118, 205, {grp: 'المروحيات'});
  mkUnit('iq', 'recon', 100, 150, {orbit: {x: 100, y: 95, r: 30}, oa: 0});
}
function nearestEnemy(u){""")
# ---------- 5) أماكن ثابتة أخرى من الخريطة القديمة
M2 = "(typeof MAP2 !== 'undefined')"
rep("for (const x of [1120, 1220, 1320]) { W.smokes.push({x, y: 1150, r: 30, until: W.t + 150}); for (let i = 0; i < 4; i++) wp('smoke_screen', x + (i - 1.5) * 16, 1150 + (wrand() - .5) * 10,",
    f"const SY = {M2} ? 112 : 1150, SR = {M2} ? 8 : 30; for (const x of ({M2} ? [86, 100, 114] : [1120, 1220, 1320])) {{ W.smokes.push({{x, y: SY, r: SR, until: W.t + 150}}); for (let i = 0; i < 4; i++) wp('smoke_screen', x + (i - 1.5) * SR * .5, SY + (wrand() - .5) * 3,")
rep("goal = u.side === 'iq' ? u.start : {x: u.x, y: 280};", f"goal = u.side === 'iq' ? u.start : {{x: u.x, y: {M2} ? -40 : 280}};")
rep("const tg_y_exit = j => (j.drone ? j.drone.y : 1200) - 10 * KM;", f"const tg_y_exit = j => (j.drone ? j.drone.y : ({M2} ? 100 : 1200)) - 10 * KM;")
rep("if (W.phase !== 'prep' && !j.moved) { j.moved = true; o.y -= 230; }", f"if (W.phase !== 'prep' && !j.moved) {{ j.moved = true; o.y -= {M2} ? 25 : 230; }}")
rep("const x0 = 1150 + i * 25, y0 = 180, tx = tg.x + (wrand() - .5) * 40, ty = tg.y + (wrand() - .5) * 40,",
    f"const x0 = ({M2} ? 95 : 1150) + i * 25, y0 = {M2} ? -800 : 180, sp_ = {M2} ? 8 : 40, tx = tg.x + (wrand() - .5) * sp_, ty = tg.y + (wrand() - .5) * sp_,")
rep("const c = [[1220, 1085], [1180, 830], [1165, 670]];", f"const c = {M2} ? [[100, 150], [100, 112], [TOWNS[0].x, TOWNS[0].y + 4]] : [[1220, 1085], [1180, 830], [1165, 670]];")
# الكثافة والتشتت ونصف قطر الضرر بحجمها الحقيقي (الوحدة فصيل منتشر ~100-200 م)
rep("if (v.side === side && ground(v) && dist(u, v) < 60) n += UT[v.t].cost;", f"if (v.side === side && ground(v) && dist(u, v) < ({M2} ? 15 : 60)) n += UT[v.t].cost;")
rep("const tx = v.x + (wrand() - .5) * 24, ty = v.y + (wrand() - .5) * 24,", f"const SC_ = {M2} ? 7 : 24, tx = v.x + (wrand() - .5) * SC_, ty = v.y + (wrand() - .5) * SC_,")
rep("const A = {arty: p.area, rkt: 30, bm: 40, agm: 34}[p.k]", f"const RS_ = {M2} ? .3 : 1, A = {{arty: p.area, rkt: 30, bm: 40, agm: 34}}[p.k] * RS_")
rep("v.smokeUsed = true; W.smokes.push({x: v.x, y: v.y, r: 18, until: W.t + 90});", f"v.smokeUsed = true; W.smokes.push({{x: v.x, y: v.y, r: {M2} ? 5 : 18, until: W.t + 90}});")
# الكاميرا تتبع مقدمة القوات
rep("const ty = Math.min(...f.map(u => u.y)) + 70, tx = f.reduce((s, u) => s + u.x, 0) / f.length;", f"const ty = Math.min(...f.map(u => u.y)) + ({M2} ? 22 : 70), tx = f.reduce((s, u) => s + u.x, 0) / f.length;", 0)
open('war.js', 'w').write(w)
print('ok')
