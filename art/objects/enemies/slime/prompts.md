# slime — смерть (вибух), 5 кадрів сіткою 3×2

Шаблон: `slime_death_template.py` → `.png` / `.json` (каркас без заливки, контур з `slime_a.png`), погоджено людиною 2026-10-14.
Генерація: `codex exec … -i slime_death_template.png art/objects/enemies/slime/slime_a.png`. Промпт — у виклику (журнал сесії):
pose template + той самий слизень з Image 2; кадри: роздувся → тріскає → вибух (краплі й 3 ока летять) → краплі падають → калюжа з 2 очима;
NO fire/smoke/flash/glow; 6-та клітинка порожня.

| файл | що | спроба | референси | примітка |
|---|---|---|---|---|
| slime_death_sheet_v1.png | аркуш 5 кадрів | 1 | slime_death_template, slime_a | порядок кадрів і 6-та клітинка ок, прозорість ок (смуга 3 px біля краю: 0 px alpha>128; FAIL «top» у sprite_check — ледь видимі пікселі). Масштаб ×~1,6 від шаблону і нижче, але однаковий у всіх кадрах (низ 471…486 px). Кадр 0 майже не роздутий (h/w 0,59 проти 0,66 у slime_a). Манера яскравіша й з товщим обведенням, ніж slime_a (очі більші, колір насиченіший) |

Апрув людини 2026-10-14 («все ок»; на питання про манеру: слизень у грі — глянцеві slime_a/b, «хай так і буде»). Перенесено: `slime_death_sheet.png` (сирий аркуш Codex, v1), `slime_death_template.py/.png/.json`; нарізка — `../death_cut.py`.

Атлас для гри (2026-10-14): `../death_atlas.py` → `slime_death_atlas.png` / `.json` (5 кадрів рядком, ×0,5 від аркуша; точка опори й `px_scale` — кадр 0 лягає на скін a з `slime_skins.png`) → `game/objects/slime/slime_death_rig.tres`.
