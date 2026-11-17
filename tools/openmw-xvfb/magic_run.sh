#!/bin/bash
# magic_run.sh PRZYPADEK… – pełne porównanie (compile, OpenMW z/bez czarów, Godot z/bez, diff) dla przypadków magii
HERE="$(cd "$(dirname "$0")" && pwd)"; export OUT="${OUT:-/tmp/mgcmp}"; D=${DISP:-93}
for c in "$@"; do
  n=$(basename "$c" .json)
  bash "$HERE/mwscript_case.sh" "$c" compile >/dev/null 2>&1
  bash "$HERE/mwscript_case.sh" "$c" omw $D >/dev/null 2>&1 || echo "$n: błąd OpenMW"
  bash "$HERE/mwscript_case.sh" "$c" omw-base $((D+1)) >/dev/null 2>&1 || echo "$n: błąd OpenMW (baza)"
  bash "$HERE/mwscript_case.sh" "$c" godot >/dev/null 2>&1 || echo "$n: błąd Godot"
  bash "$HERE/mwscript_case.sh" "$c" godot-base >/dev/null 2>&1 || echo "$n: błąd Godot (baza)"
  bash "$HERE/mwscript_case.sh" "$c" diff > "$OUT/$n.diff.txt" 2>&1
  echo "== $n: $(tail -1 "$OUT/$n.diff.txt")"
done
