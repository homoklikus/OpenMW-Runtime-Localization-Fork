"""Katalog angielski launchera i komunikatów mwcore: tekst źródłowy (polski) → angielski.

Każdy klucz `tr()`/`N_()` w launcherze i mwcore musi mieć tu wpis (test `test_i18n` w launcher/tests).
Etykiety opcji gry mają oba języki w `mwcore.settings.GAME_SCHEMA` (label_pl / label_en)."""

EN: dict[str, str] = {
    "plik":
        "file",
    "Usunięto profil „{name}” (zapisy gry zachowane)":
        "Deleted profile “{name}” (saved games kept)",
    "dzisiaj, %H:%M":
        "today, %H:%M",
    "pliki":
        "files",
    "plików":
        "files",
    "Graj":
        "Play",
    "Morrowind na silniku Godot":
        "Morrowind on the Godot engine",
    "Profil to zestaw aktywnych modów i ich kolejności, ustawienia gry i zapisy. Przekonwertowana gra jest wspólna – profil z modami przechowuje tylko różnice. Usunięcie profilu nie usuwa zapisów gry.":
        "A profile is a set of active mods and their order, game settings and saved games. The converted game is shared – a profile with mods stores only the differences. Deleting a profile does not delete saved games.",
    "Nowy profil":
        "New profile",
    "Nazwa:":
        "Name:",
    "Utworzono profil „{name}”":
        "Created profile “{name}”",
    "Stan instalacji":
        "Installation status",
    "Widok z ostatniej sesji gry (zapisywany lokalnie) albo ilustracja":
        "View from the last game session (stored locally) or an illustration",
    "Aktywny profil":
        "Active profile",
    "Zarządzaj profilami":
        "Manage profiles",
    "Szybkie akcje":
        "Quick actions",
    "Ostatnie działania":
        "Recent activity",
    "Morrowind (gra podstawowa)":
        "Morrowind (base game)",
    "Aktywne mody: {v}":
        "Active mods: {v}",
    "Ostatnia konwersja: {human_time}":
        "Last conversion: {human_time}",
    "Konfiguracja: {config}":
        "Configuration: {config}",
    "Dane: {data}":
        "Data: {data}",
    "Logi: {logs}":
        "Logs: {logs}",
    "Projekt gry: {v}":
        "Game project: {v}",
    "Ostatnie działania:":
        "Recent activity:",
    "\nSprawdzenie Godota: {g} → {v}":
        "\nGodot check: {g} → {v}",
    "<b>1. Konwersja</b> – wskaż swoją legalną instalację Morrowinda (Steam, GOG lub ręczną). Konwerter lokalnie przygotuje modele, tekstury, teren i świat. Oryginalne pliki nie są zmieniane, a wyników nie wolno publikować.<br><br><b>2. Mody</b> – instaluj archiwa ZIP/7z; każdy mod to osobna warstwa, mod niżej na liście wygrywa konflikty, „Zastosuj” przebudowuje tylko zmienione zasoby.<br><br><b>3. Profile</b> – różne zestawy modów i ustawień; przekonwertowana gra jest wspólna.<br><br><b>4. Graj</b> – gra startuje w osobnym procesie Godota. Sterowanie: WASD, mysz, Spacja – skok, Shift – bieg, E – drzwi, F – broń, R – magia, M – okno magii, F6 – latanie (test).<br><br><b>Construction Set</b> – edytor świata w Godocie; zmiany zapisuje jako warstwę projektu, bez nadpisywania ESM/ESP.<br><br>Dokumentacja: <i>docs/LAUNCHER.md</i> i <i>docs/DEBIAN13.md</i> w katalogu projektu.":
        "<b>1. Conversion</b> – point to your legal Morrowind installation (Steam, GOG or manual). The converter prepares models, textures, terrain and the world locally. The original files are not changed, and the results must not be published.<br><br><b>2. Mods</b> – install ZIP/7z archives; each mod is a separate layer, the mod lower in the list wins conflicts, “Apply” rebuilds only the changed assets.<br><br><b>3. Profiles</b> – different sets of mods and settings; the converted game is shared.<br><br><b>4. Play</b> – the game starts in a separate Godot process. Controls: WASD, mouse, Space – jump, Shift – run, E – doors, F – weapon, R – magic, M – magic window, F6 – flying (test).<br><br><b>Construction Set</b> – world editor in Godot; changes are saved as a project layer, without overwriting ESM/ESP.<br><br>Documentation: <i>docs/LAUNCHER.md</i> and <i>docs/DEBIAN13.md</i> in the project directory.",
    "O projekcie":
        "About",
    "{APP_NAME} {version__} (alpha)\n\nEksperymentalny port Morrowinda na Godot 4. Projekt nie zawiera danych Bethesdy – gracz dostarcza własną, legalną instalację, konwertowaną lokalnie.\n\nMorrowind® i The Elder Scrolls® są znakami towarowymi ZeniMax Media Inc. Projekt nie jest z nimi powiązany.\n\nSilnik: Godot Engine ({GODOT_URL}) – Godot Foundation i społeczność Godota. Projekt nie jest oficjalnym produktem Godot Foundation.\n{GODOT_LOGO_CREDIT}.\n\nKod: licencja GNU GPL w wersji 3 lub późniejszej (jak OpenMW). Kod źródłowy: github.com/homoklikus/OpenMW-Runtime-Localization-Fork (gałąź OpenMWGoDot).":
        "{APP_NAME} {version__} (alpha)\n\nAn experimental port of Morrowind to Godot 4. The project contains no Bethesda data – the player provides their own legal installation, converted locally.\n\nMorrowind® and The Elder Scrolls® are trademarks of ZeniMax Media Inc. The project is not affiliated with them.\n\nEngine: Godot Engine ({GODOT_URL}) – the Godot Foundation and the Godot community. The project is not an official product of the Godot Foundation.\n{GODOT_LOGO_CREDIT}.\n\nCode: GNU GPL version 3 or later (like OpenMW). Source code: github.com/homoklikus/OpenMW-Runtime-Localization-Fork (branch OpenMWGoDot).",
    "Konwersja zakończona pomyślnie ({n} {files_word}, {human_size})":
        "Conversion completed successfully ({n} {files_word}, {human_size})",
    "Zaimportowano projekt gry po aktualizacji":
        "Imported the game project after an update",
    "Import projektu gry nie powiódł się":
        "Importing the game project failed",
    "Gra zakończyła się błędem (kod {code})":
        "The game exited with an error (code {code})",
    "Construction Set zakończył się błędem (kod {code})":
        "Construction Set exited with an error (code {code})",
    "Nowy":
        "New",
    "Kopiuj":
        "Copy",
    "Zmień nazwę":
        "Rename",
    "Usuń":
        "Delete",
    "Ustaw aktywny":
        "Set active",
    "   ✓ aktywny":
        "   ✓ active",
    "{name}   [{id}]   mody: {v}{mark}":
        "{name}   [{id}]   mods: {v}{mark}",
    "Kopiuj profil":
        "Copy profile",
    "Nazwa kopii:":
        "Name of the copy:",
    "Skopiowano profil „{name}” jako „{name2}”":
        "Copied profile “{name}” as “{name2}”",
    "Nowa nazwa:":
        "New name:",
    "Usuń profil":
        "Delete profile",
    "Usunąć profil „{name}”?\n\nZostaną usunięte jego ustawienia i nakładka konwersji. Zapisy gry NIE zostaną usunięte.":
        "Delete profile “{name}”?\n\nIts settings and conversion overlay will be deleted. Saved games will NOT be deleted.",
    "Konwersja":
        "Conversion",
    "Aktualizuj\nzasoby gry":
        "Update\ngame assets",
    "Mody":
        "Mods",
    "Instaluj i zarządzaj\nmodami":
        "Install and manage\nmods",
    "Ustawienia":
        "Settings",
    "Grafika,\nsterowanie":
        "Graphics,\ncontrols",
    "Edytor świata\ni modów":
        "World and mod\neditor",
    "Nie wskazano instalacji Morrowinda":
        "No Morrowind installation selected",
    "Konwersja → Wybierz… / Wykryj":
        "Conversion → Browse… / Detect",
    "Konwersja w toku":
        "Conversion in progress",
    "postęp na stronie Konwersja":
        "progress on the Conversion page",
    "Rozmiar danych: ":
        "Data size: ",
    "Gra działa":
        "Game running",
    "Dziennik i diagnostyka":
        "Log and diagnostics",
    "Sprawdź Godota":
        "Check Godot",
    "Ostatni log gry":
        "Last game log",
    "Ostatni log edytora":
        "Last editor log",
    "Otwórz katalog logów":
        "Open log directory",
    "Brak logów.":
        "No logs.",
    "Pomoc":
        "Help",
    "Strona główna":
        "Home",
    "Profile":
        "Profiles",
    "Otwórz katalog danych":
        "Open data directory",
    "Logi":
        "Logs",
    "Godot: znaleziono":
        "Godot: found",
    "Godot: brak":
        "Godot: missing",
    "Konwersja w toku…":
        "Conversion in progress…",
    "Konwersja przerwana – ukończone zasoby zachowane":
        "Conversion interrupted – completed assets kept",
    "Konwersja nie powiodła się (kod {code})":
        "Conversion failed (code {code})",
    "Gra":
        "Game",
    "Gra już działa w tym profilu.":
        "The game is already running in this profile.",
    "Nie można uruchomić gry":
        "Cannot start the game",
    "Przygotowanie projektu gry po aktualizacji (import Godota)…":
        "Preparing the game project after an update (Godot import)…",
    "Błąd":
        "Error",
    "Nie udało się uruchomić Godota:\n{v}":
        "Could not start Godot:\n{v}",
    "Gra zakończyła się błędem":
        "The game exited with an error",
    "Kod wyjścia: {code}\nLog: {log}\n\n{log_tail}":
        "Exit code: {code}\nLog: {log}\n\n{log_tail}",
    "Edytor już działa.":
        "The editor is already running.",
    "Nie można uruchomić edytora":
        "Cannot start the editor",
    "Nie udało się uruchomić Construction Set.":
        "Could not start the Construction Set.",
    "Construction Set zakończył się błędem":
        "Construction Set exited with an error",
    "{name} (kopia)":
        "{name} (copy)",
    "Profil":
        "Profile",
    "Zasoby przekonwertowane":
        "Converted assets",
    "Brak działań – zacznij od wskazania instalacji Morrowinda.":
        "No activity yet – start by selecting your Morrowind installation.",
    " (wersja nie sprawdzona)":
        " (version not checked)",
    "Gra już działa":
        "The game is already running",
    "W tym profilu działa już gra (PID {holder}). Uruchomić drugą instancję?":
        "A game is already running in this profile (PID {holder}). Start a second instance?",
    "Import projektu":
        "Project import",
    "Przerwać konwersję i zamknąć launcher? Ukończone zasoby zostaną zachowane, konwersję można później wznowić.":
        "Stop the conversion and close the launcher? Completed assets will be kept, the conversion can be resumed later.",
    "Gra nadal działa. Zamknąć launcher? Gra zostanie zamknięta.":
        "The game is still running. Close the launcher? The game will be closed.",
    "brak – wymagany":
        "missing – required",
    "nie zainstalowano":
        "not installed",
    "Zasoby: ":
        "Assets: ",
    "Profil gotowy do gry":
        "Profile ready to play",
    "Profil wymaga uwagi":
        "Profile needs attention",
    "nie znaleziono":
        "not found",
    "nie działa":
        "not working",
    "Gotowy":
        "Ready",
    "Godot nie zaimportował projektu gry:\n":
        "Godot did not import the game project:\n",
    "Wymaga uwagi: ":
        "Needs attention: ",
    "Logo Godot Engine © 2017 Andrea Calabró, licencja CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), zmienione: wersja szara; Godot Foundation, godotengine.org":
        "Godot Engine logo © 2017 Andrea Calabró, licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), modified: grey version; Godot Foundation, godotengine.org",
    "Brak przekonwertowanych danych gry. Uruchom konwersję.":
        "No converted game data. Run the conversion.",
    "Konwersja jest niekompletna (przerwana?). Wznów ją albo napraw.":
        "The conversion is incomplete (interrupted?). Resume or repair it.",
    "Trwa konwersja (inny proces).":
        "A conversion is in progress (another process).",
    "Wykryto instalację Morrowinda ({join})":
        "Detected a Morrowind installation ({join})",
    "Katalog {p} leży w katalogu projektu ({repo}). Przekonwertowane dane zawierają zasoby gry i nie mogą trafić do repozytorium – wybierz katalog poza projektem.":
        "Directory {p} is inside the project directory ({repo}). Converted data contains game assets and must not end up in the repository – choose a directory outside the project.",
    "Dane wymagają aktualizacji: ":
        "The data needs an update: ",
    ". Użyj „Napraw”.":
        ". Use “Repair”.",
    "Katalog {p} leży w instalacji gry ({ip}) – wybierz inny, gra musi zostać nietknięta.":
        "Directory {p} is inside the game installation ({ip}) – choose another one, the game must stay untouched.",
    "nie wskazano instalacji Morrowinda":
        "no Morrowind installation selected",
    "{v} ({v2}) wymaga: {join}":
        "{v} ({v2}) requires: {join}",
    "Uszkodzone dane konwersji: ":
        "Damaged conversion data: ",
    "Nie znaleziono Godota 4 (ustaw ścieżkę w Ustawieniach → Zaawansowane).":
        "Godot 4 not found (set the path in Settings → Advanced).",
    "Nie znaleziono projektu gry (project.godot).":
        "Game project not found (project.godot).",
    "Nie wskazano poprawnej instalacji Morrowinda.":
        "No valid Morrowind installation selected.",
    "Trwa konwersja – poczekaj na jej zakończenie albo ją przerwij.":
        "A conversion is running – wait for it to finish or stop it.",
    "Profil odwołuje się do nieistniejących modów: ":
        "The profile refers to mods that do not exist: ",
    "Pliki gry":
        "Game files",
    "Świat (ESM/ESP)":
        "World (ESM/ESP)",
    "Modele":
        "Models",
    "Tekstury":
        "Textures",
    "Wypiekanie scen":
        "Baking scenes",
    "Gra bazowa":
        "Base game",
    "Mody profilu":
        "Profile mods",
    " · pozostało ok. {m} min {sec:02d} s":
        " · about {m} min {sec:02d} s left",
    " · pozostało ok. {sec} s":
        " · about {sec} s left",
    "weryfikacja: {total_bad} uszkodzonych":
        "verification: {total_bad} damaged",
    "usunięto {v}":
        "deleted {v}",
    "Katalog Morrowinda, „Data Files” albo openmw.cfg":
        "Morrowind directory, “Data Files” or openmw.cfg",
    "Wybierz…":
        "Browse…",
    "Wykryj":
        "Detect",
    "Pełna konwersja (zalecana)":
        "Full conversion (recommended)",
    "Tylko Balmora i okolice (test)":
        "Only Balmora and surroundings (test)",
    "Szybki start (gra przed końcem konwersji) będzie dostępny, gdy Runtime nauczy się bezpiecznie obsługiwać brakujące zasoby.":
        "Quick start (playing before the conversion finishes) will become available when the Runtime can safely handle missing assets.",
    "Konwertuj / aktualizuj":
        "Convert / update",
    "Weryfikuj":
        "Verify",
    "Napraw":
        "Repair",
    "Wyczyść cache":
        "Clear cache",
    "Anuluj":
        "Cancel",
    "Katalog Morrowinda":
        "Morrowind directory",
    "Katalog na przekonwertowane dane":
        "Directory for converted data",
    "Kroki: {join}":
        "Steps: {join}",
    "Przerywanie – kończenie bieżących zasobów…":
        "Stopping – finishing the current assets…",
    "weryfikacja ok":
        "verification ok",
    "<span style='color:{WARN}'>Weryfikacja: {total_bad} uszkodzonych plików, {v} problemów świata</span>":
        "<span style='color:{WARN}'>Verification: {total_bad} damaged files, {v} world problems</span>",
    "Usunięto {v} nieużywanych plików.":
        "Deleted {v} unused files.",
    "{get}: {get2} — {done} / {total} plików{fmt_eta}":
        "{get}: {get2} — {done} / {total} files{fmt_eta}",
    "<span style='color:{ERR}'>Błędy zasobów: {errors}</span> (szczegóły w logu i raporcie konwersji)":
        "<span style='color:{ERR}'>Asset errors: {errors}</span> (details in the log and the conversion report)",
    "<span style='color:{OK}'>Konwersja zakończona</span>":
        "<span style='color:{OK}'>Conversion completed</span>",
    "<span style='color:{WARN}'>Przerwano – ukończone zasoby zachowane; „Konwertuj” wznowi pracę</span>":
        "<span style='color:{WARN}'>Interrupted – completed assets kept; “Convert” resumes the work</span>",
    "<span style='color:{ERR}'>Konwersja nie powiodła się (kod {code}) – zobacz log</span>":
        "<span style='color:{ERR}'>Conversion failed (code {code}) – see the log</span>",
    "Źródło:":
        "Source:",
    "Cel:":
        "Target:",
    "Zakres:":
        "Scope:",
    "<i>Wskaż instalację gry (Steam, GOG lub ręczną).</i>":
        "<i>Select the game installation (Steam, GOG or manual).</i>",
    "<span style='color:{WARN}'>Nie wykryto instalacji – wskaż ją ręcznie.</span>":
        "<span style='color:{WARN}'>No installation detected – select it manually.</span>",
    "Katalog docelowy":
        "Target directory",
    "Źródło nie jest poprawną instalacją Morrowinda.":
        "The source is not a valid Morrowind installation.",
    "Zamknij grę przed konwersją.":
        "Close the game before converting.",
    "<span style='color:{OK}'>Weryfikacja: dane kompletne</span>":
        "<span style='color:{OK}'>Verification: data complete</span>",
    "Naprawa: ponowna konwersja tylko uszkodzonych/brakujących zasobów…":
        "Repair: converting again only damaged/missing assets…",
    "Czyszczenie":
        "Cleanup",
    "Brak nieużywanych plików.":
        "No unused files.",
    "Usunąć {v} nieużywanych plików z katalogu konwersji?\nOryginalna instalacja gry nie jest zmieniana.":
        "Delete {v} unused files from the conversion directory?\nThe original game installation is not changed.",
    " (bez BSA)":
        " (without BSA)",
    "{out}: brak konwersji":
        "{out}: not converted",
    "zainstalowano {id}":
        "installed {id}",
    "Zainstalowano mod „{name}”":
        "Installed mod “{name}”",
    "Kolejność pluginów: {join}":
        "Plugin order: {join}",
    "Konflikty plików: {v} (między modami: {v2}) – wygrywa mod niżej na liście":
        "File conflicts: {v} (between mods: {v2}) – the mod lower in the list wins",
    "Archiwum: {archive_name}  (SHA-256 {v}…)":
        "Archive: {archive_name}  (SHA-256 {v}…)",
    "Plików: {files}, katalog danych: {data_root}":
        "Files: {files}, data directory: {data_root}",
    "Archiwum moda":
        "Mod archive",
    "Archiwa (*.zip *.7z)":
        "Archives (*.zip *.7z)",
    "Odinstalowano mod „{mid}”":
        "Uninstalled mod “{mid}”",
    "Zainstaluj mod z archiwum ZIP lub 7z":
        "Install a mod from a ZIP or 7z archive",
    "Wyżej w kolejności (ładowany wcześniej)":
        "Higher in the order (loaded earlier)",
    "Niżej w kolejności (wygrywa konflikty)":
        "Lower in the order (wins conflicts)",
    "Usuń z profilu":
        "Remove from profile",
    "Mod zostaje na dysku":
        "The mod stays on disk",
    "Odinstaluj":
        "Uninstall",
    "Usuń mod z dysku (z potwierdzeniem)":
        "Delete the mod from disk (with confirmation)",
    "Zastosuj":
        "Apply",
    "Przebuduj tylko zasoby zmienione przez mody":
        "Rebuild only the assets changed by mods",
    "{v} (brak w magazynie!)":
        "{v} (missing from the store!)",
    "tylko zasoby":
        "assets only",
    "Najpierw wskaż instalację Morrowinda (Konwersja).":
        "First select the Morrowind installation (Conversion).",
    "Mod nie jest zainstalowany – usuń go z profilu.":
        "The mod is not installed – remove it from the profile.",
    "Plugin {v} – wymaga: {v2}":
        "Plugin {v} – requires: {v2}",
    "<br>Zainstalowano „{name}”. Kliknij „Zastosuj”, aby przekonwertować tylko zmienione zasoby.":
        "<br>Installed “{name}”. Click “Apply” to convert only the changed assets.",
    "Odinstaluj mod":
        "Uninstall mod",
    "Usunąć mod „{mid}” z dysku? Inne profile, które go używają, zgłoszą brak moda.":
        "Delete mod “{mid}” from disk? Other profiles that use it will report a missing mod.",
    "<span style='color:%s'>Brakujące zależności: %s</span>":
        "<span style='color:%s'>Missing dependencies: %s</span>",
    "<span style='color:%s'>Brak modów: %s</span>":
        "<span style='color:%s'>Missing mods: %s</span>",
    "Konflikty ({v}):":
        "Conflicts ({v}):",
    "Instalacja moda":
        "Mod installation",
    "Nie zainstalowano: {e}":
        "Not installed: {e}",
    "  {v}: {join} (wygrywa {v2})":
        "  {v}: {join} (winner: {v2})",
    "(gra)":
        "(game)",
    "okno":
        "window",
    "pełny ekran":
        "fullscreen",
    "pełny ekran (wyłączny)":
        "fullscreen (exclusive)",
    "wyłączone":
        "off",
    "niska":
        "low",
    "średnia":
        "medium",
    "wysoka":
        "high",
    "Dźwięk, napisy, mysz i część grafiki można też zmienić w grze (Esc → Ustawienia).":
        "Sound, subtitles, mouse and some graphics options can also be changed in the game (Esc → Settings).",
    "Język launchera":
        "Launcher language",
    "Roślinność generowana przy konwersji ([flora] enabled)":
        "Vegetation generated during conversion ([flora] enabled)",
    "Automatyczna – trawa Remirosa (dołączona do programu, bez ESP)":
        "Automatic – Remiros grass (bundled with the program, no ESP)",
    "Z wtyczek groundcover":
        "From groundcover plugins",
    "Obie (hybryda)":
        "Both (hybrid)",
    "Źródło":
        "Source",
    "Gęstość (0–2)":
        "Density (0–2)",
    "Wtyczki groundcover bez roślinności proceduralnej ([Groundcover] enabled)":
        "Groundcover plugins without procedural vegetation ([Groundcover] enabled)",
    "Gęstość wtyczek groundcover (0–1)":
        "Groundcover plugin density (0–1)",
    "wykrywanie automatyczne":
        "automatic detection",
    "Projekt gry":
        "Game project",
    "interpreter launchera":
        "launcher interpreter",
    "Python (konwerter)":
        "Python (converter)",
    "np. {example}":
        "e.g. {example}",
    "Parametry uruchamiania":
        "Launch parameters",
    "Minimalizuj launcher po starcie gry":
        "Minimize the launcher after the game starts",
    "Wypiekaj sceny z teksturami pod GPU po konwersji":
        "Bake scenes with GPU textures after conversion",
    "Katalogi":
        "Directories",
    "Otwórz logi":
        "Open logs",
    "Diagnostyka":
        "Diagnostics",
    "Plik wykonywalny Godota":
        "Godot executable",
    "{v} — profil {name}":
        "{v} — profile {name}",
    "Automatycznie (jak launcher: {upper})":
        "Automatic (like the launcher: {upper})",
    "Oryginalny (bez tłumaczenia)":
        "Original (no translation)",
    "Grafika":
        "Graphics",
    "Dźwięk":
        "Sound",
    "Sterowanie":
        "Controls",
    "Język":
        "Language",
    "Świat":
        "World",
    "Zaawansowane":
        "Advanced",
    "Konfiguracja: {config}\nDane: {data}\nCache: {cache}\nLogi: {logs}":
        "Configuration: {config}\nData: {data}\nCache: {cache}\nLogs: {logs}",
    "Nie znaleziono działającego Godota 4.":
        "No working Godot 4 found.",
    "{upper} (brak w konwersji)":
        "{upper} (not in the conversion)",
    "<br>Zmiana języka nie wymaga ponownej konwersji.":
        "<br>Changing the language does not require a new conversion.",
    "\nRoślinność jest liczona przy konwersji – po zmianie ustawień uruchom „Aktualizuj” na stronie Konwersja. Zasięg i gęstość rysowania w grze: zakładka Grafika.":
        "\nVegetation is computed during conversion – after changing these settings run “Update” on the Conversion page. Drawing distance and density in the game: the Graphics tab.",
    "\n(tryb przenośny)":
        "\n(portable mode)",
    "Konwersja nie zawiera tłumaczeń. Pliki localization/language/&lt;wtyczka&gt;.yaml (format forka OpenMW RLF) dodaj jako mod i uruchom aktualizację konwersji.":
        "The conversion contains no translations. Add localization/language/&lt;plugin&gt;.yaml files (OpenMW RLF fork format) as a mod and update the conversion.",
    "\nTryb automatyczny: trawa Remirosa liczona z reguł forka na teksturach terenu; modele i tekstury Remiros' Groundcover (autor: Remiros) są dołączone do programu – nic nie trzeba instalować.":
        "\nAutomatic mode: Remiros grass computed from the fork rules on terrain textures; the Remiros' Groundcover models and textures (author: Remiros) are bundled with the program – nothing needs to be installed.",
    "Tłumaczenia w konwersji: ":
        "Translations in the conversion: ",
    "Brak wtyczek groundcover (rozpoznawane automatycznie przy instalacji moda).":
        "No groundcover plugins (detected automatically when a mod is installed).",
    "  (ekran)":
        "  (screen)",
    "Wtyczki groundcover: ":
        "Groundcover plugins: ",
    "puste = wyłączone":
        "empty = off",
    "konwersja już trwa":
        "a conversion is already running",
    "Nie udało się uruchomić konwertera: {python}":
        "Could not start the converter: {python}",
    "OpenMWGodot – pierwsza konfiguracja":
        "OpenMWGodot – first-time setup",
    "Gotowe":
        "Done",
    "Język / Language":
        "Język / Language",
    "Instalacja Morrowinda":
        "Morrowind installation",
    "Wskaż katalog gry (Steam, GOG, ręczna instalacja), „Data Files” albo openmw.cfg. Pliki gry nie są zmieniane.":
        "Select the game directory (Steam, GOG, manual installation), “Data Files” or openmw.cfg. The game files are not changed.",
    "Potrzeba kilku GB wolnego miejsca. Dane nie mogą być publikowane – zawierają zasoby gry.":
        "A few GB of free space are needed. The data must not be published – it contains game assets.",
    "Można ją przerwać – ukończone zasoby zostaną zachowane i konwersję da się wznowić.":
        "It can be interrupted – completed assets are kept and the conversion can be resumed.",
    "Rozpocznij konwersję":
        "Start conversion",
    "< Wstecz":
        "< Back",
    "Dalej >":
        "Next >",
    "Zakończ":
        "Finish",
    "Konfiguracja zakończona. W głównym oknie kliknij „Graj”.\nJeśli konwersja nie skończyła się, wznów ją na stronie „Konwersja”.":
        "Setup finished. Click “Play” in the main window.\nIf the conversion did not finish, resume it on the “Conversion” page.",
    "<span style='color:{WARN}'>Nie wykryto – wskaż ręcznie.</span>":
        "<span style='color:{WARN}'>Not detected – select it manually.</span>",
    "Konwersja zakończona.":
        "Conversion completed.",
    "Przerwano – można wznowić później.":
        "Interrupted – can be resumed later.",
    "Błąd konwersji (kod {code}).":
        "Conversion error (code {code}).",
    "Brak danych gry":
        "No game data",
    "Znaleziono: ":
        "Found: ",
    "nieobsługiwany format archiwum: {name} (obsługiwane: .zip, .7z)":
        "unsupported archive format: {name} (supported: .zip, .7z)",
    "ścieżka bezwzględna w archiwum: {name!r}":
        "absolute path in the archive: {name!r}",
    "ścieżka wychodzi poza katalog (..): {name!r}":
        "path leaves the directory (..): {name!r}",
    "pusta ścieżka w archiwum: {name!r}":
        "empty path in the archive: {name!r}",
    "katalog docelowy nie jest pusty: {dest}":
        "target directory is not empty: {dest}",
    "przekroczony limit rozmiaru po rozpakowaniu":
        "size limit exceeded after extraction",
    "za dużo plików w archiwum ({v})":
        "too many files in the archive ({v})",
    "rozmiar po rozpakowaniu przekracza limit":
        "size after extraction exceeds the limit",
    "podejrzany współczynnik kompresji {v:.0f}:1 (archive bomb?)":
        "suspicious compression ratio {v:.0f}:1 (archive bomb?)",
    "obsługa 7z wymaga pakietu py7zr (Debian: sudo apt install python3-py7zr)":
        "7z support requires the py7zr package (Debian: sudo apt install python3-py7zr)",
    "dowiązanie symboliczne po rozpakowaniu: {name}":
        "symbolic link after extraction: {name}",
    "plik poza katalogiem docelowym":
        "file outside the target directory",
    "przekroczony limit rozmiaru po rozpakowaniu (archive bomb?)":
        "size limit exceeded after extraction (archive bomb?)",
    "dowiązanie symboliczne w archiwum: {filename!r}":
        "symbolic link in the archive: {filename!r}",
    "podejrzany współczynnik kompresji pliku {filename!r}":
        "suspicious compression ratio of file {filename!r}",
    "ścieżka poza katalogiem docelowym: {filename!r}":
        "path outside the target directory: {filename!r}",
    "brak world/index.json":
        "world/index.json missing",
    "eksport świata niekompletny":
        "world export incomplete",
    "brak zapisu konwersji dla tego zestawu modów":
        "no conversion record for this set of mods",
    "zmienił się zestaw lub kolejność modów":
        "the set or order of mods has changed",
    "zmieniły się pliki ESM/ESP":
        "ESM/ESP files have changed",
    "uszkodzony {rel}":
        "damaged {rel}",
    "nie znaleziono plików ESM do wczytania":
        "no ESM files found to load",
    "brak {v}.esm":
        "{v}.esm missing",
    "brak archiwum {v}.bsa (modele/tekstury mogą być niekompletne)":
        "archive {v}.bsa missing (models/textures may be incomplete)",
    "błąd odczytu: {e}":
        "read error: {e}",
    "ścieżka nie istnieje":
        "the path does not exist",
    "brak Morrowind.esm i katalogu „Data Files”":
        "Morrowind.esm and the “Data Files” directory are missing",
    "archiwum nie zawiera danych gry (brak meshes/textures/…, ESP/ESM ani BSA)":
        "the archive contains no game data (no meshes/textures/…, ESP/ESM or BSA)",
    "mod {id}: data_root poza katalogiem moda":
        "mod {id}: data_root outside the mod directory",
    "brak pliku: {archive}":
        "missing file: {archive}",
    "nie ma moda {mod_id}":
        "no such mod {mod_id}",
    "uszkodzony plugin {name}: {e}":
        "damaged plugin {name}: {e}",
    "niepoprawny identyfikator profilu: {pid!r}":
        "invalid profile identifier: {pid!r}",
    "nie można usunąć ostatniego profilu":
        "cannot delete the last profile",
    "Domyślny":
        "Default",
    "Język gry profili ({ids}) ustawiony na {lang} – niezależnie od języka launchera":
        "Game language of profiles ({ids}) set to {lang} – independent of the launcher language",
    "Instaluj…":
        "Install…",
}
