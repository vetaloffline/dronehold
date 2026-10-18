---
name: ship
description: Доставити поточну роботу — перевірити тести на копії, закомітити, запушити гілку й створити PR у main (або оновити вже відкритий). Тільки коли людина сама набрала /ship.
argument-hint: "[що зроблено] [не чисть драфт] | --help"
disable-model-invocation: true
---

# /ship — коміт, пуш, PR

Вхід: `$ARGUMENTS` — порожньо, або опис змін (бере участь у назві гілки, заголовку коміту й PR), або
фраза «не чисть драфт» / «keep drafts» (вимикає чистку чернеток сесії після пушу, крок 6).

Правила для всіх кроків:
- Кожна команда `git` і `gh` — окремим викликом Bash з кореня репо: без `cd … &&`, без `git -C`, без пайпів
  після `gh`. Інакше команда не потрапляє в `excludedCommands` sandbox і падає на мережі/TLS.
- Шлях до файлу для `gh` — абсолютний у scratchpad сесії: `gh` працює поза sandbox, де `$TMPDIR` інший.
- PR не мерджити ніколи.
- СТОП = вивести причину й вивід команди, що впала, чекліст з кроку 9 і завершити skill без подальших кроків.

## Крок 0. Довідка

`$ARGUMENTS` = `--help` або `-h` → вивести блок нижче дослівно і завершити skill (нічого не перевіряти).

```
/ship [опис змін] [не чисть драфт]

Перевіряє, комітить, пушить гілку й створює PR у main (або оновлює відкритий). PR не мерджить.
Після успішного пушу видаляє чернетки цієї сесії: art/drafts/<id сесії>/ (чужі й старі не чіпає).

  опис змін       вільний текст: з нього назва нової гілки, заголовок коміту й PR;
                  сюди ж — обмеження («коміть тільки свої зміни»)
  не чисть драфт  лишити чернетки цієї сесії; те саме — «keep drafts»
  -h, --help      ця довідка

Приклади:
  /ship
  /ship relay build radius
  /ship турель 360 не чисть драфт
```

Інакше → крок 1.

## Крок 1. Зібрати стан

Виконати:
1. `git branch --show-current` → `BRANCH`.
2. `git status --short` → `DIRTY` = є хоч один рядок.
3. `git fetch origin --prune`.
4. Є upstream (`git rev-parse --abbrev-ref @{u}` успішний) → `AHEAD` = `git rev-list --count @{u}..HEAD`;
   upstream нема → `AHEAD` = `git rev-list --count origin/main..HEAD`.
5. `BRANCH` ≠ `main` → `gh pr view --json number,state,url` → `PR_STATE` = `OPEN` | `MERGED` | `CLOSED`;
   помилка «no pull requests found» → `PR_STATE` = `NONE`.

## Крок 2. Вибрати шлях

Перевіряти по черзі, спрацьовує перший збіг:
1. `DIRTY` = ні і `AHEAD` = 0 → вивести «Нічого доставляти — усе вже в PR #N» (`PR_STATE` = `MERGED`/`OPEN`)
   або «Нічого доставляти — усе вже в main» (`BRANCH` = `main`). СТОП.
2. `BRANCH` = `main` → крок 3.
3. `PR_STATE` = `MERGED` або `CLOSED` → крок 3.
4. Інакше → крок 4.

Не питати людину на цьому кроці.

## Крок 3. Нова гілка від свіжого main

Незакомічені зміни переносяться в нову гілку самі. Коміти з `AHEAD` на старій гілці не переносяться — якщо
`DIRTY` = ні і `AHEAD` > 0 на змердженій гілці: вивести список цих комітів (`git log --oneline origin/main..HEAD`)
і спитати, чи робити `git cherry-pick` у нову гілку. Відповідь «ні» → СТОП.

1. `BRANCH` = `main` → `git pull --ff-only`; інакше → `git fetch origin main:main`. Помилка → СТОП.
2. Назва: `<тип>/<назва>`. Тип за змінами: код гри (`game/`, `tests/`) → `feat` або `fix` (виправлення
   помилки); тільки `art/` → `art`; тільки `.md`, `docs/`, `.claude/`, `.agents/` → `docs`. Назва — 2–4
   англійські слова через дефіс з `$ARGUMENTS`, а якщо він порожній — зі змісту `git status`/`git diff`.
3. `git rev-parse --verify --quiet refs/heads/<гілка>` успішний або `git ls-remote --heads origin <гілка>`
   непорожній → додати до назви `-2`, `-3`… до вільної.
4. `git switch -c <гілка> main`. Помилка (конфлікт переносу змін) → СТОП.
5. `BRANCH` = нова гілка, `PR_STATE` = `NONE`. → крок 4.

## Крок 4. Визначити, які перевірки потрібні

`CHANGED` = шляхи з `git status --short` плюс `git diff --name-only origin/main...HEAD`.

- Хоч один шлях у `game/`, `tests/`, `project.godot`, `art/objects/` або з розширенням `.gd`, `.tscn`,
  `.tres`, `.gdshader`, `.import` → крок 5 (тести гри).
- Інакше → записати «тести гри не ганяли: змінено тільки <список верхніх папок>» → крок 6.

Окремо: шлях у `.claude-plugin/` або `plugins/` → виконати `claude plugin validate .` і
`claude plugin validate plugins/my-toolkit` (у sandbox, той самий розбір виводу, що для `.claude/skills/` нижче);
exit ≠ 0 або рядок `✘` → СТОП. Хук guard-main.py підключений двічі: у `.claude/settings.json` і через плагін
`my-toolkit@dronehold` (`plugins/my-toolkit/hooks/hooks.json`). Запис у settings.json не прибирати: політика
організації може блокувати маркетплейс з папки (`is blocked by enterprise policy`), і тоді працює тільки він.

Окремо: шлях у `.agents/hooks/`, `plugins/` або `.claude/settings.json` → виконати `bash .agents/hooks/test-guard-main.sh`
і `bash .agents/hooks/test-guard-rm.sh` (другий перевіряє й підключення хука в settings.json); у будь-якому є
рядок `FAIL` або exit ≠ 0 → СТОП.

Окремо: шлях у `.claude/skills/` → виконати `claude plugin validate .claude/skills` (у sandbox; блок
`<sandbox_violations>` про `datadoghq.com` і `api.anthropic.com` — телеметрія, не помилка).
- exit ≠ 0 або рядок `✘` → СТОП: скіл з такою помилкою вантажиться з порожнім frontmatter (Claude не бачить
  `description`, губляться `disable-model-invocation` і решта полів).
- exit 0 і рядки `⚠` → записати попередження для звіту, продовжити.
- Не ловить (перевірено): невідомі поля, невалідні значення (`disable-model-invocation: maybe`). Ці поля
  переглянути в diff очима.

## Крок 5. Тести гри на копії

Тільки на копії (`.claude/rules/editor-and-perf.md`: редактор може бути відкритий).

```
rsync -a --delete --exclude .git --exclude .godot --exclude art/drafts --exclude '.env*' ./ $TMPDIR/dh_copy/
godot --headless --path $TMPDIR/dh_copy --import > $TMPDIR/dh_import.txt 2>&1; echo "import exit=$?"; grep -E 'SCRIPT ERROR|Parse Error' $TMPDIR/dh_import.txt | head -5
for t in run_tests smoke_game smoke_sandbox smoke_menu smoke_turret_360 smoke_map_editor; do godot --headless --path $TMPDIR/dh_copy --script res://tests/$t.gd > $TMPDIR/dh_$t.txt 2>&1; echo "$t exit=$?"; grep -E '^(tests|smoke|menu|sandbox|turret 360|map editor):|SCRIPT ERROR|Parse Error' $TMPDIR/dh_$t.txt | head -5; done
```

Тест пройшов, якщо одночасно: exit 0; підсумковий рядок (`tests:`, `smoke:`, `menu:`, `sandbox:`,
`turret 360:`, `map editor:`) закінчується на `0 failed`; нема `SCRIPT ERROR` і `Parse Error`.
Скрипт, що не скомпілювався, теж дає exit 0 — тому підсумковий рядок обов'язковий.

Виняток `smoke_menu`: у його виводі є `cannot save user://settings.cfg` і `FAIL: sound button mutes and remembers`
→ це sandbox (не пускає в `~/Library/Application Support/Godot`). Виконати `echo $TMPDIR` у sandbox, потім
перезапустити тільки `smoke_menu` з `dangerouslyDisableSandbox: true` і абсолютним шляхом до копії та виводу.

Будь-який тест не пройшов → СТОП (нічого не комітити).

Механіка: зміни в `game/` змінюють ігрове правило (ціни, урон, радіус, швидкість, хвилі, новий об'єкт чи
поведінка), а `docs/concept.md` не в `CHANGED` → спитати «Оновити docs/concept.md під цю зміну?».
«Так» → оновити й додати до коміту. «Ні» → крок 6.

## Крок 6. Чернетки

Чернетки цієї сесії — тільки `art/drafts/${CLAUDE_SESSION_ID}/`. Решта `art/drafts/` — інших сесій, що
працюють паралельно, або старі: їх не видаляти ніколи, ні скриптом, ні іншими командами.

- `$ARGUMENTS` містить «не чисть драфт» або «keep drafts» → `CLEAN` = ні.
- Інакше → `CLEAN` = так (рішення людини 2026-10-14: після доставки чернетки сесії не потрібні — апрувнуте
  вже перенесено в `art/`; чистити без нагадування).

Тут нічого не видаляти: чистка — у кроці 7 після успішного пушу (впала доставка → чернетки лишаються).
Записати для звіту верхні папки решти `art/drafts/` як «інші сесії або старі, не чіпав».

→ крок 7.

## Крок 7. Коміт і пуш

1. `git status --short`. Не додавати: `*.log`, `scratch/`, `.claude/.cc-writes/`, `.env*`, `*.pem`, `*.key`,
   файли > 10 МБ поза `art/`. Інший незнайомий файл, якого не створювали в цій сесії і не видно з
   `$ARGUMENTS`, — спитати, чи комітити.
2. Групи комітів: один коміт на одну зміну за змістом (фіча разом з її тестами й доками — один коміт;
   незв'язана правка README чи конфігів — окремий).
3. Заголовок — англійською, у стилі `git log --oneline -10`: `<Що>: <суть>`. Без підпису Claude і
   `Co-Authored-By`.
4. `git add <шляхи групи>` → `git commit` — на кожну групу.
5. `git push -u origin HEAD`. Помилка → СТОП.
6. `CLEAN` = так → `bash .claude/skills/art/scripts/clean_drafts.sh` (видаляє тільки папку цієї сесії, решту
   перелічує); exit ≠ 0 → вивести його повідомлення, продовжити (чернетки не блокують доставку).
   `CLEAN` = ні → записати для звіту, що `art/drafts/${CLAUDE_SESSION_ID}/` лишено на прохання.
7. Чужі чернетки (рядки «лишились» з виводу `clean_drafts.sh`, або `ls art/drafts` при `CLEAN` = ні, без папки
   цієї сесії) — самому не видаляти ніколи, тільки спитати → крок «Чужі чернетки» в
   `.claude/skills/art/SKILL.md` (питання з галочками). Нема чужих → далі.

`PR_STATE` = `OPEN` → крок 9. `PR_STATE` = `NONE` → крок 8.

## Крок 8. Створити PR

1. Записати тіло інструментом Write у `<scratchpad>/pr_body.md` (абсолютний шлях scratchpad — з опису
   середовища сесії):

```
## Що зроблено

- **<суть>** — <пояснення>.

## Перевірки (копія репо, Godot 4.7.2)

- `run_tests` — exit 0, N passed, 0 failed
- `smoke_*` — exit 0, 0 failed
- Не перевіряли: <вікно / телефон / що саме>.
```

   Крок 5 пропущено → у «Перевірки» написати рядок з кроку 4 замість результатів тестів.
   Був `claude plugin validate`, `test-guard-main.sh` чи `test-guard-rm.sh` → додати в «Перевірки» рядком з результатом.
2. `gh pr create --base main --head <BRANCH> --title "<заголовок англійською>" --body-file <scratchpad>/pr_body.md`

→ крок 9.

## Крок 9. Звіт людині

Вивести чекліст. Позначки: `[x]` зроблено, `[ ]` не зроблено (СТОП раніше або чекає людину), `[–]` пропущено —
після позначки причина. Кожен рядок — з фактом, не «ок».

```
- [x] Гілка: <BRANCH> (нова від main / існуюча)
- [x] Коміти: <git log --oneline origin/main..HEAD>
- [x] Тести гри: <кожен тест: exit, підсумковий рядок>  |  [–] змінено тільки <папки>
- [x] validate скілів: <✔ / ⚠ попередження>  |  [–] .claude/skills/ не змінювали
- [x] validate маркетплейсу й my-toolkit: <✔ / ⚠ попередження>  |  [–] .claude-plugin/ і plugins/ не змінювали
- [x] test-guard-main.sh, test-guard-rm.sh: <результат кожного>  |  [–] .agents/hooks/ і settings.json не змінювали
- [x] Чернетки цієї сесії: <видалено / лежать: …>; інші сесії й старі (не чіпав): <папки>
- [x] Пуш: origin/<BRANCH>
- [x] PR: <посилання> (створено / оновлено)
- [ ] Мердж — робить людина
```

СТОП на будь-якому кроці → той самий чекліст: що встигли — `[x]`, на чому зупинились і решта — `[ ]`.
