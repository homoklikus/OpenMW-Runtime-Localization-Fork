# MCP — etap 2c: trawa Remirosa w forku (reguły tekstur + mapa liczników, pach75)

**Status:**
- MCP 0.4.0: **sprawdzony na Debianie 13** (2026-11-14 15:19): 76/76, `srcmanifest` zgodny, integracja 58/58.
- Zmiana silnika (`pach75`): przygotowana i sprawdzona offline, ale **niezastosowana**. Czeka na budowę i test w grze.

| | |
|---|---|
| Wersja MCP | `openmw-mcp 0.4.0`, hash drzewa `93f8275f5bcec353de73acd52a3f4fb129722affd204c55bd80a119d0095ec30` |
| Zmiana silnika | `Fork/experiments/remiros-texture-2026-11-14/pach75-remiros-texture-groundcover.py` (poza repozytorium do czasu akceptacji) |
| Baza forka | `groundcover.cpp` z `5629d385` (sha256 `59f577fb…`) |
| Źródło danych | Remiros' Groundcover 4.1, Core OpenMW + 01b Thicker Grass (7 pluginów; sumy SHA-256 w nagłówku danych) |

## Decyzje (użytkownik, 2026-11-14)
- Tabela wkompilowana w C++. Obejmuje wszystkie 7 pluginów. Stare, ręcznie strojone profile AI/AL/BC/GL/WG są usunięte.
- Wierność: dokładne liczniki na teksel, pod warunkami:
  - liczniki działają tylko dla zgodnego terenu i tekstur;
  - zmienione komórki lub teksele przechodzą na reguły proceduralne;
  - **żadnych współrzędnych pojedynczych roślin z ESP**.

## Jak Remiros rozmieszcza trawę (ustalone z danych przez MCP)
| Cecha | Wynik |
|---|---|
| Klucz | **tekstura LAND**. Każda ze 102 statyk należy do jednej z 39 tekstur, a każda tekstura do jednego pluginu |
| Gęstość | stała na teksel dla tekstury (Solstheim dokładnie 36,000; zmienność między komórkami 1–30%) |
| Pozycja | losowa (najbliższy sąsiad 43,9 j. wobec 43,0 j. dla rozkładu Poissona). Przy krawędzi teksela do ±0,3 teksela przenikanie z sąsiedniej tekstury |
| Zbocze | **bez filtru** (akceptacja ≈1 do 60°) |
| Obiekty, ścieżki | **bez omijania** (gęstość przy obiektach ×1,03–1,2) |
| Woda | brak trawy przy z = teren + 23 ≤ 0; rośliny są na płyciznach do ok. −15 |
| Skala | równomierna w zakresie statyki (np. 1,26–1,61) |
| Wysokość | +23 j. nad terenem (10 statyk Ashlands: +25) |
| Obrót | według normalnej terenu: `rotX = asin(n.y)`, `rotY = atan2(−n.x, n.z)` (p90 różnicy 0,06 rad) + losowy obrót Z |
| Wycięcia | autor usunął trawę z części miejsc: 5,8% tekseli z regułą ≥ 4/teksel nie ma żadnej rośliny |

## Algorytm w forku
Dla każdego teksela komórki:
1. **Tryb liczników** — gdy odcisk wysokości LAND (FNV-1a po `lround` 65×65 wierzchołków) zgadza się z zapisanym, a tekstura teksela jest ta sama co w danych:
   - dokładnie tyle roślin, ile miał Remiros;
   - pozycje losowe w tekselu (do 4 prób, gdy wypadną pod wodą);
   - model według tekstury w punkcie przesuniętym o ±0,3 teksela.
2. **Tryb reguł** — w pozostałych przypadkach (zmieniony teren lub tekstura, brak wpisu): gęstość tekstury na teksel, pozycje w tekselu poszerzonym o 0,3 z każdej strony.
3. W obu trybach:
   - model według udziałów statyk tej tekstury;
   - skala z zakresu statyki;
   - z = teren + przesunięcie statyki;
   - obrót według normalnej;
   - gęstość mnożona przez `world.cfg [Flora] density`.

Ziarna są deterministyczne (komórka, teksel, numer rośliny). Filtr granic chunku działa jak `isInChunkBorders`.

Dane zawierają tylko agregaty: 39 reguł tekstur, 102 statyki (model, udział, skala, +z), 715 komórek z odciskiem terenu i 90 210 wpisami „teksel – tekstura – liczba”. Plik danych C++ ma 950 KB.

## Weryfikacja offline
| Test | Wynik |
|---|---|
| Liczba roślin, cały świat (emulacja, tryb liczników) | **828 667 / 830 457 (99,78%)** |
| Odchyłka na komórkę (komórki ≥300 roślin) | mediana **0,11%**, p90 0,76%, max 3,5% |
| Rozkład modeli, cały świat | odległość TV **0,0044**; na komórkę mediana 0,034 (losowanie) |
| Dla porównania: same reguły tekstur | odchyłka/komórkę mediana 10,3%, p90 24% |
| Rdzeń C++ vs emulacja Python (44 komórki, prawdziwe dane) | **64 349 roślin identycznych bajt w bajt** (`-Wall -Wextra -Werror`) |
| Testy jednostkowe (`tests/test_remiros.py`, 7) | odcisk terenu, reguły, liczniki i wycięcia, przejście na reguły przy zmianie terenu lub tekstury, woda, brak modeli, zgodność C++↔Python |
| Test integracyjny | VM (atrapa `flatpak info`) 58/58; **Debian 13 (prawdziwy Flatpak) 58/58**, w tym emulacja po pach75 = Remiros ±3% w (2,−10), (−24,19), (15,−9) |

Wcześniejsze porównanie starego generatora z Remirosem (0,55–3,21 zależnie od regionu, 35% roślin poza profilami) opisuje [etap 2c — flora forka](2026-11-14-etap2c-flora-forka.md). Po pach75 te różnice znikają, bo generator obejmuje wszystkie 7 obszarów, łącznie z Solstheimem, Azura's Coast i Sheogoradem.

## Zmiany w forku (pach75)
- Nowe pliki w `apps/openmw/mwrender/`:
  - `remirosgroundcovergen.hpp` — rdzeń, wzorzec w `tools/MCP-openMW/cpp/`;
  - `remirosgroundcover.{hpp,cpp}` — adapter do `TerrainStorage` i VFS;
  - `remirosgroundcoverdata.{hpp,cpp}` — dane.
- `groundcover.cpp`: −1011 linii (profile AI/AL/BC/GL/WG, ich regiony, wagi i skale). Gdy w VFS są modele `meshes/grass/rem_*.nif`, flora proceduralna = generator Remirosa. W przeciwnym razie zostaje ogólna flora proceduralna, z niezmienionym zachowaniem i wykluczeniami. Log: `Procedural flora: Remiros texture rules (pach75): …`.
- `groundcover.hpp` (członek `mRemiros`), `apps/openmw/CMakeLists.txt`.
- Pluginowy Groundcover (`source=groundcover/hybrid`) bez zmian. Oficjalne OpenMW bez zmian.

MCP rozpoznaje stan zmiany: `openmw_groundcover_mode` → `remiros_texture_rules: {in_source, in_binary}` (znacznik w binarce).

## Ograniczenia
- Silnik liczy wysokość w `getProceduralHeightAt` (float), emulacja w float64. Mogą różnić się pojedyncze rośliny tuż przy progu wody. Rdzeń C++ jest z emulacją identyczny przy tym samym terenie.
- Mapa liczników odpowiada waniliowemu terenowi i tej wersji Remirosa. Mody krajobrazu przełączają zmienione komórki lub teksele na reguły (przewidywana odchyłka jak dla samych reguł: około 10% na komórkę).
- Modele muszą być w VFS jako `meshes/grass/<nazwa>.nif` (w profilu `fork-test`: `remiros_procedural_test`, wszystkie 26 obecne).
- Budowy i testu w grze jeszcze nie było.

## Następne kroki
1. ~~Debian: testy MCP 0.4.0~~ (zaliczone), commit MCP i dokumentacji na `0.5-world`.
2. Gałąź `world-remiros-texture`: `pach75 --apply`, budowa, test w grze (log, komórki (2,−10), (−24,19), (15,−9) obok referencji Flatpak).
3. Po akceptacji: commit zmiany silnika i merge (wykonuje użytkownik).
