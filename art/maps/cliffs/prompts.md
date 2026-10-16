# Скелі — арт (блок на клітинку: стіна-колони і природна скеля, `game/core/cliffs.gd`)

Шлях рішень людини 2026-10-15: контур + текстура («УЖАС а не скеля») → блок на клітинку з колон («для
периметра підійде, всередині — не скеля») → два види: колони для периметра, природна скеля з піками й
спусками для середини. Референси — кропи скель старої `map_03_ground.png` («опорні кадри клас»).

| файл | що | спроба | референси | примітка |
|---|---|---|---|---|
| ref_ridge_a.png, ref_ridge_b.png | кропи 1200×500 з `art/maps/map_03/map_03_ground.png` (2700,600 і 2500,1880) | — | — | людина: «опорні кадри так клас» |
| cliff_top_raw_v1.png | верх плато, Codex 1254×1254 | 1 | ref_ridge_a, ref_ridge_b | промпт — `cliff_top_prompt.txt`; мох + сірі плити + жовті квіти, без дерев |
| cliff_top_v1.png | безшовний 1024×1024 | 1 | — | `python3 art/maps/ground/ground_dirt_make.py cliff_top_raw_v1.png -o cliff_top_v1.png` (без підгонки кольору); на 3×3 стиків не видно |
| cliff_columns_template.png | шаблон аркуша стовпів 4×2, фронт 48 px карти ×4 | — | — | `cliff_columns_template.py`, чекає «Шаблон ок?» |
| cliff_face_template.png | шаблон смуги фронту | — | — | відкинуто разом з підходом «контур + текстура» |
| cliff_top_on_shape_v1.png | превʼю верху на контурі | 1 | — | людина: «УЖАС а не скеля» → підхід змінено: блок на клітинку |
| cliff_blocks_template.png | шаблон 8 блоків 4×2: клітинка 32×24 + висота 48, ×4 | — | — | `cliff_blocks_template.py`; людина: «шаблон ок» |
| cliff_blocks_v1.png | аркуш 8 блоків від Codex | 1 | template, ref_ridge_a, ref_ridge_b | прозорий фон без ореолу; блоки ×1,2 від шаблону (≈49×92 px карти), IoU аркуша 0,24; нарізка `cliff_blocks_cut.py` → blocks_v1/, превʼю `cliff_blocks_preview.py` → cliff_blocks_preview_v1_*.png: склеюється в будь-якій формі, але ряд вузьких стовпів виглядає як частокіл |
| cliff_blocks_preview_v1_*.png | превʼю колон у лабіринті | 1 | — | людина: «краще, для периметра підійде, але всередині — колони, нема піків і плавного спуску» → два види: колони для периметра, природна скеля для середини (рішення людини) |
| rock_blocks_template.png | шаблон 8 блоків природної скелі: пік 96, високі 72, середні 44, низькі 20 px карти, ×3 | — | — | `rock_blocks_template.py`; людина: «шаблон ок» |
| rock_blocks_v1.png | аркуш природної скелі від Codex | 1 | template, ref_ridge_a, ref_ridge_b | уступи, сколи, пік зі шпилем, низькі полиці; усе ×1,2 і зсунуте вниз від шаблону → нарізка за зв'язними шматками `rock_blocks_cut.py` (rocks_v1/), точка на землі заміряна по блоку; прозорий фон без ореолу |
| rock_blocks_preview_v1c_*.png | превʼю природної скелі в лабіринті | 1 | — | `rock_blocks_preview.py rocks_v1 --jitter-size 0.12 --jitter-x 7 --jitter-y 3`: висота від відстані до кінця хребта + шум, пік — одна клітинка на горб |
| cliff_wall_sheet.png, cliff_rock_sheet.png | аркуші, перейменовані з cliff_blocks_v1 / rock_blocks_v1 | — | — | **апрув людини 2026-10-15** («мені подобається все перенось») |
| cliff_atlas.png | атлас 16 блоків для гри | — | — | `python3 cliff_sheet_cut.py cliff_wall_sheet.png -t cliff_blocks_template.json -o $TMPDIR/cut -p cliff_wall`, те саме для `cliff_rock_sheet.png` з `rock_blocks_template.json -p cliff_rock`, далі `python3 cliff_atlas.py --wall $TMPDIR/cut/cliff_wall.json --rock $TMPDIR/cut/cliff_rock.json` (пише й `game/core/cliff_blocks.tres`); у `.import` мипмапи |
