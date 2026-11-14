# MCP-openMW — dokumentacja rozwoju

Wspólny serwer MCP (Model Context Protocol) do analizy i testowania dwóch silników:
- **official** — OpenMW 0.51.0 (Flatpak `org.openmw.OpenMW`, źródła `openmw-0.51.0` = `f4bec414`);
- **fork** — OpenMW Runtime Localization Fork, gałąź `0.5-world`.

Kod MCP: [`tools/MCP-openMW/`](../../tools/MCP-openMW/) w tym repozytorium (od wersji 0.2.1). W katalogu projektu `MCP-openMW/` jest dowiązaniem do niego. Ten katalog zawiera dokumentację. Szczegóły: [wersjonowanie i test integracyjny](2026-11-14-wersjonowanie-i-test-integracyjny.md).

## Wersjonowanie kodu MCP
Podstawowy identyfikator wersji to commit tego repozytorium. Każdy etap podaje też wersję pakietu i **hash drzewa źródeł**:
- `MCP-openMW/SOURCE-MANIFEST.sha256` — suma SHA-256 każdego pliku źródłowego, testów, konfiguracji i katalogu sum;
- hash drzewa = `sha256sum SOURCE-MANIFEST.sha256` (to samo wypisuje `python -m openmw_mcp.srcmanifest`);
- zgodność kodu z dokumentowanym stanem: `python -m openmw_mcp.srcmanifest --check`.

Hash trafia także do każdego manifestu testu (`mcp.tree_sha256`), więc wynik testu da się powiązać z wersją MCP.

## Etapy
| Etap | Zakres | Wersja / hash drzewa | Status |
|---|---|---|---|
| 1 | narzędzia tylko do odczytu: instalacje, profile, VFS, mody, flora, manifest testu | 0.1.0 / `efb03baa76271f5e7f8beb74bae79a34bfac3915c116c825793900b19a67708c` | [**zatwierdzony** — Debian 13: 36/36](2026-11-14-etap1-narzedzia-odczytu.md) |
| 2 | dane świata: LAND/LTEX, emulacja oficjalnego Groundcover offline | 0.2.0 / `26512797b6a68e7e95d0f414097a2203754e3988129ee921be73b7f101b96af4` | [sprawdzony — Debian 13: 46/46](2026-11-14-etap2-teren-i-baseline.md) |
| 2.1 | kod w Git (`tools/MCP-openMW/`), test integracyjny przez protokół MCP, liczenie w regionie | 0.2.1 / `560428b4b09cef0e4bfc1e49042f6dc17305d991c437b85a577b95fed1eb9a12` | [sprawdzony — Debian 13: testy jednostkowe + integracja 44/44](2026-11-14-wersjonowanie-i-test-integracyjny.md) |
| 2c | emulacja proceduralnej flory forka offline (generator, ziarna, PGRD) | — | planowany (rozpoznanie w dokumencie etapu 2) |
| 2b | parser NIF (bounding boxy, wysokości modeli) | — | planowany |
| 3 | parser logów, uruchamianie scenariuszy testowych | — | planowany |
| 4 | instrumentacja forka (osobna, minimalna zmiana C++) | — | planowany |
| 5 | porównania wizualne | — | planowany |

Założenia architektury: [2026-11-14-architektura-mcp.md](2026-11-14-architektura-mcp.md).
