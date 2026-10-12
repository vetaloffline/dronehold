#!/usr/bin/env bash
# Чистить art/drafts/: видаляє весь вміст, саму папку лишає.
# Аргументів не приймає: шлях зашитий, щоб скриптом не можна було видалити щось інше.
# Окремий скрипт, бо в .claude/settings.json є deny на `rm -rf *`, а allow не робить з deny винятків;
# правило Bash матчить текст команди, тому allow на цей скрипт не відкриває інших `rm -rf`.
set -euo pipefail

if [ $# -ne 0 ]; then
  echo "clean_drafts: аргументи не приймаються" >&2
  exit 2
fi

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
drafts="$root/art/drafts"

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
items=("$drafts"/*)
if [ ${#items[@]} -eq 0 ]; then
  echo "clean_drafts: art/drafts уже порожня"
  exit 0
fi
for p in "${items[@]}"; do
  echo "видаляю art/drafts/${p##*/}"
done
rm -rf -- "${items[@]}"
echo "clean_drafts: готово, видалено ${#items[@]}"
