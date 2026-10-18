# my-toolkit

## Purpose

Не дає агенту змінювати `main`/`master` напряму. На `main` дозволені тільки читання, `pull`, `fetch` і перехід
на іншу гілку. Зміни йдуть через гілку й PR. Хук упакований як плагін: репо підключає його кожному, хто клонує,
і його можна поставити в інший проєкт.

## Install

Нічого ставити не треба: `.claude/settings.json` репо реєструє маркетплейс і вмикає плагін.

```json
"extraKnownMarketplaces": { "dronehold": { "source": { "source": "directory", "path": "." } } },
"enabledPlugins": { "my-toolkit@dronehold": true }
```

1. Клонувати репо, запустити `claude` у корені.
2. Прийняти діалог довіри до папки. Без нього маркетплейс з project settings не реєструється, і хук не працює.
3. Перевірити: `/plugin` → `my-toolkit@dronehold` увімкнений, або `claude plugin list`.

Відносний `path` рахується від main checkout репо, тому у worktree плагін береться з main checkout.

Політика організації (`strictKnownMarketplaces` у managed settings) може не пускати маркетплейс з папки:
`/plugin` і `claude plugin list` тоді показують `Marketplace source 'dir:…' is blocked by enterprise policy`, і
плагін не вантажиться. Тому в dronehold `guard-main.py` підключений ще й прямо в `.claude/settings.json`. Там, де
плагін завантажився, хук спрацьовує двічі, з однаковою відповіддю. `--plugin-dir` ця політика не блокує.

В іншому проєкті — поставити з GitHub (Claude Code клонує весь репо dronehold як маркетплейс):

```
/plugin install my-toolkit --marketplace vetaloffline/dronehold
```

Разовий запуск без маркетплейсу (id буде `my-toolkit@inline`):

```bash
claude --plugin-dir ./plugins/my-toolkit
```

## Commands

—

## Skills

| Виклик | Що робить |
|---|---|
| `/my-toolkit:guard-test` | проганяє `test-guard-main.sh` з тієї копії плагіна, яку завантажив Claude Code, і показує її шлях |

Тільки ручний виклик (`disable-model-invocation: true`).

## Hooks

| Подія | Matcher | Команда | Що робить |
|---|---|---|---|
| `PreToolUse` | `Bash` | `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/guard-main.py"` | exit 2 (заборона з причиною в stderr) для змін main/master: commit/push/merge на main, push у main з гілки, `gh pr merge`, зміни main через `gh api`; exit 0 — решта |

`hooks/guard-main.py` і `hooks/test-guard-main.sh` — symlink на `.agents/hooks/`. Справжні файли лишаються там,
бо `.agents/hooks/` захищена sandbox від запису агентом, і цей же `guard-main.py` імпортує `guard-rm.py` та
викликає Codex (`.codex/hooks`).
