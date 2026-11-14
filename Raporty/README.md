# Raporty projektu OpenMW Runtime Localization Fork

Zwięzłe podsumowania zmian, patchy, testów i decyzji technicznych. Surowe dane, logi i duże wyniki trzymamy lokalnie, poza repozytorium.

| Katalog | Zawartość |
|---|---|
| [`migracja/`](migracja/) | reorganizacje środowiska pracy |
| [`patche/`](patche/) | różnice forka względem oficjalnego OpenMW, architektura modyfikacji |
| [`groundcover/`](groundcover/) | proceduralna flora, profile Remirosa, eksperymenty |
| [`mcp/`](mcp/) | założenia przyszłego serwera MCP |

## Trzy stany kodu — zawsze rozróżniaj

| # | Stan | Identyfikator |
|---|---|---|
| 1 | Oficjalne OpenMW 0.51.0 | tag `openmw-0.51.0` = `f4bec41444214a7903bebd178389ca22ca13f646` (Flatpak `org.openmw.OpenMW` 0.51.0 jest zbudowany z tego commita) |
| 2 | Fork, gałąź `0.5-world` | `5629d385e69ef45f5bfb350cb01783409f7139fc` = stan 1 + 72 commity |
| 3 | Eksperyment Azura's Coast | niezatwierdzony diff `groundcover.cpp` (+322/−56), poza repozytorium |

Wyników eksperymentu (3) nie traktujemy jako funkcji gałęzi (2). Porównania (1)↔(2) wykonujemy na profilach o tych samych ustawieniach renderowania i zestawie modów.

Zasoby bazowe Groundcover dla obu stanów: Remiros' Groundcover 4.1 `00 Core OpenMW` + `01b Thicker Grass OpenMW` (z grzybami) — zweryfikowane po SHA-256 jako wariant używany historycznie.

## Dokumenty z 2026-11-14
- [Reorganizacja środowiska](migracja/2026-11-14-reorganizacja.md)
- [Fork vs OpenMW 0.51.0 — różnice i architektura](patche/2026-11-14-fork-vs-openmw-0.51.0.md)
- [Groundcover: stan forka, Remiros, eksperyment AC](groundcover/2026-11-14-groundcover-stan.md)
- [Remiros: wariant historyczny i referencyjny](groundcover/2026-11-14-remiros-wariant-historyczny.md)
- [Założenia architektury MCP](mcp/2026-11-14-architektura-mcp.md)
