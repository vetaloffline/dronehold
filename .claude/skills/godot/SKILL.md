---
name: godot
description: Перезапустити Godot — вбити завислий процес і відкрити редактор (за замовчуванням) або гру. Тільки коли людина сама набрала /godot.
argument-hint: "[editor|game]"
disable-model-invocation: true
---

# /godot — убити й запустити

Режим: `$ARGUMENTS` — `game` → гра (головна сцена `main_menu.tscn` з `project.godot`), інакше редактор.

`ps`, `kill`, запуск вікна в sandbox не працюють (`ps`: operation not permitted) — ці команди тільки з
`dangerouslyDisableSandbox: true`. Шлях до проєкту — корінь репо (`git rev-parse --show-toplevel`).

## 1. Що запущено

```
ps -axo pid,etime,command | grep -i '[G]odot'
```

Розкласти:
- редактор — у команді `-e` або `--editor`;
- гра з редактора — `--remote-debug`;
- `--headless` — тести чи імпорт (свої чи з іншої сесії): **не чіпати**, тільки згадати.

## 2. Убити

- **Редактор** (режим `editor`) — усі не-headless процеси Godot. Попередити одним рядком: незбережене в
  редакторі пропаде.
- **Гра** (режим `game`) — тільки процеси гри. Редактор живий і не завис — його не вбивати: запуск гри
  з CLI поруч з відкритим редактором ми не перевіряли (чи чіпає він `.godot/` — не знаю), тому
  спитати: закрити редактор чи запустити гру кнопкою ▶ (F5) у самому редакторі.

```
kill <pid…>; sleep 3; for p in <pid…>; do kill -0 $p 2>/dev/null && kill -9 $p; done; ps -axo pid,command | grep -i '[G]odot'
```

## 3. Запустити

Редактор:
```
nohup godot --path <репо> -e > $TMPDIR/godot_editor.log 2>&1 &
```
Гра:
```
nohup godot --path <репо> > $TMPDIR/godot_game.log 2>&1 &
```

Потім `sleep 6; ps -axo pid,etime,command | grep -i '[G]odot'; tail -20 <лог>`.

## Звіт

Що вбито (pid), що запущено (pid), живий процес чи ні, помилки з лога (`SCRIPT ERROR`, `ERROR`).
Процес помер одразу — показати хвіст лога, повторно не запускати.
