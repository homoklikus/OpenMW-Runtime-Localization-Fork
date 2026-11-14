# MCP — etap 2c: proceduralna flora forka offline i porównanie z Remirosem

**Status: sprawdzony na Debianie 13 (2026-11-14 14:36): 69/69, `srcmanifest` zgodny (`1e8fc71f…`), integracja 53/53. Wersja 0.3.0 nie była commitowana osobno — wchodzi w 0.4.0 razem z [trawą Remirosa (pach75)](2026-11-14-etap2c-trawa-remirosa-pach75.md). Opisany tu generator to stan forka SPRZED pach75.**

| | |
|---|---|
| Wersja pakietu | `openmw-mcp 0.3.0` |
| Hash drzewa źródeł | `1e8fc71f97da818ab2f8e67b874f49e01d7955594a9e5297e416b35822cba23b` |
| Baza w Git | `478677cf` (0.2.1, bez `__init__.py` — zob. dokument o wersjonowaniu); zmiany 0.3.0 jeszcze niezacommitowane |
| Fork | `0.5-world`, `apps/openmw/mwrender/groundcover.cpp` (`Groundcover::collectInstances`), `terrainstorage.cpp` |

## Nowe narzędzia
| Narzędzie | Co robi |
|---|---|
| `openmw_fork_flora_cell` | emulacja generatora forka w komórce: profil regionalny, liczba kandydatów, odrzucenia według przyczyny, modele, skale, parametry generatora (gęstość, pula, aktywne profile, wzór ziarna) |
| `openmw_fork_flora_region` | to samo w prostokącie świata, w tych samych granicach co `openmw_groundcover_region` |
| `openmw_flora_compare` | jedna komórka obok siebie: Remiros (oficjalny Groundcover) i fork |
| `openmw_flora_coverage` | cały świat: które komórki Remirosa fork obsługuje, ile instancji traci w pozostałych |

## Co odwzorowano z kodu forka
- Ziarno kandydata `cellX·0x9e3779b9 ^ cellY·0x85ebca6b ^ index·0xc2b2ae35` (uint32), `hash32`, `random01` (24 bity), siatka `ceil(√N)` z jitterem, filtr granic chunku. **Zgodność bit w bit sprawdzona** z programem w C skompilowanym z tych samych lambd (test `test_hash_and_seed_match_c_reference`).
- Liczba kandydatów: 32768 ogólnie, AI 4096, AL/BC/GL/WG 8192, razy gęstość z `world.cfg [Flora]` (`std::lround`).
- Profile: komórka musi mieć rekord CELL. AI, BC i WG są wybierane po regionie (RGNN). AL i GL po regionie albo, zapasowo, gdy co najmniej 2 z 9 próbek tekstur LAND zawierają `tx_al_`/`tx_ashlands_` lub `tx_gl_`. Gdy aktywny jest którykolwiek profil Remirosa, komórki spoza profili nie dostają roślinności.
- Odrzucenia: wysokość ≤ 1 (woda), nachylenie (45° dla AI/AL/GL, 28° dla pozostałych), waga powierzchni (ogólna, AI, AL) i dwa losowania akceptacji (miejsce bazowe i klaster o promieniu 0).
- Wybór modelu (AI według tekstury z wagami z Rem_AI.esp; AL 45/45/10; BC, GL i WG równo) oraz skale profili.

## Czego nie odwzorowano (wynik forka jest górną granicą)
- Wykluczenia obiektów sceny w promieniu `exclusion_distance` (`collectFloraExclusions`) — wymagają granic modeli z NIF (etap 2b).
- Wykluczenia ścieżek PGRD (`collectPathgridExclusions`). Kandydatów na teksturach, na których silnik sprawdza ścieżki, liczymy osobno (`pathgrid_check_candidates`).
- Teren liczony w float64 (pozycje i losowania w float32). Przypadki dokładnie na progu mogą się różnić pojedynczymi instancjami.
- Skala modeli spoza profili Remirosa (wymaga granic NIF). W trybie profili Remirosa skala profilu modelu to 1.0, jak w silniku.

## Wyniki na prawdziwych danych (profil `fork-test`, pula `RLF_FLORA_POOL=all`, gęstość 1.0)

### Pokrycie świata (`openmw_flora_coverage`)
Fork ma aktywne profile AI, AL, BC, GL i WG (pula 22 modeli). Remiros ma referencje w 700 komórkach zewnętrznych, co daje 830 457 instancji przy gęstości 1.0.

| | Komórki | Instancje Remirosa |
|---|---|---|
| obsługiwane przez fork | 477 | 538 186 (65%) |
| **nieobsługiwane** | **223** | **292 271 (35%)** |

Największe braki: Solstheim (Hirstaang Forest 118 799, Isinfier Plains 99 705, Felsaad Coast, Brodir Grove, Thirsk — bez żadnego profilu), Azura's Coast (91 z 101 komórek; 10 obsługuje zapasowe próbkowanie AL/GL), Sheogorad (59 z 69), Molag Mar. Komórka (15, −9), dotychczasowe odniesienie, leży w Azura's Coast — fork nie generuje tam niczego.

### Komórki w regionach z profilem (`openmw_flora_compare`, 15 komórek z każdego regionu)
| Region | Remiros | Fork (górna granica) | Fork/Remiros (suma) | Mediana na komórkę (min–max) | Główne przyczyny odrzuceń |
|---|---|---|---|---|---|
| Ascadian Isles | 18 982 | 22 290 | 1,17 | 1,19 (0,78–1,70) | woda 40%, waga 0 — 36% |
| Ashlands | 14 472 | 46 439 | **3,21** | 2,70 (1,61–6,20) | waga 0 — 66%, nachylenie 34% |
| Bitter Coast | 16 419 | 20 483 | 1,25 | 1,24 (0,23–2,16) | woda 72%, nachylenie 15% |
| Grazelands | 25 126 | 39 990 | 1,59 | 1,71 (0,76–2,38) | waga 0 — 56%, losowanie 33% |
| West Gash | 10 760 | 5 945 | **0,55** | **0,16** (0,00–1,87) | woda 35%, waga 0 — 26%, **nachylenie 25%** |

Ponieważ wykluczenia obiektów nie są jeszcze odwzorowane, rzeczywiste liczby forka będą niższe. Dotyczy to zwłaszcza Ashlands i Grazelands, gdzie fork już teraz przekracza Remirosa.

### Nachylenie: Remiros vs limit forka
Udział instancji Remirosa na zboczach powyżej limitu forka (próbka co 7. instancja):

| Region | Limit forka | Instancje Remirosa ponad limitem | Ponad 45° |
|---|---|---|---|
| West Gash | 28° | **34,4%** | 9,7% |
| Bitter Coast | 28° | **18,4%** | 0,8% |
| Ashlands | 45° | 7,2% | 7,2% |
| Ascadian Isles | 45° | 1,8% | 1,8% |
| Grazelands | 45° | 1,0% | 1,0% |

Limit 28° dla WG i BC odcina dużą część miejsc, na których autor stawiał roślinność. To najbardziej prawdopodobne wyjaśnienie niedoboru w West Gash. Decyzja o zmianie należy do strojenia forka. MCP niczego w silniku nie zmienia.

### Wysokość instancji
Referencje Remirosa leżą stale około 23 jednostki nad terenem (etap 2). Fork stawia instancje dokładnie na wysokości terenu (`getProceduralHeightAt`). `alignRemirosAiToTerrain` zmienia tylko obrót. Wpływ na wygląd wymaga porównania wizualnego. Tu zapisujemy go jako różnicę danych, a nie błąd.

## Testy
`tests/test_stage2c.py` — 21 testów na syntetycznych danych (w tym wykrywanie plików źródłowych ignorowanych przez Git):
- hash i ziarno zgodne z C;
- tabela wag powierzchni i reguła ścieżek;
- granice wyboru modeli AI, kompletność puli;
- płaski teren z trawą — każdy kandydat przyjęty (8192 / 4096 przy gęstości 0.5);
- odrzucenia: woda, skała, ziemia (≈0,35²), region bez profilu, brak CELL, tryb ogólny poza regionami;
- zapasowe próbkowanie GL;
- addytywność regionów (dwie połowy = cała komórka);
- rejestracja narzędzi w serwerze.

| Środowisko | Jednostkowe | Integracja |
|---|---|---|
| VM Cowork | 69/69 | 53/53 (atrapa `flatpak info`) |
| Debian 13 | — | — |

## Następne kroki
1. Wykluczenia ścieżek z PGRD (prosty parser; daje dokładniejszą liczbę na drogach).
2. Parser NIF (etap 2b), wykluczenia obiektów i pełna liczba instancji forka.
3. Potwierdzenie w silniku przez minimalną instrumentację forka (licznik instancji na komórkę, za flagą). Patch w konwencji `pachXX-*.py` będzie przedstawiony do akceptacji przed zastosowaniem.
