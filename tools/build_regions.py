"""يبني ملفات المناطق من بيانات Natural Earth (ملكية عامة).

الاستعمال:
    pip install shapely
    python3 tools/build_regions.py <ne_10m_admin_1_states_provinces.geojson> <ne_10m_populated_places_simple.geojson>

يكتب:
    data/regions.json      المناطق: الاسم، الدولة، حصة السكان والاقتصاد، العاصمة، المناطق المجاورة
    data/regions_geo.json  أشكال المناطق مبسطة للرسم

حصص السكان والاقتصاد تقديرات اللعبة: من سكان المدن في كل منطقة (Natural Earth) مع وزن للمساحة.
"""
import json
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
}
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


def main(admin_path, places_path):
    countries = json.load(open(f"{ROOT}/data/countries.json"))["countries"]
    playable = {c["id"]: c for c in countries}
    feats = json.load(open(admin_path))["features"]

    # تجميع المناطق
    groups = {}
    for f in feats:
        p = f["properties"]
        cc = p["adm0_a3"]
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
                "neighbors": sorted(regions[j]["id"] for j in nbrs[i]),
            })
            out_geo[r["id"]] = flat_polys(simple, tol * tol * 4)

    order = [c["id"] for c in countries]
    out_regions.sort(key=lambda r: (order.index(r["country"]), r["id"]))
    meta = "Natural Earth 1:10m admin-1 + populated places (public domain). حصص السكان والاقتصاد تقديرات اللعبة."
    json.dump({"_source": meta, "regions": out_regions}, open(f"{ROOT}/data/regions.json", "w"), ensure_ascii=False, indent=0, separators=(",", ":"))
    json.dump({"_source": meta, "shapes": out_geo}, open(f"{ROOT}/data/regions_geo.json", "w"), ensure_ascii=False, separators=(",", ":"))

    counts = defaultdict(int)
    for r in out_regions:
        counts[r["country"]] += 1
    print("مناطق:", len(out_regions), dict(counts))
    missing = [r["name_en"] for r in out_regions if r["name_ar"] == r["name_en"]]
    print("بلا اسم عربي:", len(missing), missing[:20])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
