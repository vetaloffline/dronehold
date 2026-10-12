#!/usr/bin/env bash
# Чистить чернетки поточної сесії Claude Code: видаляє тільки art/drafts/<id сесії>/.
# Папки інших сесій і старі чернетки поза папками сесій не чіпає: у репо паралельно працюють кілька сесій.
# Id сесії бере з $CLAUDE_CODE_SESSION_ID (Claude Code виставляє його в shell; збігається з
# ${CLAUDE_SESSION_ID}, який скіл art підставляє в шляхи чернеток). Аргументів не приймає: так агент не
# може передати чужий id, а шлях не можна підмінити.
# Окремий скрипт, бо в .claude/settings.json є deny на `rm -rf *`, а allow не робить з deny винятків;
# правило Bash матчить текст команди, тому allow на цей скрипт не відкриває інших `rm -rf`.
set -euo pipefail

if [ $# -ne 0 ]; then
  echo "clean_drafts: аргументи не приймаються" >&2
  exit 2
fi

id="${CLAUDE_CODE_SESSION_ID:-}"
if ! [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "clean_drafts: нема id сесії в CLAUDE_CODE_SESSION_ID ('$id') — нічого не видаляю" >&2
  exit 2
fi

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
drafts="$root/art/drafts"
mine="$drafts/$id"

if [ ! -e "$drafts" ]; then
  echo "clean_drafts: art/drafts нема — нічого чистити"
  exit 0
fi
if [ -L "$drafts" ] || [ ! -d "$drafts" ]; then
  echo "clean_drafts: art/drafts — не звичайна папка, не чіпаю" >&2
  exit 2
fi
if ! git -C "$root" check-ignore -q --no-index art/drafts/; then
  echo "clean_drafts: art/drafts не в .gitignore — не чіпаю" >&2
  exit 2
fi
if [ -n "$(git -C "$root" ls-files art/drafts)" ]; then
  echo "clean_drafts: в art/drafts є файли під git — не чіпаю" >&2
  exit 2
fi

shopt -s nullglob dotglob
if [ ! -e "$mine" ]; then
  echo "clean_drafts: чернеток цієї сесії (art/drafts/$id) нема"
elif [ -L "$mine" ] || [ ! -d "$mine" ]; then
  echo "clean_drafts: art/drafts/$id — не звичайна папка, не чіпаю" >&2
  exit 2
else
  for p in "$mine"/*; do
    echo "видаляю art/drafts/$id/${p##*/}"
  done
  rm -rf -- "$mine"
  echo "clean_drafts: готово, видалено art/drafts/$id"
fi

left=("$drafts"/*)
if [ ${#left[@]} -eq 0 ]; then
  echo "clean_drafts: art/drafts порожня"
else
  echo "clean_drafts: лишились (інші сесії або старі чернетки, не чіпав):"
  for p in "${left[@]}"; do
    echo "  art/drafts/${p##*/}"
  done
fi
