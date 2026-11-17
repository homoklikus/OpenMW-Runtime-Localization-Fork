# Inwentaryzacja zgodności OpenMWGodot z OpenMW

Stan na 2026-11-17 (po etapach „pełny start gry”, „pięć okien tworzenia postaci” i „MWScript zgodny z OpenMW”). Cel: wierne odtworzenie OpenMW, zanim
zajmiemy się remasterem. OpenMW jest źródłem prawdy (fork `apps/openmw`, ten sam kod co oficjalne 0.51).

## Statusy

| Status | Znaczenie |
|---|---|
| **Zweryfikowane** | zachowanie porównane z kodem OpenMW **i** sprawdzone testem regresyjnym albo sondą na prawdziwych danych |
| **Zaimplementowane** | jest w kodzie i ma testy na danych syntetycznych, ale nie porównano go krok po kroku z OpenMW |
| **Częściowo zgodne** | działa inaczej niż OpenMW albo tylko w części (różnice opisane) |
| **Brakujące** | nie ma albo jest tylko zaślepka/stała wartość |
| **Nieprzetestowane** | nie wiadomo – trzeba sondy albo porównania |

Priorytet: **P1** – psuje wierność od pierwszych minut gry, **P2** – zauważalne w zwykłej grze, **P3** – rzadkie.

Sposób sprawdzenia: przegląd kodu OpenMW, testy `tools/run_tests.sh` (dane syntetyczne), sondy na prawdziwych
danych na VM użytkownika (tylko identyfikatory i liczby – bez tekstów gry). **Porównanie w działaniu z OpenMW
przez MCP-openMW (`openmw_ai_compare_start`) nie działa**: serwer MCP działa w sesji pulpitu użytkownika i nie ma
dostępu do ekranu X („Authorization required … x11 not available” – brak uprawnień do ekranu sesji, prawdopodobnie
po zablokowaniu/ponownym logowaniu; nie ingerowaliśmy w sesję). **Obejście (od etapu startu gry):** oficjalne
OpenMW 0.51.0 uruchamiane na VM na wirtualnym ekranie Xvfb (renderowanie programowe llvmpipe, bez dźwięku,
glibc 2.39 i libstdc++ 14 z Ubuntu 24.04 tylko dla tego procesu, konfiguracja w /tmp – bez zmian w systemie
i profilu użytkownika), sterowane przez XTest; Godot uruchamiany na tym samym Xvfb (renderer zgodności).

## 1. Start gry i menu

Etap „pełny start gry” (2026-11-17). Porównanie z działającym OpenMW 0.51.0 (oficjalne wydanie) na wirtualnym
ekranie Xvfb na VM – zrzuty obu silników w `OpenMW RLF/Raporty/xvfb-2026-11-17/` (lokalnie, nie w repozytorium).
Sonda `godot/tests/probe_start.gd` na prawdziwych danych (12/12) i test `test_start_game.gd` na syntetycznych (62/62).

| Element | Status | Wynik / różnice | Prio |
|---|---|---|---|
| Kolejność startu (Engine::go): logo firmy → menu główne + muzyka tytułowa → logo Morrowinda | Zweryfikowane | ta sama kolejność na zrzutach OpenMW i Godota; logo firmy 16,2 s przy długości 16,0 s, tempo 4,01 s po 4 s; logo Morrowinda bez wyciszania muzyki | – |
| Filmy: lokalna konwersja Bink → Theora (ffmpeg gracza), ścieżka aktualizacji, błędy | Zaimplementowane | 17 filmów zakodowanych na VM (~2 min, 140 MB w katalogu danych gracza); kodowanie tylko po zmianie źródła; brak ffmpeg/kodera – filmy pominięte z komunikatem; test_video (atrapa ffmpeg) | – |
| Pomijanie filmów (tylko Esc, gdy allowSkipping) | Zweryfikowane | Esc pomija logo Morrowinda i wstęp w obu silnikach | – |
| Synchronizacja obrazu i dźwięku filmów | Nieprzetestowane | tempo obrazu zgodne z zegarem; zgodności dźwięku nie da się sprawdzić bez urządzenia audio (VM: dźwięk wyłączony w obu silnikach) | P2 |
| Menu główne (bez gry: Nowa gra, Opcje, Zasługi, Wyjdź, „Wczytaj” przy zapisach; w grze: Wróć, Nowa gra, Zapisz, Wczytaj, Opcje, Wyjdź) | Zweryfikowane | układ przycisków i obraz tła zgodne ze zrzutami OpenMW; Nowa gra/Wyjdź w trakcie gry z potwierdzeniem; Zasługi = film mw_credits | – |
| Animowane tło menu | Zweryfikowane | OpenMW z danymi Morrowinda pokazuje **obraz** menu_morrowind.dds (animacja tylko, gdy istnieje video/menu_background.bik – w Morrowindzie go nie ma); u nas tak samo | – |
| Ekrany ładowania (Splash/, pasek, etykieta; tapeta tylko bez gry, w grze zamrożona klatka po 50 ms) | Częściowo zgodne | wygląd tapety i paska sprawdzony zrzutem Godota; ekranu OpenMW nie uchwycono (ładowanie za szybkie); dane wczytujemy przed logo, więc ekranu „Inicjalizacja…” po logo firmy nie ma | P3 |
| Okno zapisu/wczytania (postać, lista, zrzut 259×133, komórka, opis, usuń, nazwa, OK/Anuluj) | Zweryfikowane | układ i treść opisu zgodne ze zrzutami OpenMW (Poziom, Dzień, Zdrowie, data w grze, czas gry, data pliku) | – |
| Zapisy według postaci, nadpisywanie z potwierdzeniem, usuwanie z potwierdzeniem, pusta nazwa | Zweryfikowane | jak CharacterManager/SaveGameDialog; test_start_game | – |
| Szybki zapis/odczyt (F5/F9) | Zaimplementowane | „Quicksave”, najstarszy z max quicksaves nadpisywany; odczyt – najnowszy zapis postaci | – |
| Zgodność wsteczna zapisów | Zweryfikowane | zapisy sprzed etapu (katalog główny, bez opisu) widoczne jako osobna postać, wczytywane z migracją; nowe zapisy tej postaci idą do katalogu postaci | – |
| Uszkodzony plik zapisu | Zweryfikowane | pominięty na liście; wczytanie – stan wyczyszczony, menu główne i komunikat, plik nietknięty | – |
| Menu pauzy = menu główne w grze (Esc) | Zweryfikowane | HUD widoczny pod menu (jak OpenMW) | – |
| Śmierć gracza: stan „Ended”, po animacji pytanie o wczytanie ostatniego zapisu / menu | Częściowo zgodne | czas animacji śmierci stały (3 s) zamiast końca animacji gracza | P2 |
| `PlayBink`, `FadeIn`/`FadeOut`/`FadeTo` | Zaimplementowane | ScreenFader – kolejka i liniowe przejścia jak OpenMW; PlayBink zatrzymuje świat na czas filmu, ale reszta skryptu wykonuje się w tej samej klatce (w OpenMW po filmie) | – |
| Nowa gra z menu: ekran ładowania, film Movies_New_Game, fadeScreenOut(0)+fadeScreenIn(1) | Zweryfikowane | statek po filmie, przejście z czerni w 1 s; HUD bez pasków/minimapy na starcie (wcześniej widoczny – naprawione) | – |
| Autozapis przy odpoczynku ([Saves] autosave) | Brakujące | | P2 |
| `WakeUpPC`, `GetPCSleep` (sny wątku głównego) | Częściowo zgodne | od etapu MWScript: odpoczynek godzina po godzinie (TimeAdvancer), skrypty w trakcie, WakeUpPC przerywa; brak przerywania snu stworzeniami – punkt 4a | P2 |

## 2. Nowa gra (statek więzienny → urząd celny → Seyda Neen)

Sonda `godot/tests/probe_newgame.gd` (prawdziwe dane, agent gracza chodzi po siatce nawigacji, aktywuje obiekty
z bliska tylko przy odblokowanym sterowaniu, zamyka okna jak gracz): **15/15 sprawdzeń, cała sekwencja w 126 s.**

| Etap | Status | Wynik sondy (kolejność zdarzeń zgodna ze skryptami CharGen) |
|---|---|---|
| Jiub (`chargennamenpc`): kwestia → okno imienia | Zweryfikowane | t≈7 s okno imienia; stany 10 → 20 → 40 → −1 |
| Strażnik (`chargenwalknpc`): AiTravel pod pokład do gracza | Zweryfikowane | po naprawie (punkt 7) schodzi schodami, stan 30 przy graczu (t≈22 s), `GetAIPackageDone` dopiero u celu |
| Komunikat, `EnablePlayerControls`, AiEscort na pokład, AiTravel, stan 60 → −1 | Zweryfikowane | eskorta czeka na gracza, kończy się na górnym pokładzie (t≈45 s) |
| Wyjście ze statku (`chargen_shipdoor`, komunikat `CharGenCustomsDoor` < 300 j.) | Zweryfikowane | teleport na nabrzeże |
| Strażnik na nabrzeżu (`chargenracenpc`): podejście < 108 j. → menu rasy → AiTravel | Zweryfikowane | stany 10 → 30 → 40 → 50 → −1 |
| Urząd: `chargenclassnpc` (< 100 j.) → klasa → znak → przegląd → `EnableStatsMenu`, `RaceCheck` | Zweryfikowane | kolejność menu: imię, rasa, klasa, znak, przegląd |
| Arkusz (`chargenstatssheet`): `Activate` + `EnableInventoryMenu`, przycisk „Weź” | Zweryfikowane | „Weź” widoczny dopiero po odblokowaniu ekwipunku (BookWindow::setInventoryAllowed) |
| Strażnik drzwi (`chargendoorguardtalker`): arkusz → `Unlock` drzwi | Zweryfikowane | |
| Drzwi do korytarza – **drzwi obrotowe** | Zweryfikowane | wcześniej brak mechaniki (drzwi bez teleportu się nie otwierały) – punkt 7 |
| Podwórze: beczka (`chargenfatiguebarrel` < 400 j.), pierścień (`chargen_ring_keley`, 3 komunikaty), `EnableMagicMenu` | Zweryfikowane | |
| Drzwi kapitana (`chargendoorentercaptain`, wymaga pierścienia) | Zweryfikowane | |
| Sellus Gravius: powitanie zabiera arkusz (`state` −1), temat „duties” (znany z tematu „morrowind”) → dziennik `A1_1_FindSpymaster` 1, paczka, wskazówki, 87 sztuk złota | Zweryfikowane | tematy dopisywane z hiperłączy jak w OpenMW |
| Wyjście (`chargendoorexitcaptain`): `CharGenState` −1, odblokowanie okien, teleport do Seyda Neen | Zweryfikowane | po wyjściu brak blokad sterowania i okien |
| Blokady okien w trakcie tworzenia postaci (disallowAll) – także odpoczynek | Zweryfikowane | **naprawione:** odpoczynek był dozwolony; teraz zablokowany do `EnableRest` albo `CharGenState` −1 (getRestEnabled) |
| Okna kreatora jak w OpenMW: imię, rasa (podgląd 3D, płeć, twarz, włosy), klasa (wybór/pytania/własna), znak, przegląd z „Wstecz” | Zweryfikowane | osobne okna jak OpenMW – szczegóły w punkcie 2a; sonda nowej gry 15/15 po zmianie | – |
| Wstęp wideo i zaciemnienie po starcie | Zweryfikowane | punkt 1 | – |

Odchylenie sondy od gracza: aktywacja z odległości 64 j. w poziomie od obiektu (w OpenMW – promień z kamery
do obiektu ≤ iMaxActivateDist 192); odległości 3D od oczu zapisuje dziennik sondy (63–136 j.).

## 2a. Tworzenie postaci – pięć okien (etap 2026-11-17)

Wspólny formularz zastąpiony oknami odwzorowującymi OpenMW (`apps/openmw/mwgui/charactercreation.cpp`, `race.cpp`,
`class.cpp`, `birth.cpp`, `review.cpp`, `textinput.cpp`; układy `files/data/mygui/openmw_chargen_*.layout`,
`openmw_text_input.layout`, `openmw_infobox.layout`): pozycje i rozmiary z plików układu × skala interfejsu,
skórki MW_Dialog / MW_DialogNoTransp / MW_Box / MW_List / MW_Button / SandText / HeaderText, strzałki
`omw_menu_scroll_*` (tekstury OpenMW). Jedna implementacja zasad: każdy wybór trafia od razu do postaci
(`step_done` → `MWCharacter.build` od zera), więc powroty nie dublują premii. Kod: `mw_chargen_window.gd`
(przebieg CSE, imię, rasa, znak, przegląd), `mw_chargen_class.gd` (okna klas), `mw_chargen_ui.gd` (elementy układów).

Porównanie z oficjalnym OpenMW 0.51.0 na Xvfb (1280×720, skala 1,0 w obu silnikach, te same dane, okna otwierane
`--script-run` z EnableNameMenu/EnableRaceMenu/EnableClassMenu/EnableBirthMenu/EnableStatReviewMenu) – zrzuty
obu silników w `OpenMW RLF/Raporty/xvfb-2026-11-17/chargen/{openmw,godot}` (lokalnie). Testy: `test_chargen_windows.gd`
(70), `test_chargen_class.gd` (29), `test_character.gd` (20), `test_chargen.gd` (21); sonda na prawdziwych danych
`probe_chargen.gd` (8 sprawdzeń zbiorczych: 10 ras × 2 płcie – wszystkie twarze i włosy z zawijaniem i podglądem,
21 klas – obraz i statystyki, 13 znaków – obraz i czary, wszystkie 66 kombinacji odpowiedzi pytań → istniejąca
klasa, statystyki po 9 powrotach = buildPlayer od zera) i `probe_newgame.gd` (15/15, statek → Seyda Neen w 125 s).

| Element | Status | Wynik / różnice | Prio |
|---|---|---|---|
| Przebieg CharacterCreation: etapy CSE, handleDialogDone (okno ze skryptu zamyka się, gdy etap nieosiągnięty), „Dalej” zamiast OK po przejściu etapu, Wstecz (rasa → imię, klasa/znak → wybór sposobu, przegląd → znak → przegląd), przyciski przeglądu (ReviewNext) | Zweryfikowane | kod OpenMW + test_chargen_windows + sonda nowej gry | – |
| Okno imienia (320×97): etykieta sName, pole, OK/sNext, Enter, puste imię → komunikat sNotifyMessage37 i okno zostaje | Zweryfikowane | układ zgodny ze zrzutem OpenMW | – |
| Okno rasy (640×433): lista grywalnych ras według nazwy, podgląd 3D głowy (VM_HeadOnly, kamera 125 j. przed kością „Bip01 Head”, 12,3°, pochylenie 6°, obrót suwakiem 0–999 od 600, kółko myszy ±50), płeć/twarz/włosy ze strzałkami (zawijanie, reset do pierwszej przy zmianie rasy/płci, części w kolejności rekordów, bez BPF_NotPlayable i „1st”), premie umiejętności, moce | Zweryfikowane | zrzut: układ, czcionka, kolory, lista i podgląd jak w OpenMW; oświetlenie z Inventory_Directional* | – |
| Atrybuty rasy w oknie rasy | Zweryfikowane (brak jak w OpenMW) | OpenMW **nie pokazuje** atrybutów w oknie rasy (tylko premie i moce); atrybuty widać w przeglądzie – tak samo u nas | – |
| ClassChoiceDialog (InfoBox: pytania, lista, własna, Wstecz → rasa) | Zweryfikowane | rozmiar i układ przycisków jak na zrzucie (±4 px) | – |
| PickClassDialog (491×316): lista grywalnych klas bez własnych, obraz textures/levelup (brak – warrior), specjalizacja, atrybuty, umiejętności | Zweryfikowane | zrzut zgodny | – |
| Pytania (InfoBox z losową kolejnością odpowiedzi, głos chargen qaN, tabela showClassQuestionDialog) i GenerateClassResultDialog | Zweryfikowane | zrzuty zgodne (zawijanie długich odpowiedzi jak MW_Button); bez tekstów pytań w danych gracza opcja pytań jest ukryta (OpenMW ma je zawsze w openmw.cfg) | – |
| CreateClassDialog (498×198) z oknami wyboru specjalizacji/atrybutu/umiejętności (zamiana duplikatów) i opisu; okno pamięta wybory; bez nazwy OK nie działa | Zweryfikowane | zrzuty zgodne; rekord klasy dynamiczny w zapisie | – |
| Okno znaku (527×378): lista według nazwy, obraz TNAM, zdolności (efekty stałe bez czasu i zasięgu), moce, czary z ikonami i opisem efektu jak MWSpellEffect | Zweryfikowane | zrzut zgodny | – |
| Przegląd (541×428): imię/rasa/klasa/znak z przyciskami, zdrowie/magia/kondycja, atrybuty i umiejętności z kolorami zmian, umiejętności główne/drugorzędne/pozostałe, zdolności/moce/czary | Zweryfikowane | zrzut zgodny | – |
| Czary początkowe gracza (autoCalcPlayerSpells: PCStart, magia bazowa, fAutoPCSpellChance, attrSkillCheck, iAutoPCSpellMax) | Zaimplementowane | **naprawione:** wcześniej brak; teraz w MWCharacter.build (test_character, przegląd) – nie porównano listy czarów z działającym OpenMW | P2 |
| Konwersja: części ciała wszystkich grywalnych ras | Zweryfikowane | **naprawione:** przy konwersji wybranych komórek brakowało modeli ras bez NPC w tych komórkach (pusty podgląd orka/khajiitki i brak ciała po wyborze) | – |
| Podpowiedzi (tooltipy) ras, klas, umiejętności, atrybutów jak ToolTips OpenMW (ikona, opis) | Częściowo zgodne | u nas zwykły tekst (nazwa i efekty czarów); brak okienek z ikoną i opisem | P3 |
| Teksty „Anuluj”/„OK” w oknach wyboru (Interface:Cancel/OK) | Częściowo zgodne | po polsku jak reszta interfejsu silnika; GMST z danych gracza bez zmian | P3 |
| Paski przewijania MW_VScroll/MW_HScroll | Częściowo zgodne | strzałki OpenMW, tor i suwak rysowane kolorem (bez tekstur suwaka) | P3 |
| Sterowanie padem (controller menus) | Brakujące | | P3 |
| Porównanie zrzutów piksel w piksel | Nieprzetestowane | tło za oknami różni się (inna pozycja startowa świata), czcionka rysowana przez inny rasteryzator – porównanie wzrokowe, nie automatyczne | – |

## 3. Interfejs

| Element | Status | Uwagi | Prio |
|---|---|---|---|
| Tryb menu (statystyki, ekwipunek, magia, mapa), HUD, pojemnik, handel, alchemia, rozmowa | Zaimplementowane | etap 10i–10k; układ z OpenMW, brak porównania zrzutami | – |
| Pasek zdrowia wroga w HUD | Brakujące | | P2 |
| Szybkie klawisze (F1, 1–9) | Brakujące | | P1 |
| Okno ilości (dzielenie stosów, Shift przy przeciąganiu) | Brakujące | dziś zawsze cały stos / 1 sztuka | P2 |
| Dziennik jak książka (zadania, indeks tematów, strony) | Brakujące | dziś lista | P2 |
| Okno awansu (obraz klasy, mnożniki atrybutów) | Częściowo zgodne | | P2 |
| Odpoczynek/czekanie (układ OpenMW, „do wyleczenia”) | Częściowo zgodne | | P2 |
| Tworzenie zaklęć (usługa) | Brakujące | | P2 |
| Naprawa u kupca / młotkiem, ładowanie kamieniem duszy | Częściowo zgodne | logika częściowo, okna OpenMW brak | P2 |
| Zaklinanie, kupno zaklęć, trening, podróż w układzie OpenMW | Częściowo zgodne | wygląd Morrowinda, układ list | P3 |
| Więzienie (okno odsiadki, utrata umiejętności) | Nieprzetestowane | | P2 |
| Towarzysz (dzielenie ekwipunku), przechodzenie przez drzwi | Brakujące | | P2 |
| Konsola (~) | Brakujące | przydatna też do testów | P3 |
| Ustawienia jak OpenMW (zakładki, klawisze) | Częściowo zgodne | mniej opcji | P3 |
| Kursor z gry (`tx_cursor`) | Brakujące | | P3 |
| Podpowiedź nad obiektem w świecie: waga, wartość, właściciel na czerwono | Częściowo zgodne | dziś tekst akcji | P2 |
| Okno komunikatu (MessageBox) w stylu i położeniu OpenMW | Częściowo zgodne | | P3 |
| Książka/zwój: „Weź” tylko przy odblokowanym ekwipunku | Zweryfikowane | test_chargen + sonda | – |

## 4. Skrypty (Morrowind, Tribunal, Bloodmoon)

**Stan po etapie MWScript (2026-11-17) – szczegóły w punkcie 4a.** Mapa poniżej (stałe zera, nieobsłużone) to stan
sprzed etapu, zostawiony dla porównania.

Wcześniejsze wywołanie na sucho (cel: gracz): 127 funkcji zwraca wynik, 13 zwraca stałe 0, 96 nieobsłużonych.
**127 działających funkcji to status „Zaimplementowane”, nie „Zweryfikowane”** – zweryfikowane są tylko te, które
przeszły sondę nowej gry: `Say`/`SayDone`, `GetDistance`, `AITravel`, `AIEscort`, `AIWander`,
`GetAIPackageDone`, `MessageBox`/`GetButtonPressed`, `Enable*Menu`, `Enable/DisablePlayer*`, `Disable`,
`OnActivate`/`Activate`, `OnPCAdd`, `GetItemCount`, `Unlock`, `GetStandingPC`, `StartScript`/`StopScript`,
`GetRace`, `Journal`, `AddItem`/`RemoveItem`, `AddTopic`, `ShowMap`, `MenuMode`, `GetSecondsPassed`,
`GetDisabled`, `PositionCell`, `ChangeWeather`, zmienne lokalne i globalne (`CharGenState`).

### Mapa zależności: funkcje → zadania, skrypty i mechanika

Analiza statyczna skryptów z danych (Morrowind + Tribunal + Bloodmoon) i kodu interpretera (`mw_scripts.gd`,
`mw_script_host.gd`): funkcja, liczba skryptów, przykładowe zadania (identyfikatory dziennika z tych samych
skryptów), mechanika. Pełna lista: 110 nazw bez obsługi (część może być obsłużona przez wzorzec nazwy –
do potwierdzenia przy wdrażaniu).

**Stałe zera (zachowanie fałszywe – najpierw do naprawy, bo skrypty „działają”, a robią co innego):**

| Funkcja | Skrypty | Zadania (przykłady) | Mechanika |
|---|---|---|---|
| `OnPCHitMe` | 31 | 21 zadań: `co_1`, `co_2`, `co_13a`, `bm_brodirgrove`, `bm_wolfgiver` | reakcja NPC na uderzenie (walka) |
| `GetTarget` | 15 | 13: `co_8`, `co_9a`, `co_12`, `bm_wildhunt` | cel walki AI |
| `IsWerewolf` | 14 | 8: `bm_bearhunt1/2`, `bm_ceremony1/2`, `bm_frostgiant1` | wilkołactwo (Bloodmoon) |
| `GetPCSleep` | 11 | 15: `a1_2_antabolisinformant`, `a1_6_addhiranirrinformant`, `a1_10_mehramilo`, `a1_11_zainsubaniinformant`, `a1_dreams` | sen gracza – **wątek główny (sny, napaść Mrocznego Bractwa)** |
| `GetDetected` | 10 | 7: `hh_twinlamps1/3`, `hr_arobarkidnap`, `hr_rescuesarethi`, `eb_bone` | wykrywanie skradania |
| `OnKnockout` | 5 | 5: `hr_honorchallenge`, `hr_billcollect`, `ms_bouncer` | powalenie (zmęczenie) |
| `OnMurder` | 5 | 4: `b5_venimhort`, `hr_archmaster`, `hr_foundershelm` | zabójstwo (przestępstwa) |
| `GetAttacked` | 5 | 2: `ms_adulterer`, `ms_barbarianbook` | |
| `GetWerewolfKills`, `GetPCInJail`, `GetPCTraveling` | 2–3 | Bloodmoon: `bm_*` | wilkołactwo, więzienie, podróż |
| `GetPCSneaking` | 2 | – (`proximitymine`) | skradanie |
| `GetLOS` | 2 | `da_mephala`, `fg_nchurdamz` | linia widzenia |

**Nieobsłużone (najczęstsze):**

| Funkcja | Skrypty | Zadania (przykłady) | Mechanika |
|---|---|---|---|
| `SetHealth` | 33 | 14: `bm_bearhunt1`, `bm_meadhall`, `bm_missionary`, `bm_skaalattack`; skrypty globalne `endgame` | statystyki dynamiczne |
| `BecomeWerewolf`, `UndoWerewolf`, `SetWerewolfAcrobatics` | 18 / 5 / 3 | 9: `bm_bearhunt*`, `bm_ceremony*` | wilkołactwo |
| `ModHealth`, `ModCurrentHealth`, `ModFatigue`, `SetFatigue`, `ModMagicka`, `SetMagicka`, `ModCurrentFatigue` | 2–16 | `c3_destroydagoth`, `tr_champion`, `va_vampcurse`, `ms_crimsonplague` | statystyki dynamiczne – **zakończenie wątku głównego** |
| ~~`PlayBink`~~ | 10 | 11: `a1_sleepersawake`, `a2_6_incarnate`, `bm_bearhunt*` | **zaimplementowane** (etap startu gry) |
| `Resurrect` | 10 | `tr_champion`, `bm_trees`, `co_10` | |
| `WakeUpPC` | 8 | 17 zadań wątku głównego (`a1_*`) | sen – **wątek główny** |
| ~~`FadeIn`/`FadeOut`~~ (i `FadeTo`) | 7/7 | Bloodmoon `bm_*` | **zaimplementowane** (etap startu gry) |
| `Mod*`/`Set*`/`Get*` atrybutów i umiejętności (`ModRestoration` 65 obiektów, `ModStrength`, `GetStrength`, …) | 1–7 | `va_vampcurse`, `tg_bitterbribe`, `co_12`, `tr_champion` | statystyki |
| `ModResist*` (5 wariantów), `SetScale` | 6 | `bm_trees`, `co_10` | stworzenia skryptowe |
| `ForceSneak`/`ClearForceSneak`, `ForceRun` | 4/1 | 7: `co_3`, `co_6`, `co_6a`, `ms_adulterer`, `co_12` | ruch NPC |
| `Move`/`MoveWorld` | 5/5 | `ms_crimsonplague`, `tt_maskvivec` | ruch obiektów (platformy, kamienie) |
| `Enable/DisableTeleporting`, `Enable/DisableLevitation` | 3–4 | `c3_destroydagoth`; `tribunalmain`, `bloodmoonmain`, `endgame` | blokady magii |
| `ModRegion` | 4 | `c3_destroydagoth`, `tr_showpower`, `tr_sothasil` | pogoda (zakończenie wątku głównego) |
| `Drop` | 3 (160 obiektów) | `ht_slaverebellion` | ekwipunek NPC |
| `SetWaterLevel`/`ModWaterLevel` | 3/1 | – | woda |
| `HurtStandingActor`/`HurtCollidingActor`, `GetCollidingPC`/`GetCollidingActor`/`GetStandingActor` | 1–3 | – (pułapki, `explosion_pushout`) | fizyka |
| `RaiseRank` | 1 | `mg_flowers`, `mg_stolenreport` | frakcje (Gildia Magów) |
| `HasItemEquipped`, `GetWeaponType` | 2/1 | `co_5`, `co_12`, `co_12a` | ekwipunek |
| `TurnMoonRed`/`TurnMoonWhite` | 1 | `bm_frostgiant1/2`, `bm_wildhunt` | niebo |
| `RemoveSoulGem`, `OnPCSoulGemUse` | 2/1 | – (Gwiazda Azury) | dusze |
| `Face`, `Fall`, `PlaceItemCell`, `PlaySoundVP`, `GetSquareRoot`, `GetStat`, `GetParalysis` | 1 | `tr_champion`, `ms_crimsonplague`, `ms_thief` | różne |

Wniosek: żadna z tych funkcji nie jest potrzebna w sekwencji nowej gry (sonda: `unsupported` puste). Najwcześniej
potrzebne są `GetPCSleep`/`WakeUpPC` (sny wątku głównego), `PlayBink`/`Fade*` (start gry) i rodzina statystyk
(`Set*`/`Mod*`) – zgodnie z zasadą „funkcje potrzebne wcześniej wdrażamy od razu” wchodzą do etapu 1/3 roadmapy.

## 4a. MWScript – zgodność funkcji z OpenMW (etap 2026-11-17)

**Miarą zgodności nie jest liczba rozpoznawanych instrukcji**, tylko to, czy wykonanie daje ten sam stan gry co
OpenMW. Każda funkcja oznaczona „Zweryfikowane” przeszła porównanie z oficjalnym OpenMW 0.51 na tych samych danych
(Morrowind + Tribunal + Bloodmoon) albo sondę nowej gry; „Zaimplementowane” – działa według kodu OpenMW i ma test
syntetyczny albo wspólną ścieżkę kodu ze zweryfikowanymi, ale nie było porównania.

**Audyt przed etapem (ponowne liczenie, 1207 skryptów, stary kompilator, 253 nazwy):** 142 rozpoznawane
(130 po nazwie + 12 getterów statystyk przez wzorzec nazwy – to część „17 niezbadanych” z wcześniejszej
inwentaryzacji), 13 stałych zer, 97 bez obsługi (w tym `fakeiswere`, które nie jest funkcją). Wśród
„rozpoznawanych” były pozorne: gettery atrybutów i umiejętności NPC zwracały 0, `AddSpell`/`RemoveSpell` działały
tylko na gracza, `HasSoulGem` zwracało 0/1 zamiast liczby, `OnPCAdd`/`OnPCEquip`/`OnPCDrop` były funkcjami
„zużywanymi” przy odczycie (w OpenMW to zmienne lokalne ustawiane przez silnik), `OnDeath` było kasowane co klatkę.

**Co zmieniło się w interpreterze (poza nowymi funkcjami):**

* Kompilator czyta argumenty według sygnatur z kodu OpenMW (`components/compiler/extensions0.cpp`, plik
  generowany `converter/mwconv/mwscript_sig.py`, 511 wpisów): tryb argumentu (`+`, `-`, porównania kończą argument
  poza nawiasami), argumenty opcjonalne i pomijane, nazwy `c` małymi literami, zmienna lokalna zasłania funkcję,
  instrukcja w wyrażeniu – nazwa, nieznana nazwa w wyrażeniu – liczba z ostrzeżeniem, `obiekt->zmienna` – odniesienie
  pominięte („Stray explicit reference”). Na danych gry: błędy kompilacji 1 = 1, ostrzeżenia 43 = 43 (jak przed).
* `OnPCAdd`, `OnPCEquip`, `OnPCDrop`, `OnPCHitMe`, `OnPCRepair`, `OnPCSoulGemUse`, `PCSkipEquip` – zmienne lokalne
  ustawiane na 1 przez silnik, tylko gdy skrypt je deklaruje; kasuje je skrypt (OpenMW `setVarByInt`).
* Kolejność jak `Engine::frame`: skrypty lokalne, potem globalne; skrypty działają także przy otwartych oknach
  (pauza drzewa Godota) – poza menu głównym w pauzie (`MenuMode` ma więc sens jak w OpenMW).
* Błąd wykonania: skrypt globalny zatrzymany (`GlobalScripts::run`), lokalny wyłączony dla obiektu do wczytania
  gry; funkcja z odniesieniem wywołana bez obiektu w skrypcie globalnym (`MissingImplicitRefError`, tabela
  `godot/scripts/mw/mw_script_refs.gd` z kodu OpenMW) – przerwanie i zatrzymanie (porównane: `fail_global`).
* Statystyki aktorów (`mw_actor_stats.gd`): baza, modyfikator, ubytek i bieżąca jak `AttributeValue`/`SkillValue`/
  `DynamicStat` (Set czyści modyfikator, Mod z limitem 100, ModCurrent bez górnego limitu, kondycja poniżej zera →
  powalenie), przeliczanie magii przy INT/Fortify Maximum Magicka i kondycji przy Str/Wil/Agi/End z zachowaniem
  proporcji; także NPC i stworzenia poza wczytaną komórką (stan w zapisie).
* Poprawione przy okazji (wykryte porównaniem): zdolności rasy NPC (`race->mPowers`) w efektach i magii NPC,
  odnawianie kondycji NPC (`calculateRestoration`), martwy aktor bez efektów zdolności/czarów, spłata grzywny
  uspokaja świadków (identyfikatory przestępstw `getNewCrimeId`/`recordCrimeId`), reakcja na cios (`GetAttacked`,
  towarzysze – `friendlyHit`, „pokojowi” z `OnPCHitMe` i Fight 0), `SetPCCrimeLevel` bez obcięcia do zera, teleport
  gracza bez obrażeń od upadku, nazwa wnętrza z rekordu komórki (kompilator zamienia nazwy na małe litery).

**Porównania z OpenMW** (`tools/openmw-xvfb/mwscript_compare.py`, przypadki `tools/openmw-xvfb/mwscript_cases/`,
etapy `tools/openmw-xvfb/mwscript_case.sh PRZYPADEK all`): oficjalne OpenMW na Xvfb wykonuje polecenia z dodatku
testowego (jeden skrypt globalny, bez danych gry) w 30. klatce, skrypt Lua zapisuje migawkę (statystyki bazowe/
zmodyfikowane/bieżące, efekty, poziom, frakcje, ekwipunek, przedmioty, zmienne skryptu, pozycje, skala, flagi
gracza); sonda Godota (`godot/tests/probe_mwscript.gd`) wykonuje ten sam skrypt skompilowany konwerterem i zapisuje
tę samą migawkę. Przy różnych wartościach bazowych (np. inny gracz bez kreatora) porównywane są zmiany albo
wartości po. Wynik wszystkich 15 przypadków (końcowy przebieg na kodzie z tego etapu): **0 różnic** (po poprawkach wymienionych wyżej). Pominięte pola:
pozycje aktorów (AI wędrówki), bieżąca kondycja w długich przypadkach (czas klatek llvmpipe), punkty AI.

**Sondy na prawdziwych danych po etapie:** nowa gra 15/15, start gry 12/12, kreator postaci 8/8;
`tools/run_tests.sh` – wszystkie testy (nowy `test_mwscript_functions.gd`, 36 sprawdzeń).

**Nadal brakujące lub częściowe (zależności nie w zakresie etapu):** animacje śmierci i powalenia (czas `OnDeath`,
`OnKnockout`), przerywanie snu stworzeniami, okno więzienia, model i nakładka wilkołaka, efekt Lewitacji
i interwencje (flagi `Enable/Disable*` zapisywane), księżyce (`TurnMoonRed/White`), `SetAngle` w osiach X/Y,
fizyka zderzeń skryptowych bez Bullet (przybliżenie przez kolizje ruchu Godota). Funkcje z OpenMW nieużywane
w skryptach gry nie są w tabeli (np. `ForceJump`, `ForceMoveJump`, `GetForceJump`, `HitAttemptOnMe` – zaimplementowane przy okazji).

Tabela: wszystkie 252 nazwy używane w skryptach gry po kompilacji nowym kompilatorem; „Skrypty” – liczba skryptów
z daną funkcją; „Porównanie” – przypadki z wynikiem 0 różnic. Generowana: `tools/gen_mwscript_inventory.py`.

| Funkcja | Skrypty | Rodzaj | Status | Test | Porównanie z OpenMW | Zależności | Znane różnice |
|---|---|---|---|---|---|---|---|
| `getjournalindex` | 547 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `disable` | 390 | instrukcja | Zweryfikowane | test_scripts | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `journal` | 378 | instrukcja | Zweryfikowane | test_scripts | zgodne: misc2 | — | — |
| `enable` | 300 | instrukcja | Zweryfikowane | test_scripts | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `menumode` | 289 | funkcja (wartość) | Zweryfikowane | test_scripts | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `onactivate` | 258 | funkcja (wartość) | Zweryfikowane | test_scripts | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getdisabled` | 225 | funkcja (wartość) | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `ondeath` | 221 | funkcja (wartość) | Częściowo zgodne | test_mwscript_functions | zgodne: events_death | śmierć aktora | flaga od razu po śmierci (OpenMW – po animacji śmierci; animacji brak); kasowanie odczytem zgodne |
| `cellchanged` | 201 | funkcja (wartość) | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `getdistance` | 194 | funkcja (wartość) | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `messagebox` | 172 | — | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getsecondspassed` | 170 | funkcja (wartość) | Zweryfikowane | sonda nowej gry | zgodne: move_scale | — | — |
| `stopscript` | 124 | instrukcja | Zweryfikowane | test_scripts | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getitemcount` | 120 | funkcja (wartość) | Zweryfikowane | test_scripts | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `activate` | 118 | instrukcja | Zweryfikowane | test_scripts | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `startcombat` | 106 | instrukcja | Zweryfikowane | — | zgodne: misc3 | — | — |
| `getdeadcount` | 105 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `forcegreeting` | 98 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `removeitem` | 81 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `say` | 79 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `additem` | 77 | instrukcja | Zweryfikowane | test_scripts | zgodne: misc_player | — | — |
| `getpccell` | 77 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `aiwander` | 73 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `setfight` | 73 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `gethealth` | 69 | funkcja (wartość) | Zweryfikowane | — | zgodne: stats_player, stats_npc | — | — |
| `playsound` | 62 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `positioncell` | 57 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `cast` | 53 | instrukcja | Częściowo zgodne | — | — | — | gracz: tylko wybór czaru (jak OpenMW); NPC: efekty od razu, bez AiCast/animacji |
| `addspell` | 52 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `getbuttonpressed` | 48 | funkcja (wartość) | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getcurrentaipackage` | 48 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc3 | — | — |
| `getsoundplaying` | 40 | funkcja (wartość) | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `stopcombat` | 40 | instrukcja | Zweryfikowane | — | zgodne: misc3 | — | — |
| `playloopsound3dvp` | 39 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `getcommondisease` | 37 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `getpos` | 37 | funkcja (wartość) | Zweryfikowane | — | zgodne: move_scale, misc3 | — | — |
| `getaipackagedone` | 35 | funkcja (wartość) | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `sethealth` | 33 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: stats_player, stats_npc | — | — |
| `sethello` | 30 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `playgroup` | 29 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `getblightdisease` | 28 | funkcja (wartość) | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `startscript` | 28 | instrukcja | Zweryfikowane | test_scripts | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getpcrank` | 26 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `dontsaveobject` | 25 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `aitravel` | 24 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `placeitem` | 24 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `saydone` | 24 | funkcja (wartość) | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getpccrimelevel` | 23 | funkcja (wartość) | Zweryfikowane | — | zgodne: werewolf, misc2 | — | — |
| `random` | 22 | funkcja (wartość) | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `geteffect` | 21 | funkcja (wartość) | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `rotate` | 21 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `addtopic` | 20 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `becomewerewolf` | 18 | instrukcja | Częściowo zgodne | test_mwscript_functions | zgodne: werewolf | statystyki, ekwipunek, AI, przestępstwa | statystyki, szata, wiedza świadków i grzywna jak OpenMW; brak modelu wilkołaka, nakładki ekranu, pazurów |
| `getspell` | 18 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `lock` | 18 | instrukcja | Zweryfikowane | — | zgodne: misc3 | — | — |
| `aifollow` | 17 | instrukcja | Zweryfikowane | — | zgodne: misc3 | — | — |
| `removespell` | 17 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `unlock` | 17 | instrukcja | Zweryfikowane | sonda nowej gry | zgodne: misc3 | — | — |
| `modhealth` | 16 | instrukcja | Zweryfikowane | — | zgodne: stats_player, stats_npc | — | — |
| `setdisposition` | 16 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `disableplayercontrols` | 15 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getangle` | 15 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `gettarget` | 15 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc3 | AI (walka, powitanie) | — |
| `placeatpc` | 15 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `enableplayercontrols` | 14 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `iswerewolf` | 14 | funkcja (wartość) | Zweryfikowane | test_mwscript_functions | zgodne: werewolf | stan wilkołaka | — |
| `playsound3d` | 14 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `position` | 14 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `getstandingpc` | 13 | funkcja (wartość) | Częściowo zgodne | sonda nowej gry | — | — | jak GetStandingActor |
| `modreputation` | 12 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `getpcsleep` | 11 | funkcja (wartość) | Częściowo zgodne | test_mwscript_functions | — | odpoczynek (okno) | sen co godzinę po 1/60 s jak TimeAdvancer; brak przerywania snu stworzeniami (fSleepRandMod) |
| `getdetected` | 10 | funkcja (wartość) | Częściowo zgodne | — | — | AI (wykrywanie) | jak getLOS; zasięg przetwarzania 7168 j. stały |
| `playbink` | 10 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `resurrect` | 10 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: resurrect | stan aktora, koniec gry | — |
| `setdelete` | 10 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `xbox` | 10 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc3 | — | — |
| `getwaterlevel` | 9 | funkcja (wartość) | Zweryfikowane | test_mwscript_functions | zgodne: water/water_ship/water_ext | woda komórki | — |
| `modcurrenthealth` | 9 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: stats_player, stats_npc | — | — |
| `moddisposition` | 9 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `setpos` | 8 | instrukcja | Zweryfikowane | — | zgodne: misc3 | — | — |
| `wakeuppc` | 8 | instrukcja | Częściowo zgodne | test_mwscript_functions | — | odpoczynek (okno) | jak GetPCSleep |
| `fadein` | 7 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `fadeout` | 7 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `modrestoration` | 7 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `setangle` | 7 | instrukcja | Częściowo zgodne | — | zgodne: move_scale | — | tylko oś Z; osie X/Y zgłaszane jako nieobsługiwane |
| `modfatigue` | 6 | instrukcja | Zweryfikowane | — | zgodne: stats_player, stats_npc | — | — |
| `modresistfire` | 6 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `modresistfrost` | 6 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `modresistmagicka` | 6 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `modresistparalysis` | 6 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `modresistpoison` | 6 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `setatstart` | 6 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `setscale` | 6 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: move_scale | przebudowa węzła | — |
| `stopsound` | 6 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `changeweather` | 5 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enableplayerfighting` | 5 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enableplayermagic` | 5 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `explodespell` | 5 | instrukcja | Częściowo zgodne | — | — | — | gracz: tylko wybór czaru (jak OpenMW); NPC: efekty od razu, bez AiCast/animacji |
| `getattacked` | 5 | funkcja (wartość) | Zaimplementowane | test_mwscript_functions | — | walka, przestępstwa (spłata) | nieporównane z OpenMW |
| `getfatigue` | 5 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `loopgroup` | 5 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `move` | 5 | instrukcja | Zweryfikowane | — | zgodne: move_scale | fizyka, aktorzy na obiekcie | — |
| `moveworld` | 5 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: move_scale | fizyka, aktorzy na obiekcie | — |
| `onknockout` | 5 | funkcja (wartość) | Częściowo zgodne | test_mwscript_functions | zgodne: events_death | kondycja, powalenie | powalenie bez animacji; od ciosu stałe 2 s (OpenMW – długość animacji knockdown) |
| `onmurder` | 5 | funkcja (wartość) | Zweryfikowane | test_mwscript_functions | zgodne: events_death | przestępstwa (morderstwo) | — |
| `pcraiserank` | 5 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `playloopsound3d` | 5 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `setfatigue` | 5 | instrukcja | Zweryfikowane | — | zgodne: stats_player, stats_npc | — | — |
| `setflee` | 5 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `undowerewolf` | 5 | instrukcja | Częściowo zgodne | test_mwscript_functions | zgodne: werewolf_undo | statystyki, ekwipunek | jak BecomeWerewolf |
| `aiescort` | 4 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `clearforcesneak` | 4 | instrukcja | Zaimplementowane | test_mwscript_functions | — | ruch aktora | nieporównane z OpenMW |
| `enableteleporting` | 4 | instrukcja | Częściowo zgodne | test_mwscript_functions | — | — | Znakowanie/Przywołanie respektują flagę; Boska/Almsivi interwencja nie istnieją (magia) |
| `forcesneak` | 4 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: misc_player | ruch aktora | — |
| `getlocked` | 4 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc3 | — | — |
| `hassoulgem` | 4 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc_player | — | — |
| `modregion` | 4 | instrukcja | Zaimplementowane | — | — | pogoda | nieporównane z OpenMW |
| `modspeed` | 4 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `modstrength` | 4 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: stats_player | — | — |
| `playsound3dvp` | 4 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `setalarm` | 4 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `showrestmenu` | 4 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `disableteleporting` | 3 | instrukcja | Częściowo zgodne | test_mwscript_functions | zgodne: misc_player | — | jak EnableTeleporting |
| `drop` | 3 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: misc_player | ekwipunek, świat | — |
| `enableinventorymenu` | 3 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enablemagicmenu` | 3 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enablemapmenu` | 3 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enablestatsmenu` | 3 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getlevel` | 3 | funkcja (wartość) | Zweryfikowane | — | zgodne: stats_player | — | — |
| `getrace` | 3 | funkcja (wartość) | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `getspelleffects` | 3 | funkcja (wartość) | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `getweapondrawn` | 3 | funkcja (wartość) | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `getwerewolfkills` | 3 | funkcja (wartość) | Zweryfikowane | test_mwscript_functions | zgodne: werewolf | śmierć NPC (wilkołak) | — |
| `hurtcollidingactor` | 3 | instrukcja | Częściowo zgodne | — | — | — | jak GetCollidingPC |
| `modwillpower` | 3 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setmagicka` | 3 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `setmarksman` | 3 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `setwaterlevel` | 3 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: water/water_ship/water_ext | woda komórki | — |
| `setwerewolfacrobatics` | 3 | instrukcja | Zweryfikowane | — | zgodne: werewolf | statystyki | — |
| `disablelevitation` | 2 | instrukcja | Częściowo zgodne | — | — | — | jak EnableLevitation |
| `enablelevitation` | 2 | instrukcja | Częściowo zgodne | — | — | — | flaga zapisywana (LEVT); efekt Lewitacji nie jest jeszcze zaimplementowany |
| `getcollidingpc` | 2 | funkcja (wartość) | Częściowo zgodne | — | — | — | zderzenie z ostatniego ruchu Godota (slide collisions) zamiast Bullet |
| `getinterior` | 2 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `getlos` | 2 | funkcja (wartość) | Częściowo zgodne | — | — | fizyka (promień) | linia wzroku na wysokości 1,5 m (OpenMW – wysokość oczu aktora z Bullet) |
| `getpcinjail` | 2 | funkcja (wartość) | Częściowo zgodne | — | — | więzienie | brak okna więzienia – prawda przez jedną klatkę skryptów po GoToJail |
| `getpcsneaking` | 2 | funkcja (wartość) | Zaimplementowane | test_mwscript_functions | — | skradanie | nieporównane z OpenMW |
| `getpctraveling` | 2 | funkcja (wartość) | Zaimplementowane | — | — | podróże | nieporównane z OpenMW |
| `getsecurity` | 2 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getsneak` | 2 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getstrength` | 2 | funkcja (wartość) | Zweryfikowane | — | zgodne: stats_player | — | — |
| `hasitemequipped` | 2 | funkcja (wartość) | Zweryfikowane | test_mwscript_functions | zgodne: misc_player | — | — |
| `hitonme` | 2 | funkcja (wartość) | Zaimplementowane | test_mwscript_functions | — | walka | nieporównane z OpenMW |
| `hurtstandingactor` | 2 | instrukcja | Częściowo zgodne | — | — | — | jak GetStandingActor |
| `modagility` | 2 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `modblock` | 2 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `modcurrentfatigue` | 2 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: stats_player, stats_npc | — | — |
| `modendurance` | 2 | instrukcja | Zweryfikowane | — | zgodne: stats_npc | — | — |
| `modmagicka` | 2 | instrukcja | Zweryfikowane | — | zgodne: stats_player, stats_npc | — | — |
| `modmediumarmor` | 2 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modpcfacrep` | 2 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `placeatme` | 2 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `removesoulgem` | 2 | instrukcja | Zweryfikowane | — | zgodne: misc_player | — | — |
| `setagility` | 2 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `setathletics` | 2 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setblock` | 2 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setlongblade` | 2 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `setpccrimelevel` | 2 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `setrestoration` | 2 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setspeed` | 2 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `setstrength` | 2 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: stats_player, stats_npc | — | — |
| `setwillpower` | 2 | instrukcja | Zweryfikowane | — | zgodne: stats_player, stats_npc | — | — |
| `showmap` | 2 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `disableplayerfighting` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `disableplayerjumping` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `disableplayermagic` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `disableplayerviewswitch` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `disablevanitymode` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enablebirthmenu` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enableclassmenu` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enablenamemenu` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enableplayerjumping` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enableplayerviewswitch` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enableracemenu` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enablerest` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enablestatreviewmenu` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `enablevanitymode` | 1 | instrukcja | Zweryfikowane | sonda nowej gry | — | — | sonda nowej gry (bez porównania funkcji osobno) |
| `face` | 1 | instrukcja | Zaimplementowane | — | — | AI (AiFace) | nieporównane z OpenMW |
| `fakeiswere` | 1 | — | Nie funkcja | — | — | — | nie funkcja: `player->fakeiswere` – OpenMW pomija odniesienie („Stray explicit reference”) i czyta zmienną lokalną; kompilator konwertera tak samo (od tego etapu) |
| `fall` | 1 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: move_scale | — | — |
| `forcerun` | 1 | instrukcja | Zweryfikowane | test_mwscript_functions | zgodne: misc_player | ruch aktora | — |
| `getagility` | 1 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getchameleon` | 1 | funkcja (wartość) | Zweryfikowane | — | zgodne: stats_npc | — | — |
| `getcollidingactor` | 1 | funkcja (wartość) | Częściowo zgodne | — | — | — | jak GetCollidingPC |
| `getcurrentweather` | 1 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc3 | — | — |
| `getdisposition` | 1 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `getendurance` | 1 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getflee` | 1 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `getintelligence` | 1 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getluck` | 1 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getmagicka` | 1 | funkcja (wartość) | Zweryfikowane | — | zgodne: stats_player | — | — |
| `getmarksman` | 1 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getparalysis` | 1 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getpersonality` | 1 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getspeed` | 1 | funkcja (wartość) | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `getsquareroot` | 1 | funkcja (wartość) | Zweryfikowane | test_mwscript_functions | zgodne: misc_player | — | — |
| `getstandingactor` | 1 | funkcja (wartość) | Częściowo zgodne | — | — | — | kontakt z podłożem (normalna) zamiast Bullet |
| `getstat` | 1 | funkcja (wartość) | Zweryfikowane | test_mwscript_functions | zgodne: misc_player | — | — |
| `getweapontype` | 1 | funkcja (wartość) | Zweryfikowane | test_mwscript_functions | zgodne: misc_player | — | — |
| `getwillpower` | 1 | funkcja (wartość) | Zweryfikowane | — | zgodne: stats_npc | — | — |
| `gotojail` | 1 | instrukcja | Częściowo zgodne | — | — | — | brak okna więzienia (dni, umiejętności – od razu) |
| `modarmorer` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modathletics` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modaxe` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modbluntweapon` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modfactionreaction` | 1 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `modfight` | 1 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `modheavyarmor` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modintelligence` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modlongblade` | 1 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `modluck` | 1 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `modmarksman` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modmercantile` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modpersonality` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modshortblade` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modspear` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `modwaterlevel` | 1 | instrukcja | Zweryfikowane | — | zgodne: water/water_ship/water_ext | woda komórki | — |
| `payfine` | 1 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `pcclearexpelled` | 1 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `pcexpelled` | 1 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc2 | — | — |
| `pcjoinfaction` | 1 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `placeitemcell` | 1 | instrukcja | Zaimplementowane | — | — | świat (komórki) | nieporównane z OpenMW |
| `playsoundvp` | 1 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `raiserank` | 1 | instrukcja | Zweryfikowane | — | zgodne: rank | frakcje | — |
| `rotateworld` | 1 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `scriptrunning` | 1 | funkcja (wartość) | Zweryfikowane | — | zgodne: misc3 | — | — |
| `setalchemy` | 1 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `setalteration` | 1 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `setarmorer` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setaxe` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setbluntweapon` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setconjuration` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setdestruction` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setenchant` | 1 | instrukcja | Zweryfikowane | — | zgodne: misc2 | — | — |
| `setendurance` | 1 | instrukcja | Zweryfikowane | — | zgodne: stats_player | — | — |
| `setheavyarmor` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setillusion` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setmediumarmor` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setmysticism` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `setspear` | 1 | instrukcja | Zaimplementowane | — | — | — | ta sama ścieżka kodu (rodzina statystyk) co funkcje zweryfikowane porównaniem |
| `streammusic` | 1 | instrukcja | Zaimplementowane | — | — | — | nieporównane z OpenMW |
| `turnmoonred` | 1 | instrukcja | Brakujące | — | — | — | brak księżyców na niebie (Masser/Secunda nie są renderowane) – instrukcja zgłaszana jako brakująca |
| `turnmoonwhite` | 1 | instrukcja | Brakujące | — | — | — | jak TurnMoonRed |

Podsumowanie: Zweryfikowane 153, Częściowo zgodne 23, Zaimplementowane 73, Brakujące 2, Nie funkcja 1 (razem 252).

## 5. Magia (etap 2026-11-17: pełna mechanika efektów)

Wszystkie 143 efekty OpenMW 0.51 (Morrowind, Tribunal, Bloodmoon; dane zawierają 141 rekordów MGEF, 139 efektów
występuje w SPEL/ENCH/ALCH/INGR). Jedna implementacja dla wszystkich źródeł (czary, zdolności rasy i znaku,
przedmioty zaklęte stałe/przy użyciu/przy uderzeniu, mikstury, składniki, skrypty): `mw_magic.gd`
(inflict → applyProtections, _apply_effect → applyMagicEffect, _actor_effect → applyActorMagicEffect,
_remove_effect → removeMagicEffect, _should_remove → shouldRemoveEffect), skutki ruchu w `mw_actor.gd`
(apply_movement co klatkę), walka w `mw_combat.gd`, AI w `mw_ai.gd`/`mw_dialogue.gd`.

**Stan przed etapem:** 0 zweryfikowanych porównaniem, 79 zaimplementowanych (testy syntetyczne), 14 częściowo,
50 brakujących. **Po etapie:** 70 zweryfikowanych porównaniem z OpenMW (36 przypadków porównawczych), 65
zaimplementowanych zgodnie z kodem OpenMW, 8 częściowo zgodnych, 0 brakujących.

Dodatkowo w tej części: trwałe czary (choroby, zaraza, klątwy) nakładają efekty jednorazowe na pule (Wyssanie i
Uszkodzenie atrybutów/umiejętności) i Korpus pogarsza się co 24 h; wielkości zdolności losowane raz i zapisywane;
podstawa kondycji/magii przeliczana po zmianie atrybutów (CreatureStats::setAttribute / recalculateMagicka – także
stworzenia i NPC bez autoobliczania); przedmioty przywołane zakładane jak ActionEquip (bez zdejmowania broni
dwuręcznej), także NPC; zmiana postawy za przestępstwa (reportCrime). Część 3: znaczniki Wykrywania na mapie
lokalnej, ExtraSpell, zmienne czasu świata zsynchronizowane z czasem gry (GameHour, DaysPassed, Day/Month/Year –
DateTimeManager; wcześniej zmienne skryptów nie zmieniały czasu i nie rosły o północy), mikstury przez Equip.

Porównania: `tools/openmw-xvfb/magic_run.sh tools/openmw-xvfb/magic_cases/*.json` – czary nakładane w obu
silnikach jak `ActiveSpells:add` (Lua po stronie OpenMW), migawka pełnej mapy efektów („fx”), statystyk, AI,
ekwipunku i położeń (próbki w czasie).

| # | Efekt | Przed etapem | Po etapie | Działanie | Test / porównanie z OpenMW |
|---|---|---|---|---|---|
| 0 | WaterBreathing | Brakujące | Zweryfikowane | tonięcie (fHoldBreathTime 20 s, fSuffocationDamage 3/s) wyłączone; gracz i NPC | fx_drown/fx_breathe: −12 zdrowia po 24 s / 0 – jak OpenMW |
| 1 | SwiftSwim | Częściowo zgodne | Zaimplementowane | prędkość pływania gracza i NPC × (1 + 0,01 × wielkość) | mapa efektów zgodna (fx_player_map) |
| 2 | WaterWalking | Brakujące | Zweryfikowane | kolizja z powierzchnią wody, przeniesienie na powierzchnię, castable (za głęboko), usuwane po teleporcie | fx_waterwalk: z = 0 w obu silnikach |
| 3 | Shield | Częściowo zgodne | Zaimplementowane | pancerz +wielkość (Npc::getArmorRating), GetArmorBonus | fx_player_map |
| 4 | FireShield | Częściowo zgodne | Zweryfikowane | odporność na ogień + rani atakującego wręcz (applyElementalShields: 0,1 × wielkość × (1 − 0,01 × x), przed blokiem) | fx_shield_attack: 2 pkt na trafienie w obu (liczba trafień zależy od AI walki) |
| 5 | LightningShield | Częściowo zgodne | Zaimplementowane | odporność na żywioł + rani atakującego wręcz (applyElementalShields, przed blokiem) | mapa zgodna; obrażenia atakującego – test syntetyczny brak porównania |
| 6 | FrostShield | Częściowo zgodne | Zaimplementowane | odporność na żywioł + rani atakującego wręcz (applyElementalShields, przed blokiem) | mapa zgodna; obrażenia atakującego – test syntetyczny brak porównania |
| 7 | Burden | Częściowo zgodne | Zaimplementowane | obciążenie gracza i NPC (prędkość, lot, skok, przeciążenie) | fx_player_map, fx_npc_stats (Ciężar: rzut odporności) |
| 8 | Feather | Częściowo zgodne | Zaimplementowane | obciążenie gracza i NPC (prędkość, lot, skok, przeciążenie) | fx_player_map, fx_npc_stats (Ciężar: rzut odporności) |
| 9 | Jump | Zaimplementowane | Zaimplementowane | wysokość skoku (+64 j. × wielkość) | mapa zgodna; wzór getJump |
| 10 | Levitate | Brakujące | Zweryfikowane | lot bez grawitacji, prędkość fMin/MaxFlySpeed, DisableLevitation usuwa (sLevitateDisabled) | fx_levitate: utrzymanie wysokości 900 j. |
| 11 | SlowFall | Brakujące | Częściowo zgodne | inercja w dół × (1 − 0,005 × wielkość) na krok fizyki, brak obrażeń od upadku | fx_slowfall: bez obrażeń w obu; prędkość graniczna Godot 59 j./s = wzór przy 60 Hz, OpenMW w Xvfb ~70 j./s (2–5 kl./s) |
| 12 | Lock | Zaimplementowane | Zaimplementowane | zamki drzwi/pojemników dotykiem (Open: unlockAttempted) | test syntetyczny |
| 13 | Open | Zaimplementowane | Zaimplementowane | zamki drzwi/pojemników dotykiem (Open: unlockAttempted) | test syntetyczny |
| 14 | FireDamage | Zaimplementowane | Zaimplementowane | obrażenia zdrowia co sekundę, śmierć, odporności/słabości | test_magic |
| 15 | ShockDamage | Zaimplementowane | Zaimplementowane | obrażenia zdrowia co sekundę, śmierć, odporności/słabości | test_magic |
| 16 | FrostDamage | Zaimplementowane | Zaimplementowane | obrażenia zdrowia co sekundę, śmierć, odporności/słabości | test_magic |
| 17 | DrainAttribute | Zaimplementowane | Zweryfikowane | ubytki atrybutów, przywracanie po wygaśnięciu i wyleczeniu | fx_corprus, fx_disease_cure: wartości stałe zgodne (bez rzutu odporności) |
| 18 | DrainHealth | Zaimplementowane | Zweryfikowane | wyssanie zdrowia/kondycji | fx_npc_dynamic (różnica 0,6 zdrowia – czas próbki) |
| 19 | DrainMagicka | Zaimplementowane | Zweryfikowane | wyssanie magii | fx_potions_restore (rzut odporności) |
| 20 | DrainFatigue | Zaimplementowane | Zweryfikowane | wyssanie zdrowia/kondycji | fx_npc_dynamic (różnica 0,6 zdrowia – czas próbki) |
| 21 | DrainSkill | Zaimplementowane | Częściowo zgodne | ubytki atrybutów/umiejętności, przywracanie po wygaśnięciu (Drain) | fx_player_damage/fx_npc_stats: wartości zgodne do rzutu odporności (losowe) |
| 22 | DamageAttribute | Zaimplementowane | Częściowo zgodne | ubytki atrybutów/umiejętności, przywracanie po wygaśnięciu (Drain) | fx_player_damage/fx_npc_stats: wartości zgodne do rzutu odporności (losowe) |
| 23 | DamageHealth | Zaimplementowane | Zweryfikowane | obrażenia zdrowia co sekundę, śmierć | fx_player_damage |
| 24 | DamageMagicka | Zaimplementowane | Zaimplementowane | zdrowie/magia/kondycja, Drain poniżej zera | test_magic |
| 25 | DamageFatigue | Zaimplementowane | Zaimplementowane | zdrowie/magia/kondycja, Drain poniżej zera | test_magic |
| 26 | DamageSkill | Zaimplementowane | Częściowo zgodne | ubytki atrybutów/umiejętności, przywracanie po wygaśnięciu (Drain) | fx_player_damage/fx_npc_stats: wartości zgodne do rzutu odporności (losowe) |
| 27 | Poison | Zaimplementowane | Zweryfikowane | trucizna, paraliż i ich leczenie | fx_cures: 0 różnic |
| 28 | WeaknessToFire | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 29 | WeaknessToFrost | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 30 | WeaknessToShock | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 31 | WeaknessToMagicka | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 32 | WeaknessToCommonDisease | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 33 | WeaknessToBlightDisease | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 34 | WeaknessToCorprusDisease | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 35 | WeaknessToPoison | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 36 | WeaknessToNormalWeapons | Zaimplementowane | Zaimplementowane | słabości w odpornościach i obrażeniach | wielkość w mapie zgodna (fx_player_damage: Fire, Poison – rzut odporności) |
| 37 | DisintegrateWeapon | Zaimplementowane | Zaimplementowane | zużycie broni/pancerza wg slotów (kolejność OpenMW) | test_magic |
| 38 | DisintegrateArmor | Zaimplementowane | Zaimplementowane | zużycie broni/pancerza wg slotów (kolejność OpenMW) | test_magic |
| 39 | Invisibility | Częściowo zgodne | Zweryfikowane | wykrywanie, trafienie; zdejmowana przy ataku, czarze, przedmiocie, wypiciu, alchemii; od pierwszej klatki; czar z tej samej klatki (kolejka ActiveSpells) nie jest zdejmowany | fx_invis_break, fx_invis_break2: 0 różnic |
| 40 | Chameleon | Zaimplementowane | Zaimplementowane | wykrywanie/obrona/atak (combat.cpp) | wielkość w mapie zgodna (fx_player_map) |
| 41 | Light | Brakujące | Częściowo zgodne | światło przy aktorze (promień 22 j. × wielkość × 3) | bez porównania obrazu; tylko światło otoczenia w OpenMW – tu OmniLight |
| 42 | Sanctuary | Zaimplementowane | Zaimplementowane | wykrywanie/obrona/atak (combat.cpp) | wielkość w mapie zgodna (fx_player_map) |
| 43 | NightEye | Brakujące | Częściowo zgodne | światło otoczenia + 0,7 × min(1, wielkość/100) dla gracza | bez porównania obrazu |
| 44 | Charm | Brakujące | Zaimplementowane | postawa NPC + wielkość (getDerivedDisposition) | fx_npc_ai: Urok zgodny; postawa różna przez grzywnę (patrz różnice) |
| 45 | Paralyze | Zaimplementowane | Zweryfikowane | bez ruchu i ataku (sparaliżowany NPC nie zadaje ciosów); Leczenie paraliżu | fx_paralyze_combat (gracz bez strat), fx_cures |
| 46 | Silence | Zaimplementowane | Zaimplementowane | blokada czarów / kara do szansy; Dźwięk: pętla „magic sound” gracza | test_magic |
| 47 | Blind | Zaimplementowane | Zaimplementowane | wykrywanie/obrona/atak (combat.cpp) | wielkość w mapie zgodna (fx_player_map) |
| 48 | Sound | Zaimplementowane | Zaimplementowane | blokada czarów / kara do szansy; Dźwięk: pętla „magic sound” gracza | test_magic |
| 49 | CalmHumanoid | Brakujące | Zweryfikowane | Fight − wielkość i stopCombat | fx_npc_ai, fx_calm_combat: GetTarget player 0 po Uspokojeniu w obu |
| 50 | CalmCreature | Brakujące | Zweryfikowane | modyfikator Fight/Flee stworzeń | fx_creature_ai: ustawienia AI zgodne |
| 51 | FrenzyHumanoid | Brakujące | Zweryfikowane | modyfikator Fight/Flee | fx_npc_command: 0 różnic |
| 52 | FrenzyCreature | Brakujące | Zaimplementowane | modyfikator Fight/Flee (modifyAiSetting), wariant ludzi/stworzeń | fx_npc_ai: Szał stworzeń na NPC – nieprawidłowy w obu |
| 53 | DemoralizeHumanoid | Brakujące | Zweryfikowane | modyfikator Fight/Flee (modifyAiSetting), Uspokojenie zatrzymuje walkę, wariant ludzi/stworzeń | fx_npc_ai: Fight 0 / Flee 34 jak OpenMW |
| 54 | DemoralizeCreature | Brakujące | Zweryfikowane | modyfikator Fight/Flee stworzeń | fx_creature_ai: ustawienia AI zgodne |
| 55 | RallyHumanoid | Brakujące | Zweryfikowane | modyfikator Fight/Flee | fx_npc_command: 0 różnic |
| 56 | RallyCreature | Brakujące | Zweryfikowane | modyfikator Fight/Flee stworzeń | fx_creature_ai: ustawienia AI zgodne |
| 57 | Dispel | Zaimplementowane | Zaimplementowane | usuwanie czarów z szansą wielkości | test_magic |
| 58 | Soultrap | Zaimplementowane | Zaimplementowane | dusza do kamienia (soulTrap) | test_magic |
| 59 | Telekinesis | Brakujące | Zaimplementowane | zasięg aktywacji + wielkość × 21,33 j., bez aktorów i otwartych drzwi teleportujących | bez porównania |
| 60 | Mark | Częściowo zgodne | Zweryfikowane | Znak z obrotem, Przywołanie, DisableTeleporting, zapis | fx_markrecall: 0 różnic |
| 61 | Recall | Częściowo zgodne | Zweryfikowane | Znak z obrotem, Przywołanie, DisableTeleporting, zapis | fx_markrecall: 0 różnic |
| 62 | DivineIntervention | Brakujące | Zweryfikowane | teleportToClosestMarker (siatka komórek, wnętrza przez drzwi) | fx_divine → Pelagiad, fx_almsivi → Vivec (x, y zgodne) |
| 63 | AlmsiviIntervention | Brakujące | Zweryfikowane | teleportToClosestMarker (siatka komórek, wnętrza przez drzwi) | fx_divine → Pelagiad, fx_almsivi → Vivec (x, y zgodne) |
| 64 | DetectAnimal | Brakujące | Zaimplementowane | znaczniki na mapie lokalnej (listDetectedReferences: promień wielkość × 22 j., pojemniki i aktorzy z przedmiotem) | mapa efektów zgodna (fx_potions); znaczniki – bez porównania obrazu |
| 65 | DetectEnchantment | Brakujące | Zaimplementowane | znaczniki na mapie lokalnej (listDetectedReferences: promień wielkość × 22 j., pojemniki i aktorzy z przedmiotem) | mapa efektów zgodna (fx_potions); znaczniki – bez porównania obrazu |
| 66 | DetectKey | Brakujące | Zaimplementowane | znaczniki na mapie lokalnej (listDetectedReferences: promień wielkość × 22 j., pojemniki i aktorzy z przedmiotem) | mapa efektów zgodna (fx_potions); znaczniki – bez porównania obrazu |
| 67 | SpellAbsorption | Częściowo zgodne | Zaimplementowane | dla każdego efektu osobno: rzut dla każdego aktywnego efektu, absorbSpell (+koszt) | rzuty losowe – porównanie rozkładu brak |
| 68 | Reflect | Częściowo zgodne | Zaimplementowane | dla każdego efektu osobno: rzut dla każdego aktywnego efektu, absorbSpell (+koszt) | rzuty losowe – porównanie rozkładu brak |
| 69 | CureCommonDisease | Zaimplementowane | Zweryfikowane | usuwanie chorób i zarazy z listy czarów (także NPC), cofnięcie Wyssania | fx_disease_cure: GetSpell/GetCommonDisease/GetBlightDisease 0, atrybuty wracają |
| 70 | CureBlightDisease | Zaimplementowane | Zweryfikowane | usuwanie chorób i zarazy z listy czarów (także NPC), cofnięcie Wyssania | fx_disease_cure: GetSpell/GetCommonDisease/GetBlightDisease 0, atrybuty wracają |
| 71 | CureCorprusDisease | Brakujące | Zaimplementowane | usuwa efekt Korpus | bez porównania |
| 72 | CurePoison | Zaimplementowane | Zweryfikowane | trucizna, paraliż i ich leczenie | fx_cures: 0 różnic |
| 73 | CureParalyzation | Zaimplementowane | Zweryfikowane | trucizna, paraliż i ich leczenie | fx_cures: 0 różnic |
| 74 | RestoreAttribute | Zaimplementowane | Zweryfikowane | przywracanie | fx_player_map (Restore Health), fx_player_damage (Restore Attribute) |
| 75 | RestoreHealth | Zaimplementowane | Zweryfikowane | przywracanie | fx_player_map (Restore Health), fx_player_damage (Restore Attribute) |
| 76 | RestoreMagicka | Zaimplementowane | Zweryfikowane | przywracanie magii/kondycji | fx_potions_restore: pełne przywrócenie w obu |
| 77 | RestoreFatigue | Zaimplementowane | Zweryfikowane | przywracanie magii/kondycji | fx_potions_restore: pełne przywrócenie w obu |
| 78 | RestoreSkill | Zaimplementowane | Zaimplementowane | przywracanie | test_magic |
| 79 | FortifyAttribute | Zaimplementowane | Zweryfikowane | wzmocnienia (czasowe zdrowie/magia/kondycja – tylko bieżąca, w mapie efektów) | fx_player_map, fx_npc_stats |
| 80 | FortifyHealth | Zaimplementowane | Zweryfikowane | wzmocnienia (czasowe zdrowie/magia/kondycja – tylko bieżąca, w mapie efektów) | fx_player_map, fx_npc_stats |
| 81 | FortifyMagicka | Zaimplementowane | Zaimplementowane | wzmocnienie magii (bieżąca) | test_magic |
| 82 | FortifyFatigue | Zaimplementowane | Zweryfikowane | wzmocnienia (czasowe zdrowie/magia/kondycja – tylko bieżąca, w mapie efektów) | fx_player_map, fx_npc_stats |
| 83 | FortifySkill | Zaimplementowane | Zweryfikowane | wzmocnienia (czasowe zdrowie/magia/kondycja – tylko bieżąca, w mapie efektów) | fx_player_map, fx_npc_stats |
| 84 | FortifyMaximumMagicka | Zaimplementowane | Częściowo zgodne | maks. magia (recalculateMagicka) | OpenMW przelicza stan startowy przy wygaśnięciu – różnica stanu bazowego |
| 85 | AbsorbAttribute | Zaimplementowane | Zaimplementowane | pochłanianie do rzucającego | test_magic |
| 86 | AbsorbHealth | Zaimplementowane | Zaimplementowane | pochłanianie do rzucającego | test_magic |
| 87 | AbsorbMagicka | Zaimplementowane | Zaimplementowane | pochłanianie do rzucającego | test_magic |
| 88 | AbsorbFatigue | Zaimplementowane | Zweryfikowane | pochłanianie kondycji do rzucającego | fx_absorb: ~20/s w obu (różnica – długość okna czasu) |
| 89 | AbsorbSkill | Zaimplementowane | Zaimplementowane | pochłanianie do rzucającego | test_magic |
| 90 | ResistFire | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 91 | ResistFrost | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 92 | ResistShock | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 93 | ResistMagicka | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 94 | ResistCommonDisease | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 95 | ResistBlightDisease | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 96 | ResistCorprusDisease | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 97 | ResistPoison | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 98 | ResistNormalWeapons | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 99 | ResistParalysis | Zaimplementowane | Zaimplementowane | odporności (getEffectResistance – zawsze, także bez rzucającego) | wielkość w mapie zgodna (fx_player_map) |
| 100 | RemoveCurse | Zaimplementowane | Zaimplementowane | usuwanie chorób/trucizn/paraliżu/klątw (także NPC) | test_magic |
| 101 | TurnUndead | Brakujące | Zweryfikowane | Flee + wielkość dla nieumarłych (Creature::Undead) | fx_turnundead: ucieczka przywołanego szkieletu zgodna |
| 102 | SummonScamp | Brakujące | Zweryfikowane | pełny aktor (statystyki, ekwipunek, AI follow, pomoc w walce, koniec, śmierć, przez drzwi z graczem, zapis) | fx_summon (0 różnic), fx_summon_end (znika po 10 s) |
| 103 | SummonClannfear | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 104 | SummonDaedroth | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 105 | SummonDremora | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 106 | SummonAncestralGhost | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 107 | SummonSkeletalMinion | Brakujące | Zweryfikowane | pełny aktor (statystyki, ekwipunek, AI follow, pomoc w walce, koniec, śmierć, przez drzwi z graczem, zapis) | fx_summon (0 różnic), fx_summon_end (znika po 10 s) |
| 108 | SummonBonewalker | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 109 | SummonGreaterBonewalker | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 110 | SummonBonelord | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 111 | SummonWingedTwilight | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 112 | SummonHunger | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 113 | SummonGoldenSaint | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 114 | SummonFlameAtronach | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 115 | SummonFrostAtronach | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 116 | SummonStormAtronach | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 117 | FortifyAttack | Zaimplementowane | Zaimplementowane | wykrywanie/obrona/atak (combat.cpp) | wielkość w mapie zgodna (fx_player_map) |
| 118 | CommandCreature | Brakujące | Zaimplementowane | AiFollow (rozkaz) dla stworzeń | fx_creature_ai: wielkość zgodna; pakiet – niejednoznaczny obiekt „mudcrab” w skrypcie |
| 119 | CommandHumanoid | Brakujące | Zweryfikowane | AiFollow (rozkaz), gdy wielkość ≥ poziom | fx_npc_command: GetCurrentAIPackage = 3 w obu |
| 120 | BoundDagger | Zaimplementowane | Zweryfikowane | przedmiot w ekwipunku na czas efektu | fx_bound: ekwipunek zgodny |
| 121 | BoundLongsword | Zaimplementowane | Zweryfikowane | przedmiot przywołany: ActionEquip bez zdejmowania broni dwuręcznej/tarczy | fx_bound_weapons: 0 różnic |
| 122 | BoundMace | Zaimplementowane | Zweryfikowane | przedmiot przywołany: ActionEquip bez zdejmowania broni dwuręcznej/tarczy | fx_bound_weapons: 0 różnic |
| 123 | BoundBattleAxe | Zaimplementowane | Zweryfikowane | przedmiot przywołany: ActionEquip bez zdejmowania broni dwuręcznej/tarczy | fx_bound_weapons: 0 różnic |
| 124 | BoundSpear | Zaimplementowane | Zweryfikowane | przedmiot przywołany: ActionEquip bez zdejmowania broni dwuręcznej/tarczy | fx_bound_weapons: 0 różnic |
| 125 | BoundLongbow | Zaimplementowane | Zweryfikowane | przedmiot przywołany: ActionEquip bez zdejmowania broni dwuręcznej/tarczy | fx_bound_weapons: 0 różnic |
| 126 | ExtraSpell | Brakujące | Zaimplementowane | NPC zdejmuje wszystko poza bronią, amunicją, spodniami i pochodnią; po wygaśnięciu autoEquip | brak czaru z tym efektem w danych gry – bez porównania |
| 127 | BoundCuirass | Zaimplementowane | Zweryfikowane | przedmiot w ekwipunku na czas efektu | fx_bound: ekwipunek zgodny |
| 128 | BoundHelm | Zaimplementowane | Zweryfikowane | przedmiot w ekwipunku na czas efektu | fx_bound: ekwipunek zgodny |
| 129 | BoundBoots | Zaimplementowane | Zweryfikowane | przedmiot w ekwipunku na czas efektu | fx_bound: ekwipunek zgodny |
| 130 | BoundShield | Zaimplementowane | Zweryfikowane | przedmiot przywołany: ActionEquip bez zdejmowania broni dwuręcznej/tarczy | fx_bound_weapons: 0 różnic |
| 131 | BoundGloves | Zaimplementowane | Zweryfikowane | przedmiot w ekwipunku na czas efektu | fx_bound: ekwipunek zgodny |
| 132 | Corprus | Częściowo zgodne | Zweryfikowane | choroba jako trwały czar: Wyssanie/Wzmocnienie przy dodaniu, pogarszanie co 24 h znacznika czasu (DaysPassed) | fx_corprus: atrybuty po 2 dniach zgodne (dwa pogorszenia) |
| 133 | Vampirism | Częściowo zgodne | Częściowo zgodne | dialogi, Obrażenia od słońca i Słabość na ogień ze zdolności, brak przestępstwa przy napaści na wampira (canCommitCrimeAgainst), wielkość zostaje po śmierci; wygląd głowy wampira – brak (obraz) | fx_sun, fx_vampire_crime: grzywna 0 w obu |
| 134 | SummonCenturionSphere | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 135 | SunDamage | Brakujące | Zweryfikowane | zdrowie na zewnątrz × widoczność słońca | fx_sun: ~5/s w obu (Wampir: obrażenia od słońca) |
| 136 | StuntedMagicka | Brakujące | Zaimplementowane | bez odnowy magii przy odpoczynku (pozostały czas), getHoursToRest | bez porównania |
| 137 | SummonFabricant | Brakujące | Zaimplementowane | jak inne przywołania (Fabrykant bez czaru w danych; Creature04/05 – GMST bez stworzenia) | bez porównania |
| 138 | SummonWolf | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 139 | SummonBear | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 140 | SummonBonewolf | Brakujące | Zweryfikowane | pełny aktor z GMST (statystyki, odporności, zdolności, AI follow) | fx_summon_all: zgodne; różnice: OpenMW AI rzuca czary wzmacniające (zużycie magii), losowy ekwipunek z list, losowa wielkość regeneracji |
| 141 | SummonCreature04 | Brakujące | Zaimplementowane | jak inne przywołania (Fabrykant bez czaru w danych; Creature04/05 – GMST bez stworzenia) | bez porównania |
| 142 | SummonCreature05 | Brakujące | Zaimplementowane | jak inne przywołania (Fabrykant bez czaru w danych; Creature04/05 – GMST bez stworzenia) | bez porównania |

### Różnice i zależności (magia)

- **Rzuty odporności** (getEffectResistance) są losowe w obu silnikach – częściowe odparcie (np. 19 zamiast 20)
  wynika z rzutu, nie ze wzoru (wzór sprawdzony na wypisanych wartościach). Brak porównania rozkładów.
- **Nieprawidłowe efekty** (Odpędzenie nieumarłych na NPC, Szał stworzeń na NPC): OpenMW zostawia ich wielkość
  w mapie efektów do końca (Flag_Invalid bez Flag_Applied); w Godocie znikają – mechanika bez skutku w obu.
- **Szkodliwy czar na NPC** (onHit → napaść): grzywna 40 i spadek postawy ofiary (fDispAttacking) – zgodne po
  uzupełnieniu reportCrime o zmiany postawy (trwałe i modyfikator przestępstwa do spłaty) oraz getFightDispositionBias.
- **Przywołania:** OpenMW AI rzuca czary wzmacniające (np. Daedroth – Bariera) – w Godocie brak (etap AI walki);
  ekwipunek z list poziomowanych i wielkości zdolności (np. regeneracja) są losowane w obu silnikach.
- **Pogarszanie Korpusu** liczy się od znacznika czasu (DaysPassed), nie od kalendarza: `set GameHour to GameHour + 25`
  przesuwa tylko kalendarz (DateTimeManager::setHour) – w obu silnikach bez pogorszenia; `DaysPassed + 2` – dwa.
- **Powolne opadanie:** w Xvfb OpenMW działa z 2–5 kl./s i większym krokiem fizyki – prędkość graniczna różni
  się od wzoru przy 60 Hz; brak obrażeń od upadku zgodny.
- **SetPos/Position gracza w OpenMW stawia go na podłożu**, gdy nie lewituje (Godot nie) – różnica MWScript,
  poza magią; testy używają teleportu Lua bez stawiania na podłożu.
- **OpenMW zawiesza się w Xvfb**, gdy lewitacja kończy się wysoko (RemoveSpellEffects albo ActiveSpells:remove)
  – sprawdzone 3 razy; przypadek opadania zbudowany bez tego.
- Stan startowy gracza OpenMW (--skip-menu) ma nieprzeliczone magię/kondycję (przeliczane przy zmianie
  atrybutu) – różnice „(zmiana)” magii/kondycji w fx_player_map/fx_bound/fx_player_damage.
- **Zależności:** Wampiryzm (reakcje NPC, sen, wygląd), znaczniki Wykrywania jako proste kwadraty (bez ikon
  detect_*_icon), przenoszenie stałych referencji NPC między komórkami
  (towarzysze przez drzwi – działa dla przywołań i obiektów dynamicznych), AiCast (Cast/ExplodeSpell NPC działa
  natychmiast, bez animacji), światło/widzenie w ciemności bez porównania obrazu, Boska/Almsivi do komórek spoza
  konwersji (x, y zgodne; teren i nazwa komórki – zależność od konwersji).

## 6. Świat i obraz

| Element | Status | Uwagi | Prio |
|---|---|---|---|
| Widok pierwszoosobowy z rękami i bronią, animacje ataku i rzucania | Brakujące | dziś sama kamera | P1 |
| Widok trzecioosobowy (Tab) | Brakujące | | P2 |
| Efekty wizualne czarów | Brakujące | | P1 |
| Opady (deszcz, śnieg, popiół, zaraza), błyskawice | Częściowo zgodne | dźwięki są, cząsteczek brak | P2 |
| Księżyce Masser i Secunda (fazy) | Brakujące | | P2 |
| Kręgi i plusk na wodzie, ślady | Brakujące | | P3 |
| Wierność oświetlenia (Godot liniowo + tonowanie, OpenMW w gamma) | Częściowo zgodne | porównać zrzutami | P1 |
| Daleki teren i obiekty na horyzoncie | Brakujące | | P3 |
| Odbicia wody (poziomy 0–5) | Częściowo zgodne | tylko niebo | P3 |

## 7. AI, fizyka i mechanika świata

| Element | Status | Uwagi / test |
|---|---|---|
| Szukanie drogi: kolejność navmesh → pathgrid → prosto (PathFinder::buildPath) | Zweryfikowane | `mw_navmesh.gd` (parametry DetourNavigator: 1/34 skali, cell 0,2, wspinaczka 34 j., nachylenie 46°); sonda nowej gry, test_ai |
| buildPathByPathgridImpl: „prosto do celu” tylko gdy cel bliżej niż pierwszy/ostatni punkt, pomijanie pierwszego punktu z warunkiem widoczności, cel dopisany tylko dla osiągalnego punktu | Zweryfikowane | test_ai_mechanics (pathgrid ×4) |
| AiPackage::pathTo: cel osiągnięty w 3D (32 j.), przebudowa drogi, punkty zdejmowane w poziomie, RemoveLoops, checkPathCompleted | Zweryfikowane | sonda (strażnik pod pokładem), test_ai |
| Każdy pakiet ma własny PathFinder – stan drogi nie przechodzi na następny pakiet | Zweryfikowane | **przyczyna fałszywego „GetAIPackageDone” eskorty**; test_ai „nie kończy się od razu” |
| ObstacleCheck (utknięcie 1,5 s / 0,5 j., unik 1 s, 7 kierunków), predictAndAvoidCollisions | Zweryfikowane | test_ai (podróżny omija stojącego NPC) |
| Stepper: wejście na stopień ≤ 34 j. (3 próby jak sDoExtraStairHacks, zejście tylko na ≤ 46°), prostopadłościan aktora | Zweryfikowane | **naprawione:** gracz zatrzymywał się na progu drzwi urzędu (20 j.); test_ai_mechanics (20 j. pokonany, 48 j. nie) |
| Drzwi obrotowe: World::activateDoor/rotateDoor/processDoors – 90°/s, otwórz/zamknij/odwróć w trakcie, zatrzymanie na aktorze w kierunku obrotu, AiAvoidDoor, zapis i wznowienie ruchu | Zweryfikowane | **nowa mechanika**; test_ai_mechanics (drzwi ×10), sonda (drzwi korytarza urzędu) |
| AiPackage::openDoors – NPC otwiera drzwi na drodze (poza AiWander), z kluczem; evadeObstacles: najpierw drzwi | Zaimplementowane | brak sceny testowej z NPC przechodzącym przez drzwi na prawdziwych danych |
| AiWander (bezczynność, punkty w promieniu, spacer) | Zaimplementowane | sonda Seyda Neen 60 s: 13/15 aktorów w ruchu, wszyscy w promieniu wędrówki, nikt nie spadł pod teren |
| Aresztowanie przez strażnika, grzywna, więzienie | Nieprzetestowane | do sondy | 
| Czas świata a zmienne skryptów (GameHour, DaysPassed, Day/Month/Year – DateTimeManager) | Zweryfikowane | fx_corprus, fx_sun: GameHour i DaysPassed jak OpenMW; kalendarz o północy |
| Zmiana postawy świadków i ofiary za przestępstwo (reportCrime: trwała / modyfikator do spłaty, getFightDispositionBias) | Zweryfikowane | napaść czarem: fx_npc_ai (grzywna 40, postawa −10 jak OpenMW) |
| Wilkołactwo (Bloodmoon) | Częściowo zgodne | od etapu MWScript: statystyki z GMST, szata, świadkowie i grzywna, brak rozmów/ekwipunku/snu, agresja NPC – porównane z OpenMW; brak modelu, nakładki ekranu i pazurów (punkt 4a) |
| Choroby, wampiryzm | Częściowo zgodne | leczenie chorób NPC, Obrażenia od słońca; Korpus bez pogarszania (punkt 5) |

### Odchylenia od OpenMW (świadome, udokumentowane)

* Siatka nawigacji: OpenMW buduje kafelki navmesh na żądanie dla każdego rozmiaru aktora; my – jedną siatkę na
  komórkę (w tle) dla aktora o wymiarach NPC. Stworzenia dużo większe/mniejsze używają tej samej siatki.
* Brak flagi „navmesh + pathgrid” (OpenMW łączy je dla części aktorów); pathgrid tylko, gdy siatki nie ma.
* Ścieżka częściowa (`partial`) rozpoznawana po odległości końca drogi od celu (32 j. / wzrost aktora), w OpenMW
  zwraca ją Detour.
* Skrót prosto do celu dla latających/pływających (canActorMoveByZAxis) – niezaimplementowany.
* Drzwi: kierunek „na aktora” liczony z kąta skrzydła (środek modelu) zamiast punktu kontaktu i normalnej
  Bullet; dźwięk drzwi bez przesunięcia początku (setSoundOffset).
* NPC otwierający drzwi uruchamia domyślną akcję drzwi, bez lokalnego `OnActivate` skryptu drzwi.

## Kolejność dalszych prac (roadmapa użytkownika)

1. ~~Start gry~~ – wykonane 2026-11-17 (punkt 1); pozostało: autozapis, czas animacji śmierci.
2. ~~Pięć okien kreatora postaci jak w OpenMW~~ – wykonane 2026-11-17 (punkt 2a); pozostało: podpowiedzi z ikonami, tekstury pasków przewijania, pad.
3. ~~MWScript – stałe zera i nieobsłużone~~ – wykonane 2026-11-17 (punkt 4a); pozostało: zależności z punktu 4a
   (animacje śmierci/powalenia, sen przerywany stworzeniami, okno więzienia, wygląd wilkołaka, Lewitacja, księżyce).
4. Efekty magii z punktu 5.
5. Interfejs z punktu 3.
6. Grafika: animacje, widok 1-/3-osobowy, pogoda, oświetlenie.
7. Tribunal/Bloodmoon (wilkołactwo i pozostałe).

Każdy krok kończy się porównaniem z OpenMW (sondy MCP, gdy będzie ekran X) i aktualizacją tej listy.
