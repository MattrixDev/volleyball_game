#!/usr/bin/env python3
"""Stellen zum Filmen aus den Ballkontakten einer Pruefung (statt aus Fehlern):
python3 tools/lab/contacts.py audit.json shots.json art1,art2,... [vorher=40] [nachher=80] [max_takt]
Art = Kontaktart (bump, set, spike, block, serve) oder anim (dig, pass, attack). Je Art die erste Stelle."""
import json, sys
d = json.load(open(sys.argv[1]))
kinds = sys.argv[3].split(",")
pre = int(sys.argv[4]) if len(sys.argv) > 4 else 40
post = int(sys.argv[5]) if len(sys.argv) > 5 else 80
maxf = int(sys.argv[6]) if len(sys.argv) > 6 else 10**9
out = []
for k in kinds:
    for c in d["contacts"]:
        if (c["kind"] == k or c["anim"] == k) and c["tick"] > 300 and c["tick"] < maxf and all(abs(c["tick"] - o["peak_f"]) > pre + post for o in out):
            p = c["player"]
            out.append({"f0": c["tick"] - pre, "f1": c["tick"] + post, "team": 0 if p[0] == "A" else 1, "num": int(p[1:]),
                        "label": f"{c['kind']} {c['anim']}", "peak_f": c["tick"], "ctx": ""})
            break
out.sort(key=lambda s: s["f0"])
json.dump(out, open(sys.argv[2], "w"), indent=1)
for s in out:
    print(s["label"], s["peak_f"], "AB"[s["team"]] + str(s["num"]))
