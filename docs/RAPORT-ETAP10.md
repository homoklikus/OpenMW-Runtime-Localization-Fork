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

## 7. Pozostałe punkty etapu (do wykonania)

§3 szybkie klawisze i wybór magii, §4 podpowiedzi `openmw_tooltips`, §5 okno ilości, §6 konsola, §7 więzienie,
§8 towarzysz, §9 notatki mapy i pole tekstowe, §10 ustawienia, autozapis, ekrany ładowania, Enter/Tab/strzałki,
pad, §11 porównania 720p/1440p/2160p i nowych okien, §12 dodatki i mody.

## 8. Commity (lokalne, bez push)

* Etap 10 cz. 1: stos trybów GUI jak WindowManager OpenMW 0.51
* Etap 10 cz. 2: stworzenia wodne i latające jak MovementSolver OpenMW
* Etap 10 cz. 3: interfejs po angielsku (GMST → l10n → zapas angielski)
* Etap 10 cz. 4: launcher – pełne tłumaczenie PL/EN i zmiana języka bez restartu
* Etap 10 cz. 5: przejścia między komórkami jak OpenMW – zaciemnienie, gotowość pierwszej klatki
* Etap 10 cz. 6: stworzenia – kształt z „Bounding Box” i adjustPosition (weryfikacja na prawdziwych danych)

## 9. Zalecana kolejność dalszych prac

1. Okno ilości i szybkie klawisze (codzienna rozgrywka), 2. podpowiedzi openmw_tooltips, 3. więzienie i towarzysz,
4. konsola (też do testów), 5. ustawienia/autozapis/klawiatura/pad, 6. porównania zrzutami wszystkich okien.
