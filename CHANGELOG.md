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
* Etap 8: AI, nawigacja i reakcje świata – siatki ścieżek PGRD (eksport świata v8 – „Aktualizuj” w launcherze;
  A* i składowe spójne jak OpenMW), pakiety AI z rekordów i skryptów (wander, travel, escort, follow, activate;
  AiWander/AiTravel/AiEscort/AiFollow/AiActivate, GetAIPackageDone, GetCurrentAIPackage), powitania (Hello),
  animacje chodu i biegu, wykrywanie gracza (skradanie – Ctrl, niewidzialność, kameleon), AI walki (broń, czary,
  łuki, ucieczka), przestępstwa (kradzież, wtargnięcie, napaść, morderstwo), świadkowie wg Alarm, pościg i rozmowa
  strażnika, grzywna i konfiskata, więzienie (znaczniki z `world/markers.json`), wytrychy i sondy (Security),
  pułapki rzucają czar; pozycje i stan AI NPC w zapisie. Koniec „dryfu” NPC (kolizje modeli).
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
