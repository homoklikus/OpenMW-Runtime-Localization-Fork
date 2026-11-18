#!/bin/bash
# mwscript_case.sh PRZYPADEK.json ETAP [ekran] – jeden etap porównania MWScript (dzielone na krótkie wywołania):
#   compile | omw | omw-base | godot | godot-base | diff | all
# Zmienne: OMW=/tmp/omwx  DATA=/tmp/s9_out  GODOT=…/Godot_v4.7.2-stable_linux.x86_64  OUT=/tmp/mwcmp
set -euo pipefail
CASE="$1"; STEP="$2"; DISP="${3:-71}"
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
OMW="${OMW:-/tmp/omwx}"; DATA="${DATA:-/tmp/s9_out}"; OUT="${OUT:-/tmp/mwcmp}"
GODOT="${GODOT:-$REPO/Godot_v4.7.2-stable_linux.x86_64}"
N="$(basename "$CASE" .json)"; mkdir -p "$OUT"
PY=(python3 "$HERE/mwscript_compare.py")
case "$STEP" in
  compile)
    "${PY[@]}" compile --case "$CASE" --out "$OUT/$N.c.json"
    "${PY[@]}" compile --case "$CASE" --baseline --out "$OUT/$N.base.c.json" ;;
  omw|omw-base)
    C="$OUT/$N.c.json"; S="$OUT/$N.omw.json"; [ "$STEP" = omw-base ] && { C="$OUT/$N.base.c.json"; S="$OUT/$N.base.omw.json"; }
    rm -f "/tmp/.X$DISP-lock"
    "${PY[@]}" openmw --case "$C" --omw "$OMW" --cfg "$OMW/cfg/openmw" --work "$OUT/work_${N}_$STEP" --display "$DISP" \
      --timeout 150 --out "$S" ;;
  godot|godot-base)
    C="$OUT/$N.c.json"; S="$OUT/$N.gd.json"; [ "$STEP" = godot-base ] && { C="$OUT/$N.base.c.json"; S="$OUT/$N.base.gd.json"; }
    CELL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("cell","Seyda Neen"))' "$C")"
    INT="$(python3 -c 'import json,sys; print(1 if json.load(open(sys.argv[1])).get("interior") else 0)' "$C")"
    WHERE=(--start="$CELL"); [ "$INT" = 1 ] && WHERE=(--cell="$CELL")
    "$GODOT" --headless --path "$REPO/godot" -s res://tests/probe_mwscript.gd -- --data="$DATA" \
      --project="$OUT/proj_$N" "${WHERE[@]}" --case="$C" --out="$S" 2>&1 | grep -E "^RESULT|^MWDBG|MWGODOT_SCRIPT|SCRIPT ERROR|Parse Error" || true
    test -s "$S" ;;
  all)
    "$0" "$CASE" compile && "$0" "$CASE" omw "$DISP" && "$0" "$CASE" omw-base "$((DISP + 1))" \
      && "$0" "$CASE" godot && "$0" "$CASE" godot-base && "$0" "$CASE" diff ;;
  diff)
    "${PY[@]}" diff "$OUT/$N.omw.json" "$OUT/$N.gd.json" --tol 0.6 --base-a "$OUT/$N.base.omw.json" \
      --base-b "$OUT/$N.base.gd.json" --case "$CASE" ;;
esac
