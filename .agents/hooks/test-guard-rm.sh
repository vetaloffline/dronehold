#!/usr/bin/env bash
# Тести guard-rm.py: pass — пропустити без питань, ask — спитати людину (JSON permissionDecision "ask"),
# deny — заборонити (exit 2). Наприкінці — чи хук підключений у .claude/settings.json і чи там не лишилось
# правил rm, що його перекривають (deny/ask сильніші за хук).
# Запуск: bash .claude/hooks/test-guard-rm.sh
H="$(cd "$(dirname "$0")" && pwd)/guard-rm.py"
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
T=$(mktemp -d "${TMPDIR:-/tmp}/guardrm.XXXXXX")
T=$(cd "$T" && pwd -P)
mkdir -p "$T/repo/art/drafts/sess/x" "$T/repo/art/drafts/old" "$T/repo/art/drafts/with space" \
  "$T/repo/game" "$T/repo/art/objects" "$T/other"
git -C "$T/repo" init -q
ln -s "$T/repo/game" "$T/repo/art/drafts/link"
pass=0; fail=0
run() {  # $1 = stdin JSON → "pass" | "ask" | "deny" | "rc=N"
  local out rc
  out=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$T/repo" python3 "$H" 2>&1); rc=$?
  if [ "$rc" = 2 ]; then echo deny
  elif [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '"permissionDecision": "ask"'; then echo ask
  elif [ "$rc" = 0 ] && [ -z "$out" ]; then echo pass
  else echo "rc=$rc:$out"; fi
}
check() {  # $1 очікуване, $2 отримане, $3 опис
  if [ "$2" = "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL exp=$1 got=$2 :: $3"; fi
}
t() {  # $1 очікуване, $2 cwd від $T, $3 команда
  check "$1" "$(run "$(jq -n --arg c "$3" --arg d "$T/$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')")" "[$2] $3"
}

# === pass: усе всередині art/drafts/ — без питань
t pass repo 'rm -rf art/drafts/old'
t pass repo 'rm -rf art/drafts/sess art/drafts/old'
t pass repo 'rm -r -f art/drafts/sess/x'
t pass repo 'rm -fr -- art/drafts/old'
t pass repo 'rm -Rf art/drafts/old'
t pass repo 'rm --recursive --force art/drafts/old'
t pass repo 'rm -rfv art/drafts/old'
t pass repo 'rm -rf ./art/drafts/old'
t pass repo 'rm -rf "art/drafts/with space"'
t pass repo "rm -rf 'art/drafts/with space'"
t pass repo 'rm -rf art/drafts/*'
t pass repo 'rm -rf art/drafts/sess/*'
t pass repo 'rm art/drafts/sess/a.png'
t pass repo 'rm -f art/drafts/sess/*.png'
t pass repo 'rm -i art/drafts/sess/a.png'
t pass repo 'unlink art/drafts/sess/a.png'
t pass repo/art 'rm -rf drafts/old'
t pass repo/art/drafts 'rm -rf old sess'
t pass repo 'cd art/drafts && rm -rf old'
t pass repo 'cd art && cd drafts && rm -rf old'
t pass repo "rm -rf $T/repo/art/drafts/old"
t pass repo 'rm -rf art/drafts/link'
t pass repo 'rm -rf art/drafts/old 2>/dev/null'
t pass repo 'rm -rf art/drafts/old; echo done'
t pass repo 'rm -rf art/drafts/old && rm -rf art/drafts/sess'
t pass repo 'ls art/drafts && rm -rf art/drafts/old || true'
t pass repo 'bash -c "rm -rf art/drafts/old"'
t pass repo 'sh -c "rm -rf art/drafts/old"'
t pass repo 'nohup rm -rf art/drafts/old'
t pass repo 'time rm -rf art/drafts/old'
t pass repo 'sudo rm -rf art/drafts/old'
t pass repo 'find art/drafts/old -name "*.png" -delete'
t pass repo 'find art/drafts -type f -exec rm {} +'
t pass repo 'bash .claude/skills/art/scripts/clean_drafts.sh'
# === pass: не видалення — хук мовчить
t pass repo 'echo "rm -rf /"'
t pass repo "git commit -m 'rm -rf game'"
t pass repo 'git rm -r game'
t pass repo 'ls -la'
t pass repo 'grep -rn "rm" game'
t pass repo 'find . -name "*.gd"'
t pass repo 'rmdir art/drafts/old'
t pass repo 'mkdir -p art/drafts/new'
check pass "$(run '{"tool_name":"Edit","tool_input":{"file_path":"x"},"cwd":"/"}')" "не Bash"
check pass "$(run 'not json')" "битий JSON на вході"
check pass "$(run '{"tool_name":"Bash","tool_input":{},"cwd":"/"}')" "Bash без команди"

# === ask: поза art/drafts/ або шлях не видно — з дозволу людини
t ask repo 'rm game/a.gd'
t ask repo 'rm -f art/objects/x.png'
t ask repo 'rm README.md'
t ask repo 'unlink game/a.gd'
t ask repo 'rm -rf game'
t ask repo 'rm -r -f game'
t ask repo 'rm -R game'
t ask repo 'rm --recursive game'
t ask repo 'rm -rf art/objects'
t ask repo 'rm -rf art/drafts/../objects'
t ask repo 'rm -rf art/drafts/old game'
t ask repo 'rm -rf art/dr*'
t ask repo 'rm -rf $HOME/x'
t ask repo 'rm -rf ${TMPDIR}/x'
t ask repo 'rm -rf `pwd`/art/drafts/old'
t ask repo 'rm -rf $(pwd)/art/drafts/old'
t ask repo 'echo $(rm -rf game)'
t ask repo '(rm -rf game)'
t ask repo 'cd $X && rm -rf old'
t ask repo 'cd .. && rm -rf repo/game'
t ask repo 'ls && rm -rf game'
t ask repo 'rm -rf art/drafts/old && rm -rf game'
t ask repo 'bash -c "rm -rf game"'
t ask repo 'zsh -c "rm game/a.gd"'
t ask repo 'FOO=1 rm -rf game'
t ask repo 'env rm -rf game'
t ask repo 'command rm -rf game'
t ask repo '/bin/rm -rf game'
t ask repo 'sudo rm -rf game'
t ask repo 'sudo -u root rm game/a.gd'
t ask repo 'find . -name x | xargs rm -rf'
t ask repo 'find game -name "*.tmp" -delete'
t ask repo 'find art/drafts/.. -delete'
t ask repo 'rm -rf art/drafts/link/../../game'
t ask repo "rm -rf $T/other"
t ask repo 'rm -rf "art/drafts/old" "game"'
t ask repo "bash <<'EOF'
rm -rf game
EOF"

# === deny: катастрофічне — навіть з дозволом ні
t deny repo 'rm -rf art/drafts'
t deny repo 'rm -rf art/drafts/'
t deny repo 'rm -rf ./art/drafts/.'
t deny repo 'rm -rf .'
t deny repo 'rm -rf ..'
t deny repo 'rm -rf /'
t deny repo 'rm -rf /*'
t deny repo 'rm -rf ~'
t deny repo 'rm -rf ~/'
t deny repo "rm -rf $T/repo"
t deny repo/art/drafts 'rm -rf ../..'
t deny repo 'rm -rf art/drafts/old && rm -rf .'
t deny repo 'sudo rm -rf /'
t deny repo 'find . -delete'
t deny repo 'find -delete'
t deny repo 'find . -type f -exec rm {} \;'
t deny repo 'bash -c "rm -rf ~"'

# === підключення в settings.json (deny і ask на rm сильніші за хук — їх там бути не має)
S="$REPO/.claude/settings.json"
check yes "$(jq -r '[.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command | test("guard-rm\\.py")] | any | if . then "yes" else "no" end' "$S")" "settings.json: guard-rm.py у PreToolUse Bash"
check none "$(jq -r '[(.permissions.deny // [])[], (.permissions.ask // [])[] | select(test("^Bash\\((rm|unlink|find)\\b"))] | if length==0 then "none" else join(", ") end' "$S")" "settings.json: нема deny/ask на rm"

echo "guard-rm tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
