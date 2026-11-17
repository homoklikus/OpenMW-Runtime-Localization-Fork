# Inwentaryzacja zgodności OpenMWGodot z OpenMW

Stan na 2026-11-17 (po naprawie AI strażnika i sondzie nowej gry). Cel: wierne odtworzenie OpenMW, zanim
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
przez MCP-openMW (`openmw_ai_compare_start`) nie jest dziś możliwe**: OpenMW na VM kończy się błędem
„x11 not available” (brak ekranu X). Do czasu udostępnienia ekranu porównujemy z kodem OpenMW i ze skryptami
z danych, które OpenMW wykonuje tak samo.

## 1. Start gry i menu

| Element | Status | Uwagi | Prio |
|---|---|---|---|
| Filmy: logo Bethesdy, logo Morrowinda, wstęp po „Nowej grze” | Brakujące | pliki `Video/*.bik` gracza; ffmpeg dekoduje Bink → konwersja lokalna do Ogg Theora – sprawdzone na VM | P1 |
| Menu główne (Nowa gra, Wczytaj, Opcje, Zasługi, Wyjdź), tło `mw_menu.bik`, muzyka tytułowa | Brakujące | gra startuje od razu w świecie z launchera | P1 |
| Ekran ładowania (losowy obraz z `Splash/`, pasek postępu) | Brakujące | | P2 |
| Okno zapisu/wczytywania (lista zapisów, nazwa, postać, miejsce, zrzut) | Brakujące | jest tylko szybki zapis/wczytanie (F5/F9) | P1 |
| Menu pauzy (Esc) | Częściowo zgodne | prosty, bez zapisu/wczytania z listą | P2 |
| Ekran śmierci | Częściowo zgodne | prosty; OpenMW: wczytanie ostatniego zapisu albo menu | P2 |
| `PlayBink`, `FadeIn`/`FadeOut`/`FadeTo`, `WakeUpPC` w skryptach | Brakujące | patrz punkt 4 – mapa zależności | P1 |

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
| Okna kreatora jak w OpenMW: imię, rasa (podgląd 3D, płeć, twarz, włosy), klasa (wybór/pytania/własna), znak, przegląd z „Wstecz” | Częściowo zgodne | u nas jeden wspólny formularz – etap roadmapy 2 | P1 |
| Wstęp wideo i `FadeIn` po starcie | Brakujące | etap roadmapy 1 | P1 |

Odchylenie sondy od gracza: aktywacja z odległości 64 j. w poziomie od obiektu (w OpenMW – promień z kamery
do obiektu ≤ iMaxActivateDist 192); odległości 3D od oczu zapisuje dziennik sondy (63–136 j.).

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
| `PlayBink` | 10 | 11: `a1_sleepersawake`, `a2_6_incarnate`, `bm_bearhunt*` | filmy (roadmapa 1) |
| `Resurrect` | 10 | `tr_champion`, `bm_trees`, `co_10` | |
| `WakeUpPC` | 8 | 17 zadań wątku głównego (`a1_*`) | sen – **wątek główny** |
| `FadeIn`/`FadeOut` | 7/7 | Bloodmoon `bm_*` | ekran (roadmapa 1) |
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

## 5. Magia

| Element | Status | Uwagi |
|---|---|---|
| Efekty obrażeń, leczenia, wzmocnień/osłabień, paraliż, odporności w obrażeniach | Zaimplementowane | testy syntetyczne |
| Oddychanie pod wodą, chodzenie po wodzie, lewitacja, powolne spadanie, tarcza, niewidzialność, kameleon, światło, widzenie w ciemności, ślepota, wykrywanie, telekineza, Boska/Almsivi interwencja, **przywołania**, przedmioty przywołane, uspokojenie/szał/demoralizacja/odwaga/odpędzanie nieumarłych, kontrola istot, choroby, wampiryzm, słońce | Brakujące | oznaczone w kodzie jako „później” |
| Tarcze żywiołów, słabości | Nieprzetestowane | |

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
| Wilkołactwo (Bloodmoon) | Brakujące | |
| Choroby, wampiryzm | Częściowo zgodne | |

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

1. Start gry: filmy (konwersja lokalna ffmpeg → Theora), menu główne, ekrany ładowania, okno zapisu/wczytania,
   `PlayBink`, `FadeIn`/`FadeOut`/`FadeTo`, `WakeUpPC`/`GetPCSleep`.
2. Pięć okien kreatora postaci jak w OpenMW.
3. MWScript – najpierw stałe zera, potem nieobsłużone wg mapy z punktu 4.
4. Efekty magii z punktu 5.
5. Interfejs z punktu 3.
6. Grafika: animacje, widok 1-/3-osobowy, pogoda, oświetlenie.
7. Tribunal/Bloodmoon (wilkołactwo i pozostałe).

Każdy krok kończy się porównaniem z OpenMW (sondy MCP, gdy będzie ekran X) i aktualizacją tej listy.
