# MCP-openMW — dokumentacja rozwoju

Wspólny serwer MCP (Model Context Protocol) do analizy i testowania dwóch silników:
- **official** — OpenMW 0.51.0 (Flatpak `org.openmw.OpenMW`, źródła `openmw-0.51.0` = `f4bec414`);
- **fork** — OpenMW Runtime Localization Fork, gałąź `0.5-world`.

Kod MCP leży **poza tym repozytorium**, w katalogu projektu `MCP-openMW/` (obok `Fork/` i `OpenMW/`). Ten katalog zawiera wyłącznie dokumentację.

## Wersjonowanie kodu MCP
Każdy etap podaje wersję pakietu i **hash drzewa źródeł**:
- `MCP-openMW/SOURCE-MANIFEST.sha256` — suma SHA-256 każdego pliku źródłowego, testów, konfiguracji i katalogu sum;
- hash drzewa = `sha256sum SOURCE-MANIFEST.sha256` (to samo wypisuje `python -m openmw_mcp.srcmanifest`);
- zgodność kodu z dokumentowanym stanem: `python -m openmw_mcp.srcmanifest --check`.

Hash trafia także do każdego manifestu testu (`mcp.tree_sha256`), więc wynik testu da się powiązać z wersją MCP.

## Etapy
| Etap | Zakres | Wersja / hash drzewa | Status |
|---|---|---|---|
| 1 | narzędzia tylko do odczytu: instalacje, profile, VFS, mody, flora, manifest testu | 0.1.0 / `efb03baa76271f5e7f8beb74bae79a34bfac3915c116c825793900b19a67708c` | [**zatwierdzony** — Debian 13: 36/36](2026-11-14-etap1-narzedzia-odczytu.md) |
| 2 | dane świata: LAND, emulacja oficjalnego Groundcover, NIF | — | planowany |
| 3 | parser logów, uruchamianie scenariuszy testowych | — | planowany |
| 4 | instrumentacja forka (osobna, minimalna zmiana C++) | — | planowany |
| 5 | porównania wizualne | — | planowany |

Założenia architektury: [2026-11-14-architektura-mcp.md](2026-11-14-architektura-mcp.md).
