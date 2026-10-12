---
name: godot
description: Перезапустити Godot — вбити завислий процес і відкрити редактор (за замовчуванням) або гру. Тільки коли людина сама набрала /godot.
argument-hint: "[editor|game]"
disable-model-invocation: true
---

# /godot — убити й запустити

Вхід: `$ARGUMENTS` = `game` → `MODE` = `game` (головна сцена `main_menu.tscn` з `project.godot`);
інше або порожньо → `MODE` = `editor`.

Правила для всіх кроків:
- `ps`, `kill`, `nohup godot …` — тільки з `dangerouslyDisableSandbox: true` (у sandbox `ps`: operation not permitted).
- Поза sandbox `$TMPDIR` інший, ніж у sandbox: запуск і читання лога — в одному виклику Bash.
- `REPO` = вивід `git rev-parse --show-toplevel`.
- СТОП = вивести причину й вивід команди і завершити skill.

## Крок 1. Знайти процеси

`ps -axo pid,etime,command | grep -i '[G]odot'` (поза sandbox).

Розкласти кожен рядок:
- у команді `--headless` → `HEADLESS` (тести чи імпорт; не чіпати ніколи);
- у команді `-e` або `--editor` → `EDITOR`;
- у команді `--remote-debug` → `GAME_FROM_EDITOR`;
- решта → `OTHER` (гра з CLI або редактор, відкритий з Project Manager).

→ крок 2.

## Крок 2. Що вбивати

- `MODE` = `editor` → `KILL` = `EDITOR` + `GAME_FROM_EDITOR` + `OTHER`. Непорожній → вивести «Незбережене в
  редакторі пропаде». → крок 3.
- `MODE` = `game`, `EDITOR` порожній → `KILL` = `GAME_FROM_EDITOR` + `OTHER`. → крок 3.
- `MODE` = `game`, `EDITOR` непорожній → спитати через AskUserQuestion «Редактор відкритий. Закрити його й
  запустити гру з CLI, чи запустиш гру кнопкою ▶ (F5) у редакторі?» (запуск гри з CLI поруч з відкритим
  редактором не перевіряли — невідомо, чи чіпає він `.godot/`). «Закрити» → `KILL` = усі не-`HEADLESS`,
  → крок 3. «F5» → СТОП без дій.

`KILL` порожній → крок 4.

## Крок 3. Убити

Поза sandbox, `<pids>` — PID з `KILL`:

```
kill <pids>; sleep 3; for p in <pids>; do kill -0 $p 2>/dev/null && kill -9 $p; done; ps -axo pid,command | grep -i '[G]odot'
```

Хоч один PID з `KILL` ще живий → СТОП. → крок 4.

## Крок 4. Запустити

Поза sandbox, один виклик:

- `MODE` = `editor`:
  `nohup godot --path <REPO> -e > $TMPDIR/godot_editor.log 2>&1 & sleep 6; ps -axo pid,etime,command | grep -i '[G]odot'; grep -E 'SCRIPT ERROR|ERROR' $TMPDIR/godot_editor.log | head -10; tail -5 $TMPDIR/godot_editor.log`
- `MODE` = `game`:
  `nohup godot --path <REPO> > $TMPDIR/godot_game.log 2>&1 & sleep 6; ps -axo pid,etime,command | grep -i '[G]odot'; grep -E 'SCRIPT ERROR|ERROR' $TMPDIR/godot_game.log | head -10; tail -5 $TMPDIR/godot_game.log`

Нового процесу Godot у виводі `ps` нема → вивести хвіст лога. СТОП (повторно не запускати).

## Крок 5. Звіт людині

Вивести: вбиті PID (і чи знадобився `kill -9`), PID запущеного процесу, рядки `SCRIPT ERROR`/`ERROR` з лога
або «помилок у лозі нема», процеси `HEADLESS`, якщо були.
