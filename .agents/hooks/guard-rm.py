#!/usr/bin/env python3
"""PreToolUse-хук на видалення: чернетки — без питань, решта — тільки з дозволу людини.

Кожна підкоманда `rm` (з -r чи без), `unlink`, `find … -delete` / `find … -exec rm` (шляхи find — як
rm -r) у Bash-команді, також за `sudo`/`doas`; шлях рахується від cwd з урахуванням `cd`:
  - усі шляхи строго всередині <репо>/art/drafts/          → пропустити (без питань);
  - хоч один шлях поза art/drafts/ або його не видно ($, бектики, `cd $X`, `xargs rm`)
                                                           → «ask»: Claude Code питає людину;
  - рекурсивний rm на /, ~, корінь репо чи вище, саму art/drafts
                                                           → заборона (exit 2), навіть з дозволом.
Кінцевий компонент шляху не розкривається (rm видаляє посилання, а не те, на що воно вказує),
батьківська папка — через realpath. Шаблон (*, ?, [) — дивиться папку до шаблону.
`bash -c '…'` і heredoc у shell розбираються, як у guard-main.py (той самий розбір команди).

Замінює правила `rm` у .claude/settings.json (deny `rm -rf *` і ask `rm *`): ті матчили лише текст
команди. Рішення людини 2026-10-14: чистка чернеток — без апруву, будь-яке інше видалення — з апрувом.
Не межа безпеки: скрипти, alias, `perl -e unlink`, `python -c`, `mv` у кошик не розбираються.

Вихід: 2 = заборона (причина в stderr); 0 + JSON permissionDecision "ask" = спитати людину;
0 без виводу = звичайний потік дозволів.
"""
import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
sys.dont_write_bytecode = True  # без __pycache__ у .agents/hooks
_spec = importlib.util.spec_from_file_location("guard_main", os.path.join(HERE, "guard-main.py"))
_gm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gm)

GLOB = re.compile(r"[*?\[]")
# Обгортки, за якими може стояти rm (guard-main.WRAPPERS їх не знає): sudo/doas — повноваження.
EXTRA_WRAPPERS = {"sudo", "doas", "xcrun"}
# Перший вираз find (-name, !, дужки) — кінець списку шляхів.
FIND_PATH_END = re.compile(r"^(-|!|\(|\))")
DRAFTS, ASK, DENY = "drafts", "ask", "deny"


def project_root(cwd):
    root = os.environ.get("CLAUDE_PROJECT_DIR")
    if root:
        return os.path.realpath(root)
    try:
        out = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        if out.returncode == 0:
            return os.path.realpath(out.stdout.strip())
    except OSError:
        pass
    return None


def is_recursive(args):
    for a in args:
        if a == "--":
            break
        if a == "--recursive":
            return True
        if a.startswith("-") and not a.startswith("--") and ("r" in a or "R" in a):
            return True
    return False


def paths_of(args):
    out, opts = [], True
    for a in args:
        if opts and a == "--":
            opts = False
        elif opts and a.startswith("-") and a != "-":
            continue
        else:
            out.append(a)
    return out


class Guard:
    def __init__(self, root):
        self.root = root
        self.drafts = os.path.realpath(os.path.join(root, "art", "drafts")) if root else None
        self.home = os.path.realpath(os.path.expanduser("~"))
        self.verdict = DRAFTS
        self.reasons = []

    def note(self, verdict, reason):
        order = {DRAFTS: 0, ASK: 1, DENY: 2}
        if order[verdict] > order[self.verdict]:
            self.verdict = verdict
        self.reasons.append(reason)

    def dangerous(self, target):
        """Рекурсивно видаляти не можна навіть з дозволом: /, ~, корінь репо чи вище, сама art/drafts."""
        if target in ("/", self.home) or target == self.drafts:
            return True
        if self.root and (target == self.root or self.root.startswith(target.rstrip(os.sep) + os.sep)):
            return True
        return False

    def classify(self, path, dir_, recursive, drafts_ok=False):
        """drafts_ok: сама art/drafts теж «всередині» (корінь find: видаляє лише знахідки під ним)."""
        if "$" in path or "`" in path or dir_ is None:
            self.note(ASK, f"шлях «{path}» не видно до запуску")
            return
        full = os.path.normpath(os.path.join(dir_, os.path.expanduser(path)))
        m = GLOB.search(full)
        if m:
            base = full[:m.start()]
            parent = os.path.realpath(base if base.endswith(os.sep) else os.path.dirname(base) or "/")
            if self.drafts and (parent == self.drafts or parent.startswith(self.drafts + os.sep)):
                return
            if recursive and self.dangerous(parent):
                self.note(DENY, f"«{path}» — шаблон у {parent}")
            else:
                self.note(ASK, f"«{path}» поза art/drafts/")
            return
        name = os.path.basename(full)
        parent = os.path.realpath(os.path.dirname(full) or "/")
        target = os.path.realpath(full) if name in ("", ".", "..") else os.path.join(parent, name)
        if self.drafts and (target.startswith(self.drafts + os.sep) or (drafts_ok and target == self.drafts)):
            return
        if recursive and self.dangerous(target):
            self.note(DENY, f"«{path}» = {target}")
        else:
            self.note(ASK, f"«{path}» поза art/drafts/")

    def check_bash(self, command, cwd):
        command, shell_bodies = _gm.split_heredocs(command)
        for body in shell_bodies:
            self.check_bash(body, cwd)
        try:
            lex = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=True)
            lex.whitespace_split = True
            tokens = list(lex)
        except ValueError:
            self.note(ASK, "не вдалося розібрати команду з rm")
            return

        segments, seg, skip = [], [], False
        for t in tokens:
            if skip:
                skip = False
            elif t in _gm.SEPARATORS:
                segments.append(seg)
                seg = []
            elif set(t) <= set("<>&"):
                skip = True
                # `2>/dev/null`: дескриптор перед редиректом — не аргумент команди.
                if seg and seg[-1].isdigit():
                    seg.pop()
            else:
                seg.append(t)
        segments.append(seg)

        dir_ = cwd
        for seg in segments:
            seg = _gm.strip_prefix(seg)
            if seg and os.path.basename(seg[0]) in EXTRA_WRAPPERS:
                # sudo -u user rm …: опції обгортки мають значення — шукаємо саму команду видалення.
                names = [os.path.basename(a) for a in seg]
                hit = next((i for i, n in enumerate(names) if i > 0 and n in ("rm", "unlink", "find", "xargs")), None)
                seg = _gm.strip_prefix(seg[hit:]) if hit is not None else []
            if not seg:
                continue
            prog = os.path.basename(seg[0])
            if prog == "cd":
                target = seg[1] if len(seg) > 1 else "~"
                if "$" in target or "`" in target or dir_ is None:
                    dir_ = None
                else:
                    dir_ = os.path.normpath(os.path.join(dir_, os.path.expanduser(target)))
            elif prog in _gm.SHELLS and "-c" in seg[:-1]:
                self.check_bash(seg[seg.index("-c") + 1], dir_ or cwd)
            elif prog == "xargs" and "rm" in [os.path.basename(a) for a in seg[1:]]:
                self.note(ASK, "xargs … rm: шляхів не видно")
            elif prog in ("rm", "unlink"):
                if self.drafts is None:
                    self.note(ASK, "не знайшов корінь проєкту")
                    continue
                rec = prog == "rm" and is_recursive(seg[1:])
                for p in paths_of(seg[1:]):
                    self.classify(p, dir_, rec)
            elif prog == "find" and ("-delete" in seg or any(
                    a in ("-exec", "-execdir", "-ok", "-okdir") and i + 1 < len(seg)
                    and os.path.basename(seg[i + 1]) in ("rm", "unlink") for i, a in enumerate(seg))):
                # find видаляє все під своїми шляхами (до першого виразу): ті шляхи — як у rm -r.
                if self.drafts is None:
                    self.note(ASK, "не знайшов корінь проєкту")
                    continue
                roots = []
                for a in seg[1:]:
                    if FIND_PATH_END.match(a):
                        break
                    roots.append(a)
                for p in roots or ["."]:
                    self.classify(p, dir_, True, drafts_ok=True)


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return
    if data.get("tool_name") != "Bash":
        return
    command = (data.get("tool_input") or {}).get("command", "")
    if not re.search(r"\b(rm|unlink|find)\b", command):
        return
    cwd = data.get("cwd") or os.getcwd()
    g = Guard(project_root(cwd))
    g.check_bash(command, cwd)
    if g.verdict == DENY:
        print("guard-rm: " + "; ".join(r for r in g.reasons) +
              ". Рекурсивно видаляти /, ~, корінь репо чи саму art/drafts не можна.", file=sys.stderr)
        sys.exit(2)
    if g.verdict == ASK:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": "guard-rm: видалення поза art/drafts/ — потрібен дозвіл людини ("
                                        + "; ".join(g.reasons) + ")",
        }}, ensure_ascii=False))


if __name__ == "__main__":
    main()
