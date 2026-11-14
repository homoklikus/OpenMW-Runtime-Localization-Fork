# MCP — etap 2: teren (LAND) i oficjalny Groundcover offline

**Status:** funkcje terenu i baseline **sprawdzone na Debianie 13** (0.2.0: 46/46, hash zgodny). Wersja 0.2.1 (narzędzie regionu, test integracyjny, kod w Git) **sprawdzona na Debianie** (testy jednostkowe, integracja 44/44).

| | 0.2.0 | 0.2.1 |
|---|---|---|
| Hash drzewa źródeł | `26512797b6a68e7e95d0f414097a2203754e3988129ee921be73b7f101b96af4` | `560428b4b09cef0e4bfc1e49042f6dc17305d991c437b85a577b95fed1eb9a12` |
| Testy jednostkowe | Debian 13: 46/46 | VM: 48/48; Debian 13: zaliczone |
| Test integracyjny (protokół MCP) | — | VM z atrapą `flatpak info`: 44/44; Debian 13: **44/44** |
| Położenie kodu | `MCP-openMW/` (poza Git) | `tools/MCP-openMW/` w tym repozytorium |

Odniesienie: OpenMW 0.51.0 (`f4bec414`), fork `0.5-world`. Kontrola wersji: `python -m openmw_mcp.srcmanifest --check`. Drzewo 0.2.0 nie jest zachowane w Git — zmiany 0.2.1 wobec niego: narzędzie `openmw_groundcover_region`, automatyczne wyznaczanie katalogu projektu, informacja Git w `srcmanifest`, skrypt `scripts/integracja.py`, 2 nowe testy.

## Co dodaje etap 2
Nowe moduły: `land.py` (LAND/LTEX), `gcbaseline.py` (emulacja oficjalnego Groundcover). Wszystkie narzędzia tylko czytają.

| Narzędzie | Co robi |
|---|---|
| `openmw_land_cell` | teren komórki z `content=` profilu: który plugin dostarcza LAND (i co nadpisał), zakres wysokości, nachylenie, tekstury, opcjonalnie siatka 16×16 |
| `openmw_land_point` | wysokość, nachylenie i tekstura w punkcie świata |
| `openmw_groundcover_baseline` | ile instancji oficjalny Groundcover narysuje w komórce przy danej gęstości, z podziałem na pluginy i modele, skalą, teksturą i nachyleniem pod instancjami |
| `openmw_land_texture_mapping_check` | test hipotezy przesunięcia mapowania tekstur (opis niżej) |
| `openmw_groundcover_height_offset` | wysokość referencji groundcover względem terenu, osobno dla każdego pluginu |
| `openmw_groundcover_region` (0.2.1) | instancje, których pozycja leży w prostokącie świata `[x0,x1)×[y0,y1)`, także przypisane do sąsiednich komórek — wspólne granice do porównań z florą proceduralną |

## Źródła semantyki (kod silnika, nie inżynieria wsteczna)
- `components/esm3/loadland.cpp` — VHGT (offset + delty int8, ×8), VTEX zapisane blokami 4×4.
- `apps/openmw/mwworld/store.cpp` — LTEX mapowane per plugin (`(plugin, indeks)`), VTEX 0 = tekstura domyślna; ostatni LAND dla komórki wygrywa.
- `apps/openmw/mwrender/groundcover.cpp` (0.51.0) — `DensityCalculator` (float32, reset na komórkę), RefNum unikalny w obrębie pliku, kalkulator pomija usunięte referencje (linia 404), filtr granic chunku nie odrzuca referencji przypisanych do komórki.
- fork `terrainstorage.cpp` — `getProceduralHeightAt` (triangulacja „diamond”), `getSlopeDegreesAt`, `getLandTextureAt`.

## Testy
`tests/test_stage2.py` — 10 testów na syntetycznych rekordach (bez zasobów gry): dekodowanie VHGT, transpozycja VTEX (również odwrotność), LTEX per plugin i nadpisanie ID, nadpisanie LAND w kolejności ładowania, wysokość i nachylenie na płaszczyźnie, triangulacja w kwadracie parzystym i nieparzystym, tryby mapowania tekstur i przejście do sąsiedniej komórki, `DensityCalculator` (0.5, 0.25, 1.0), dobór instancji jak w silniku (RefNum w dwóch plikach, usunięte, bez modelu, poza granicą komórki, gęstość 0.5), przesunięcie wysokości, rejestracja narzędzi w serwerze.

| Środowisko | Wynik |
|---|---|
| VM Cowork (Python 3, mcp SDK) | 0.2.0: 46/46 · 0.2.1: 48/48 |
| Debian 13 | 0.2.0: **46/46**, `srcmanifest --check` zgodne (`26512797…`) · 0.2.1: zaliczone, zgodne (`560428b4…`), integracja 44/44 |

## Wyniki na prawdziwych danych (Morrowind + Tribunal + Bloodmoon, Remiros 4.1: Core OpenMW + 01b Thicker Grass)
Liczby zagregowane; pliki gry i modów nie są publikowane.

- Indeks: 1540 rekordów LAND, 159 mapowań LTEX; groundcover: 700 komórek zewnętrznych + 1 wnętrze (`Rotheran, Arena` w Rem_AC), 105 statyk.
- **Komórka (15, −9), gęstość 1.0: 1449 instancji** (Rem_AC 1044, Rem_WG 405), z tego 21 leży pozycyjnie poza komórką, ale silnik je rysuje, bo są przypisane do tej komórki. Gęstość 0.5 → 724.
- Teren (15, −9): wysokość −584…2424, średnie nachylenie 20,7°, maksymalne 52,2°.
- Rozkład nachylenia pod instancjami (15, −9): <5° 94, 5–10° 316, 10–15° 298, 15–20° 267, 20–28° 205, 28–35° 142, 35–45° 120, 45–60° 7.

To pierwsza powtarzalna liczba odniesienia dla oficjalnego Groundcover w tej komórce. Historycznych liczb 963/500 nie udało się odtworzyć ani tu, ani w etapie 1.

### Hipoteza przesunięcia tekstur — niepotwierdzona
Z kodu renderera (`gridsampling.hpp`, `material.cpp`) wyprowadzono hipotezę, że widoczna tekstura w punkcie odpowiada tekselowi przesuniętemu o ćwierć teksela (`X = floor(t − 0.25)`, `Y = floor(t + 0.25)`), a nie `floor(t)` jak w forku. Sprawdzono to na 836 265 referencjach Remirosa: gdyby hipoteza była trafna, rośliny danego modelu powinny częściej trafiać w jedną teksturę przy mapowaniu „render”.

| Mapowanie | Ważony udział najczęstszej tekstury |
|---|---|
| fork `floor(t)` | **0,6142** |
| hipoteza „render” | 0,5855 |

Mapowanie forka lepiej pasuje do rozmieszczenia autora dla większości modeli. **Hipoteza nie jest potwierdzona** — albo wyprowadzenie jest błędne, albo autor rozmieszczał względem danych VTEX, a nie widocznego obrazu. Nie wynika z tego błąd w forku. Rozstrzygnięcie wymaga porównania wizualnego (etap 5).

### Wysokość referencji względem terenu
Referencje we wszystkich trzech pluginach (Rem_AC, Rem_WG, Rem_Solstheim; próbka ok. 16,7 tys.) leżą **stałe ok. 23 jednostki nad terenem** (mediana 23,0, p90 24,3). Przy takim stałym przesunięciu dane nie rozróżniają triangulacji „diamond” od jednej przekątnej (mediana |dz| 23,00 w obu); poprawność triangulacji potwierdzają testy syntetyczne.

Do sprawdzenia w kolejnym kroku: czy proceduralna flora forka stawia modele na wysokości terenu bez tego przesunięcia. To pytanie badawcze, nie stwierdzony błąd.

## Ograniczenia
- To emulacja offline według kodu silnika, nie pomiar w działającym OpenMW. Potwierdzenie liczby instancji w silniku wymaga instrumentacji (etap 4) lub logów.
- Tryb `render` mapowania tekstur to hipoteza (patrz wyżej).
- Parser NIF odłożony do etapu 2b (bounding boxy i wysokości modeli — potrzebne m.in. do wyjaśnienia przesunięcia 23 j.).
- Fauna i lokalizacja YAML nie są jeszcze objęte narzędziami.

## Plan następnego kroku: emulacja proceduralnej flory forka (etap 2c)
Rozpoznanie w `apps/openmw/mwrender/groundcover.cpp` forka (`Groundcover::collectInstances`):
- Kandydaci są **deterministyczni na komórkę**: ziarno `base = cellX·0x9e3779b9 ^ cellY·0x85ebca6b ^ index·0xc2b2ae35`, `hash32` (xorshift-multiply), `random01` z 24 bitów; siatka `ceil(√N)` z jitterem. Chunk tylko odfiltrowuje pozycje, więc wynik dla komórki nie zależy od podziału na chunki — porównanie z pluginami w tych samych granicach jest możliwe offline.
- Liczba kandydatów: ogólnie 32768·gęstość, profil AI 4096, AL/BC/GL/WG 8192; przy aktywnym profilu Remirosa komórki spoza regionu nie dostają roślinności.
- Odrzucenia: wagi LAND/tekstur, nachylenie, ścieżki z PGRD (`collectPathgridExclusions`), obiekty sceny w odległości `exclusion_distance` (`collectFloraExclusions` — potrzebuje granic modeli, czyli parsera NIF z etapu 2b).

Kolejność: (1) port generatora do Pythona bez wykluczeń obiektów, z zapisem parametrów (gęstość, liczba kandydatów, profil, pula modeli, ziarna) w wyniku; (2) wykluczenia ścieżek z PGRD; (3) parser NIF i wykluczenia obiektów; (4) weryfikacja z silnikiem przez minimalną instrumentację forka (licznik instancji na komórkę, za flagą). Ta instrumentacja byłaby osobnym patchem w konwencji `pachXX-*.py` — ostatnie numery to `pach74s-FIX1…FIX7` (niezatwierdzony eksperyment Azura's Coast), więc numer zostanie ustalony przed przygotowaniem patcha. Kod oficjalnego OpenMW pozostaje bez zmian.

## Odtworzenie
```bash
cd "MCP-openMW"                                      # = Fork/repo/tools/MCP-openMW
.venv/bin/python -m pytest
.venv/bin/python -m openmw_mcp.srcmanifest --check   # 0.2.1: 560428b4…
.venv/bin/python scripts/integracja.py               # test przez protokół MCP na prawdziwych danych
```
