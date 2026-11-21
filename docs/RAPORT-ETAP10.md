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
Różnica wobec OpenMW: przeciąganie Godota (wciśnij–przesuń–puść) zamiast „kliknij, by podnieść”, więc okno pojawia się
przy upuszczeniu; komunikat (sTake) i wynik są te same. Upuszczenie na postać (użycie) – bez okna ilości.
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
zaklinanie (teksty pomocy), mapa (znaczniki). Test: test_tooltips (43). Brak: podpowiedź obiektu w świecie z ikoną
(HUD), HandToHandToolTip i Spell/ItemPtr na polach broni i czaru w HUD.

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
szczegóły wody poza shaderem, Lights, Scripts (Lua), Language (język – launcher), pad i „Enable Controller”.
Różnice: domyślne klawisze skoku/aktywacji portu (Spacja/E) zostały – OpenMW ma E/Spację. Test: test_settings (71,
poprzednio „Anuluj przywraca” – zachowanie spoza OpenMW).

### 7.9 Pozostałe punkty etapu (do wykonania)

§10 ekrany ładowania, Enter/Tab/strzałki, pad, §11 porównania 720p/1440p/2160p i nowych okien, §12 dodatki i mody.

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

Pełny zestaw tools/run_tests.sh: 64/64 po cz. 14; 64/64 po cz. 13; 63/63 po cz. 12; 62/62 po cz. 11; 61/61 po naprawie (po cz. 8: 59/59 (test_menu_mode poprawiony – upuszczenie stosu przez okno ilości)).

## 9. Zalecana kolejność dalszych prac

1. Klawiatura w oknach (Enter/Tab/strzałki), pad, ekrany ładowania, 2. porównania zrzutami wszystkich nowych okien z OpenMW
(720p/1440p/2160p), 3. dodatki i mody.
