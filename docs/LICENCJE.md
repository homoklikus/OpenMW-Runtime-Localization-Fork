# Licencje i dystrybucja

> To analiza techniczna, nie porada prawna. Przed publicznym wydaniem warto ją potwierdzić z prawnikiem.

## Zasoby Bethesdy

* Repozytorium, wydania, raporty i artefakty CI **nie zawierają** żadnych plików gry ani wyników ich
  konwersji. `.gitignore` wyklucza `*.esm/*.esp/*.bsa`, katalogi `Data Files` i wyniki.
* Wszystkie dane testowe są generowane kodem (`mwconv/synthetic*.py`): geometria, tekstury proceduralne,
  ESM/ESP „Synthville”. Można je publikować na licencji projektu.
* Raport konwersji gracza zawiera ścieżki i nazwy rekordów (metadane) — zostaje lokalnie u gracza.
* Model dystrybucji jak w OpenMW: gracz wskazuje własną legalną instalację, konwersja odbywa się lokalnie.

## Kod projektu

**Decyzja (2026-11-15): GPL-3.0-or-later dla całego repozytorium** (konwerter, launcher, projekt Godot,
wtyczka CS 2.0, GDExtension) — ta sama licencja co OpenMW. Powód: projekt będzie korzystał z kodu forka
OpenMW RLF i być może oryginalnego OpenMW (np. interpreter MWScript, mechaniki, loader NIF), a to wymaga
licencji zgodnej z GPLv3. Pełny tekst: `LICENSE`. Copyright © 2026 OpenMWGodot contributors.

Konsekwencje:

* kod OpenMW i forka RLF (GPLv3) można przenosić — z zachowaniem informacji o prawach autorskich
  i oznaczeniem pochodzenia (plik, wersja/commit OpenMW) w nagłówku przeniesionego pliku i w tym dokumencie;
* każdy rozpowszechniany build (paczka, wydanie) musi mieć dostępny kod źródłowy — repozytorium jest
  publiczne (`homoklikus/OpenMW-Runtime-Localization-Fork`, gałąź `OpenMWGoDot`);
* GPL praktycznie wyklucza wydania na konsole (zamknięte SDK);
* MCP-openMW (`tools/MCP-openMW` w forku, GPLv3) może być teraz użyty także jako kod.

Kod napisany w sesjach 1–3 jest implementacją własną, powstałą na podstawie publicznych opisów formatów:

| Źródło wiedzy | Licencja | Sposób użycia |
|---|---|---|
| NifTools `nif.xml` | BSD-3-Clause | opis formatu NIF (fakty o układzie pól) |
| UESP „Mod File Format” (TES3) | CC BY-SA (tekst) | opis formatu ESM/ESP/BSA – fakty, bez kopiowania tekstu |
| kod OpenMW 0.51 (fork RLF) | GPLv3 | odczyt w celu potwierdzenia konwencji (stała `UnitsPerMeter`, kolejność obrotów referencji, triangulacja „diamond”, zerowanie transformacji korzenia NIF, semantyka skinu, lista ukrytych znaczników). Do sesji 3 żaden fragment nie został skopiowany. |

Przeniesiony kod OpenMW (od sesji 4): *na razie brak* — każdy przeniesiony fragment dopisujemy tutaj.

## Zależności i narzędzia

| Komponent | Licencja | Dystrybuowany? |
|---|---|---|
| Godot 4.5.1 | MIT | tak (silnik/eksport) – wymaga zachowania informacji o licencji (także FreeType, ENet, mbedTLS itd. wg `COPYRIGHT.txt` Godota) |
| godot-cpp 4.5 | MIT | tak (w GDExtension) |
| Python 3, numpy, Pillow | PSF, BSD-3, MIT-CMU | tak, jeśli dołączymy konwerter z interpreterem (np. PyInstaller) – wtedy dołączamy ich licencje |
| PySide6 (Qt 6) | LGPL-3.0 | launcher; zgodne z GPLv3 (w paczce samodzielnej: dołączyć licencje Qt) |
| py7zr | LGPL-2.1-or-later | launcher (archiwa modów); zgodne z GPLv3 |
| SQLite (moduł `sqlite3` Pythona) | domena publiczna | – |
| pytest, scons | MIT | nie (narzędzia deweloperskie) |
| Khronos glTF-Validator (npm) | Apache-2.0 | nie (tylko testy) |


## Grafiki launchera

* `launcher/resources/banner.png` (pejzaż) i `launcher/resources/preview.png` (ilustracja miasta) — wycinki
  z grafiki referencyjnej launchera, którą autor projektu wygenerował w ChatGPT (sesja 3, 2026-11-15).
  Nie pochodzą z gry. Wycięte bez godła, tytułu i podpisu. Warunki OpenAI przypisują prawa do wyników
  użytkownikowi; przed publicznym wydaniem warto to jeszcze potwierdzić w aktualnych warunkach.
* `launcher/resources/openmwgodot.png`, godło, ikony, pejzaż i podgląd proceduralny (zapasowe) — własne,
  rysowane kodem.
* `launcher/resources/godot/icon.svg` — oficjalna ikona Godot Engine z repozytorium Godota
  (`misc/logo/icon.svg`), © 2017 Andrea Calabró, licencja CC BY 4.0 (`launcher/resources/godot/LICENSE.txt`).
  W stopce panelu bocznego wyświetlana w wersji szarej, jak w grafice referencyjnej (zmiana: tylko kolory,
  przeliczane w `art.godot_logo`; plik SVG w repozytorium jest niezmieniony), jako odnośnik do https://godotengine.org; uznanie autorstwa
  w podpowiedzi i w oknie „O projekcie”. Użycie zgodne z polityką znaków towarowych Godot Foundation
  (logo jako odniesienie do silnika, bez sugerowania oficjalnego produktu).
* Logo *Morrowind* / *The Elder Scrolls* (znak towarowy Bethesdy) nie jest częścią repozytorium,
  także w wersji narysowanej przez AI.

## Dane roślinności

* `converter/mwconv/data/remiros_rules.json.gz` — tabela reguł i liczników trawy Remirosa przeniesiona z forka
  OpenMW RLF (`apps/openmw/mwrender/remirosgroundcoverdata.cpp`, gałąź `0.5-world`, 3bfa4c3), wygenerowana przez
  MCP-openMW z wtyczek Remiros' Groundcover 4.1. Zawiera wyłącznie agregaty (gęstości na teksel, udziały statyk,
  liczby roślin w polach 128×128 j., odciski terenu) – bez modeli, tekstur i współrzędnych pojedynczych roślin.
  Modele i tekstury trawy dostarcza gracz (mod Remirosa); nie są częścią repozytorium.
