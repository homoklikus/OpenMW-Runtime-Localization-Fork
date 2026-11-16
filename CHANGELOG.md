# Zmiany

## 0.5 — 2026-11-15: roślinność z forka OpenMW RLF (etap 2, `docs/PORT-RLF.md`)

* Konwerter `mwconv/flora.py`: wtyczki groundcover (openmw.cfg `groundcover=`, mody rozpoznawane automatycznie)
  oraz trawa Remirosa jak w forku – tabela reguł i liczników forka wbudowana, bez ESP (z moda tylko modele
  i tekstury); pliki `world/flora/<x>_<y>.bin`; czytnik ESM czyta PGRD.
* Modele i tekstury Remiros' Groundcover (autor: Remiros) dołączone do programu – trawa działa bez instalowania
  moda; roślinność domyślnie włączona.
* Roślinność: kolor wierzchołków modeli Remirosa (znacznik wiatru MGE XE) nie barwi już tekstur – koniec
  turkusowych kamieni.
* Launcher: rozdzielczość wykrywana z podłączonych ekranów (np. 3440x1440, także HiDPI) i ultrawide na liście;
  gra przyjmuje dowolną rozdzielczość „SZERxWYS” i wyśrodkowuje okno.
* Gra: tryb zrzutu do porównań z OpenMW (`--camera`, `--look`, `--hour`, `--weather`, `--fov`, `--screenshot`);
  argumenty można też podać w `override.cfg` (`[mwgodot] cli/<nazwa>=…`), np. przy starcie przez MCP Godota.
* MCP-openMW 0.8.0 przeniesiony do repozytorium (`tools/MCP-openMW`, wcześniej w forku na zamrożonej gałęzi
  `0.5-world`): profil zewnętrzny `openmwgodot` (zrzuty OpenMWGodot z tą samą kamerą co OpenMW, porównania
  z każdym profilem), wykrywanie folderu `OpenMW RLF` obok repozytorium.
* Etap 0: `GameState` (różnice stanu gry względem danych bazowych) i zapis gry v1 (`docs/FORMAT-ZAPISU.md`):
  F5/F9 szybki zapis/odczyt, Esc menu pauzy; zgodność wtyczek, migracje z kopią, zapisy atomowe;
  referencje wyłączone w stanie gry nie są rysowane.
* Etap 0: `MWActor` – wspólny aktor gracza/NPC/stworzeń (ruch, kapsuła, intencje) z kontrolerami (gracz:
  `mw_player_controller.gd`); szyna zdarzeń (`mw_events.gd`: komórki, aktywacja, zapis/odczyt); akcje wejścia
  (`mw_input.gd`: menu, szybki zapis/odczyt, współrzędne) zamiast klawiszy w kodzie; Esc działa też w pauzie.
* Etap 1: konwerter eksportuje `world/records/` (NPC_, CREA, RACE, CLAS, FACT, BODY, BSGN, SKIL, broń, zbroje,
  ubrania, książki, przedmioty, światła, GMST, GLOB) ze scalaniem wg kolejności ładowania; MCP-openMW:
  `openmw_record_compare_start/status` – porównanie rekordów z silnikiem OpenMW (Lua) pole po polu.
* Etap 10 (w toku) – okna jak w OpenMW: rozmowa (położenie i rozmiar z [Windows] dialogue, kolory nagłówków,
  odnośników i odpowiedzi z FontColor, pasek postawy), handel (siatki ikon kupca i gracza, przenoszenie sztuk
  kliknięciem lub przeciąganiem, tła „barter”, ceny w podpowiedziach), alchemia (pola aparatów i składników z
  ikonami, efekty, siatka składników); paski tytułu okien z tekstur gry.
* Etap 10 (w toku) – HUD jak w Morrowindzie: paski zdrowia, magii i kondycji, pole broni (stan) i czaru (szansa,
  ładunek), ikona skradania, minimapa z kompasem, ikony działających efektów, nazwa broni/czaru i miejsca po
  zmianie, celownik i podpowiedź nad celem; F11 – ukryj HUD, F3 – pasek informacji (domyślnie ukryty). Pojemniki
  jak w OpenMW: okno pojemnika obok ekwipunku, przeciąganie i dwuklik, „Weź wszystko”, limit pojemności.
  Wszystkie okna gry w wyglądzie Morrowinda (motyw domyślny).
* Etap 10 (w toku) – tryb menu jak w Morrowindzie: prawy przycisk myszy (także I, M, N) pokazuje naraz okna
  statystyk, ekwipunku, magii i mapy w położeniach OpenMW (przesuwanie, zmiana rozmiaru, układ w zapisie gry);
  wygląd z tekstur gry gracza (ramki, paski, tła ikon), kolory FontColor i czcionka MysticCards. Ekwipunek:
  podgląd postaci w założonych rzeczach, pancerz, obciążenie, kategorie, ikony przedmiotów kolumnami, podpowiedzi,
  przeciąganie na postać (załóż/użyj) i poza okna (upuść). Statystyki: paski, poziom, rasa, klasa, atrybuty,
  umiejętności wg klasy z postępem, frakcje, znak, reputacja, grzywna. Magia: działające efekty, moce, zaklęcia,
  przedmioty magiczne. Konwerter kopiuje tekstury interfejsu i ikony.
* Etap 10 (w toku) – woda jak OpenMW: woda „shader” (port water.frag – fale z 6 warstw mapy normalnych, Fresnel,
  załamanie z barwą głębi, rozpraszanie i odblask słońca, chwiejne brzegi, mocniejsze fale w deszczu; odbija niebo)
  albo prosta woda z animowanych tekstur gry (ustawienie „Woda z falami”); pod wodą mgła i kolor jak w OpenMW
  (Water_Underwater*). Cienie słońca: kaskady, zasięg i rozdzielczość wg jakości.
* Etap 10 (w toku) – pogoda i niebo jak OpenMW (WeatherManager): kolory nieba, mgły, otoczenia i słońca wg pory
  dnia (wartości Morrowind.ini z instalacji gracza, brakujące – domyślne OpenMW), płynne przejścia między
  pogodami z kolejką, zmiana pogody regionu co 20 h gry, mgła liniowa (początek = odległość × (1 − głębokość)),
  chmury pogody (Tx_Sky_*, przesuw, mieszanie przy przejściu), tarcza słońca o zachodzie i gwiazdy nocą; słońce
  w kierunku jak w Morrowindzie (najwyżej o 13:00), nocą światło księżyców; wnętrza: mgła z gęstości komórki.
* Etap 10 (w toku) – dźwięki z kluczy animacji jak OpenMW (handleTextKey): „Sound:” i „SoundGen:” z tekstów
  .kf – kroki NPC wg butów (boso, lekkie, średnie, ciężkie), w wodzie i przy pływaniu; stworzenia z rekordów SNDG
  (pomruk, ryk, krzyk, kroki – własne, z tego samego modelu albo ogólne); kroki gracza też wg butów i wody.
  Konwerter: rekordy SNDG (eksport świata v13 – „Aktualizuj”).
* Etap 10 (w toku) – ustawienia w grze (Esc → Ustawienia): głośności (ogólna, muzyka, głosy, efekty, kroki),
  napisy, czułość myszy, odwrócenie osi, pole widzenia (domyślnie 60° jak OpenMW), odległość widzenia, cienie,
  mgła, V-Sync, limit FPS – działają od razu, „Zapisz”/„Anuluj”; zapis do ingame_settings.json, launcher scala
  go z profilem (te same opcje w zakładce „Dźwięk” i „Sterowanie” launchera). Komunikaty i napisy kwestii na
  warstwie nad oknami – wcześniej napis kwestii chował się pod oknem zwoju/książki.
* Etap 10 (w toku) – klasa postaci jak w OpenMW: „Pytania…” – 10 pytań z Morrowind.ini/openmw.cfg (albo
  tłumaczeń lokalizacji RLF), odpowiedzi w losowej kolejności, głos lektora, wynik według tabeli OpenMW i okno
  z opisem klasy (Wróć/OK); „Własna…” – nazwa, opis, specjalizacja, 2 ulubione atrybuty, 5 głównych
  i 5 drugorzędnych umiejętności bez powtórzeń (domyślne jak OpenMW), klasa zapisywana w grze. Konwerter:
  world/fallbacks.json (eksport świata v12 – „Aktualizuj”); bez tekstów pytań w instalacji przycisk jest ukryty.
* Etap 10 (w toku) – poprawki po porównaniu z OpenMW (kominek w urzędzie celnym w Seyda Neen): konwerter zeruje
  transformację korzenia NiNode (rekord 0, poza „Bip01”) jak OpenMW (`components/nif/node.cpp`) – modele z obróconym
  korzeniem (m.in. kominki) stały tyłem do pokoju; korzeń-kształt zachowuje obrót (nif2gltf-0.1.2, ponowna
  konwersja tylko takich modeli – „Aktualizuj”). Światła jak OpenMW z wartościami Morrowind.ini: natężenie
  r / (3·d) z wygaszaniem do 2r (wcześniej słabsze i ucięte na promieniu); światła ujemne pomijane jak przy
  oświetleniu shaderami OpenMW (koniec czarnych plam). MCP-openMW 0.12.0: ujęcia porównawcze we wnętrzach.
* Etap 10 (w toku) – mapa (klawisz N) jak w OpenMW: mapa lokalna – widok z góry segmentów po 8192 jedn.
  (komórka zewnętrzna; wnętrze obrócone wg NorthMarker), mgła wojny 32 × 32 na segment odkrywana wokół gracza
  (w zapisie), drzwi z nazwą celu, strzałka gracza; mapa świata – obraz z wysokości WNAM w kolorach palety
  OpenMW (18 px na komórkę), znaczniki odwiedzonych nazwanych miejsc i odkrytych przez ShowMap, pozycja gracza,
  przybliżanie kółkiem myszy; przełącznik „Świat”/„Lokalna”. Konwerter: world/map/ (eksport świata v11 –
  „Aktualizuj”). Brak (później): nakładanie odkrytych map lokalnych na mapę świata, własne notatki na mapie.
* Etap 10 (w toku) – książki i zwoje jak w OpenMW: aktywacja książki w świecie otwiera ją do czytania (przycisk
  „Weź”), z ekwipunku – bez „Weź” (w walce nie wolno); książka – dwie strony z numerami, poprzednia/następna
  (strzałki), zwój – jedna przewijana kolumna; znaczniki Morrowinda (BR, P, DIV ALIGN, FONT COLOR/FACE, IMG
  z BookArt; tekst po ostatnim BR ukryty) i lokalizacji RLF ([c=#], [b], [i], [pagebreak]), podział na strony
  w granicach linii jak Paginator OpenMW, tłumaczenia tekstów (BOOK|id|TEXT), podstawienia (%PCName…),
  czcionki MysticCards i daedryjska (OFL, z OpenMW), tła i przyciski z tekstur gry (tx_menubook, scroll),
  dźwięki otwierania, kartkowania i zamykania. Pierwsze przeczytanie książki z umiejętnością podnosi ją o 1
  (raz na książkę, w zapisie). Konwerter: ilustracje BookArt i tekstury okien („Aktualizuj”).
* Etap 10 (w toku) – dźwięk świata: głosy NPC z plików Vo jak OpenMW (`DialogueManager::say`: powitanie Hello,
  Idle wg fVoiceIdleOdds, Attack przy rozpoczęciu walki i atakach wg iVoiceAttackOdds, Hit wg iVoiceHitOdds
  i przy śmierci, Flee, Thief, Intruder; jedna kwestia naraz, głos z głowy aktora, napisy), Say ze skryptu
  odtwarza nagranie i SayDone czeka na jego koniec; muzyka jak skrypt `music.lua` (playlisty Explore i Battle,
  losowa kolejność, bitwa gdy ktoś w pobliżu walczy, przejścia z wyciszeniem, StreamMusic ze skryptu, muzyka
  śmierci); dźwięki otoczenia regionu (szanse z REGN, co 1–5 s), pętle pogody (deszcz, burza, burza popiołu,
  zaraza, zamieć) i dźwięk pod wodą; głośności jak domyślne OpenMW (muzyka 0,5, głosy 0,8, kroki 0,2).
  Konwerter: głosy (Sound/Vo) i muzyka (Music/) kopiowane do katalogu wyników – eksport świata v10
  („Aktualizuj” w launcherze). Poprawka: nazwy pogody burzy i burzy popiołu w ChangeWeather, GetCurrentWeather
  i warunku dialogów Weather były niezgodne z pogodą gry.
* Etap 9: pełna rozgrywka początku gry – nowa gra jak w Morrowindzie: statek więzienny i tworzenie postaci
  przez skrypty CharGen (imię, rasa, klasa, znak, przegląd w kolejnych menu wywoływanych przez NPC; blokady
  sterowania, walki, magii i okien, odblokowywane po kolei; kwestie Say z napisami i SayDone; urząd celny,
  papiery, sztylet, pierścień w beczce, kapitan Gravius i paczka), potem łazik do Balmory, Caius Cosades (A1_1),
  Gildia Wojowników i zadanie ze szczurami u Drarayne Thelas (walka, dziennik, nagroda). Skrypty przedmiotów
  w ekwipunku (OnPCAdd, OnPCEquip), funkcje bez nawiasów (SayDone, GetAIPackageDone…), GetRace, ChangeWeather,
  GetCurrentWeather, GetStandingPC, Rotate, PlayGroup/LoopGroup, Disable/EnableRest, ShowRestMenu. Gracz po
  teleporcie stawiany na podłożu (bez obrażeń od upadku przy wyjściu z budynków), siła i odstęp ataków AI jak
  w OpenMW. Szybki kreator jak dotąd: ustawienie "chargen_mode": "quick".
  Poprawki po pierwszej grze: koniec przycięć – skrypty sprawdzające GetSoundPlaying przed PlayLoopSound3D
  tworzyły setki odtwarzaczy dźwięku na sekundę (fizyka 15–25 ms na klatkę, teraz ok. 1,5 ms); dźwięki
  skryptów należą do obiektu jak w OpenMW (GetSoundPlaying, StopSound, pętle, głośność i wysokość z VP).
  Aktorzy wchodzą na stopnie do 34 jedn. (OpenMW Stepper) i mają kolizję walcem zamiast kapsuły – da się
  zejść trapem ze statku na pomost, schody i progi już nie zatrzymują. `--perf=1`: czasy podsystemów
  w logu (MWGODOT_PERF).
* Etap 8: AI, nawigacja i reakcje świata – siatki ścieżek PGRD (eksport świata v8 – „Aktualizuj” w launcherze;
  A* i składowe spójne jak OpenMW), pakiety AI z rekordów i skryptów (wander, travel, escort, follow, activate;
  AiWander/AiTravel/AiEscort/AiFollow/AiActivate, GetAIPackageDone, GetCurrentAIPackage), powitania (Hello),
  animacje chodu i biegu, wykrywanie gracza (skradanie – Ctrl, niewidzialność, kameleon), AI walki (broń, czary,
  łuki, ucieczka), przestępstwa (kradzież, wtargnięcie, napaść, morderstwo), świadkowie wg Alarm, pościg i rozmowa
  strażnika, grzywna i konfiskata, więzienie (znaczniki z `world/markers.json`), wytrychy i sondy (Security),
  pułapki rzucają czar; pozycje i stan AI NPC w zapisie. Koniec „dryfu” NPC (kolizje modeli). Stworzenia
  z punktów pojawiania się (LEVC) – eksport świata v9. MCP-openMW 0.11.0: porównanie zachowań AI z OpenMW
  (Seyda Neen: 14/14 pakietów AI, 12/12 promieni wędrówki, ta sama reakcja straży na napaść).
  Regresja przed publikacją (porównanie wszystkich etapów 2–8 z OpenMW): NPC i stworzenia pływają (poziom
  wody komórki), bezczynny NPC rusza dalej, gdy nie stoi przy innym punkcie wędrówki lub stoi przed drzwiami
  (isNearAllowedPosition bez bieżącego celu, proximityToDoor); ujęcia porównawcze z zamrożonymi aktorami.
* Etap 7: walka, magia i mechanika RPG – rozwój umiejętności i awans (T – odpoczynek, okno awansu), ruch wg
  statystyk, handel z targowaniem, zakup zaklęć, trening, podróże, walka wręcz i dystansowa (F – broń), pancerz,
  śmierć i przeszukiwanie ciał, zaklęcia i moce (R – przygotuj, M – okno magii), działające efekty, pociski czarów,
  mikstury, składniki, alchemia, przedmioty zaklęte, pułapka dusz, zaklinanie (samodzielne i u zaklinacza);
  MGEF/ENCH w konwerterze (eksport świata v7 – „Aktualizuj” w launcherze); zapis v4/v5 z migracją. Latanie
  testowe przeniesione z F na F6. MCP-openMW 0.10.0: porównanie wzorów z OpenMW na tych samych wejściach –
  156/156 zgodnych (3152 liczby).
* Etap 6: dialogi, zadania i dziennik – rekordy DIAL/INFO (kolejność odpowiedzi jak OpenMW, eksport świata v6 –
  „Aktualizuj” w launcherze), filtr odpowiedzi, powitania, tematy z hiperłączami, pytania, skrypty wyniku,
  podstawienia (%PCName…), postawa i perswazja, frakcje gracza, dziennik z datą i dziennik tematów; okno rozmowy
  (E na NPC) i dziennika (J); tłumaczenia dialogów z lokalizacji RLF; zapis v3 z migracją. Odbiór: rozmowa
  z Caiusem Cosadesem na danych z gry – wstąpienie do Blades i zadanie „Antabolis Informant” z wpisem w dzienniku.
* Etap 5: MWScript – kompilator skryptów w konwerterze, maszyna skryptów w grze (skrypty startowe i lokalne,
  zmienne, Enable/Disable, OnActivate, dziennik, przedmioty, pozycje, komunikaty), stan skryptów w zapisie,
  raport nieobsługiwanych funkcji; Raven Rock po starcie zgodny z OpenMW (344/344 obiektów). Eksport świata v5.
* Etap 4: postać gracza – statystyki początkowe, wartości pochodne i zdolności ras/znaków jak w OpenMW,
  obrażenia od upadku, kreator postaci przy nowej grze, pasek zdrowia/magii/kondycji; rekordy SPEL
  (eksport świata v4 – „Aktualizuj” w launcherze).
* Etap 3: pojemniki, listy poziomowane (jak OpenMW), ekwipunek gracza i NPC z list, pochodnie NPC nocą,
  aktywacja (E) – drzwi z zamkami i pułapkami, podnoszenie i odkładanie przedmiotów, okno pojemnika i ekwipunku (I);
  pływanie; minimalny dźwięk (efekty SOUN, kroki); zapis v2 z migracją. Konwerter: nowe rekordy, dźwięki,
  eksport świata v3 (wymaga „Aktualizuj” w launcherze).
* Etap 2 ukończony: NPC i stworzenia jako `MWActor` (bez AI); porównanie 13 NPC z Seyda Neen i Balmory z OpenMW –
  wygląd i ekwipunek zgodne w 12 ujęciach (różnica: listy poziomowane strażnika cesarskiego – etap 3).
  MCP-openMW 0.9.0: `openmw_capture_npcs`, zamrażanie aktorów w OpenMW, kolejka ujęć; zrzuty Godota bez vsync.
* Etap 2c: NPC w ubraniach i zbrojach – automatyczne zakładanie ekwipunku jak w OpenMW (InventoryStore::autoEquip:
  broń wg umiejętności, zbroja wg pancerza skorygowanego umiejętnością i porównania z walką bez zbroi, ubrania wg
  wartości, zakazy dla ras zwierzęcych; umiejętności z autoobliczaniem) i priorytety części (NpcAnimation::updateParts:
  zbroja > ubranie > ciało, szata i spódnica zasłaniają nogi, hełm zdejmuje włosy, tarcza w lewej ręce; broń
  schowana). Na razie bez list poziomowanych w inwentarzu i pochodni nocą (`mw_equipment.gd`).
* Konwerter (nif2gltf-0.1.1): transformacja korzenia NIF stosowana jak w OpenMW (wcześniej zerowana – części
  ciała z modów z obróconym korzeniem, np. uda Dark Elfa, leżały poziomo). Pamięć podręczna 0.1.0 pozostaje
  ważna dla modeli z korzeniem jednostkowym, więc „Aktualizuj” konwertuje ponownie tylko modele, których to dotyczy.
* Etap 2: NPC składani z części ciała jak w OpenMW (szkielet base_anim/female/kna → Skeleton3D, części rasy
  BODY ze skinningiem przepinane na kości po nazwach, części sztywne na kościach mocowania z lustrem lewej strony,
  głowa i włosy z rekordu NPC, zastępcze męskie części dla kobiet, pomijanie „1st”); animacje bezczynności NPC
  (xbase_anim + żeńskie/zwierzęce z pierwszeństwem) i stworzeń; konwerter dodaje modele aktorów i ścieżki GLB
  w rekordach BODY (`mw_actor_visual.gd`, test `test_actors.gd`).
* Woda: falowanie i wzór we współrzędnych świata – bez szczelin na łączeniach komórek.
* Gra `mw_flora.gd`: MultiMesh, bez kolizji i cieni, test alfa, normalne w górę; zasięg i gęstość w ustawieniach.
* Launcher: zakładka Świat (odpowiednik world.cfg forka), opcje roślinności w zakładce Grafika.

## 0.4 — 2026-11-15: lokalizacja runtime z forka OpenMW RLF (etap 1, `docs/PORT-RLF.md`)

* Konwerter: pliki `localization/language/<wtyczka>.yaml` (format forka) w kolejności ładowania →
  `world/localization/<JĘZYK>/`; nadpisywanie per język, warianty INFO, znaczniki, `fallbacks`, odcisk zmian.
* Gra: `MWLocalization` – język wybierany w trakcie działania (Ustawienia → Język → „Język gry”), nazwy
  regionów, wnętrz i drzwi po przetłumaczeniu, formatowanie w pasku (BBCode), znacznik QA.
* Launcher: przed startem gry import projektu, jeśli skrypty zmieniły się od ostatniego importu.
* Zależność: `python3-yaml`.

## 0.3.1 — 2026-11-15: licencja GPL-3.0-or-later

* Licencja całego projektu zmieniona z MIT na **GPL-3.0-or-later** (jak OpenMW), żeby móc korzystać z kodu
  forka OpenMW RLF i oryginalnego OpenMW. Projekt opublikowany na gałęzi `OpenMWGoDot` repozytorium
  `homoklikus/OpenMW-Runtime-Localization-Fork`; gałąź `0.5-world` zamrożona (blokada + tag `0.5-world-final`).
* Poprawki po pierwszym uruchomieniu u gracza: katalog konwersji poza repozytorium, uszkodzone tekstury przy
  duplikatach .dds/.tga, wypiekanie ze świeżego GLB, ukryte znaczniki edytora, start w mieście, współrzędne (F3/F4).

## 0.3 — 2026-11-15 (sesja 3): osobny launcher

* **Nowy launcher Qt 6 (PySide6)** `launcher/`: ekran główny 1024×683 wg grafiki referencyjnej (menu boczne,
  baner, stan instalacji z podglądem, aktywny profil, szybkie akcje, ozdobny „Graj”, ostatnie działania,
  pasek stanu), paleta kolorów z próbek referencji, własne godło i proceduralne grafiki zamiast logo
  i ilustracji Bethesdy, opcjonalny lokalny motyw `~/.config/openmwgodot/theme/`, kreator pierwszego uruchomienia, strony Konwersja / Mody / Ustawienia, zarządzanie
  profilami, uruchamianie gry i Construction Set w osobnych procesach, ciemny motyw i własne godło,
  skrót w menu KDE (`tools/install_launcher.sh`).
* **Usunięty launcher-scena Godota** (sesja 2) – wymaganie: launcher nie może inicjalizować silnika;
  jego logika (wykrywanie, postęp) przeniesiona do `mwcore` i launchera Qt. Scena startowa projektu
  Godota to znów `main.tscn`.
* **`mwcore`** – wspólna warstwa danych: katalogi XDG/przenośne, atomowy JSON, konfiguracja i schemat
  ustawień, profile, instalacja i walidacja Morrowinda, mody (bezpieczne archiwa ZIP/7z, warstwy,
  kolejność, zależności, konflikty), plan i stan konwersji, polecenia i blokady procesów.
* **Konwerter**: anulowanie SIGTERM/SIGINT z zachowaniem ukończonych zasobów (kod 130), blokada katalogu
  (`convert.lock`), odtwarzanie uszkodzonej bazy cache, `verify` / `clean`, nakładka profilu na wspólną
  bazę (`--base-out`), zdarzenia `stage` dla każdego etapu, `asset_error`, `warning`, `cancelled`,
  lekki moduł nagłówka ESM (`mwconv/esm/header.py`, bez numpy).
* **Runtime**: wiele katalogów danych (`--base`), ustawienia z pliku (`--settings`: okno, rozdzielczość,
  V-Sync, limit FPS, skala 3D, cienie, zasięg, odległość widzenia, woda, mgła, czułość i odwrócenie myszy),
  kod wyjścia 2 przy braku danych, tryb `--autotest-frames` dla testów integracyjnych.
* **CS 2.0**: wtyczka czyta argumenty z launchera (`--data`, `--project`, `--base`) i od razu wczytuje świat.

## 0.2 — 2026-11-15 (sesja 2)

Trudne przypadki NIF i diagnostyka (`scan`, `inspect`), kontrolery/morfy/cząsteczki/.kf, woda, drzwi,
pora dnia i pogoda, strumieniowe ESM, wypiekanie `.scn`, CS 2.0 (teren, rekordy, konflikty), zgodność z Godot 4.7.

## 0.1 — 2026-11-15 (sesja 1)

Konwerter NIF/ESM/BSA/LAND → GLB + model świata, runtime Godot, prototyp CS 2.0.
