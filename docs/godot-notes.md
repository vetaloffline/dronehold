# Реалізація арту в Godot

Як перенести налаштовані в HTML-тюнерах об'єкти в Godot 4 (GDScript). Числа не дублюються тут —
вони лежать у `*_rig.json` поруч з артом; тюнери (`*.html`) — еталон поведінки: що там видно, те
має бути в грі.

## Загальне

- Усі PNG об'єкта лежать у спільних координатах свого спрайта (ставити в `(0, 0)` батька).
  Масштаб у світі — `scale` вузла-кореня об'єкта.
- Тінь будівлі — окремий `Sprite2D` під об'єктом (`z_index` нижче або перший у дереві), не в Y-sort.
- Світові об'єкти — під `Node2D` з `y_sort_enabled = true`; точка сортування — нижній край
  (`base_y` у rig) → корінь об'єкта зсувати так, щоб `position.y` = низ основи.
- Світіння, промені, іскри — тільки кодом, у спрайти не запікаються.
  Сяйво: `Sprite2D` з радіальною `GradientTexture2D` + `CanvasItemMaterial.blend_mode = BLEND_MODE_ADD`.
  Іскри: `GPUParticles2D` (на вебі — `CPUParticles2D`, якщо GPU-частинки не тягне).
- Кути в rig — градуси, за годинниковою стрілкою, відносно намальованої пози → `rotation = deg_to_rad(a)`.

## Ядро — `art/objects/buildings/core/`

```
Core (Node2D)
  Shadow   Sprite2D  core_shadow.png
  Sprite   Sprite2D  core.png
  Beam     (код)     промінь/пульс з диска зверху
```

## Бур — `art/objects/buildings/drill/` (`drill_rig.json`)

```
Drill (Node2D)
  BodyShadow  Sprite2D  drill_body_shadow.png
  ArmShadow   Node2D    (код, див. нижче)
  Body        Sprite2D  drill_body.png
  Shoulder    Node2D  position = shoulder_on_body
    Arm1      Sprite2D drill_arm_1.png, offset = -seg1.pivot
    Elbow     Node2D  position = seg1.end - seg1.pivot
      Arm2    Sprite2D drill_arm_2.png, offset = -seg2.pivot
      Wrist   Node2D  position = seg2.end - seg2.pivot
        Arm3  Sprite2D drill_arm_3.png, offset = -seg3.pivot
        Lens  Marker2D position = seg3.lens - seg3.pivot + laser.tip_offset
```

`draw_order` у rig: Arm3 під Arm2 під Arm1 → у дереві Arm3 малюється першим (`show_behind_parent`
або порядок/`z_index`).

**Цикл** (`timing_s`): опускає → заряд → стріляє → охолодження → піднімає → чекає. Рух між
`pose_up` і `pose_fire` — `Tween` з `TRANS_QUAD, EASE_IN_OUT` по `rotation` трьох суглобів.
Під час пострілу — тремтіння `recoil` (синус по голові і невеликий зсув).

**Промінь:** `Line2D` (або 3 шари: сяйво, середина, біле ядро) від `Lens` до точки удару,
`blend ADD`, ширина × (1 + `flicker_a` · шум). Лінза — сяйво, що росте в заряді й гасне в охолодженні.
Точка удару — сяйво `hot_*`, іскри `sparks` (напрям, розкид, гравітація, життя).

**Тінь руки:** для кожного суглоба висота `h = groundY - y`, де `groundY` інтерполюється по
довжині руки від `shoulder_ground` до лінзи в позі пострілу; тінь суглоба = `(x + tx·h, groundY + ty·h)`;
кожен сегмент — темний силует, афінно натягнутий на тіні своїх двох суглобів
(формула — `segShadowMatrix` у `drill_anim.html`). У Godot: `Polygon2D` з текстурою-силуетом або
`draw_set_transform_matrix` у `_draw()`.

## Жила кристалів — `art/objects/resources/crystal_vein/` (`crystal_vein_rig.json`)

```
CrystalVein (Node2D)
  Shadow       Sprite2D  crystal_vein_shadow.png
  ShardShadows (код)     3 еліпси, менші й прозоріші, коли кристалик вище
  Vein         Sprite2D  crystal_vein.png
  Glow         Sprite2D  радіальне сяйво, ADD, пульс
  Shard1..3    Sprite2D  crystal_shard_N.png + своє сяйво
  DrillSlot    Marker2D  drill_slot.offset — єдине місце під бур
  HitPoint     Marker2D  drill_slot.hit_point — куди б'є лазер
```

- Кристалик: `y = center.y - sin((t/period + phase)·2π)·bob_amp`, хитання й «обертання» — формули
  в `shard_motion`. Рахувати в `_process`, не `Tween` (безкінечний синус).
- **Один бур на жилу:** у режимі будівництва бур не ставиться вільно — примарка «прилипає» до
  `DrillSlot` найближчої жили (зелена, якщо слот вільний; червона, якщо зайнятий). Поставлений бур
  отримує масштаб `drill_slot.scale` і цілиться в `HitPoint` (`auto_aim`: кут голови обчислюється
  так, щоб труба дивилась на ціль, плюс `head_offset`).

## Слизень — `art/objects/enemies/slime/` (`slime_rig.json`)

```
Slime (Node2D)            position = точка біля ніг (pivot)
  Shadow   (код)          еліпс shadow_ellipse, ширина × scale.x тіла
  Body     Node2D         scale, skew — анімація; scale.x < 0 при русі вліво
    Sprite Sprite2D       slime.png, offset = -pivot, centered = false
    Eye1..3 Node2D        маска ока (clip_children), усередині — повіка
```

- **Цикл** (`crawl`): фаза `p += dt·rate/period`; `f(p) = -cos(2π·u)`, де `u` пробігає 0…0.5 за
  частку `lunge` і 0.5…1 за решту. Ціль: `scale = (1 + stretch·f, 1 - squash·f)`; з `jelly > 0` —
  пружина (`k = 40 + 360·jelly`, `c = 2√k·damp`). `skew = -deg_to_rad(lean)·f(p - leanPhase)·dir`.
- **Рух «гусінь»:** за кадр зсув = `inch · W/2 · |Δscale_x| + slide · 64 · rate · dt` уздовж напрямку
  (`W` — ширина слизня у px). Середня швидкість — `avgSpeed()` у тюнері; під швидкість з балансу:
  `rate = speed / avgSpeed()`.
- **Моргання** (`blink_s`): серія — очі в порядку `blink_order` з кроком `bGap`, кожне
  закривається `bClose`, тримається `bHold`, відкривається `bOpen` (smoothstep); далі пауза
  `bPause + randf()·bRand`. Повіка — еліпс `rx·1.2 × ry` кольору `lid`, центр
  `y - 2·ry + 2·ry·closure`, обрізаний еліпсом ока мінус очі зі списку `over`.
- Натовп сотнями: не по `Node2D` на кожного, а `MultiMeshInstance2D` + масив станів (AGENTS.md);
  моргання тоді — окремим шаром або шейдером.

## Тюнери

| Об'єкт | Тюнер | Що крутити |
|---|---|---|
| Ядро | `core/core_shadow_editor.html` | тінь |
| Бур | `drill/drill_anim.html` | пози, фази, промінь, іскри, тінь руки |
| Жила | `crystal_vein/crystal_vein_anim.html` | кристалики, сяйво |
| Жила + бур | `crystal_vein/crystal_vein_drill_scene.html` | місце бура, точка удару, постріл по кристалу |
| Слизень | `enemies/slime/slime_crawl.html` | повзання, желе, моргання, тінь, натовп |

Змінив у тюнері → «Скопіювати параметри» → оновити `*_rig.json` (і дефолти в HTML).
