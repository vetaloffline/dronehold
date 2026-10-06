#!/usr/bin/env python3
"""PreToolUse-хук: у головну гілку — тільки pull/fetch, решта через гілку й MR.

Bash: на main|master забороняє commit/merge/rebase/cherry-pick/revert/reset/am,
push у main|master з будь-якої гілки, fetch/pull, що підміняють main|master,
перейменування/видалення/перезапис main|master.
mcp__gitlab__*: забороняє merge/approve MR, коміти через API в main|master,
видалення main|master, зняття чи зміну захисту гілок, зміну default_branch.

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
ON_PROTECTED = {"commit", "merge", "rebase", "cherry-pick", "revert", "reset", "am"}
EXIT_FLAGS = {"--abort", "--quit", "--skip"}
NEW_BRANCH_FLAGS = {"-b", "-B", "-c", "-C", "--orphan"}
BRANCH_REWRITE_FLAGS = {"-f", "--force", "-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy"}


def deny(reason):
    print(f"guard-main: {reason}. У main/master — тільки pull/fetch; працюй у гілці, у main — через MR.",
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

    elif here_branch in PROTECTED and sub in ON_PROTECTED and not (set(rest) & EXIT_FLAGS):
        if not (sub == "reset" and (not rest or rest[0] == "--")):
            deny(f"git {sub} на {here_branch}")

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


def strip_prefix(seg):
    while seg and (seg[0] in WRAPPERS or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", seg[0])):
        seg = seg[1:]
    return seg


def check_bash(command, cwd):
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


def check_gitlab(tool, inp):
    name, action = tool.rsplit("__", 1)[-1], inp.get("action")
    if name == "manage_merge_request" and action in ("merge", "approve"):
        deny(f"MR {action} через MCP — це робиш ти, не Claude")
    if name == "manage_files" and ref_name(str(inp.get("branch") or "")) in PROTECTED:
        deny("коміт через API в головну гілку")
    if name == "manage_ref":
        if action in ("unprotect_branch", "update_branch_protection"):
            deny("зняття чи зміна захисту гілки")
        if action == "delete_branch" and ref_name(str(inp.get("branch") or "")) in PROTECTED:
            deny("видалення головної гілки")
    if name == "manage_project" and action == "update" and inp.get("default_branch"):
        deny("зміна default branch")


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    tool, inp = data.get("tool_name", ""), data.get("tool_input") or {}
    if tool == "Bash":
        check_bash(inp.get("command", ""), data.get("cwd") or os.getcwd())
    elif tool.startswith("mcp__gitlab__"):
        check_gitlab(tool, inp)


if __name__ == "__main__":
    main()
