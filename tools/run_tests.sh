#!/usr/bin/env bash
# Pełny zestaw testów na danych syntetycznych (bez plików gry).
#   tools/run_tests.sh [--godot /ścieżka/godot] [--no-render] [--work /tmp/mwgodot-test]
# Kroki: pytest → dane „Synthville” → konwersja → walidacja GLB (opcjonalnie, node) → testy Godota
#        (import GLB, import edytorowy, świat + CS 2.0, ponowny import z nowym pluginem, GDExtension) → zrzuty.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
WORK="/tmp/mwgodot-test"
RENDER=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --godot) GODOT="$2"; shift 2;;
    --work) WORK="$2"; shift 2;;
    --no-render) RENDER=0; shift;;
    *) echo "nieznana opcja $1"; exit 2;;
  esac
done
PY="${PYTHON:-python3}"
DATA="$WORK/Data Files"
OUT="$WORK/out"
PROJ="$WORK/project"
rm -rf "$WORK"; mkdir -p "$WORK"
pass() { echo -e "\e[32m✔ $*\e[0m"; }
step() { echo -e "\n\e[1m== $* ==\e[0m"; }

step "1. Testy konwertera (pytest)"
(cd "$ROOT/converter" && $PY -m pytest -q)
pass "pytest"

step "1b. Launcher Qt (offscreen; z prawdziwym Godotem: gra + Construction Set)"
if $PY -c "from PySide6.QtWidgets import QApplication" 2>/dev/null; then
  (cd "$ROOT/launcher" && QT_QPA_PLATFORM=offscreen MWGODOT_REAL_GODOT="$(command -v "$GODOT" || echo "$GODOT")" $PY -m pytest -q tests)
  pass "launcher"
else
  echo "(pominięto – PySide6 niedostępne lub brak bibliotek Qt: sudo apt install python3-pyside6.qtwidgets)"
fi

step "2. Dane syntetyczne + konwersja"
(cd "$ROOT/converter" && $PY -m mwconv synth --out "$DATA" >/dev/null)
(cd "$ROOT/converter" && $PY -m mwconv convert --data "$DATA" --archive "$DATA/synth.bsa" \
   --content mwg_synthtown.esm --content mwg_synthtown_patch.esp --cell Synthville --out "$OUT" | tail -n 25)
pass "konwersja"

step "3. Walidacja GLB (Khronos glTF-Validator)"
if command -v node >/dev/null && node -e "require('gltf-validator')" 2>/dev/null; then
  node "$ROOT/tools/validate_gltf.js" $(find "$OUT/meshes" -name '*.glb') > "$WORK/validator.json"
  pass "walidator: $(grep -c '"errors": 0' "$WORK/validator.json") plików bez błędów"
else
  echo "(pominięto – zainstaluj: npm install gltf-validator i ustaw NODE_PATH)"
fi

step "4. Godot: import projektu"
"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1 || true
# fixture do testu importu edytorowego (własne syntetyczne GLB)
FIX="$ROOT/godot/tests/_fixture"
rm -rf "$FIX"; mkdir -p "$FIX/meshes/synth" "$FIX/textures"
cp "$OUT"/meshes/synth/*.glb "$FIX/meshes/synth/"; cp "$OUT"/textures/*.png "$FIX/textures/"
"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1 || true

run_gd() {  # $1 = skrypt, reszta = argumenty
  local s="$1"; shift
  local log="$WORK/$(basename "$s" .gd).log"
  "$GODOT" --headless --path "$ROOT/godot" -s "res://tests/$s" -- "$@" > "$log" 2>&1 || { grep -E "FAIL|RESULT|ERROR" "$log"; echo "BŁĄD: $s"; exit 1; }
  grep RESULT "$log" | cut -c1-400
  pass "$s"
}
step "5. Godot: testy"
run_gd test_import.gd --data="$OUT"
run_gd test_editor_import.gd
run_gd test_controllers.gd --data="$OUT"
run_gd test_game.gd --data="$OUT" --project="$WORK/project_game"
run_gd test_cs2.gd --data="$OUT" --project="$WORK/project_cs2"
run_gd test_world.gd --data="$OUT" --project="$PROJ"
step "6. Ponowny import z nowym pluginem (zmiany CS 2.0 muszą przetrwać)"
(cd "$ROOT/converter" && $PY -c "from mwconv.synthetic_world import write_patch2; write_patch2('$DATA')")
(cd "$ROOT/converter" && $PY -m mwconv convert --data "$DATA" --archive "$DATA/synth.bsa" \
   --content mwg_synthtown.esm --content mwg_synthtown_patch.esp --content mwg_synthtown_patch2.esp \
   --cell Synthville --out "$OUT" | grep -E "Modele|Tekstury|Gotowe")
run_gd test_world.gd --data="$OUT" --project="$PROJ" --phase=verify --expect-source=mwg_synthtown_patch2.esp
step "6b. Wypiekanie GLB → .scn (tekstury VRAM) i porównanie"
(cd "$ROOT/converter" && $PY -m mwconv convert --data "$DATA" --archive "$DATA/synth.bsa" \
   --content mwg_synthtown.esm --content mwg_synthtown_patch.esp --content mwg_synthtown_patch2.esp \
   --cell Synthville --out "$OUT" --bake-godot "$GODOT" --bake-project "$ROOT/godot" | grep -E "Wypiekanie|Gotowe")
run_gd test_bake.gd --data="$OUT"
if ls "$ROOT/godot/bin/"libmw_native* >/dev/null 2>&1; then
  run_gd test_gdextension.gd
else
  echo "(GDExtension niezbudowane – pominięto; patrz docs/DEBIAN13.md)"
fi

if [[ $RENDER == 1 ]]; then
  step "7. Zrzuty ekranu"
  XV=""; command -v xvfb-run >/dev/null && [[ -z "${DISPLAY:-}" ]] && XV="xvfb-run -a -s '-screen 0 1280x720x24'"
  eval $XV "$GODOT" --path "$ROOT/godot" --rendering-driver opengl3 -s res://tests/render_shot.gd -- \
    --data="$OUT" --out="$WORK/shot_models.png" --mode=models 2>/dev/null | grep SHOT || true
  eval $XV "$GODOT" --path "$ROOT/godot" --rendering-driver opengl3 -s res://tests/render_shot.gd -- \
    --data="$OUT" --project="$PROJ" --out="$WORK/shot_world.png" --mode=world --cam=40,60,-60 --look=117,10,-117 2>/dev/null | grep SHOT || true
  eval $XV "$GODOT" --path "$ROOT/godot" --rendering-driver opengl3 -s res://tests/render_shot.gd -- \
    --data="$OUT" --out="$WORK/shot_effects.png" --mode=effects 2>/dev/null | grep SHOT || true
  (cd "$ROOT/launcher" && QT_QPA_PLATFORM=offscreen $PY tools/screenshots.py "$WORK" >/dev/null 2>&1 && echo "SHOT launcher (Qt)") || true
fi
echo -e "\n\e[32mWSZYSTKIE TESTY ZALICZONE\e[0m  (wyniki: $WORK)"
