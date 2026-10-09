# Dronehold

2D-оборона бази з видобутком, вид 3/4. Godot 4.7.2, GDScript, рендерер Compatibility.
Платформи: мобілка (головна) → ПК → браузер. Як влаштовано — [docs/godot-notes.md](docs/godot-notes.md).
Концепт і всі ухвалені рішення: [docs/concept.md](docs/concept.md). Читай його перед роботою над механікою.

## Початок роботи

- Нова гілка — **завжди від свіжого `main`**, ніколи від іншої гілки:
  `git fetch origin` → `git switch -c <тип>/<назва> origin/main`.
  Якщо задача залежить від незмерженої гілки — спершу мердж тієї гілки в `main`, потім нова гілка.

## Правила проєкту

- GDScript, без C# (проєкти на C# у Godot 4 не експортуються у веб). Виняток — гарячий цикл рою
  (`game/swarm/swarm_sim.gd`) можна перенести на C++ (GDExtension), не міняючи його масивів.
- Спрайти статичні (генерує ШІ). Будь-яка анімація — кодом: `Tween`, `scale`, `rotation`, синус.
- Арт: де що лежить, як генерувати й апрувити — [docs/art-pipeline.md](docs/art-pipeline.md).
- Pivot спрайтів юнітів біля ніг; під кожним тінь-еліпс; світ сортується по Y.
- Ціна будь-чого — словник: `cost = {"crystal": 50}`, не число. Так другий ресурс додається без переписування.
- Склади (ядро, ретранслятор) — у групі `"storage"`; дрон шукає найближчий через одну функцію.
- Масові вороги — не по ноді на кожного: рій у масивах (`SwarmSim`), малювання `MultiMesh` смугами.
- Об'єкт = сцена `game/objects/<назва>/` + спільний `<назва>_rig.tres`; усе `@tool`, анімується в редакторі.

## Перевірки

```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/smoke_game.gd
godot --headless --path . --script res://tests/smoke_sandbox.gd
godot --headless --path . --script res://tests/smoke_menu.gd
godot --headless --path . --script res://tests/smoke_turret_360.gd
```

Усі — exit 0 **і** у виводі є `tests: … 0 failed` / `smoke: 0 failed`, нема `SCRIPT ERROR`
(скрипт, що не скомпілювався, теж дає exit 0). Шейдери й картинку headless не перевіряє — потрібен
запуск у вікні.

## Як працюємо

- Спершу найменша робоча петля «добув → збудував → вистояв», потім глибина.
- Нова механіка чи зміна рішення — оновити `docs/concept.md` у тому ж кроці.
