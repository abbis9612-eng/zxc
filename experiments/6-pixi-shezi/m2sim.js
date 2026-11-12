const { chromium, devices } = require('playwright');
const plan = process.argv[2] || 'none', seed = +(process.argv[3] || 11);
(async () => {
  const b = await chromium.launch(); const p = await (await b.newContext({ ...devices['Pixel 7'] })).newPage();
  await p.route('**/*', r => { const u = r.request().url(); return (u.startsWith('http://127.0.0.1') || u.startsWith('data:')) ? r.continue() : r.abort(); });
  await p.goto('http://127.0.0.1:8765/index.html'); await p.waitForTimeout(1200);
  const o = await p.evaluate(([plan, seed]) => {
    war(); wspeed = 0; W.seed = seed; const deaths = []; let used = {};
    const alive = new Set(W.units.filter(u => !u.dead).map(u => u.id));
    for (let i = 0; i < 40000 && !W.end; i++) {
      stepWar(.1);
      if (plan === 'all') {
        if (W.t > 400 && !used.res) { wOrder('res'); used.res = 1; }
        if (W.t > 120 && W.cool.msl <= 0 && W.uses.msl) { W.aimAt = densest('tr'); wOrder('msl-go'); W.aimAt = null; }
        if (W.t > 300 && W.cool.air <= 0 && W.uses.air) { W.aimAt = densest('tr'); wOrder('air-go'); W.aimAt = null; }
      }
      for (const u of W.units) if (u.dead && alive.has(u.id)) { alive.delete(u.id); if (deaths.length < 25) deaths.push(Math.round(W.t) + 's ' + u.side + ':' + u.t + ' @' + Math.round(u.x) + ',' + Math.round(u.y)); }
    }
    return {min: (W.t / 60).toFixed(1), end: W.end, ctl: W.ctl, iq: (strength('iq') / W.init.iq).toFixed(2), tr: (strength('tr') / W.init.tr).toFixed(2), kb: Object.entries(W.kb || {}).sort((a, b) => b[1] - a[1]).slice(0, 12), deaths};
  }, [plan, seed]);
  console.log(JSON.stringify(o, null, 0)); await b.close();
})();
