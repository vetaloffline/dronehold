#!/usr/bin/env bash
# Тести guard-main.py: очікуваний код виходу (0 — пропустити, 2 — заборонити).
# Запуск: bash .claude/hooks/test-guard-main.sh
H="$(cd "$(dirname "$0")" && pwd)/guard-main.py"
T=$(mktemp -d "${TMPDIR:-/tmp}/guard.XXXXXX")
cd "$T" && git init -q -b main repoA && git init -q -b feat repoB && mkdir norepo
pass=0; fail=0
t() {
  local exp=$1 dir=$2 cmd=$3 out rc
  out=$(jq -n --arg c "$cmd" --arg d "$T/$dir" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | python3 "$H" 2>&1); rc=$?
  if [ "$rc" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL exp=$exp got=$rc [$dir] $cmd :: $out"; fi
}
other() {
  local exp=$1 tool=$2 inp=$3 rc
  jq -n --arg t "$tool" --argjson i "$inp" '{tool_name:$t,tool_input:$i,cwd:"/"}' | python3 "$H" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$exp" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL exp=$exp got=$rc $tool $inp"; fi
}

# --- git: базові сценарії
t 0 repoB 'git commit -m "x"'
t 2 repoA 'git commit -m x'
t 0 repoA 'git pull'
t 0 repoA 'git pull --rebase origin main'
t 0 repoA 'git fetch origin'
t 2 repoA 'git pull origin feat'
t 2 repoB 'git push origin HEAD:main'
t 2 repoB 'git push origin +feat:refs/heads/main'
t 2 repoB 'git push origin :main'
t 0 repoB 'git push -u origin feat'
t 0 repoB 'git push --force-with-lease origin feat'
t 2 repoA 'git push'
t 2 repoA 'git push origin HEAD'
t 2 repoB 'git push --all'
t 2 repoB 'git checkout main && git merge feat'
t 2 repoB 'git switch main; git cherry-pick abc'
t 0 repoB 'git rebase origin/main'
t 0 repoB 'git rebase --onto main a b'
t 2 repoB 'git rebase feat main'
t 2 repoB 'cd ../repoA && git commit -m x'
t 2 repoB 'git -C ../repoA commit -m x'
t 0 repoA 'git -C ../repoB commit -m x'
t 0 repoB 'bash -c "git commit -m x"'
t 2 repoB 'bash -c "git push origin main"'
t 2 repoB 'git fetch origin feat:main'
t 0 repoB 'git fetch origin main:main'
t 2 repoA 'git branch -m feat'
t 2 repoB 'git branch -D main'
t 0 repoB 'git branch -D old'
t 2 repoB 'git checkout -B main origin/feat'
t 0 repoA 'git checkout -b feat2 && git commit -m x'
t 2 repoA 'git merge --abort'
t 2 repoA 'git reset'
t 2 repoA 'git reset --soft HEAD~1'
t 0 repoA 'git status && git log --oneline -5 2>&1 | head'
t 0 repoB 'echo "git push origin main"'
t 0 norepo 'git commit -m x'
t 2 repoA 'FOO=1 git commit -m x'
t 2 repoA 'env GIT_X=1 git merge feat'
t 0 repoB "git commit -m \"\$(cat <<'EOF'
fix
git push origin main
EOF
)\""
t 0 repoB "git commit -q -F - <<'EOF'
Guard main
  branch); on other branches; gh checks
git push origin main
EOF
git log --oneline -2"
t 0 repoB "cat <<EOF > notes.txt
git push origin main
EOF"
t 2 repoB "bash <<'EOF'
git push origin main
EOF"
t 2 repoB "git log -1 && sh -s <<-EOF
	gh pr merge 1
	EOF"

# --- git на main: білий список
t 0 repoA 'git log --oneline -5'
t 0 repoA 'git show HEAD'
t 0 repoA 'git diff main...feat'
t 0 repoA 'git branch'
t 0 repoA 'git branch -a'
t 0 repoA 'git tag -l'
t 0 repoA 'git remote -v'
t 0 repoA 'git stash list'
t 0 repoA 'git config --get user.name'
t 0 repoA 'git switch -c feat3'
t 0 repoA 'git --version'
t 2 repoA 'git add .'
t 2 repoA 'git stash'
t 2 repoA 'git checkout -- README.md'
t 2 repoA 'git checkout README.md'
t 2 repoA 'git restore README.md'
t 2 repoA 'git filter-branch --tree-filter x'
t 2 repoA 'git tag v1'
t 2 repoA 'git remote add up https://x'
t 2 repoA 'git config user.name x'
t 2 repoA 'git branch -D feat'
t 2 repoA 'git notes add -m x'
t 2 repoA 'git gc'

# --- git на інших гілках: можна все, крім змін main
t 0 repoB 'git add . && git stash && git stash pop'
t 0 repoB 'git reset --hard HEAD~1'
t 0 repoB 'git merge main'
t 0 repoB 'git filter-branch --tree-filter x HEAD'
t 2 repoB 'git filter-branch --tree-filter x -- --all'
t 2 repoB 'git push . feat:main'
t 2 repoB 'git fetch . feat:main'

# --- gh: дозволено
t 0 repoB 'gh pr create --base main --title x --body y'
t 0 repoB 'gh pr view 1 --comments'
t 0 repoB 'gh pr list && gh pr checks 1'
t 0 repoB 'gh pr checkout 3'
t 0 repoB 'gh issue create -t x -b y'
t 0 repoB 'gh run list'
t 0 repoB 'gh workflow run deploy.yml -f env=prod'
t 0 repoB 'gh run rerun 123'
t 0 repoB 'gh api repos/o/r/actions/workflows/deploy.yml/dispatches -f ref=main'
t 0 repoB 'gh release create v1 --target main'
t 0 repoB 'gh --version'
t 0 repoB 'gh api repos/o/r/pulls'
t 0 repoB 'gh api repos/o/r/contents/README.md'
t 0 repoB 'gh api -X GET search/issues -f q=x'
t 0 repoB 'gh api repos/o/r/issues/1/comments -f body=hi'
t 0 repoB 'gh api repos/o/r/contents/a.txt -X PUT -f message=m -f content=x -f branch=feat'
t 0 repoB 'gh api repos/o/r/merges -f base=feat -f head=main'
t 0 repoB 'gh api repos/o/r/git/refs -f ref=refs/heads/feat2 -f sha=abc'
t 0 repoB "gh api graphql -f query='query { viewer { login } }'"
t 0 repoB "gh api graphql -f query='mutation { addComment(input:{}) { clientMutationId } }'"
t 0 repoB 'gh repo edit --description x'
t 0 repoB 'gh repo sync'
t 0 repoB 'gh repo sync --branch feat'

# --- gh: заборонено
t 2 repoB 'gh pr merge 1 --rebase'
t 2 repoB 'gh pr merge --auto 1'
t 2 repoB 'gh pr -R o/r merge 1'
t 2 repoB 'cd .. && gh pr merge 1'
t 2 repoB 'bash -c "gh pr merge 1"'
t 2 repoB 'gh api -X PUT repos/o/r/pulls/1/merge'
t 2 repoB 'gh api --method=PUT /repos/o/r/pulls/2/merge'
t 2 repoB 'gh api -XPUT repos/o/r/pulls/2/merge'
t 2 repoB 'gh api https://api.github.com/repos/o/r/pulls/2/merge -X PUT'
t 2 repoB 'gh api repos/o/r/merges -f base=main -f head=feat'
t 2 repoB 'gh api repos/o/r/merge-upstream -f branch=main'
t 2 repoB 'gh api repos/o/r/contents/a.txt -X PUT -f message=m -f content=x'
t 2 repoB 'gh api repos/o/r/contents/a.txt -X PUT -f message=m -f content=x -f branch=main'
t 2 repoB 'gh api -X DELETE repos/o/r/contents/a.txt -F branch=master'
t 2 repoB 'gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc'
t 2 repoB 'gh api repos/o/r/git/refs -f ref=refs/heads/main -f sha=abc'
t 2 repoB 'gh api -X DELETE repos/o/r/branches/main/protection'
t 2 repoB 'gh api repos/o/r/branches/feat/rename -f new_name=main'
t 2 repoB 'gh api -X DELETE repos/o/r/rulesets/5'
t 2 repoB 'gh api -X POST repos/o/r/rulesets --input r.json'
t 2 repoB 'gh api repos/o/r/contents/x -X PUT --input body.json'
t 2 repoB 'gh api -X PATCH repos/o/r -f default_branch=dev'
t 2 repoB 'gh api -X PATCH repos/o/r -F allow_merge_commit=true'
t 2 repoB 'gh api -X DELETE repos/o/r'
t 2 repoB "gh api graphql -f query='mutation { mergePullRequest(input:{pullRequestId:\"x\"}) { clientMutationId } }'"
t 2 repoB "gh api graphql -f query='mutation(\$i: CreateCommitOnBranchInput!) { createCommitOnBranch(input: \$i) { commit { oid } } }'"
t 2 repoB 'gh api graphql -F query=@q.graphql'
t 2 repoB 'gh repo edit --default-branch dev'
t 2 repoB 'gh repo edit --enable-merge-commit'
t 2 repoB 'gh repo edit --enable-squash-merge=false'
t 2 repoB 'gh repo delete o/r --yes'
t 2 repoB 'gh repo sync o/r'
t 2 repoB 'gh repo sync --force'
t 2 repoB 'gh repo sync --source other/r'
t 2 repoB "gh alias set m 'pr merge'"
t 2 repoB 'gh extension install x/gh-y'
t 2 repoB 'gh m 1'

# --- не-Bash інструменти хук не чіпає
other 0 Read '{"file_path":"/x"}'
other 0 mcp__gitlab__manage_merge_request '{"action":"merge","project_id":"1"}'

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
