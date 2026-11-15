# Licencje i dystrybucja — analiza (sesja 1)

> To analiza techniczna, nie porada prawna. Przed publicznym wydaniem warto ją potwierdzić z prawnikiem.

## Zasoby Bethesdy

* Repozytorium, wydania, raporty i artefakty CI **nie zawierają** żadnych plików gry ani wyników ich
  konwersji. `.gitignore` wyklucza `*.esm/*.esp/*.bsa`, katalogi `Data Files` i wyniki.
* Wszystkie dane testowe są generowane kodem (`mwconv/synthetic*.py`): geometria, tekstury proceduralne,
  ESM/ESP „Synthville”. Można je publikować na licencji projektu.
* Raport konwersji gracza zawiera ścieżki i nazwy rekordów (metadane) — zostaje lokalnie u gracza.
* Model dystrybucji jak w OpenMW: gracz wskazuje własną legalną instalację, konwersja odbywa się lokalnie.

## Kod projektu

Obecnie: **MIT** dla całego repozytorium (konwerter, projekt Godot, wtyczka CS 2.0, GDExtension).
Konwerter jest implementacją własną, napisaną na podstawie publicznych opisów formatów:

| Źródło wiedzy | Licencja | Sposób użycia |
|---|---|---|
| NifTools `nif.xml` | BSD-3-Clause | opis formatu NIF (fakty o układzie pól) |
| UESP „Mod File Format” (TES3) | CC BY-SA (tekst) | opis formatu ESM/ESP/BSA – fakty, bez kopiowania tekstu |
| kod OpenMW 0.51 (fork RLF) | **GPLv3** | tylko odczyt w celu potwierdzenia konwencji (stała `UnitsPerMeter`, kolejność obrotów referencji, wzór triangulacji „diamond”, zerowanie transformacji korzenia NIF, semantyka skinu). Żaden fragment kodu nie został skopiowany ani przetłumaczony 1:1. |
| MCP-openMW (`tools/MCP-openMW` w forku) | w repozytorium GPLv3; nagłówek `nif.py` deklaruje przeniesienie układu rekordów „1:1 z components/nif/*.cpp” | **nie użyty jako kod** – traktuję go jako utwór zależny od GPL. Konsultowany wyłącznie jako opis formatu. |

### Decyzja do podjęcia przez Ciebie (wpływa na dalsze prace)

* **Zostajemy przy MIT** → nie wolno włączać kodu OpenMW (ani MCP-openMW) do MWGodot. Mechaniki
  (formuły walki, AI, MWScript) implementujemy samodzielnie na podstawie dokumentacji i obserwacji.
* **Przechodzimy na GPLv3 (całość lub runtime)** → możemy legalnie przenosić komponenty OpenMW
  (np. interpreter MWScript, mechaniki, loader NIF w C++ jako GDExtension). Godot (MIT), godot-cpp (MIT),
  numpy (BSD), Pillow (MIT-CMU) są zgodne z GPLv3. Konsekwencje: każdy rozpowszechniany build musi mieć
  dostępny kod źródłowy; GPL praktycznie wyklucza wydania na konsole (zamknięte SDK).
* Wariant mieszany: konwerter i CS 2.0 MIT, runtime gry GPLv3 — możliwy, jeśli granica jest czysta
  (osobne programy komunikujące się plikami; `world/` i GLB to dane, nie linkowanie).

Rekomendacja: dopóki nie potrzebujemy kodu OpenMW — MIT (większa swoboda). Gdy dojdziemy do MWScript
i mechanik, warto wrócić do decyzji, bo przepisywanie interpretera od zera to duży koszt.

## Zależności i narzędzia

| Komponent | Licencja | Dystrybuowany? |
|---|---|---|
| Godot 4.5.1 | MIT | tak (silnik/eksport) – wymaga zachowania informacji o licencji (także FreeType, ENet, mbedTLS itd. wg `COPYRIGHT.txt` Godota) |
| godot-cpp 4.5 | MIT | tak (w GDExtension) |
| Python 3, numpy, Pillow | PSF, BSD-3, MIT-CMU | tak, jeśli dołączymy konwerter z interpreterem (np. PyInstaller) – wtedy dołączamy ich licencje |
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
