# Groundcover: oficjalne 0.51.0, fork `0.5-world`, eksperyment AC (2026-11-14)

## Oficjalne 0.51.0
Statyki z plików `groundcover=` → `GroundcoverStore`. Dla każdego chunku quadtree `collectInstances` czyta referencje komórek, filtruje je po pozycji w granicach chunku i gęstości (`DensityCalculator`, deterministyczny), a `createChunk` buduje instancjonowaną geometrię (shader: wiatr, stomp, point lighting). Włączane przez `[Groundcover] enabled`. Brak kolizji.

## Fork `0.5-world`
Ta sama klasa i ścieżka renderowania. W `collectInstances` doszedł drugi przebieg, który dopisuje instancje proceduralne do tej samej mapy.

| Aspekt | Implementacja |
|---|---|
| Włączanie | `world.cfg [Flora]`; `source` decyduje o pluginach (`automatic` = tylko proceduralne) |
| Pula modeli | 18 modeli vanilla z VFS albo lista ze zmiennej `OPENMW_FLORA_TEST_ASSET` |
| Profile Remirosa | AI, AL, BC, GL, WG — każdy aktywny tylko przy komplecie modeli rodziny w puli; **brak AC i Solstheim** |
| Region | angielska nazwa `CELL.mRegion`; AL/GL także ≥2/9 próbek LAND (`tx_al_`/`tx_ashlands_`, `tx_gl_`) |
| Wyłączność | przy aktywnym profilu Remirosa komórki spoza profili nie dostają roślinności |
| Kandydaci/komórkę | ogólnie 32 768 × density; AI 4096; AL/BC/GL/WG 8192; jitterowana siatka w obrębie komórki |
| Deterministyczność | hash `(cellX, cellY, index)` — powtarzalne, niezależne od podziału na chunki; zmiana density zmienia siatkę |
| Filtry | woda (z ≤ 1), nachylenie 28° (45° AI/AL/GL), waga tekstury LAND, statyki z ESM + `exclusion_distance`, pathgrid |
| Model/skala | selektory regionalne z wagami; skale per profil; normalizacja footprintu dla modeli nie-Remiros |

## Dane Remirosa 4.1 (Core OpenMW)
7 pluginów bez masterów (AC, AI, AL, BC, GL, WG, Solstheim), łącznie ~836 000 referencji w 701 komórkach. **140 komórek pokrywa więcej niż jeden plugin.** Plugin ≠ region: Rem_WG ma 65 komórek na Azura's Coast, a Rem_AC 54 w Sheogorad. W komórce (15,−9) jest 1044 referencji Rem_AC i 405 Rem_WG. Historycznych liczb 963 / 500 / 1,926× nie da się odtworzyć z danych — metrykę porównania trzeba zdefiniować na nowo.

Mod testowy forka (`remiros_procedural_test`) = Core OpenMW + nakładka `01b Thicker Grass` (identyczne bajtowo), także pod unikalną ścieżką VFS `meshes/omwpl_remiros_test/`.

## Eksperyment Azura's Coast (niezatwierdzony)
Diff `groundcover.cpp` (+322/−56), nakłada się czysto na `5629d385`. Zawiera: profil AC (miks 31 233/9 295/8 770 z Rem_AC.esp), detekcję regionu z fallbackiem `tx_ac_*`, wagi LAND z analizy 49 298 referencji, 4096 kandydatów, brak odrzucania nachylenia do 70° i wyłączone wykluczenia dla AC, jitter ±128 j. ze spilloverem między chunkami i „własnością” chunku, skale 1,20–1,73 oraz log diagnostyczny dla (15,−9). **Nie jest częścią gałęzi.**

## Wnioski do dalszej pracy
1. Najpierw ustalić metrykę i baseline z danych (oficjalne rozmieszczenie da się policzyć offline z ESP), dopiero potem stroić generator.
2. Rozważyć obsługę wielu rodzin modeli w jednej komórce (dane Remirosa tego wymagają).
3. Przenieść konfigurację puli modeli ze zmiennej środowiskowej do konfiguracji.
