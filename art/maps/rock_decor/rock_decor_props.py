#!/usr/bin/env python3
"""Cut the rock decor sheet into props for the game (art/maps/props) and register them in props.json.

The sheet (rock_decor_sheet.png, Codex, 10 pieces in the order of rock_decor_template.py) is cut by
../cliffs/cliff_sheet_cut.py (connected pieces, ground point measured at the foot), each piece saved as
art/maps/props/prop_<kind>.png, and props.json gets one entry per kind (replaced if it is there):
  name, file, foot (old 64x48 cells, rounded up — for old tools), foot_cells (exact, 32x24 — Prop reads it),
  ground (px in the PNG), body_w (= foot_cells.x * 32 * texels: Prop draws it at 1/texels, as Codex drew it),
  size.
Exit 0 ok, 1 cut failed, 2 bad args.

Example: python3 rock_decor_props.py
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROPS = os.path.abspath(os.path.join(HERE, "..", "props"))
CUT = os.path.abspath(os.path.join(HERE, "..", "cliffs", "cliff_sheet_cut.py"))
# Template order → prop kind.
KINDS = ["cliff_spire", "cliff_twin_spires", "cliff_crest", "cliff_rockfall", "cliff_slab",
         "cliff_split", "cliff_scree", "cliff_ledge", "cliff_arch", "cliff_fallen_pillar"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheet", default=os.path.join(HERE, "rock_decor_sheet.png"), help="Codex sheet (default: rock_decor_sheet.png here)")
    ap.add_argument("--props", default=PROPS, help="props folder with props.json (default: art/maps/props)")
    a = ap.parse_args()
    if not os.path.isfile(a.sheet) or not os.path.isfile(os.path.join(a.props, "props.json")):
        print("no sheet or props.json", file=sys.stderr)
        return 2
    tpl = json.load(open(os.path.join(HERE, "rock_decor_cut_template.json")))
    with tempfile.TemporaryDirectory() as tmp:
        r = subprocess.run([sys.executable, CUT, a.sheet, "-t", os.path.join(HERE, "rock_decor_cut_template.json"),
                            "-o", tmp, "-p", "piece"])
        if r.returncode != 0:
            return 1
        meta = json.load(open(os.path.join(tmp, "piece.json")))
        texels = meta["texels_per_map_px"]
        entries = []
        for i, b in enumerate(meta["blocks"]):
            kind = KINDS[i]
            fw, fh = tpl["blocks"][i]["foot_cells"]
            shutil.copy(os.path.join(tmp, b["file"]), os.path.join(a.props, f"prop_{kind}.png"))
            entries.append({"name": kind, "file": f"prop_{kind}.png", "foot": [math.ceil(fw / 2), math.ceil(fh / 2)],
                            "foot_cells": [fw, fh], "ground": b["ground"], "body_w": round(fw * 32 * texels, 2),
                            "size": b["size"]})
    pj = os.path.join(a.props, "props.json")
    data = [p for p in json.load(open(pj)) if p.get("name") not in KINDS] + entries
    with open(pj, "w") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"{len(entries)} props -> {a.props}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
