#!/usr/bin/env bash
# Animations-Labor. Ein Match mit festem Zufall (--seed) laeuft ohne Bild und misst alle Spieler;
# danach wird dasselbe Match mit Bild abgespielt und nur an den schlimmsten Stellen gefilmt.
#   tools/lab/lab.sh audit SEED TAKTE ordner             -> ordner/audit.json + Zusammenfassung
#   tools/lab/lab.sh film SEED ordner [anzahl] [typen]   -> ordner/sNN.mp4, sNN_bogen.jpg (typen=keep: shots.json behalten)
#   tools/lab/lab.sh all SEED TAKTE ordner [anzahl]      -> beides
# Godot: Umgebungsvariable GODOT (sonst "godot"). 120 Takte = 1 s Spielzeit.
set -euo pipefail
cd "$(dirname "$0")/../.."
G=${GODOT:-godot}
ARGS=(--play --botplay ${LAB_EXTRA:-})
cmd=$1; seed=$2
audit() {
  local ticks=$1 out=$2; mkdir -p "$out"
  "$G" --headless --fixed-fps 60 res://scenes/main.tscn -- "${ARGS[@]}" --seed="$seed" --lab-audit="$out/audit.json" --lab-end="$ticks" > "$out/audit.log" 2>&1 || true
  grep -E "SCRIPT ERROR|LAB:" "$out/audit.log" | head -5
  python3 tools/lab/summary.py "$out/audit.json" | tee "$out/zusammenfassung.txt"
}
film() {
  local out=$1 n=${2:-8} types=${3:--}
  [ "$types" = keep ] || python3 tools/lab/pick.py "$out/audit.json" "$out/shots.json" "$n" "$types"
  rm -f "$out"/s*_main.jpg "$out"/s*_side.jpg "$out"/s*_front.jpg
  xvfb-run -a -s "-screen 0 960x540x24" "$G" --rendering-driver opengl3 --resolution 960x540 --fixed-fps 60 \
    res://scenes/main.tscn -- "${ARGS[@]}" --seed="$seed" --lab-shots="$out/shots.json" --lab-out="$out" > "$out/film.log" 2>&1 || true
  grep -E "SCRIPT ERROR" "$out/film.log" | head -5 || true
  python3 tools/lab/sheet.py "$out"
}
case $cmd in
  audit) audit "$3" "$4" ;;
  film) film "$3" "${4:-8}" "${5:--}" ;;
  all) audit "$3" "$4"; film "$4" "${5:-8}" ;;
esac
