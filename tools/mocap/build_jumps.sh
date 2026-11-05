#!/usr/bin/env bash
# Alle CMU-Blockspruenge (mit erkanntem Absprung, Huefte mindestens 18 cm hoch) -> assets/models/mocap_jumps.json
# Aufruf: tools/mocap/build_jumps.sh <ordner mit cmu/01_block_sprung>
set -euo pipefail
cd "$(dirname "$0")/../.."
D=${1:-/mnt/project-files/bewegungsdaten/cmu}/01_block_sprung
args=()
for f in "$D"/*.bvh; do b=$(basename "$f" .bvh); args+=("j$b=$f"); done
python3 tools/mocap/cmu_to_clips.py /tmp/mocap_all.json --trim "${args[@]}"
python3 - <<'PY'
import json
d = json.load(open("/tmp/mocap_all.json"))
keep = {k: v for k, v in d.items() if v["ev"] and v["ev"]["rise"] >= 0.18 and v["ev"]["dip"] >= 0.1}
json.dump(keep, open("assets/models/mocap_jumps.json", "w"), separators=(",", ":"))
print(len(keep), "Spruenge behalten von", len(d))
PY
