import fs from 'fs';
import {geoMercator, geoPath, geoArea} from 'd3-geo';
// d3 يحتاج الحلقات باتجاه عقارب الساعة؛ إن انقلبت المساحة (أكبر من نصف الكرة) نعكسها
function rewind(f){
  const g = f.geometry; if (!g) return f;
  const polys = g.type === 'Polygon' ? [g.coordinates] : g.type === 'MultiPolygon' ? g.coordinates : [];
  for (const poly of polys) for (const ring of poly) {
    const test = {type:'Polygon', coordinates:[ring]};
    if (geoArea(test) > 2 * Math.PI) ring.reverse();
  }
  return f;
}
const a1 = JSON.parse(fs.readFileSync('adm1.json'));
const a0 = JSON.parse(fs.readFileSync('adm0.json'));
const places = JSON.parse(fs.readFileSync('../ne/places.geojson'));
const W = 1000, H = 1300;
const box = {type:'Feature', geometry:{type:'Polygon', coordinates:[[[30,14],[30,40],[60,40],[60,14],[30,14]]]}};
const proj = geoMercator().fitExtent([[0,0],[W,H]], box);
const path = geoPath(proj).digits(1);
const prov = [];
for (const f0 of a1.features) {
  const f = rewind(f0);
  const p = f.properties;
  const d = path(f); if (!d) continue;
  const c = proj([p.longitude, p.latitude]) || path.centroid(f);
  prov.push({id: p.adm1_code, c: p.adm0_a3, n: p.name_ar || p.name, d, x: Math.round(c[0]), y: Math.round(c[1]), a: Math.round(path.area(f))});
}
const bg = a0.features.map(rewind).map(f => ({c: f.properties.ADM0_A3, d: path(f)})).filter(x => x.d);
const AR = {IRQ:'بغداد',SYR:'دمشق',JOR:'عمّان',SAU:'الرياض',KWT:'الكويت',IRN:'طهران',TUR:'أنقرة',LBN:'بيروت',QAT:'الدوحة',ARE:'أبوظبي',BHR:'المنامة',OMN:'مسقط',YEM:'صنعاء',EGY:'القاهرة',CYP:'نيقوسيا',GEO:'تبليسي',ARM:'يريفان',AZE:'باكو',TKM:'عشق آباد',AFG:'كابل',PAK:'إسلام آباد',SDN:'الخرطوم',ERI:'أسمرة',DJI:'جيبوتي'};
const caps = [];
for (const f of places.features) {
  const p = f.properties;
  if (p.FEATURECLA !== 'Admin-0 capital' && p.featurecla !== 'Admin-0 capital') continue;
  const xy = proj(f.geometry.coordinates);
  if (xy[0] < -50 || xy[0] > W + 50 || xy[1] < -50 || xy[1] > H + 50) continue;
  const c3 = p.adm0_a3; if (!AR[c3]) continue;
  caps.push({n: AR[c3], c: c3, x: Math.round(xy[0]), y: Math.round(xy[1])});
}
fs.writeFileSync('mapdata.js', 'const MAP=' + JSON.stringify({W, H, prov, bg, caps}) + ';');
console.log(prov.length, bg.length, caps.length, fs.statSync('mapdata.js').size);
console.log(caps.map(c => c.n + ':' + c.c).join(' '));
