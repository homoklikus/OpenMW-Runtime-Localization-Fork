# MWGodot — eksperyment: Morrowind na Godot 4

Eksperymentalny remaster Morrowinda: **oryginalna gra jest źródłem danych**, a silnik działa na
nowoczesnych formatach (glTF 2.0, JSON, PNG) w Godot 4.5. Razem z grą powstaje **Construction Set 2.0**
jako wtyczka edytora Godota.

> Projekt nie zawiera żadnych danych Bethesdy. Gracz wskazuje własną, legalną instalację Morrowinda,
> a konwerter przygotowuje dane lokalnie. Wszystkie testy korzystają z własnych danych syntetycznych.

```
converter/   mwconv – konwerter NIF/ESM/ESP/BSA/LAND → GLB + model świata (Python, numpy, Pillow)
godot/       projekt Godot 4.5: gra (strumieniowanie komórek, postać) + addons/mw_cs2 (CS 2.0)
gdextension/ minimalne rozszerzenie C++ (godot-cpp) – szkielet pod natywne przyspieszenia
tools/       run_tests.sh (pełny test), bench.py (benchmark), validate_gltf.js (walidator Khronos)
docs/        ARCHITEKTURA.md, DEBIAN13.md, LICENCJE.md, RAPORT-SESJA-1.md
```

Szybki start (Debian 13, szczegóły w `docs/DEBIAN13.md`):

```bash
GODOT=godot ./tools/run_tests.sh                     # wszystko na danych syntetycznych
cd converter && python3 -m mwconv convert --openmw-cfg ~/.config/openmw/openmw.cfg \
    --cell Balmora --out ~/.local/share/mwgodot/mwdata  # Twoja instalacja → dane lokalne
godot --path ../godot -- --data=$HOME/.local/share/mwgodot/mwdata
```

Licencja kodu: MIT (patrz `docs/LICENCJE.md` – w tym decyzja o ewentualnym przejściu na GPLv3).
