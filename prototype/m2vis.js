const { chromium, devices } = require('playwright');
(async () => {
  const b = await chromium.launch({args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader']});
  const p = await (await b.newContext({ ...devices['Pixel 7'], deviceScaleFactor: 1 })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.route('**/*', r => { const u = r.request().url(); return (u.startsWith('http://127.0.0.1') || u.startsWith('data:') || u.startsWith('blob:')) ? r.continue() : r.abort(); });
  await p.goto('http://127.0.0.1:8765/index.html'); await p.waitForTimeout(1500);
  const tap = async s => { const r = await p.locator(s).first().boundingBox(); await p.touchscreen.tap(r.x + r.width / 2, r.y + r.height / 2); };
  await tap('#advice'); await p.waitForTimeout(3000);
  const shot = async (n, f, a) => { if (f) await p.evaluate(f, a); await p.waitForTimeout(2500); await p.screenshot({path: `m2/${n}.png`, timeout: 90000}); };
  await shot('a_start');
  await shot('b_whole', () => { W.follow = false; W.cam.x = 100; W.cam.y = 100; W.cam.k = 2.1; });
  await shot('c_town_k10', () => { W.cam.x = TOWNS[0].x; W.cam.y = TOWNS[0].y + 8; W.cam.k = 10; });
  await shot('d_town_k40', () => { W.cam.k = 40; });
  await shot('e_town_k150', () => { W.cam.k = 150; });
  // نلعب 7 دقائق من المعركة بسرعة ثم ننظر للجبهة
  await p.evaluate(() => { wspeed = 0; for (let i = 0; i < 6000 && W.t < 600; i++) stepWar(.1); wspeed = 1; W.follow = true; W.cam.k = 6; });
  await shot('f_battle_t600');
  await shot('g_front_k40', () => { W.follow = false; const u = W.units.filter(v => v.side === 'iq' && (v.t === 'tank' || v.t === 'ifv' || v.t === 'squad') && !v.dead).sort((a, b) => a.y - b.y)[0] || TOWNS[0]; W.cam.x = u.x; W.cam.y = u.y; W.cam.k = 40; });
  console.log(JSON.stringify(await p.evaluate(() => ({t: Math.round(W.t), ctl: W.ctl, iq: (strength('iq') / W.init.iq).toFixed(2), tr: (strength('tr') / W.init.tr).toFixed(2)}))), 'ERRS', errs.slice(0, 3));
  await b.close();
})();
