# Ями — окремі об'єкти

Ями з землі map_03, перемальовані окремими спрайтами з прозорим фоном: людина ставить їх у редакторі Godot на
тайл землі (`art/maps/ground/`). Форма — з карти: Codex отримує кроп своєї ями з `art/maps/map_03/map_03_ground.png`.
`pits_trim.py` обрізає `<назва>_raw.png` (полотно Codex) до видимих пікселів + 8 px → `<назва>.png` (це бере гра).

Промпт A/B/C (різниться опис форми в дужках і формат): «Redraw this exact pit as a standalone game sprite. Image 1 is
a blurry crop of the current game map: copy EXACTLY the outline shape of the pit (<форма>), its proportions and
orientation, the vertical grey basalt-column walls seen on the far side inside the hole, the ring of small pale stones
along the rim and the dark bottomless interior - the same object, same angle, same colours, just redrawn much sharper
and cleaner at high resolution, filling the image … with a small margin.» + стиль-блок skill art + «Transparent
background, no ground texture: everything outside the stone rim fully transparent, NO dirt, NO grass, NO pebbles
scattered around. ONLY this pit, no UI, no text, no other objects.»

| файл | що | спроба | референси | примітка |
|---|---|---|---|---|
| pit_vee_raw.png → pit_vee.png | яма «галочка» (A), 1536×1024 → 1527×816 | 1 | pit_vee_ref.png (кроп карти ×2,61; яма 508×188 px за схемою) | форма «a long hole bent like a wide shallow V»; IoU силуету зі схемою 0,90 (bbox-нормовано); 2,84 текселя на px карти; апрув 2026-10-15 |
| pit_oval_raw.png → pit_oval.png | мала овальна (B), → 1450×920 | 1 | pit_oval_ref.png (×3; 304×168) | «a small rounded oval hole, wider than tall»; IoU 0,92; 4,37 текселя / px; апрув 2026-10-15 |
| pit_snake_raw.png → pit_snake.png | «змійка» (C), 1024×1536 → 944×1477 | 1 | pit_snake_ref.png (×3; 236×424) | «a long narrow hole running top to bottom, wide at the top-left, bending like a snake / S and narrowing to the bottom»; IoU 0,86; 3,56 текселя / px; апрув 2026-10-15 |
| pit_round_raw.png → pit_round.png | кругла (D), 1536×1024 → 1091×757 | 1 | pit_round_template.png (`pits_template.py`: отвір 300×225 px карти ×3, кільце 18 px), pit_oval_raw.png (стиль) | промпт: «Draw ONE round pit as a standalone game sprite. Image 1 is the SHAPE TEMPLATE: copy only its outline, position and size - the light grey ring is the stone rim, the middle grey band is the visible far inner wall, the dark area is the bottomless hole; NOT its flat grey look. Image 2 is an approved pit sprite of THIS game: draw in EXACTLY the same art style and materials …» + стиль-блок + прозорий фон; template_compare: IoU 0,94, масштаб 1,008, вісь +0,7°; ≈3 текселі на px карти; камені краю трохи більші, ніж у інших; апрув 2026-10-15 |
