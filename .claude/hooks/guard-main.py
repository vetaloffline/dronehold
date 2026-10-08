#!/usr/bin/env python3
"""PreToolUse-хук: main|master — тільки читання, pull і fetch; зміни — через гілку й PR.

Bash, на main|master: білий список — команди читання, pull, fetch, перехід на
іншу гілку; усе інше заборонено.
Bash, на інших гілках: дозволено все, крім змін main|master — push у main|master,
fetch/pull, що підміняють main|master, rebase/checkout -B/branch/update-ref/
filter-branch, що переписують main|master.
Bash, gh: дозволено все, крім змін main|master — pr merge, мерж/коміт/ref/захист
main через gh api (REST і GraphQL), зміни default branch і налаштувань мержу,
repo delete, віддалений repo sync; alias/extension і невідомі підкоманди
заборонені, бо через них не видно, що виконається.

Код виходу 2 = заборона (причина в stderr), 0 = звичайний потік дозволів.
Не межа безпеки: скрипти, alias і бектики не розбираються. Гарантію дає
захист гілки на сервері.
"""
import json
import os
import re
import shlex
import subprocess
import sys

PROTECTED = {"main", "master"}
SEPARATORS = {"&&", "||", ";", ";;", "|", "|&", "&", "(", ")"}
WRAPPERS = {"env", "command", "builtin", "nohup", "time", "exec", "nice"}
SHELLS = {"sh", "bash", "zsh"}
READ_ONLY = {
    "status", "log", "diff", "show", "blame", "annotate", "grep", "ls-files", "ls-tree", "ls-remote",
    "rev-parse", "rev-list", "describe", "shortlog", "cat-file", "show-ref", "for-each-ref", "merge-base",
    "name-rev", "whatchanged", "check-ignore", "check-attr", "count-objects", "var", "archive", "help",
    "version", "fetch", "pull",
}
GH_COMMANDS = {
    "auth", "browse", "codespace", "cs", "discussion", "gist", "issue", "org", "pr", "project", "release",
    "repo", "skill", "cache", "run", "workflow", "agent-task", "alias", "api", "attestation", "completion",
    "config", "copilot", "extension", "ext", "extensions", "gpg-key", "label", "licenses", "preview",
    "ruleset", "rs", "search", "secret", "ssh-key", "status", "variable", "help", "version",
}
GH_API_VALUE_FLAGS = {"-X", "--method", "-f", "--raw-field", "-F", "--field", "-H", "--header", "--input",
                      "-q", "--jq", "-t", "--template", "-p", "--preview", "--hostname", "--cache"}
GH_MERGE_SETTINGS = {"--default-branch", "--enable-merge-commit", "--enable-rebase-merge",
                     "--enable-squash-merge", "--enable-auto-merge"}
REPO_MERGE_FIELDS = {"default_branch", "allow_merge_commit", "allow_squash_merge", "allow_rebase_merge",
                     "allow_auto_merge"}
# Гілку в цих мутаціях видно лише у змінних, тому вони заборонені повністю.
GRAPHQL_MAIN_MUTATIONS = (
    "mergePullRequest", "enablePullRequestAutoMerge", "enqueuePullRequest", "mergeBranch",
    "createCommitOnBranch", "createRef", "updateRef", "updateRefs", "deleteRef",
    "createBranchProtectionRule", "updateBranchProtectionRule", "deleteBranchProtectionRule",
    "createRepositoryRuleset", "updateRepositoryRuleset", "deleteRepositoryRuleset",
)
NEW_BRANCH_FLAGS = {"-b", "-B", "-c", "-C", "--orphan"}
BRANCH_REWRITE_FLAGS = {"-f", "--force", "-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy"}


def deny(reason):
    print(f"guard-main: {reason}. У main/master — тільки pull/fetch; працюй у гілці, у main — через PR.",
          file=sys.stderr)
    sys.exit(2)


def git(path, *args):
    try:
        out = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def current_branch(path):
    return git(path, "branch", "--show-current") or ""


def ref_name(ref):
    ref = ref.lstrip("+")
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


def positionals(args, takes_value=()):
    """Позиційні аргументи до `--`; пропускає прапорці й значення прапорців з takes_value."""
    out, skip = [], False
    for a in args:
        if skip:
            skip = False
            continue
        if a == "--":
            break
        if a.startswith("-"):
            skip = a in takes_value
            continue
        out.append(a)
    return out


def check_refspecs(refspecs, why):
    """fetch/pull: refspec src:main дозволений, лише якщо src — той самий main (синхронізація)."""
    for r in refspecs:
        if ":" not in r:
            continue
        src, dest = r.split(":", 1)
        if ref_name(dest) in PROTECTED and (r.startswith("+") or ref_name(src).split("/")[-1] != ref_name(dest)):
            deny(f"{why} {r} підміняє головну гілку")


def resolve_checkout_target(rest, here):
    """Гілка, на якій опиниться checkout/switch; None — гілка не змінюється."""
    for i, a in enumerate(rest):
        if a in NEW_BRANCH_FLAGS and i + 1 < len(rest):
            if rest[i + 1] in PROTECTED:
                deny(f"checkout {a} {rest[i + 1]} перезаписує головну гілку")
            return rest[i + 1]
    if "--detach" in rest or "-d" in rest:
        return ""
    if "--" in rest:
        return None
    if "-" in rest:
        prev = git(here, "rev-parse", "--symbolic-full-name", "@{-1}")
        return ref_name(prev) if prev else None
    pos = positionals(rest, {"--conflict"})
    if not pos:
        return None
    if pos[0] in PROTECTED or git(here, "rev-parse", "--verify", "--quiet", f"refs/heads/{pos[0]}") is not None:
        return pos[0]
    return None


def allowed_on_protected(sub, rest):
    """Білий список для main|master: тільки читання, pull і fetch."""
    if sub in READ_ONLY:
        return True
    if sub == "branch":
        return not (set(rest) & BRANCH_REWRITE_FLAGS)
    if sub == "tag":
        return not positionals(rest) or bool({"-l", "--list"} & set(rest))
    if sub == "remote":
        return not rest or rest[0] in ("-v", "--verbose", "show", "get-url")
    if sub == "stash":
        return bool(rest) and rest[0] in ("list", "show")
    if sub == "reflog":
        return not rest or rest[0] not in ("expire", "delete")
    if sub == "config":
        return bool({"--get", "--get-all", "--get-regexp", "--list", "-l"} & set(rest)) \
            or (bool(rest) and rest[0] in ("get", "list"))
    if sub == "worktree":
        return bool(rest) and rest[0] == "list"
    return False


def check_git(args, dir_, branch):
    """Перевіряє одну git-команду; повертає гілку для dir_ після неї."""
    here, here_branch, i = dir_, branch, 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] == "-C" and i + 1 < len(args):
            here = os.path.normpath(os.path.join(here, os.path.expanduser(args[i + 1])))
            here_branch = current_branch(here)
            i += 2
        elif args[i] in ("-c", "--git-dir", "--work-tree", "--namespace") and i + 1 < len(args):
            i += 2
        else:
            i += 1
    if i >= len(args):
        return branch
    sub, rest = args[i], args[i + 1:]
    new_branch = None

    if sub in ("checkout", "switch"):
        new_branch = resolve_checkout_target(rest, here)
        if here_branch in PROTECTED and new_branch is None:
            deny(f"git {sub} файлів на {here_branch} змінює робочу копію")

    elif here_branch in PROTECTED and not allowed_on_protected(sub, rest):
        deny(f"git {sub} на {here_branch}")

    elif sub in ("filter-branch", "filter-repo"):
        if "--all" in rest or any(ref_name(p) in PROTECTED for p in rest):
            deny(f"git {sub} переписує головну гілку")

    elif sub == "rebase":
        pos = positionals(rest, {"--onto", "-s", "--strategy", "-X", "--strategy-option", "-x", "--exec"})
        if len(pos) >= 2:
            if ref_name(pos[1]) in PROTECTED:
                deny(f"git rebase {pos[0]} {pos[1]} переписує головну гілку")
            new_branch = pos[1]

    elif sub == "push":
        if {"--all", "--mirror", "--branches"} & set(rest):
            deny("git push --all/--mirror зачіпає головну гілку")
        refspecs = positionals(rest, {"-o", "--push-option", "--repo", "--receive-pack", "--exec"})[1:]
        if not refspecs and here_branch in PROTECTED:
            deny(f"git push з {here_branch}")
        for r in refspecs:
            dest = r.split(":", 1)[1] if ":" in r else r
            if ref_name(dest) in PROTECTED or (dest in ("HEAD", "@") and here_branch in PROTECTED):
                deny(f"git push {r} у головну гілку")

    elif sub == "fetch":
        check_refspecs(positionals(rest, {"--depth", "-j", "--jobs", "-o", "--server-option"})[1:], "git fetch")

    elif sub == "pull":
        refspecs = positionals(rest, {"-s", "--strategy", "-X", "--strategy-option", "--depth", "-o"})[1:]
        check_refspecs(refspecs, "git pull")
        if here_branch in PROTECTED:
            for r in refspecs:
                if ref_name(r.split(":", 1)[0]).split("/")[-1] != here_branch:
                    deny(f"git pull {r} у {here_branch} — це мерж чужої гілки")

    elif sub == "branch" and set(rest) & BRANCH_REWRITE_FLAGS:
        if here_branch in PROTECTED and set(rest) & {"-m", "-M", "--move"}:
            deny(f"перейменування {here_branch}")
        if any(ref_name(p) in PROTECTED for p in positionals(rest, {"-u", "--set-upstream-to"})):
            deny("видалення/перезапис/перейменування головної гілки")

    elif sub == "update-ref":
        if any(ref_name(p) in PROTECTED for p in positionals(rest, {"-m"})):
            deny("git update-ref головної гілки")

    if new_branch is None or here != dir_:
        return branch
    return new_branch


def gh_api_request(args):
    """Розбирає аргументи gh api: (метод, endpoint, поля, чи є --input)."""
    method, endpoint, fields, has_input, i = None, None, {}, False, 0
    while i < len(args):
        a = args[i]
        if a.startswith("--") and "=" in a:
            flag, value = a.split("=", 1)
        elif a.startswith("-X") and len(a) > 2:
            flag, value = "-X", a[2:]
        elif a in GH_API_VALUE_FLAGS and i + 1 < len(args):
            flag, value = a, args[i + 1]
            i += 1
        elif a.startswith("-"):
            flag, value = a, None
        else:
            endpoint = endpoint or a
            i += 1
            continue
        if flag in ("-X", "--method"):
            method = value.upper()
        elif flag in ("-f", "--raw-field", "-F", "--field") and value is not None:
            key, _, val = value.partition("=")
            fields[key] = val
        elif flag == "--input":
            has_input = True
        i += 1
    # gh api: GET за замовчуванням, POST — коли є поля чи --input.
    method = method or ("POST" if fields or has_input else "GET")
    endpoint = re.sub(r"^https?://[^/]+/", "", endpoint or "").split("?")[0].strip("/")
    return method, endpoint, fields, has_input


def check_gh_api(args):
    method, ep, fields, has_input = gh_api_request(args)
    if method in ("GET", "HEAD"):
        return
    if has_input:
        deny("gh api --input: тіло запиту з файлу не перевірити")
    if ep == "graphql":
        query = fields.get("query", "")
        if query.startswith("@"):
            deny("gh api graphql із запитом з файлу не перевірити")
        hit = next((m for m in GRAPHQL_MAIN_MUTATIONS if re.search(rf"\b{m}\b", query)), None)
        if hit:
            deny(f"GraphQL-мутація {hit} може змінити головну гілку")
        return
    prot = "(main|master)"
    if re.search(r"(^|/)pulls/[^/]+/merge$", ep):
        deny("мерж PR через gh api")
    if re.search(r"(^|/)merges$", ep) and ref_name(fields.get("base", "main")) in PROTECTED:
        deny("мерж у головну гілку через gh api")
    if re.search(r"(^|/)merge-upstream$", ep) and ref_name(fields.get("branch", "main")) in PROTECTED:
        deny("синхронізація головної гілки з upstream через gh api")
    if re.search(r"(^|/)contents(/|$)", ep) and ref_name(fields.get("branch", "")) in PROTECTED | {""}:
        deny("запис файлу в головну гілку через gh api (без branch — це default branch)")
    if re.search(rf"(^|/)git/refs/heads/{prot}$", ep) or (
            re.search(r"(^|/)git/refs$", ep) and ref_name(fields.get("ref", "")) in PROTECTED):
        deny("зміна ref головної гілки через gh api")
    if re.search(rf"(^|/)branches/{prot}(/|$)", ep):
        deny("перейменування чи зміна захисту головної гілки через gh api")
    if re.search(r"(^|/)branches/[^/]+/rename$", ep) and fields.get("new_name") in PROTECTED:
        deny("перейменування гілки в головну через gh api")
    if re.search(r"(^|/)rulesets(/|$)", ep):
        deny("зміна rulesets через gh api")
    if re.fullmatch(r"repos/[^/]+/[^/]+", ep) and (method == "DELETE" or REPO_MERGE_FIELDS & set(fields)):
        deny("видалення репо чи зміна default branch/налаштувань мержу через gh api")


def check_gh(args):
    if not args or args[0].startswith("-"):
        return
    sub, rest = args[0], args[1:]
    if sub not in GH_COMMANDS:
        deny(f"gh {sub}: невідома підкоманда (alias чи extension) — не видно, що виконається")
    action = next(iter(positionals(rest, {"-R", "--repo"})), "")
    if sub == "pr" and action == "merge":
        deny("gh pr merge — PR мержиш ти")
    elif sub == "alias" and action in ("set", "import"):
        deny("gh alias дозволяє обійти заборони")
    elif sub in ("extension", "ext", "extensions") and action in ("install", "upgrade", "exec"):
        deny(f"gh extension {action} — сторонній код поза перевірками")
    elif sub == "repo" and action == "delete":
        deny("gh repo delete знищує головну гілку разом з репо")
    elif sub == "repo" and action == "edit" and any(a.split("=", 1)[0] in GH_MERGE_SETTINGS for a in rest):
        deny("зміна default branch чи налаштувань мержу")
    elif sub == "repo" and action == "sync":
        sync_args = rest[rest.index("sync") + 1:]
        if {"--force", "-s", "--source"} & set(sync_args) or positionals(sync_args, {"-b", "--branch"}):
            deny("gh repo sync віддаленого репо, з іншого джерела чи з --force")
    elif sub == "api":
        check_gh_api(rest)


HEREDOC = re.compile(
    r"([^\n]*?)<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2([^\n]*)\n(.*?)\n[ \t]*\3[ \t]*(?=\n|$)", re.S)


def split_heredocs(command):
    """Прибирає тіла heredoc (це дані, а не команди); тіла, що йдуть у shell, повертає окремо."""
    shell_bodies = []

    def repl(m):
        prefix, rest, body = m.group(1), m.group(4), m.group(5)
        if re.search(r"(^|[\s;&|(])(ba|z)?sh(\s+-s)?\s*$", prefix):
            shell_bodies.append(body)
        return prefix + rest

    return HEREDOC.sub(repl, command), shell_bodies


def strip_prefix(seg):
    while seg and (seg[0] in WRAPPERS or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", seg[0])):
        seg = seg[1:]
    return seg


def check_bash(command, cwd):
    command, shell_bodies = split_heredocs(command)
    for body in shell_bodies:
        check_bash(body, cwd)
    try:
        lex = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        if re.search(r"\bgit\b", command) and (current_branch(cwd) in PROTECTED
                                                or re.search(r"\b(main|master)\b", command)):
            deny("не вдалося розібрати команду з git")
        return

    segments, seg, skip = [], [], False
    for t in tokens:
        if skip:
            skip = False
        elif t in SEPARATORS:
            segments.append(seg)
            seg = []
        elif set(t) <= set("<>&"):
            skip = True  # редирект і його ціль
        else:
            seg.append(t)
    segments.append(seg)

    dir_, branch = cwd, current_branch(cwd)
    for seg in segments:
        seg = strip_prefix(seg)
        if not seg:
            continue
        prog = os.path.basename(seg[0])
        if prog == "cd":
            target = os.path.expanduser(seg[1] if len(seg) > 1 else "~")
            dir_ = os.path.normpath(os.path.join(dir_, target))
            branch = current_branch(dir_)
        elif prog in SHELLS and "-c" in seg[:-1]:
            check_bash(seg[seg.index("-c") + 1], dir_)
        elif prog == "git":
            branch = check_git(seg[1:], dir_, branch)
        elif prog == "gh":
            check_gh(seg[1:])


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    if data.get("tool_name") == "Bash":
        command = (data.get("tool_input") or {}).get("command", "")
        check_bash(command, data.get("cwd") or os.getcwd())


if __name__ == "__main__":
    main()
