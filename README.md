# MWGodot — eksperyment: Morrowind na Godot 4

Eksperymentalny remaster Morrowinda: **oryginalna gra jest źródłem danych**, a silnik działa na
nowoczesnych formatach (glTF 2.0, JSON, PNG) w Godot 4.5–4.7. Razem z grą powstaje **Construction Set 2.0**
jako wtyczka edytora Godota.

> Projekt nie zawiera żadnych danych Bethesdy. Gracz wskazuje własną, legalną instalację Morrowinda,
> a konwerter przygotowuje dane lokalnie. Wszystkie testy korzystają z własnych danych syntetycznych.

```
launcher/    OpenMWGodot Launcher – Qt 6 (PySide6): konwersja, mody, profile, ustawienia, „Graj”, Construction Set
converter/   mwconv – konwerter NIF/ESM/ESP/BSA/LAND → GLB + model świata (Python, numpy, Pillow)
             mwcore – wspólna warstwa danych (profile, mody, konfiguracja, stan konwersji, procesy)
godot/       projekt Godot 4.5: gra (strumieniowanie komórek, postać) + addons/mw_cs2 (CS 2.0)
gdextension/ minimalne rozszerzenie C++ (godot-cpp) – szkielet pod natywne przyspieszenia
tools/       run_tests.sh (pełny test), bench.py (benchmark), validate_gltf.js (walidator Khronos)
docs/        ARCHITEKTURA.md, LAUNCHER.md, DEBIAN13.md, LICENCJE.md, RAPORT-SESJA-1..3.md; CHANGELOG.md
```

Szybki start (Debian 13, szczegóły w `docs/DEBIAN13.md`):

```bash
GODOT=godot ./tools/run_tests.sh                     # wszystko na danych syntetycznych (Godot 4.5–4.7)
./tools/install_launcher.sh && openmwgodot           # launcher: wykryj Morrowinda → konwertuj → graj
cd converter && python3 -m mwconv convert --openmw-cfg ~/.config/openmw/openmw.cfg \
    --cell Balmora --out ~/.local/share/mwgodot/mwdata  # Twoja instalacja → dane lokalne
godot --path ../godot -- --data=$HOME/.local/share/mwgodot/mwdata
```

Licencja kodu: MIT (patrz `docs/LICENCJE.md` – w tym decyzja o ewentualnym przejściu na GPLv3).
