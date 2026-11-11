# المؤثرات والأصوات

## طريقة العمل

**المؤثرات المرئية:** الصور ثابتة، والحركة يصنعها الكود. كل انفجار يتكوّن من عدة صور: كرة نار، ودخان، وشرر، وحطام، وحفرة. اللعبة تكبّرها وتدوّرها وتبهّتها وتطلق منها عشرات الجزيئات، فيظهر كل انفجار مختلفاً عن غيره.

**الأصوات:** ChatGPT وGemini لا يصنعان أصواتاً. استعمل **ElevenLabs Sound Effects** (elevenlabs.io): فيه خطة مجانية، تكتب له الوصف فيعطيك الصوت. نزّل كل صوت كملف MP3 وأرسله لي مع رقمه.

---

## أولاً: صور المؤثرات (في ChatGPT أو Gemini)

انسخ ما داخل المربع كاملاً. ستأتيك صورة واحدة في كل رد، واكتب «التالي» بعدها.

```
You are generating visual-effect textures for a top-down military strategy game. Rules for EVERY image:
- ONE single full-size 1024x1024 image per reply, never a grid.
- Seen from directly above (top-down), photorealistic, high detail.
- Solid pure BLACK background (#000000), nothing else in the image, no text.
- The effect is centered and fills about 80% of the frame, with soft natural edges that fade into the black.
- Write the item number above each image. After each image wait; when I write "next" generate the next number.

ITEMS
1. Fireball explosion seen from above: bright yellow-white core, orange and red flames, dark edges
2. Large dark grey-black smoke cloud seen from above, soft billowing puffs
3. Light grey dust and smoke puff seen from above, thin and wispy
4. Sparks and burning debris flying outward in all directions from a center point, seen from above
5. Ground shockwave ring of dust expanding outward, seen from above
6. Muzzle flash of a tank cannon seen from above: bright star-shaped flash with a short cone of fire pointing up
7. Rocket engine exhaust flame seen from above, pointing down: white-hot core, orange plume
8. Long straight missile smoke trail seen from above, white-grey, getting wider and fading toward the bottom
9. Air-burst interception explosion in the sky: white-blue flash with a ring of small black smoke puffs
10. Thick black oil fire smoke column seen from above, drifting to one side
11. Small rifle and machine-gun tracer flashes, several short glowing orange lines
12. Napalm-like spreading ground fire seen from above, orange flames on the ground
```

**بعدها صورتان على خلفية بيضاء** (لأنهما على الأرض وليستا ضوءاً). انسخ هذا في محادثة جديدة:

```
Two top-down photorealistic game textures on a solid pure white background, ONE image per reply, 1024x1024, no text:
13. A fresh shell crater in desert sand seen from directly above, scorched dark center, debris around it
14. A burned-out destroyed tank wreck seen from directly above, blackened, smoking, turret displaced
```

---

## ثانياً: الأصوات (في ElevenLabs Sound Effects)

اكتب كل وصف كما هو. اجعل المدة كما هو مكتوب بين القوسين.

| # | الصوت | الوصف |
|---|---|---|
| 1 | مدفع دبابة | `tank cannon firing, deep powerful boom with metallic ring, outdoor desert` (2 ثانية) |
| 2 | مدفعية ثقيلة | `heavy 155mm howitzer firing, huge low boom echoing across hills` (3 ثوانٍ) |
| 3 | راجمة صواريخ | `multiple rocket launcher firing a rapid salvo of rockets, whooshing launches` (4 ثوانٍ) |
| 4 | إطلاق صاروخ باليستي | `ballistic missile launch, roaring rocket engine ignition rising into the sky` (5 ثوانٍ) |
| 5 | صاروخ يمر | `missile flying overhead fast, sharp whoosh passing by` (2 ثانية) |
| 6 | انفجار كبير | `massive explosion impact, deep bass rumble with debris falling` (4 ثوانٍ) |
| 7 | انفجار متوسط | `medium explosion, sharp blast with crackling fire` (3 ثوانٍ) |
| 8 | انفجار بعيد | `distant explosion far away, muffled low boom` (3 ثوانٍ) |
| 9 | اعتراض صاروخ | `air defense missile interception, launch whoosh then mid-air explosion` (3 ثوانٍ) |
| 10 | مقاتلة تمر | `fighter jet flyby at low altitude, loud roaring jet engine passing` (4 ثوانٍ) |
| 11 | مروحية | `military attack helicopter rotor blades approaching and hovering` (5 ثوانٍ، يُكرَّر) |
| 12 | مسيّرة انتحارية | `loitering munition drone buzzing propeller engine approaching` (4 ثوانٍ) |
| 13 | رشاش ثقيل | `heavy machine gun firing bursts, 12.7mm, outdoor` (3 ثوانٍ) |
| 14 | تبادل إطلاق نار | `distant battlefield small arms gunfire exchange, rifles and machine guns` (6 ثوانٍ، يُكرَّر) |
| 15 | جنازير دبابات | `tank tracks and diesel engines rumbling, armored column moving` (6 ثوانٍ، يُكرَّر) |
| 16 | احتراق | `burning fire crackling with secondary small explosions` (5 ثوانٍ، يُكرَّر) |
| 17 | صفارة إنذار | `air raid siren wailing in a city` (6 ثوانٍ، يُكرَّر) |
| 18 | أجواء الجبهة | `war front ambience, distant artillery rumbles and wind` (10 ثوانٍ، يُكرَّر) |
| 19 | ضغطة زر | `short clean military UI click` (0.5 ثانية) |
| 20 | تنبيه | `military radio alert beep, urgent` (1 ثانية) |
| 21 | الشهر التالي | `deep cinematic transition swoosh with low drum hit` (2 ثانية) |
| 22 | نصر | `short triumphant military brass sting` (3 ثوانٍ) |
| 23 | هزيمة | `short dark ominous orchestral sting` (3 ثوانٍ) |

**بديل مجاني ومحترف للأصوات:** حزمة **Sonniss GDC Game Audio Bundle** (sonniss.com/gameaudiogdc). أصوات احترافية مجانية ومسموح باستعمالها، وفيها أسلحة وانفجارات حقيقية. لكن حجمها كبير جداً (عشرات الغيغابايتات)، فتصلح إذا كان عندك كمبيوتر.
