# Założenia architektury MCP-openMW (2026-11-14)

Status: założenia z początku prac. Zaimplementowane etapy opisują osobne dokumenty (`README.md` w tym katalogu).

## Położenie kodu (od wersji 0.2.1)
Kod MCP: `tools/MCP-openMW/` w tym repozytorium (Python ≥ 3.10, oficjalne SDK `mcp`, transport stdio). W katalogu projektu `MCP-openMW/` jest dowiązaniem do `Fork/repo/tools/MCP-openMW/`. Środowisko `.venv/`, cache i raporty testów nie są wersjonowane. Dane wejściowe (gra, mody, profile, Flatpak) są czytane z katalogu projektu, nie z repozytorium.

## Zasady
- Jeden serwer, dwa cele: `official` (OpenMW 0.51.0, Flatpak) i `fork` (`0.5-world`). Eksperymenty tylko jako jawny wariant budowany w osobnym worktree.
- Każdy wynik ma etykietę stanu: commit, binarka, profil, hash zestawu modów, `settings.cfg` i `world.cfg`. Porównanie wyników o różnych etykietach daje ostrzeżenie albo jest odrzucane.
- Kolejność: analiza kodu i danych → diagnostyka i statystyki → testy → porównanie wizualne.
- Bez agentów wstrzykiwanych do gry. Bez zmian w oficjalnym kodzie. Instrumentacja tylko w forku, za flagą.

## Dostępne bez modyfikacji silnika (sprawdzone w kodzie 0.51.0)
- Opcje uruchomienia: `--skip-menu`, `--new-game`, `--start`, `--load-savegame`, `--script-run` (plik komend konsoli), `--no-sound`, `--replace=config --config --user-data --data-local`.
- Lua: `openmw.camera` (`setMode`, `setStaticPosition`, `setYaw`, `setPitch`), `GameObject:teleport`, `world.getExteriorCell`, `core.quit`; wyjście tylko przez `print` → `openmw.log`.
- Brak API Lua do zrzutów ekranu (jest tylko akcja klawisza), brak zdalnego sterowania w czasie rzeczywistym, brak odczytu liczników Groundcover.

## Wymaga instrumentacji (fork)
Liczniki instancji per komórka/chunk/model (osobno pluginy i proceduralne), przyczyny odrzuceń kandydatów, czas budowy chunku. Oficjalne rozmieszczenie Groundcover liczymy offline z ESP — jest deterministyczne.

## Etapy i narzędzia
1. **Kod i dane:** `env_status`, `code_diff`, `profile_diff`, `vfs_resolve`, `esp_scan`, `land_query`, `nif_info`, `dds_info`, `gc_reference_stats`.
2. **Diagnostyka:** `log_parse`, `gc_compare`, `loc_stats`.
3. **Testy:** `build_fork` (z wariantami w worktree), `run_test` (scenariusz `--script-run` + mod Lua kamery, limit czasu, zbieranie logów), `run_status/kill`.
4. **Wizualne:** `capture` (zewnętrzne przechwycenie okna), `image_compare`. Wymagane identyczne ustawienia renderowania i zestaw tekstur.

## Kolejność implementacji
Etykiety stanu i porównanie profili → skan ESP/LAND i baseline Remirosa → instrumentacja forka i porównanie liczb → automatyczne uruchomienia → zrzuty i porównania obrazów.
