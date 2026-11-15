# Format zapisu gry OpenMWGodot — v1 (etap 0)

Plik `*.mwsave` (domyślnie w katalogu zapisów profilu, `--saves`; szybki zapis: `quicksave.mwsave`),
JSON skompresowany Zstandard (`FileAccess.open_compressed`). Kod: `godot/scripts/mw/mw_game_state.gd`.

```json
{
  "format": "mwgodot-save", "version": 1,
  "header": {"profile": "default", "character": "", "game": "OpenMWGodot", "created": "…",
             "world_format": 1,
             "content": [{"name": "Morrowind.esm", "sha256": "…"}, …],   // kolejność ładowania
             "base_fingerprint": "<sha256 listy content>"},
  "refs":    {"morrowind.esm#1234": {"enabled": false},
              "tribunal.esm#77":    {"mw": {"pos": [x, y, z], "rot": [rx, ry, rz], "scale": 1.0}}},
  "globals": {}, "time": {"day": 3, "hour": 17.5},
  "player":  {"interior": "", "fly": false, "mw": {"pos": [x, y, z], "rot": [pitch, 0, yaw]}},
  "dyn_next": 1
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
* Każdy kolejny etap dopisuje własną sekcję (np. ekwipunek, zmienne skryptów, dziennik) – zmiana znaczenia
  istniejącego pola wymaga nowej wersji i migracji.

Klawisze: **F5** szybki zapis, **F9** szybki odczyt, **Esc** menu pauzy.
