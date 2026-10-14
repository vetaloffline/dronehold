# Легкий кулемет — журнал промптів

| Файл | Що | Спроба | Референси | Примітка |
|---|---|---|---|---|
| `light_mg_concepts_v1.png` | аркуш 2×2: 4 концепти вигляду | 1 | Image 1 `art/objects/buildings/machine_gun/machine_gun_preview.png`, Image 2 `art/objects/buildings/core/core.png` | A — купол на триніжку, тонкий ствол з дульним гальмом; B — два тонкі стволи, 4 лапи; C — купол на низькому циліндрі, ствол у перфорованому кожусі; D — щиток на стійці з кільцем. sprite_check OK. Чекає вибору людини. |

## Промпт v1

```
$imagegen Concept sheet for a tower-defense game: FOUR different design concepts of a LIGHT MACHINE GUN TURRET, arranged in a 2x2 grid, all at the same scale, generous transparent space between them, each one a complete turret (base + rotating head + gun) seen from the same camera angle with the gun pointing toward the lower left. This light turret is the cheap, small, weaker little brother of the heavy turret in Image 1: about 60 percent of its size, a lighter build, and instead of four fat gatling barrels it has ONE THIN LONG barrel (or two thin needle barrels in one concept). Concept A: compact rounded dome head on a small three-legged tripod, single thin long barrel with a small muzzle brake. Concept B: slim boxy head with two thin parallel needle barrels, on a short squat four-leg base. Concept C: round turret head on a low cylindrical armored pedestal (no legs), single thin barrel inside a perforated cooling sleeve. Concept D: small gun with a little front armor shield plate on a single post with a rotating ring collar, single thin barrel. Image 1 is the approved heavy machine gun of this game and Image 2 is the approved core building: match their design language exactly - orange and dark-grey armor plates, light-grey panels, black mechanical parts, small blue indicator lights, dark outline, same detail level and the same view angle and lighting. [стиль-блок з SKILL.md] A soft contact shadow on the ground under each base is allowed, falling to the left. NO light beams, NO glow halos, NO muzzle flash, NO sparkles, NO particles baked into the sprite. Transparent background, no ground texture. ONLY these four turrets, no ground, no UI, no text, no labels, no letters, no other objects.
```

| Файл | Що | Спроба | Референси | Примітка |
|---|---|---|---|---|
| `light_mg_base_v1.png` | основа без голови: лапи, кільце, помаранчевий комір, вісь зверху, тінь вліво | 1 | Image 1 `light_mg_concept_d.png` (концепт D, вирізаний з аркуша), Image 2 `machine_gun_base.png` | sprite_check: тінь торкалась лівого краю (1 px, alpha 1) → поля +40 px кодом → OK. Людина вибрала концепт D. |
| `light_mg_head_v1.png` | голова окремо: щиток, барабан, ручка, тонкий ствол, шийка з втулкою | 1 | Image 1 `light_mg_concept_d.png`, Image 2 `machine_gun_head_135.png` | sprite_check OK. Підгонка до концепту D: голова ×0,335 (IoU 0,861), основа ×0,385 (IoU 0,887) → голова відносно основи ×0,87. Збірка: `light_mg_assembled_vs_concept.png`. |

Промпти base/head v1 — precise-object-edit концепту D (повний текст — у виводі сесії 2026-10-12): base — «keep EXACTLY the pedestal… REMOVE everything above the orange ring collar… flat round mounting plate with a short thick black axle stub… soft cast shadow to the left»; head — «draw ONLY the rotating gun head… keep the short black neck, end it with a flat round black hub… REMOVE the whole pedestal, NO ground shadow».

## 16 ракурсів голови — партія 1 (сірий шаблон `tpl/tpl_NN.png` + апрувнута голова `light_mg_head_v1.png`)

Шаблон: `light_mg_template.py` (3D-модель, K 0,509 з коміра основи, IoU моделі з апрувнутою головою 0,847), аркуш
`check_sheet.png` — людина: «ок». Заміри: `light_mg_measure.py` (підгонка моделі: азимут, зум, housing), перевірено
на апрувнутій голові: 136,0° проти 136,4°, зум 3,14 проти 3,125.

| Файл | Ракурс | Спроба | Заміряно | IoU з моделлю | Примітка |
|---|---|---|---|---|---|
| `views/light_mg_head_112_5_v1.png` | 112,5° | 1 | 122,0° (+9,5°) | 0,786 | поза допуском: Codex довернув до зразка (136,4°), ствол коротший, втулка не на housing |
| `views/light_mg_head_135_v1.png` | 135° | 1 | 135,0° (0,0°) | 0,839 | ок |
| `views/light_mg_head_157_5_v1.png` | 157,5° | 1 | 157,5° (0,0°) | 0,796 | ок |

Висновок: сірий шаблон тримає позу біля зразка, на 24° від нього — ні (як тарілка ретранслятора). Далі —
кольоровий рендер моделі (`light_mg_template.py color` → `tplc/tplc_NN.png`, аркуш `color_sheet.png`) +
precise-object-edit. Чекає «ок» людини на кольоровий рендер.

## 16 ракурсів — кольоровий рендер (`tplc/tplc_NN.png`, людина: «ок») + апрувнута голова

Промпт: «precise-object-edit of Image 1: 3D render in the exact required pose. Keep EXACTLY silhouette, rotation
angle, barrel direction, position, size; hub at the same pixel. Repaint only materials… Image 2: copy design, NOT
pose» + стиль-блок. Спроба 2 для 0°: + «EXACT SIDE PROFILE… drum on the FAR side, NOT visible». Спроба 2 для
22,5/45/67,5/292,5/315/337,5°: + «drum on the FAR side, HIDDEN… do NOT draw any drum or orange ring on the visible
side» (у спробі 1 Codex додавав барабан на видимий бік — силует проходив, деталь ні).
Дрібне кодом: поля +40 px (202,5° v1, 45° v1 — пікселі alpha 1 на краю), шум alpha < 16 далеко від об'єкта (292,5° v1).

Фінальний набір (`light_mg_place.py` → `placed/`, один множник 1/зум на спрайт, housing в одній точці, полотно 929×543,
housing (471, 424); аркуш `placed/sheet.png`):

| Ракурс | Файл | Спроба | Заміряно | Похибка | IoU |
|---|---|---|---|---|---|
| 0° | `views/light_mg_head_000_v2.png` | 2 | 3,5° | +3,5 | 0,84 |
| 22,5° | `…_022_5_v2.png` | 2 | 24,5° | +2,0 | 0,88 |
| 45° | `…_045_v2.png` | 2 | 46,5° | +1,5 | 0,90 |
| 67,5° | `…_067_5_v2.png` | 2 | 67,5° | 0,0 | 0,88 |
| 90° | `…_090_v1.png` | 1 | 90,0° | 0,0 | 0,86 |
| 112,5° | `…_112_5_v2.png` | 2 | 113,5° | +1,0 | 0,88 |
| 135° | `…_135_v1.png` (сірий шаблон) | 1 | 135,0° | 0,0 | 0,84 |
| 157,5° | `…_157_5_v1.png` (сірий шаблон) | 1 | 157,5° | 0,0 | 0,80 |
| 180° | `…_180_v1.png` | 1 | 180,5° | +0,5 | 0,85 |
| 202,5° | `…_202_5_v1.png` | 1 | 205,5° | +3,0 | 0,82 |
| 225° | `…_225_v1.png` | 1 | 224,0° | −1,0 | 0,83 |
| 247,5° | `…_247_5_v1.png` | 1 | 247,0° | −0,5 | 0,88 |
| 270° | `…_270_v1.png` | 1 | 270,5° | +0,5 | 0,94 |
| 292,5° | `…_292_5_v2.png` | 2 | 292,5° | 0,0 | 0,90 |
| 315° | `…_315_v2.png` | 2 | 316,0° | +1,0 | 0,88 |
| 337,5° | `…_337_5_v2.png` | 2 | 335,0° | −2,5 | 0,86 |

Чекає апруву людини.

## Апрув і перенос (2026-10-14)

Людина: «ідеально» на `light_mg_views_sheet.png` → перенесено сюди: 16 голів (`light_mg_head_<az>.png`),
основа й тінь окремими шарами (`light_mg_base_export.py` з `light_mg_base_codex.png`), вихідні картинки Codex
(`light_mg_concept.png` — концепт D, `light_mg_base_codex.png`, `light_mg_head_codex.png`; у Godot `importer="skip"`),
скрипти шаблону, замірів, підгонки й rig (`light_mg_rig_export.py` → `game/objects/light_mg/`).
Чернетки Codex (усі спроби) лишились в `art/drafts/buildings/light_mg/` (не в репо).
