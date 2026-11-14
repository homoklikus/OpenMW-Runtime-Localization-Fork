# MCP — etap 3: porównania wizualne (oficjalny OpenMW vs fork)

**Status:** w trakcie. Testy lokalne przeszły (VM 83/83). Pierwszego przebiegu na Debianie jeszcze nie było.

| | |
|---|---|
| Wersja MCP | `openmw-mcp 0.5.1`, hash drzewa `b8963dbb8c944351de3588c7b2c581372aba4005caaebef5289631a92dd03e14` (0.5.0: `f9ed8ea5…`) |
| Cel | porównanie obrazu w tych samych miejscach, tej samej kamerze, porze i pogodzie — najpierw trawa Remirosa: oficjalne pluginy vs fork po pach75 (`94e5fb45`, gałąź `world-remiros-texture`) |

## Jak to działa
1. `openmw_capture_plan` / `openmw_capture_start` wybiera punkt kamery dla każdej komórki:
   - cel: najgęstszy teksel z mapy liczników Remirosa;
   - kamera 700 j. od celu, nad wodą, na wysokości oczu (+128), lekko w dół.
2. Każdy silnik dostaje katalog `Raporty/mcp/zrzuty/<data>/<profil>/` (poza repozytorium):
   - `cfg/` jako **ostatni** katalog konfiguracji: log, `settings.cfg` z nadpisaniami (1920×1080 w oknie, FOV 60, PNG), kopie `world.cfg`, `shaders.yaml`, `input_v3.xml` z profilu;
   - `data/` ze skryptem Lua `rlf_capture` i wygenerowanym scenariuszem;
   - `userdata/`.

   Profile `openmw-ref` i `openmw-test` nie są zmieniane.
3. Uruchomienie: `--replace=config`, konfiguracje profilu i na końcu `cfg/`, potem `--skip-menu --start=Balmora --no-sound`. Oficjalny przez `flatpak run --socket=x11` (uprawnienie tylko na czas uruchomienia), fork z `Fork/install/bin`. Oba z `SDL_VIDEODRIVER=x11`, czyli przez XWayland, bo KDE Wayland nie przyjmuje zewnętrznych klawiszy dla natywnych okien Wayland.
4. Skrypt Lua dla każdego ujęcia:
   - przenosi gracza za kamerę;
   - ustawia pogodę (`core.weather.changeWeather`) i przyspiesza czas, żeby przejście pogody się zakończyło;
   - zatrzymuje czas i ustawia godzinę;
   - ustawia kamerę statyczną (`camera.setStaticPosition/setYaw/setPitch`) i ukrywa HUD;
   - po załadowaniu wpisuje do logu `RLF_CAPTURE READY <id>`.
5. MCP widzi znacznik i wysyła F12 (zrzut silnika, dokładny obraz klatki). Gdy plik się nie pojawi, używa `import -window`. Na końcu wykonuje `core.quit()`.
6. Porównanie: arkusz obok siebie, średnia różnica RGB i udział pikseli roślinności w dolnych 2/3 kadru (miara orientacyjna).

## Testy
`tests/test_capture.py`, 7 testów:
- scenariusz Lua i escapowanie;
- geometria kamery (odległość, wysokość, konwencja yaw/pitch OpenMW, gracz za kamerą, wybór najgęstszego teksela);
- katalogi i polecenia dla obu profili (kolejność `--config`, `cfg/` ostatni, `--socket=x11`);
- przebieg z atrapą silnika (znaczniki w logu, zrzuty, błędy);
- porównanie obrazów (Pillow);
- rejestracja narzędzi.

## Pierwszy przebieg (Debian 13, 2026-11-14 16:18, `2026-11-14-161804-porownanie`)
- **Fork:** 3/3 ujęcia, zrzuty F12 przez silnik, bez ostrzeżeń, czyste wyjście przez `core.quit()`. Pogoda (Clear) i godzina 12:00 ustawione poprawnie, HUD ukryty, kierunki kamery zgodne z konwencją. Na Solstheimie (−24, 19) widać gęstą trawę, której fork przed pach75 nie miał. Ujęcie (15, −9) patrzyło w górę na zbocze, więc wybór punktu kamery poprawiono: kara za kamerę poniżej celu, pitch co najmniej 0,08 rad w dół.
- **Oficjalny (Flatpak):** `Fatal error: Could not initialize SDL! x11 not available`. Uprawnienie `fallback-x11` ukrywa X11 w sesji Wayland mimo `--socket=x11`. Poprawka: `--nosocket=wayland --nosocket=fallback-x11 --socket=x11`, tylko na czas uruchomienia.

## Drugi przebieg (Debian 13, 2026-11-14 16:25, `2026-11-14-162502-porownanie`)
Oba silniki: 3/3 ujęcia przez F12, status `done`, bez błędów w logach. Pogoda i godzina ustawione w obu (zweryfikowane na żywo — poprzednie ograniczenie nieaktualne).

| Ujęcie | Region | Śr. różnica RGB | Udział roślinności oficjalny / fork | Obserwacja |
|---|---|---|---|---|
| c-5_-3 | Bitter Coast | ok. 7 | 0,616 / 0,612 | trawa praktycznie taka sama |
| c-24_19 | Solstheim | ok. 25–29 | 0,269 / 0,305 | gęstość podobna, inny miks modeli na pierwszym planie |
| c15_-9 | Azura's Coast | ok. 7–10 | 0,125 / 0,109 | **oficjalny: brak jakiejkolwiek trawy w kadrze**, fork: trawa i grzyby Remirosa |

**Błąd kierunku kamery w MCP 0.5.0 (wykryty przy analizie tego przebiegu).** API Lua `openmw.camera` samo neguje kąty (`camerabindings.cpp`: `setYaw(v)` → `Camera::setYaw(−v)`, `setPitch(v)` → `Camera::setPitch(−v)`), więc `yaw`/`pitch` w Lua mają konwencję `rot` obiektu: yaw = kurs, pitch > 0 = w dół. MCP negował je drugi raz. Kamera patrzyła w kierunku odbitym względem osi Y (kurs = −planowany) i lekko w górę. Oba silniki dostały ten sam scenariusz, więc pary zrzutów pokazują **te same miejsca** i porównanie pozostaje ważne. Kadry nie celowały jednak w najgęstszy teksel. Wcześniejsze „patrzenie w górę na zbocze” w pierwszym przebiegu miało tę samą przyczynę. Poprawka w 0.5.1: `yaw = kurs`, `pitch = +w dół`, test geometrii poprawiony.

Kontrola danych dla **faktycznego** kierunku kamery (kąt ±46° = poziome FOV przy 16:9 i pionowym 60°; emulacja offline obu stron, tryb liczników we wszystkich komórkach):

| Ujęcie | Remiros 150–600 j. | Fork pach75 150–600 j. | Remiros / fork 600–2000 j. |
|---|---|---|---|
| c15_-9 | 0 | 5 (ac_grass_03 ×3, ac_grass_04 ×2) | 0 / 0 |
| c-24_19 | 42 (sol_grass_01 ×8, sol_grass_02 ×34) | 32 (sol_grass_01 ×1, sol_grass_02 ×31) | 402 / 406 |
| c-5_-3 | 19 | 14 | 104 / 102 |

Wnioski:
- Dane offline zgadzają się z obrazami, więc emulacja i silnik forka zachowują się tak samo.
- **c15_-9:** oficjalny zrzut jest poprawny, bo Remiros nie ma w tym kadrze ani jednej rośliny. Fork stawia 5 roślin blisko kamery. Liczba na teksel jest zachowana, ale fork rozkłada rośliny równomiernie w tekselu (512 j.), a Remiros skupił je w jego innej części, poza kadrem. Wariant 1 zachowuje liczby na teksel, ale nie rozkład wewnątrz teksela. Wcześniejsza hipoteza o opóźnionym doładowaniu trawy w oficjalnym silniku jest nieaktualna.
- **c-24_19:** zielone kępki na lewym zrzucie (oficjalny) to `rem_sol_grass_01` z zieloną teksturą `tx_grass_solstheim_01`. Biała trawa to `rem_sol_grass_02`. Pliki modeli i tekstur w forku są identyczne z oryginałem (SHA-256). Remiros miesza modele w obrębie teksela: na `Tx_BM_grass_snow_02a` 89% `_02` i 11% `_01`. Fork wybiera model losowo według tekstury w punkcie, więc lokalnie miks może odbiegać. W tym kadrze wyszło 1 zamiast 8 zielonych, przy zgodnej liczbie roślin w skali komórki. Bliska trawa jest też rzadsza (32 wobec 42), z tej samej przyczyny co w c15_-9.
- **c-5_-3:** zgodnie.
- Tekstury terenu różnią się, bo profil forka używa Morrowind Enhanced Textures 6.1. Nie dotyczy to trawy.

Możliwe poprawienie wierności (zmiana silnika, wymaga decyzji): w tabeli liczników zapisać liczby **per model** na teksel oraz rozkład w podsiatce teksela (np. 4×4 pola po 128 j.). Nadal bez współrzędnych pojedynczych roślin, ale miks modeli i luki byłyby odtworzone dokładnie.

## Trzeci przebieg — poprawiona kamera (Debian 13, 2026-11-14 17:08, `2026-11-14-170831-porownanie`)
Oba silniki: 3/3 ujęcia przez F12, bez błędów. Fork bez pach76 (stan pach75).
- Kamera patrzy na zaplanowany cel i lekko w dół, więc poprawka 0.5.1 działa.
- **c-24_19 (Solstheim):** w obu silnikach widać zielone kępki `rem_sol_grass_01` wśród białej trawy. Rozmieszczenie lokalnie się różni, czego w pach75 należy się spodziewać. Udział roślinności 0,512 (oficjalny) / 0,602 (fork).
- **c-5_-3 (Bitter Coast):** podobnie; oficjalny ma na pierwszym planie więcej szerokolistnych roślin, fork więcej kęp traw (0,860 / 0,840).
- **c15_-9 (Azura's Coast):** prawą połowę kadru zasłania bliskie zbocze. Wybór punktu kamery w 0.6.0 sprawdza więc zasłonięcie terenem w 5 promieniach w poziomym polu widzenia (±40°) i wybiera spośród 16 kierunków. Dla (15,−9) daje to kamerę wyżej, z pochyleniem ok. 32° w dół.

## Czwarty przebieg — fork z pach76 (Debian 13, 2026-11-14 17:23, `2026-11-14-172349-porownanie`)
Oba silniki: 3/3 ujęcia, bez błędów. Kamera wybrana z kontrolą zasłonięcia (MCP 0.6.0). Trawa forka z pach76 odpowiada oryginałowi we wszystkich trzech ujęciach; szczegóły w [raporcie pach76](2026-11-14-pach76-liczniki-w-polach-teksela.md).

## Piąty przebieg — 7 regionów Remirosa, fork z pach76 (Debian 13, 2026-11-14 17:59, `2026-11-14-175937-porownanie`)
Po jednej komórce na plugin, wybranej spośród najgęstszych. Oba silniki: 7/7 ujęć, bez błędów.

Poniżej liczba roślin w kadrze według danych (±46°, do 350 j. / 350–700 j.) i ocena zrzutów:

| Komórka | Region (plugin) | Komórka: Remiros / fork pach76 | Kadr: Remiros / fork | Zrzuty |
|---|---|---|---|---|
| (5,−9) | Ascadian Isles (AI) | 3076 / 3076 | 4+22 / 6+21 | praktycznie identyczne |
| (0,15) | Ashlands (AL) | 3523 / 3523 | 7+17 / 6+17 | ta sama gęstość; kępy w innych miejscach pól 128 j. |
| (12,11) | Grazelands (GL) | 3587 / 3587 | 7+18 / 5+18 | lewą połowę zasłania głaz (obiekt, nie teren); trawa po prawej zgodna |
| (−7,12) | West Gash (WG) | 1759 / 1759 | 2+11 / 2+11 | bardzo podobne |
| (−5,−3) | Bitter Coast (BC) | 2703 / 2701 | 7+15 / 6+18 | bardzo podobne |
| (−24,19) | Solstheim | 9087 / 9087 | 12+43 / 10+51 | jak w czwartym przebiegu |
| (15,−9) | Azura's Coast (AC) | 1435 / 1435 | 2+11 / 1+9 | jak w czwartym przebiegu |

Podział na modele w komórce: różnica (TV) 0 we wszystkich komórkach poza BC (0,0004).

Ograniczenie: kontrola widoku uwzględnia teren, ale nie obiekty (głazy, drzewa). Wymagałoby to granic modeli NIF (etap 2b).

## MCP 0.5.1 — poprawka kamery, powtórzenia ujęć i czasy oczekiwania
- Poprawka kierunku kamery (wyżej).
- `openmw_capture_plan` / `openmw_capture_start`: nowe parametry `repeat` (1–5; seria ujęć powtórzona, id z sufiksem `-r2`…), `settle_seconds`, `render_seconds`.
- Drugi przebieg odwiedza te same miejsca przy już wczytanych zasobach — kontrola, czy różnica nie wynika z doładowania.
- Test: `test_repeat_shots_and_timing_override` (8 testów w `test_capture.py`).

## Ograniczenia
- Wiatr porusza trawą, więc obrazy nie są identyczne co do piksela. Miary służą do oceny różnic, nie do testów „bit w bit”.
- Różnice widoczne z bliska trzeba sprawdzić w danych (rozkład w tekselu, miks modeli), zanim uzna się je za błąd silnika.
- Zrzut wymaga aktywnego okna gry. W trakcie przebiegu nie używaj myszy ani klawiatury.
