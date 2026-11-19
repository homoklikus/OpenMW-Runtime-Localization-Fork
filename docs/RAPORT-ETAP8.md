# Etap 8 – dokończenie klasycznego GUI i dalszy audyt zgodności z OpenMW 0.51

Stan na 2026-11-19. Baza: lokalny HEAD po etapie 7 (`8b359a1`). Zasada etapu: najpierw pełny, wierny port
OpenMW 0.51; nowoczesny interfejs jest wstrzymany do ukończenia portu.

## 1. Niestabilność test_ai – przyczyna i naprawa

| Objaw (pod obciążeniem, 6 równoległych przebiegów) | Przyczyna | Rodzaj | Naprawa |
|---|---|---|---|
| „podąża za graczem” – NPC nie rusza mimo gracza w zasięgu | `_los` zasłaniali inni aktorzy; OpenMW (`PhysicsTaskScheduler::hasLineOfSight`) bada promień z maską World, HeightMap i Door | **błąd silnika** | trafienia w aktorów pomijane; dotyczy podążania, powitań, świadków przestępstw i walki |
| aktywacja AiFollow | OpenMW sprawdza ją co 0,5 s (`storage.mTimer`), Godot co 0,25 s | rozbieżność | timer 0,5 s |
| „pakiet podróży z rekordu” po 120 klatkach już zakończony | pod obciążeniem klatka to więcej czasu gry (time_scale 4) | założenie testu | typ pakietu sprawdzany zaraz po wczytaniu |
| „ostatni = podróż” po zakończeniu | `AiSequence::execute` przy pustej sekwencji ustawia `mLastAiPackage = None`; kilka kroków fizyki w jednej klatce | założenie testu (Godot zgodny z OpenMW) | sprawdzenie semantyki OpenMW (−1 po pustym kroku) |
| „AiTravel nie kończy się od razu” | 30 klatek pod obciążeniem wystarcza na dojście | założenie testu | niezmiennik: zakończony tylko u celu |
| pozycja po odczycie | NPC idzie dalej przez 3 klatki | założenie testu | sprawdzenie bez ruchu AI |
| odległości 999–1134 jedn. przy podążaniu | gracz stawiany przy podróżnym, który pod obciążeniem doszedł w inne miejsce (ściana chaty) | założenie testu | znane, otwarte pozycje |

Wynik: 8/8 przy ośmiu równoległych przebiegach (wcześniej 0/6 przy sześciu). Regresja: aktor stojący między
NPC a graczem nie zasłania widoczności. Skutek uboczny zgodny z OpenMW: NPC częściej witają gracza
(test_sound_world czeka teraz na koniec kwestii).

## 2. Pasek przewijania MW_VScroll / MW_HScroll

Wg `files/data/mygui/openmw_list.skin.xml`:
- szerokość 14 px;
- strzałki w polach MW_Box 14 × 15 (`omw_menu_scroll_up/down`, 10 × 10 od 2, 2);
- tło MW_Box 3 px od strzałek;
- suwak `omw_menu_scroll_center_v` kafelkowany, 9 px od x = 2, zakres TrackRangeMargins 20/19, minimum 14 px;
- kółko i strzałki przesuwają o 36 px × skala GUI (Godot domyślnie przesuwa o 1/8 strony);
- MoveToClick: kliknięcie w tło przenosi suwak w to miejsce.

Styl ustawia motyw (`UI._apply_scroll_theme`), a zachowanie konfiguracja każdego ScrollContainer i paska
w chwili dodania do drzewa (także wewnętrzne paski list). Tekstury suwaka pochodzą z zasobów OpenMW (GPLv3),
nie od Bethesdy. Testy w `test_ui_geometry`: szerokość, pola strzałek, krok, kółko, MoveToClick i minimum
suwaka przy skali 1 i 2.

## 3. Statystyki przed zakończeniem kreatora

OpenMW (`Npc::getNpcData`, `MechanicsManager::buildPlayer`):
- **nowa gra:** atrybuty, umiejętności i poziom z NPDT rekordu „player”; zdrowie, magia i kondycja z NPDT
  (bez przeliczania); czary rekordu i moce rasy z rekordu. `MechanicsManager::update` nie wywołuje
  `buildPlayer`.
- **setPlayerName:** tylko imię.
- **setPlayerRace / Class / Birthsign:** `buildPlayer` od wartości rekordu. Rasa jest naliczana tylko po jej
  wyborze (`mRaceSelected`), klasa tylko po jej wyborze (`mClassSelected`), znak po ustawieniu. Zdrowie liczy
  `updateHealth` = floor((siła + wytrzymałość) / 2), magię i kondycję wzory z atrybutów. Na końcu
  `unequipAll` + `autoEquip`.
- **wczytanie zapisu:** oba znaczniki ustawione (`playerLoaded`).

Wcześniej Godot naliczał rasę i klasę od razu. Teraz `character.build_record()` i `build(choice, flags)`,
znaczniki w `state.player.chargen_flags`. Komunikat „Utworzono postać”, którego OpenMW nie ma, został
usunięty. Testy zależne od umiejętności klasy (handel, postęp, walka, magia, przestępstwa, tryb menu,
dźwięk) jawnie ustawiają postać po kreatorze. test_chargen sprawdza dane rekordu przed kreatorem, rasę bez
klasy oraz rasę z klasą.

## 4. Oświetlenie wnętrz

Porównanie kodu OpenMW 0.51 (`lib/light/util.glsl`, `lightutil.cpp`, `RenderingManager::configureAmbient`,
`settings-default.cfg`) z Godotem:

| Element | OpenMW 0.51 | Godot przed | Godot po |
|---|---|---|---|
| Przestrzeń barw | gamma (bez linearyzacji tekstur i świateł) | liniowo + sRGB na końcu: tłumienie I działało jak I^0,45, przez co światła były zbyt jasne z daleka | tłumienie przeliczone do I^2,2 (zanik d^−2,2, energia (r/3)^2,2) |
| Tonemapping | brak | Filmic | Linear (obcięcie do [0, 1]) |
| Zasięg światła | r × 1,75 (light radius multiplier), wygaszanie od 0,75 do 1,0 tego zasięgu | 2r | 1,75 r (okno Godota) |
| Słońce we wnętrzu | kolor „sunlight” komórki, kierunek (−1, 45°, 45°) | wyłączone | jak OpenMW, bez cieni |
| Minimalna jasność ambientu | luminancja 0,08 (`minimum interior brightness`) | brak | jak OpenMW |
| Ujemne światła | pomijane (shaders) | pomijane | bez zmian |

Ograniczenia: OpenMW obcina sumę oświetlenia przed mnożeniem przez teksturę, a Godot obcina wynik końcowy.
Kąt padania (lambert) liczony jest liniowo. Porównanie zrzutów tych samych wnętrz (Arrille's Tradehouse,
urząd celny) wymaga VM, patrz punkt 8.

## 5. Mapa lokalna wnętrz

Wg `LocalMap::requestInteriorMap` i `LocalMapRenderToTexture`:
- granice z geometrii modeli (wcześniej z pozycji referencji) z marginesem 500 jedn.;
- obrót wg NorthMarker;
- kamera ortogonalna od zMax + 5 jedn. do zMin (wcześniej wysokość gracza + 60 m);
- bez mgły;
- jasność jak światło mapy OpenMW (ambient 0,3 + 0,7 × lambert dla kierunku (−0,3, −0,3, 0,7) ≈ 0,9 na
  podłodze). Godot renderuje bez cieniowania i skaluje do 0,9, bo osobne światło kierunkowe oświetliłoby
  cały świat.

Sprawdzone renderem pod Xvfb na danych syntetycznych. Porównanie z OpenMW na prawdziwych danych: punkt 8.

## 6. Zachowanie okien: przypinanie, ukrywanie, maksymalizacja, HUD

Wg `WindowPinnableBase`, `WindowManager::updateVisible/toggleVisible/toggleMaximized` i `HUD::on*Clicked`:
- **pinezka:** przycisk w pasku tytułu (skórki PinUp/PinDown: `menu_rightbutton{up,down}_*` z gry). Przypięte
  okno (statystyki, ekwipunek, magia, mapa) zostaje widoczne po wyjściu z trybu GUI na osobnej warstwie, bez
  obsługi myszy, i jest odświeżane co 0,5 s. Jego część HUD się chowa (paski, broń, czar, minimapa).
  Przypięta mapa nie blokuje sterowania ani zapisu.
- **Shift + podwójne kliknięcie tytułu:** przełączenie między prostokątem zwykłym a „maximized” z ustawień
  (`stats/inventory/spells/map maximized x/y/w/h`).
- **samo podwójne kliknięcie tytułu:** ukrycie nieprzypiętego okna (ustawienie „hidden”, tylko w trybie
  Interface).
- **kliknięcie elementu HUD w trybie Interface:** przełącza okno (paski – statystyki, broń – ekwipunek,
  czar – magia, minimapa – mapa). Wilkołak dostaje `sWerewolfRefusal`. Tło trybu menu leży nad HUD, więc
  kliknięcie przechodzi przez nie.
- **okno mapy** wg `openmw_map_window.layout`: tytuł (nazwa komórki) w pasku z pinezką, widok na całe wnętrze,
  przycisk World/Local 61 × 22 w prawym dolnym rogu (10/9 px).

Stan pin/hidden/maximized jest w stanie gracza (zapis gry). OpenMW trzyma go w `settings.cfg`, czyli
globalnie; ta rozbieżność jest opisana w punkcie 10. Testy w test_menu_mode.

## 7. Okno rozmowy i przyciski

`openmw_dialogue_window.layout`:
- marginesy 8;
- historia w MW_Box z wcięciem 7;
- prawa kolumna 166 px, 9 px od historii: pasek postawy 18 px z tekstem wewnątrz (wcześniej podpis pod
  paskiem), 5, lista tematów, 7, Goodbye 23.

Przyciski MW_Button: 23 px przy czcionce 16 (marginesy motywu 3/3), w poziomie tekst + 24 jak
`AutoSizedButton` (wcześniej 25 px i szersze). Zapasowe teksty po angielsku (jak OpenMW bez GMST), a nie po
polsku.

## 8. Handel (GM_Barter)

Wcześniej handel był jednym oknem z listami i polskimi opisami. Teraz układ OpenMW:
- okno ekwipunku gracza (prostokąt „inventory barter”) z siatką handlu: sprzedawane rzeczy znikają, kupowane
  mają tło `menu_icon_barter`;
- okno kupca w prostokącie `barter` 0,6/0,27/0,38/0,63 (`openmw_trade_window.layout`): kategorie z filtrem
  nazw, siatka towaru, dolny panel z „+”, etykietą `sTotalCost`/`sTotalSold`, kwotą bez znaku, `sYourGold`,
  „−”, `sSellerGold`, `sMaxSale`, `sBarterDialog8` (Offer) i Cancel;
- okno rozmowy ukryte na czas handlu (`updateVisible` dla GM_Barter), Cancel wraca do rozmowy.

Semantyka przycisków jak `TradeWindow`: +/− zmieniają wartość bezwzględną salda, wpisana kwota zachowuje znak,
Max Sale ustawia złoto kupca, przeniesienie przedmiotu ustawia saldo na ofertę kupca (`updateOffer`).
Ceny i targowanie bez zmian (`mw_trade.gd`). Testy w test_trade.

## 9. Okna usług i pojemnika

- **Zakup zaklęć, podróże, trening** (`mw_service_window.gd`) wg `openmw_spell_buying_window`,
  `openmw_travel_window` i `openmw_trainingwindow`:
  - skórka MW_Dialog, wyśrodkowane okno 450 × 290 / 500 × 250 / 320 × 200;
  - tytuł `sServiceSpellsTitle` itd., podtytuł SandText;
  - lista SandTextButton po 18 px w formacie „nazwa  - cena” + `sgp`, pozycje za drogie wyszarzone
    i nieaktywne;
  - „sGold: N”, OK albo Cancel z l10n `Interface`.

  Wcześniej była to lista w oknie handlu z polskimi opisami.
- **Pojemnik** wg `openmw_container_window`: przyciski `sDisposeofCorpse` (tylko przy łupieniu ciała),
  `sTakeAll` i Close przy prawej krawędzi.
- **Brakująca funkcja „Dispose of Corpse” dodana** (`ContainerWindow::onDisposeCorpseButtonClicked`): najpierw
  „weź wszystko”, potem ciało nietrwałego aktora znika ze świata, a przy trwałym pojawia się
  `sDisposeCorpseFail`.
- **Konwerter:** gubił flagę trwałości z nagłówka rekordu (`FLAG_PERSISTENT` 0x400, `Class::isPersistent`).
  Teraz NPC i stworzenia mają pole `persistent`. Test: pytest `test_records`.

## 10. Testy

- `tools/run_tests.sh`: wszystkie testy zaliczone (przebiegi `rtx61` i `rtx63`, a po ostatnich zmianach
  `rtx64`, patrz niżej).
- Wielokrotne przebiegi test_ai pod obciążeniem: 8/8 (osiem równoległych instancji) oraz 6/6 i 2/2 w osobnych
  seriach.
- Nowe i rozszerzone testy:
  - `test_ui_geometry`: MW_VScroll przy skali 1 i 2;
  - `test_menu_mode`: przypinanie, ukrywanie, maksymalizacja, kliknięcie HUD, filtry;
  - `test_dialogue`: układ okna;
  - `test_trade`: handel i okna usług;
  - `test_chargen`: statystyki przed kreatorem, po rasie, po klasie;
  - `test_weather`: oświetlenie wnętrz, światła punktowe, tonemapping;
  - `test_combat`: Dispose of Corpse;
  - `test_ai`: widoczność bez aktorów;
  - pytest `test_records`: flaga trwałości.
- Porównania wizualne na prawdziwych danych w tej części etapu nie były możliwe (punkt 12). Procedura z
  etapu 7 jest gotowa (`ui_cases`, `ui_geom_compare.py`) i obejmuje także oświetlenie (te same wnętrza i kadry).

## 11. Pozostałe braki i kolejność prac

Priorytety z zależnościami (P1 – psuje wierność od pierwszych minut, P2 – zwykła gra, P3 – rzadkie):

1. **Porównania na prawdziwych danych** (wymaga VM): oświetlenie wnętrz po zmianach z punktu 4, mapa
   lokalna wnętrz, okna rozmowy i handlu, przypięte okna, pasek MW_VScroll. P1.
2. **Sonda menu głównego:** `I.UI.setMode("MainMenu")` w OpenMW nic nie pokazuje. Trzeba otworzyć menu
   klawiszem Esc przez XTest (KeySender już jest w `mwscript_compare.py`) i porównać układ, tła, przejścia,
   wczytywanie zapisu i nową grę. P2.
3. **Pozostałe okna usług w układach OpenMW:** naprawa (`openmw_merchantrepair`), doładowanie
   (`openmw_recharge_dialog`). Zakup zaklęć, podróże i trening są już zrobione (punkt 9). P2.
4. **Alchemia, zaklinanie, tworzenie czarów** (`openmw_alchemy_window`, `openmw_enchanting_dialog`,
   `openmw_spellcreation_dialog`): dziś wspólne okno `mw_magic_window` z polskimi opisami. P2.
5. **Okno pojemnika:** wymiary względem ItemView (5 px) i porównanie zrzutem. P3.
6. **Odpoczynek i awans:** `openmw_wait_dialog`, `openmw_levelup_dialog` (teksty zapasowe po polsku). P2.
7. **Okno perswazji:** `openmw_persuasion_dialog`. P3.
8. **Ustawienia okien w settings (globalnie)** zamiast w zapisie gry, jak `[Windows]` OpenMW. P3.
9. **Okno ustawień** jak OpenMW (zakładki, klawisze; teksty z l10n OMWEngine). P3.
10. **Konsola (~)**, przydatna także do testów porównawczych. P3.
11. **Sterowanie kontrolerem w menu** (`[GUI] controller menus`). P3.

Pozostałe systemy (z inwentaryzacji): animacje pierwszo- i trzecioosobowe (P1), efekty wizualne magii (P1),
opady, księżyce, daleki teren (P2/P3). Port nie jest ukończony.

## 12. Środowisko porównań i commity

Od ok. 12:50 powłoka VM nie montuje podłączonych folderów („Too many open files in system” po stronie
montowania hosta), choć przesyłanie plików przez most działa. Bez powłoki nie da się uruchamiać OpenMW na
Xvfb ani robić commitów bezpośrednio w repozytorium.

Obejście: drzewo robocze urządzenia (dokładnie stan `8b359a1`) zostało odtworzone w chmurze z plików
pobranych przez most. Na nim powstały logiczne commity etapu 8, przesłane jako seria łatek do
`etap8-patches/` w repozytorium. Zastosowanie, gdy powłoka wróci (bez push):

    cd "/media/precell/Inne/Projekty AI/OpenMWGoDot"
    git am etap8-patches/*.patch
