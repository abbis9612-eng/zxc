const { chromium, devices } = require('playwright');
(async () => {
  const b = await chromium.launch({args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader']});
  const p = await (await b.newContext({ ...devices['Pixel 7'], deviceScaleFactor: 1 })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(String(e))); p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  await p.goto('http://127.0.0.1:8766/index.html'); await p.waitForFunction(() => window.ISO, null, {timeout: 60000}).catch(e => errs.push('no ISO'));
  await p.waitForTimeout(2500); await p.screenshot({path: 'shots/s1.png'});
  // نقرة لتحريك الدبابة للأمام
  await p.touchscreen.tap(206, 300); await p.waitForTimeout(5000); await p.screenshot({path: 'shots/s2.png'});
  await p.evaluate(() => { const m = ISO.me; ISO.boom(m.x + 12, m.y + 16, 1); }); await p.waitForTimeout(700); await p.screenshot({path: 'shots/s3.png'});
  await p.waitForTimeout(2500); await p.screenshot({path: 'shots/s4.png'});
  await p.evaluate(() => { ISO.cam.s = .2; }); await p.waitForTimeout(800); await p.screenshot({path: 'shots/s5.png'});
  console.log(await p.evaluate(() => document.getElementById('hud').textContent), 'ERRS', JSON.stringify(errs.slice(0, 5)));
  await b.close();
})();
