# صور وأصوات المعركة — الدفعة الرابعة: الأرض والأصوات الحقيقية

الملفات جاهزة:

- الأرض: `assets/battle/51.jpg` إلى `56.jpg`، الصورة كلها نسيج.
- العناصر: `assets/battle/57.jpg` إلى `74.jpg`، خلفية بيضاء.
- المضغوط: `assets/battle/battle-sprites-4.zip`
- الأصوات: `assets/sounds/41.mp3` إلى `70.mp3`، تسجيلات حقيقية، والمصادر في `assets/sounds/LICENSES.md`.

## أولاً: أنسجة الأرض (51 إلى 56)

هذه تظهر عند التقريب حتى لا تبدو الأرض ضبابية. لا تحتاج خلفية: الصورة كلها أرض. إذا ما طلعت متصلة الأطراف تماماً، أنا أصلحها.

```
You are generating ground textures for a top-down military strategy game set in northern Iraq near Duhok. Rules for EVERY image:
- ONE single full-size 1024x1024 image per reply, never a grid.
- Seen from directly above (orthographic, like a drone photo from 100 meters), photorealistic, high detail.
- The texture fills the whole image edge to edge, uniform, seamless and tileable, no objects in the center, no shadows from big objects, no text.
- Soft even daylight, natural colors, late autumn.
- Write the item number above each image. After each image wait; when I write "next" generate the next number.

ITEMS
51. Dry light-brown desert dirt with small scattered stones and pebbles
52. Dry yellow steppe grass, short and patchy, with bare soil between the tufts
53. Plowed brown farmland soil with straight parallel furrows
54. Young green wheat field in rows, with brown soil visible between the rows
55. Rocky grey limestone hillside ground with small dry shrubs and cracks
56. Gravel dirt road surface with tire tracks, light grey-brown
```

## ثانياً: عناصر على الأرض (57 إلى 74) — خلفية بيضاء

```
You are generating top-down sprites for a realistic military strategy game in northern Iraq. Rules for EVERY image:
- ONE single full-size 1024x1024 image per reply, never a grid.
- Strict top-down orthographic view (camera directly above), photorealistic, high detail, like a drone photo.
- Solid pure WHITE background (#FFFFFF), nothing else, no ground, no text, no logos.
- Soft overhead light from the top-left, no cast shadow.
- Write the item number above each image. After each image wait; when I write "next" generate the next number.

ITEMS
57. A single olive tree seen from directly above, round grey-green canopy
58. A single tall poplar tree seen from directly above, narrow dark green canopy
59. A single eucalyptus tree seen from directly above, loose light green canopy
60. A small dry desert bush seen from directly above
61. A group of three large grey boulders seen from directly above
62. A single flat-roofed two-storey concrete house seen from directly above, beige, small water tank and satellite dish on the roof
63. A single flat-roofed one-storey village house with a walled courtyard, seen from directly above, light grey concrete
64. A single flat-roofed house with a red-brown roof and a small garden, seen from directly above
65. A partly destroyed flat-roofed house with a collapsed roof corner and rubble, seen from directly above
66. A straight segment of a concrete compound wall, seen from directly above
67. A high-voltage electricity pylon (steel lattice tower) seen from directly above
68. A white civilian sedan car seen from directly above
69. A white civilian pickup truck seen from directly above
70. A burned-out destroyed civilian car seen from directly above, blackened
71. A tall concrete water tower seen from directly above
72. A small farm shed with a metal roof seen from directly above
73. A row of concrete T-wall blast barriers seen from directly above
74. A small earth berm with a parked military truck behind it seen from directly above
```

---

## ثالثاً: أصوات الاشتباك الحقيقية (41 إلى 70)

**مهم:** اعملها بـ **ElevenLabs Sound Effects** بنفس الوصف بالضبط. لا تبدّلها بأصوات من مواقع ثانية حتى لو تشبهها، لأن المرة الفاتت أربعة طلعت غلط. إذا خلص رصيدك المجاني، أرسلها على دفعات.

كل سلاح له صوتان: **قريب** و**بعيد**، لأن الصوت الحقيقي يتغير كثيراً بالمسافة.

| # | الصوت | الوصف | المدة |
|---|---|---|---|
| 41 | كلاشنكوف قريب | `AK-47 assault rifle firing a short burst, close, outdoor, sharp and loud` | 2 ث |
| 42 | كلاشنكوف بعيد | `AK-47 rifle bursts far away across a valley, distant gunfire with echo` | 4 ث |
| 43 | رشاش PKM قريب | `PKM machine gun firing a long burst, close, outdoor` | 3 ث |
| 44 | رشاش بعيد | `machine gun bursts far away in the hills, distant with echo` | 4 ث |
| 45 | دوشكا قريب | `DShK 12.7mm heavy machine gun firing, deep heavy thumping bursts, close` | 3 ث |
| 46 | رشاش 50 قريب | `M2 Browning .50 caliber heavy machine gun firing bursts, close` | 3 ث |
| 47 | بندقية جي 3 | `G3 battle rifle firing several single shots, outdoor, close` | 3 ث |
| 48 | قناص | `sniper rifle single shot with a long rolling echo across hills` | 3 ث |
| 49 | مدفع 30 ملم | `30mm autocannon of an infantry fighting vehicle firing short bursts` | 3 ث |
| 50 | مدفع دبابة قريب | `125mm tank main gun firing, extremely loud blast with shockwave, close` | 3 ث |
| 51 | مدفع دبابة بعيد | `tank cannon firing far away, deep boom echoing across hills` | 4 ث |
| 52 | إطلاق هاون | `mortar launching a shell, hollow thump, outdoor` | 2 ث |
| 53 | قذيفة هاون تسقط | `mortar shell short incoming whistle then explosion` | 3 ث |
| 54 | مدفعية بعيدة | `155mm howitzer firing in the distance, low rumble with echo` | 4 ث |
| 55 | رصاص يمر فوقك | `bullets cracking and snapping overhead, supersonic cracks, no gunshots` | 3 ث |
| 56 | رصاص يضرب التراب | `bullet impacts hitting dirt and rocks, small thuds and puffs` | 3 ث |
| 57 | رصاص يضرب حديد | `bullets hitting metal armor, sharp pings and ricochets` | 2 ث |
| 58 | ارتداد قذيفة | `tank shell ricochet off armor, loud metallic whine` | 2 ث |
| 59 | دوران البرج | `tank turret traversing, electric hydraulic motor whine` | 2 ث |
| 60 | صاروخ راجمة واحد | `single 122mm artillery rocket launch, fast rising roar` | 2 ث |
| 61 | رشقة راجمة بعيدة | `multiple rocket launcher salvo far away, rapid series of distant whooshes` | 5 ث |
| 62 | انفجار كبير مع صدى | `large explosion with a long echo rolling across a valley` | 5 ث |
| 63 | انفجار قريب مع حطام | `close explosion with dirt and debris falling down afterwards` | 3 ث |
| 64 | معركة بعيدة | `distant battle ambience, continuous far away gunfire with occasional explosions` | 15 ث، يُكرَّر |
| 65 | صيحات جنود | `distant soldiers shouting commands, unintelligible, battlefield` | 5 ث |
| 66 | محرك دبابة واقف | `tank diesel engine idling, close, low rumble` | 5 ث، يُكرَّر |
| 67 | مدرعة بعجلات | `8x8 wheeled armored vehicle driving, diesel engine and tires on gravel` | 5 ث، يُكرَّر |
| 68 | قنبلة يدوية | `hand grenade explosion, sharp blast, outdoor` | 2 ث |
| 69 | آر بي جي | `RPG rocket launcher firing then the rocket exploding` | 3 ث |
| 70 | دبابة تمر قريباً | `tank driving past close, engine roar and squeaking tracks` | 5 ث |
