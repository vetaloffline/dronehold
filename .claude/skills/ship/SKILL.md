---
name: ship
description: Доставити поточну роботу — перевірити тести на копії, закомітити, запушити гілку й створити PR у main (або оновити вже відкритий). Тільки коли людина сама набрала /ship.
argument-hint: "[що зроблено] [почисть драфт]"
disable-model-invocation: true
---

# /ship — коміт, пуш, PR

Аргументи: `$ARGUMENTS` (може бути порожньо). Тут може бути опис для коміту й PR або вказівкою «почисть драфт».

Команди `git` і `gh` — кожну окремим викликом, без `cd … &&` і без пайпів після `gh`
(у sandbox `gh` у пайпі падає на TLS). Мерджити PR — ніколи (хук і deny на `gh pr merge` це й так блокують).

## 1. Що є

```
git branch --show-current
git status --short
git fetch origin --prune
```

Нові коміти: є upstream — `git rev-list --count @{u}..HEAD`, нема — `git rev-list --count origin/main..HEAD`.
PR гілки: `gh pr view --json number,state,url` (нема PR — команда падає з «no pull requests found», це нормально).

## 2. Чи є що доставляти

| Стан | Що робити |
|---|---|
| Нема незакомічених змін і нових комітів | Написати «Нічого доставляти — усе вже в PR #N» (або «…вже в main») і **зупинитись**. |
| Гілка `main` або PR гілки вже `MERGED`, є зміни | **Не питати й не зупинятись** — нова гілка від свіжого main (нижче), далі як завжди. |
| Інакше (PR `OPEN` або PR нема) | Далі. |

Нова гілка (незакомічені зміни переїжджають у неї самі):
- свіжий main: на `main` — `git pull --ff-only`; не на `main` — `git fetch origin main:main`;
- `git switch -c <тип>/<назва> main`: тип — `feat` | `fix` | `docs` | `art` | `refactor` | `test`, назва — 2–4
  англійські слова через дефіс за змістом змін (або з `$ARGUMENTS`); зайнята — інша назва.

Упало (локальний main має свої коміти, конфлікт при переносі) — тільки тоді показати помилку й зупинитись.

## 3. Перевірки

Тільки `.md` і `.claude/` у змінах — тести не ганяти, у звіті так і написати.

Інакше — на копії (правило `.claude/rules/editor-and-perf.md`, редактор може бути відкритий):

```
rsync -a --delete --exclude .git --exclude .godot --exclude art/drafts --exclude '.env*' ./ $TMPDIR/dh_copy/
godot --headless --path $TMPDIR/dh_copy --import > $TMPDIR/dh_import.txt 2>&1; echo "import exit=$?"; grep -E 'SCRIPT ERROR|Parse Error' $TMPDIR/dh_import.txt | head -5
for t in run_tests smoke_game smoke_sandbox smoke_menu smoke_turret_360 smoke_map_editor; do godot --headless --path $TMPDIR/dh_copy --script res://tests/$t.gd > $TMPDIR/dh_$t.txt 2>&1; echo "$t exit=$?"; grep -E '^(tests|smoke|menu|sandbox|turret 360|map editor):|SCRIPT ERROR|Parse Error' $TMPDIR/dh_$t.txt | head -5; done
```

`smoke_menu` у sandbox падає на «sound button mutes and remembers» (`cannot save user://settings.cfg (error 12)`):
`user://` — це `~/Library/Application Support/Godot/…`, sandbox туди не пускає. Тоді перезапустити тільки
його з `dangerouslyDisableSandbox: true`; `$TMPDIR` поза sandbox інший — шлях до копії підставити повний
(той, що `$TMPDIR/dh_copy` дає в sandbox). Поза sandbox він проходить (перевірено 2026-10-12).

Пройшло = кожен exit 0, кожен підсумковий рядок закінчується на `0 failed`, нема `SCRIPT ERROR`/`Parse Error`
(скрипт, що не скомпілювався, теж дає exit 0). Щось упало — показати вивід і **зупинитись**, нічого не комітити.

Зміни в механіці, а `docs/concept.md` не змінено — нагадати (AGENTS.md: нова механіка → оновити concept.md),
спитати, чи оновлювати, до коміту.

## 4. Чернетки

У `$ARGUMENTS` є «почисть драфт» або «clear draft directory» — `bash .claude/skills/art/scripts/clean_drafts.sh`.
Ні — не чіпати; якщо `art/drafts/` не порожня, одним рядком сказати, що там лежить.

## 5. Коміт і пуш

- `git status --short` ще раз; у коміт — зміни задачі. Не комітити випадкове: логи, `scratch/`,
  `.claude/.cc-writes`, файли з секретами. Сумнівний файл — спитати.
- Заголовок коміту англійською, як в історії (`git log --oneline -10`): «Що: коротко про суть».
  Різні за змістом зміни — окремими комітами.
- `git push -u origin HEAD`

## 6. PR

PR уже `OPEN` — пуш його оновив; дати посилання й закінчити.

PR нема — тіло у `$TMPDIR/pr_body.md` у форматі попередніх PR (наприклад #9):

```
## Що зроблено

- **Суть** — пояснення.

## Перевірки (копія репо, Godot 4.7.2)

- `run_tests` — exit 0, N passed, 0 failed
- smoke-тести — exit 0, 0 failed
- Що не перевіряли (вікно, телефон) — так і написати.
```

```
gh pr create --base main --head <гілка> --title "<заголовок англійською>" --body-file $TMPDIR/pr_body.md
```

## Звіт

Гілка, коміти (`git log --oneline origin/main..HEAD`), результат тестів з exit-кодами, посилання на PR.
