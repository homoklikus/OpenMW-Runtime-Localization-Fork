# Format zapisu gry OpenMWGodot — v3 (etap 6; v2 – etap 3; v1 – etap 0)

Plik `*.mwsave` (domyślnie w katalogu zapisów profilu, `--saves`; szybki zapis: `quicksave.mwsave`),
JSON skompresowany Zstandard (`FileAccess.open_compressed`). Kod: `godot/scripts/mw/mw_game_state.gd`.

```json
{
  "format": "mwgodot-save", "version": 3,
  "header": {"profile": "default", "character": "", "game": "OpenMWGodot", "created": "…",
             "world_format": 1,
             "content": [{"name": "Morrowind.esm", "sha256": "…"}, …],   // kolejność ładowania
             "base_fingerprint": "<sha256 listy content>"},
  "refs":    {"morrowind.esm#1234": {"enabled": false},
              "morrowind.esm#88":   {"deleted": true},                    // przedmiot podniesiony ze świata
              "morrowind.esm#91":   {"lock": 0, "trap": ""},              // zamek otwarty kluczem, pułapka rozbrojona
              "tribunal.esm#77":    {"mw": {"pos": [x, y, z], "rot": [rx, ry, rz], "scale": 1.0}}},
  "globals": {}, "time": {"day": 3, "hour": 17.5},
  "player":  {"interior": "", "fly": false, "level": 1, "mw": {"pos": [x, y, z], "rot": [pitch, 0, yaw]},
              // etap 4: postać (wartości bazowe; zmodyfikowane i pochodne liczone przy wczytaniu)
              "character": {"name": "Nerevar", "race": "dark elf", "female": false, "class": "warrior",
                            "birthsign": "warwyrd", "head": "…", "hair": "…", "level": 1,
                            "attributes": [8 liczb], "skills": [27 liczb], "spells": ["ancestor guardian", …],
                            "health": 50, "magicka": 40, "fatigue": 170,
                            // etap 6: frakcje gracza (członkostwo, ranga, wydalenie), reputacja we frakcjach,
                            // reputacja i grzywna gracza
                            "factions": {"blades": {"rank": 0, "expelled": false}},
                            "faction_reputation": {"blades": 1}, "reputation": 0, "bounty": 0}},
  "dyn_next": 3,
  // v2 (etap 3):
  "inventories": {"player": [{"id": "gold_001", "count": 50}],
                  "morrowind.esm#4567": [{"id": "potion_local_brew_01", "count": 2}]},   // pełna zawartość po zmianie
  "dynamic": {"dyn#2": {"base": "misc_com_bottle_01", "cell": "ext:-2,-9", "count": 1,
                        "mw": {"pos": [x, y, z], "rot": [0, 0, yaw], "scale": 1.0}}},     // przedmiot odłożony w świecie
  "seed": 123456,                                                                 // losowanie list poziomowanych
  // etap 5:
  "scripts": {"started": true, "running": ["main", "bloodmoonscript"],                // skrypty globalne
              "locals": {"bloodmoon.esm#1234": {"doonce": 1}, "global:main": {}}},  // zmienne lokalne
  "journal": {"co_9a": 10},                                                       // indeksy zadań
  // v3 (etap 6):
  "dialogue": {"known": {"caius cosades": true, "orders": true},                  // tematy znane graczowi
               "entries": [{"quest": "a1_1_findspymaster", "info": "<id odpowiedzi>", "text": "<tekst po podstawieniach>",
                            "actor": "Caius Cosades", "day": 1, "month": 7, "day_of_month": 16}],  // wpisy dziennika
               "quests": {"a1_1_findspymaster": {"finished": true, "infos": ["<id>", …]}},
               "topics": {"orders": [{"info": "<id>", "text": "…", "actor": "Caius Cosades"}]},  // dziennik tematów
               "npcs": {"morrowind.esm#5678": {"disposition": 60, "talked": true, "fight": 30}},  // postawa, AI
               "reactions": {"blades": {"camonna tong": -5}},                     // zmienione reakcje frakcji
               "deaths": {}, "map_markers": ["Balmora"]}
}
```

Zasady (plan, rewizja 2.0, §2.1–2.4):

* Tylko **różnice** względem danych bazowych z konwertera. Brak wpisu = stan z danych.
* Klucz referencji = stabilny `sid`: `"<plik, który utworzył referencję>#<refnum>"` (małe litery). Plik wyznacza
  się z nagłówka wtyczki (indeks mastera z FRMR), więc ID nie zależy od kolejności ładowania; referencje
  przeniesione (MVRF) i nadpisane przez mody zachowują `sid`. Obiekty utworzone w grze: `dyn#N`.
* Pozycje i kąty w jednostkach Morrowinda – zapis nie zależy od scen, ścieżek ani węzłów Godota.
* Wpisy dla wtyczek, których brakuje, i sekcje nieznane tej wersji gry są **zachowywane** przy ponownym zapisie.
* Odczyt sprawdza zgodność z bieżącymi danymi (brakująca/zmieniona/nowa wtyczka, inna kolejność) i pokazuje
  ostrzeżenia; nic nie jest po cichu usuwane.
* Zapis atomowy (`.tmp` → zmiana nazwy), poprzednia wersja jako `.bak`. Migracja starszego formatu najpierw
  robi kopię `<plik>.v<wersja>.bak`; zapis z nowszej wersji gry – błąd, plik bez zmian.
* Inwentarze: brak wpisu = zawartość z rekordu (CONT/NPC_/CREA) z listami poziomowanymi rozlosowanymi
  deterministycznie wg `seed` i `sid` (ten sam wynik przy każdym wczytaniu komórki); po pierwszej zmianie
  (podniesienie, przełożenie) zapisywana jest pełna zawartość. Złoto zawsze jako `gold_001`.
* Zmienne globalne (GLOB) zmienione przez skrypty – w `globals` (nazwa małymi literami → wartość).
* Postać (etap 4) to nowe pole w `player` – zgodne wstecz w v2; zapis bez postaci dostaje postać domyślną
  (rekord NPC „player”).
* Migracja v1 → v2: nowe sekcje puste, `player.level = 1` (stan świata bez zmian).
* Migracja v2 → v3: pusta sekcja `dialogue` (indeksy zadań z `journal` zostają; wpisy dziennika z tekstem
  powstają od tej wersji). Teksty wpisów są zapisywane po tłumaczeniu i podstawieniach (%PCName…), jak w OpenMW.
* Każdy kolejny etap dopisuje własną sekcję (np. ekwipunek, zmienne skryptów, dziennik) – zmiana znaczenia
  istniejącego pola wymaga nowej wersji i migracji.

Klawisze: **F5** szybki zapis, **F9** szybki odczyt, **Esc** menu pauzy, **E** aktywacja (drzwi, przedmioty,
pojemniki, rozmowa z NPC), **I** ekwipunek, **J** dziennik.
