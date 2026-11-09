#!/usr/bin/env python3
"""Rewrite Ambxst's `import qs.<path>` lines into relative directory imports and
write a qmldir in every QML directory, so the tree loads as a plugin inside
omarchy-shell (where `qs.` resolves to Omarchy's own shell directory)."""
import os
import re
import sys

root = os.path.abspath(sys.argv[1])
# qs.* namespaces that belong to Omarchy's shell and must stay as-is.
KEEP = {"qs.Commons", "qs.Ui", "qs.services"}
IMPORT_RE = re.compile(r'^(\s*)import\s+(qs(?:\.[A-Za-z_][A-Za-z0-9_]*)+)(\s+as\s+[A-Za-z_][A-Za-z0-9_]*)?\s*;?\s*$')
changed = 0

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if not d.startswith(".")]
    for fn in filenames:
        if not fn.endswith(".qml"):
            continue
        path = os.path.join(dirpath, fn)
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        out = []
        dirty = False
        for line in lines:
            m = IMPORT_RE.match(line)
            if m and m.group(2) not in KEEP:
                target = os.path.join(root, *m.group(2).split(".")[1:])
                if not os.path.isdir(target):
                    sys.exit(f"{path}: no directory for {m.group(2)}")
                rel = os.path.relpath(target, dirpath)
                out.append(f'{m.group(1)}import "{rel}"{m.group(3) or ""}')
                dirty = True
            else:
                out.append(line)
        if dirty:
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n".join(out))
            changed += 1

qmldirs = 0
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if not d.startswith(".")]
    types = sorted(f for f in filenames if f.endswith(".qml") and f[0].isupper())
    if not types:
        continue
    entries = []
    for fn in types:
        with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
            head = f.read(4000)
        singleton = re.search(r"^\s*pragma\s+Singleton\b", head, re.M) is not None
        entries.append(("singleton " if singleton else "") + f"{fn[:-4]} 1.0 {fn}")
    with open(os.path.join(dirpath, "qmldir"), "w", encoding="utf-8") as f:
        f.write("\n".join(entries) + "\n")
    qmldirs += 1

print(f"rewrote {changed} files, wrote {qmldirs} qmldir files")
