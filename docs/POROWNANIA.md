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

Zgodnie z planem (rewizja 2.0, §2.7 i §6): porównania wizualne są **referencyjne** – nie blokują rozwoju
progami podobieństwa obrazu. Zgodność obowiązkową (dane, rozmieszczenie, ID, mechanika, skrypty, zapisy)
sprawdzamy liczbowo (np. `openmw_remiros_compare`, porównania rekordów).

## Ujęcia NPC (etap 2d, MCP-openMW 0.9.0)

* `openmw_capture_npcs(cells=["-2,-9","-3,-2"], start=True)` – kamera przed każdym NPC (do 4 na komórkę albo
  lista `npcs`), w odległości 230 jednostek, pole widzenia 55°. W OpenMW aktor jest na czas ujęcia **zamrażany**
  (skrypt `actor.lua`: bez pakietów AI, bez ruchu, teleport na pozycję z danych) – jak w porcie, gdzie NPC stoją.
  Pozy mogą się różnić (zamrożona klatka chodu albo pływania) – porównanie dotyczy wyglądu i ekwipunku.
* Kolejka ujęć: plik `Raporty/mcp/zrzuty/kolejka-ujec.json` (`{"shots": [...]}`) zastępuje ujęcia następnego
  `openmw_capture_start` – np. ujęcia wyliczone skryptem, bez restartu serwera MCP; po użyciu plik trafia do
  katalogu przebiegu.
* Zrzuty Godota są robione bez vsync: przy zablokowanym ekranie kompozytor dławi klatki okna z vsync.
