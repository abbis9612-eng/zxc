const { chromium, devices } = require('playwright');
(async () => {
  const b = await chromium.launch({args: ['--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader']});
  const p = await (await b.newContext({ ...devices['Pixel 7'], deviceScaleFactor: 1 })).newPage();
  const errs = []; p.on('pageerror', e => errs.push('PAGE: ' + String(e))); p.on('console', m => { if (m.type() === 'error') errs.push('CONSOLE: ' + m.text()); }); p.on('requestfailed', r => errs.push('BLOCKED(test only): ' + r.url().slice(0, 80)));
  await p.route('**/*', r => { const u = r.request().url(); return (u.startsWith('http://127.0.0.1') || u.startsWith('data:') || u.startsWith('blob:')) ? r.continue() : r.abort(); });
  await p.goto('http://127.0.0.1:8765/index.html'); await p.waitForTimeout(1500);
  const R = []; const ok = (name, cond, extra = '') => { R.push((cond ? 'OK   ' : 'FAIL ') + name + (extra ? '  ' + extra : '')); };
  const tap = async s => { const r = await p.locator(s).first().boundingBox(); if (!r) return false; await p.touchscreen.tap(r.x + r.width / 2, r.y + r.height / 2); return true; };
  const ev = (f, a) => p.evaluate(f, a);
  const shot = async n => { const t0 = Date.now(); console.log('shot', n, 'W.t', await p.evaluate(() => W && Math.round(W.t))); await p.screenshot({path: `qa/${n}.png`, timeout: 60000}); console.log('  done', Date.now() - t0, 'ms'); };
  // 1) الدخول: هل يظهر الرسم القديم قبل الجديد؟
  await tap('#advice');
  const seen = [];
  for (let i = 0; i < 12; i++) { await p.waitForTimeout(100); seen.push(await ev(() => !!(window.PXW && PXW.ok))); if (i === 1) await shot('01_enter_200ms'); }
  ok('العرض الجديد جاهز لحظة الدخول (بلا رسم قديم)', seen[0], 'جاهز بعد ' + (seen.indexOf(true) + 1) * 100 + 'ms');
  await p.waitForTimeout(1200); await shot('02_start');
  // 2) أوامر عامة
  for (const [id, k] of [['#wo-hold', 'hold'], ['#wo-retreat', 'retreat'], ['#wo-attack', 'attack']]) { await tap(id); await p.waitForTimeout(150); ok('أمر ' + k, await ev(k => W.order === k, k)); }
  // 3) السرعة
  for (const s of [0, 1, 16, 32, 4]) { await tap(`[data-wsp="${s}"]`); await p.waitForTimeout(100); ok('سرعة ' + s, await ev(s => wspeed === s, s)); }
  // 4) التقريب والإبعاد والمتابعة
  const k0 = await ev(() => W.cam.k); await tap('#wzin'); await p.waitForTimeout(150); const k1 = await ev(() => W.cam.k); ok('زر التقريب', k1 > k0, `${k0.toFixed(2)}→${k1.toFixed(2)}`);
  await tap('#wzout'); await p.waitForTimeout(150); ok('زر الإبعاد', (await ev(() => W.cam.k)) < k1);
  await tap('#wfollow'); await p.waitForTimeout(100); ok('زر المتابعة يطفي', await ev(() => !W.follow)); await tap('#wfollow'); await p.waitForTimeout(100); ok('زر المتابعة يشتغل', await ev(() => W.follow));
  // 5) تحديد وحدة بالضغط عليها
  await ev(() => { W.follow = false; wspeed = 0; const u = W.units.find(v => v.side === 'iq' && v.t === 'tank' && !v.dead); W.cam.x = u.x; W.cam.y = u.y; window._u = u.id; });
  await p.waitForTimeout(300);
  const box = await p.locator('#wc').boundingBox();
  await p.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2); await p.waitForTimeout(300);
  ok('تحديد دبابة بالضغط', await ev(() => W.sel.includes(window._u)), await ev(() => JSON.stringify(W.sel)));
  ok('لوحة الوحدة المحددة تظهر', await p.locator('#wsel').isVisible());
  await shot('03_selected');
  // تحريك إلى نقطة
  const fp = await ev(() => { const cv = wc(); for (let r = 80; r < 300; r += 20) for (let a = 0; a < 6.28; a += .5) { const sx = cv.clientWidth / 2 + Math.cos(a) * r, sy = cv.clientHeight / 2 + Math.sin(a) * r; if (sy < 150 || sy > cv.clientHeight - 200 || sx < 70 || sx > cv.clientWidth - 20) continue; const x = (sx - cv.clientWidth / 2) / W.cam.k + W.cam.x, y = (sy - cv.clientHeight / 2) / W.cam.k + W.cam.y, R = Math.max(.4, 24 / W.cam.k) * 1.5; if (!W.units.some(u => !u.dead && Math.hypot(u.x - x, u.y - y) < R)) return [sx, sy]; } return [200, 300]; });
  await p.touchscreen.tap(box.x + fp[0], box.y + fp[1]); await p.waitForTimeout(300);
  ok('أمر تحرك لنقطة', await ev(() => { const u = W.units.find(v => v.id === window._u); return !!u.manual; }));
  await p.waitForTimeout(100); await shot('04_move_order');
  // مهاجمة عدو محدد
  const en = await ev(() => { const e = W.units.find(v => v.side === 'tr' && !v.dead && v.t === 'tank'); W.cam.x = e.x; W.cam.y = e.y; return e.id; }); await p.waitForTimeout(300);
  await p.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2); await p.waitForTimeout(300);
  ok('أمر مهاجمة عدو', await ev(en => W.units.find(v => v.id === window._u).focus === en, en));
  await tap('#wsel-free'); await p.waitForTimeout(150); ok('زر تحرير الوحدة', await ev(() => !W.units.find(v => v.id === window._u).manual));
  await tap('#wsel-x'); await p.waitForTimeout(150); ok('زر إلغاء التحديد', await ev(() => W.sel.length === 0));
  // 6) ضربة جوية بالهدف
  await ev(() => { W.cool.air = 0; W.cool.msl = 0; });
  await tap('#wo-air'); await p.waitForTimeout(200); ok('زر الضربة الجوية يطلب هدفاً', await ev(() => W.aim === 'air'));
  ok('رسالة التوجيه تظهر', await p.locator('#whint').isVisible(), await p.locator('#whint').textContent());
  await p.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2 - 50); await p.waitForTimeout(300);
  ok('الطائرات انطلقت', await ev(() => W.units.some(u => u.t === 'jet' && !u.dead)));
  await shot('05_air_aim_tap');
  // 7) الصواريخ
  await tap('#wo-msl'); await p.waitForTimeout(200); ok('زر الصواريخ يطلب هدفاً', await ev(() => W.aim === 'msl'));
  await p.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2); await p.waitForTimeout(300);
  ok('الراجمات استلمت المهمة', await ev(() => W.units.some(u => u.t === 'mlrs' && u.job)));
  // 8) الاحتياط
  const n0 = await ev(() => W.units.length); await tap('#wo-res'); await p.waitForTimeout(200); ok('الاحتياط دخل', (await ev(() => W.units.length)) > n0);
  // 9) رموز القيادة
  await tap('#wc2'); await p.waitForTimeout(500); ok('زر رموز القيادة', await ev(() => C2MODE)); await shot('06_c2'); await tap('#wc2'); await p.waitForTimeout(500); ok('رجوع من الرموز', await ev(() => !C2MODE)); await shot('07_back_from_c2');
  // 10) اللعب دقيقة بسرعة ×4 مع متابعة
  await ev(() => { wspeed = 4; W.follow = true; W.cam.k = 2.6; }); await p.waitForTimeout(8000); await shot('08_play');
  // 11) الحسم السريع والنتيجة
  await tap('#wquick'); await p.waitForTimeout(1500); ok('الحسم السريع ينهي المعركة', await ev(() => !!W && !!W.end), await ev(() => W && W.end));
  ok('شاشة النتيجة تظهر', await p.locator('#wres').isVisible()); await shot('09_result');
  // 12) الخروج والعودة
  await tap('#wclose'); await p.waitForTimeout(800); ok('الخروج من المعركة', await ev(() => W === null));
  await shot('10_after_close');
  const again = await tap('#advice'); await p.waitForTimeout(2500); ok('الدخول مرة ثانية', again && await ev(() => !!W && PXW.ok)); await shot('11_reenter');
  ok('لا توجد قماشة رسم مكررة', await ev(() => document.querySelectorAll('#wgl').length === 1));
  console.log(R.join('\n')); console.log('ERRORS:', errs.length ? '\n' + errs.slice(0, 10).join('\n') : 'none');
  await b.close();
})();
