# Format zapisu gry OpenMWGodot — v5 (etap 7; v3 – etap 6; v2 – etap 3; v1 – etap 0)

Plik `*.mwsave` (domyślnie w katalogu zapisów profilu, `--saves`; szybki zapis: `quicksave.mwsave`),
JSON skompresowany Zstandard (`FileAccess.open_compressed`). Kod: `godot/scripts/mw/mw_game_state.gd`.

```json
{
  "format": "mwgodot-save", "version": 5,
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
                            "faction_reputation": {"blades": 1}, "reputation": 0, "bounty": 0,
                            // etap 7: rozwój, awans, ekwipunek, magia
                            "health_base": 52, "skill_progress": [27 × 0..1], "level_progress": 3,
                            "skill_increases": [8 liczb], "spec_increases": [3 liczby],
                            "equipment": {"16": {"id": "iron dagger", "health": -1}},   // miejsce → przedmiot (-1 = pełny stan)
                            "active_spells": [{"id": "fleabite", "name": "…", "kind": "spell", "caster": "player",
                                               "effects": [{"effect": 14, "skill": -1, "attribute": -1, "min": 1, "max": 1,
                                                            "duration": 3, "time_left": 1.5, "magnitude": 1, "applied": true}]}],
                            "magic_damage": {"attributes": [8], "skills": [27]},          // ubytki (Damage/Drain)
                            "item_charge": {"ring_x": 47.5}, "powers_used": {"moc": 123.0},  // godzina gry
                            "selected_magic": {"kind": "spell", "id": "fleabite"}},
             "mark": {"interior": "", "pos": "x,y,z"}},
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
               "deaths": {}, "map_markers": ["Balmora"]},
  // v4 (etap 7): stan aktorów zmieniony w grze (te same klucze magii co u gracza)
  "actors": {"morrowind.esm#5678": {"health": 20, "fatigue": 80, "magicka": 10, "dead": false, "knocked_down": false,
                                    "attacked": true, "condition": {"16": 250}, "active_spells": [], "magic_damage": {}}},
  // etap 9 (bez zmiany wersji): w „player” – "controls": {"controls": true, "fighting": false, …} (blokady
  //   Disable/EnablePlayer…; brak klucza = dozwolone), "menus": {"inventory": true, "magic": false, "map": …,
  //   "stats": …, "rest": …} (okna odblokowywane skryptami CharGen; brak klucza = dozwolone), "chargen_choice":
  //   {imię, rasa, płeć, głowa, włosy, klasa, znak} (stan menu tworzenia postaci), "weather_override":
  //   {"bitter coast region": "rain"} (ChangeWeather); w „scripts.locals” klucze "inv:<id przedmiotu>" – zmienne
  //   skryptów przedmiotów w ekwipunku gracza (przenoszone ze świata przy podniesieniu)
  // etap 8 (bez zmiany wersji – nowe pola, starsze zapisy działają): w „actors” stan AI aktora
  //   "ai": {"packages": [{"type": "wander", "distance": 512, "remaining": 5, "idle": […], "repeat": false},
  //                       {"type": "pursue", "target": "player", "priority": 2}], "done": false, "last": 0,
  //          "start": [x, y, z]},                     // stos pakietów (AiSequence), punkt startu wędrówki
  //   "alarmed": true, "crime_id": 1                 // świadek przestępstwa / napadnięty przez gracza
  // w „refs” pozycja aktora po ruchu (MW): "morrowind.esm#5678": {"mw": {"pos": [x, y, z], "rot": [0, 0, rz], "scale": 1}}
  // w „player”: "bounty": 40, "stolen": {"misc_com_wood_spoon_01": {"ra'virr": 1}}, "last_exterior": [x, y, z]
  // v5 (etap 7): rekordy utworzone w grze (mikstury z alchemii, zaklęcia i przedmioty zaklęte)
  "created": {"potion": {"mwg_generated_1": {"name": "…", "weight": 0.75, "value": 58, "model": "m\\misc_potion_standard_01.nif",
                                             "effects": [{"effect": 75, "min": 20, "max": 20, "duration": 59, "range": 0}]}},
              "enchantment": {"mwg_generated_2": {"type": 2, "cost": 2, "charge": 5, "effects": […]}},
              "clothing": {"mwg_generated_3": {"name": "…", "enchant": "mwg_generated_2", "source_object": "…", …}}},
  "created_next": 4
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
* Migracja v3 → v4: pusta sekcja `actors`; v4 → v5: puste `created`, `created_next = 1`.
* Etap 8: pozycje NPC są zapisywane przy opuszczeniu komórki, przejściu przez drzwi i zapisie gry (w `refs[sid].mw`),
  stos pakietów AI w `actors[sid].ai` (tworzony z rekordu przy pierwszym użyciu, jak `AiSequence::fill`).
  Pakiet `pursue` (pościg strażnika) jest zapisywany jak pozostałe; walka (`combat`) też – po odczycie trwa dalej.
  `player.stolen` – skradzione przedmioty z właścicielem (konfiskata przy grzywnie/więzieniu), `player.bounty` – grzywna.
* Kamień dusz z duszą to w inwentarzu id `<kamień>@<stworzenie>` (osobny stos, jak dusza w CellRef OpenMW).
* Przedmioty i mikstury utworzone w grze mają id `mwg_generated_N`; rekord identyczny z istniejącym jest używany
  ponownie (jak `Alchemy::getRecord`/`Enchanting::getRecord`).
* Każdy kolejny etap dopisuje własną sekcję (np. ekwipunek, zmienne skryptów, dziennik) – zmiana znaczenia
  istniejącego pola wymaga nowej wersji i migracji.

Klawisze: **F5** szybki zapis, **F9** szybki odczyt, **Esc** menu pauzy, **E** aktywacja (drzwi, przedmioty,
pojemniki, rozmowa z NPC), **I** ekwipunek, **J** dziennik, **T** odpoczynek, **F** broń, **R** magia, **M** okno magii,
lewy przycisk – atak/rzucenie.
