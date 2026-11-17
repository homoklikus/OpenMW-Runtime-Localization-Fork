# Porównanie z OpenMW na wirtualnym ekranie (Xvfb)

Gdy sesja pulpitu jest niedostępna (np. zablokowana – MCP-openMW zgłasza „x11 not available”), oficjalne
OpenMW 0.51.0 można uruchomić na wirtualnym ekranie Xvfb, bez dotykania sesji użytkownika, jego profilu OpenMW
ani systemu. Na Ubuntu 22.04 wydanie OpenMW wymaga nowszych glibc/libstdc++ – `setup.sh` pobiera je z Ubuntu 24.04
do katalogu podręcznego i używa tylko dla procesu OpenMW (loader `ld-linux` z tego katalogu).

```
tools/openmw-xvfb/setup.sh [KATALOG]            # domyślnie ~/.cache/openmwgodot/openmw-xvfb
tools/openmw-xvfb/run.sh KATALOG CFG_DIR [argumenty OpenMW…]
python3 tools/openmw-xvfb/drive.py ZRZUTY sleep:5 shot:logo key:Escape click:512,556 type:Test …
```

`CFG_DIR` – katalog z `openmw/openmw.cfg` i `openmw/settings.cfg` (XDG_CONFIG_HOME procesu), np. z `data=`
wskazującym „Data Files” gracza, `content=`, `fallback-archive=` i fallbackami `Movies_*`. Zrzuty zawierają obraz
gry – zostają lokalnie (np. `OpenMW RLF/Raporty/`), nie trafiają do repozytorium.
Ograniczenia: renderowanie programowe (llvmpipe), brak urządzenia dźwięku – synchronizacji dźwięku nie sprawdzimy.

## Porównanie MWScript z OpenMW (`mwscript_compare.py`)

```
tools/openmw-xvfb/mwscript_case.sh tools/openmw-xvfb/mwscript_cases/stats_player.json all [ekran]
#   etapy osobno: compile | omw | omw-base | godot | godot-base | diff   (zmienne: OMW, DATA, GODOT, OUT)
```

Przypadek (JSON): `setup` i `commands` – wiersze MWScript wykonywane w 30. klatce (`delay`), `after` – [klatka,
wiersz] później, `every` – co klatkę, `vars` – zmienne skryptu sondy w migawce, `actors`/`objects`/`items`/
`npc_items`/`globals` – co zapisać, `ignore`/`tol` – pola pomijane i tolerancje, `interior` – komórka jako wnętrze
w Godocie. OpenMW dostaje w kopii konfiguracji (katalog roboczy) dodatek testowy `mwprobe.esp` z jednym skryptem
globalnym (bez danych gry) i skrypt Lua zapisujący migawkę do dziennika (wiersze `MWSNAP`); Godot – sondę
`godot/tests/probe_mwscript.gd` z tym samym skryptem skompilowanym konwerterem. Migawki zawierają tylko liczby
i identyfikatory. Przebieg bazowy (`*-base`: tylko `setup`) pozwala porównać zmiany, gdy wartości wyjściowe obu
silników się różnią (np. gracz bez kreatora postaci). Oryginalne pliki gry ani profil OpenMW nie są zmieniane.
