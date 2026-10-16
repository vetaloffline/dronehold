# Скельні елементи-декор (піки, обвали, осипи…)

Задача людини 2026-10-16: «не просто стовпи — піки, обвалені елементи; ~10 концепцій, потім гарно
розставимо на скелі карти A». Окремі об'єкти декору (ставить людина), стиль — блоки `art/maps/cliffs/`.

| файл | що | спроба | референси | примітка |
|---|---|---|---|---|
| rock_decor_template.png | шаблон 5×2: 10 силуетів, опора в клітинках, висота, ×2 px | — | — | `rock_decor_template.py`; людина: «шаблон ок» |
| rock_decor_v1.png | аркуш 10 елементів від Codex | 1 | template, cliff_rock_sheet.png, cliff_ref_ridge_a.png | промпт у розмові (natural rock formations, 10 по порядку шаблону) |
| (чернетки) cut_v1/, rock_decor_variants_sheet.png | нарізка `art/maps/cliffs/cliff_sheet_cut.py -t rock_decor_cut_template.json -p rock_decor` | 1 | — | усі 10 по порядку, прозорий фон без ореолу, арка з прозорим отвором; ×1,23 від шаблону, IoU аркуша 0,22, вісь −4,3°; обвал, розколота брила й повалений стовп — кубуваті |
| rock_decor_on_map_a_*.png | превʼю на карті A | 1 | — | `rock_decor_on_map_a.py`: піки й гребінь на верху хребтів (підйом як Cliffs.top_y_at), решта біля підніжжя й у полі |
| rock_decor_sheet.png | аркуш, перейменований з rock_decor_v1 | 1 | — | **апрув людини 2026-10-16** («апрув усі 10, перенось в гру») |
| ../props/prop_cliff_*.png | 10 видів декору для `Prop` | — | — | `python3 rock_decor_props.py`: нарізка + `props.json` (`foot_cells`, `body_w` під масштаб ½); у `.import` мипмапи |
