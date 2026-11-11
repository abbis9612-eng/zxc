# صور وأصوات المعركة — الدفعة الثالثة

الطريقة نفسها: انسخ ما داخل المربع كاملاً في ChatGPT أو Gemini، وستأتيك صورة واحدة في كل رد، ثم اكتب «التالي». أرسل الصور كلها في ملف zip واحد، وأسماؤها بأرقامها.

## أولاً: صور على خلفية بيضاء

البرج منفصل عن الهيكل حتى يدور البرج نحو الهدف والدبابة ماشية. **مهم:** الهيكل والبرج لنفس الدبابة لازم يكونان بنفس الحجم والألوان، فاطلبهما في نفس المحادثة واحداً بعد الآخر.

```
You are generating top-down sprites for a realistic military strategy game. Rules for EVERY image:
- ONE single full-size 1024x1024 image per reply, never a grid.
- Strict top-down orthographic view (camera directly above), photorealistic, high detail, like a drone photo.
- Solid pure WHITE background (#FFFFFF), nothing else, no ground, no text, no logos, no flags.
- Soft overhead light from the top-left, no cast shadow.
- Front of every vehicle and missile points to the TOP of the image.
- Keep the same scale and colors between a hull and its matching turret.
- Write the item number above each image. After each image wait; when I write "next" generate the next number.

ITEMS
28. T-72 main battle tank HULL ONLY, turret removed, the round turret ring opening visible on top, desert tan camouflage, tracks and engine deck detailed
29. The TURRET ONLY of the same T-72 from item 28, with its long gun barrel pointing up, same desert tan camouflage, same scale, the turret centered in the image
30. A modern Iraqi main battle tank HULL ONLY (angular modern design, side skirts), turret removed, desert tan camouflage
31. The TURRET ONLY of the same tank from item 30, angular modern turret with long gun pointing up, same scale and colors
32. Leopard 2A4 main battle tank HULL ONLY, turret removed, green woodland camouflage
33. The TURRET ONLY of the same Leopard 2A4 from item 32, flat-faced boxy turret with long gun pointing up, green woodland camouflage, same scale
34. Altay main battle tank HULL ONLY, turret removed, green woodland camouflage
35. The TURRET ONLY of the same Altay tank from item 34, long gun pointing up, green woodland camouflage, same scale
36. Mi-35 attack helicopter WITHOUT its main rotor blades (rotor hub only), desert tan camouflage, rocket pods and missiles under the stub wings
37. T129 ATAK attack helicopter WITHOUT its main rotor blades (rotor hub only), grey-green camouflage, missiles under the stub wings
38. F-16 fighter jet in flight carrying two air-to-ground missiles and two bombs under the wings, light grey paint
39. A single air-to-ground missile (like a Maverick) in flight, white-grey body with fins
40. A single 122mm artillery rocket (like a Grad rocket) in flight, olive body with tail fins
41. A single tactical ballistic missile in flight, white body with black markings and fins
42. A single anti-tank guided missile in flight (like a Kornet), olive body with small fins
```

## ثانياً: مؤثرات على خلفية سوداء

انسخ هذا في محادثة جديدة:

```
Top-down visual-effect textures for a military game on a solid pure BLACK background (#000000), ONE image per reply, 1024x1024, no text, effect centered and fading softly into the black. After each image wait; when I write "next" generate the next number.
43. A tank cannon firing seen from directly above: bright muzzle flash at the end of the barrel and a wide ring of light desert dust blown outward along the ground around it
44. The backblast of a shoulder-fired anti-tank missile launch seen from above: a cone of dust and grey smoke blown backward
45. A large cloud of light dust and grey smoke kicked up on the ground by a rocket launcher firing, seen from above
46. Bullets hitting sandy ground seen from above: several small sprays of light dust and dirt
47. An armor-piercing round hitting a tank seen from above: intense white-orange spark shower and molten metal fragments
48. A thin light dust trail kicked up behind a moving vehicle on a desert road seen from above, long and fading toward the bottom
49. A thick white smoke-screen cloud from smoke grenades seen from above, dense and soft
50. A destroyed tank burning fiercely seen from above: a tall column of flame and black smoke rising from the hull
```

---

## ثالثاً: الأصوات (ElevenLabs Sound Effects)

اكتب كل وصف كما هو، وخلّ المدة كما مكتوبة بين القوسين. أرسل كل صوت باسم رقمه.

| # | الصوت | الوصف |
|---|---|---|
| 24 | إطلاق صاروخ مضاد دروع | `anti-tank guided missile launch, sharp pop then rocket motor ignition hiss, outdoor` (3 ثوانٍ) |
| 25 | صاروخ طائر | `guided missile flying past, continuous rocket motor hiss and whoosh` (3 ثوانٍ) |
| 26 | إطلاق صاروخ من طائرة | `air-to-ground missile released from a fighter jet, rocket ignition roar moving away` (3 ثوانٍ) |
| 27 | قذيفة تصيب دبابة | `tank shell hitting armor, loud metallic clang with blast and debris` (2 ثانية) |
| 28 | رصاص يمر قريباً | `bullets snapping and cracking past close overhead, supersonic cracks` (3 ثوانٍ) |
| 29 | رصاص يصيب الأرض | `bullet impacts hitting dirt and rocks with ricochets` (3 ثوانٍ) |
| 30 | صاروخ راجمة واحد | `single artillery rocket launch whoosh, fast rising roar` (2 ثانية) |
| 31 | قذيفة قادمة | `incoming artillery shell whistle falling then impact` (3 ثوانٍ) |
| 32 | دوران البرج | `tank turret traversing, electric hydraulic motor whine` (2 ثانية) |
| 33 | محرك دبابة يتحرك | `tank diesel engine revving and accelerating with track clanking, close` (5 ثوانٍ، يُكرَّر) |
| 34 | راجمة المروحية | `attack helicopter firing a rapid salvo of unguided rockets` (3 ثوانٍ) |
| 35 | رشاش المروحية | `attack helicopter 30mm cannon firing short bursts` (3 ثوانٍ) |
| 36 | طائرة على ارتفاع | `fighter jet flying high and far away, distant rumbling roar` (6 ثوانٍ، يُكرَّر) |
| 37 | انفجار ذخيرة الدبابة | `ammunition cooking off inside a burning tank, popping secondary explosions` (5 ثوانٍ) |
| 38 | خطوات الجنود | `squad of soldiers running on gravel, footsteps and gear rattling` (4 ثوانٍ، يُكرَّر) |
| 39 | لاسلكي عسكري | `military radio chatter, short unintelligible voice bursts with static` (5 ثوانٍ) |
| 40 | قنبلة دخان | `smoke grenade pop and long hissing smoke release` (3 ثوانٍ) |
