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
| 2.1 | kod w Git (`tools/MCP-openMW/`), test integracyjny przez protokół MCP, liczenie w regionie | 0.2.1 / commit `478677cf7f3f82c2aba2066ee0f88fafa97c39d7` (**bez `__init__.py`**, naprawione w 0.3.0), hash `560428b4b09cef0e4bfc1e49042f6dc17305d991c437b85a577b95fed1eb9a12` | [sprawdzony — Debian 13: testy jednostkowe + integracja 44/44](2026-11-14-wersjonowanie-i-test-integracyjny.md) |
| 2c | emulacja proceduralnej flory forka offline, porównanie z Remirosem, pokrycie regionów | 0.3.0 / `1e8fc71f97da818ab2f8e67b874f49e01d7955594a9e5297e416b35822cba23b` | [sprawdzony — Debian 13: 69/69, integracja 53/53](2026-11-14-etap2c-flora-forka.md) (nie commitowany osobno — wchodzi w 0.4.0) |
| 2c-b | trawa Remirosa w forku: reguły tekstur + mapa liczników, zmiana silnika pach75 (przygotowana) | 0.4.0 / `93f8275f5bcec353de73acd52a3f4fb129722affd204c55bd80a119d0095ec30` | [MCP: sprawdzony — Debian 13: 76/76, integracja 58/58; pach75: zbudowany, w grze aktywny (log), commit `94e5fb45`, scalony z `0.5-world` (`f9f775ae`)](2026-11-14-etap2c-trawa-remirosa-pach75.md) |
| 2c-c | trawa Remirosa: liczniki per pole 4×4 teksela i per statyka, zmiana silnika pach76 (przygotowana); poprawka `_capture_plans` | 0.6.0 / `6d9c78ca069940ceab495e31c07f177bb9e7e9c5025a0ac6e05d2a936d1c3a9f` | [VM: 86/86, zgodność C++ na prawdziwym terenie; wybór kamery z kontrolą zasłonięcia; pach76: sprawdzony w grze i **zatwierdzony**, commit `5ead2e90`, scalony z `0.5-world` (`f9f775ae`)](2026-11-14-pach76-liczniki-w-polach-teksela.md) |
| 2b | parser NIF (bounding boxy, wysokości modeli) | — | planowany |
| 3 | porównania wizualne: uruchamianie obu silników z ujęciami (Lua), zrzuty, porównanie obrazów; 0.5.1: poprawka kierunku kamery, powtórzenia ujęć | 0.5.1 / `b8963dbb8c944351de3588c7b2c581372aba4005caaebef5289631a92dd03e14` | [**zatwierdzony** — pięć przebiegów na Debianie, w tym 7 regionów Remirosa](2026-11-14-etap3-porownania-wizualne.md) |
| 4 | instrumentacja forka (osobna, minimalna zmiana C++) | — | planowany |
| 5 | porównania wizualne | — | planowany |

Założenia architektury: [2026-11-14-architektura-mcp.md](2026-11-14-architektura-mcp.md).
