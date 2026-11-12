const { chromium, devices } = require('playwright');
(async () => {
  const b = await chromium.launch({args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader']});
  const p = await (await b.newContext({ ...devices['Pixel 7'], deviceScaleFactor: 1 })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e)));
  await p.route('**/*', r => { const u = r.request().url(); return (u.startsWith('http://127.0.0.1') || u.startsWith('data:') || u.startsWith('blob:')) ? r.continue() : r.abort(); });
  await p.goto('http://127.0.0.1:8765/index.html'); await p.waitForTimeout(1500);
  const c = async s => { const r = await p.locator(s).first().boundingBox(); await p.touchscreen.tap(r.x + r.width / 2, r.y + r.height / 2); };
  await c('#advice');
  await p.waitForFunction(() => window.PXW && PXW.ok, null, {timeout: 30000});
  await p.evaluate(() => { wspeed = 4; });
  // نلعب بالسرعة الطبيعية ×4 ونصور كل 20 ثانية حقيقية (80 ثانية معركة) مع متابعة الكاميرا
  for (let i = 0; i < 5; i++) {
    await p.waitForTimeout(i === 0 ? 3000 : 25000);
    const info = await p.evaluate(() => ({t: Math.round(W.t), k: +W.cam.k.toFixed(2), parts: W.parts.length, proj: W.proj.length, fx: 0}));
    await p.screenshot({path: `audit/a${String(i).padStart(2, '0')}.png`});
    console.log(i, JSON.stringify(info));
  }
  console.log('ERRS', JSON.stringify(errs.slice(0, 5)));
  await b.close();
})();
