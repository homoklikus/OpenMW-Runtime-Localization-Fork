# Fork `0.5-world` vs OpenMW 0.51.0 — różnice i architektura (2026-11-14)

Baza `f4bec414` (`openmw-0.51.0`) → `5629d385`: 72 commity, 88 plików, +20 570 / −747.

| Obszar | Kluczowe pliki | ~Linie |
|---|---|---|
| Launcher (mody, archiwa, Nexus, World, Groundcover) | `apps/launcher/datafilespage.cpp`, `worldpage.*`, `settingspage.*`, `components/contentselector/*` | 10 000 |
| Groundcover / World | `apps/openmw/mwrender/groundcover.cpp`, `terrainstorage.*`, `renderingmanager.cpp`, `components/worldconfig/*` | 2 600 |
| Runtime localization | `components/translation/*`, `apps/openmw/engine.cpp`, `mwgui/*`, `mwdialogue/*`, `mwscript/*`, `mwlua/contentbindings.cpp` | 3 300 |
| Tłumaczenia Qt, dokumentacja, CI | `files/lang/*`, `docs/*`, `.github/workflows/windows.yml`, `CI/*` | 5 300 |

Nowe zależności: LibArchive i Qt Network (launcher); opcjonalnie `7z` w `PATH`.

## Runtime localization
- Natywny loader YAML (yaml-cpp, parser strumieniowy). Dla każdego aktywnego pliku treści sprawdza dokładnie jedną ścieżkę VFS: `localization/language/<stem>.yaml`, w kolejności ładowania.
- Język z `[General] preferred locales` (tak samo jak l10n). Dokładny locale ma pierwszeństwo przed językiem bazowym. Kolejne warstwy nadpisują wpisy o tym samym priorytecie.
- Zastosowanie po wczytaniu ESM, przed `ESMStore::setUp()`:
  - nadpisanie pól rekordów statycznych (`FNAM/DESC/TEXT/RNAM`, `GMST STRV` itd.) przez `insertStatic`;
  - tabele wyłącznie do wyświetlania: nazwy komórek, tematy (ID techniczne pozostają angielskie), odpowiedzi INFO z wariantami płci NPC/gracza, `Choice`, `Say`/`MessageBox`;
  - stringi fallback (Level Up, pytania tworzenia postaci).
- Znaczniki `[b] [i] [c=#rrggbb]` trafiają tylko do GUI; do rekordów idzie czysty tekst. Podświetlanie QA wg źródła (`runtime localization qa source`).
- Dziennik lokalizuje zapisany tekst przy wyświetlaniu, więc zapis pozostaje neutralny językowo (wyjątek: wpisy z wariantami płci).
- Język wybierany przy starcie; brak przełączania w trakcie gry. Brak cache — YAML parsowany przy każdym uruchomieniu.

## World
- `world.cfg` w katalogu konfiguracji: `[Flora] enabled, source=automatic|groundcover|hybrid, density (0–2), exclusion_distance (0–20 m)`, `[Fauna] enabled` (tylko parsowane, brak implementacji).
- **Zmiana semantyki:** przy `[Flora] enabled=true` o pluginach `groundcover=` decyduje `source`, a nie `[Groundcover] enabled`; w trybie `automatic` pluginy nie są renderowane. Przy `enabled=false` zachowanie jest oficjalne.
- Launcher: strona World, pełne ustawienia `[Groundcover]`. Okno debug: zakładka „Świat” (pozycja, komórka, tekstura LAND).

## Groundcover
Szczegóły: [`../groundcover/2026-11-14-groundcover-stan.md`](../groundcover/2026-11-14-groundcover-stan.md). W skrócie: fork rozszerza oficjalną klasę `Groundcover` (ten sam renderer, instancing, shader i dystans) o osobny przebieg generowania instancji proceduralnych.

## Launcher i Nexus Mods
- Content selector: oznaczanie pluginów jako Groundcover (`groundcover=`), sortowanie wg zależności.
- Mody zasobów: konflikty plików, analiza rozdzielczości DDS, instalacja z archiwów (LibArchive, BAIN, ochrona przed `..`/symlinkami), bezpieczna podmiana i usuwanie zarządzanych modów, metadane INI.
- Nexus: walidacja klucza, lista plików, pobieranie, GraphQL (tłumaczenia), aktualizacje, nakładki tłumaczeń. `Application-Version` ustawione na sztywno na `0.4-dev`.
- NXM (Linux): plik `.desktop` w `~/.local/share/applications`, domyślny handler w `mimeapps.list` (z odtwarzaniem poprzedniego), przekazywanie przez `QLocalServer`.

## Znane ograniczenia i zagrożenia
1. Klucz API Nexus: tymczasowy cache „testowy”; na Linuksie klucz główny leży w pliku obok szyfrogramu (to zaciemnienie, nie ochrona). Do zastąpienia magazynem systemowym.
2. Proceduralna flora zależy od zmiennej środowiskowej `OPENMW_FLORA_TEST_ASSET`. Regiony są wykrywane po angielskich nazwach `CELL.mRegion`, więc mody zmieniające regiony nie są obsługiwane.
3. Koszt CPU budowy chunków (wiele zapytań terenowych na kandydata, ponowne czytanie ESM przy wykluczeniach) — niezmierzony.
4. Wykluczenia flory liczone z treści ESM, nie ze stanu gry.
5. Ryzyko utrwalenia zlokalizowanych nazw w rekordach dynamicznych zapisu — do przetestowania.
6. Silnik nie sprawdza zgodności ESM z sumami `sha256` zapisanymi w YAML.
7. Launcher, tak jak oficjalny, ignoruje `--config`/`--user-data`; profile testowe izoluje lokalny `openmw.cfg` obok binarki.
