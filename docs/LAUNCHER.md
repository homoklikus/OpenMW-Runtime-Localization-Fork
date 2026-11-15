# OpenMWGodot Launcher — dokumentacja techniczna i użytkowa

Wersja launchera: 0.1.0 · warstwa danych `mwcore` 0.3.0 · konwerter `mwconv` 0.1.0

## 1. Komponenty

| | Komponent | Gdzie | Uruchamianie |
|---|---|---|---|
| A | **Launcher** (Qt 6 / PySide6) | `launcher/openmwgodot_launcher/` | `launcher/openmwgodot-launcher` lub `openmwgodot` po instalacji |
| B | **Konwerter** `mwconv` (CLI, działa bez launchera) | `converter/mwconv/` | `python3 -m mwconv convert|verify|clean|scan|inspect` |
| C | **Runtime** (gra, Godot 4.5–4.7) | `godot/` (`res://main.tscn`) | proces Godota uruchamiany przez „Graj” |
| D | **Construction Set 2.0** (wtyczka edytora Godota) | `godot/addons/mw_cs2/` | proces `godot -e` uruchamiany przyciskiem |
| E | **Wspólna warstwa danych** `mwcore` | `converter/mwcore/` | biblioteka (launcher, testy, przyszłe narzędzia) |

Zasada: **start launchera nie uruchamia Godota** (nawet `godot --version`). Godot startuje dopiero po „Graj”,
„Construction Set” albo na żądanie w Ustawieniach → Diagnostyka. Potwierdzone testem
`test_launcher_starts_without_godot` (atrapa Godota rejestrowałaby każde wywołanie).

```
Launcher (Qt) ──► mwcore (profile, mody, plan, walidacja) ──► python -m mwconv convert … (QProcess, MWPROGRESS)
     │                                                   └──► wyniki: <converted>/base, <profil>/out
     ├──► godot --path godot res://main.tscn -- --data=… --base=… --settings=… --profile=…   (gra)
     └──► godot -e --path godot -- --data=… --project=…                                       (CS 2.0)
```

### Dlaczego PySide6

* lekki start (≈0,4 s do pokazania okna w testach offscreen; 0,15 s sam Qt), ~60–80 MB RAM;
* bezpośrednie użycie istniejących modułów Pythona (konwerter, `mwcore`) – bez drugiej implementacji;
* Debian 13 ma pakiety (`python3-pyside6.qtwidgets`), na Windows ten sam kod;
* samodzielna aplikacja: PyInstaller/Nuitka (patrz §9) – gracz nie instaluje środowiska programistycznego.

Natywny C++/Qt nie dawał realnej przewagi: logika danych i konwerter są w Pythonie.

## 2. Katalogi (XDG)

| Rodzaj | Linux (domyślnie) | Zawartość |
|---|---|---|
| kod i binaria | repozytorium / katalog aplikacji | `launcher/`, `converter/`, `godot/` |
| konfiguracja | `~/.config/openmwgodot/` | `launcher.json`, `profiles/<id>.json` |
| dane | `~/.local/share/openmwgodot/` | `converted/base/` (wspólna konwersja), `mods/<id>/`, `profiles/<id>/` (nakładka `out/`, `project/` CS 2.0, `runtime_settings.json`), `saves/<id>/` |
| cache | `~/.cache/openmwgodot/staging/` | rozpakowywanie archiwów modów |
| logi | `~/.local/state/openmwgodot/logs/` | `game-*.log`, `editor-*.log` |
| blokady | `$XDG_RUNTIME_DIR/openmwgodot/locks/` | `game-<profil>.lock`, `editor-<profil>.lock` |

Tryb przenośny: plik `portable.txt` w katalogu głównym aplikacji (obok `launcher/`) albo zmienna
`OPENMWGODOT_PORTABLE=<katalog>` → wszystko w `<katalog>/userdata/`. Windows: `%APPDATA%`/`%LOCALAPPDATA%`.
Uprawnienia administratora nie są potrzebne.

## 3. Formaty

`launcher.json` (zapis atomowy; uszkodzony plik → kopia `*.bad-<czas>` i wartości domyślne):

```json
{"version": 1, "language": "pl", "install": {"kind": "morrowind", "path": "/…/Morrowind"},
 "converted_dir": null, "conversion_scope": "full", "active_profile": "default",
 "godot_path": "", "python_path": "", "project_dir": "", "minimize_on_play": true, "bake": true,
 "launch_args": "", "wizard_done": true, "wizard_step": 4}
```

Profil `profiles/<id>.json`:

```json
{"id": "druga-postac", "name": "Druga postać", "created": 1763212345.0, "version": 1,
 "mods": [{"id": "lepsze-drewno", "enabled": true}, {"id": "nowe-szyldy", "enabled": false}],
 "settings": {"window_mode": "windowed", "resolution": "1920x1080", "scale_3d": 1.0, "vsync": true,
              "max_fps": 0, "shadows": "medium", "load_radius": 1, "view_distance": 1500, "water": true,
              "fog": true, "mouse_sensitivity": 0.0025, "invert_y": false}}
```

Mod `mods/<id>/mod.json` (+ `files/` z rozpakowanym archiwum, `files_index.json` – indeks do konfliktów):

```json
{"id": "lepsze-drewno", "name": "Lepsze Drewno", "data_root": "files/Lepsze Drewno/Data Files",
 "plugins": [{"file": "Lepsze Drewno.esp", "masters": ["Morrowind.esm"], "is_master": false}],
 "archives": [], "files": 3, "archive_name": "Lepsze Drewno.zip", "archive_sha256": "…", "installed": 1763…}
```

Ustawienia dla Runtime `profiles/<id>/runtime_settings.json` = ustawienia profilu + `profile`, `language`.
Rekord konwersji `…/out/.mwconv/conversion_record.json`: podpis zestawu modów (id + SHA-256 archiwów
w kolejności), zakres, nazwy i rozmiary ESM/ESP.

## 4. Profile i mody bez duplikowania gry

* `converted/base` – konwersja czystej instalacji, wspólna dla wszystkich profili.
* Profil z modami: `profiles/<id>/out` = **nakładka** (`mwconv convert --base-out`): tylko zasoby, których
  plik źródłowy różni się od bazy (nowe/podmienione przez mody), plus świat profilu (JSON).
  Modele w nakładce odwołują się do tekstur bazy ścieżkami względnymi; Runtime szuka plików najpierw
  w nakładce, potem w bazie (`--base=`).
* Mody są osobnymi warstwami (`mods/<id>/files/...`), nigdy nie są kopiowane do konwersji ani do gry.
  Kolejność: ESM (gra, potem mody wg profilu), następnie ESP (tak samo); późniejszy mod wygrywa konflikt pliku.
* Zmiana jednego moda/kolejności → przyrostowo: konwerter porównuje źródło (warstwę) i rozmiar/mtime/SHA-256
  każdego zasobu; świat (JSON) jest eksportowany ponownie tylko przy zmianie ESM/ESP lub VFS.
* Usunięcie profilu usuwa jego konfigurację i nakładkę; **zapisy gry (`saves/<id>`) zostają**.

## 5. „Graj”

Walidacja (bez hashowania zasobów, ≈ milisekundy): instalacja, brak trwającej konwersji (QProcess
i blokada `convert.lock` z żywym PID), profil (istniejące mody, spełnione zależności ESM/ESP), stan konwersji
(manifesty JSON czytelne, `export_state.json: complete`, rekord konwersji zgodny z bieżącym zestawem
modów i plików ESM/ESP), znaleziony Godot i projekt. Każdy problem ma komunikat i kieruje na właściwą stronę
(Konwersja / Mody / Ustawienia). Następnie: blokada instancji na profil (druga instancja tylko po zgodzie),
osobny proces Godota (lista argumentów, parametry użytkownika dzielone `shlex` – bez powłoki), log do pliku,
minimalizacja okna, po zakończeniu przywrócenie okna i komunikat z końcówką logu przy kodzie ≠ 0.

Argumenty dla Runtime (po `--`): `--data`, `--base` (gdy nakładka), `--project`, `--settings`, `--profile`,
`--saves`. Runtime przy braku danych kończy się kodem 2 (launcher pokazuje błąd).

## 6. Konwersja

Strona „Konwersja”: źródło (wybór/wykrywanie Steam, Steam Flatpak, GOG, Wine, OpenMW), raport komponentów
(Morrowind/Tribunal/Bloodmoon, ESM + BSA), katalog docelowy, zakres (pełna – zalecana; „Balmora i okolice”
jako test), operacje:

| Operacja | Działanie |
|---|---|
| Konwertuj / aktualizuj | kroki: baza, potem nakładka profilu; przyrostowo; opcjonalnie wypiekanie |
| Weryfikuj | `mwconv verify --deep --no-mark` (obecność i struktura plików, JSON świata) |
| Napraw | verify z oznaczeniem uszkodzonych + konwersja tylko ich |
| Wyczyść cache | `mwconv clean` → lista nieużywanych plików → usunięcie po potwierdzeniu |
| Anuluj | SIGTERM: konwerter kończy bieżące zasoby, zapisuje je i wychodzi z kodem 130; brak częściowych plików; „Konwertuj” wznawia |

Postęp jest rzeczywisty (zdarzenia `MWPROGRESS` z konwertera): etap, `x / y` plików, pasek, błędy zasobów;
etapy bez liczby plików (VFS, ESM) pokazują pasek nieokreślony. Czas pozostały tylko przy ≥ 3% i ≥ 3 s etapu.
„Szybki start” nie jest oferowany, bo Runtime nie obsługuje jeszcze brakujących zasobów w trakcie gry.

## 7. Bezpieczeństwo

* oryginalna instalacja tylko do odczytu (testy porównują SHA-256 całego drzewa przed/po);
* archiwa: blokada path traversal (`..`, ścieżki bezwzględne, litery dysków), dowiązań, archive bomb
  (limit rozmiaru liczony też w trakcie zapisu, liczba plików, współczynnik kompresji), rozpakowanie do
  `staging` i przeniesienie po sukcesie;
* manifest moda nie może wskazać katalogu poza modem (`data_root` sprawdzany po rozwiązaniu ścieżki);
* zapisy atomowe (konfiguracja, profile, manifesty, stan eksportu, wyniki konwersji);
* procesy uruchamiane listą argumentów (QProcess/subprocess), bez powłoki;
* usuwanie (mody, profile, cache) wyłącznie po potwierdzeniu; logi nie zawierają sekretów.

## 8. Testy (automatyczne)

`launcher/tests/test_launcher.py` (Qt offscreen) + `converter/tests/test_mwcore.py`, `test_resilience.py`:

| Wymaganie | Test |
|---|---|
| start launchera bez Godota | `test_launcher_starts_without_godot` |
| poprawna instalacja / brak instalacji | `test_valid_installation_conversion_and_play`, `test_missing_installation_blocks_play`, `test_install_inspect` |
| przerwana konwersja + wznowienie | `test_cancel_resume_and_damaged_cache`, `test_cancel_and_resume` (konwerter) |
| uszkodzony cache | j.w. + `test_corrupt_cache_and_outputs_repair` |
| instalacja moda z archiwum (ZIP, 7z), ataki | `test_mods_install_…`, `test_mod_install_zip_and_7z`, `test_archive_attacks_rejected` |
| konflikty, kolejność, przebudowa tylko zmian | `test_mods_install_conflicts_order_and_incremental_rebuild`, `test_profile_overlay_on_shared_base` |
| profile, ustawienia | `test_profiles_and_settings`, `test_profiles_crud_keeps_saves` |
| uruchomienie gry / błędny kod wyjścia / jedna instancja | `test_valid_…_and_play`, `test_game_error_exit_code_reported`, `test_single_instance_per_profile` |
| Construction Set | `test_editor_launch` |
| integracja z prawdziwym Godotem (gra z nakładką modów + CS) | `test_real_godot_game_and_editor` (MWGODOT_REAL_GODOT) |
| kreator, przerwanie, wznowienie | `test_first_run_wizard_and_resume` |
| brak modyfikacji plików gry | porównanie drzewa w testach konwersji, modów i przerwania |

## 9. Instalacja, uruchamianie, wydanie

Debian 13 / KDE Plasma:

```bash
sudo apt install python3-pyside6.qtwidgets python3-numpy python3-pil python3-py7zr
./tools/install_launcher.sh            # polecenie `openmwgodot` + skrót „OpenMWGodot” w menu, ikona
openmwgodot                            # albo: launcher/openmwgodot-launcher
```

Bez instalacji: `cd launcher && python3 -m openmwgodot_launcher`.
Wersja samodzielna (plan, nie zbudowana w tej sesji): PyInstaller w trybie `--onedir` z `launcher/`,
`converter/` i Pythonem; Godot dołączany jako `bin/godot` (launcher wykrywa go automatycznie).

## 9a. Wygląd (zgodny z grafiką referencyjną)

Układ ekranu głównego odwzorowuje grafikę referencyjną: boczne menu (Strona główna, Konwersja, Mody,
Profile, Ustawienia, Construction Set, Dziennik i diagnostyka, Pomoc), baner, karty „Stan instalacji”
z podglądem, „Aktywny profil”, „Szybkie akcje”, ozdobny przycisk „Graj”, „Ostatnie działania”
i pasek stanu („Gotowy”, „Otwórz katalog danych”, „Logi”, „O projekcie”).

Paleta (`theme.py`) to średnie kolorów z próbek grafiki referencyjnej:

| Element | Kolor |
|---|---|
| tło okna / panel boczny / karty | `#0e0e0e` / `#131314` / `#171819`→`#161717` |
| kafelki szybkich akcji, ramka | `#282522`, `#6e6457` |
| zaznaczenie w menu (złoto) | `#a78850`→`#61481b`, ramka `#c9a865` |
| akcent tekstu i tytułów | `#d7b46e` |
| pasek stanu | `#191714` |
| potwierdzenie / informacja | `#3f8f2c` / `#3a6fb0` |
| niebo banera | `#5e2e2b`→`#8a4e4b` |

**Baner i podgląd.** Pejzaż (wulkan, twierdza, grzybowa wieża) i ilustracja miasta są wycięte z grafiki
referencyjnej wygenerowanej przez autora projektu w ChatGPT; nie pochodzą z gry. Pliki:
`launcher/resources/banner.png` (868×188) i `preview.png` (363×166), bez godła, napisu i podpisu. Launcher rysuje go wyrównanego do prawej, z przejściem w tło pod tytułem.
Gdy pliku brak, używany jest proceduralny pejzaż (`art.banner`).

**Świadome odstępstwa.** Logo *Morrowind* (znak towarowy Bethesdy) zastępuje własne godło
(mosiężny pierścień z górami). Podgląd nie ma podpisu „Balmora”, bo to ilustracja, a nie widok z zaimportowanej gry.
Po pierwszej sesji gry zastępuje go zrzut ostatniego widoku. Po pierwszym uruchomieniu gry podgląd pokazuje
lokalny zrzut ostatniego widoku (`<zapisy profilu>/last_view.png`), który nigdy nie opuszcza komputera.

**Motyw lokalny (opcjonalny).** Własne obrazy można położyć w `~/.config/openmwgodot/theme/`
(w trybie przenośnym: `userdata/config/theme/`):

* `banner.png` — tło banera (ma pierwszeństwo przed `resources/banner.png`) (skalowane i kadrowane do ~1024×140, tytuł rysowany na wierzchu),
* `preview.png` — obraz w karcie „Stan instalacji” (270×150).

Pliki są czytane wyłącznie lokalnie; launcher nie kopiuje ich do repozytorium, raportów ani logów.

## 10. Ograniczenia (0.1.0)

* tłumaczenie angielskie obejmuje ekran główny; pozostałe strony są po polsku (zmiana języka po restarcie);
* brak konfliktów na poziomie rekordów ESP w launcherze (są w CS 2.0 – lista konfliktów komórki);
* brak kolejności pluginów niezależnej od kolejności modów, brak „merged patch”;
* brak integracji z Nexus Mods (zgodnie z wymaganiem – osobny etap);
* dźwięk, język gry, kontroler – sekcje puste/ukryte, bo Runtime ich nie obsługuje;
* zamknięcie launchera przy działającej grze kończy grę (po potwierdzeniu);
* paczka samodzielna (PyInstaller) i Windows – nieprzetestowane.

## 11. Zmiany

Patrz `CHANGELOG.md`.
