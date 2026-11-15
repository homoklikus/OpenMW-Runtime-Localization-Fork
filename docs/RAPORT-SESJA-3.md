# OpenMWGodot — raport z sesji 3 (2026-11-15): osobny launcher desktopowy

Zakres: specyfikacja „OpenMWGodot — osobny launcher desktopowy” oraz wygląd i kolory według
grafiki referencyjnej. Dane testowe: wyłącznie własne, syntetyczne. Repozytorium jest lokalne,
niczego nie opublikowano. Fork OpenMW RLF pozostał nietknięty.

## 1. Działający launcher

`launcher/` to aplikacja Qt 6 (PySide6), niezależna od Godota. Start launchera nie uruchamia silnika;
Godot startuje tylko dla „Graj”, dla Construction Set i jednorazowo dla `--version`.

| Funkcja | Stan |
|---|---|
| Ekran główny wg referencji (menu boczne, baner, stan instalacji z podglądem, profil, szybkie akcje, „Graj”, ostatnie działania, pasek stanu) | gotowe |
| „Graj”: szybkie sprawdzenie na podstawie manifestu (instalacja, wynik konwersji, sygnatura modów, Godot, projekt), potem osobny proces | gotowe |
| Konwersja: pierwsza, aktualizacja, weryfikacja, naprawa, czyszczenie cache, katalog docelowy; rzeczywisty postęp, ETA tylko gdy jest wiarygodne, bezpieczne anulowanie i wznowienie | gotowe |
| Pełna konwersja domyślnie; zakres „Balmora” jako opcja zaawansowana, nazwany wprost | gotowe |
| Mody: ZIP/7z, włączanie i wyłączanie, kolejność, zależności ESM/ESP, konflikty plików, przebudowa tylko zmian, mody jako warstwy | gotowe |
| Profile: tworzenie, kopiowanie, zmiana nazwy, usuwanie (zapisy zostają), aktywacja; bez duplikowania gry (nakładka `--base-out`) | gotowe |
| Ustawienia: grafika, sterowanie, język, zaawansowane; dźwięk i kontroler ukryte, bo Runtime ich nie obsługuje | gotowe |
| Construction Set w osobnym procesie, z danymi aktywnego profilu | gotowe |
| Kreator pierwszego uruchomienia z zapamiętywaniem kroków | gotowe |
| XDG, tryb przenośny, bez uprawnień administratora | gotowe |

Bezpieczeństwo: zapisy atomowe konfiguracji i manifestów; rozpakowywanie odporne na path traversal,
ścieżki absolutne, dowiązania i archive bomb; manifest moda nie może wyjść poza katalog moda; procesy
uruchamiane przez QProcess z listą argumentów (bez powłoki); usuwanie tylko po potwierdzeniu; pliki gry
otwierane tylko do odczytu (testy porównują hash drzewa przed i po).

## 2. Wygląd: grafika referencyjna

Układ i paleta odwzorowują referencję. Kolory to średnie z próbek obrazu: tło `#0e0e0e`, panel boczny
`#131314`, karty `#171819`, kafelki `#282522` z ramką `#6e6457`, złote zaznaczenie `#a78850`→`#61481b`,
zielone potwierdzenia, niebieskie informacje, karmazynowe niebo banera `#5e2e2b`→`#8a4e4b`.

Pejzaż na banerze i ilustracja miasta w karcie „Stan instalacji” są wycięte z grafiki referencyjnej
wygenerowanej w ChatGPT (`launcher/resources/banner.png`, `preview.png`), bez godła, napisu i podpisu.
Logo *Morrowind* jest znakiem towarowym Bethesdy, więc zastępuje je własne godło (mosiężny pierścień
z górami).
Po pierwszej sesji gry podgląd pokazuje lokalny zrzut ostatniego widoku. Opcjonalny motyw lokalny:
`~/.config/openmwgodot/theme/banner.png` i `preview.png` (własne obrazy użytkownika, czytane tylko
lokalnie). Szczegóły: `LAUNCHER.md` §9a.

## 3. Zrzuty ekranu

`zrzuty/launcher_01…07` (Qt offscreen, generowane przez `launcher/tools/screenshots.py`):
ekran główny, kreator, konwersja w toku, konwersja zakończona, mody z konfliktem, ustawienia,
ustawienia zaawansowane.

## 4. Test uruchomienia konwertera z launchera

`test_valid_installation_conversion_and_play` i `test_cancel_resume_and_damaged_cache`: launcher uruchamia
prawdziwy `mwconv convert --progress-json` przez QProcess na syntetycznej instalacji. Sprawdzane:
zdarzenia etapów i postępu, rekord konwersji z sygnaturą, stan READY; anulowanie (kod 130) → stan
INCOMPLETE → wznowienie bez ponownej konwersji gotowych plików; uszkodzony cache SQLite → naprawa;
weryfikacja i czyszczenie osieroconych plików; blokada równoległej konwersji (kod 3).

## 5. Test uruchomienia gry Godot

`test_real_godot_game_and_editor` z prawdziwym Godotem (`MWGODOT_REAL_GODOT`): konwersja z modem →
„Graj” → `godot --path godot -- --data … --base … --settings … --profile … --saves … --autotest-frames=N`.
Gra ładuje bazę i nakładkę profilu, renderuje komórki, wypisuje `MWGODOT_STATS` i kończy z kodem 0.
Sprawdzane: `cells > 0`, `models.failed == 0`, `max_fps == 33` (ustawienie z launchera dotarło do gry),
niepusta lista `base_roots`. Testy z atrapą Godota sprawdzają też błędny kod wyjścia (komunikat i log
w launcherze) i jedną instancję gry na profil.

## 6. Test uruchomienia Construction Set

Ten sam test: „Construction Set” → `godot --editor --path godot -- --data … --project … --base …
--profile …`; wtyczka CS 2.0 automatycznie wczytuje świat profilu; edytor kończy z kodem 0 bez
`SCRIPT ERROR`. `test_editor_launch` sprawdza argumenty i blokadę z atrapą.

## 7. Wyniki testów

| Zestaw | Godot 4.7.1 | Godot 4.5.1 |
|---|---|---|
| konwerter + mwcore (pytest, 60) | ✔ | ✔ |
| launcher Qt (12, w tym prawdziwa gra i CS) | ✔ 12/12 | ✔ 12/12 |
| walidator glTF Khronos (8 plików) | ✔ | ✔ |
| test_import (31), test_controllers (20), test_world (30 + 8) | ✔ | ✔ |
| test_editor_import, test_game, test_cs2, test_bake, test_gdextension | ✔ | ✔ |
| zrzuty: modele, świat, efekty, launcher | ✔ | ✔ |

Logi: `testy/run_tests_godot47.log`, `testy/run_tests_godot45.log`.

## 8. Instrukcja dla Debiana 13

```bash
sudo apt install python3-pyside6.qtwidgets python3-numpy python3-pil python3-py7zr
tar xzf mwgodot-sesja3.tar.gz && cd mwgodot
./tools/install_launcher.sh      # polecenie `openmwgodot`, skrót w menu KDE, ikona
openmwgodot
```

Pierwsze uruchomienie: kreator prosi o katalog Morrowinda (wykrywa Steam, Flatpak, GOG, Wine,
openmw.cfg), ścieżkę do Godota 4.7 (`godot` w PATH albo plik binarny), uruchamia pełną konwersję
i kończy. Potem „Graj”. Testy u siebie: `tools/run_tests.sh --godot /ścieżka/godot`.
Pełny opis: `docs/DEBIAN13.md` i `docs/LAUNCHER.md`.

## 9. Ograniczenia i następne kroki

* Pierwsza konwersja prawdziwej instalacji nie była jeszcze uruchomiona (brak plików gry w tej sesji);
  zaczynamy od `mwconv scan` u Ciebie.
* Tłumaczenie angielskie obejmuje tylko ekran główny.
* Konflikty rekordów ESP pokazuje CS 2.0, nie launcher.
* Paczka samodzielna (PyInstaller) i Windows nie były testowane.
