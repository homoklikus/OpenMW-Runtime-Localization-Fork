# Etap 10 – kompletność klasycznego interfejsu i zarządzanie trybami GUI

Stan: **w toku** (raport cząstkowy, aktualizowany przy każdej części). Port wierny OpenMW 0.51, bez nowych
funkcji. Commity lokalne, bez push.

## 1. Wykonane części

| Część | Zakres | Testy |
|---|---|---|
| 1. Stos trybów GUI (§2) | `mw_gui_modes.gd`: pushGuiMode / popGuiMode / removeGuiMode / containsMode, exitCurrentGuiMode, ukrywanie okien przykrytego trybu i przywracanie przy zdjęciu (GuiModeState::update), updateVisible (pauza, kursor). Jeden mechanizm dla wszystkich okien – bez wyjątków dla poszczególnych scenariuszy | test_gui_modes (24), test_trade wg stanu stosu, pełny zestaw |
| 2. Stworzenia wodne i latające (dodatek, priorytet) | punkt 3 niżej | test_water_creatures (22), test_water_game (20) |
| 3. Język angielski (dodatek, priorytet) | punkt 4 niżej | test_language (38) |

### Stos trybów GUI – scenariusze z zadania

* ekwipunek → alchemia → zamknięcie → ekwipunek; ekwipunek → kamień dusz → zaklinanie / ładowanie → ekwipunek;
* rozmowa → handel / trening / podróż (anuluj) → rozmowa; ekwipunek → naprawa → ekwipunek;
* okno z pytaniem nad trybem – po wyborze lub anulowaniu tryb bez zmian;
* Esc = exitCurrentGuiMode na każdym poziomie (okno może odmówić zamknięcia), pauza symulacji i przechwycenie
  myszy wynikają ze stosu (pusty stos i brak innych okien → gra);
* tryb już na stosie przenoszony na wierzch, usunięcie trybu ze środka stosu, „Żegnaj” wraca do świata.

## 2. Wykryte i naprawione błędy (wykrycie → przyczyna → naprawa → test)

| Błąd | Przyczyna | Naprawa | Test |
|---|---|---|---|
| Okna otwierane z ekwipunku zamykały tryb menu (powrót do świata zamiast do ekwipunku) | każde okno samo pauzowało/wznawiało grę i zamykało poprzednie | wspólny stos trybów | test_gui_modes |
| „Latający Slaughterfish” | punkt 3 | punkt 3 | test_water_* |
| Ciało martwego aktora z włączoną grawitacją spadałoby przez teren (wykryte przy teście latających) | po śmierci kształt kolizji jest wyłączany, a ruch szedł przez `move_and_slide` | ciało opada do podłoża wyznaczonego promieniem, pod wodą wypływa (mFloatToSurface, 25 j./s) | test_water_game („martwe latające spada na ziemię”) |
| Walka: pływak pod celem „sięgał” go z dna | odległość walki liczona w poziomie | getDistanceToBounds – odległość 3D | test_water_game |
| Po wczytaniu zapisu z menu głównego gracz obraca kamerą, ale się nie rusza (zgłoszenie) | `_enter_nogame` wyłączało `_physics_process` gracza, wczytanie przywracało tylko `process_mode` (w trakcie gry problem nie występował) | `load_game`/`new_game` włączają fizykę gracza; odtworzone i sprawdzone na kopii zapisu użytkownika (0,00 m → ruch) | test_load_controls |
| Kwestie NPC na początku gry ginęły (zgłoszenie) | MenuMode skryptów nie uwzględniało filmu ani stosu trybów GUI – skrypty na statku (Say Jiuba, okno imienia) działały pod filmem wprowadzającym nowej gry | MenuMode = WindowManager::isGuiMode (tryb GUI na stosie, GM_Video, menu główne) | test_load_controls |
| Podpowiedź broni: obrażenia „0 – 0” | odczyt nieistniejących pól `chop_min`/… zamiast `chop: [min, max]` | podpowiedzi OpenMW (cz. 9) | test_tooltips |
| test_crime: sprawdzenie „przeniesienie czeka, póki gra stoi” raz nie przeszło w pełnym zestawie | wyścig w teście: wynik zależał od tego, czy strażnik zdążył zagadać (pauza) przed sprawdzeniem; zachowanie gry zgodne z World::update | test ustawia pauzę jawnie i sprawdza, że przeniesienie czeka | test_crime (3 powtórzenia) |
| Testy (i uruchomienia bez launchera) zapisywały autozapis/szybki zapis do zapisów użytkownika (user://saves); test_progress raz nie przeszedł – długi zapis do pełnego katalogu wydłużył klatkę, a TimeAdvancer (jak w OpenMW 0.51) przeszedł kilka godzin w jednej klatce, mijając godzinę przerwania | brak --saves w testach; autozapis przed odpoczynkiem (nowy, domyślnie włączony jak w OpenMW) | bez --saves przy --project zapisy w <projekt>/saves (launcher zawsze podaje --saves); test przerwania snu z wyłączonym autozapisem (autozapis sprawdza test_settings) | test_progress, test_settings |
| Polskie komunikaty przy zamkniętych drzwiach/pojemniku, podniesieniu przedmiotu i pułapce | własne komunikaty spoza OpenMW | jak OpenMW: FailedAction bez tekstu (tylko dźwięk), ActionTake bez tekstu, pułapka działa czarem | test_interaction |
| Samoczynny obrót kamery po wczytaniu gry (zgłoszenie) | osie urządzeń spoza kontrolerów gry (spoczynek ≠ 0) czytane jako prawa gałka; „Enable Controller = Off” nie odcinał akcji pada | punkt 7.14 | test_look_stability, test_gamepad |

## 3. Stworzenia wodne

**Objaw:** Slaughterfish wysoko w powietrzu, poza wodą (podpowiedź „Rozmawiaj: Slaughterfish”).

**Przyczyna (ogólna, nie dla jednego ID):** `mw_cell_builder` dawał brak grawitacji każdemu stworzeniu z flagą
Swims bez Walks (`no_gravity = not walks and (flies or swims)`). Poza wodą taki aktor nie spadał: wjeżdżał po stoku
brzegu i stopniach (Stepper), a gdy teren opadał – zostawał w powietrzu. Dodatkowo poziom pływania liczono ze stałego
wzrostu 1,8 m, więc mała ryba w wodzie płytszej niż ok. 1,6 m „nie pływała” i trafiała do gałęzi lądowej. W danych
użytkownika 2 ze 131 umieszczeń stworzeń wyłącznie wodnych (5 rekordów) ma początek do 68,6 j. nad lustrem wody –
w OpenMW spadają do wody, u nas wisiały od wczytania komórki.

**OpenMW (porównanie z kodem 0.51):**
* `World::isFlying`: bez grawitacji tylko canFly (Flies) albo Lewitacja; martwy/sparaliżowany nie leci.
  Swims nie zwalnia z grawitacji. `isPureWaterCreature` = Swims i nie Bipedal/Flies/Walks – używane przez AI, nie
  przez fizykę; stworzenie pływające i chodzące (np. krab) nie jest traktowane jak ryba.
* `MovementSolver`: poniżej poziomu pływania albo w locie – prędkość z pochyleniem i obrotem; „If not able to fly,
  don't allow to swim up into the air” – składowa w górę odrzucana; poza wodą grawitacja i bezwładność.
* `World::isUnderwater`: poziom z połówek wymiarów fizycznych aktora.
* AI: `canActorMoveByZAxis` (pływa albo leci) – pochylenie (smoothTurn osi X) w pathTo i walce, shortcutPath,
  ostatni punkt drogi po odległości 3D, AiWander::wanderNearStart (8% co reakcję, destinationIsAtWater dla
  niewodnych, isDestinationHidden, isAreaOccupiedByOtherActor), Creature::getMaxSpeed – fMin/fMaxFlySpeed dla Flies.
* martwy/sparaliżowany pod wodą wypływa (CharacterController mFloatToSurface).

**Naprawa (warstwa fizyki aktora i AI, bez obejść):** wszystkie punkty wyżej przeniesione do `mw_actor.gd`
(gałąź pływania i lotu, `can_fly`, `inert`, `ai_pitch`, wysokość z kapsuły, `_corpse_step`), `mw_magic.apply_movement`
(isFlying co klatkę), `mw_cell_builder` (tylko Flies), `mw_ai.gd` (pochylenie, skrót, wanderNearStart, odległość 3D,
prędkość lotu). Nie użyto stałej wysokości, teleportacji pod wodę, blokady ID ani wyłączenia fizyki.

**Testy regresji (dodatek, pkt 1–9):**

| Przypadek | Test |
|---|---|
| 1. ryba w wodzie (ruch w górę zatrzymany pod powierzchnią, w dół – głębiej) | test_water_creatures |
| 2. ruch i atak (walka z graczem nad rybą: płynie w górę, nie wyżej niż poziom pływania, trafia) | test_water_game |
| 3. brzeg (stok 30° wychodzący z wody – brak wjazdu ponad wodę) | test_water_creatures |
| 4. głęboka i płytka woda (0,5 m – mała ryba pływa) | test_water_creatures |
| 5. poza wodą z danych/skryptu (3–4 m nad ziemią – spada; komórka bez wody) | test_water_creatures, test_water_game |
| 6. ponowne wczytanie komórki z flagami rekordu | test_water_game |
| 7. zapis/odczyt (pozycja, grawitacja, brak unoszenia) | test_water_game |
| 8. czary i efekty ruchu (Lewitacja na stworzeniu wodnym, koniec Lewitacji, śmierć latającego) | test_water_creatures, test_water_game |
| 9. inne stworzenia (Swims+Walks, Flies, Swims+Flies, Walks – flagi → grawitacja) | test_water_creatures |

Test syntetyczny przechodzi na nowym kodzie i nie przechodzi na starym (7 niezaliczonych, m.in. ryba wisi na
y = 4,0 m) – sprawdzone.

**Weryfikacja na prawdziwych danych (kontynuacja etapu):** OpenMW 0.51 w maszynie wirtualnej (Xvfb, scenariusz
Lua `rlf_ai`: pozycje aktorów co 1 s) i port (`tools/ai_compare.gd`) w Seyda Neen przy 14 punktach odradzania
stworzeń wodnych (listy poziomowane); porównywane wyłącznie liczby. Instancja OpenMW na pulpicie użytkownika nie
miała dostępu do ekranu X – sesji użytkownika nie zmieniałem. Wykryte i naprawione dwie dalsze różnice:
1. **Kształt aktora z węzła „Bounding Box”** (BulletNifLoader::findBoundingBox, Actor: mCollisionBox,
   mMeshTranslation): port liczył prostopadłościan z granic całej siatki (ogon, płetwy), więc poziom pływania był
   za wysoko – ryba przy powierzchni (−136 j.) opadała w porcie o 20 j. 36 z 37 modeli stworzeń ma ten węzeł.
   Konwerter zapisuje go w `extras.mw_bounding_box` (MODEL_CONVERTER 0.1.3 – modele konwertowane ponownie),
   aktor używa półwymiarów (niezależne x/wysokość/z) i przesunięcia środka.
2. **World::adjustPosition przy pierwszej aktualizacji aktora** (Actors::update): z = max(z, teren) + 20 j., a
   aktor, który nie leci i nie pływa, stawiany na podłożu (traceDown). Ryba z punktu odradzania nad wodą (+54 j.)
   w OpenMW trafia na dno (−140 j.); w porcie zatrzymywała się na poziomie pływania (−36 j.), po poprawce trafia
   na dno (−142 j.).

| Przypadek | OpenMW | Port przed | Port po |
|---|---|---|---|
| ryby pod wodą (−129…−1293 j.) | bez wynurzania ponad poziom pływania | jw. | jw. (+20 j. z adjustPosition jak OpenMW) |
| ryba przy powierzchni (−136 j.) | zostaje | opada o 20 j. (za duża wysokość) | wysokość z „Bounding Box” |
| odradzanie nad wodą (+54 j.) | dno (−140 j.) | poziom pływania (−36 j.) | dno (−142 j.) |
| ciało (śmierć), ponowne wczytanie, zapis/odczyt, atak | – | – | test_water_game; ciało wypływa / opada |

**Pozostała różnica (niepotwierdzona):** po trafieniu na dno ryba z odradzania nad wodą płynie w porcie w górę
ku pozycji startowej AiWander zapamiętanej przed adjustPosition (kolejność jak w Actors::update: AI przed
adjustPosition); w 8 s próbkowania OpenMW ryba nie płynęła. Krótka próba i losowość list poziomowanych nie
pozwalają rozstrzygnąć – bez zmiany zachowania.

## 4. Język angielski

* Źródło tekstu: GMST z danych gry (z warstwą tłumaczeń, jeśli włączona) → l10n OpenMW (`OMWEngine`, `Calendar`;
  domyślny język „en”) → zapas angielski w kodzie tylko przy braku klucza. Zapas to krótkie własne sformułowania –
  bez kopiowania tekstów Bethesdy do repozytorium.
* Usunięte z kodu: ok. 170 polskich napisów i zapasów (kreator, statystyki, ekwipunek, handel, usługi, książki,
  ustawienia, zapis/wczytanie, ekran ładowania, komunikaty magii, zamków, pułapek, menu główne, mapa, HUD
  diagnostyczny). Tablice zapasowe atrybutów, umiejętności i specjalizacji po angielsku.
* Podpowiedź celownika: aktor – sama nazwa (ToolTips::getToolTipViaPtr), bez „Rozmawiaj:”; zamek i pułapka –
  `#{sLockLevel}: N`, `#{sTrapped}`; klucz – „nazwa #{sKeyUsed}”.
* Diagnostyka (print, ostrzeżenia, błędy skryptów i konwertera, raporty) zostaje po polsku – nie jest tekstem gry.
  Infrastruktura wielojęzyczna i pliki `pl.yaml` bez zmian.
* Ustawienie języka: l10n z `preferred_locales` (domyślnie en); tłumaczenia danych gry z „Język gry” w launcherze –
  wartość „auto” przejmuje język launchera. U użytkownika launcher ma `language: pl`, `game_language: auto`, więc
  teksty danych gry są tłumaczone na polski; dla angielskiego trzeba w launcherze ustawić „Język gry” = `en`
  (konfiguracji użytkownika nie zmieniałem). Testy i porównania uruchamiane są z językiem angielskim.
* Test `test_language.gd` (nie tylko diakrytyki): słowa z listy polskich słów interfejsu, aktywny język l10n,
  przekazanie ustawienia (pl → [pl, en], en → EN, auto → język launchera, original → bez tłumaczenia),
  pierwszeństwo GMST z danych nad zapasem, zapasy przy braku klucza, skan ponad 1000 literałów skryptów i ekrany:
  ekwipunek/statystyki/magia, rozmowa, handel, trening, podróż, zakup czarów, książka, odpoczynek, ustawienia,
  menu główne, zapis i wczytanie. Na starym kodzie test zgłasza 257 polskich literałów i błędy na każdym ekranie.
* Pozostaje: syntetyczne dane testowe konwertera (nazwy i dialogi postaci testowych) są po polsku – to dane, nie
  interfejs; ich tłumaczenie wymaga zmiany oczekiwań wielu testów.

## 5. Launcher EN

**Przyczyna (kilka współdziałających błędów, nie brakujące pojedyncze napisy):**
1. Słownik `i18n.py` miał 20 kluczy, a `tr()` było wywoływane w 7 miejscach – pozostałe ok. 400 tekstów launchera
   i komunikatów `mwcore` (strony, kreator, okna dialogowe, podpowiedzi, stany konwersji, błędy instalacji,
   archiwów i modów, dziennik działań) było wpisane po polsku na stałe.
2. `page_settings.py` importował `LANG` przez wartość (`from .i18n import LANG`) – zmienna była kopiowana przy
   imporcie, przed `set_lang()` w oknie głównym, więc etykiety ustawień zawsze były polskie.
3. Stałe modułów (`CHOICE_LABELS`, `STAGE_NAMES`, `STEP_NAMES`, podpis logo) tłumaczone przy imporcie – zamrożone
   w języku sprzed wczytania konfiguracji.
4. Kreator pierwszego uruchomienia powstawał przed `set_lang()` (zawsze po polsku), a wybór „English” na jego
   pierwszej stronie nie zmieniał pozostałych, już zbudowanych stron.
5. Zmiana języka w Ustawieniach działała dopiero po ponownym uruchomieniu i zmieniała tylko te kilka kluczy.
6. Dziennik działań zapisywał gotowy polski tekst – wpisy nie zmieniały języka; domyślny profil zapisany jako
   „Domyślny” był wyświetlany po polsku także w EN.
7. Język gry „auto” przejmował język launchera, więc zmiana języka launchera zmieniała język gry.

**Naprawa:**
* `mwcore/i18n.py` + `mwcore/i18n_en.py` – wspólny katalog launchera i `mwcore` (klucz = tekst polski, jak gettext;
  316 wpisów, parametry nazwane). Wszystkie teksty interfejsu przez `tr()`; stałe modułów przez `N_()` i
  tłumaczenie przy użyciu. Narzędzie przepisujące zachowało kod i komentarze (zamiana po zakresach AST).
* Zmiana języka bez restartu: `MainWindow.set_language()` zapisuje `language` w konfiguracji launchera i buduje
  cały interfejs od nowa; procesy gry, edytora i konwersji należą do okna i działają dalej, dziennik konwersji jest
  przenoszony; sygnały konwertera podłączone do metod (nie lambd), więc usunięta strona jest odłączana.
* Kreator: język ustawiany przed zbudowaniem stron, zmiana na stronie języka przebudowuje pozostałe strony.
* Dziennik działań zapisuje szablon źródłowy i argumenty (`Activity.add(kind, text, **args)`), tłumaczenie przy
  wyświetlaniu (`tr_stored`) – także stare wpisy o stałej treści. Domyślny profil: `Profile.display_name`.
* Nazwy języków w selektorze w ich własnym języku („Polski”, „English”); format liczb i dat zależny od języka.
* Niezależność od języka gry: przed zmianą języka launchera profile z „Język gry = auto” dostają jawnie
  dotychczasowy język (gra wygląda tak samo jak przed zmianą); wpis w dzienniku działań. Mechanizm
  `game_language` poza tym bez zmian.
* Nie tłumaczone: surowy log konwertera (diagnostyka `mwconv`, w tym raport JSON) i nazwy modów nadane przez
  autorów.

**Testy PL/EN (`launcher/tests/test_i18n.py`, 7 testów; prawdziwe okna Qt, platforma offscreen):**
kompletność katalogu i zgodność parametrów, brak polskich literałów poza `tr()` i brak literałów w wywołaniach Qt
pokazujących tekst, brak `tr()` przy imporcie; scenariusz: start z `language: pl` → przełączenie na EN bez
restartu (wszystkie strony bez polskich słów, nie tylko diakrytyków) → komunikaty dynamiczne (pasek stanu,
problemy „Graj”, dziennik działań z wpisem zapisanym po polsku, konwersja) → zamknięcie i ponowne uruchomienie
(EN zapamiętany) → powrót na PL → język gry niezmieniony (efektywny język w ustawieniach runtime: pl przed i po);
kreator w EN i zmiana języka w kreatorze; komunikaty `mwcore` w obu językach. Zrzuty ekranów launchera w EN i PL
(`tools/screenshots.py KATALOG pl|en`) obejrzane – jedyny pominięty napis („Instaluj…”) znaleziony na zrzucie
i poprawiony. Testy launchera: 22 zaliczone, 1 pominięty (jak wcześniej); testy konwertera – zaliczone.

**Po ponownym uruchomieniu:** język przywracany z konfiguracji launchera (`launcher.json`), kreator i okno główne
od pierwszej klatki w wybranym języku.

## 6. Przechodzenie między komórkami

**Objaw:** przy wyjściu ze statku przez chwilę widać częściowo załadowany świat i błędy grafiki.

**Sonda klatek** (`godot/tests/probe_transition.gd`): zapis każdej narysowanej klatki od rozpoczęcia przejścia
(także klatek rysowanych przez ekran ładowania w trakcie synchronicznego wczytywania); dla każdej: czy ekran
ładowania zasłaniał obraz, zaciemnienie, wczytane komórki, postawienie gracza, kompilacje potoków shaderów,
różnica od obrazu ustalonego przyciemnionego o zamierzone zaciemnienie. Klatka pokazana graczowi z różnicą
> 0,06 = niekompletna scena. Prawdziwe dane (statek → Seyda Neen, budynek, teleport, granica komórek) na maszynie
użytkownika (Xvfb + lavapipe, obrazy tylko lokalnie, do chmury trafiły wyłącznie liczby).

**Przyczyna (dwie, obie potwierdzone sondą przed poprawką):**
1. Kompilacja potoków shaderów nowych materiałów w pierwszej klatce pokazanej graczowi: wyjście ze statku –
   12 potoków powierzchni i 19 specjalizacji skompilowanych w pierwszej widocznej klatce, różnica 0,079
   (obraz niekompletny, klatka 8 s na rendererze CPU). OpenMW rysuje komórkę od razu kompletną; Godot kompiluje
   potoki podczas rysowania.
2. Pokazywanie świata przed postawieniem gracza na podłożu (World::adjustPosition): kolizje Jolt są dostępne
   dla zapytań dopiero po kroku fizyki, więc pierwsze klatki pokazywały kamerę z punktu docelowego drzwi
   (budynek → świat: różnica 0,084).
Dodatkowe różnice z OpenMW: brak `fadeScreenOut(0.5)`/`fadeScreenIn(0.5)` przy zmianie komórki; ScreenFader w
warstwie nad całym interfejsem (OpenMW: FadeToBlack – nad sceną, pod HUD-em, oknami i ekranem ładowania); stara
scena usuwana dopiero po klatce.

**Przebieg przed:** drzwi → komórki zwalniane (queue_free) → loadingOn (zamrożona klatka) → synchroniczne
wczytanie → loadingOff → pierwsza klatka nowej sceny (kompilacja potoków, gracz jeszcze nie postawiony) →
postawienie po 2 klatkach fizyki.

**Przebieg po (jak Scene::changeToInteriorCell/changeToExteriorCell + gotowość pierwszej klatki):**
fadeScreenOut(0.5), jeśli była wczytana komórka → loadingOn (zamrożona klatka) → stara scena ukryta od razu →
synchroniczne wczytanie (ekran ładowania z paskiem po 50 ms; zaciemnienie postępuje w klatkach ekranu ładowania,
jak ScreenFader::onFrameStart w OpenMW) → gracz stawiany na podłożu → ekran ładowania zostaje do gotowości:
gracz postawiony i jedna klatka z nową kamerą narysowana bez nowych kompilacji potoków (gotowość wizualna;
mechanika, AI, nawigacja i mapa lokalna działają dalej) → loadingOff → fadeScreenIn(0.5). To samo przy
przekraczaniu granicy komórek (doczytanie siatki) i po wczytaniu zapisu (bez zaciemnienia). Odsłanianie działa
także w pauzie (podróż z rozmowy, film). Limit 240 klatek tylko jako zabezpieczenie (ostrzeżenie w logu), bez
stałego opóźnienia. Tło ekranu ładowania: w grze zamrożona klatka, bez gry – losowy obraz Splash/ (bez zmian).

**Wyniki sondy na prawdziwych danych (640×360, lavapipe):**

| Przejście | Przed: niekompletne klatki widoczne | Po |
|---|---|---|
| statek → Seyda Neen (wyjście ze statku) | 1 (0,079; kompilacja 31 potoków) | 0 (kompilacja za ekranem ładowania, potem zaciemnienie 0,5 s) |
| Seyda Neen → budynek | 0 (pierwsza klatka przed postawieniem: 0,029) | 0 |
| budynek → Seyda Neen | 1 (0,084; przed postawieniem) | 0 |
| teleport na ląd w innej komórce | 0 (0,015 przed postawieniem) | 0 |
| przekroczenie granicy komórki | – | 0 |
| statek → Seyda Neen przy obciążonym CPU | – | 0 |
| statek → Seyda Neen w 1280×720 | – | 0 |

Test regresji bez renderera `test_transition.gd` (43 sprawdzenia): warstwa FadeToBlack, zaciemnienie przy
przejściu z komórki, ekran ładowania do gotowości, stara scena ukryta, gracz postawiony przed odsłonięciem,
zagnieżdżenie 0 po odsłonięciu, zaciemnienie znika po 0,5 s – dla: świat → wnętrze (drzwi), wnętrze → to samo
wnętrze (COC/MWScript), wnętrze → świat (drzwi), teleport w świecie, podróż w pauzie, wczytanie zapisu w świecie
i we wnętrzu. Szybka podróż i Interwencje Almsivi/Boska używają tej samej ścieżki `travel()`/`travel_to_cell()`.
Nie zmierzono: 1440p/2160p (lavapipe na 2 rdzeniach nie mieści się w limicie czasu wywołania), obrazu OpenMW
w tym samym przejściu (porównano przebieg z kodem 0.51).

## 7. Pozostałe GUI

### 7.1 Okno ilości (cz. 7)
CountDialog jak OpenMW 0.51 (`mw_count_dialog.gd`): okno modalne MW_DialogNoTransp, wysokość 128, szerokość
max(nazwa + 160, 320), środek ekranu; komunikat, nazwa (z duszą), pole liczby 1…max (strzałki ±1, tekst
nieliczbowy – poprzednia wartość), suwak (pozycja = liczba − 1), OK/Cancel, domyślnie cały stos, Enter/Esc.
Wywołania: pojemnik ↔ ekwipunek (przeciągnięcie, dwuklik, Alt + kliknięcie – transferItem), upuszczenie w świat,
handel (sQuanityMenuMessage02 w oknie kupca, 01 w ekwipunku – zamiast przenoszenia po jednej sztuce). Ctrl – 1 sztuka,
Shift – cały stos bez pytania. Stan (wytrzymałość „#c:N”, dusza „@stworzenie”) zachowany w obu częściach.
Różnica wobec OpenMW usunięta w cz. 23: przeciąganie Godota zastąpione DragAndDrop OpenMW (kliknięcie podnosi,
okno ilości przy podniesieniu – punkt 7.16). Upuszczenie na postać (użycie) – bez okna ilości.
Test: test_count_dialog (46); test_interaction i test_menu_mode – dwuklik/upuszczenie stosu przez okno ilości.

### 7.2 Szybkie klawisze i wybór magii (cz. 8)
`mw_quick_keys.gd`: QuickKeysMenu (GM_QuickKeysMenu, F1 przełącza; 380 × 224 + przyrost instrukcji, 10 pól, OK),
QuickKeysMenuAssign, ItemSelectionDialog (sQuickMenu6, Filter_OnlyUsableItems), MagicSelectionDialog (330 × 370,
SpellView bez kosztu – wspólny `spell_model()` z oknem magii). activateQuickKey: klawisze 1–9 i 0 poza trybem GUI,
po tworzeniu postaci, nie jako wilkołak; w trakcie ataku/powalenia – odroczenie do następnej klatki; sparaliżowany lub
martwy – nic; brak przedmiotu – „sQuickMenu5 nazwa”, zastępstwo findReplacement (najmniejszy dodatni stan); przedmiot –
użycie jak z ekwipunku i dobycie broni z prawej ręki, przedmiot magiczny – założenie i wybór jako magia, czar – wybór,
pole 10 – walka wręcz. Zapis: 9 pól w `state.player.quick_keys` (REC_KEYS). Test: test_quick_keys (41).
Brak: obsługa pada (mControllerFocus), ustawianie klawiszy w ustawieniach (zakładka sterowania – osobny punkt).

### 7.3 Podpowiedzi (cz. 9)
`mw_tooltips.gd` – ToolTips OpenMW dla przedmiotów (ItemModelIndex/ItemPtr) i czarów (Spell, SpellCost w zakupie
czarów): createToolTip (nagłówek z ikoną, tekst, efekty MW_EffectImage, zaklęcie z ładunkiem), getToolTipInfo
wszystkich klas przedmiotów, ToolTips::position, tylko w trybie GUI. Podpięte w siatkach przedmiotów (ekwipunek,
pojemnik, handel, alchemia, zaklinanie, naprawa, ładowanie), szybkich klawiszach, oknie magii i wyborze magii.
Test: test_tooltips (32). Do zrobienia: podpowiedzi układów (`Layout`: umiejętności, atrybuty, klasa, rasa, znak,
efekty magiczne, poziom, zdrowie, frakcja) – dziś tekst Godota; podpowiedź obiektów w świecie z ikoną (HUD).

### 7.4 Podpowiedzi układów (cz. 10)
Układy `openmw_tooltips.layout` (Text, Faction, Race, Specialization, Class, Health, Attribute, Skill z paskiem postępu
albo sSkillMaxReached, SkillNoProgress, Level, BirthSign, MagicEffect) i ToolTipInfo ikon działających efektów
(SpellIcons: źródła z wielkością). Podpięte: okno statystyk (wszystkie wiersze), HUD (paski, ikony efektów), okno
magii (ikony efektów), kreator (premie rasy, atrybuty w przeglądzie, czary), edytor efektu (MagicEffectToolTip),
zaklinanie (teksty pomocy), mapa (znaczniki). Test: test_tooltips (43). Podpowiedź obiektu w świecie z ikoną –
cz. 22 (punkt 7.16). Brak: HandToHandToolTip i Spell/ItemPtr na polach broni i czaru w HUD.

### 7.5 Więzienie i towarzysz (cz. 11)
Więzienie (`mw_jail_screen.gd`): World::goToJail w dwóch krokach (najpierw grzywna, przedmioty i GetPCInJail przy
otwartej rozmowie, przeniesienie po pierwszej klatce bez pauzy), GM_Jail z zaciemnieniem, przeniesieniem do
prisonmarker, oknem sInPrisonTitle z paskiem (100 kroków co 1/60 s), odpoczynkiem, upływem czasu, jailTimeServed
i oknem ReleasedFromPrison ze zmianami umiejętności. Towarzysz: sCompanionShare (zmienna lokalna „companion”),
GM_Companion z oknem 600 × 300, filtrem, paskiem obciążenia, zyskiem (minimumprofit, sProfitValue), ostrzeżeniem
przy ujemnym zysku, bez kradzieży; bez powitania – od razu okno. Testy: test_crime (36), test_companion (17).
Brak: zrzutowe porównanie z OpenMW obu okien (do zrobienia razem z pozostałymi oknami).

### 7.6 Konsola (cz. 12)
`mw_console.gd` jak Console OpenMW 0.51: klawisz „`” (A_Console; nie przy oknie z pytaniem, w wierszu poleceń też
zamyka), otwarta konsola = isConsoleMode, czyli tryb GUI (pauza, kursor, MenuMode = 1), Esc zamyka najpierw konsolę.
Okno wg [Windows] console (0,255; 0,215; 0,49 × 0,3125) i openmw_console.layout: historia (czcionka o stałej
szerokości, biała, 10000 znaków), pasek wyszukiwania (<, >, pole, Aa, .*), wiersz poleceń z fokusem. Polecenie:
echo „> …”, kompilacja `mw_mwscript_compiler.gd` – port parsera konwertera (tabela sygnatur generowana z konwertera,
`tools/gen_gd_mwscript_sig.py`; wektory `tests/data/mwscript_vectors.json` i wszystkie 1231 skryptów Morrowind/
Tribunal/Bloodmoon dają identyczne drzewa) ze zmiennymi lokalnymi wybranego obiektu, wykonanie w jego kontekście;
wynik funkcji #FF00FF, błędy #FF2222. Wybór kliknięciem w świat, tytuł „Console (refid)”, ponowne kliknięcie
odznacza. Historia: strzałki, bez powtórzeń z rzędu, console_history.txt (bufor 4096). Tab: listNames (słowa
kluczowe, funkcje, identyfikatory obiektów), Ctrl+W, Ctrl+U. Polecenia konsoli: coc (findInteriorPosition, potem
komórka zewnętrzna o tej nazwie), coe, tgm (bez obrażeń, upadku, kosztów kondycji i magii gracza), tcl (swobodny
ruch bez kolizji), tai, fillmap, tm, sv, help; ra/fixme i polecenia Lua zgłaszane jako nieobsługiwane.
Na prawdziwych danych (VM): otwarcie, pauza, MenuMode, GetHealth, coc do wnętrza Seyda Neen, wybór NPC
i GetDisposition, sv, coe −2 −9, fillmap, tgm – bez błędów. Test: test_console (74).
Brak: porównanie zrzutem z OpenMW, przełączniki grafiki (tcb, twf, tsky…).

### 7.7 Notatki na mapie (cz. 13)
CustomMarkerCollection i EditNoteDialog jak OpenMW 0.51: dwuklik na mapie lokalnej (onMapDoubleClicked) – nowa
notatka w klikniętym miejscu (komórka zewnętrzna punktu albo wnętrze, położenie w jednostkach MW); okno modalne
openmw_edit_note.layout (336 × 242 na środku, #{sEditNote}, pole wielowierszowe 303 × 150 z fokusem, przyciski
#{sDelete} – tylko przy edycji, OK, Cancel; Esc = Cancel). Dwuklik na znaczniku – edycja (updateMarker), usuwanie
z potwierdzeniem #{sDeleteNote}. Znacznik CustomMarkerButton (icons\map_marker_red.dds 16 × 16, nad mgłą, kolor
0,6 / 1,0 pod kursorem, podpowiedź TextToolTipOneLine) na mapie lokalnej i minimapie HUD (komórki siatki 3 × 3,
wnętrze – komórka). Podpowiedzi znaczników drzwi i miejsc mapy świata pokazują notatki komórki docelowej
(ToolTipInfo::notes: ikona 8 × 8 w kolorze (1; 0,3; 0,3), pierwszy wiersz do 60 znaków + „ ...”). Znaczniki drzwi
z textures\door_icon.dds 8 × 8 w kolorze normal / normal_over (wcześniej czerwony kwadrat 6 px). Zapis w stanie gracza
(odpowiednik REC_MARK). Pole tekstowe TextInputDialog (imię w kreatorze) było już zgodne (cz. kreatora).
Na prawdziwych danych (VM): okno notatki, znacznik z map_marker_red, znacznik drzwi z door_icon, minimapa – bez
błędów. Test: test_map_notes (44).

### 7.8 Okno opcji, przypisania klawiszy, autozapis (cz. 14)
`mw_settings_window.gd` przepisany na SettingsWindow OpenMW 0.51 (dotychczasowe okno z „Zapisz/Anuluj” i własnym
układem nie było zgodne): MW_Window #{OMWEngine:SettingsWindow} w trybie GM_Settings, 0,8 × 0,8 ekranu (min.
640 × 550), zakładki Prefs / Audio / Controls / Video (Video, Detail Level, Water), OK z fokusem, Esc; zmiany od
razu, zapis przy zamknięciu (ingame_settings.json; nowe klucze dodane do schematu launchera, żeby nie ginęły przy
scalaniu). Suwaki MW_HScroll z zakresem i stroną z układu, wartość min + (max − min) × poz. / (Range − 1), nagłówki
z wartością (DifficultyValue, ActorsProcessingRangeValue, FieldOfViewValue, ViewDistanceValueCells – format ICU),
podpisy skrajne; przełączniki On/Off. Nowe działające ustawienia: przezroczystość menu (tło wszystkich okien od razu,
jak setMenuTransparency), opóźnienie podpowiedzi (ToolTips::onFrame – odliczanie bez ruchu myszy), trudność
(combat.difficulty), zasięg przetwarzania aktorów, autozapis przed odpoczynkiem (WaitDialog::startWaiting →
quickSave("Autosave")), „Always Use Best Attack” (getBestAttack), celownik, odwrócenie osi X, czułość kamery
(0,2…5,0 × dotychczasowa czułość), tryb okna (Fullscreen / Windowed Fullscreen / Windowed – lista rozdzielczości
i ramka wg OpenMW), ramka okna, VSync Off/On/Adaptive, lista rozdzielczości (getResolutionText, potwierdzenie
ConfirmResolution), pole widzenia 30…110, odległość widzenia (suwak „Large” 2500…81920 j.; ustawienie portu
w metrach), shader wody (od razu). Sterowanie (BindingsManager): akcje w kolejności getActionKeySorting z opisami
GMST, nazwy przypisań (klawisz, „#{sMouse} N” w numeracji SDL), przypisywanie z komunikatem stałym RebindAction
(Esc anuluje, F3/F4/F10/Win zastrzeżone, klawisz zabierany innej akcji), Reset Controls z pytaniem, zapis
input_bindings.json (odpowiednik input_v3.xml). Komunikat stały: staticMessageBox/removeStaticMessageBox.
Usunięte z okna w grze (nie ma ich w OpenMW, zostają w launcherze): cienie, mgła, limit FPS.
Na prawdziwych danych (VM): okno w trybie GM_Settings, 29 akcji – wszystkie opisy i „sMouse” z GMST gry.
Pominięte (port ich nie obsługuje – bez atrap): przetwarzanie końcowe, gamma, filtrowanie tekstur, anizotropia,
szczegóły wody poza shaderem, Lights, Scripts (Lua), Language (język – launcher); pad i „Enable Controller” doszły
w cz. 16 (punkt 7.10).
Różnice: domyślne klawisze skoku/aktywacji portu (Spacja/E) zostały – OpenMW ma E/Spację. Test: test_settings (71,
poprzednio „Anuluj przywraca” – zachowanie spoza OpenMW).

### 7.9 Nawigacja klawiaturą (cz. 15)
`mw_keyboard_nav.gd` jak KeyboardNavigation OpenMW 0.51 (przed przekazaniem klawisza do GUI, tylko w trybie GUI):
Tab / Shift+Tab – następna / poprzednia kontrolka okna z zawinięciem, bez fokusu – pierwsza kontrolka okna modalnego
(albo wierzchnich okien); pola z AcceptTab (filtry ekwipunku, handlu, magii, towarzysza, wiersz konsoli) zachowują
Tab; strzałki tylko na przyciskach, bez zawinięcia i tylko w kierunku, w którym leży sąsiad; Enter / Enter
numeryczny / Spacja klikają przycisk z fokusem (powtórzenia klawisza pomijane); poza trybem GUI fokus zdejmowany.
Wbudowana nawigacja Godota (Tab, strzałki między przyciskami) wyłączona tam, gdzie OpenMW jej nie ma. Domyślny fokus:
okno z pytaniem – przycisk #{sOk}/#{sYes} (getDefaultKeyFocus), potwierdzenie – OK, opcje – OK; saveFocus/restoreFocus
trybu przy przykryciu i zdjęciu trybu. Test: test_keyboard_nav (25).

### 7.10 Pad (cz. 16)
`mw_gamepad.gd` jak ControllerManager OpenMW 0.51 ([GUI] controller menus = false – menu sterowane jak klawiaturą):
domyślne przypisania loadControllerDefaults (A aktywacja, X broń, Y magia, B tryb menu, Start menu gry, Guide
szybki zapis, LB dziennik, RB odpoczynek, wciśnięcie lewej gałki skradanie, prawy spust atak, lewy skok; lewa gałka
ruch ze strefą martwą 0,1), rozglądanie prawą gałką (MouseManager::update: oś × dt × 1000 × czułość / 256 rad,
odwrócenie osi X/Y). W trybie GUI (gamepadToGuiControl): krzyżak = strzałki, A = Spacja albo kliknięcie (kursor
pada), B = wyjście z okna modalnego / trybu, LB/RB = Shift+Tab/Tab, wciśnięcie lewej gałki – kursor pada, lewa gałka
przesuwa kursor (× dt × 1500 / skala × gamepad cursor speed, wolniej z prawym spustem), prawa – kółko; przyciski pada
w trybie GUI nie trafiają do akcji gry. „Enable Controller” w zakładce Controls (i w launcherze). Zmiana klawisza nie
usuwa przypisań pada (clearAllKeyBindings). Brak: przełącznik Mouse/Keyboard – Controller (zmiana przypisań pada),
„controller menus”, żyroskop. Test: test_gamepad (23).
Ekrany ładowania: zgodne od etapu 9/10 cz. 5 (LoadingScreen: tapeta co 5 s, zamrożona klatka, initialDelay 50 ms
minus postęp, etykieta „ważna”, położenie okienka); różnica – GM_Loading nie jest kładziony na stos trybów (port
czeka w czasie ekranu ładowania na postawienie gracza przez fizykę, której pauza trybu GUI by nie puściła).

### 7.11 Porównania nowych okien z OpenMW 720p/1440p/2160p (cz. 17)
Przypadki `tools/openmw-xvfb/ui_cases/ui_stage10_{720,1440,2160,2160_tabs}.json` na prawdziwych danych (VM:
oficjalny OpenMW 0.51 i port w Xvfb, ta sama komórka i ustawienia, [GUI] menu transparency = 1,0 w obu silnikach,
żeby porównywać zawartość okien bez tła sceny): szybkie klawisze (I.UI.setMode QuickKeysMenu), konsola (klawisz `),
okno opcji (Esc → „Options”) i jego zakładki Audio, Controls, Video (kliknięcia w nagłówku). Porównanie liczbowe
(bez publikowania zrzutów): `ui_geom_compare.py` (prostokąty okien), `ui_block_diff.py` (nowe: bloki 8 × 8 z różnicą
jasności lub gęstości krawędzi w prostokącie okna) oraz położenia linii ramek w wierszach i kolumnach.
`mwscript_compare.py` wpisuje rozdzielczość przypadku do settings.cfg OpenMW (bez niej OpenMW startował w 800 × 600)
i stosuje ustawienia przypadku („settings”); sonda portu (`probe_mwscript.gd`) obsługuje QuickKeysMenu, klawisz `
i – w przypadkach z krokami UI – naciska klawisze na tym samym zegarze rzeczywistym co kroki UI (przy 1440p/2160p
wolniejsze klatki przesuwały naciśnięcia względem zrzutów). Przy 2160p zapis zrzutu trwa ok. 7 s w każdym silniku,
dlatego zakładki opcji są osobnym przypadkiem z rozsuniętymi krokami.

Wyniki po poprawkach: prostokąty wszystkich okien zgodne co do piksela (IoU 1,000, przesunięcie 0 px) we wszystkich
trzech rozdzielczościach; linie ramek i suwaków identyczne (Preferences: 138/166/178…/600, Audio 170/186…, Controls,
Video – lista rozdzielczości 152/345, FOV 436/452; przy 1440p i 2160p tak samo w skali). Bloki różne
(720p): szybkie klawisze 3,7 % (glify napisów), konsola 5,7 %, opcje 5,2 %, Audio 4,1 %, Controls 10,8 %, Video 7,4 %
– pozostałe różnice to braki funkcji opisane niżej, napisy (glify, tytuł okna opcji) i tekst z `--script-run` w
historii konsoli OpenMW (narzędzie porównań, nie gra).

Znalezione i naprawione:

| Błąd | Przyczyna | Naprawa | Test |
|---|---|---|---|
| Menu główne widoczne przez okno opcji (przy przezroczystości 1,0 przyciski menu na stronie opcji) | warstwa opcji 26 pod warstwą menu 40; w OpenMW Settings leży nad MainMenu (openmw_layers.xml) | opcje 41; komunikaty i napisy (Notification) 45 – nad opcjami | test_ui_geometry („warstwy…”) |
| Okno opcji: zakładki od 136 zamiast 144, strona od 127 zamiast 138, suwaki 16 px zamiast 14, odstępy i dół strony inne | układ z kontenerów (VBox/HBox) zamiast pozycji z openmw_settings_window.layout | położenia bezwzględne z układu: klient MW_Window (8, 28), TabControl (8, 8) – nagłówek 24, MW_Box od 30, TabItem z wcięciem 4; przyciski zakładek = napis + 8 co + 4 (MW_Button_RightPadding); suwaki Prefs (4, 4 + 60k) z paskiem 14 px w y + 20, Audio (4, 4 + 50k) pasek 18 px w y + 24, przełączniki od (4, 250) co 30, Controls z elementami przy dolnej krawędzi (Δ = wys. strony − 369), Video: TabControlInner (strony od y = 28 bez ramki), lista (0, 4, 195, 225), prawa kolumna od x = 207, FOV w y = 238, Detail Level – suwak w y = 126 | test_ui_geometry (1280 × 720 i 3840 × 2160) |
| Przycisk OK i Reset Controls szersze niż w OpenMW (OK 56 zamiast 48 px) | stała szerokość z układu; w OpenMW to AutoSizedButton (napis + 24) | szerokość napis + 24, OK przy prawej krawędzi (ExpandDirection Left) | test_ui_geometry |
| Lista rozdzielczości z podwójną ramką | dodatkowa ramka wokół listy, która ma własną (MW_List) | bez dodatkowej ramki | porównanie (linie 152/345) |
| Nagłówki suwaków i etykiety Window Mode/VSync w kolorze „normal” | NormalText ma fontcolour=header | kolor header | porównanie |
| Szybkie klawisze: pola bez ramki | brak MW_Box_Overlay z MW_ItemIconBox | nakładka MW_Box na każdym polu | test_ui_geometry (10 nakładek) |
| Konsola: brak paska tytułu z bokami | tytuł jako zwykła etykieta | pasek MW_Window (UI.add_head) | porównanie |
| Konsola: pole wyszukiwania i wiersz poleceń 28 px z ramką na całą wysokość, przyciski szersze niż 28 px, pasek do prawej krawędzi | brak wymiarów z openmw_console.layout / MW_ConsoleCommand | przyciski 28 × 28 co 4, HBox (1, 0, szer. − 5), pola z MW_Box 26 px (linie 206, 345/369 jak OpenMW) | test_ui_geometry |
| Test pada: obrót prawą gałką „< 0,1 rad na klatkę” nie przechodził przy wolniejszej klatce (0,11–0,13) | test zależny od czasu klatki | test sprawdza wzór (oś × dt × 1000 × czułość / 256) dla dt tej klatki | test_gamepad |

Wykluczony fałszywy trop: ramka wokół historii konsoli – dodana w trakcie pracy, porównanie pokazało, że
MW_TextBoxEdit OpenMW nie ma ramki, więc została usunięta.

Braki funkcji widoczne w porównaniu (nie atrapy – port ich nie ma): zakładki Scripts i Language (nagłówek OpenMW ma
6 zakładek), Lights i Shadows w Video, przełącznik „mouse emulation cursor” (Prefs), przetwarzanie końcowe i gamma
(Video), filtrowanie tekstur i anizotropia (Detail Level), przełącznik Mouse/Keyboard – Controller nad listą
przypisań; na liście przypisań brak akcji, których port nie obsługuje: widok z trzeciej osoby (TogglePOV), zbliżenie
kamery, stały bieg (AlwaysRun), automatyczny ruch, poprzedni/następny czar i broń, zrzut ekranu, HUD przetwarzania
końcowego. Tytuł okna opcji OpenMW zajmuje szerszy pasek (ok. 130 px zamiast 85 px) – przyczyna ustalona i usunięta
w cz. 18 (punkt 7.12: tekst z GMST sOptions).

### 7.12 Teksty silnika z GMST, zakładka Language, przełącznik pada w Controls (cz. 18)
**Teksty silnika z GMST („gmst overrides l10n”).** Przyczyna szerszego tytułu okna opcji: OpenMW 0.51 z danymi
Morrowinda ma udawany język „gmst” (`resources/vfs-mw/l10n/<kontekst>/gmst.yaml`: SettingsWindow = sOptions,
Preferences = sPrefs, OK = sOK, Audio = sAudio, ConsoleWindow = sConsoleTitle, DifficultyValue = „{gmst:sDifficulty}
({value})”, ReleasedFromPrison z formą plural…), a przy domyślnym [General] gmst overrides l10n = true stoi on przed
preferowanymi językami (l10n::Manager::setPreferredLocales). Teksty silnika pochodzą więc z GMST danych gry, nie
z en.yaml. Na danych użytkownika sOptions ma 12 znaków i różni się od „Options” z en.yaml (porównane tylko długość
i równość, bez wypisywania tekstu); pozostałe sprawdzone GMST okna opcji są równe tekstom en.yaml. Port używał
wyłącznie en.yaml. Naprawa: `mw_l10n.gd` ładuje gmst.yaml (wpis prosty = identyfikator GMST, mapa {pattern,
variables} – tokeny {gmst:…} i zamiana %s/%d na {zmienna} jak GmstFormatParser), kolejność „gmst” przed / po językach
wg ustawienia, wyszukiwanie GMST przez dialog (z warstwą tłumaczeń danych), formy ICU plural/select. Dodane konteksty
Interface (files/data/l10n/Interface) i Mechanics. Różnica: przy braku rekordu GMST OpenMW wypisuje „GMST:id”, port
bierze następny język (z prawdziwym Morrowind.esm wszystkie GMST istnieją; dane syntetyczne testów ich nie mają).
Po poprawce tytuł okna opcji zgodny z OpenMW co do kolumn glifów (720p).

**Zakładka Language** (openmw_settings_window.layout): uwaga LanguageNote, Primary / Secondary Language (MW_ComboBox
250 × 24 w (4, 52) i (262, 52), języki z nazw plików l10n poza „gmst”, druga lista z „None”), przełącznik „Strings
From ESM Files Have Priority” (gmst overrides l10n). Zmiana pokazuje okno ChangeRequiresRestart i zapisuje
preferred_locales / gmst_overrides_l10n (nowe klucze w schemacie launchera); teksty zmieniają się po ponownym
uruchomieniu jak w OpenMW (wcześniej preferred_locales było ustawiane przed wczytaniem ustawień z gry). Nazwy języków
po angielsku (TranslationServer) – OpenMW podaje je w języku głównym (ICU getDisplayName). Zakładki Scripts nadal brak,
więc Language jest piątą zakładką (w OpenMW szóstą).

**Mouse/Keyboard – Controller** (HBox (4, 4) nad listą przypisań, onKeyboardSwitchClicked / onControllerSwitchClicked):
lista pada w kolejności getActionControllerSorting (akcje obsługiwane przez port), nazwy sdlControllerButtonToString
/ sdlControllerAxisToString („A Button”, „Right Trigger”…), ruch z osi (A_MoveForwardBackward) – „None” jak w OpenMW;
przypisywanie: przycisk pada albo spust (wychylenie > 0,5), klawiatura i mysz pomijane, Esc przerywa, przycisk/oś
zabierane innej akcji; Reset Controls w trybie pada – resetToDefaultControllerBindings; zapis w input_bindings.json
(„controller”). loadControllerDefaults jak w OpenMW: domyślne tylko dla akcji bez przypisania i gdy przycisk nie jest
zajęty (wcześniej domyślny przycisk dodawany zawsze).

Znalezione i naprawione przy porównaniu (720p, potwierdzone 1440p/2160p):

| Błąd | Przyczyna | Naprawa | Test |
|---|---|---|---|
| Teksty silnika z en.yaml zamiast GMST (tytuł okna opcji szerszy w OpenMW) | brak języka „gmst” (vfs-mw/l10n) | punkt wyżej | test_language (7 sprawdzeń gmst) |
| Listy rozwijane (Window Mode, VSync, języki, zapis, alchemia) w ramce przycisku | OptionButton w skórce MW_Button | MW_ComboBox: MW_Box, tekst od x = 6, strzałka omw_menu_scroll_down 14 × 11, 7 px od prawej | porównanie (linie 194/216) |
| Napisy NormalText/SandText 2–3 px za wysoko | TextAlign „Left Bottom” w skórkach – port wyrównywał do góry | wyrównanie do dołu pola | porównanie (Audio: 0,8 % bloków) |
| Przełączniki On/Off i lista VSync 2 px za wysoko | MyGUI HBox wyśrodkowuje element 24 px w wierszu 28/32 px | wyśrodkowanie (autozapis y = 252, VSync y = 76) | test_ui_geometry, porównanie (394/414) |
| Domyślne przyciski pada dopisywane mimo innego przypisania | register_defaults bez warunku isJoystickButtonBound | jak loadControllerDefaults(false) | test_settings, test_gamepad |
| Gra uruchomiona z launchera kończyła się kodem 6 („corrupted size vs. prev_size in fastbins”) – wykryte w pełnym zestawie (test_launcher, prawdziwy Godot) po dodaniu języka „gmst” | wyszukiwanie GMST zapisane w zmiennej statycznej skryptu jako lambda trzymająca scenę główną; zmienna statyczna żyje dłużej niż scena | wywołanie metody obiektu dialogu (Callable z bind) i czyszczenie przy usuwaniu sceny | test_launcher (test_real_godot_game_and_editor, 2 powtórzenia przed – błąd, po – zaliczony) |

Wyniki (prostokąty okien IoU 1,000 i przesunięcie 0 px we wszystkich przypadkach; bloki różne): 720p – opcje 2,0 %,
Audio 0,8 %, Controls 6,9 % (brakujące akcje), Video 3,6 % (Lights/Shadows, gamma, przetwarzanie końcowe), Language
1,6 %; 1440p – 0,5 / 0,2 / 3,3 / 1,5 / 0,3 %; 2160p – Audio 1,1 %, Controls 2,5 %, Video 1,8 %, Language 1,1 %.
Testy: test_settings (90), test_language (45), test_ui_geometry (129), test_gamepad (23).

### 7.13 Dodatki: Tribunal i Bloodmoon (§12, cz. 19)
Przypadki `ui_tribunal_720` (Mournhold Temple: Reception Area) i `ui_bloodmoon_720` (Raven Rock, Bar) na danych
z Morrowind.esm + Tribunal.esm + Bloodmoon.esm: HUD z minimapą, tryb Interface (statystyki, ekwipunek, magia,
mapa lokalna wnętrza dodatku), dziennik, szybkie klawisze; teleport na pierwszy punkt siatki ścieżek komórki.
Dla porównania ten sam zestaw w Arrille's Tradehouse (`ui_windows_720`, obejmuje też okna kreatora).
Dane do porównań konwertowane teraz z `--openmw-cfg` (fallbacki jak w OpenMW): bez nich world/fallbacks.json był
pusty i kreator nie pokazywał opcji pytań (różnica danych testowych, nie gry).

Wyniki: prostokąty okien jak w Morrowindzie (dziennik, szybkie klawisze, statystyki, ekwipunek IoU 1,000; okno
magii 0,979 – linie ramek identyczne, detektor dokleja tło sceny, jak w etapie 7); bloki różne w dodatkach na
poziomie Arrille's (np. dziennik 2,7 %, szybkie klawisze 3,7 %), więc bez różnic właściwych dla dodatków.
W Bloodmoonie detektor łączy mapę z jaśniejszą sceną 3D za oknem (oświetlenie wnętrza – nie interfejs).

Znalezione i naprawione (wszystkie dotyczyły także Morrowinda):

| Błąd | Przyczyna | Naprawa | Test |
|---|---|---|---|
| Mapa lokalna: brak znaczników drzwi w nieodkrytej części (Mournhold: OpenMW 4, port 0) | port pomijał drzwi pod mgłą; w OpenMW (LocalMapBase::updateDoorMarkers) znaczniki są zawsze, a podpowiedź tylko w odkrytej części (ToolTips: isPositionExplored) | znaczniki zawsze, podpowiedź tylko w odkrytej części | test_map |
| Mapa lokalna w oknie mapy w skali o połowę za małej (drzwi ±22 zamiast ±40 px od gracza) | segment 256 px; OpenMW: getWidgetSize = zoom 1 × [Map] local map widget size = 512 (HUD: zoom 0,5 = 256) | segment 512 px w oknie mapy | test_map; porównanie: znaczniki w miejscach OpenMW |
| Minimapa HUD bez znaczników drzwi | brak updateDoorMarkers w HUD (HudWindow to LocalMapBase) | znaczniki door_icon 8 × 8 na minimapie | test_map_notes |
| Minimapa HUD z mgłą | OpenMW: [Map] local map hud fog of war = false | minimapa bez mgły (ustawienie hud_fog_of_war) | test_map |
| Paski przewijania MW_ScrollView przy samej krawędzi (statystyki, przegląd w kreatorze, lista przypisań) 4 px za daleko w prawo | Godot kładzie pasek przy krawędzi, skórka MW_ScrollView ma VScroll w (szer. − 18, 3) | `UI.mw_scroll_view` – margines 4 px z prawej (linie 527/539 i 876/888 jak OpenMW) | test_ui_geometry |
| Wartości umiejętności w statystykach 6–10 px za daleko w lewo; w przeglądzie kreatora szerszy widok przesuwał pasek | dopełnienie 12 px; OpenMW: wartość do W − 24 (addSkills); płótno przeglądu szersze od widoku | dopełnienie wg W − 24, płótno do krawędzi paska | test_ui_geometry (W − 24) |
| test_progress raz nie przeszedł w pełnym zestawie (sen do 10 h zamiast przerwania po 3 h) | test zależny od długości klatki: TimeAdvancer (jak w OpenMW) sprawdza przerwanie raz na klatkę, a jedna wolna klatka przechodziła kilka godzin | test prowadzi okno klatkami o stałym dt = 1/60 s (logika okna bez zmian) | test_progress (4 powtórzenia) |
| ClassChoiceDialog 2 × 2 px za mały | fitToText przycisku: napis + 8 (port + 6), okno: 10 + … + 10 (port + 8) | wymiary jak InfoBoxDialog (ramka 454…823 × 287…431 jak OpenMW) | test_ui_geometry |

Pozostało: HUD 1 px niżej niż w OpenMW – przyczyna ustalona i usunięta w cz. 22 (układ HUD sprzed 0.51,
punkt 7.16); górne 3 px paska
MW_ScrollView (Godot przesunąłby też treść). Mapa lokalna wnętrz w OpenMW na Xvfb jest czarna (poza znacznikami)
także w odkrytej części, więc obrazu mapy nie porównano – tylko położenia znaczników. Mody: nie sprawdzone
w tej części (punkt 7.15).

### 7.14 Samoczynny obrót kamery po wczytaniu gry (zgłoszenie, cz. 20)
**Objaw:** po wczytaniu zapisu kamera obraca się sama i trzeba ręcznie przeciwdziałać.

**Sprawdzone:** przywracanie orientacji z zapisu (`_apply_state`: odchylenie gracza i pochylenie kamery – raz,
poprawnie), mysz (jedyna ścieżka obrotu: `mw_player_controller._unhandled_input`, tylko w trybie przechwyconym,
bez podwójnego przetwarzania – inne skrypty z InputEventMouseMotion tylko przeciągają okna), skrypty (Rotate pomija
gracza, Position/SetAngle ustawiają kąt raz), AI (gracz nie jest na liście aktorów AI), przejścia GUI ↔ gra i wczytanie
z menu, utrata fokusu (Godot zwalnia klawisze; osie pada zostają). Jedyne źródło obrotu ciągłego bez udziału
gracza to prawa gałka w `mw_gamepad.gd` (cz. 16).

**Przyczyna:** port czytał osie urządzenia nr 0 (`Input.get_joy_axis(0, …)`), gdy tylko Godot zgłaszał jakiekolwiek
urządzenie „joypad”, a zdarzenia pada w akcjach miały urządzenie „wszystkie”. Godot zgłasza także urządzenia, które
nie są kontrolerami gry (nierozpoznane pady, czujniki położenia, część klawiatur/myszy z osiami) – ich osie
w spoczynku mają wartości ≠ 0 (np. −1), poza strefą martwą 0,1, więc prawa gałka „była wychylona” bez przerwy.
OpenMW otwiera tylko urządzenia rozpoznane jako kontroler gry (SDL_IsGameController – z mapowaniem), więc takie
urządzenia nie sterują grą. Dodatkowo „Enable Controller = Off” nie wyłączał akcji z pada (Godot ustawia stan akcji
przed wywołaniem `_input`).

**Naprawa (bez wyłączania obrotu i bez opóźnień):** aktywny pad to pierwszy rozpoznany kontroler gry
(`Input.is_joy_known`); zdarzenia pada we wszystkich akcjach gry są wiązane z tym urządzeniem (bez pada albo przy
„Enable Controller = Off” – z nieistniejącym urządzeniem), także po zmianie przypisań i przy podłączeniu/odłączeniu
(`joy_connection_changed`); prawa gałka, kursor pada i przyciski w GUI – tylko z aktywnego urządzenia.

**Diagnostyka:** `mw_look_diag.gd` co klatkę rozdziela zmianę odchylenia i pochylenia na źródła „mouse”, „pad”
(z osiami i urządzeniem), „script”, „state” (wczytanie, podróż) i resztę „other” (logika kamery, fizyka). Z argumentem
`--look-diag` (np. w polu dodatkowych argumentów launchera) gra wypisuje co sekundę `MWGODOT_LOOK …` ze sumami źródeł
i listą urządzeń pada (nazwa, rozpoznane, osie) – pozwala potwierdzić źródło na komputerze użytkownika.

**Test regresji `test_look_stability.gd` (25):** wczytanie w trakcie gry i z menu głównego, zapis we wnętrzu i na
zewnątrz – 90 klatek bez wejścia: orientacja z zapisu i zero klatek z obrotem; bez pada; urządzenie spoza kontrolerów
gry z osiami −1 (bez obrotu i bez ruchu gracza); rozpoznany pad z gałkami w spoczynku i w strefie martwej; „Enable
Controller” wyłączone przy wychylonej gałce; powrót z GUI; diagnostyka przypisuje obrót z pada do „pad”, a obrót bez
źródła do „other”. test_gamepad (26): wybór pada, wiązanie zdarzeń z urządzeniem. Ograniczenie: mysz w trybie
przechwyconym nie jest dostępna w trybie headless (ścieżka myszy sprawdzona kodem i diagnostyką); urządzeń
wejściowych komputera użytkownika nie mam z maszyny wirtualnej – potwierdzenie źródła na jego sprzęcie: `--look-diag`.

### 7.15 Glitche przy wczytywaniu zapisu (P0, cz. 21)

**Zbadane** (main.gd): `load_slot`, `load_game`, `_apply_state`, `travel`/`travel_to_cell`, `_begin_reveal`/
`_update_reveal`, `cleanup`, start z `--load`, ekran ładowania (`mw_loading_screen.gd`), HUD, ScreenFader, pogoda,
porównane z `StateManager::loadGame`, `LoadingScreen::loadingOn/Off`, `Scene::changeToCell`, `WeatherManager`.
Sonda `tests/probe_loadgame.gd` zapisuje każdą narysowaną klatkę (także rysowaną przez ekran ładowania w trakcie
synchronicznego wczytania) i za błąd uznaje klatkę pokazaną graczowi (bez zasłony ekranu ładowania), w której:
obraz różni się od ustalonego (> 0,06), kamera jest gdzie indziej (> 5 cm), liczba komórek jest inna, gracz wisi
nad ustaloną pozycją (> 25 cm), nie ma HUD-u, pogoda (bieżąca/następna) jest inna albo w drzewie są węzły komórek
spoza `loaded` (duplikaty). Aktorzy zamrożeni na czas pomiaru (ruch NPC to nie błąd wczytania).

**Przyczyny (wszystkie potwierdzone sondą przed poprawką):**

| Objaw | Przyczyna | Naprawa |
|---|---|---|
| Start z `--load` zapisu we wnętrzu: geometria i aktorzy podwójnie, migotanie (z-fighting) do końca sesji | `_ready` po `load_game` wywoływało drugi raz `_load` tej samej komórki (stara ścieżka startu `--cell`); `_begin_reveal` w tej ścieżce nie było – świat pokazywany bez ekranu ładowania | start z `--load` przez `load_slot` – ta sama ścieżka co z menu (Engine::go → StateManager::loadGame) |
| Pierwsza klatka po zdjęciu ekranu ładowania bez HUD (każde wczytanie i każde przejście) | HUD ustalał widoczność w `_process` przed `loading_off` w tej samej klatce | `loading_off` odświeża HUD i minimapę od razu (WindowManager::updateVisible przy GM_Loading) |
| Wczytanie w trakcie gry: zamrożona klatka poprzedniej gry na ekranie ładowania, potem nowy świat | OpenMW wywołuje `cleanup()` (State_NoGame) przed ScopedLoad – ekran ładowania z tapetą; port – przed cleanup | `cleanup()` i stan „bez gry” przed `loading_on` |
| Ekran ładowania w trakcie wczytania czasem zmieniał tryb (tapeta → zamrożona klatka) | zagnieżdżone `loading_on` liczyło tryb od nowa, gdy ekranu jeszcze nie narysowano (OpenMW: `if (mNestedLoadingCount++ > 0) return;`) | zagnieżdżone wywołanie nie zmienia trybu (wykryte testem regresji – 2 z 3 przebiegów) |
| Po wczytaniu niebo, mgła, światło zmieniały się przez wiele sekund | pogoda nie była zapisywana: trwało przejście od pogody poprzedniej sesji | stan pogody w zapisie (WeatherManager::write/readRecord: bieżąca, następna, w kolejce, mTransitionFactor, czas do zmiany, region); stary zapis – pogoda regionu od razu |

Bez sztucznych opóźnień i bez wydłużania czarnego ekranu: ekran ładowania znika w tej samej klatce co wcześniej
(`reveal_frames` 1–2 na danych syntetycznych, 2–8 na danych gry). Zachowane: odsłanianie po gotowości pierwszej
klatki (cz. 5) i limit 240 klatek; kamera, Jolt i postawienie gracza – w sondzie bez odchyleń (OpenMW przy
wczytaniu też nie poprawia pozycji – changeToCell(adjustPlayerPos = false)).

**Pomiary (klatki z niekompletnym światem pokazane graczowi, przed → po):**

| Scenariusz | Dane gry, VM, gl_compatibility 1280 × 720 | 3440 × 1440 (dane gry) | Dane syntetyczne, lavapipe Forward+ 1280 × 720 | 3440 × 1440 Forward+ |
|---|---|---|---|---|
| wczytanie w grze – zapis zewnętrzny (Seyda Neen, 6 komórek, wielu NPC) | 1 → 0 | 1 → 0 | 1 → 0 | → 0 |
| wczytanie w grze – wnętrze (Census and Excise Office) | 1 → 0 | 1 → 0 | 1 → 0 | → 0 |
| ten sam zapis ponownie | 1 → 0 | – | 1 → 0 | → 0 |
| inny zapis bez restartu | 1 → 0 | – | 1 → 0 | → 0 |
| z menu głównego w trakcie gry (wnętrze / zewnątrz) | 1+1 → 0 | – | 1+1 → 0 | → 0 |
| z menu głównego bez gry | 1 → 0 | – | 1 → 0 | → 0 |
| po podróży między komórkami | 1 → 0 | – | 1 → 0 | → 0 |
| start z `--load` (wnętrze) | 44 → 0 (duplikat komórki w każdej klatce, bez ekranu ładowania) | zewnątrz: → 0 | 49 → 0 | – |

Kolumna „3440 × 1440 Forward+” – przebieg po poprawce na danych syntetycznych (lavapipe, Vulkan, domyślny
renderer projektu): 8 scenariuszy, 0 złych klatek. **Ograniczenie:** VM nie ma Vulkana (renderer zgodności), a lavapipe kompiluje potoki inaczej niż sterownik
GPU – pełnego potwierdzenia na karcie i monitorze użytkownika stąd nie da się zrobić. Do lokalnego potwierdzenia
(Forward+, 3440 × 1440): `godot --path godot --resolution 3440x1440 -s res://tests/probe_loadgame.gd -- --data=<dane>
--start="Seyda Neen" --interior="Seyda Neen, Census and Excise Office" --out=/tmp/lg --size=3440x1440` (wynik
`RESULT … bad_visible_frames`, zrzuty klatek tylko lokalnie z `--png=1`).

Test regresji `test_load_reveal.gd` (59) w `run_tests.sh`: wczytanie w grze (świat, wnętrze, ten sam zapis, stary
zapis bez pogody), z menu bez gry, start z `--load`: tapeta na ekranie ładowania, odsłanianie, brak duplikatów komórek,
HUD w klatce zdjęcia ekranu, pogoda z zapisu (w trakcie przejścia), stary zapis – bez przejścia.

### 7.16 Audyt GUI wobec OpenMW 0.51 – 3440 × 1440 i zachowanie (cz. 22–23)

Porównania na tych samych danych (Morrowind + Tribunal + Bloodmoon, konwersja z `--openmw-cfg`) w Xvfb: OpenMW
0.51.0 (oficjalne wydanie) i port (renderer zgodności). Metryki: prostokąty okien (ui_geom_compare – IoU), linie
ramek (wiersze/kolumny maski ramek), mapy krawędzi bloków 8 px (ui_block_diff) i mapy gęstości krawędzi obszarów
(ocena wizualna w postaci liczbowej – zrzutów z danymi gry nie przenoszę poza VM; zostają lokalnie w `/tmp/uicmp*`
na VM do obejrzenia). Każdą różnicę bloków sprawdziłem do przyczyny – „IoU 1,000” okna nie kończył sprawdzania.

**Macierz porównań:** 720p, 1440p, 2160p – części 17–19 (opcje, konsola, szybkie klawisze, HUD, tryb menu,
dziennik, kreator, dodatki); 1080p – etapy 8–9 (rozmowa, handel, pojemnik, odpoczynek, usługi, alchemia,
zaklinanie, awans, naprawa, perswazja, komunikaty, menu główne); **3440 × 1440 (21:9) – nowe przypadki `*_3440`:**
`ui_windows_3440` (HUD, Interface: statystyki/ekwipunek/magia/mapa, dziennik, 6 okien kreatora), `ui_stage10_3440`
(szybkie klawisze, konsola, opcje: 5 zakładek), `ui_windows_e8_3440` (HUD z podpowiedzią obiektu, odpoczynek,
rozmowa, handel, pojemnik, menu główne), `ui_services_e8_3440` (trening, zakup zaklęć, podróż),
`ui_messagebox_e9_3440` (komunikaty), `ui_levelup_e9_3440`, `ui_alchemy_e9_3440`, `ui_enchanting_e9_3440`
(zaklinanie, tworzenie czarów), `ui_repair_e9_3440` (naprawa młotkiem, naprawa u kupca); `ui_mainmenu_e8_3440` –
w repozytorium, menu główne porównane w `ui_windows_e8_3440`.

**Wyniki 3440 × 1440 (bloki różne – po poprawkach):**

| Zrzut | Okna (IoU) | Bloki | Pozostałe obszary różnic |
|---|---|---|---|
| HUD | – | 0,4 % (było 0,6) | scena 3D (jasność oświetlenia, mapa lokalna wnętrza w OpenMW czarna pod Xvfb) |
| Interface (4 okna) | 1,000 × 4 | 2,1 % (2,8) | podgląd postaci 3D w ekwipunku (oświetlenie modelu) |
| dziennik | 0,997 | 1,3 % | tekst strony (rasteryzacja czcionki księgi), księga teraz od x 936 jak OpenMW |
| kreator (imię, rasa) | 1,000 | 0,3 / 0,7 % | podgląd głowy 3D |
| kreator (klasa, wybór, znak, przegląd) | okno porównywane liniami ramek: zgodne | – | OpenMW przy przełączaniu trybów sondą zostawia okno rasy pod spodem (w zwykłej grze znika po OK) |
| szybkie klawisze, konsola | 1,000 | 0,4 % | scena |
| opcje (5 zakładek) | 1,000 | 0,5–1,1 % (1,3–2,7) | zakładka Scripts w OpenMW (brak w porcie), Controls – brakujące akcje, Video – brakujące ustawienia |
| odpoczynek | 0,974 → ramki zgodne | 0,4 % (0,5) | rasteryzacja glifów 1 px |
| rozmowa | 1,000 | 0,6 % | zawijanie i rasteryzacja tekstu |
| handel | 1,000 × 2 | 2,5 % (2,7) | **lista towarów kupca w innej kolejności/składzie** (do zbadania), podgląd postaci |
| pojemnik | 1,000 × 2 | 1,2 % | podgląd postaci |
| trening / zakup zaklęć / podróż | 1,000 | 0,4–0,5 % | przycisk teraz tekst + 24 (był ≥ 60) |
| komunikaty | – | 0,5 % | scena |
| awans | 1,000 × 2 | 0,5 % | scena |
| alchemia | 1,000 | 0,3 % | scena |
| zaklinanie / tworzenie czarów | 1,000 / 1,000 | 0,3 / 0,3 % | scena |
| naprawa / naprawa u kupca | 1,000 / 1,000 | 0,4 / 0,3 % | wiersz nazwy narzędzia i pole przycisku w naprawie (27 i 15 bloków – do sprawdzenia) |

**Wykryte i naprawione (cz. 22–23):**

| Różnica | Przyczyna | Naprawa | Test |
|---|---|---|---|
| Słabe pionowe linie co ~546 px w tle szerokich okien (opcje, ekwipunek, handel; najwyraźniej w 21:9) | ramki MW_Window jako StyleBoxTexture w trybie TILE_FIT: kafel skalowany, filtr liniowy próbkował ramkę; MyGUI TileRect kafelkuje bez skalowania | tryb TILE (jak TileRect) – też wierniejszy wzór krawędzi | porównanie: kolumny z liniami 12 → 2 (krawędzie), opcje 1,5 % → 0,6 % |
| HUD 1 px niżej i w lewo (zgłoszone wcześniej jako „HUD 1 px niżej przy 720p”) | port wg układu sprzed 0.51 (12, 147) | openmw_hud.layout 0.51: paski (13, 146/161/176), broń 82, czar 122, skradanie 162, minimapa y 123, efekty y 168 | test_ui_geometry (155, w tym 3440 × 1440); linie ramek identyczne |
| Celownik większy | 32 × 32 zamiast 27 × 27 (HUD_Crosshair) | 27 × 27 w ((szer. − 27) / 2, (wys. − 27) / 2) | test_ui_geometry |
| Dziennik i księgi 1 px w prawo (21:9) | środek liczony w pikselach; OpenMW – WindowBase::center w jednostkach ScalingLayer i przeskalowanie ProxyRenderTarget | `UI.book_origin` | test_ui_geometry (4 rozdzielczości) |
| Podpowiedź obiektu w świecie: jeden wiersz pod celownikiem; w OpenMW pełna podpowiedź nad obiektem (u góry ekranu, gdy obiekt wychodzi poza ekran) | brak odpowiednika ToolTips::update poza trybem GUI | getToolTipViaPtr dla obiektu pod celownikiem (przedmiot z ikoną, wagą, wartością; drzwi „to” + cel; zamek, pułapka; aktor – nazwa, w walce bez podpowiedzi) w położeniu getScreenCoords | test_tooltips (50); zrzut: ramka co do piksela |
| Podpowiedzi o 5 px za wysokie | nagłówek 18 px, tekst z minimalnego rozmiaru etykiety; MyGUI: getTextSize = wiersze × 16 | wiersze × 16 px | test_tooltips |
| Okno odpoczynku: teksty przy lewej krawędzi | VBox::align środkuje dzieci bez HStretch | wyśrodkowane | zrzut |
| Przyciski w wierszach HBox (handel, pojemnik, okno ilości, notatka, odpoczynek) 1–3 px za wysoko i 1 px niższe | przycisk 23 px u góry wiersza; AutoSizedButton = tekst + (24, 8), HBox środkuje w pionie | `UI.auto_button_row`: 24 px, wyśrodkowane | test_trade, test_count_dialog, test_map_notes; zrzut: linie przycisków handlu i pojemnika |
| Przycisk usług (trening, zaklęcia, podróż, naprawa) za szeroki | szerokość ≥ 60 | tekst + 24 (AutoSizedButton, ExpandDirection Left) | zrzut: krawędzie przycisków jak OpenMW |
| **Przenoszenie przedmiotów jak w Godocie** (przytrzymaj i przeciągnij, dwuklik – użyj) | przeciąganie Godota | DragAndDrop OpenMW – punkt niżej | test_count_dialog (59) |

**Zachowanie (C):**
* przenoszenie przedmiotów – teraz jak `draganddrop.cpp`/`InventoryWindow::onItemSelected`: kliknięcie podnosi
  (okno ilości przy stosie, Ctrl – 1, Shift – cały stos, Alt – przełożenie), z pojemnika przedmiot trafia do
  ekwipunku od razu (startDrag), założony jest zdejmowany, ikona 42 × 42 z liczbą przy kursorze, podniesiona liczba
  znika z siatki, kliknięcie odkłada (ekwipunek, pojemnik, postać – użyj/załóż, poza oknami – na ziemię),
  zamknięcie okna zostawia przedmiot w ekwipunku. Handel, alchemia i wybór przedmiotu działają kliknięciami jak w
  OpenMW (tam też bez przenoszenia);
* klawiatura, Tab/Enter/Esc/strzałki, pad, fokus, stos trybów, pauza, położenie okien – cz. 1, 9, 14–16, 20
  (testy); rozdzielczość 21:9: okna trybu menu z ułamków [Windows] (test_ui_geometry dla 3440 × 1440);
* **nie sprawdzone w tej części:** przełączanie pełny ekran ↔ okno i zmiana rozdzielczości w trakcie gry na
  21:9 z porównaniem do OpenMW, podpowiedzi przy krawędziach ekranu w 21:9, przewijanie list rozwijanych, ekran
  ładowania OpenMW w 21:9 (port: tapeta 4:3 z czarnymi pasami jak BackgroundImage bez [GUI] stretch menu
  background – zgodnie z kodem, bez zrzutu OpenMW).

**Brakujące funkcje (stan rzeczywisty, nie „zgodne”):** akcje sterowania TogglePOV, zoom kamery, AlwaysRun,
AutoMove, Cycle* (broń/czar), Screenshot; ustawienia: zakładka Scripts (Lua), Lights, Shadows, gamma,
przetwarzanie końcowe, filtrowanie tekstur, mouse emulation cursor, [GUI] stretch menu background; konsola bez Lua
i bez przełączników grafiki (tcb, twf, tsky…); pasek zdrowia wroga w HUD; kursor gry (tx_cursor); skórka
„Owned” podpowiedzi i kolor celownika dla cudzych rzeczy ([Game] show owned – w OpenMW domyślnie wyłączone).

### 7.17 Ekran ładowania na sprzęcie użytkownika i lista towarów kupca (cz. 24–25)

**Ekran ładowania – „nie ma ekranu ładowania, tylko glicze” (zgłoszenie po cz. 23).** Pomiar na komputerze
użytkownika (RTX 5090, Vulkan Forward+, 3440 × 1440 pełny ekran, prawdziwe dane Morrowind + Tribunal + Bloodmoon,
kopia zapisu `test.mwsave`), gra uruchamiana przez moduł MCP Godota z `--load-diag` i `--diag-menu-load` (ta sama
ścieżka co wybór zapisu w oknie wczytywania: `close_main_menu` → `load_slot`). Diagnostyka zapisuje co klatkę
tylko liczby: czas klatki, kompilacje potoków, obiekty/wywołania rysowania, komórki, zasłonę, HUD oraz – z odczytu
obrazu – sygnaturę 8 × 4 średnich jasności i jasność pasów lewy/środek/prawy (bez zrzutów, obraz gry nie opuszcza
komputera).

| Klatki wczytania z menu (12 zasłoniętych) | Przed | Po |
|---|---|---|
| klatka 0 (tuż po `loading_on`) | menu główne | tapeta + okienko |
| klatki 1–9 (komórki 1…9 budowane w trakcie `load_game`) | **budowany świat** – sygnatura zmienia się z każdą komórką | tapeta + okienko (sygnatura stała) |
| klatki 10–11 (odsłanianie, `nested` = 1) | tapeta | tapeta |
| klatka 12 (zdjęcie ekranu) | świat + HUD | świat + HUD |

**Przyczyna:** wczytanie jest synchroniczne, a klatki ekranu ładowania rysuje `RenderingServer.force_draw`
(jak OpenMW `LoadingScreen::draw`). Kontrolki Godota rysują się jednak dopiero przy opróżnieniu kolejki komunikatów
na końcu klatki (`CanvasItem::queue_redraw` → `call_deferred`) – nowo zbudowany ekran ładowania, zmieniona tapeta,
etykieta i pasek nie miały w tych klatkach żadnych poleceń rysowania. Ekran był niewidoczny, a pod nim gracz widział
menu i świat budowany komórka po komórce. Potwierdzone także minimalnym projektem (lavapipe): nowa `ColorRect` po
`force_draw` – brak, prostokąt dodany przez `RenderingServer.canvas_item_add_rect` – od razu.
Wcześniejsze sondy (cz. 21) tego nie wykryły, bo w nich ekran ładowania był już zbudowany i narysowany w zwykłej
klatce wcześniej w sesji, a z launchera (menu główne od startu) jest budowany przy pierwszym wczytaniu.

**Naprawa** (`mw_loading_screen.gd`): obraz ekranu ładowania składany wprost w RenderingServer (`_render()`:
czarne tło, tapeta 4:3 albo zamrożona klatka, okienko MW_Box z etykietą i paskiem – z tych samych stylów i układu
co dotąd). Drzewo kontrolek zostaje dla układu i testów, ale jest przezroczyste. Dotyczy wszystkich ścieżek:
wczytanie z menu, w grze, `--load`, przejścia między komórkami (zamrożona klatka).
Test regresyjny `test_loading_render.gd` (wymaga wyświetlacza, w `run_tests.sh` w części ze zrzutami): w każdej
zasłoniętej klatce odczyt obrazu – róg ekranu czarny (tło ekranu ładowania), okienko narysowane. Przed poprawką
5 z 6 zasłoniętych klatek pokazywało świat, po poprawce 0.

**Wynik po poprawce na RTX 5090:** 12/12 zasłoniętych klatek – tapeta z okienkiem; świat i HUD od klatki
odsłonięcia. Średni czas klatki po odsłonięciu ok. 35 ms (do sprawdzenia osobno – wydajność nie jest częścią tego
punktu). **Ograniczenie:** proces uruchomiony przez MCP nie miał dostępu do X11 (brak autoryzacji) i działał na
Wayland (bez protokołu FIFO), a launcher uruchamia grę przez X11/XWayland – przyczyna jest niezależna od systemu
okien (kolejka komunikatów Godota), ale potwierdzenie z launchera należy do użytkownika.

**Lista towarów kupca (P1.1).** Porównanie z `TradeWindow::setPtr`, `ContainerItemModel`, `TradeItemModel::update`,
`World::getItemsOwnedBy/getContainersOwnedBy`, `SortFilterItemModel::Compare`:

| Różnica | Przyczyna (warstwa) | Naprawa |
|---|---|---|
| brak przedmiotów leżących w sklepie (półki, lady) | model danych: port brał tylko kupca i jego pojemniki; OpenMW dodaje `getItemsOwnedBy` – referencje aktywnych komórek o właścicielu = kupiec | `world_items()`, łączenie w stosy z towarem pojemników; kupno z referencji – `setCount` (liczba w zapisie gry, `refs[sid].count`) albo `deleteObject` |
| towar z pojemników o pojemności 0 i wyłączonych | mechanika: brak warunków `GetContainersOwnedByVisitor` | pojemność > 0, tylko dostępne |
| lista nie urywała się na świetle bez flagi Carry | mechanika: OpenMW `return` (nie `continue`) w `TradeItemModel::update` | to samo (w OpenMW dotyczy to tylko przedmiotów ze świata – pojemniki pomijają takie światła wcześniej) |
| inna kolejność siatek kupca i gracza | prezentacja: siatki handlu bez sortowania, sprzedawane rzeczy na końcu | `SortFilterItemModel::Compare`: Type_Barter, Type_Equipped, Type_Normal, rodzaj, nazwa, ładunek zaklęcia (%; stały 101), stan, czas użycia, wartość, waga, id – wspólne z ekwipunkiem i pojemnikiem (dodane brakujące poziomy) |
| ekwipunek gracza w handlu tylko z rzeczami „do sprzedania” | prezentacja: OpenMW pokazuje cały ekwipunek, kliknięcie rzeczy, której kupiec nie przyjmuje – dźwięk i `sBarterDialog4` | to samo |

Test `test_trade_sources.gd` (26) w `run_tests.sh`; `test_trade.gd` bez zmian zaliczony.

**Okno naprawy (P1.2, wiersz narzędzia):** wg `openmw_repair.layout` i `Gui::Box` – odstęp 4 px w wierszu i między
etykietami sUses/sQuality (było 0), etykiety w skórce SandText, ikona narzędzia i ToolBox wyśrodkowane w pionie
wiersza (HBox::align). Porównanie zrzutem z OpenMW (`ui_repair_e9_3440`, VM, renderer zgodności, 3440 × 1440,
cz. 28): ramka okna IoU 1,000; wiersze tekstu sUses/sQuality w OpenMW zaczynają się w y = 861 i 881 – przed poprawką
w porcie 863 i 879, po poprawce 861 i 881 (dół wierszy 872/896 wobec 871/894 – rasteryzacja czcionki); przycisk
Cancel 866–887 wobec 866–888; bloki 8 × 8 z różnicą w oknie: 136 → 133 z 2016 (pozostałe – tekst).

**Ekran ładowania – pozostałe ścieżki na RTX 5090 (cz. 29):** start z `--load` i wczytanie w trakcie gry
(`--diag-ingame-load`). Przy starcie z `--load` wczytanie trwa jeszcze w oknie 1152 × 648, a w trakcie okno przechodzi
w pełny ekran 3440 × 1440 – obraz ekranu ładowania (polecenia RenderingServer bez kotwic) zostawał w starym
rozmiarze i w dwóch klatkach odsłaniania poza nim widać było świat. Naprawa: przy zmianie rozmiaru widoku w trakcie
ładowania układ i obraz składane na nowo. Po poprawce: start z `--load` – 12/12 zasłoniętych klatek to tapeta
(także po zmianie rozmiaru), wczytanie w grze – 11/11. `test_loading_render` sprawdza też zmianę rozmiaru okna
pod ekranem ładowania (przed poprawką – świat w nowym obszarze). Przejście do wnętrza w trakcie gry
(`--diag-travel`, jak coc do „Seyda Neen, Census and Excise Office”): 3 zasłonięte klatki z zamrożonym obrazem
poprzedniej sceny, potem czerń zaciemnienia (fade 0,99) i rozjaśnianie w nowym wnętrzu – bez klatek z niekompletną
sceną.
Uwaga z pomiaru startu z `--load`: wczytanie odbywało się w oknie domyślnym 1152 × 648, a pełny ekran włączał się
w trakcie (na Wayland zmiana trybu okna jest asynchroniczna – nawet `apply_display` na początku `_ready` nie zdąży).
OpenMW tworzy okno od razu w trybie z ustawień (Engine::createWindow). Naprawa (cz. 30): launcher przekazuje Godotowi
`--fullscreen` albo `--resolution SZERxWYS` z ustawień profilu, więc okno powstaje od razu we właściwym trybie;
dodatkowo gra ustawia tryb okna zaraz po wczytaniu ustawień. Test `test_game_command_window_args` (pytest).

**Lista kupca – porównanie zrzutem** (`ui_windows_e8_3440`, handel u Arrille, VM, cz. 28): siatka okna kupca
podzielona na pola 42 × 42 (600 pól) – pola z różnicą średniej jasności > 12: przed poprawkami cz. 25 **43**,
po **15** (średnia różnica 3,48 → 2,48). Pozostałe różnice są pojedyncze w pierwszych kolumnach siatki (nie ma
przesunięcia całej listy – kolejność i skład zgodne co do pozycji); przyczyna pojedynczych pól (liczby sztuk,
tła przedmiotów magicznych) – zbadana w cz. 31 (niżej). Pozostałe odstępstwa
modelu przedmiotów: stos po identyfikatorze – założony egzemplarz w tym samym stosie co niezałożone (OpenMW:
osobny stos Type_Equipped), przedmioty ze skryptem łączone w stos (OpenMW: nie). Wpływ: tylko u kupców z założonymi lub oskryptowanymi
przedmiotami. Przedmioty przywołane (Flag_Bound – identyfikatory z GMST sMagicBound*, MechanicsManager::isBoundItem)
od cz. 31 są pomijane w towarze kupca jak w TradeItemModel::update (test_trade_sources, 28 sprawdzeń).

**Lista kupca – przyczyna pozostałych różnic (cz. 31, analiza danych na VM, tylko identyfikatory i liczby):**
pojemniki Arrille, które są źródłami towaru (właściciel = kupiec, pojemność > 0), zawierają listy poziomowane:
`random_ingredient` ×10, `random_armor_steel` ×3, `l_n_armor_shields` ×2, `random_de_weapon` ×7,
`random_de_shoes_common` ×2 i `random_expensive_de_fclothes_02` ×1 (w dwóch workach). OpenMW rozstrzyga je losowo:
`ContainerCustomData` → `fillNonRandom(…, seed)` z `World::getPrng()` (ziarno losowe przy każdym starcie,
o ile nie podano `--random-seed`), potem `resolve()` przy otwarciu; port – deterministycznie, ziarnem z referencji
(`_rng_for(sid)`). Wylosowane przedmioty (zbroje, broń, ubrania – w kolejności SortFilterItemModel na początku
listy, czyli w pierwszych kolumnach siatki – i składniki) różnią się więc między przebiegami samego OpenMW,
a różna liczba odrębnych identyfikatorów przesuwa sąsiednie pola. Dopasowanie pól 42 × 42 (każde pole OpenMW do
najbliższego pola portu) pokazuje w pierwszych kolumnach przesunięcia o 1–3 pozycje (obok niejednoznacznych dopasowań powtarzających się ikon).
Przedmioty stałe sprawdzone wprost: przedmioty w świecie należące do Arrille (48 referencji) – bez skryptów, bez
zaklęć, uszkodzona broń (srebrny krótki miecz 270/570, srebrny kij 240/270) jako osobne pojedyncze sztuki, strzały
bez wytrzymałości (WeaponType bez HasHealth – łączą się w stos, jak w porcie), klucz `key_arrile` odrzucony
(Miscellaneous::canSell – flaga Key), założone ubrania kupca pominięte (TradeItemModel: isEquipped). Wniosek:
pozostałe pola różnic to losowość list poziomowanych, nie błąd modelu towaru; zgodności co do pola nie da się
uzyskać bez wspólnego ziarna losowania (porównanie z `--random-seed` wymagałoby odtworzenia generatora OpenMW
w porcie – poza zakresem etapu 10).

### 7.18 Akcje sterowania OpenMW 0.51 (P2, cz. 26)

Porównane z `BindingsManager::loadKeyDefaults/loadControllerDefaults/getActionKeySorting/getActionControllerSorting/
actionValueChanged`, `ActionManager::executeAction`, `InventoryWindow::cycle`, `SpellWindow::cycle`,
`scripts/omw/input/playercontrols.lua`, `ScreenCaptureHandler`/`WriteScreenshotToFileOperation`.

| Akcja | Domyślnie (klawiatura / pad) | Stan |
|---|---|---|
| Activate / Jump | **Spacja / E** (było odwrotnie: E / Spacja) · A / lewy spust | poprawione domyślne (zapisane przypisania gracza bez zmian – jak input_v3.xml) |
| AlwaysRun | Caps Lock · – | zaimplementowane: bieg = Run ≠ alwaysRun, przełącznik zapisywany w ustawieniach (`always_run`), tylko gdy ruch dozwolony (bez pauzy, trybu GUI i blokady skryptu) |
| AutoMove | Q · – | zaimplementowane: ruch do przodu, wyłączany pierwszym ruchem przód/tył (ruch w bok go nie wyłącza) |
| CycleWeaponLeft/Right | [ / ] · X + lewy/prawy spust | zaimplementowane: kolejna broń prawej ręki w kolejności SortFilterItemModel bez grupowania typów, z pominięciem stosów tego samego przedmiotu, założenie jak użycie w ekwipunku; nie w trybie GUI, w ataku, przy paraliżu, powaleniu, śmierci; wilkołak – sWerewolfRefusal |
| CycleSpellLeft/Right | - / = · Y + lewy/prawy spust | zaimplementowane: kolejna pozycja SpellModel (moce, czary, przedmioty magiczne), bez wyboru – pierwsza |
| Screenshot | F12 · – | zaimplementowane: `screenshots/screenshotNNN.<format>` w katalogu danych (launcher: obok `saves`), `[General] screenshot format` (png), komunikat ScreenshotMade/Failed tylko przy `notify on saved screenshot` (domyślnie wył.) |
| TogglePOV, ZoomIn/ZoomOut | Tab, kółko · prawa gałka | **zależne od nieprzeniesionej kamery trzecioosobowej** (MWRender::Camera: widok TPP, oddalanie, ciało gracza w TPP) – akcji nie dodano, by nie tworzyć przycisków bez działania |
| TogglePostProcessorHUD | F2 | zależne od nieprzeniesionego post-processingu (shadery Lua/omwfx) |

Nowe akcje są na liście przypisań okna opcji w kolejności OpenMW (klawiatura i pad) z opisami z GMST
(sAlways_Run, sAuto_Run, sPrevSpell, sNextSpell, sPrevWeapon, sNextWeapon, OMWEngine:Screenshot).
Test `test_player_controls.gd` (45): domyślne klawisze i przypisania, kolejność listy, AlwaysRun (bieg, zapis),
AutoMove (bok/przód/tył), Cycle Weapon (pierwsza bez broni, następna, poprzednia, zawinięcie, blokada w menu),
Cycle Spell (pierwsza, następna, zawinięcie, wilkołak). `test_settings` i `test_gamepad` – oczekiwane domyślne
klawisze poprawione na wartości OpenMW (wcześniej test utrwalał odwrócone Activate/Jump).
Ustawienie „Always Run” w GUI jest w OpenMW 0.51 na stronie skryptów Lua (Scripts → OpenMW Controls) – zakładka
Scripts zależy od nieprzeniesionego Lua (punkt 7.16); przełącza je klawisz.

### 7.19 Okno ↔ pełny ekran i rozdzielczości na sprzęcie użytkownika (P3, cz. 27)

Diagnostyka `--diag-display` (`mw_display_diag.gd`) uruchomiona przez MCP na RTX 5090 użytkownika (3440 × 1440,
dane gry, kopia zapisu): kolejno okno 1280 × 720, 2560 × 1440, 3440 × 1440, 3840 × 2160, pełny ekran w oknie,
pełny ekran wyłączny, okno 1280 × 720, pełny ekran – przez `main.apply_display` (ta sama ścieżka co okno opcji),
po 45 klatkach wiersz liczb. Wyniki:

| Sprawdzenie | Wynik |
|---|---|
| rozmiar widoku = rozmiar okna we wszystkich krokach (bez rozciągania 16:9 do 21:9 – projekt bez trybu stretch) | tak (8/8) |
| HUD po zmianie: paski przy lewej krawędzi (x = 15), minimapa i ikony efektów przy prawej, dół ekranu – według rozmiaru widoku | tak (8/8) |
| celownik na środku ((widok − 31) / 2) | tak (8/8) |
| powrót z pełnego ekranu do okna i ponownie do pełnego ekranu | tryb i rozmiar zgodne |
| wyśrodkowanie okna | **niesprawdzalne w tym przebiegu**: proces z MCP działał na Wayland (bez autoryzacji X11), a Wayland nie pozwala programowi ustawiać ani odczytywać położenia okna (zawsze 0, 0); launcher uruchamia grę przez X11 |
| pełny ekran wyłączny | na Wayland Godot daje tryb pełnoekranowy okna (brak trybu wyłącznego) |
| skala interfejsu | na Wayland `screen_get_scale` = 2,0 z ułamkową skalą pulpitu – UI w tym przebiegu 1,15; przez X11 (launcher) skala 1,0. OpenMW na Wayland/XWayland – nieporównane |

Do potwierdzenia przez użytkownika z launchera (X11): wyśrodkowanie okna po przejściu z pełnego ekranu, przełączanie
w trakcie gry, podpowiedzi przy krawędziach 21:9 i przewijanie list (automatycznie sprawdzone tylko w testach
`test_tooltips` i `test_ui_geometry`).
OpenMW przy pełnym ekranie wyłącznym zmienia tryb monitora na wybraną rozdzielczość; Godot 4 nie zmienia trybu
monitora (pełny ekran zawsze w rozdzielczości pulpitu) – **odstępstwo zależne od silnika Godot**: w pełnym ekranie
wybór rozdzielczości nie ma skutku.

### 7.20 Konsola i ustawienia – trzy kategorie (P4, cz. 27)

**Konsola / MWScript** – 298 nazw instrukcji i funkcji z `components/compiler/extensions0.cpp` (OpenMW 0.51):

| Kategoria | Nazwy |
|---|---|
| 1. zaimplementowane (285) | wszystkie pozostałe; w cz. 27–28 doszły: GetPCRunning, GetWindSpeed (0 we wnętrzach), Get/Set/ModPCVisionBonus (Night Eye ograniczony do [0, 1]), PCGet3rdPerson (0 – widok zawsze pierwszoosobowy), PCForce1stPerson, ToggleSky (ts), ToggleWater (twa), ToggleWireframe (twf), ToggleWorld (tw), ToggleScripts, ToggleFullHelp (tfh – pełna pomoc w podpowiedziach: Owner, Owner Faction, Rank, Global, Script), ToggleFogOfWar (tfow), User1–4; **cz. 28:** AddToLevCreature, AddToLevItem, RemoveFromLevCreature, RemoveFromLevItem (kopia listy z dopisaną/usuniętą pozycją jako rekord w GameState.created – ESMStore::overrideRecord, w zapisie gry), TogglePathGrid (tpg – romby i krawędzie jak createPathgridGeometry), ToggleCollisionBoxes / ToggleCollisionGrid (tcb / tcg – kształty kolizji), ToggleBorders (tb – CellBorder: 2 × 40 odcinków 10 j. nad terenem, czarno-żółte), BetaComment / bc / ORI (czas, plik treści, RefNum, RefID, komórka, siatka, współrzędne, model, skrypt, notatki), MenuTest, TestCells, TestInteriorCells (tylko bez gry, jak OpenMW), TestModels (t3d) |
| 2. brakujące, możliwe teraz | brak |
| 3. zależne od nieprzeniesionych części | PCForce3rdPerson, ToggleVanityMode (tvm) – kamera trzecioosobowa (MWRender::Camera); GetMasserPhase, GetSecundaPhase, TurnMoonRed/White – księżyce nieba (SkyManager::Moon); ReloadLua – Lua; ShowSceneGraph – graf sceny OSG; ToggleNavMesh, ToggleRecastMesh, ToggleActorsPaths (tap), SetNavMeshNumber – DetourNavigator (port używa nawigacji Godota) |

BetaComment bez listy tekstur modelu (TextureFetchVisitor i archiwa BSA w VFS – port czyta przekonwertowane modele).
Pełna pomoc: bez wierszy „Stolen … from …” (port nie prowadzi rejestru skradzionych przedmiotów według właścicieli,
MechanicsManager::getStolenItemOwners) i bez dopisku postaci wilkołaka w nazwie NPC.

**Ustawienia okna opcji** (37 ustawień z `openmw_settings_window.layout` 0.51):

| Kategoria | Ustawienia |
|---|---|
| 1. zaimplementowane | GUI: menu transparency, tooltip delay, subtitles; Game: difficulty, actors processing range, best attack; Saves: autosave; HUD: crosshair; Sound: 5 głośności; Input: invert x/y, camera sensitivity, enable controller; Video: rozdzielczość, tryb okna, VSync, window border; Camera: field of view, viewing distance; Water: shader; General: gmst overrides l10n; Language; w cz. 27: **[General] anisotropy** (suwak w Detail Level, poziom filtrowania anizotropowego widoku), **[Water] refraction, sunlight scattering, wobbly shores** (przełączniki w zakładce Water; gałęzie @waterRefraction / @sunlightScattering / @wobblyShores w shaderze wody, bez załamania – kolor wody z odbiciem i przezroczystość waterTransparency; domyślnie jak settings-default.cfg: refraction wyłączone) |
| 2. brakujące, możliwe teraz | brak – w cz. 28 doszły [Shaders] maximum light distance i light fade start (wygaszanie świateł z odległością od kamery: distance fade świateł Godota od start × odległość do odległości) oraz minimum interior brightness (ambient wnętrza); ustawiane w pliku ustawień gry (`maximum_light_distance`, `light_fade_start`, `minimum_interior_brightness`) – zakładki Lights w oknie opcji nie dodano, bo jej pozostałe pola (lighting method, max lights, light bounds multiplier, przełączniki Shaders) zależą od potoku oświetlenia OpenMW, a układ VBox tej zakładki bez nich byłby inny niż w 0.51 |
| 3. zależne | Texture Filtering (Bilinear/Trilinear) – filtr mipmap próbników Godota ustalany przy starcie (rendering/textures/default_filters), OpenMW zmienia go w trakcie gry; Shadows – w oknie opcji 0.51 tej zakładki nie ma; Post Processing enabled – post-processing OpenMW (omwfx) nieprzeniesiony; Video gamma – rampa gammy monitora (SDL_SetWindowGammaRamp), Godot nie ma odpowiednika; Shaders: lighting method, force per pixel lighting, classic falloff, clamp lighting, match sunlight to sun – potok oświetlenia OpenMW (Godot Forward+ ma własny); Water: texture quality, reflection detail, rain ripple detail – odbicie wody jest przybliżeniem nieba (bez kamery odbicia RTT) i bez zmarszczek deszczu; zakładka Scripts – Lua |

Pliki `godot/l10n/OMWEngine/*.yaml` i `Calendar/en.yaml` pochodziły z nowszej wersji OpenMW niż 0.51 (np.
`LightsClusteredLighting` zamiast `LightingMethod`, Calendar `timeFormat`) – w cz. 28 zastąpione plikami 0.51; żaden
usunięty klucz nie był używany w kodzie poza `timeFormat` (godzina w oknie odpoczynku i zapisu liczona teraz jak
WaitDialog/SaveGameDialog 0.51: „%i %s” z #{Calendar:am}/#{Calendar:pm} – ten sam wynik).
Test `test_console_toggles.gd` (53).

### 7.21 Werdykt etapu GUI

Etapu 10 **nie można zamknąć** bez potwierdzenia na sprzęcie użytkownika z launchera (X11): ekran ładowania przy
wczytaniu zapisu, przejścia okno ↔ pełny ekran i wyśrodkowanie okna. Okno naprawy i lista kupca porównane zrzutami
z OpenMW na VM (punkt 7.17) – w liście kupca zostały pojedyncze różnice pól (do sprawdzenia lokalnie). Kategoria 2
z punktu 7.20 – wyczerpana; pliki l10n OMWEngine i Calendar – z 0.51 (cz. 28).
Ekran ładowania przy wczytaniu zapisu – naprawiony i zmierzony na RTX 5090 użytkownika (punkt 7.17; proces przez
MCP na Wayland – potwierdzenie z launchera po stronie użytkownika). Lista towarów kupca – przyczyny usunięte
(punkt 7.17), porównanie zrzutem z OpenMW u tego samego kupca – do zrobienia.

### 7.22 Pozostałe punkty etapu (do wykonania)

Mody – zgodnie z poleceniem nie testowane (kolejność: najpierw klasyczne GUI).

## 8. Commity (lokalne, bez push)

* Etap 10 cz. 1: stos trybów GUI jak WindowManager OpenMW 0.51
* Etap 10 cz. 2: stworzenia wodne i latające jak MovementSolver OpenMW
* Etap 10 cz. 3: interfejs po angielsku (GMST → l10n → zapas angielski)
* Etap 10 cz. 4: launcher – pełne tłumaczenie PL/EN i zmiana języka bez restartu
* Etap 10 cz. 5: przejścia między komórkami jak OpenMW – zaciemnienie, gotowość pierwszej klatki
* Etap 10 cz. 6: stworzenia – kształt z „Bounding Box” i adjustPosition (weryfikacja na prawdziwych danych)
* Etap 10 cz. 7: okno ilości (CountDialog)
* Etap 10 cz. 8: szybkie klawisze i wybór magii
* Etap 10 cz. 9: podpowiedzi w układzie OpenMW (przedmioty, czary)
* Etap 10: naprawa – ruch po wczytaniu zapisu z menu i MenuMode skryptów
* Etap 10 cz. 10: podpowiedzi układów (Layout) i ikon efektów
* Etap 10 cz. 11: więzienie i towarzysz
* Etap 10 cz. 12: konsola (MWScript)
* Etap 10 cz. 13: notatki na mapie (EditNoteDialog, CustomMarker)
* Etap 10 cz. 14: okno opcji jak SettingsWindow, przypisania klawiszy, autozapis
* Etap 10 cz. 15: nawigacja klawiaturą w oknach (KeyboardNavigation)
* Etap 10 cz. 16: pad (ControllerManager)
* Etap 10 cz. 17: porównania nowych okien z OpenMW 720p/1440p/2160p i poprawki układów
* Etap 10 cz. 18: teksty silnika z GMST, zakładka Language, przełącznik pada w Controls
* Etap 10 cz. 19: dodatki (Tribunal, Bloodmoon) – znaczniki drzwi, skala mapy, MW_ScrollView, ClassChoiceDialog
* Etap 10 cz. 20: naprawa – samoczynny obrót kamery (pad tylko z kontrolera gry), diagnostyka źródeł obrotu
* Etap 10 P0: wczytywanie zapisu bez niekompletnych klatek (cz. 21)
* Etap 10 cz. 22: GUI 21:9 (3440 × 1440) – ramki okien, HUD 0.51, księgi, podpowiedź obiektu
* Etap 10 cz. 23: DragAndDrop jak OpenMW, przyciski AutoSizedButton, raport audytu
* Etap 10: raport – 3440 × 1440 dla awansu, alchemii, zaklinania, naprawy; pełny zestaw 68/68
* Etap 10 cz. 24: diagnostyka wczytania na sprzęcie użytkownika (--load-diag)
* Etap 10 cz. 25: ekran ładowania rysowany przez RenderingServer, towar kupca jak TradeWindow OpenMW
* Etap 10 cz. 26: akcje sterowania OpenMW 0.51 (AlwaysRun, AutoMove, Cycle, Screenshot, domyślne klawisze)
* Etap 10 cz. 27: konsola i ustawienia – kategorie, przełączniki, anizotropia, opcje wody; diagnostyka trybów okna
* Etap 10 cz. 28: listy poziomowane, przełączniki debugowe, BetaComment, TestCells/TestModels, światła, l10n 0.51
* Etap 10 cz. 29: ekran ładowania przy zmianie rozmiaru okna, diagnostyka wczytania w trakcie gry
* Etap 10: diagnostyka przejścia między komórkami (--diag-travel)
* Etap 10 cz. 30: okno od razu w trybie z ustawień (launcher: --fullscreen / --resolution)
* Etap 10: raport – przyczyna różnic listy kupca (listy poziomowane, cz. 31)
* Etap 10 cz. 31: przedmioty przywołane poza towarem kupca (Flag_Bound)

Pełny zestaw tools/run_tests.sh: 72/72 po cz. 30 (Xvfb + lavapipe, pytest z test_game_command_window_args); 72/72 po cz. 28 (test_language wykrył polski komunikat błędu w nowym kodzie – poprawiony, testy od test_language powtórzone); 72/72 po cz. 27 (nowe test_player_controls i test_console_toggles; test_loading_render powtórzony osobno po zniknięciu serwera Xvfb w trakcie przebiegu – środowisko, nie test); 70/70 po cz. 25 (nowe test_trade_sources i test_loading_render; Xvfb + lavapipe); 68/68 po cz. 21–23 (z nowym test_load_reveal; test_count_dialog, test_trade, test_map_notes, test_load_reveal powtórzone na końcowym kodzie cz. 23); 67/67 po cz. 20; 66/66 po cz. 19 (38 w przebiegu, test_progress poprawiony i 28 kolejnych po poprawce); 66/66 po cz. 18; 66/66 po cz. 17; 66/66 po cz. 16; 65/65 po cz. 15; 64/64 po cz. 14; 64/64 po cz. 13; 63/63 po cz. 12; 62/62 po cz. 11; 61/61 po naprawie (po cz. 8: 59/59 (test_menu_mode poprawiony – upuszczenie stosu przez okno ilości)).

## 9. Zalecana kolejność dalszych prac

1. Potwierdzenie przez użytkownika z launchera: ekran ładowania, przejścia okno ↔ pełny ekran, wyśrodkowanie okna,
2. (zamknięte w cz. 31: różnice listy kupca u Arrille wynikają z losowania list poziomowanych w pojemnikach kupca).
Mody – dopiero po zamknięciu klasycznego GUI.
