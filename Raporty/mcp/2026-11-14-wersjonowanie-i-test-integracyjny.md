# MCP — kod w repozytorium forka i test integracyjny (0.2.1)

**Status: przeniesienie wykonane i sprawdzone na Debianie 13 (2026-11-14 14:07): testy jednostkowe zaliczone, `srcmanifest --check` zgodne (`560428b4…`), test integracyjny 44/44, test przez klienta Claude Code zgodny (14:10).**

## Problem
Do wersji 0.2.0 kod MCP leżał w `MCP-openMW/` poza Gitem. Dokumentację można było powiązać z kodem tylko przez hash `SOURCE-MANIFEST.sha256`, a dawnych wersji nie dało się odtworzyć (drzewo etapu 1 `efb03baa…` nie zostało zachowane).

## Rozwiązanie
- Kod jest przenoszony do `tools/MCP-openMW/` w tym repozytorium (gałąź `0.5-world`).
- W katalogu projektu `MCP-openMW` staje się **dowiązaniem symbolicznym** do `Fork/repo/tools/MCP-openMW`. Jest jedna kopia kodu. Ścieżka robocza i rejestracja `openmw-rlf` w Claude Code (`…/MCP-openMW/.venv/bin/openmw-mcp`) działają bez zmian.
- Odwrotny kierunek (kod poza repo, dowiązanie w repo) odpada: Git zapisuje wtedy tylko dowiązanie, nie pliki. Submoduł albo subtree wymagałyby osobnego repozytorium, a tego nie zakładamy.
- `SOURCE-MANIFEST.sha256` zostaje jako dodatkowy identyfikator wersji testowej. `srcmanifest --check` i `openmw_env_status` podają teraz także `git.last_commit_for_mcp` i to, czy są niezacommitowane zmiany.

Zmiany w kodzie, które to umożliwiają:
- `"project_root": "auto"`: MCP sam znajduje katalog projektu z `Fork/` i `OpenMW/`, wychodząc w górę zarówno od ścieżki przez dowiązanie, jak i od ścieżki rzeczywistej. Można to nadpisać zmienną `OPENMW_MCP_PROJECT_ROOT`.
- Ścieżki `@mcp/…` w `openmw-mcp.json` są liczone względem katalogu MCP (np. katalog sum Remirosa).
- Test `test_project_root_auto_through_symlink_and_mcp_paths` sprawdza oba warianty ścieżki.

## Co jest wersjonowane, a co nie
Wersjonowane są: `src/`, `tests/`, `scripts/`, `catalog/remiros-4.1.sha256` (tylko nazwy plików i sumy SHA-256, bez zawartości modów), `claude/*.example|snippet`, `openmw-mcp.json`, `pyproject.toml`, `README.md`, `SOURCE-MANIFEST.sha256`, `.gitignore`.

Ignorowane są: `.venv*/`, `.cache/`, `.pytest_cache/`, `__pycache__/`, `*.pyc`, `*.egg-info/`, `build/`, `dist/`. Raporty testów i manifesty trafiają do `Raporty/mcp/` w katalogu projektu, poza repozytorium.

## Przeniesienie — `Fork/scripts/mcp-do-repo.sh`
Skrypt jest w katalogu projektu (`Fork/scripts/`), poza repozytorium.

1. `--check`: sprawdza, że `MCP-openMW` jest zwykłym katalogiem, cel nie istnieje, repozytorium jest na `0.5-world`, oba miejsca są na tym samym systemie plików (`mv` to zmiana nazwy), dowiązania działają i nie działa serwer `openmw-mcp`.
2. Robi pełną kopię zapasową z `.venv` do `Kopie-zapasowe/MCP-openMW-<data>.tar.gz` i sprawdza liczbę plików w archiwum.
3. Zapisuje listę SHA-256 przed, wykonuje `mv` i `ln -s`, zapisuje listę po. Listy muszą być identyczne. Jeśli `ln -s` się nie uda, przywraca poprzedni układ.
4. Sprawdza w Git, że `.venv` i cache są ignorowane, i wypisuje pliki do dodania.
5. Uruchamia `pytest` i `srcmanifest --check` z nowej lokalizacji.

Skrypt sprawdzono najpierw w VM na syntetycznej kopii projektu, potem wykonano go na Debianie. Projekt leży tam na ext4 (`stat -f` podaje „ext2/ext3”). Wynik: kopia zapasowa `Kopie-zapasowe/MCP-openMW-2026-11-14-140705.tar.gz` (3648 plików z `.venv`), 3648 plików na miejscu, sumy SHA-256 przed i po zgodne, `.venv`/`.cache`/`.pytest_cache` ignorowane, 25 plików do dodania w repozytorium.

### Rejestracja w Claude Code po przeniesieniu
Serwer był zarejestrowany z zakresem `local`. Claude Code przypisuje taki wpis do ścieżki katalogu projektu, a po przeniesieniu bieżący katalog rozwiązuje się do `Fork/repo/tools/MCP-openMW`. Dlatego `claude mcp list` przestał pokazywać `openmw-rlf`, choć sam serwer działa (test integracyjny uruchomił tę samą binarkę). Rozwiązanie: rejestracja z zakresem `user`, przez ścieżkę z dowiązaniem:
```bash
claude mcp add --scope user openmw-rlf -- "/media/precell/Inne/Projekty AI/OpenMW RLF/MCP-openMW/.venv/bin/openmw-mcp"
```

Cofnięcie: `rm MCP-openMW && mv Fork/repo/tools/MCP-openMW MCP-openMW` (w katalogu projektu).

## Test integracyjny — `scripts/integracja.py`
Test łączy się z serwerem tak jak Claude Code: osobny proces stdio (`.venv/bin/openmw-mcp`), `initialize`, `list_tools`, `call_tool`. Wartości oczekiwane są wyznaczane **niezależnie od kodu MCP**. Skrypt ma własny parser `.cfg`/`settings.cfg`/`world.cfg`, używa `git rev-parse`, `LC_ALL=C flatpak info` i `files/manifest.json` Flatpaka, własnego parsera nagłówków ESP, przeglądu katalogów `data=` oraz liczb z audytu (701 komórek, 105 statyk, 1449 instancji).

| Obszar | Sprawdzane |
|---|---|
| protokół | `initialize`, komplet 22 narzędzi |
| silniki | HEAD i gałąź forka, commit binarki forka (`resources/version`), wersja Flatpaka 0.51.0, commit źródeł = `manifest.json` = tag `openmw-0.51.0` (`f4bec414`), commit pakietu ≠ commit źródeł, HEAD `OpenMW/repo` |
| profile (oba) | `content=` i `groundcover=` w kolejności, pliki znalezione, `data=` w tej samej kolejności, izolacja od domyślnych profili, katalog konfiguracji |
| VFS | dla ścieżek dostarczanych przez kilka katalogów `data=` zwycięzca = ostatni katalog (niezależny przegląd plików) |
| flora | fork: proceduralna wg `world.cfg`, pluginy **wyłączone przez `source=automatic`** mimo `[Groundcover] enabled=true`, pula modeli kompletna, profile AI/AL/BC/GL/WG; official: Groundcover z pluginów, 701 komórek i 105 statyk (MCP = parser niezależny = log silnika) |
| mody | Remiros = dokładnie `00 Core OpenMW` + `01b Thicker Grass OpenMW` (SHA-256), mastery i liczba CELL w Rem_AC.esp |
| porównanie | `vfs_compare`, `profile_diff`: wykryte różne silniki i różny mechanizm flory |
| etap 2 | baseline (15, −9) = 1449, LAND (15, −9) z Morrowind.esm, region komórki zgodny z baseline |

Raport JSON z odpowiedziami narzędzi trafia do `Raporty/mcp/testy/integracja-<data>.json` (lokalnie, poza repozytorium). Kod wyjścia: 0 = wszystko zaliczone, 1 = FAIL, 3 = SKIP.

### Wyniki
| Środowisko | Wynik | Uwagi |
|---|---|---|
| VM Cowork, Flatpak niedostępny | 20 PASS, 3 SKIP | część oficjalna pominięta |
| VM Cowork, atrapa `flatpak info` + prawdziwe pliki wdrożenia Flatpaka | **44/44 PASS** | wersja z atrapy; `manifest.json`, metainfo i binarka prawdziwe |
| Debian 13 (prawdziwy Flatpak, po przeniesieniu do `tools/`) | **44/44 PASS** (2026-11-14 14:07) | serwer `…/tools/MCP-openMW/.venv/bin/openmw-mcp` |

Podczas przygotowania test wykrył dwa błędy w **samym teście**: liczył komórki ze wszystkich plików zamiast komórek unikalnych (852 zamiast 701 — silnik scala tę samą komórkę z kilku pluginów) i porównywał nazwy wariantów bez prefiksu katalogu (`Remiros 4.1 :: …`). Oba poprawiono. W MCP nie wykryto rozbieżności.

### Test przez klienta Claude Code
Uzupełnieniem jest wywołanie przez samego klienta. Odpowiedź Claude porównuje się z raportem JSON z `integracja.py`.

**Wynik (Debian 13, 2026-11-14 14:10, `openmw-rlf` w zakresie `user`, ✔ Connected): zgodny z raportem integracyjnym.** Claude, korzystając tylko z narzędzi `openmw-rlf`, podał:
- HEAD forka `0b9ed5b6` (zgodny z `origin/0.5-world`);
- commit binarki `5629d385` (8 commitów za HEAD, bez zmian w kodzie);
- oficjalne OpenMW 0.51.0, źródła `f4bec414`;
- `fork-test`: flora proceduralna z profilami AI/AL/BC/GL/WG, pula 22 modeli, wszystkie w VFS, bez pluginów;
- `official-ref`: Groundcover z 7 pluginów Rem_*;
- Remiros 4.1 = Core OpenMW + 01b Thicker Grass (76/76 plików);
- baseline (15, −9) = 1449 (Rem_AC 1044, Rem_WG 405), opisany jako emulacja, nie pomiar.

Klient sam odnotował też, że eksperyment Azura's Coast jest niezacommitowany.

Polecenie:
```bash
cd "/media/precell/Inne/Projekty AI/OpenMW RLF/MCP-openMW"
claude -p "Użyj tylko narzędzi serwera openmw-rlf: openmw_env_status, openmw_groundcover_mode (fork-test i official-ref), openmw_mods_identify (official-ref), openmw_groundcover_baseline (official-ref, 15, -9). Podaj tabelę: HEAD forka, commit binarki forka, wersja i commit źródeł oficjalnego OpenMW, mechanizm flory w obu profilach, wariant Remirosa, liczba instancji baseline." \
  --allowedTools "mcp__openmw-rlf__openmw_env_status mcp__openmw-rlf__openmw_groundcover_mode mcp__openmw-rlf__openmw_mods_identify mcp__openmw-rlf__openmw_groundcover_baseline"
```
