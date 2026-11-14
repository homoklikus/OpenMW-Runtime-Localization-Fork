# MCP-openMW, etap 1 — narzędzia tylko do odczytu (2026-11-14)

| | |
|---|---|
| Wersja | `openmw-mcp` 0.1.0 |
| Hash drzewa źródeł | `efb03baa76271f5e7f8beb74bae79a34bfac3915c116c825793900b19a67708c` (`sha256sum MCP-openMW/SOURCE-MANIFEST.sha256`, 21 plików) |
| Status | **zatwierdzony** — testy automatyczne: Debian 13 **36/36** (2026-11-14 13:36, `srcmanifest --check` zgodny), VM 36/36; próba na prawdziwym projekcie w trybie odczytu. Podłączenie w kliencie Claude: jeszcze nie sprawdzane |

## Zakres
Serwer tylko czyta. Nie uruchamia silników i nie zmienia ich kodu, configów ani modów. Jedyne zapisy to manifesty testów (`Raporty/mcp/manifesty/` w katalogu projektu) i lokalny cache sum SHA-256.

## Technologie i architektura
Python ≥3.10, oficjalne SDK `mcp` (1.x `FastMCP` lub 2.x `MCPServer`), transport stdio. Konfiguracja `openmw-mcp.json` opisuje cele (`fork`, `official`), profile (`fork-test`, `official-ref`), eksperyment Azura's Coast i katalogi wariantów modów.

| Moduł | Zadanie |
|---|---|
| `environment` | wykrywanie instalacji, Git (bez fetch, bez blokad), binarki (SHA-256, ELF build-id, znaczniki), `resources/version`, CMakeCache, eksperymenty |
| `cfgparse`, `profiles` | `openmw.cfg`, `settings.cfg`, `world.cfg`; łańcuch configów, scalanie opcji, ustawienia, warstwy VFS, izolacja profilu |
| `bsa`, `esp` | listy plików BSA TES3; nagłówki, rekordy, komórki i referencje pluginów |
| `mods` | odciski SHA-256 katalogów, identyfikacja wariantów i kolejności nakładek, konflikty nazw, nadpisywanie plików, kolizje wielkości liter |
| `flora` | mechanizm roślinności: oficjalny Groundcover z pluginów ESP / proceduralna flora forka / eksperyment |
| `manifest` | manifest testu z etykietą stanu, diff profili, porównanie VFS |
| `srcmanifest` | wersja kodu MCP poza Gitem |

## Integracja z silnikami
Semantykę przeniesiono z kodu źródłowego, bez zgadywania:
- **OpenMW 0.51.0:** `components/files/configurationmanager.cpp` (`readConfiguration`, `mergeComposingVariables`, `processPath`) i `components/settings/settings.cpp::load`. Wynik: kolejność configów i `data=`, `replace=`, tokeny `?local?`/`?global?`/`?userdata?`/`?userconfig?`, ścieżki względne od pliku `.cfg`, defaults z pierwszego katalogu configu.
- **Fork:** `apps/openmw/mwrender/renderingmanager.cpp::getWorldspaceChunkMgr` (tabela `world.cfg [Flora]` ↔ `[Groundcover]`) i `groundcover.cpp::hasRemiros*TestPool` (warunki aktywacji profili AI/AL/BC/GL/WG).
- **Flatpak:** wersja z `LC_ALL=C flatpak info` oraz metainfo, commit źródeł z `files/manifest.json`, commit pakietu tylko informacyjnie. MCP nie wywołuje `flatpak run`.
- Kolejność VFS zgodna z logami obu silników: BSA < `resources/vfs` < `data=` < `data-local`.

## Narzędzia (16)
| Narzędzie | Przeznaczenie |
|---|---|
| `openmw_env_status` | obie instalacje, wersje, commity, binarki, eksperymenty, wersja MCP |
| `openmw_git_info` | stan Git celu |
| `openmw_list_profiles` | profile testowe |
| `openmw_profile_effective` | efektywna konfiguracja profilu |
| `openmw_setting` | efektywna wartość ustawienia |
| `openmw_vfs_resolve` | dostawca pliku VFS i nadpisania (z SHA-256) |
| `openmw_vfs_overrides` | ścieżki z wieloma dostawcami, różnice bajtów |
| `openmw_vfs_compare` | dwa profile: brakujące pliki, różne SHA-256 |
| `openmw_mods_identify` | odciski katalogów `data=`, warianty, konflikty nazw |
| `openmw_mod_identify_dir` | wariant dowolnego katalogu moda |
| `openmw_groundcover_mode` | mechanizm roślinności, profile Remirosa, pula modeli |
| `openmw_groundcover_stats` | komórki, statyki, referencje z pluginów `groundcover=` |
| `openmw_esp_info` | mastery i rekordy pluginu |
| `openmw_manifest_build`, `openmw_manifest_write` | manifest testu z etykietą stanu |
| `openmw_profile_diff` | różnice profili i ostrzeżenia o porównywalności |

## Testy
- **36 testów automatycznych** na syntetycznym projekcie (ścieżka ze spacją, repo Git, binarka ELF, atrapa Flatpaka sprawdzająca, że `flatpak run` nie pada, BSA, ESP, warianty moda). Obejmują przypadki błędne: brak instalacji, brak konfiguracji, nieprawidłowe ścieżki, konflikt nazw modów, różne SHA-256, profil bez `--replace=config` czytający profil użytkownika. Wynik w VM (Ubuntu 22.04, Python 3.10, `mcp` 2.3.0): 36/36, także z katalogiem tymczasowym na dysku hosta. Debian 13 (Python 3.13, `mcp` 2.3.0): pierwszy przebieg 33/35 (błąd nr 6), po poprawce **36/36**.
- **Próba na prawdziwym projekcie** (tylko odczyt):
  - fork: binarka z `5629d385`, HEAD różni się tylko dokumentacją, aktywne profile AI/AL/BC/GL/WG, 22/22 modeli puli w VFS, eksperyment AC nieobecny;
  - oficjalne: 0.51.0, źródła `f4bec414`, pakiet `18f04802`;
  - referencja: 7 pluginów, **701 komórek, 105 statyk**, zgodnie z logiem silnika z tego samego dnia.

### Wykryte błędy i poprawki
1. Cache SHA-256 mógł zwrócić nieaktualną sumę przy szybkim nadpisaniu pliku tego samego rozmiaru. Teraz pliki zmienione <2 s temu są zawsze haszowane, a klucz obejmuje i-węzeł i ctime.
2. Odcisk katalogu ignorował pliki różniące się tylko wielkością liter. Teraz liczony z prawdziwych ścieżek, a kolizje są raportowane jako niejednoznaczność VFS.
3. `groundcover_stats` liczył tylko komórki zewnętrzne (700). Teraz liczy jak silnik (701, w tym wnętrze w `Rem_AC.esp`) i osobno zewnętrzne.
4. Zgodność z `mcp` 2.x (zmiana nazwy `FastMCP` → `MCPServer`).
5. Podczas próby MCP wykrył niespójność profilu referencyjnego (przemianowany katalog moda). Profil poprawiono.
6. **Niedeterminizm przy nazwach różniących się wielkością liter** (wykryty na Debianie 13: 33/35, 2 testy padły na ext4, w VM przechodziły): w jednym katalogu `Rem_AC.esp` i `rem_ac.esp` — wybór pliku zależał od kolejności katalogu w systemie plików. Tak samo zachowuje się OpenMW (`Files::MultiDirCollection`: dopasowanie bez wielkości liter, w jednym katalogu wygrywa ostatni z `directory_iterator`). Poprawka: MCP wybiera deterministycznie (dokładna nazwa, potem alfabetycznie), zgłasza niejednoznaczność jako problem profilu, przechodzenie VFS jest sortowane. Test regresyjny + przebieg testów na katalogu tymczasowym na dysku hosta: 36/36.

## Instalacja i uruchomienie
```bash
cd MCP-openMW
python3 -m venv .venv && .venv/bin/pip install -e '.[test]'
.venv/bin/python -m pytest
.venv/bin/python -m openmw_mcp.srcmanifest --check
claude mcp add openmw-rlf -- "$PWD/.venv/bin/openmw-mcp"
```

## Ograniczenia
- Brak pomiarów w trakcie gry: mechanizm flory wynika z analizy konfiguracji i kodu.
- Ustawienia domyślne z `files/settings-default.cfg` repozytorium (odpowiednik `defaults.bin`).
- Pula proceduralna czytana ze skryptu `run-flora-test.sh` (zmienna środowiskowa nie należy do konfiguracji silnika).
- Wykrywanie eksperymentu w binarce przez znacznik tekstowy.

## Następny etap
Dane świata (LAND z ESM, emulacja oficjalnego `Groundcover::collectInstances` jako baseline liczb, parser NIF) — po zatwierdzeniu etapu 1.
