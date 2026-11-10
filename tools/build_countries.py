"""يبني data/countries.json لكل دول العالم.

الاستعمال:
    python3 tools/build_countries.py <ne_10m_admin_1_states_provinces.geojson>

- الدول الموجودة في data/countries.json تبقى كما هي تماماً (أرقامها مضبوطة يدوياً ومختبرة)،
  ويُضاف لها فقط جيرانها البريون الجدد.
- الدول الجديدة تُبنى من tools/world_reference.json: جداول أرقام تقديرية (الناتج، السكان، الإنفاق العسكري،
  الموارد، الأجيال، الحكم، الاستقرار، الأسماء والعواصم) استُخرجت من نموذج HTML للعبة قدّمه صاحب المشروع.
- أعداد السلاح للدول الجديدة من علاقة إحصائية تُستخرج من الدول المضبوطة يدوياً
  (العدد ~ ميزانية الجيش^أ × السكان^ب لكل نوع)، حتى تبقى بنفس مقياس اللعبة وتوازنها.
"""
import json
import math
import sys
from collections import defaultdict

from shapely.geometry import shape, Point
from shapely.strtree import STRtree

ROOT = __file__.rsplit("/tools/", 1)[0]

# رموز Natural Earth التي تختلف عن رموز اللعبة
NE_CODE = {"PSE": "PSX", "SSD": "SDS"}
# كيانات لا تُلعب (متنازع عليها أو بلا علم في المكتبة)
SKIP = {"CYN", "SOL"}
UNITS = ["infantry", "armor", "artillery", "fighters", "bombers", "helicopters", "drones", "air_defense",
         "ships", "submarines", "missiles", "atgm", "ashm", "ew"]
NAVAL = {"ships", "submarines", "ashm"}
# ترتيب أجيال النموذج: مشاة، دبابات، مدفعية، مضاد دروع، جو، مسيّرات، بحرية، دفاع جوي، مضاد سفن، باليستي
GEN_IDX = {"land": [0, 1, 2], "air": [4], "sea": [6], "missile": [9, 5], "air_defense": [7]}
GOV_MAP = {"mon": "monarchy", "isl": "islamic", "mil": "military", "one": "one_party"}
AR_PREFIX = ["محافظة ", "ولاية ", "مقاطعة ", "إقليم ", "منطقة ", "محافظه ", "إمارة "]


# أسماء العواصم حيث يختلف اسم المحافظة عن المدينة
CAPITALS_AR = {
    "BRA": "برازيليا", "NGA": "أبوجا", "AUS": "كانبرا", "ITA": "روما", "ESP": "مدريد", "IDN": "جاكرتا", "NLD": "أمستردام",
    "CHE": "برن", "TWN": "تايبيه", "BEL": "بروكسل", "ARG": "بوينس آيرس", "SWE": "ستوكهولم", "IRL": "دبلن", "THA": "بانكوك",
    "AUT": "فيينا", "NOR": "أوسلو", "PHL": "مانيلا", "VNM": "هانوي", "BGD": "دكا", "MYS": "كوالالمبور", "DNK": "كوبنهاغن",
    "COL": "بوغوتا", "ZAF": "بريتوريا", "ROU": "بوخارست", "CZE": "براغ", "CHL": "سانتياغو", "PRT": "لشبونة", "FIN": "هلسنكي",
    "KAZ": "أستانا", "PER": "ليما", "NZL": "ولينغتون", "GRC": "أثينا", "QAT": "الدوحة", "KWT": "الكويت", "HUN": "بودابست",
    "OMN": "مسقط", "MAR": "الرباط", "ETH": "أديس أبابا", "KEN": "نيروبي", "AGO": "لواندا", "VEN": "كاراكاس", "CUB": "هافانا",
    "LBY": "طرابلس", "TUN": "تونس", "SDN": "الخرطوم", "YEM": "صنعاء", "LBN": "بيروت", "PSE": "رام الله", "AFG": "كابول",
    "AZE": "باكو", "GEO": "تبليسي", "ARM": "يريفان", "BLR": "مينسك", "SRB": "بلغراد", "BGR": "صوفيا", "HRV": "زغرب",
    "MMR": "نايبيداو", "LKA": "كولومبو", "NPL": "كاتماندو", "UZB": "طشقند", "TKM": "عشق آباد", "MNG": "أولان باتور",
    "BHR": "المنامة", "SOM": "مقديشو", "MRT": "نواكشوط", "SEN": "داكار", "MLI": "باماكو", "NER": "نيامي", "TCD": "إنجامينا",
    "ECU": "كيتو", "BOL": "سوكري", "PRY": "أسونسيون", "URY": "مونتيفيديو", "TZA": "دودوما", "UGA": "كمبالا", "COD": "كينشاسا",
    "CMR": "ياوندي", "GHA": "أكرا", "CIV": "ياموسوكرو", "SSD": "جوبا", "ERI": "أسمرة", "DJI": "جيبوتي", "LTU": "فيلنيوس",
    "LVA": "ريغا", "EST": "تالين", "SVK": "براتيسلافا", "SVN": "ليوبليانا", "ISL": "ريكيافيك", "CYP": "نيقوسيا",
}


def rate(x, ref, power=0.45):
    """إنتاج حقيقي إلى تقييم 0-100 بمنحنى يشبه تقييمات الدول المضبوطة يدوياً"""
    if not x or x <= 0:
        return 0
    return int(round(min(100.0, 100.0 * (x / ref) ** power)))


# أُسس ثابتة للعلاقة: العدد ~ الميزانية^ب × السكان^ج. المعامل وحده يُستخرج من الدول المضبوطة
# (الوسيط، حتى لا تشذ دولة واحدة). الانحدار الحر غير مستقر مع 25 دولة فقط.
EXP = {"infantry": (0.45, 0.45), "armor": (0.7, 0.2), "artillery": (0.65, 0.25), "atgm": (0.65, 0.25)}
EXP_DEFAULT = (0.85, 0.1)


def fit_units(existing, ref):
    coef = {}
    for u in UNITS:
        bexp, pexp = EXP.get(u, EXP_DEFAULT)
        ks = []
        for c in existing:
            st = ref["ST"].get(c["id"])
            n = float(c["military"].get(u, 0))
            if not st or n <= 0:
                continue
            budget = st[0] * st[2] / 100.0
            ks.append(n / (max(budget, 0.05) ** bexp * max(st[1], 0.1) ** pexp))
        ks.sort()
        coef[u] = [math.log(ks[len(ks) // 2]), bexp, pexp] if ks else None
    return coef


def solve3(A, b):
    m = [row[:] + [b[i]] for i, row in enumerate(A)]
    for i in range(3):
        p = max(range(i, 3), key=lambda r: abs(m[r][i]))
        m[i], m[p] = m[p], m[i]
        for r in range(3):
            if r != i and m[i][i] != 0:
                f = m[r][i] / m[i][i]
                m[r] = [m[r][k] - f * m[i][k] for k in range(4)]
    return [m[i][3] / m[i][i] for i in range(3)]


def clean_ar(name, fallback):
    if not name:
        return fallback
    for p in AR_PREFIX:
        if name.startswith(p) and len(name) > len(p) + 1:
            return name[len(p):]
    return name


def main(admin_path):
    ref = json.load(open(f"{ROOT}/tools/world_reference.json"))
    data = json.load(open(f"{ROOT}/data/countries.json"))
    existing = data["countries"]
    have = {c["id"] for c in existing}
    feats = json.load(open(admin_path))["features"]
    by_cc = defaultdict(list)
    for f in feats:
        by_cc[f["properties"]["adm0_a3"]].append(f)

    # الجيران البريون من تلامس المحافظات
    geoms, owners = [], []
    for cc, fs in by_cc.items():
        for f in fs:
            geoms.append(shape(f["geometry"]).buffer(0))
            owners.append(cc)
    tree = STRtree(geoms)
    land_nb = defaultdict(set)
    for i, g in enumerate(geoms):
        for j in tree.query(g):
            j = int(j)
            if owners[j] != owners[i] and g.intersects(geoms[j]):
                land_nb[owners[i]].add(owners[j])
    back = {v: k for k, v in NE_CODE.items()}

    def game_code(ne):
        return back.get(ne, ne)

    coef = fit_units(existing, ref)
    ids = [k for k in ref["ST"] if k not in have and k not in SKIP and NE_CODE.get(k, k) in by_cc]
    ids.sort(key=lambda k: -ref["ST"][k][0])
    landlocked = set(ref.get("LANDLOCKED", []))
    demoq = set(ref.get("DEMOC", []))
    axis = set(ref.get("AXIS", []))
    new = []
    for cid in ids:
        gdp, pop, milp = ref["ST"][cid]
        pc = gdp / max(pop, 0.01)
        fs = by_cc[NE_CODE.get(cid, cid)]
        name_en = fs[0]["properties"].get("admin") or cid
        lon, lat = ref["CAP"].get(cid, [0, 0])
        # العاصمة: اسم المحافظة التي تقع فيها
        cap_ar = CAPITALS_AR.get(cid, "")
        pt = Point(lon, lat)
        best = None
        for f in fs:
            g = shape(f["geometry"])
            d = g.distance(pt)
            if best is None or d < best[0]:
                best = (d, f)
        if best and cap_ar == "":
            pp = best[1]["properties"]
            cap_ar = clean_ar(pp.get("name_ar"), pp.get("name") or name_en)
            for pre in ["العاصمة في ", "منطقة العاصمة "]:
                cap_ar = cap_ar.replace(pre, "")
        gens = ref.get("GENS", {}).get(cid)
        if not gens:
            gens = [3, 3, 3, 3, 3, 2, 3, 3, 2, 0] if pc > 30 else ([2, 3, 2, 2, 3, 2, 2, 2, 2, 0] if pc > 10 else ([2, 2, 2, 2, 2, 1, 1, 2, 1, 0] if pc > 4 else [1, 1, 1, 1, 1, 1, 1, 1, 1, 0]))
        tech = {}
        for br, idx in GEN_IDX.items():
            vals = [gens[i] for i in idx if gens[i] > 0]
            tech[br] = int(max(1, min(5, round(sum(vals) / len(vals))))) if vals else 1
        if gdp < 500:
            tech = {k: min(v, 4) for k, v in tech.items()}
        budget = gdp * milp / 100.0
        mil = {}
        for u in UNITS:
            cf = coef.get(u)
            if cf is None:
                mil[u] = 0
                continue
            v = math.exp(cf[0] + cf[1] * math.log(max(budget, 0.05)) + cf[2] * math.log(max(pop, 0.1)))
            if u in NAVAL and cid in landlocked:
                v = 0
            if u in ("bombers", "submarines") and budget < 8:
                v = 0
            mil[u] = int(round(v)) if v >= 1 else 0
        mil["infantry"] = max(1, mil["infantry"])
        # كل دولة تملك حداً أدنى من مضاد الدروع والحرب الإلكترونية (أنظمة المعركة تفترض وجودهما)
        mil["atgm"] = max(1, mil["atgm"])
        mil["ew"] = max(1, mil["ew"])
        mil["nukes"] = int(ref.get("NUKES", {}).get(cid, 0))
        res = {
            "oil": rate(ref["OILP"].get(cid), 4.5),
            "gas": rate(ref["GASP"].get(cid), 200),
            "steel": rate(ref["STEEL"].get(cid), 150),
            "rare_earth": rate(ref["RARE"].get(cid), 60),
            "uranium": rate(ref["URAN"].get(cid), 7),
            "food": int(max(5, min(100, round(ref["FOOD"].get(cid, 85) * 0.75)))),
        }
        gov = GOV_MAP.get(ref.get("GOV0", {}).get(cid, ""), "parliamentary" if cid in demoq else "presidential")
        stab = int(ref.get("STAB", {}).get(cid, 70 if pc > 20 else 60))
        growth = 4.0 if pc < 5 else (3.0 if pc < 15 else 1.8)
        quality = round(max(0.65, min(1.15, 0.7 + 0.1 * math.log10(max(pc, 0.5)) * 2)), 2)
        nb = sorted({game_code(x) for x in land_nb.get(NE_CODE.get(cid, cid), set())})
        tags = []
        if res["oil"] >= 50:
            tags.append("نفطية")
        if res["gas"] >= 50:
            tags.append("غازية")
        if res["food"] >= 90:
            tags.append("سلة غذاء")
        if mil["nukes"] > 0:
            tags.append("نووية")
        known = "اقتصاد %s مليار دولار" % (int(round(gdp)) if gdp >= 10 else round(gdp, 1))
        if tags:
            known += "، " + " و".join(tags)
        new.append({
            "id": cid, "flag": ref["A2"].get(cid, "").lower(), "name_ar": ref["NAMES"].get(cid, name_en),
            "name_en": name_en, "capital_ar": cap_ar, "lat": round(lat, 2), "lon": round(lon, 2),
            "gdp": gdp, "population": pop, "growth": growth,
            "tax_rate": round(min(0.4, 0.13 + milp / 100.0), 2), "stability": stab, "government": gov,
            "personality": "ambitious" if cid in axis else "cautious", "quality": quality,
            "resources": res, "tech": tech, "military": mil, "neighbors": nb,
            "doctrine": "balanced", "known_ar": known + ".",
        })
    # الجيران البريون الجدد للدول الموجودة
    all_ids = have | {c["id"] for c in new}
    for c in existing:
        extra = {game_code(x) for x in land_nb.get(NE_CODE.get(c["id"], c["id"]), set())}
        c["neighbors"] = sorted(set(c["neighbors"]) | (extra & all_ids))
    for c in new:
        c["neighbors"] = [n for n in c["neighbors"] if n in all_ids]
    data["countries"] = existing + new
    data["_world_note"] = "الدول غير المضبوطة يدوياً بُنيت آلياً بـ tools/build_countries.py من tools/world_reference.json."
    out = json.dumps(data, ensure_ascii=False, indent=2)
    open(f"{ROOT}/data/countries.json", "w").write(out + "\n")
    print("دول:", len(data["countries"]), "جديدة:", len(new))
    for u in UNITS:
        print(u, ["%.2f" % x for x in coef[u]] if coef[u] else None)


if __name__ == "__main__":
    main(sys.argv[1])
