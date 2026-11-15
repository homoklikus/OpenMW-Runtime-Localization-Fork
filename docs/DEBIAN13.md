# Uruchomienie na Debianie 13 (trixie)

## 1. Zależności

```bash
sudo apt install python3 python3-numpy python3-pil python3-pytest git xvfb
# opcjonalnie: GDExtension (C++)
sudo apt install build-essential scons
# opcjonalnie: walidator glTF
sudo apt install nodejs npm
```

Konwerter potrzebuje tylko Pythona ≥ 3.10, numpy i Pillow ≥ 10.1 (w trixie: 3.13 / 2.2 / 11.1).
Blender **nie** jest potrzebny, GPU też nie.

Godot 4.5 nie jest pakietem Debiana — użyj oficjalnej binarki (lub Flatpaka `org.godotengine.Godot`):

```bash
mkdir -p ~/opt/godot && cd ~/opt/godot
wget https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_linux.x86_64.zip
unzip Godot_v4.5.1-stable_linux.x86_64.zip && ln -sf "$PWD/Godot_v4.5.1-stable_linux.x86_64" ~/.local/bin/godot
godot --version   # 4.5.1.stable.official
```

## 2. Testy na danych syntetycznych (bez plików gry)

```bash
cd mwgodot
GODOT=godot ./tools/run_tests.sh            # pytest + konwersja + testy Godota + zrzuty ekranu
# walidator Khronos (opcjonalnie):
npm install --prefix ~/.local/lib/gltfv gltf-validator
NODE_PATH=~/.local/lib/gltfv/node_modules GODOT=godot ./tools/run_tests.sh
python3 tools/bench.py --work /tmp/mwbench   # benchmark syntetyczny
```

## 3. Konwersja Twojej instalacji Morrowinda — Balmora

Wyniki zapisuj **poza** repozytorium (zawierają przekonwertowane zasoby Bethesdy, których nie wolno
publikować). Przykład: `~/.local/share/mwgodot/mwdata`.

Wariant A — konfiguracja OpenMW (Flatpak z `/var/lib/flatpak/app/org.openmw.OpenMW` używa
`~/.var/app/org.openmw.OpenMW/config/openmw/openmw.cfg`; instalacja natywna: `~/.config/openmw/openmw.cfg`):

```bash
cd mwgodot/converter
python3 -m mwconv convert \
  --openmw-cfg ~/.var/app/org.openmw.OpenMW/config/openmw/openmw.cfg \
  --cell Balmora --grid-range=-4,-4,-1,-1 \
  --out ~/.local/share/mwgodot/mwdata --jobs 4
```

Wariant B — katalog oryginalnej gry (z `Data Files` i `Morrowind.ini`):

```bash
python3 -m mwconv convert --morrowind "/ścieżka/Morrowind" --cell Balmora --out ~/.local/share/mwgodot/mwdata
```

Wariant C — ręcznie:

```bash
python3 -m mwconv convert --data "/ścieżka/Data Files" \
  --archive "/ścieżka/Data Files/Morrowind.bsa" --archive ".../Tribunal.bsa" --archive ".../Bloodmoon.bsa" \
  --content Morrowind.esm --content Tribunal.esm --content Bloodmoon.esm \
  --cell Balmora --out ~/.local/share/mwgodot/mwdata
```

* `--cell Balmora` wybiera komórki zewnętrzne nazwane „Balmora” i wszystkie wnętrza „Balmora, …”.
  `--grid-range=x0,y0,x1,y1` dodaje okoliczne komórki (np. tereny wokół miasta). Uwaga: przy wartościach
  ujemnych pisz `--grid-range=…` (ze znakiem „=”).
* Ponowne uruchomienie przetwarza tylko zmienione pliki (SHA-256). Przerwaną konwersję wystarczy
  uruchomić ponownie. `--verify-hash` wymusza sumy SHA-256 zamiast skrótu rozmiar+mtime.
* Pełna gra (pomiar czasu, nie zalecane na start): `--all-cells --all-models --all-textures`.
* Raport: `<out>/reports/conversion.json` (czasy, przepustowość, pamięć, rozmiary, błędy i diagnostyka
  modeli – elementy przeniesione w przybliżeniu lub pominięte).

## 4. Gra i Construction Set 2.0

```bash
# gra (strumieniowanie komórek wokół gracza; WASD, mysz, spacja, Shift, F = latanie)
godot --path mwgodot/godot -- --data=$HOME/.local/share/mwgodot/mwdata
# wnętrze:
godot --path mwgodot/godot -- --data=$HOME/.local/share/mwgodot/mwdata --cell="Balmora, Caius Cosades' House"
# start w punkcie (jednostki MW):
godot --path mwgodot/godot -- --data=... --pos=-22000,-15000,1500
# tryb zgodności (słabsze GPU / brak Vulkana):
godot --path mwgodot/godot --rendering-method gl_compatibility -- --data=...
```

Edytor: `godot -e --path mwgodot/godot` → panel **MW CS 2.0** (prawy górny dok):
1. wpisz katalog danych i katalog projektu (nadpisań) → **Wczytaj świat**;
2. wybierz komórkę → **Otwórz komórkę** (powstaje scena robocza `res://cs2_cells/*.tscn` — tylko
   transformacje i metadane, bez zasobów gry);
3. przesuwaj/obracaj/skaluj referencje gizmem Godota, usuwaj klawiszem Delete, dodawaj z listy obiektów;
4. **Zapisz nadpisania projektu** → `<projekt>/overrides/cells/...json`. Gra wczytuje je automatycznie
   (`--project=` lub ustawienie `mwgodot/project_root`).

Ustawienia domyślne są w `project.godot` (`mwgodot/data_root`, `mwgodot/project_root`, `mwgodot/start_cell`).

## 5. GDExtension (opcjonalnie)

```bash
git clone -b 4.5 https://github.com/godotengine/godot-cpp ~/src/godot-cpp
cd mwgodot/gdextension
scons -j4 platform=linux target=template_debug GODOT_CPP=~/src/godot-cpp build_profile=$PWD/build_profile.json
# → godot/bin/libmw_native.linux.template_debug.x86_64.so, test: tests/test_gdextension.gd
```
