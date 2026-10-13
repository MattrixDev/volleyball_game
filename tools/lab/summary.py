#!/usr/bin/env python3
"""Zusammenfassung einer Labor-Pruefung: python3 tools/lab/summary.py audit.json"""
import json, sys, collections
d = json.load(open(sys.argv[1]))
ev = d["events"]
print(f"Takte {d['ticks']}  Ereignisse {len(ev)}  Kontakte {len(d['contacts'])}")
by = collections.defaultdict(list)
for e in ev:
    t = e["type"]
    for s in ("_l", "_r"):
        if t.endswith(s): t = t[:-2]
    by[t].append(e)
for t, es in sorted(by.items(), key=lambda kv: -len(kv[1])):
    anims = collections.Counter((e["anim"] or "-") + ("/" + e["joint"] if e.get("joint") else "") for e in es)
    peak = max(e["peak"] for e in es)
    dur = sum(e["f1"] - e["f0"] + 1 for e in es)
    print(f"{t:16s} n={len(es):4d}  Takte={dur:6d}  max={peak:.3f}  " + ", ".join(f"{k}:{v}" for k, v in anims.most_common(6)))
c = d["contacts"]
if c:
    print("\nKontakte (Abstand Koerper-Ball, m):")
    k = collections.defaultdict(list)
    for x in c: k[x["kind"] + "/" + x["anim"]].append(x["dist"])
    for kk, v in sorted(k.items()):
        v.sort()
        print(f"  {kk:18s} n={len(v):3d} median={v[len(v)//2]:.3f} max={v[-1]:.3f}")
