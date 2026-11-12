const fs = require('fs'), M = '../mock/';
const grab = (file, name) => { const s = fs.readFileSync(M + file, 'utf8'); const i = s.indexOf('"' + name + '"'); if (i < 0) throw name; const a = s.indexOf('"', i + name.length + 2) + 1, b = s.indexOf('"', a); return s.slice(a, b); };
const uri = (p, mime) => `data:${mime};base64,` + fs.readFileSync(p).toString('base64');
const fx = {};
for (const k of ['smoke_light', 'smoke_dark', 'fireball', 'sparks', 'muzzle', 'exhaust']) fx[k] = grab('vfx.js', k);
for (const k of ['launch_dust', 'blast_dust', 'dirt_hits', 'smoke_screen', 'tank_fire', 'armor_sparks', 'backblast']) fx[k] = grab('extra3.js', k);
const A = '/home/user/zxc/assets/sounds/';
const snd = {
  tank_shot: A + '50.mp3', tank_far: A + '51.mp3', tank_real: A + 'real/tank_cannon.mp3', ak: A + '41.mp3', ak_far: A + '42.mp3', pkm: A + '43.mp3', mg_far: A + '44.mp3', dshk: A + '45.mp3', m2: A + '46.mp3',
  cannon30: A + '49.mp3', atgm: A + '24.mp3', missile: A + '25.mp3', jet_release: A + '26.mp3', armor_hit: A + '27.mp3', rocket_one: A + '60.mp3', boom_echo: A + '62.mp3', boom_close: A + '63.mp3',
  incoming: A + '31.mp3', cracks: A + '55.mp3', tank_pass: A + '70.mp3', tank_idle: A + '66.mp3', cookoff: A + '37.mp3', smoke_pop: A + '40.mp3', radio: A + '39.mp3', rpg: A + '69.mp3',
  battle_far: A + 'real/battle_field.mp3', warzone: A + 'real/warzone.mp3', rockets_in: A + 'real/rockets_incoming.mp3', strike: A + 'real/strike_impact.mp3', jet_high: A + '36.mp3', jet_flyby: A + '35.mp3'
};
const S = {}; for (const k in snd) S[k] = uri(snd[k], 'audio/mpeg');
// صوت المقاتلة الحقيقي من الحزمة الأولى
const sj = fs.readFileSync(M + 'sounds.js', 'utf8'); for (const k of ['jet_flyby', 'mlrs', 'helicopter', 'explosion_big', 'artillery']) { const i = sj.indexOf('"' + k + '"'); const a = sj.indexOf('"', i + k.length + 2) + 1, b = sj.indexOf('"', a); S[k] = sj.slice(a, b); }
const meta = JSON.parse(fs.readFileSync('meta.json'));
const js = `const D3 = ${JSON.stringify({meta, sat: uri('sat.jpg', 'image/jpeg'), h: fs.readFileSync('h.bin').toString('base64'), detail: grab('extra4.js', 'dirt'), fx, snd: S})};`;
fs.writeFileSync('assets3d.js', js); console.log((js.length / 1024 | 0) + ' KB');
