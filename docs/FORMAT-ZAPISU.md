# Format zapisu gry OpenMWGodot — v2 (etap 3; v1 – etap 0)

Plik `*.mwsave` (domyślnie w katalogu zapisów profilu, `--saves`; szybki zapis: `quicksave.mwsave`),
JSON skompresowany Zstandard (`FileAccess.open_compressed`). Kod: `godot/scripts/mw/mw_game_state.gd`.

```json
{
  "format": "mwgodot-save", "version": 2,
  "header": {"profile": "default", "character": "", "game": "OpenMWGodot", "created": "…",
             "world_format": 1,
             "content": [{"name": "Morrowind.esm", "sha256": "…"}, …],   // kolejność ładowania
             "base_fingerprint": "<sha256 listy content>"},
  "refs":    {"morrowind.esm#1234": {"enabled": false},
              "morrowind.esm#88":   {"deleted": true},                    // przedmiot podniesiony ze świata
              "morrowind.esm#91":   {"lock": 0, "trap": ""},              // zamek otwarty kluczem, pułapka rozbrojona
              "tribunal.esm#77":    {"mw": {"pos": [x, y, z], "rot": [rx, ry, rz], "scale": 1.0}}},
  "globals": {}, "time": {"day": 3, "hour": 17.5},
  "player":  {"interior": "", "fly": false, "level": 1, "mw": {"pos": [x, y, z], "rot": [pitch, 0, yaw]}},
  "dyn_next": 3,
  // v2 (etap 3):
  "inventories": {"player": [{"id": "gold_001", "count": 50}],
                  "morrowind.esm#4567": [{"id": "potion_local_brew_01", "count": 2}]},   // pełna zawartość po zmianie
  "dynamic": {"dyn#2": {"base": "misc_com_bottle_01", "cell": "ext:-2,-9", "count": 1,
                        "mw": {"pos": [x, y, z], "rot": [0, 0, yaw], "scale": 1.0}}},     // przedmiot odłożony w świecie
  "seed": 123456                                                                  // losowanie list poziomowanych
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
* Migracja v1 → v2: nowe sekcje puste, `player.level = 1` (stan świata bez zmian).
* Każdy kolejny etap dopisuje własną sekcję (np. ekwipunek, zmienne skryptów, dziennik) – zmiana znaczenia
  istniejącego pola wymaga nowej wersji i migracji.

Klawisze: **F5** szybki zapis, **F9** szybki odczyt, **Esc** menu pauzy, **E** aktywacja (drzwi, przedmioty,
pojemniki), **I** ekwipunek.
