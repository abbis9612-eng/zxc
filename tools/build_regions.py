"""يبني ملفات المناطق من بيانات Natural Earth (ملكية عامة).

الاستعمال:
    pip install shapely
    python3 tools/build_regions.py <ne_10m_admin_1_states_provinces.geojson> <ne_10m_populated_places_simple.geojson> <ne_10m_coastline.geojson>

يكتب:
    data/regions.json      المناطق: الاسم، الدولة، حصة السكان والاقتصاد، العاصمة، المناطق المجاورة
    data/regions_geo.json  أشكال المناطق مبسطة للرسم

حصص السكان والاقتصاد تقديرات اللعبة: من سكان المدن في كل منطقة (Natural Earth) مع وزن للمساحة.
الموارد: تقييم الدولة في countries.json يُوزَّع على مناطقها حسب tools/resource_hotspots.json ثم بالمساحة أو السكان.
المنشآت: تُوزَّع آلياً حسب حجم الجيش والاقتصاد والسواحل (تقديرات اللعبة، لا مواقع عسكرية حقيقية).
"""
import json
import math
import sys
from collections import defaultdict

from shapely.geometry import shape, Point, mapping
from shapely.ops import unary_union
from shapely.strtree import STRtree

ROOT = __file__.rsplit("/tools/", 1)[0]

# دمج المناطق الصغيرة جداً في وحدات أكبر (حقل region في Natural Earth)
MERGE_BY_REGION = {"GBR", "FRA"}
DROP_REGIONS = {
    "FRA": {"Guyane française", "Martinique", "Guadeloupe", "Réunion", "Mayotte"},
}
MERGED_NAMES_AR = {
    ("GBR", "Northern Ireland"): "أيرلندا الشمالية",
    ("GBR", "West Wales and the Valleys"): "غرب ويلز",
    ("GBR", "East Wales"): "شرق ويلز",
    ("GBR", "North West"): "شمال غرب إنكلترا",
    ("GBR", "West Midlands"): "غرب ميدلاندز",
    ("GBR", "East Midlands"): "شرق ميدلاندز",
    ("GBR", "South West"): "جنوب غرب إنكلترا",
    ("GBR", "Eastern"): "شرق اسكتلندا",
    ("GBR", "North East"): "شمال شرق إنكلترا",
    ("GBR", "South Western"): "جنوب غرب اسكتلندا",
    ("GBR", "Yorkshire and the Humber"): "يوركشاير",
    ("GBR", "East"): "شرق إنكلترا",
    ("GBR", "South East"): "جنوب شرق إنكلترا",
    ("GBR", "Highlands and Islands"): "المرتفعات والجزر",
    ("GBR", "North Eastern"): "شمال شرق اسكتلندا",
    ("GBR", "Greater London"): "لندن الكبرى",
    ("FRA", "Hauts-de-France"): "أو دو فرانس",
    ("FRA", "Grand Est"): "الشرق الكبير",
    ("FRA", "Provence-Alpes-Côte-d'Azur"): "بروفانس والكوت دازور",
    ("FRA", "Auvergne-Rhône-Alpes"): "أوفيرن رون ألب",
    ("FRA", "Nouvelle-Aquitaine"): "آكيتين الجديدة",
    ("FRA", "Occitanie"): "أوكسيتانيا",
    ("FRA", "Bourgogne-Franche-Comté"): "بورغوني فرانش كونته",
    ("FRA", "Pays de la Loire"): "بلاد اللوار",
    ("FRA", "Bretagne"): "بريتاني",
    ("FRA", "Normandie"): "نورماندي",
    ("FRA", "Corse"): "كورسيكا",
    ("FRA", "Centre-Val de Loire"): "وادي اللوار",
    ("FRA", "Île-de-France"): "إيل دو فرانس",
}
# مناطق تُدمج في جارتها
MERGE_INTO = {"UNDOF": "Quneitra"}
# تصحيح أسماء عربية غير دقيقة في المصدر
NAME_FIXES = {
    ("PAK", "F.C.T."): "إسلام آباد",
    ("USA", "District of Columbia"): "واشنطن العاصمة",
    ("ARE", "Abu Dhabi"): "أبوظبي",
    ("JOR", "Amman"): "عمّان",
    ("KOR", "Busan"): "بوسان",
    ("KOR", "Seoul"): "سيول",
    ("JPN", "Fukuoka"): "فوكوكا",
}
# جوار حقيقي تفوته فجوات صغيرة في بيانات المصدر
EXTRA_NEIGHBORS = [("IRQ", "Baghdad", "Wasit")]
# ريع الموارد السنوي بالمليار دولار لكل نقطة من تقييم المورد (تقدير اللعبة)
OIL_RENT = 2.0
GAS_RENT = 0.7
MAX_RENT_SHARE = 0.5
RESOURCES = ["oil", "gas", "steel", "rare_earth", "uranium", "food"]
NAME_PREFIXES = ["محافظة ", "ولاية ", "مقاطعة ", "إقليم ", "منطقة ", "محافظه "]


def clean_ar(name, fallback):
    if not name:
        return fallback
    for p in NAME_PREFIXES:
        if name.startswith(p) and len(name) > len(p) + 1:
            return name[len(p):]
    return name


def flat_polys(geom, min_area):
    polys = list(geom.geoms) if geom.geom_type == "MultiPolygon" else [geom]
    polys.sort(key=lambda p: -p.area)
    out = []
    for i, p in enumerate(polys):
        if i > 0 and p.area < min_area:
            continue
        flat = []
        for x, y in p.exterior.coords[:-1]:
            flat += [round(x, 2), round(y, 2)]
        if len(flat) >= 6:
            out.append(flat)
    return out


def build_edges(regions, nbrs, by_country):
    """الحدود المشتركة بين كل منطقتين متجاورتين، خطوطاً جاهزة للرسم.

    الخريطة ترسم منها الحدود الدولية الحقيقية (حيث يختلف المالك) وخطوط الجبهة على الحد الفعلي
    بين المتحاربين، بدل رسم إطار كل منطقة مرتين.
    """
    area = {cc: sum(regions[i]["geom"].area for i in idxs) for cc, idxs in by_country.items()}

    def tol_of(cc):
        a = area[cc]
        return 0.02 if a < 50 else (0.05 if a < 500 else 0.12)

    edges = []
    for i in sorted(nbrs):
        for j in sorted(nbrs[i]):
            if j <= i:
                continue
            ri, rj = regions[i], regions[j]
            line = ri["geom"].boundary.intersection(rj["geom"].boundary)
            if line.is_empty:
                continue
            parts = []
            geoms = list(getattr(line, "geoms", [line]))
            for g in geoms:
                if g.geom_type in ("LineString", "LinearRing"):
                    parts.append(g)
                elif g.geom_type == "MultiLineString":
                    parts.extend(g.geoms)
            if not parts:
                continue
            from shapely.ops import linemerge
            merged = linemerge(parts) if len(parts) > 1 else parts[0]
            tol = max(tol_of(ri["country"]), tol_of(rj["country"]))
            lines = []
            for g in getattr(merged, "geoms", [merged]):
                g = g.simplify(tol)
                if g.length < tol * 0.5:
                    continue
                flat = []
                for x, y in g.coords:
                    flat += [round(x, 2), round(y, 2)]
                if len(flat) >= 4:
                    lines.append(flat)
            if lines:
                a, b = sorted([ri["id"], rj["id"]])
                edges.append([a, b, lines])
    edges.sort(key=lambda e: (e[0], e[1]))
    json.dump({"_source": "حدود مشتركة محسوبة من Natural Earth 1:10m admin-1 (ملكية عامة)", "edges": edges},
              open(f"{ROOT}/data/region_edges.json", "w"), ensure_ascii=False, separators=(",", ":"))
    print("حدود مشتركة:", len(edges))


# رموز Natural Earth التي تختلف عن رموز اللعبة
GAME_CODE = {"PSX": "PSE", "SDS": "SSD"}
# الدول المضبوطة يدوياً: مناطقها كما هي دون دمج (أرقامها واختباراتها مبنية عليها)
KEEP_FULL = {"USA", "CHN", "RUS", "IND", "GBR", "FRA", "DEU", "POL", "UKR", "TUR", "IRN", "IRQ", "SYR", "JOR", "ISR",
             "SAU", "ARE", "EGY", "DZA", "PAK", "JPN", "KOR", "PRK", "CAN", "MEX"}


def target_count(c, area):
    """عدد المناطق المستهدف لدولة جديدة: يكبر مع الاقتصاد والمساحة، حتى يبقى العالم كله خفيفاً على الهاتف"""
    n = 2 + math.sqrt(float(c["gdp"])) / 8.0 + math.sqrt(area) / 5.0
    return int(max(1, min(14, round(n))))


def merge_small(regions, playable, places_path):
    """يدمج محافظات الدول الجديدة المتجاورة حتى تصل للعدد المستهدف: الأصغر مساحة يندمج بأصغر جيرانه.
    الاسم من المحافظة التي فيها أكبر مدينة، والرمز أصغر رموز الأعضاء (ثابت بين البناءات)."""
    places = json.load(open(places_path))["features"]
    pts = [(Point(pl["geometry"]["coordinates"]), float(pl["properties"].get("pop_max") or 0)) for pl in places]
    pt_tree = STRtree([p for p, _ in pts])
    by_cc = defaultdict(list)
    for r in regions:
        by_cc[r["country"]].append(r)
    out = []
    for cc in sorted(by_cc):
        rs = by_cc[cc]
        if cc in KEEP_FULL:
            out += rs
            continue
        for r in rs:
            r["city"] = 0.0
            for j in pt_tree.query(r["geom"]):
                p, pop = pts[int(j)]
                if pop > r["city"] and r["geom"].contains(p):
                    r["city"] = pop
        area = sum(r["geom"].area for r in rs)
        n = min(len(rs), target_count(playable[cc], area))
        groups = [{"id": r["id"], "members": [r], "geom": r["geom"], "area": r["geom"].area} for r in rs]
        while len(groups) > n:
            groups.sort(key=lambda g: (g["area"], g["id"]))
            small = groups[0]
            sg = small["geom"].buffer(0.05)
            cands = [g for g in groups[1:] if sg.intersects(g["geom"])]
            if not cands:
                c0 = small["geom"].representative_point()
                cands = [min(groups[1:], key=lambda g: (g["geom"].distance(c0), g["id"]))]
            tgt = min(cands, key=lambda g: (g["area"], g["id"]))
            tgt["members"] += small["members"]
            tgt["geom"] = unary_union([tgt["geom"], small["geom"]]).buffer(0)
            tgt["area"] = tgt["geom"].area
            tgt["id"] = min(tgt["id"], small["id"])
            groups.remove(small)
        for g in groups:
            lead = max(g["members"], key=lambda r: (r["city"], r["geom"].area))
            out.append({"id": g["id"], "country": cc, "name_ar": lead["name_ar"], "name_en": lead["name_en"], "geom": g["geom"]})
    out.sort(key=lambda r: (r["country"], r["id"]))
    print("مناطق بعد الدمج:", len(out))
    return out


def main(admin_path, places_path, coast_path):
    countries = json.load(open(f"{ROOT}/data/countries.json"))["countries"]
    playable = {c["id"]: c for c in countries}
    feats = json.load(open(admin_path))["features"]

    # تجميع المناطق
    groups = {}
    for f in feats:
        p = f["properties"]
        cc = GAME_CODE.get(p["adm0_a3"], p["adm0_a3"])
        if cc not in playable or not p.get("name"):
            continue
        reg = p.get("region")
        if reg in DROP_REGIONS.get(cc, set()):
            continue
        name = MERGE_INTO.get(p["name"], p["name"])
        if cc in MERGE_BY_REGION:
            key = (cc, reg)
            name_ar = MERGED_NAMES_AR[key]
            name_en = reg
        else:
            key = (cc, name)
            name_ar = NAME_FIXES.get((cc, p["name"])) or clean_ar(p.get("name_ar"), p["name"])
            name_en = name
        g = groups.setdefault(key, {"country": cc, "name_ar": name_ar, "name_en": name_en, "geoms": [], "codes": []})
        if p["name"] not in MERGE_INTO:
            g["name_ar"], g["name_en"] = name_ar, name_en
        g["geoms"].append(shape(f["geometry"]).buffer(0))
        g["codes"].append(p["adm1_code"])

    regions = []
    for key in sorted(groups, key=lambda k: (k[0], min(groups[k]["codes"]))):
        g = groups[key]
        geom = unary_union(g["geoms"]).buffer(0)
        regions.append({
            "id": "".join(ch if ch.isalnum() else "_" for ch in min(g["codes"])),
            "country": g["country"], "name_ar": g["name_ar"], "name_en": g["name_en"],
            "geom": geom,
        })

    regions = merge_small(regions, playable, places_path)

    # الجوار: مناطق تتلامس حدودها (داخل الدولة وعبر الحدود)
    geoms = [r["geom"].buffer(0.05) for r in regions]
    tree = STRtree(geoms)
    nbrs = defaultdict(set)
    for i, gi in enumerate(geoms):
        for j in tree.query(gi):
            j = int(j)
            if j != i and gi.intersects(geoms[j]):
                nbrs[i].add(j)
                nbrs[j].add(i)

    by_name = {(r["country"], r["name_en"]): i for i, r in enumerate(regions)}
    for cc, a, b in EXTRA_NEIGHBORS:
        i, j = by_name[(cc, a)], by_name[(cc, b)]
        nbrs[i].add(j)
        nbrs[j].add(i)

    # السواحل: منطقة يمر بها خط ساحل بطول معقول
    coast_lines = [shape(f["geometry"]) for f in json.load(open(coast_path))["features"]]
    coast_tree = STRtree(coast_lines)
    coastal = set()
    for i, r in enumerate(regions):
        g = r["geom"].buffer(0.02)
        length = 0.0
        for j in coast_tree.query(g):
            length += g.intersection(coast_lines[int(j)]).length
            if length > 0.15:
                coastal.add(i)
                break

    # السكان من المدن
    places = json.load(open(places_path))["features"]
    raw_tree = STRtree([r["geom"] for r in regions])
    city_pop = defaultdict(float)
    for pl in places:
        pp = pl["properties"]
        pt = Point(pl["geometry"]["coordinates"])
        for j in raw_tree.query(pt):
            j = int(j)
            if regions[j]["geom"].contains(pt):
                city_pop[j] += float(pp.get("pop_max") or 0)
                break

    by_country = defaultdict(list)
    for i, r in enumerate(regions):
        by_country[r["country"]].append(i)

    out_regions, out_geo = [], {}
    for cc, idxs in by_country.items():
        c = playable[cc]
        total_city = sum(city_pop[i] for i in idxs) or 1.0
        total_area = sum(regions[i]["geom"].area for i in idxs) or 1.0
        weights = {i: 0.8 * city_pop[i] / total_city + 0.2 * regions[i]["geom"].area / total_area for i in idxs}
        cap = Point(c["lon"], c["lat"])
        cap_i = min(idxs, key=lambda i: regions[i]["geom"].distance(cap))
        gdp_w = {i: weights[i] * (1.4 if i == cap_i else 1.0) for i in idxs}
        sw, sg = sum(weights.values()), sum(gdp_w.values())
        country_area = sum(regions[i]["geom"].area for i in idxs)
        res = distribute_resources(cc, c, idxs, regions, weights, gdp_w, sw, sg, total_area)
        # ريع النفط والغاز جزء من ناتج مناطق الإنتاج: البصرة تحمل نصف اقتصاد العراق لا 6% فقط
        rent = {i: res[i].get("oil", 0.0) * OIL_RENT + res[i].get("gas", 0.0) * GAS_RENT for i in idxs}
        rent_total = sum(rent.values())
        frac = min(MAX_RENT_SHARE, rent_total / c["gdp"]) if rent_total > 0 else 0.0
        if frac > 0:
            gdp_w = {i: (1.0 - frac) * gdp_w[i] / sg + frac * rent[i] / rent_total for i in idxs}
            sg = 1.0
        fac = place_facilities(c, idxs, regions, weights, gdp_w, coastal, res, cap_i)
        tol = 0.02 if country_area < 50 else (0.05 if country_area < 500 else 0.12)
        for i in idxs:
            r = regions[i]
            rp = r["geom"].representative_point()
            simple = r["geom"].simplify(tol, preserve_topology=True)
            if simple.is_empty:
                simple = r["geom"]
            out_regions.append({
                "id": r["id"], "country": cc, "name_ar": r["name_ar"], "name_en": r["name_en"],
                "lat": round(rp.y, 2), "lon": round(rp.x, 2),
                "pop_share": round(weights[i] / sw, 5), "gdp_share": round(gdp_w[i] / sg, 5),
                "capital": i == cap_i,
                "coastal": i in coastal,
                "resources": {k: v for k, v in res[i].items() if v > 0.0},
                "facilities": fac[i],
                "neighbors": sorted(regions[j]["id"] for j in nbrs[i]),
            })
            out_geo[r["id"]] = flat_polys(simple, tol * tol * 4)

    order = [c["id"] for c in countries]
    out_regions.sort(key=lambda r: (order.index(r["country"]), r["id"]))
    meta = "Natural Earth 1:10m admin-1 + populated places (public domain). حصص السكان والاقتصاد تقديرات اللعبة."
    json.dump({"_source": meta, "regions": out_regions}, open(f"{ROOT}/data/regions.json", "w"), ensure_ascii=False, indent=0, separators=(",", ":"))
    json.dump({"_source": meta, "shapes": out_geo}, open(f"{ROOT}/data/regions_geo.json", "w"), ensure_ascii=False, separators=(",", ":"))
    build_edges(regions, nbrs, by_country)

    counts = defaultdict(int)
    for r in out_regions:
        counts[r["country"]] += 1
    print("مناطق:", len(out_regions), dict(counts))
    missing = [r["name_en"] for r in out_regions if r["name_ar"] == r["name_en"]]
    print("بلا اسم عربي:", len(missing), missing[:20])
    totals = defaultdict(int)
    for r in out_regions:
        for k, v in r["facilities"].items():
            totals[k] += v
    print("المنشآت:", dict(totals), "ساحلية:", sum(1 for r in out_regions if r["coastal"]))


def distribute_resources(cc, c, idxs, regions, weights, gdp_w, sw, sg, total_area):
    """تقييم الدولة لكل مورد (0-100) يُقسَّم على مناطقها: المناطق الغنية أولاً ثم الباقي."""
    hot = HOTSPOTS.get(cc, {})
    out = {i: {} for i in idxs}
    for k in RESOURCES:
        total = float(c["resources"].get(k, 0))
        named = {}
        for name, w in hot.get(k, {}).items():
            for i in idxs:
                if regions[i]["name_en"] == name:
                    named[i] = w
        rest = max(0.0, 1.0 - sum(named.values()))
        if k == "food":
            base = {i: 0.5 * weights[i] / sw + 0.5 * regions[i]["geom"].area / total_area for i in idxs}
        elif k == "steel":
            base = {i: gdp_w[i] / sg for i in idxs}
        else:
            base = {i: regions[i]["geom"].area / total_area for i in idxs}
        bs = sum(base.values()) or 1.0
        for i in idxs:
            share = named.get(i, 0.0) + rest * base[i] / bs
            out[i][k] = round(total * share, 3)
    return out


def place_facilities(c, idxs, regions, weights, gdp_w, coastal, res, cap_i):
    """توزيع آلي للمنشآت حسب حجم الجيش والاقتصاد (تقديرات اللعبة)."""
    m = c["military"]
    fac = {i: {} for i in idxs}

    def put(kind, ranked, n):
        if not ranked:
            return
        for k in range(n):
            i = ranked[k % len(ranked)]
            fac[i][kind] = fac[i].get(kind, 0) + 1

    by_pop = sorted(idxs, key=lambda i: (-weights[i], regions[i]["id"]))
    by_gdp = sorted(idxs, key=lambda i: (-gdp_w[i], regions[i]["id"]))
    spread = sorted(idxs, key=lambda i: (-(weights[i] * 0.5 + math.sqrt(regions[i]["geom"].area)), regions[i]["id"]))
    coast = [i for i in by_gdp if i in coastal]
    by_oil = sorted([i for i in idxs if res[i].get("oil", 0) > 0.5], key=lambda i: (-res[i]["oil"], regions[i]["id"]))

    put("airbase", spread, max(1, min(30, round(m["fighters"] / 60) + 1)))
    if coast:
        put("port", coast, max(1, min(15, round((m["ships"] + m["submarines"]) / 12) + 1)))
    put("factory", by_gdp, max(1, min(14, round(c["gdp"] / 400) + 1)))
    put("refinery", by_oil[:4] if by_oil else by_gdp[:1], max(1, min(6, round(c["resources"].get("oil", 0) / 20) + 1)))
    put("power_plant", by_pop, max(1, min(10, round(len(idxs) / 5) + 1)))
    if m.get("nukes", 0) > 0:
        site = next((i for i in sorted(idxs, key=lambda i: (-regions[i]["geom"].area, regions[i]["id"])) if i != cap_i), cap_i)
        put("nuclear", [site], 1)
    return fac


HOTSPOTS = {}

if __name__ == "__main__":
    HOTSPOTS = json.load(open(f"{ROOT}/tools/resource_hotspots.json"))
    main(sys.argv[1], sys.argv[2], sys.argv[3])
