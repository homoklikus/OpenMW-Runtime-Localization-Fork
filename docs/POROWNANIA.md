# Porównania z OpenMW (stanowisko etapu 0)

Narzędzie: serwer MCP-openMW (`OpenMW RLF/MCP-openMW`) + profil **`openmwgodot`** (rodzaj `external`).

* `openmw_capture_plan` / `openmw_capture_start` z `profile_list=["official-ref", "openmwgodot"]` wybiera
  ujęcia (kamera, kierunek, pora, pogoda), robi zrzut w oryginalnym OpenMW, potem w OpenMWGodot, i liczy
  metryki (różnica obrazu RGB, udział pikseli roślinności) oraz arkusze obok siebie.
* Po stronie gry: `tools/capture_godot.py` – dla każdego ujęcia uruchamia Godota w trybie zrzutu
  (`main.gd`: `--camera --look --hour --weather --fov --screenshot`), wynik `shot-<id>.png` + `result.json`.
* Konwencja kamery jak w API Lua OpenMW: yaw = kurs (0 = +Y MW, rośnie w stronę +X), pitch > 0 = w dół;
  pole widzenia 60° pionowo, 1920×1080, 12:00, czyste niebo.
* Wyniki zostają lokalnie: `OpenMW RLF/Raporty/mcp/zrzuty/<przebieg>/` (zrzuty z prawdziwych danych nie
  trafiają do repozytorium).
* Serwery MCP uruchamiane przez Claude Desktop potrzebują zmiennych ekranu (`DISPLAY`, `XAUTHORITY`,
  `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`) w sekcji `env` wpisu w `claude_desktop_config.json`.
