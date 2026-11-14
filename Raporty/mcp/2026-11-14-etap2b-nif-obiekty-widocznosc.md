# MCP — etap 2b: modele NIF, obiekty w świecie i wybór punktów obserwacji

| | |
|---|---|
| Data | 2026-11-14 |
| Wersja MCP | `openmw-mcp 0.7.0`, hash drzewa `22731e7b896ddb2937b478391d8be075815aa2cf5bba59181fb18118b3cdc58f` |
| Baza | `0.5-world` = `80b82e84`; generator Groundcover forka bez zmian; bez zmian w silniku i w oficjalnym OpenMW |
| Status | sprawdzone na Debianie (104 testy, integracja) i w grze (granice 9457 obiektów, zrzuty z przebiegu 18:58); poprawki po teście potwierdzone (integracja 62/62, przebieg `2026-11-14-191745-porownanie`: oba kadry c15_-9 z tego samego miejsca, bez zmiany kamery); **zatwierdzone**, commit `be3df967` |

## Cel
Claude ma sam ustalać, jakie obiekty stoją w komórce, jakie mają modele i granice oraz czy zasłaniają kamerę. Na tej podstawie ma wybierać punkty obserwacji do porównań oficjalny OpenMW / fork.

## Architektura
| Moduł | Rola | Źródło semantyki w OpenMW 0.51.0 |
|---|---|---|
| `nif.py` | odczyt NIF 4.0.0.2/4.0.0.0 (80 typów rekordów), drzewo węzłów, transformacje, kształty rysowane / pomijane, granice | `components/nif/*.cpp` (układ rekordów), `components/nifosg/nifloader.cpp` (co jest rysowane) |
| `bsa.py` (`Tes3Bsa`, `VfsReader`) | pliki z BSA TES3 i katalogów `data=`, ostatni dostawca wygrywa | rejestracja archiwów VFS: BSA, potem katalogi w kolejności |
| `objects.py` | referencje w komórkach zewnętrznych, rekordy bazowe z modelem, macierz świata | `components/esm3/loadcell.cpp` (`adjustRefNum`, MVRF/CNDT), `cellref.cpp` (XSCL 0,5–2,0), `objectpaging.cpp` / `Misc::Convert::makeOsgQuat` (obrót) |
| `scene.py` | teren jako siatka wysokości (numpy, triangulacja jak `getProceduralHeightAt`) + obiekty z geometrią w świecie | `terrainstorage.cpp` forka, `land.py` |
| `visibility.py` | promienie w polu widzenia: teren, woda, trójkąty obiektów; widoczność obszaru celu; ocena i wybór kamery | kamera Lua (`camerabindings.cpp`): yaw = kurs, pitch > 0 = w dół; FOV pionowy 60°, 16:9 |
| `geomverify.py` | weryfikacja niezależna: granice z silnika (Lua) i niebo na zrzutach | `RenderingManager::getCullSafeBoundingBox`, `CullSafeBoundsVisitor` |

Najważniejsze reguły przeniesione z kodu silnika:
- **Transformacja węzła NIF:** p_rodzic = t + s·R·p (R z 9 liczb wierszami). Transformacja korzenia (rekord 0) jest zerowana, chyba że węzeł nazywa się „Bip01”.
- **Rysowane kształty:** silnik pomija poddrzewo RootCollisionNode, węzły z flagą Hidden bez NiVisController, nieaktywne dzieci NiSwitchNode, „tri editormarker” przy znaczniku MRK oraz „shadow…”. Cząsteczki nie zasłaniają kadru (silnik pomija je też w granicach).
- **Obrót referencji przy rysowaniu:** R = Rx(−x)·Ry(−y)·Rz(−z). **Rozbieżność w silniku:** `getCullSafeBoundingBox` (Lua `getBoundingBox`) składa obrót obiektów stronicowanych w odwrotnej kolejności (Rz·Ry·Rx). Dla obiektów pochylonych w osiach X/Y granice z Lua mogą więc nie pasować do obrazu. MCP liczy oba warianty i raportuje, który pasuje.
- **Referencje:** górny bajt FRMR ≠ 0 i ≤ liczby plików MAST oznacza nadpisanie referencji pliku nadrzędnego; w przeciwnym razie to nowa referencja. Późniejszy plugin wygrywa, DELE usuwa referencję, MVRF+CNDT przenosi ją do innej komórki.

Bez osobnego silnika 3D: zasłanianie liczone jest promieniami (domyślnie 64×36 na kadr) na rzeczywistych trójkątach rysowanych kształtów, bez przybliżeń prostopadłościanami.

## Nowe narzędzia
| Narzędzie | Do czego |
|---|---|
| `openmw_nif_inspect` | model z VFS: dostawca i nadpisania, granice z geometrii (AABB, „jak silnik”, kolizja, sfera), kształty z powodem pominięcia, kontrola sfer zapisanych w pliku |
| `openmw_cell_objects` | obiekty komórki po rozstrzygnięciu pluginów, granice w świecie, przekroczenie granic komórki, obiekty sąsiadów wchodzące do komórki |
| `openmw_view_analyze` | skład kadru, przeszkody z nazwą i odległością, widoczność obszaru celu, pewność oceny, maska ASCII |
| `openmw_view_suggest` | najlepszy punkt kamery i alternatywy (16 kursów × odległości × wysokości oczu, odrzucenie kamery nad wodą i w obiektach) |
| `openmw_geometry_verify` | porównanie granic z silnika i nieba na zrzutach z przewidywaniami MCP |

Zmiany w istniejących narzędziach:
- `openmw_capture_plan` / `openmw_capture_start` wybierają kamerę z obiektami (`use_objects=True`). Ocena trafia do `plan.json`, a przy błędzie wybór wraca do metody opartej na samym terenie.
- Skrypt Lua ujęć zapisuje do logu granice obiektów statycznych z komórek 3×3 (`RLF_BBOX`), a MCP zapisuje je w `<profil>/bounds.json`.

## Wyniki testów
**Testy automatyczne (VM):** 104, z czego 18 nowych w `tests/test_stage2b.py`. Sprawdzają:
- transformacje zagnieżdżone, obrót i niejednorodną skalę;
- wyjątek „Bip01” dla korzenia;
- reguły rysowania (kolizja, ukryty z kontrolerem i bez, switch, znacznik MRK, alfa);
- paski trójkątów i kontrolę zapisanych sfer;
- pliki puste, obce, ucięte i z nieznanym rekordem;
- BSA i nadpisanie pliku przez mod;
- nadpisanie, usunięcie i przeniesienie referencji oraz obcięcie skali;
- konwencję obrotów i różnicę ich kolejności;
- siatkę wysokości (zgodną z `land.height_at` co do 1e-6);
- zasłonięcie pełne, częściowe, przez alfę i przez teren;
- wybór kamery omijający mur i obiekt przekraczający granicę komórki;
- odczyt `RLF_BBOX` i porównanie granic.

**Parser NIF na rzeczywistych plikach:** 7479 modeli, 0 błędów. Każdy plik odczytany co do bajtu, bez nadmiarowych bajtów po liście korzeni. W tym:
- Morrowind.bsa: 5798 modeli (2,7 mln trójkątów, 4,4 s);
- Tribunal.bsa: 621;
- Bloodmoon.bsa: 901;
- mody z `Fork/mods` i `OpenMW/mods`.

**Świat gry (profil fork-test):**
- 1320 komórek zewnętrznych;
- 150 209 obiektów statycznych: STAT 119 557, CONT 22 839, ACTI 3531, LIGH 3054, DOOR 1228;
- 1593 modele, wszystkie odczytane;
- 2313 referencji bez modelu (światła bez siatki, znaczniki);
- 912 obiektów bez rysowanej geometrii (tylko kolizja/znaczniki);
- 10 659 obiektów wystających poza swoją komórkę.

Pełny przegląd trwa 18 s, wczytanie sceny dla komórki około 1 s, wybór kamery 1–5 s.

**Przykład nadpisania przez VFS:** `meshes/f/flora_tree_gl_02.nif` pochodzi z luźnego pliku w `Data Files/Meshes`, który nadpisuje wersję z `Morrowind.bsa`.

**Przykład modelu (`flora_tree_gl_02.nif`):**
- 140 rekordów, 34 kształty, z czego 33 rysowane;
- 1198 trójkątów, w tym 448 z alfą (liście);
- AABB 1448 × 773 × 1099 j., granice „jak silnik” 1516 × 820 × 1147 j., kolizja 465 × 267 × 700 j.;
- wszystkie 34 sfery zapisane w pliku obejmują wierzchołki.

### Weryfikacja niezależna — niebo na zrzutach z gry
Zrzuty z przebiegu `2026-11-14-175937-porownanie` (oficjalny OpenMW) porównano z niebem przewidzianym promieniami. Kamery z tego przebiegu wybierano jeszcze bez obiektów (MCP 0.6.0).

| Ujęcie | Niebo na zrzucie | Przewidziane (alfa zasłania / alfa przepuszcza) | IoU z obiektami | IoU sam teren |
|---|---|---|---|---|
| c5_-9 Ascadian Isles | 15,2% | 13,1% / 20,7% | 0,745 | 0,584 |
| c0_15 Ashlands | 2,4% | 3,7% / 3,7% | 0,635 | 0,406 |
| c12_11 Grazelands | 18,1% | 16,3% / 18,2% | 0,887 (0,945 z alfą) | 0,720 |
| c-7_12 West Gash | 29,0% | 27,9% / 28,1% | 0,927 | 0,822 |
| c-5_-3 Bitter Coast | 6,8% | 9,3% / 10,9% | 0,664 | 0,466 |
| c-24_19 Solstheim | 5,9% | 1,5% / 6,4% | 0,248 (0,455 z alfą) | 0,181 |
| c15_-9 Azura's Coast | 1,6% | 0% / 0% | 0 | 0 |

Wnioski:
- Geometria obiektów wyraźnie poprawia zgodność z obrazem we wszystkich ujęciach z niebem, więc modele są poprawnie umieszczone w świecie: pozycja, obrót, skala i kształty.
- Wartość z gry leży między dwoma wariantami liczenia alfy (Grazelands, Solstheim, Ascadian Isles). Liście sosen na Solstheimie przepuszczają niebo, dlatego dla geometrii z alfą wynik jest przedziałem.
- Na Bitter Coast przewidziane jest więcej nieba niż na zrzucie. Trawa Groundcover i mgła nie są modelowane jako przeszkody.
- Detektor nieba to prosty próg koloru: na c15_-9 bierze niebieską wodę za niebo. Ta miara jest orientacyjna.

### Weryfikacja niezależna — wybór kamery
Ujęcia z przebiegu 17:59, z kamerą wybraną według samego terenu, porównano z kamerą proponowaną przez `openmw_view_suggest`, przy tym samym celu:

| Ujęcie | Widoczność celu: stara → nowa | Bliskie zasłonięcie kadru: stare → nowe |
|---|---|---|
| c12_11 Grazelands | 0,45 → 0,59 | 43% → 0% (na zrzucie głaz zasłaniał lewą połowę) |
| c0_15 Ashlands | 0,83 → 1,00 | 27% → 0% |
| c-5_-3 Bitter Coast | 0,97 → 1,00 | 28% → 5% |
| c-24_19 Solstheim | 0,79 → 0,93 | 0% → 0% |
| c5_-9, c-7_12, c15_-9 | 0,90–1,00 → 1,00 | ≈0% |

Przewidywania MCP dla starej kamery w Grazelands zgadzają się ze zrzutem: `terrain_rocks_gl_01` 6 j. od kamery zajmuje lewą część kadru, w środku u góry stoi pień drzewa, niebo jest w prawym górnym rogu.

### Test na Debianie (2026-11-14 18:57)
- **pytest:** 104/104.
- **Test integracyjny:** 59 PASS, 2 FAIL. Nowe sprawdzenia etapu 2b przechodzą: obiekty Seyda Neen, dostawca modelu = zwycięzca VFS, `openmw_nif_inspect`. Oba FAIL dotyczyły flory sprzed pach75: pula modeli i profile regionalne AI/AL/BC/GL/WG nie istnieją od scalenia pach75/pach76. Sprawdzenia zastąpiono kontrolą pach75/pach76 w binarce i modeli Remirosa w VFS.

### Weryfikacja w grze — granice obiektów (przebieg `2026-11-14-185856-porownanie`)
Skrypt Lua zapisał granice wszystkich obiektów statycznych (STAT, ACTI, DOOR, CONT, LIGH) z komórek 3×3 wokół 7 ujęć: 9598 w forku, 9551 w oficjalnym OpenMW. MCP dopasował je po identyfikatorze referencji (RefNum). Przesunięcie indeksu pliku o 1 wynika z wbudowanego `builtin.omwscripts` na początku listy treści silnika i zostało wykryte automatycznie (`content_index_offset`). Wszystkie identyfikatory rekordów się zgadzają.

| | fork | oficjalny |
|---|---|---|
| porównane obiekty | 9457 | 9447 |
| brak w MCP | 0 | 1 |
| niezgodne ID rekordu | 0 | 0 |
| zgodne do 2 j. | **9404 (99,4%)** | **9404 (99,5%)** |
| mediana błędu | 0,008 j. | 0,008 j. |
| 95. percentyl | 0,019 j. | 0,019 j. |
| granice z obrotem w odwrotnej kolejności (obiekty pochylone) | 1315 | 1315 |

Co wynika z porównania o samym silniku:
- `getBoundingBox` liczy granice na grafie sceny **po optymalizatorze** OpenMW. Statyczne transformacje są spłaszczone, a geometria nieprzezroczysta połączona: 6907 obiektów pasuje do wariantu „cały model”, 2496 do wariantu „kształty osobno” (rośliny z alfą), 54 do grafu bez optymalizacji.
- Dla 1315 pochylonych obiektów silnik podaje granice z obrotem w kolejności odwrotnej niż przy rysowaniu. To potwierdza rozbieżność w `getCullSafeBoundingBox` opisaną wyżej.
- Pozostałe 53 obiekty to modele animowane i efekty (świetliki `photodragons.nif`, dym `chimney_smoke_small.nif`, płomienie pochodni), kilka krzewów i budynki Raven Rock (w Bloodmoonie zmieniane w trakcie gry). Ich kształt zależy od czasu albo skryptów.

Wniosek: **parser NIF, transformacje węzłów i referencji oraz rozstrzyganie pluginów/VFS dają geometrię zgodną z silnikiem** dla 99,4% obiektów, z dokładnością setnych części jednostki. Zasłanianie MCP liczy na trójkątach, nie na tych prostopadłościanach, więc warianty optymalizatora go nie dotyczą.

### Weryfikacja w grze — nowe kadry
W tym przebiegu kamery wybierał już `openmw_view_suggest`:

| Ujęcie | Ocena MCP | Widoczność celu | Pewność | Niebo na zrzucie / przewidziane | IoU (z obiektami / sam teren) |
|---|---|---|---|---|---|
| c5_-9 Ascadian Isles | 1,12 | 1,00 | 0,89 | 19,7% / 16,0–26,7% | 0,79 / 0,51 |
| c0_15 Ashlands | 1,12 | 1,00 | 1,00 | 14,5% / 13,8% | 0,90 / 0,77 |
| c12_11 Grazelands | 0,68 | 0,55 (głazy, drzewo) | 0,92 | 23,9% / 20,4–27,5% | 0,81 / 0,76 |
| c-7_12 West Gash | 1,11 | 1,00 | 1,00 | 31,9% / 31,0% | 0,92 / 0,77 |
| c-5_-3 Bitter Coast | 1,08 | 1,00 | 0,88 | 22,9% / 19,4–30,0% | 0,72 / 0,57 |
| c-24_19 Solstheim | 1,02 | 0,93 | 0,93 | 2,8% / 0,1–1,7% | 0,02 / 0,10 |
| c15_-9 Azura's Coast | 1,20 | 1,00 | 1,00 | 17,1% / 16,9% | 0,99 / 0,99 |

Wnioski:
- Na zrzutach obu silników żaden kadr nie jest zasłonięty z bliska, a teren z trawą wypełnia dolną część obrazu.
- W Grazelands MCP zgłosił z góry, że część celu zasłaniają dwa głazy i drzewo (widoczność 0,55), i zrzut to potwierdza.
- Na Solstheimie nieba jest bardzo mało (korony sosen), więc IoU jest niemiarodajne.
- **Błąd przebiegu:** w forku na Azura's Coast postać testowa (250 j. za kamerą) została zabita, a silnik przełączył kamerę na kamerę śmierci. Zrzut forka dla c15_-9 jest więc z innego miejsca; zrzut oficjalny jest poprawny. Poprawka w skrypcie ujęć: zdrowie postaci uzupełniane co klatkę, tryb kamery statycznej przywracany (z ostrzeżeniem `RLF_CAPTURE WARN` w logu).

## Ograniczenia
- **Modelowane przeszkody:** obiekty STAT, ACTI, DOOR, CONT, LIGH. Pominięte są postacie, stworzenia, przedmioty, obiekty włączane i wyłączane skryptem, trawa (Groundcover), efekty i pogoda.
- **Alfa:** geometria z alfą (liście, kraty) jest liczona w dwóch wariantach, a wynik podawany jako przedział.
- **Kształty zależne od czasu i kamery:** billboardy (zależne od kamery), animacje (NiKeyframeController itp.) i skinning są liczone w pozycji spoczynkowej, z adnotacją w pewności oceny.
- **Zasięg:** teren i obiekty w promieniu komórek 3×3 wokół celu. Dalsze obiekty traktowane są jako niebo albo „daleko”.
- **Kamera:** model zgodny z ustawieniami ujęć MCP (FOV 60° w pionie, 16:9). Inne FOV trzeba podać w kodzie.
- **Parser:** obsługuje tylko NIF Morrowinda (4.0.0.x). Nowsze formaty (Oblivion i dalej) są odrzucane czytelnym błędem.
- **Lua `getBoundingBox`:** dla obiektów stronicowanych silnik używa innej kolejności obrotów niż przy rysowaniu i liczy granice po optymalizacji grafu — porównanie uwzględnia te warianty.

## Wnioski dla forka
- `getCullSafeBoundingBox` w OpenMW 0.51.0 dla obiektów stronicowanych używa kolejności obrotów niezgodnej z `objectpaging.cpp`. Wpływa to na `getBoundingBox` w Lua dla pochylonych obiektów. To kandydat na zgłoszenie lub poprawkę w forku (osobny etap, wymaga testu).
- Parser i scena pozwalają dalej automatycznie wykrywać obiekty unoszące się nad terenem lub zakopane w nim. Pozwalają też szukać obiektów przecinających się z trawą forka, bo pach76 nie omija obiektów, podobnie jak Remiros.
