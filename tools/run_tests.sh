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
# ścieżka do Godota jako pełna – kroki testów wchodzą do podkatalogów (converter/, launcher/)
if [[ "$GODOT" == */* ]]; then
  [[ -x "$GODOT" ]] || { echo "Nie znaleziono Godota: $GODOT"; exit 2; }
  GODOT="$(cd "$(dirname "$GODOT")" && pwd)/$(basename "$GODOT")"
fi
DATA="$WORK/Data Files"
OUT="$WORK/out"
PROJ="$WORK/project"
rm -rf "$WORK"; mkdir -p "$WORK"
pass() { echo -e "\e[32m✔ $*\e[0m"; }
step() { echo -e "\n\e[1m== $* ==\e[0m"; }

step "1. Testy konwertera (pytest)"
if ! $PY -c "import pytest" 2>/dev/null; then
  echo "Brak pytest: sudo apt install python3-pytest"; exit 2
fi
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
run_gd test_first_fish.gd
run_gd test_step_sound.gd
run_gd test_ai_mechanics.gd
run_gd test_water_creatures.gd
run_gd test_navmesh.gd
run_gd test_controllers.gd --data="$OUT"
run_gd test_game.gd --data="$OUT" --project="$WORK/project_game"
run_gd test_cs2.gd --data="$OUT" --project="$WORK/project_cs2"
run_gd test_world.gd --data="$OUT" --project="$PROJ"
rm -rf "$WORK/project_mods"; mkdir -p "$WORK/project_mods"
run_gd test_save_mods.gd --data="$OUT" --project="$WORK/project_mods" --phase=save
step "6. Ponowny import z nowym pluginem (zmiany CS 2.0 muszą przetrwać)"
(cd "$ROOT/converter" && $PY -c "from mwconv.synthetic_world import write_patch2; write_patch2('$DATA')")
(cd "$ROOT/converter" && $PY -m mwconv convert --data "$DATA" --archive "$DATA/synth.bsa" \
   --content mwg_synthtown.esm --content mwg_synthtown_patch.esp --content mwg_synthtown_patch2.esp \
   --cell Synthville --out "$OUT" | grep -E "Modele|Tekstury|Gotowe")
run_gd test_world.gd --data="$OUT" --project="$PROJ" --phase=verify --expect-source=mwg_synthtown_patch2.esp
run_gd test_save_mods.gd --data="$OUT" --project="$WORK/project_mods" --phase=add
step "6a. Zapis gry bez jednej z wtyczek (obiekty nie znikają z zapisu)"
(cd "$ROOT/converter" && $PY -m mwconv convert --data "$DATA" --archive "$DATA/synth.bsa" \
   --content mwg_synthtown.esm --content mwg_synthtown_patch2.esp \
   --cell Synthville --out "$WORK/nopatch_out" | grep -E "Gotowe")
run_gd test_save_mods.gd --data="$WORK/nopatch_out" --project="$WORK/project_mods" --phase=missing
step "6b. Wypiekanie GLB → .scn (tekstury VRAM) i porównanie"
(cd "$ROOT/converter" && $PY -m mwconv convert --data "$DATA" --archive "$DATA/synth.bsa" \
   --content mwg_synthtown.esm --content mwg_synthtown_patch.esp --content mwg_synthtown_patch2.esp \
   --cell Synthville --out "$OUT" --bake-godot "$GODOT" --bake-project "$ROOT/godot" | grep -E "Wypiekanie|Gotowe")
run_gd test_bake.gd --data="$OUT"
# przyrostowo: bez zmian → nic do wypiekania; po zmianie tekstury → ponownie tylko modele, które jej używają
BAKE=(--data "$DATA" --archive "$DATA/synth.bsa" --content mwg_synthtown.esm --content mwg_synthtown_patch.esp
      --content mwg_synthtown_patch2.esp --cell Synthville --out "$OUT" --bake-godot "$GODOT" --bake-project "$ROOT/godot")
R=$(cd "$ROOT/converter" && $PY -m mwconv convert "${BAKE[@]}")
[[ "$R" == *"'todo': 0"* ]] || { echo "BŁĄD: ponowne wypiekanie bez zmian"; echo "$R" | tail -5; exit 1; }
sleep 1.1; touch "$OUT/textures/tx_synth_roof.png"
R=$(cd "$ROOT/converter" && $PY -m mwconv convert "${BAKE[@]}")
N=$(echo "$R" | sed -n "s/.*'todo': \([0-9]*\).*/\1/p" | head -1)
[[ "$N" -ge 1 && "$N" -lt 8 ]] || { echo "BŁĄD: po zmianie tekstury wypieczono $N modeli (oczekiwano części)"; exit 1; }
pass "wypiekanie przyrostowe (zmiana tekstury → $N modeli)"
# po przeniesieniu katalogu wyników: stare sceny ignorowane (pełne ścieżki do tekstur), konwersja wypieka od nowa
rm -rf "$WORK/moved"; cp -a "$OUT" "$WORK/moved"; mv "$OUT" "$OUT.orig"
MOVED=("${BAKE[@]}"); MOVED[${#MOVED[@]}-5]="$WORK/moved"
R=$(cd "$ROOT/converter" && $PY -m mwconv convert "${MOVED[@]}")
N=$(echo "$R" | sed -n "s/.*'todo': \([0-9]*\).*/\1/p" | head -1)
[[ "$N" -ge 8 ]] || { echo "BŁĄD: po przeniesieniu wypieczono $N modeli (oczekiwano wszystkich)"; exit 1; }
run_gd test_bake.gd --data="$WORK/moved"; mv "$OUT.orig" "$OUT"
pass "wypiekanie po przeniesieniu katalogu ($N modeli)"
step "6c. Roślinność (wtyczka groundcover + trawa Remirosa z tabeli forka, MultiMesh)"
FLORA="$WORK/Flora"
(cd "$ROOT/converter" && $PY -c "from mwconv.synthetic_world import write_flora; write_flora('$FLORA')")
(cd "$ROOT/converter" && $PY -m mwconv convert --data "$DATA" --data "$FLORA" --archive "$DATA/synth.bsa" \
   --content mwg_synthtown.esm --content mwg_synthtown_patch.esp --groundcover mwg_grass.esp \
   --flora hybrid --cell Synthville --out "$WORK/flora_out" | grep -E "Roślinność|Gotowe")
run_gd test_flora.gd --data="$WORK/flora_out"

step "6d. Aktorzy (NPC z części ciała, skinning, lustro lewej strony, animacje NPC i stworzeń)"
(cd "$ROOT/converter" && $PY -c "from mwconv.synthetic_actor import write_actors; write_actors('$DATA')")
(cd "$ROOT/converter" && $PY -m mwconv convert --data "$DATA" --archive "$DATA/synth.bsa" \
   --content mwg_synthtown.esm --content mwg_synthtown_patch.esp --content mwg_actors.esp \
   --cell Synthville --out "$WORK/actors_out" | grep -E "Gotowe")
run_gd test_actors.gd --data="$WORK/actors_out"
# start gry: syntetyczne filmy Theora (zamiast Binka z gry) – 1 s, logo Morrowinda bez dźwięku jak mw_logo.bik
if command -v ffmpeg >/dev/null 2>&1; then
  mkdir -p "$WORK/actors_out/video"
  for v in synth_logo synth_intro mw_credits; do
    ffmpeg -hide_banner -nostdin -y -v error -f lavfi -i testsrc=size=320x240:rate=30:duration=1 \
      -f lavfi -i sine=frequency=440:duration=1 -c:v libtheora -q:v 5 -c:a libvorbis -ar 44100 -ac 2 -f ogg \
      "$WORK/actors_out/video/$v.ogv"
  done
  ffmpeg -hide_banner -nostdin -y -v error -f lavfi -i testsrc=size=320x240:rate=30:duration=2 \
    -c:v libtheora -q:v 5 -f ogg "$WORK/actors_out/video/synth_mwlogo.ogv"
  printf '{"format":"mwgodot-video","version":1,"videos":{"video/synth_logo.bik":{"audio":true},"video/synth_intro.bik":{"audio":true},"video/mw_credits.bik":{"audio":true},"video/synth_mwlogo.bik":{"audio":false}}}' > "$WORK/actors_out/video/index.json"
fi
rm -rf "$WORK/saves_start"
run_gd test_start_game.gd --data="$WORK/actors_out" --project="$WORK/project_start" --saves="$WORK/saves_start" --menu=1
run_gd test_interaction.gd --data="$WORK/actors_out" --project="$WORK/project_interaction" --pos=2300,2400,300 --scripts=0
run_gd test_count_dialog.gd --data="$WORK/actors_out" --project="$WORK/project_count" --pos=2300,2400,900 --scripts=0
run_gd test_quick_keys.gd --data="$WORK/actors_out" --project="$WORK/project_quickkeys" --pos=2300,2400,900 --scripts=0
run_gd test_tooltips.gd --data="$WORK/actors_out" --project="$WORK/project_tooltips" --pos=2300,2400,900 --scripts=0
run_gd test_load_controls.gd --data="$WORK/actors_out" --project="$WORK/project_load_controls" --pos=2300,2400,900 --scripts=0
run_gd test_load_ui.gd --data="$WORK/actors_out" --project="$WORK/project_load_ui" --pos=2300,2400,900 --saves="$WORK/load_ui_saves"
run_gd test_camera.gd --data="$WORK/actors_out" --project="$WORK/project_camera" --pos=2300,2400,900 --scripts=0
run_gd test_look_stability.gd --data="$WORK/actors_out" --project="$WORK/project_look" --pos=2300,2400,900 --scripts=0
run_gd test_companion.gd --data="$WORK/actors_out" --project="$WORK/project_companion" --pos=2300,2400,900 --scripts=0
run_gd test_console.gd --data="$WORK/actors_out" --project="$WORK/project_console" --pos=2300,2400,900 --scripts=0
run_gd test_keyboard_nav.gd --data="$WORK/actors_out" --project="$WORK/project_kn" --pos=2300,2400,900 --scripts=0
run_gd test_gamepad.gd --data="$WORK/actors_out" --project="$WORK/project_gp" --pos=2300,2400,900 --scripts=0
run_gd test_character.gd --data="$WORK/actors_out" --project="$WORK/project_character" --pos=2300,2400,900 --scripts=0
run_gd test_scripts.gd --data="$WORK/actors_out" --project="$WORK/project_scripts" --pos=2000,2300,900
run_gd test_mwscript_functions.gd --data="$WORK/actors_out" --project="$WORK/project_mwscript_fn" --pos=2300,2400,900
run_gd test_dialogue.gd --data="$WORK/actors_out" --project="$WORK/project_dialogue" --pos=2300,2400,900
run_gd test_progress.gd --data="$WORK/actors_out" --project="$WORK/project_progress" --pos=2300,2400,900 --scripts=0
run_gd test_trade.gd --data="$WORK/actors_out" --project="$WORK/project_trade" --pos=2300,2400,900 --scripts=0
run_gd test_player_controls.gd --data="$WORK/actors_out" --project="$WORK/project_player_controls" --pos=2300,2400,900 --scripts=0
run_gd test_console_toggles.gd --data="$WORK/actors_out" --project="$WORK/project_console_toggles" --pos=2300,2400,900 --scripts=0
run_gd test_trade_sources.gd --data="$WORK/actors_out" --project="$WORK/project_trade_sources" --pos=2300,2400,900 --scripts=0
run_gd test_item_stacks.gd --data="$WORK/actors_out" --project="$WORK/project_item_stacks" --pos=2300,2400,900 --scripts=0
run_gd test_repair.gd --data="$WORK/actors_out" --project="$WORK/project_repair" --pos=2300,2400,900 --scripts=0
run_gd test_alchemy.gd --data="$WORK/actors_out" --project="$WORK/project_alchemy" --pos=2300,2400,900 --scripts=0
run_gd test_enchanting.gd --data="$WORK/actors_out" --project="$WORK/project_enchanting" --pos=2300,2400,900 --scripts=0
run_gd test_combat.gd --data="$WORK/actors_out" --project="$WORK/project_combat" --pos=2300,2400,900 --scripts=0
run_gd test_enemy_health.gd --data="$WORK/actors_out" --project="$WORK/project_enemy_health" --pos=2300,2400,900 --scripts=0
run_gd test_cursor_drop.gd --data="$WORK/actors_out" --project="$WORK/project_cursor_drop" --pos=2300,2400,900 --scripts=0
run_gd test_pickpocket.gd --data="$WORK/actors_out" --project="$WORK/project_pickpocket" --pos=2300,2400,900 --scripts=0
run_gd test_audio_ranges.gd --data="$WORK/actors_out" --project="$WORK/project_audio_ranges" --pos=2300,2400,900 --scripts=0
run_gd test_magic.gd --data="$WORK/actors_out" --project="$WORK/project_magic" --pos=2300,2400,900 --scripts=0
run_gd test_ai.gd --data="$WORK/actors_out" --project="$WORK/project_ai" --pos=2300,2400,900 --scripts=0
run_gd test_combat_ai.gd --data="$WORK/actors_out" --project="$WORK/project_cai" --pos=2300,2400,900 --scripts=0
run_gd test_water_game.gd --data="$WORK/actors_out" --project="$WORK/project_water" --pos=2300,2400,900 --scripts=0
run_gd test_transition.gd --data="$WORK/actors_out" --project="$WORK/project_transition" --pos=2300,2400,900 --scripts=0
run_gd test_load_reveal.gd --data="$WORK/actors_out" --project="$WORK/project_load_reveal" --pos=2300,2400,900 --scripts=0
run_gd test_crime.gd --data="$WORK/actors_out" --project="$WORK/project_crime" --pos=2300,2400,900 --scripts=0
run_gd test_chargen.gd --data="$WORK/actors_out" --project="$WORK/project_chargen" --pos=2300,2400,900
run_gd test_sound_world.gd --data="$WORK/actors_out" --project="$WORK/project_sound_world" --pos=2600,2700,900
run_gd test_books.gd --data="$WORK/actors_out" --project="$WORK/project_books" --pos=2300,2400,900 --scripts=0
run_gd test_map.gd --data="$WORK/actors_out" --project="$WORK/project_map" --pos=2300,2400,900 --scripts=0
run_gd test_map_notes.gd --data="$WORK/actors_out" --project="$WORK/project_notes" --pos=2300,2400,900 --scripts=0
run_gd test_weather.gd --data="$WORK/actors_out" --project="$WORK/project_weather" --pos=2300,2400,900 --scripts=0
run_gd test_menu_mode.gd --data="$WORK/actors_out" --project="$WORK/project_menu_mode" --pos=2300,2400,900 --scripts=0
run_gd test_ui_geometry.gd --data="$WORK/actors_out" --project="$WORK/project_ui_geometry" --pos=2300,2400,900 --scripts=0
run_gd test_window_settings.gd --data="$WORK/actors_out" --project="$WORK/project_window_settings" --pos=2300,2400,900 --scripts=0 --window-settings="$WORK/window_settings_test.json"
run_gd test_messagebox.gd --data="$WORK/actors_out" --project="$WORK/project_messagebox" --pos=2300,2400,900 --scripts=0
run_gd test_gui_modes.gd --data="$WORK/actors_out" --project="$WORK/project_gui_modes" --pos=2300,2400,900 --scripts=0
run_gd test_language.gd --data="$WORK/actors_out" --project="$WORK/project_language" --pos=2300,2400,900 --scripts=0
run_gd test_chargen_class.gd --data="$WORK/actors_out" --project="$WORK/project_chargen_class" --pos=2300,2400,900 --scripts=0
run_gd test_chargen_windows.gd --data="$WORK/actors_out" --project="$WORK/project_chargen_windows" --pos=2300,2400,900 --scripts=0
run_gd test_settings.gd --data="$WORK/actors_out" --project="$WORK/project_settings" --settings="$WORK/settings_cfg/runtime_settings.json" --saves="$WORK/settings_saves" --pos=2300,2400,900 --scripts=0
run_gd test_anim_sounds.gd --data="$WORK/actors_out" --project="$WORK/project_anim_sounds" --pos=2300,2400,900 --scripts=0

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
  # ekran ładowania rysowany w klatkach force_draw (wymaga wyświetlacza – odczyt obrazu)
  eval $XV "$GODOT" --path "$ROOT/godot" -s res://tests/test_loading_render.gd -- --data="$WORK/actors_out" \
    --project="$WORK/project_loading_render" --pos=2300,2400,900 --scripts=0 > "$WORK/loading_render.log" 2>&1 \
    || { grep -E "FAIL|ERROR" "$WORK/loading_render.log" | head; echo "test_loading_render: BŁĄD"; exit 1; }
  grep RESULT "$WORK/loading_render.log"; pass "test_loading_render.gd"
  (cd "$ROOT/launcher" && QT_QPA_PLATFORM=offscreen $PY tools/screenshots.py "$WORK" >/dev/null 2>&1 && echo "SHOT launcher (Qt)") || true
fi
echo -e "\n\e[32mWSZYSTKIE TESTY ZALICZONE\e[0m  (wyniki: $WORK)"
