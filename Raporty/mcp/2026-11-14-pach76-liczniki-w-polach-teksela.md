# MCP 0.6.0 + pach76: liczniki Remirosa w polach 4×4 teksela i per statyka

| | |
|---|---|
| Data | 2026-11-14 |
| Wersja MCP | `openmw-mcp 0.6.0`, hash drzewa: patrz tabela etapów w `README.md` |
| Zmiana silnika | `pach76-remiros-subtexel-counts.py` (`Fork/experiments/remiros-subtexel-2026-11-14/`), na gałęzi `world-remiros-texture` po pach75 (`94e5fb45`) |
| Status | zbudowane, sprawdzone w grze (Debian 13, 2026-11-14 17:24) i zatwierdzone; commit `5ead2e90` na gałęzi `world-remiros-texture` (niescalonej z `0.5-world`) |

## Skąd ta zmiana
Porównanie zrzutów (etap 3) pokazało na Solstheimie zielone kępki trawy w oficjalnym OpenMW, których fork nie miał. Analiza w MCP:
- zielone kępki to statyka z modelem `rem_sol_grass_01` (zielona tekstura `tx_grass_solstheim_01`), biała trawa to `rem_sol_grass_02`; pliki w forku są identyczne z modem (SHA-256);
- Remiros miesza modele w obrębie teksela (na `Tx_BM_grass_snow_02a` 89% `_02`, 11% `_01`), a pach75 losował model według tekstury w punkcie, więc lokalny miks się rozjeżdżał;
- pach75 rozkładał rośliny po całym tekselu (512 j.), a autor często grupuje je w części teksela. Fork pokazywał trawę tam, gdzie Remiros jej nie ma (Azura's Coast), a obok rzadszą trawę.

Zgodnie z decyzją z 2026-11-14 przygotowano to jako osobny patch.

## Co się zmienia
**Dane (agregaty, bez współrzędnych roślin):** dla każdego teksela ze zgodnym terenem — tekstura i lista grup `(pole podsiatki 4×4, statyka, liczba roślin)`. Pole ma 128×128 j. Kodowanie: wpis `teksel | nazwa<<8 | liczba_grup<<16`, grupa `pole | statyka<<4 | liczba<<12`.

**Generator (tryb liczników):** dla każdej grupy dokładnie zapisana liczba roślin tej statyki (przy gęstości < 1 proporcjonalnie, część ułamkowa losowana), pozycje losowe w polu, do 4 prób, gdy punkt jest pod wodą. Skala, wysokość nad terenem i obrót jak w pach75.

**Bez zmian:**
- sprawdzanie odcisku terenu komórki i tekstury teksela — gdy się nie zgadzają, działa tryb reguł z pach75 (gęstość tekstury, rozrzut ±0,3 teksela, model wg udziałów);
- brak filtru zbocza i omijania obiektów, jak w modzie;
- adapter, `groundcover.cpp`, CMake.

## Wyniki offline (Remiros 4.1, teren Morrowind + Tribunal + Bloodmoon + UMOPP)
| Kontrola | pach75 | pach76 |
|---|---|---|
| Solstheim (−24,19), faktyczny kadr, 150–600 j.: zielone `_01` / wszystkie | 1 / 32 (Remiros 8 / 42) | 8 / 46 |
| Azura's Coast (15,−9), faktyczny kadr, 150–600 j. | 5 roślin (Remiros 0) | 0 |
| Bitter Coast (−5,−3), faktyczny kadr, 150–600 j. | 14 (Remiros 19) | 20 |
| 60 losowych komórek: suma roślin | — | 78 093 (Remiros 78 109) |
| 60 losowych komórek: różnica na komórkę | — | mediana 0%, maks. 0,43% |

Pozostałe różnice wynikają z punktów pod wodą i granic komórek.

**Zgodność C++ ↔ Python:** rdzeń `remirosgroundcovergen.hpp` skompilowany z danymi pach76 (`g++ -std=c++20 -O2 -Wall -Wextra -Werror`) daje dla 5 komórek z prawdziwym terenem (Solstheim, Azura's Coast, Bitter Coast, (2,−6), (−10,10)) te same 15 525 roślin co emulacja w Pythonie, bit w bit.

**Testy MCP:** 85 (VM). Nowy test `test_counts_keep_subtexel_cells_and_static_mix` sprawdza liczby w polach 128 j. per model i pomijanie statyki bez modelu. Do tego test zgodności C++ na danych syntetycznych i regresja `_capture_plans` z mapą liczników.

**Rozmiar:** 626 204 grup; `remirosgroundcoverdata.cpp` ok. 6 MB (pach75 ok. 1 MB), w binarce ok. 2,5 MB.

## Pozostałe zmiany MCP 0.6.0
- `remirosrules`: `SUB = 4`, `static_order`, nowy format liczników (`entries` z grupami, `groups`, `sub`), generator jak w C++.
- `openmw_remiros_export` zapisuje domyślnie do `Fork/experiments/remiros-subtexel-2026-11-14/files`; katalog pach75 zostaje jako zapis historyczny.
- `openmw_groundcover_mode` / `openmw_remiros_compare`: rozpoznają pach76 w binarce (`pach76_subtexel_counts_in_binary`).
- `openmw_remiros_rules`: statystyka liczników z liczbą grup.
- Poprawka błędu z wersji roboczej: pętla w `_capture_plans` nadpisywała zmienną środowiska (wykryte przy pierwszym uruchomieniu na Debianie, przed jakimkolwiek przebiegiem).

## Test w grze (Debian 13, 2026-11-14 17:23, `2026-11-14-172349-porownanie`)
- Budowa i instalacja: `install.sh` bez błędów. W logu forka: `Procedural flora: Remiros texture rules (pach75): Remiros 4.1 texture rules: 39 textures, 102 statics, 715 count cells, 626204 count groups (4x4 sub-texel, per static, pach76); MCP 0.6.0; usable textures=39, resolved models=26, statics without model=0`.
- Porównanie zrzutów (MCP etap 3, kamera z kontrolą zasłonięcia), oba silniki 3/3 ujęcia, bez błędów:
  - **Solstheim (−24,19):** układ pasów białej trawy, gołych łat śniegu i zielonych kępek odpowiada oryginałowi. Pojedyncze kępki stoją w innych miejscach w obrębie pola 128 j., zgodnie z założeniem.
  - **Bitter Coast (−5,−3):** praktycznie identycznie.
  - **Azura's Coast (15,−9):** skupiska grzybów i trawy w tych samych miejscach; goła skała na pierwszym planie po obu stronach.
- Różnice tekstur terenu wynikają z Morrowind Enhanced Textures 6.1 w profilu forka (bez związku z trawą).

## Ograniczenia
- Pozycja w polu 128 j. jest losowa, więc pojedyncze kępki nie stoją tam, gdzie u autora. To świadomy warunek (bez kopiowania współrzędnych).
- Prefiks wpisu w logu nadal brzmi „(pach75)”, bo pochodzi z `groundcover.cpp`. Wersję formatu rozpoznaje dalsza część wpisu („pach76”) i MCP (`pach76_subtexel_counts_in_binary`).
