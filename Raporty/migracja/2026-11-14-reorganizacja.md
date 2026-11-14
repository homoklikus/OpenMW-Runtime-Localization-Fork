# Reorganizacja środowiska — 2026-11-14

## Nowy układ katalogu projektu

```text
OpenMW RLF/
├── Fork/        repo (to repozytorium), wiki, build, install, mods, config, experiments, patches, scripts, releases, assets
├── OpenMW/      repo (oficjalne, tag openmw-0.51.0), mods (Remiros 4.1: tylko `00 Core OpenMW` + `01b Thicker Grass OpenMW`), config (profil referencyjny), scripts
├── Analiza/     remiros/ (oryginalne archiwum, dane analityczne, narzędzia skanowania ESP)
├── MCP-openMW/  (przyszły serwer MCP, pusty)
└── Raporty/     raporty lokalne, surowe dane, poprzednia migracja
```

## Przebieg
- Przeniesienia w obrębie jednego systemu plików (rename), bez kopiowania. Manifest przed i po: 9200/9200 plików, rozmiary i daty bez zmian. Sumy SHA-256 modów (4940) i archiwów zgodne.
- Skrypty (`scripts/env.sh` i reszta, skrypty Python eksperymentu) wyznaczają ścieżki względem swojego położenia — działają bez zmian w `Fork/`.
- Zaktualizowane ścieżki (z kopiami zapasowymi): `install/etc/openmw/openmw.cfg`, `install/bin/openmw.cfg`, `config/openmw-test/{openmw,launcher}.cfg`.
- `build/` nie jest przenośny (CMake zapisuje ścieżki źródła i buildu). Stary katalog odłożono jako nieaktualny; `Fork/build` skonfigurowano i zbudowano od nowa (`scripts/configure.sh`, `build.sh`, `install.sh`).
- Nowy skrypt `scripts/validate-host.sh [--build] [--run]` sprawdza strukturę, oba repozytoria, ścieżki, izolację profili oraz opcjonalnie kompiluje i uruchamia oba silniki.

## Repozytoria
- Fork: `0.5-world` @ `5629d385` = `origin/0.5-world`, drzewo czyste, `upstream` push zablokowany. `origin/main` jest 41 commitów za `0.5-world`.
- Oficjalne: klon `OpenMW/openmw`, odłączony HEAD na `openmw-0.51.0` (`f4bec414`), push zablokowany.
- Historyczna gałąź `morrowind-pl-0.2.1` (tylko w starym lokalnym repo) wskazuje na `f4bec414`, czyli na oficjalne wydanie, i nie zawiera własnych zmian.

## Walidacja na hoście (Debian 13, 2026-11-14)
- `validate-host.sh`: wszystkie kontrole OK (po poprawce odczytu wersji Flatpaka niezależnego od locale: `LC_ALL=C flatpak info` + metainfo; commit źródeł z `manifest.json` rozróżniony od commita pakietu).
- `--build`: konfiguracja CMake w `Fork/build`, kompilacja 1063/1063, instalacja — 36 OK, 0 błędów (GCC 14.2, Qt 6.8.2, OSG 3.6.5).
- `--run`: 35 OK, 0 błędów. Fork (`5629d385e6`) i oficjalne OpenMW (`f4bec41444`) czytają wyłącznie własne profile; fork: lokalizacja 58 933 wpisów; referencja: 7 pluginów Remirosa, „Loaded 701 cells, 105 statics”.
- `--run` od tej pory oznacza błąd, gdy silnik zakończy się niezerowym kodem.
- Ograniczenie: obie sesje testowe zakończyły się we wnętrzu startowym — Groundcover w świecie zewnętrznym nie był jeszcze porównywany.
