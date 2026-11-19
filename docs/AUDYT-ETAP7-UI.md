# Audyt zgodności z OpenMW 0.51 – etap 7: klasyczny interfejs

Stan na 2026-11-19. Baza: lokalny HEAD `2c2dbb7` (etap 6), commity etapu: `6469331` (cz. 1) i następne.
Źródło prawdy: OpenMW 0.51 (`apps/openmw/mwgui`, `files/data/mygui/*.layout`, `openmw_*.skin.xml`,
`files/settings-default.cfg`, `files/data/l10n`). Statusy i priorytety jak w `INWENTARYZACJA-OPENMW.md`
(Zweryfikowane / Zaimplementowane / Częściowo zgodne / Brakujące; P1–P3).

## 1. Główna przyczyna zbyt dużego interfejsu

**Objaw:** okna, napisy i HUD w Godocie były wyraźnie większe niż w OpenMW, coraz bardziej przy wyższych
rozdzielczościach (przy 1080p 1,5×, przy 4K 3×).

**Przyczyna:** każde okno liczyło własną skalę `clampf(viewport.y / 720, 1, 3)`. OpenMW skaluje inaczej:
układy MyGUI są w pikselach, czcionka ma 16 px, a całość mnoży się przez jeden współczynnik
`mScalingFactor = [GUI] scaling factor (domyślnie 1,0) × (rozmiar bufora rysowania / rozmiar okna)`
(poprawka HiDPI). **Rozdzielczość ekranu nie zmienia skali.** Jedyny wyjątek to warstwa `JournalBooks`
(ScalingLayer 600 × 520), na której dziennik, książki i zwoje skalują się o `min(w/600, h/520)`.

**Naprawa:** jedna wspólna skala `UI.ui_scale() = gui_scaling × screen_get_scale()` (ustawienie
`gui_scaling_factor`, domyślnie 1,0 jak w OpenMW, zakres 0,5–8) we wszystkich 13 oknach, które miały własną
skalę: main, potwierdzenie, tryb menu, mapa, menu główne, magia, kreator, HUD, ekran ładowania, zapis,
handel. Książka, dziennik i zwój używają `UI.book_scale(vp)` (600 × 520). Nie poprawiano rozmiarów
pojedynczych okien „na oko”: wszystkie wymiary pochodzą z układów OpenMW.

## 2. Procedura porównań wizualnych (powtarzalna)

| Element | Gdzie |
|---|---|
| Przypadki (komórka, pozycja gracza, rozdzielczość, kroki UI) | `tools/openmw-xvfb/ui_cases/ui_windows_{720,1080,1440,2160}.json` |
| OpenMW 0.51 na Xvfb: `I.UI.setMode(...)` z Lua gracza, zrzuty na `MWSHOT` | `mwscript_compare.py` (pola `resolution`, `ui`, `teleport`) |
| Godot na Xvfb (renderer zgodności), te same tryby GuiMode | `mwscript_case.sh … godot-ui`, `probe_mwscript.gd` (`_apply_ui`) |
| Porównanie geometrii (prostokąty ramek okien, IoU, przesunięcie, rozmiar) | `tools/openmw-xvfb/ui_geom_compare.py` |
| Zrzuty i pary obrazów (tylko lokalnie, poza repozytorium) | `OpenMW RLF/Raporty/ui-etap7/` (`before*`, `after*`, `final_*`, `geometria_final.json`) |

Kroki: `clear` → zrzut HUD → `Interface` (statystyki, ekwipunek, magia, mapa) → `Journal` → okna kreatora
(`ChargenName`, `ChargenRace`, `ChargenClass`, `ChargenClassPick`, `ChargenBirth`, `ChargenClassReview`).
Między zmianą trybu a zrzutem jest 2,5 s, a między zrzutem a kolejnym trybem 2 s, bo OpenMW na llvmpipe
renderuje wolno. Przypadki rozgrywają się w Arrille's Tradehouse, czyli we wnętrzu bez skryptów CharGen
(komunikaty kreatora to różnica stanu gry, a nie interfejsu). Gracza ustawia `teleport` w obu silnikach w
celu drzwi z Seyda Neen.

Uruchomienie na VM (OpenMW w `/tmp/omwx`, dane w `/tmp/s9_out`):
`OUT=/tmp/uicmp bash mwscript_case.sh ui_cases/ui_windows_1080.json omw 101`, potem `… godot-ui 102`,
potem `python3 ui_geom_compare.py OMW.png GODOT.png --json wynik.json`.

## 3. Wyniki geometrii (IoU prostokątów okien: OpenMW ↔ Godot)

Przed = kod z `2c2dbb7` z tą samą sondą i tym samym przypadkiem; po = stan po etapie 7.

| Ekran | Przed (1080p) | Po: 720p | Po: 1080p | Po: 1440p | Po: 2160p |
|---|---|---|---|---|---|
| Tryb menu (4 okna) | 0,958* | 1,0 / 1,0 / 0,98 / 1,0 | 0,93** / 1,0 / 1,0 / 1,0 | 0,93** / 1,0 / 1,0 / 1,0 | 0,93** / 1,0 / 1,0 / 1,0 |
| Dziennik | 0,645 (±200 px) | 1,0 | 0,997 | 0,997 | 1,0 |
| Imię (kreator) | 0,45 (±160 px) | 0,96 | 1,0 | 1,0 | 1,0 |
| Rasa (kreator) | 0,446 (±320 px) | 1,0 | 1,0 | 1,0 | 1,0 |

\* Ramki okien trybu menu już wcześniej były we właściwych miejscach, bo położenia i rozmiary są ułamkami
ekranu z ustawień OpenMW, ale napisy i zawartość były 1,5× za duże.
\*\* Okno statystyk ma tę samą krawędź co w OpenMW (sprawdzone na zrzucie). Detektor dokleja do niego
jaśniejszą belkę z tła sceny Godota: oświetlenie wnętrza jest jaśniejsze, patrz punkt 5.

HUD (paski, broń, czar, skradanie, minimapa, pole efektów) jest za mały dla detektora ramek. Sprawdza go
`test_ui_geometry` na wymiarach z `openmw_hud.layout` w 4 rozdzielczościach i przy skali 2, a zrzuty
powiększone (`zoom*_1080_hud_*`) są zgodne co do piksela.

## 4. Okna – stan po audycie

| Okno / element | Status | Co zrobiono / co zostało | Prio |
|---|---|---|---|
| Skala GUI (wszystkie okna) | Zweryfikowane | wspólna skala jak OpenMW, test 4 rozdzielczości + skala 2 | – |
| HUD | Zweryfikowane | układ `openmw_hud.layout`, pasek broni/czaru, puste pole czaru, pole efektów (SpellIcons, także stałe efekty), mruganie `fMagicStartIconBlink` | – |
| Podpowiedź obiektu w świecie | Zweryfikowane | **naprawione:** była widoczna w trybie GUI; OpenMW (`ToolTips::onFrame`) pokazuje ją tylko poza nim | – |
| Dziennik | Zweryfikowane | **przebudowany** jak `JournalWindow`: książka `tx_menubook`, 2 strony, numery, przyciski, zakładka (indeks A–Z, zadania aktywne/wszystkie, tematy), pusty dziennik | – |
| Statystyki | Zweryfikowane | **przebudowane** wg `openmw_stats_window.layout` i `onWindowResize`: lewa część 0,44, trzy MW_Box, wiersze 18 px, nazwy od x = 10, MW_HLine; okno nie rozpycha się ponad rozmiar z ustawień | – |
| Ekwipunek | Zweryfikowane | pasek obciążenia, lewa część wg `adjustPanes` ((H − 68) × 0,5), FilterEdit, kolory zaznaczonej kategorii (active), przycinanie przycisków w wąskim oknie | – |
| Magia | Zweryfikowane | pole efektów 268 × 23, filtr nazw (także przedmioty), Delete z potwierdzeniem `sQuestionDeleteSpell` | – |
| Pasek tytułu okien | Zweryfikowane | `MW_Caption` + `WindowCaption::align`: przerwa na tekst + 24 px, bloki `HB_ALL`, 20 px, kolor normal | – |
| Kreator (5 okien) | Zweryfikowane | rozmiary i położenia zgodne (IoU 1,0) | – |
| Mapa (okno) | Częściowo zgodne | położenie i rozmiar zgodne; mapa lokalna wnętrza w Godocie prawie czarna (mgła/odkrycie) | P2 |
| Pasek przewijania MW_VScroll (strzałki, suwak) | Brakujące | Godot ukrywa pasek; OpenMW pokazuje skórkę Morrowinda | P2 |
| Wcięcie pól od ramki okna (8 px) | Częściowo zgodne | Godot ~4 px od wewnętrznej krawędzi ramki | P3 |
| Teksty silnika (potwierdzenia, okno zapisu) | Zweryfikowane | **naprawione:** były wpisane po polsku na sztywno; teraz l10n OpenMW (`OMWEngine`, `Calendar`) wg `preferred_locales` (domyślnie en, jak OpenMW) | – |
| Pozostałe stałe polskie napisy (zapasy dla GMST, okno ustawień, kreator, magia) | Częściowo zgodne | zapasy po polsku tylko gdy brak GMST; okno ustawień i część komunikatów do przeniesienia na l10n/GMST | P2 |
| Okna rozmowy, handlu, pojemnika, odpoczynku, alchemii, zaklinania, napraw | Nieprzetestowane wizualnie | wspólna skala już działa; porównanie zrzutami w kolejnym kroku (wymaga przypadków z NPC i obiektami) | P2 |
| Menu główne, zapis/odczyt, opcje | Częściowo zgodne | `I.UI.setMode("MainMenu")` w OpenMW nic nie pokazuje – potrzebny inny sposób wywołania w sondzie | P2 |
| Zachowanie okien: przeciąganie, zmiana rozmiaru, zapamiętanie układu | Zaimplementowane | test_menu_mode (przesunięcie, zapamiętanie, odtworzenie); przypinanie (pin) i maksymalizacja – brak | P3 |
| Skróty klawiszowe, kontroler | Częściowo zgodne | klawisze trybu menu i okien są; szybkie klawisze F1/1–9 i menu kontrolera – brak (punkt 3 inwentaryzacji) | P1/P3 |

## 5. Inne systemy znalezione przy porównaniach

| Znalezisko | Status | Szczegóły | Prio |
|---|---|---|---|
| Ekwipunek startowy gracza | **Naprawione** | Godot nie wypełniał inwentarza z rekordu NPC „player” i nie zakładał ubrań (`Npc::getNpcData`: `ContainerStore::fill` + `autoEquip`). Teraz robi to raz przy nowej grze, a przebudowa postaci w kreatorze nie zdejmuje ubrań. Test: test_menu_mode | – |
| Start w komórce wewnętrznej (`--cell`) | **Naprawione** | Gracz spadał w pustkę (pozycja 0,0,0). Teraz działa `World::findInteriorPosition`: drzwi z komórki posortowane po id i celu, w komórce docelowej drzwi prowadzące z powrotem, a jeśli ich nie ma, pierwszy obiekt statyczny. Test: test_interaction | – |
| OpenMW `--start <wnętrze>` | Uwaga (zachowanie OpenMW) | OpenMW przy starcie nie ma wczytanych komórek źródłowych drzwi (`getReadOnlyDoors()` jest puste), więc sięga po pierwszy obiekt statyczny i gracz trafia poza pomieszczenie („falling into the void”). Godot sprawdza drzwi zawsze, co odpowiada COC w trakcie gry. Porównania używają jawnego `teleport` | – |
| Szybki odczyt w tej samej sekundzie | **Naprawione** | Kolejność zapisów także po `created_unix`, a nagłówek zapisu nie jest już brany z pamięci podręcznej (`saves.forget`). Wcześniej test_start_game był niestabilny | – |
| Statystyki przed ukończeniem kreatora | Częściowo zgodne | OpenMW do zakończenia kreatora pokazuje surowe wartości rekordu „player” (atrybuty 30, umiejętności 5). Godot od razu nalicza premie rasy i klasy (`character.build`) | P2 |
| Oświetlenie wnętrz | Częściowo zgodne | scena w Godocie wyraźnie jaśniejsza niż w OpenMW przy tym samym kadrze (Arrille's, urząd celny); zgodne z punktem „wierność oświetlenia” w inwentaryzacji | P1 |
| Komunikat CharGen w urzędzie celnym | Nieprzetestowane | Godot pokazuje „Press ActionActivate to talk to the Captain…” po teleporcie, OpenMW nie; do sprawdzenia warunki skryptu przy starcie `--cell` | P2 |
| `test_ai` przy równoległym uruchomieniu | Uwaga | dwa sprawdzenia pakietu podróży nie przechodzą przy 3 testach naraz (obciążenie CPU), przechodzą osobno i w `run_tests.sh` | P3 |

## 6. Testy

* Nowy `test_ui_geometry.gd` (77 sprawdzeń): HUD w 1280×720, 1920×1080, 2560×1440 i 3840×2160 oraz przy skali 2
  (paski, broń, czar, minimapa, czcionka); dziennik (skala 600 × 520, rozmiar, środek); okna trybu menu
  (położenie i rozmiar z `[Windows]`, lewa część ekwipunku wg `adjustPanes`); l10n (en, pl, Calendar, bloki).
* Rozszerzone testy: `test_menu_mode` (ubranie startowe, filtr ekwipunku i magii, usuwanie czaru, brak
  podpowiedzi obiektu w trybie GUI), `test_interaction` (`findInteriorPosition`), `test_dialogue`
  (dziennik-książka), `test_start_game` (teksty l10n, kolejność zapisów), `test_progress` (prędkość z obciążeniem).
* `tools/run_tests.sh` – **wszystkie testy zaliczone** (przebieg `rtx57`, 2026-11-19). Po zmianach l10n,
  statystyk i ekwipunku (przebieg `rtx58`): wszystkie testy zaliczone poza jednym przebiegiem `test_ai`
  („podąża za graczem”), który osobno przechodzi 3/3. To niestabilność czasowa, opisana w punkcie 5.

## 7. Ograniczenia

* Ramki styleboxów (tekstury obramowań) nie są skalowane przy `gui_scaling` > 1: rośnie tekst i wymiary,
  a grubość ramek zostaje 1:1.
* Detektor ramek opiera się na kolorze. Jasne, złoto-brązowe elementy sceny (belki, gobeliny) mogą się
  doklejać do sąsiedniego okna, dlatego wyniki trzeba czytać razem z parami zrzutów.
* OpenMW zostawia pod spodem okna z poprzednich kroków kreatora, co zaniża IoU dla okien klasy i znaku
  urodzenia. Wizualnie te okna są zgodne.
* Zrzuty i pary obrazów zawierają obraz gry, więc są tylko lokalnie (`OpenMW RLF/Raporty/ui-etap7`), nie w
  repozytorium.
* Pliki `godot/l10n/*` pochodzą z OpenMW (GPLv3, dane silnika, nie zasoby Bethesdy). Ustawienie
  `preferred_locales` nie ma jeszcze pola w launcherze.
