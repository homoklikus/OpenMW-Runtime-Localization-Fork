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
y = 4,0 m) – sprawdzone. Porównanie obrazu z OpenMW w realnej komórce czeka na odtworzenie środowiska VM
(`odtworz.sh` – /tmp maszyny został wyczyszczony przy restarcie).

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

## 5. Pozostałe punkty etapu (do wykonania)

§3 szybkie klawisze i wybór magii, §4 podpowiedzi `openmw_tooltips`, §5 okno ilości, §6 konsola, §7 więzienie,
§8 towarzysz, §9 notatki mapy i pole tekstowe, §10 ustawienia, autozapis, ekrany ładowania, Enter/Tab/strzałki,
pad, §11 porównania 720p/1440p/2160p i nowych okien, §12 dodatki i mody.

## 6. Commity (lokalne, bez push)

* Etap 10 cz. 1: stos trybów GUI jak WindowManager OpenMW 0.51
* Etap 10 cz. 2: stworzenia wodne i latające jak MovementSolver OpenMW
* Etap 10 cz. 3: interfejs po angielsku (GMST → l10n → zapas angielski)

## 7. Zalecana kolejność dalszych prac

1. Okno ilości i szybkie klawisze (codzienna rozgrywka), 2. podpowiedzi openmw_tooltips, 3. więzienie i towarzysz,
4. konsola (też do testów), 5. ustawienia/autozapis/klawiatura/pad, 6. porównania zrzutami wszystkich okien.
