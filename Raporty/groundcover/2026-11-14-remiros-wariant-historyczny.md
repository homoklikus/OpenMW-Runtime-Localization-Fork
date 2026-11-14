# Remiros' Groundcover — wariant historyczny i referencyjny (2026-11-14)

Weryfikacja po SHA-256 wszystkich plików, bez porównywania samych nazw.

- Instalacja używana we wcześniejszych testach forka (AppImage v0.4a) to **Remiros 4.1 `00 Core OpenMW` + nakładka `01b Thicker Grass OpenMW`, z grzybami**: 76/76 plików treści zgodnych. Nie zastosowano `01a No Mushrooms`, `02 Vanilla Resolution Textures` ani wariantów MGE XE.
- Te same bajty mają: katalog moda w dawnej instalacji AppImage, pula modeli generatora forka (`remiros_procedural_test`) oraz obecna referencja oficjalnego OpenMW 0.51.0.
- `01b` nadpisuje 3 modele (`rem_ac_grass_03/04`, `rem_bc_grass_02`). W OpenMW działa jako osobny `data=` po Core albo przez nadpisanie w jednym katalogu; efektywny zestaw jest taki sam.
- Pluginy Core używają 26 z 36 modeli i 25 tekstur. Modele `rem_gm/rr/at/tv` należą do pluginów Tamriel Rebuilt.
- Dawny profil AppImage różnił się od referencji: miał dodatkowo `groundcover=Vurt's Corals.esp`, domyślny dystans groundcover 6144 (referencja: 4000), większy dystans widzenia i inne mody tekstur. Działał na gałęzi `0.4a`, czyli na oficjalnym mechanizmie pluginów, przed systemem World.
- Referencja zawiera teraz tylko `00 Core OpenMW` i `01b Thicker Grass OpenMW`; pozostałe warianty można odtworzyć z oryginalnego archiwum.

Wniosek: podstawą dalszej kalibracji proceduralnego Groundcover jest Core OpenMW + Thicker Grass (z grzybami). Historyczne liczby instancji trzeba zmierzyć ponownie według jednej zdefiniowanej metryki i przy identycznych ustawieniach widoczności.
