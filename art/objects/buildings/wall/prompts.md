# Стіна з шматків — журнал (2026-10-09, схвалено 2026-10-10)

Шаблон пози: `wall_template.py` → `wall_template.png/.json` (клітинка 32×24 ×8 = 256×192; стовп 136×104×150,
проміжки висотою 110). Збирач: `wall_assemble.py <аркуш> <тека>` — вирізає 3 шматки біля їхніх блоків
шаблону, підганяє точно під розмір блоку, складає пряму / кут / сходинки / хрест / окремі.

| Спроба | Файл | Що вийшло |
|---|---|---|
| 1 | `wall_sheet_1a.png` | гарні шматки, але з перспективою (видно бічні грані) і не в розмір шаблону |
| 1 | `wall_sheet_1b.png` | Codex сам перемалював точно по шаблону: плоский фронт, стикується → схвалено, шматки тут: `wall_pillar.png`, `wall_along.png`, `wall_depth.png` |

Референси: `wall_template.png` + `art/concept/12_wall_idea.png`. Промпт — у відповіді сесії 2026-10-09
(«modular sci-fi stone wall … POSE TEMPLATE … pillar / span left-right / span into depth»).

Файли: `wall_sheet.png` — аркуш Codex (спроба 1b), `wall_assembled_preview.png` — збірка тестових стін.
Перезібрати шматки з іншого аркуша: `python3 wall_assemble.py <аркуш> <тека>`. У грі: `game/objects/wall/wall_rig.tres`
(`pillar` / `along` / `depth`, точки на землі — з `wall_pieces.json`, ×0,125).
