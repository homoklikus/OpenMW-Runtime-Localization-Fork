# MCP-openMW — etapy 1–3

Wspólny serwer MCP dla dwóch silników:
- **official** — OpenMW 0.51.0 (Flatpak `org.openmw.OpenMW`, kod w `../OpenMW/repo`);
- **fork** — OpenMW Runtime Localization Fork, gałąź `0.5-world` (`../Fork/repo`, binarka `../Fork/install`).

Etapy 1–2 tylko czytają. MCP nie uruchamia silników, nie steruje kamerą i nie zmienia configów ani modów. Zapisuje wyłącznie manifesty testów (`Raporty/mcp/manifesty/`), raporty testu integracyjnego (`Raporty/mcp/testy/`) i lokalny cache sum SHA-256 (`.cache/`).

## Położenie kodu
Kod jest wersjonowany w repozytorium forka: `Fork/repo/tools/MCP-openMW/` (gałąź `0.5-world`).
`MCP-openMW/` w katalogu projektu to dowiązanie symboliczne do tego katalogu — ta sama kopia, nie duplikat.
Katalog projektu (z `Fork/` i `OpenMW/`) MCP wyznacza sam (`"project_root": "auto"`), więc działa zarówno przez dowiązanie, jak i ze ścieżki w repozytorium.

## Instalacja (Debian 13)
```bash
cd "/media/precell/Inne/Projekty AI/OpenMW RLF/MCP-openMW"
python3 -m venv .venv                      # wymaga pakietu python3-venv
.venv/bin/pip install -e '.[test]'
.venv/bin/python -m pytest                 # testy na syntetycznym projekcie
```

## Podłączenie do Claude
Claude Code, zakres użytkownika, bez zmieniania plików projektu:
```bash
claude mcp add --scope user openmw-rlf -- "/media/precell/Inne/Projekty AI/OpenMW RLF/MCP-openMW/.venv/bin/openmw-mcp"
```
Claude Desktop: dopisz wpis z `claude/claude_desktop_config.snippet.json` do sekcji `mcpServers` w `~/.config/Claude/claude_desktop_config.json`. Pliku nie nadpisuj w całości. Przykład konfiguracji projektowej dla Claude Code: `claude/mcp.json.example`.

## Narzędzia
| Narzędzie | Opis |
|---|---|
| `openmw_env_status` | obie instalacje: wersja, commit źródeł, commit pakietu Flatpak, HEAD repo, binarka (SHA-256, ELF build-id, znaczniki), commit binarki vs HEAD, eksperymenty |
| `openmw_git_info` | stan Git celu (bez fetch) |
| `openmw_list_profiles` | profile `fork-test`, `official-ref` |
| `openmw_profile_effective` | łańcuch configów jak w silniku, kolejność `data=`, `content=`, `groundcover=`, archiwa, ustawienia, `world.cfg`, izolacja |
| `openmw_setting` | efektywna wartość ustawienia |
| `openmw_vfs_resolve` | kto dostarcza plik VFS, kto go nadpisuje (z SHA-256) |
| `openmw_vfs_overrides` | ścieżki z wieloma dostawcami: zwycięzca, czy bajty się różnią |
| `openmw_vfs_compare` | dwa profile: brakujące pliki i ta sama ścieżka z innym SHA-256 |
| `openmw_mods_identify` | odciski SHA-256 katalogów `data=`, wykrywanie wariantów i nakładek (katalog `catalog/*.sha256`), konflikty nazw |
| `openmw_mod_identify_dir` | identyfikacja wariantu dowolnego katalogu |
| `openmw_groundcover_mode` | oficjalne pluginy ESP / proceduralna flora forka (profile Remirosa, pula modeli) / eksperymenty |
| `openmw_groundcover_stats` | komórki, statyki i referencje z pluginów `groundcover=` (jak „Loaded N cells, M statics”); referencje w komórce |
| `openmw_esp_info` | mastery i rekordy pluginu |
| `openmw_manifest_build` / `openmw_manifest_write` | manifest testu z etykietą stanu |
| `openmw_profile_diff` | różnice dwóch profili, ostrzeżenia o porównywalności |

### Etap 2 — teren i oficjalny Groundcover offline
| Narzędzie | Opis |
|---|---|
| `openmw_land_cell` | LAND komórki z `content=`: plugin (i nadpisania wg kolejności), wysokości, nachylenie, tekstury LTEX, opcjonalnie siatka 16×16 |
| `openmw_land_point` | wysokość (triangulacja „diamond”), nachylenie i tekstura w punkcie świata (tryb `fork` i hipoteza `render`) |
| `openmw_groundcover_baseline` | emulacja `groundcover.cpp` 0.51.0 dla komórki: liczba instancji przy gęstości, pliki, modele, skala, tekstury i nachylenie pod instancjami |
| `openmw_land_texture_mapping_check` | test hipotezy przesunięcia tekstur LAND na wszystkich referencjach groundcover |
| `openmw_groundcover_height_offset` | z referencji − wysokość terenu per plugin (kalibracja wysokości flory proceduralnej) |
| `openmw_groundcover_region` | instancje, których pozycja leży w prostokącie świata (łącznie z przypisanymi do sąsiednich komórek) — granice do porównań z florą proceduralną |

### Etap 2c — proceduralna flora forka offline i porównanie z Remirosem
| Narzędzie | Opis |
|---|---|
| `openmw_fork_flora_cell` | emulacja `collectInstances` forka w komórce: profil regionalny (RGNN, zapasowe próbkowanie tekstur AL/GL), kandydaci, odrzucenia wg przyczyny, modele, skale, parametry generatora i wzór ziarna |
| `openmw_fork_flora_region` | to samo w prostokącie świata — te same granice co `openmw_groundcover_region` |
| `openmw_flora_compare` | komórka obok siebie: Remiros (oficjalny Groundcover) i fork — region, profil forka, pluginy Remirosa, liczby i gęstość na m², modele |
| `openmw_flora_coverage` | cały świat: komórki Remirosa z profilem forka i bez, utracone instancje wg regionu |

Wynik forka jest **górną granicą**: bez wykluczeń obiektów sceny (wymagają granic NIF) i ścieżek PGRD. Te cztery narzędzia emulują generator **sprzed pach75**.

### Etap 2c — trawa Remirosa w forku (pach75, od 0.6.0 format pach76)
| Narzędzie | Opis |
|---|---|
| `openmw_remiros_rules` | reguły wyliczone z pluginów: tekstura LAND → gęstość na teksel, statyki (model, udział, skala, +z), statystyka mapy liczników |
| `openmw_remiros_compare` | komórka: Remiros vs trawa forka (emulacja identyczna z rdzeniem C++), tryb liczników albo same reguły; od 0.6.0 liczniki per pole 4×4 teksela i per statyka (pach76) |
| `openmw_remiros_export` | zapis plików C++ (dane + kopie wzorców z `cpp/`) do katalogu eksperymentu, domyślnie `Fork/experiments/remiros-subtexel-2026-11-14/files` (pach76) — jedyny zapis |

### Etap 3 — porównania wizualne (uruchamia silniki)
| Narzędzie | Opis |
|---|---|
| `openmw_capture_plan` | punkty kamery dla komórek (cel: najgęstszy teksel Remirosa, 700 j., kamera nad wodą), katalog uruchomienia i polecenia — bez uruchamiania; `repeat` (powtórzenie serii), `settle_seconds`, `render_seconds` |
| `openmw_capture_start` | uruchamia w tle oficjalny OpenMW, potem fork; skrypt Lua `lua/rlf_capture` ustawia ujęcia, MCP robi zrzut (F12 w grze przez `xdotool`, awaryjnie `import -window`) |
| `openmw_capture_status` | postęp, zrzuty, błędy z logów, arkusze obok siebie i miary (różnica obrazów, udział pikseli roślinności) |

Profile `openmw-ref` i `openmw-test` nie są zmieniane. Każde uruchomienie dostaje katalog `Raporty/mcp/zrzuty/<data>/<profil>/` (`cfg/` jako ostatni katalog konfiguracji: log, ustawienia 1920×1080 w oknie, kopia `world.cfg`/`shaders.yaml`/`input_v3.xml`; `data/` ze skryptem Lua; `userdata/`). Oba silniki działają przez XWayland (`SDL_VIDEODRIVER=x11`; Flatpak dostaje `--socket=x11` tylko na czas uruchomienia). Wymagania: `xdotool`, `import` (ImageMagick), `pip install -e '.[capture]'` (Pillow). W trakcie przebiegu nie używaj myszy ani klawiatury.

Przebieg z terminala: `.venv/bin/python -m openmw_mcp.capture <katalog_uruchomienia>` (katalog przygotowany przez `openmw_capture_plan`).

`cpp/remirosgroundcovergen.hpp` to wzorzec rdzenia generatora (bez zależności od OSG/OpenMW), `cpp/remirosgroundcover.{hpp,cpp}` — adapter do silnika, `cpp/remiros_harness.cpp` — test porównawczy C++↔Python (`tests/test_remiros.py`, wymaga `g++`).

To emulacja offline na podstawie kodu silnika, nie pomiar w działającym silniku. Indeksy LAND/groundcover są trzymane w pamięci procesu i odświeżane, gdy zmieni się rozmiar lub mtime któregoś pliku.

## Wersja kodu
Podstawowy identyfikator: commit Git repozytorium forka, w którym zmieniono `tools/MCP-openMW/`. Dodatkowy identyfikator wersji testowej: `SOURCE-MANIFEST.sha256` (suma SHA-256 każdego pliku źródłowego) i hash drzewa (`sha256sum SOURCE-MANIFEST.sha256`). Hash pozwala wskazać stan sprzed commita albo z lokalnymi zmianami:
```bash
.venv/bin/python -m openmw_mcp.srcmanifest --check   # czy bieżące pliki odpowiadają manifestowi
.venv/bin/python -m openmw_mcp.srcmanifest --write   # po zatwierdzonej zmianie: nowy manifest
```
`--check` wypisuje też ostatni commit dotyczący MCP i to, czy są niezacommitowane zmiany. Te same dane (`mcp.tree_sha256`, `mcp.git`) trafiają do każdego manifestu testu i do `openmw_env_status`.

Odtworzenie zatwierdzonej wersji: `git -C Fork/repo checkout <commit> -- tools/MCP-openMW` (albo `git worktree add`), potem `srcmanifest --check`.

## Test integracyjny (przez protokół MCP, jak Claude Code)
```bash
.venv/bin/python scripts/integracja.py
```
Uruchamia `.venv/bin/openmw-mcp` jako osobny proces stdio, woła narzędzia i porównuje wyniki z wartościami wyznaczonymi niezależnie (pliki `.cfg`, Git, `flatpak info`, `manifest.json` Flatpaka, katalogi modów, nagłówki ESP, liczby z audytu). Raport JSON: `Raporty/mcp/testy/` (poza repozytorium). Kod wyjścia 0 = wszystko zaliczone.

Konfiguracja: `openmw-mcp.json` (ścieżki względem katalogu projektu; `@mcp/…` — względem katalogu MCP). Zmienna `OPENMW_MCP_PROJECT_ROOT` wymusza katalog projektu. Zmienne: `OPENMW_MCP_CONFIG` (inny plik), `OPENMW_MCP_CACHE=off`, `OPENMW_MCP_PATH_MAP="/z=/do;..."` (analiza kopii lub montażu).
