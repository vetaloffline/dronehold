# beetle — жук-монстр, концепт (4 варіанти)

Задача людини: монстр з 4 лапами і 2 відростками, якими б'є; стиль жука-монстра; колір салатово-зелений,
слизнєвий; 4 варіанти. Шаблону нема (концепт, поза вільна). Референси: `art/objects/enemies/slime/slime_a.png`,
`slime_b.png`.

Спільна частина промпту (COMMON):

```
Image 1 and Image 2 are approved enemy sprites of this game (purple slimes): match their design language,
glossy wet gel material, rendering quality, outline and detail level, but NOT their colour or shape.
The creature is LIME / SALAD GREEN (bright yellow-green, #9BE33A-ish), slimy, wet, semi-translucent gel
over darker green chitin, glossy highlights, slime drips. It has EXACTLY FOUR walking legs (two on each
side, NOT six, NOT eight) and EXACTLY TWO separate front striking appendages it uses to hit. Facing right,
3/4 side view under the game camera, whole body visible, centered with margin on all sides.
2.5D top-down 3/4 view, camera tilted about 30 degrees; polished game art with a light hi-res
pixel-art feel (about 128 px per unit), NOT chunky retro 16-bit; crisp sharp edges, high contrast,
bright clean colors, no blur, no soft airbrush look.
LIGHT: one sun high on the upper right: right-facing surfaces lit, left-facing surfaces in shade.
NO light beams, NO glow halos, NO sparkles, NO particles baked into the sprite.
Transparent background, no ground texture.
ONLY this one creature, no ground, no shadow, no UI, no text, no other objects.
```

| файл | що | спроба | референси | примітка |
|---|---|---|---|---|
| beetle_b_jelly_v1.png | B: драглистий жук, щупальця з шипастими булавами | 1 | slime_a, slime_b | gpt-6.1-sol (astra: at capacity). sprite_check exit 1 лише через напівпрозорі пікселі <128 біля рамки (непрозорих на краю 0). Лап 4 + під черевом крапля, що читається як 5-та лапа |
| beetle_c_stag_v1.png | C: жук-олень з клешнями краба | 1 | slime_a, slime_b | gpt-6.1-sol. sprite_check exit 1: кут alpha=1 і напівпрозорі пікселі біля рамки; непрозорих (>128) на краю 0. Видно 3 лапи (4-та схована за тілом), силует ближче до скорпіона/рака |
| beetle_a_rhino_v1.png | A: броньований жук-носоріг, дві коси богомола | 1 | slime_a, slime_b | gpt-6.1-sol (2 перші запуски: at capacity). sprite_check exit 1: напівпрозорі пікселі біля лівого краю; кути alpha 0, непрозорих на краю 0. Видно 4 лапи, але 3 з ближнього боку + 1 з дальнього — може читатися як 6-лапий; біля голови дрібні щелепи |
| beetle_d_tick_v1.png | D: кліщ-громила, кулаки-булави | 1 | slime_a, slime_b | gpt-6.1-sol (1-й запуск: at capacity). sprite_check exit 1: напівпрозорі пікселі біля краю; кути alpha 0, непрозорих на краю 0. Видно лише 2 задні лапи, передні сховані за кулаками; силует ближче до черепахи |

## Спроба 2

Людина про спробу 1: «фігня» — мультяшні слизняки-жучки, не в стилі гри. Хоче страшних, реалістичніших
монстрів, чорно-коричневих + червоних, із деякими елементами салатового слизу. Причина провалу: референси
були тільки слизні → Codex перейняв форму й матеріал слизу. Зміна: референси — `art/concept/03_wave_v1.png`
(стиль гри) + `art/objects/buildings/core/core.png` (чіткість спрайта); палітра й «не мультяшно» — прямо в промпті.

COMMON2:
```
Image 1 is a screen concept of this game: match its camera angle, rendering style and level of detail.
Image 2 is an approved sprite of this game: match its crispness, outline and polish.
Do NOT copy anything from the images except style.
LOOK: a REALISTIC, menacing, scary alien monster, NOT cartoon, NOT cute, NOT a toy, NOT a slime blob, NOT a
normal insect. Palette: black and dark brown armored chitin with rough texture, scars and cracks; deep
blood-red raw flesh and membranes visible in joints and between plates; clusters of small red eyes, no
big round cartoon eyes; toxic LIME-GREEN slime only as ACCENTS (drooling from the mouth, oozing from
cracks, a few small slime sacs), at most about 15% of the creature.
It has EXACTLY FOUR walking legs (two on each side, all four visible, NOT six, NOT eight) and EXACTLY TWO
separate front striking appendages. Facing right, 3/4 view, whole creature visible, centered with
generous margin on all sides, strong readable silhouette that still reads when small.
+ стиль-блок і заборони з COMMON
```
| beetle_b_lasher_v2.png | B2: «бичувальник», щупальця з гаками | 2 | 03_wave_v1, core | 4 лапи ок; палітра ок; манера НЕ гри: живописна дрібна фактура, тонке обведення — див. beetle_style_vs_game.png |
| beetle_a_reaper_v2.png | A2: «косар», дві коси | 2 | 03_wave_v1, core | та сама проблема манери; лап ~5 |
| — | C2, D2 | 2 | — | зупинені: людина відкинула манеру («будівля піксель, а ворог в 4K») |

Висновок спроби 2: «realistic» у промпті ламає єдиний стиль гри. Наступна: референси — machine_gun_preview + core,
блок «Один стиль гри» зі скілу; палітра й настрій — ті самі, «menacing», без «realistic».

## Спроба 3 (людина попросила: «концепція монстрів норм, але перенасичено деталями»)

precise-object-edit з v2 → той самий монстр, «much SIMPLER, far fewer details», манера як у Image 2/3;
референси: v2 + machine_gun_preview + core; блок «Один стиль гри» зі скілу.

| файл | що | спроба | референси | примітка |
|---|---|---|---|---|
| beetle_a_reaper_v3.png | A3: «косар», спрощений | 3 | a_reaper_v2, machine_gun_preview, core | 4 лапи, 2 коси; обведення товсте, плями чисті; непрозорих на краю 0 |
| beetle_b_lasher_v3.png | B3: «бичувальник», спрощений | 3 | b_lasher_v2, machine_gun_preview, core | 4 лапи, 2 щупальця з гаками; непрозорих на краю 0 |
