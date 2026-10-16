#!/usr/bin/env python3
"""Waehlt die schlimmsten Stellen aus einer Labor-Pruefung zum Filmen.
python3 tools/lab/pick.py audit.json shots.json [anzahl=8] [nur_typ,typ2] [halbe_fensterbreite_takte=60]"""
import json, sys, collections
d = json.load(open(sys.argv[1]))
n = int(sys.argv[3]) if len(sys.argv) > 3 else 8
only = set(sys.argv[4].split(",")) if len(sys.argv) > 4 and sys.argv[4] not in ("", "-") else None
half = int(sys.argv[5]) if len(sys.argv) > 5 else 60
# Wie stark ein Wert ueber der Schwelle zaehlt (grob: sichtbare Groesse)
scale = {"floor_clip": 0.05, "float": 0.1, "foot_slide": 2.0, "pop": 0.6, "yaw_pop": 0.4, "teleport": 0.3,
         "knee_backward": 0.3, "knee_sideways": 0.5, "elbow_backward": 0.3, "elbow_sideways": 0.6,
         "arm_in_body": 0.05, "arms_cross": 0.04, "legs_cross": 0.06, "net_clip": 0.1, "overlap": 0.2, "contact_far": 0.3}
def base(t):
    return t[:-2] if t.endswith(("_l", "_r")) else t
ev = []
for e in d["events"]:
    b = base(e["type"])
    if only and b not in only and e["type"] not in only:
        continue
    dur = e["f1"] - e["f0"] + 1
    e["score"] = e["peak"] / scale.get(b, 1.0) * (1.0 + min(dur, 60) / 30.0)
    ev.append(e)
ev.sort(key=lambda e: -e["score"])
per = collections.Counter()
shots = []
for e in ev:
    b = base(e["type"])
    if per[b] >= max(2, n // 4) and not only:
        continue
    if e["player"].count("+"):
        team, num = (0 if e["player"][0] == "A" else 1), int(e["player"].split("+")[0][1:])
    else:
        team, num = e["team"], e["num"]
    f0, f1 = e["peak_f"] - half, e["peak_f"] + half
    if any(abs(s["f0"] - f0) < half and s["team"] == team and s["num"] == num for s in shots):
        continue
    per[b] += 1
    shots.append({"f0": f0, "f1": f1, "team": team, "num": num, "type": e["type"], "peak_f": e["peak_f"],
                  "label": f"{e['type']} {e['peak']:.2f} {e['anim'] or '-'} {e.get('joint','')}".strip(), "ctx": e.get("ctx", "")})
    if len(shots) >= n:
        break
# Fenster duerfen sich nicht ueberlappen (eine Kamera gleichzeitig)
shots.sort(key=lambda s: s["f0"])
out = []
for s in shots:
    if out and s["f0"] <= out[-1]["f1"]:
        s["f0"] = out[-1]["f1"] + 1
        if s["f1"] - s["f0"] < half:
            continue
    out.append(s)
json.dump(out, open(sys.argv[2], "w"), indent=1)
for i, s in enumerate(out):
    print(f"s{i:02d} Takt {s['f0']}-{s['f1']} {'AB'[s['team']]}{s['num']}: {s['label']} ({s['ctx']})")
