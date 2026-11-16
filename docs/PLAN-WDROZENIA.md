# OpenMWGodot — plan wdrożenia całej gry

**Rewizja 2.0 — 2026-11-15**

Gałąź rozwojowa: `OpenMWGoDot`  
Punkt odniesienia OpenMW RLF: `0.5-world-final`  
Poprzednia roadmapa (rewizja 1): `docs/archiwum/PLAN-WDROZENIA-rev1.md`

## 1. Cel projektu

OpenMWGodot ma umożliwiać uruchomienie Morrowinda na silniku Godot, z zachowaniem oryginalnego świata, mechaniki gry, fabuły, modów i obsługi lokalizacji.

Projekt nie jest rekonstrukcją świata wykonywaną ręcznie. Oryginalne pliki Morrowinda pozostają źródłem danych, które są lokalnie konwertowane do formatu wykorzystywanego przez Godota.

Wizualnie projekt może rozwijać się jako remaster. Zgodność mechaniki i danych nie oznacza obowiązku kopiowania ograniczeń renderera OpenMW.

**Priorytet: działająca gra rozwijana małymi, weryfikowalnymi etapami.**

## 2. Zasady architektoniczne

### 2.1. Oddzielenie danych bazowych od stanu gry

- Dane świata utworzone przez konwerter są traktowane jako niemodyfikowalne podczas rozgrywki.
- `GameState` przechowuje zmiany: pozycje obiektów, ekwipunek, stan postaci, zmienne skryptów, zadania i inne informacje.
- Construction Set zapisuje zmiany w osobnych warstwach edycyjnych, nie w plikach stanu rozgrywki.
- Zapis gry nie może zależeć od ścieżek do scen Godota ani od tymczasowych identyfikatorów węzłów.

### 2.2. Stabilne identyfikatory

Każdy rekord i każda instancja obiektu w świecie musi mieć stabilną tożsamość.

Rozróżniamy:

- ID definicji rekordu, np. typ NPC, przedmiotu czy drzwi.
- ID konkretnej instancji w komórce świata.
- ID dynamicznych instancji utworzonych podczas gry.
- Informację o źródłowym pluginie i warstwach nadpisania.

Nie wolno opierać trwałych identyfikatorów wyłącznie na indeksie tablicy, kolejności importu, ścieżce do pliku GLB ani nazwie węzła Godota.

Konwerter musi uwzględniać semantykę identyfikacji referencji w ESM/ESP, także przy nadpisaniach i zmianie kolejności modów.

### 2.3. Wersjonowanie formatów

Wersjonowaniu podlegają:

- Format danych świata.
- Schematy rekordów.
- API warstwy runtime.
- Format zapisu gry.
- Manifest profilu/modów.

**Nie zamrażamy całego schematu danych na etapie 2.**

Stabilizujemy podstawowy kontrakt, ale dopuszczamy rozszerzanie i kontrolowane zmiany niekompatybilne.

Zmiana niekompatybilna wymaga nowej wersji i odpowiedniej migracji lub ponownej konwersji. Nie wolno zmieniać znaczenia istniejącego pola bez zmiany wersji.

### 2.4. Bezpieczne zapisy gry

Zapis zawiera:

- Wersję formatu.
- Identyfikator postaci i profilu.
- Manifest zestawu aktywnych modów oraz ich kolejności ładowania.
- Identyfikator lub odcisk wersji danych bazowych.
- Zmiany przechowywane przez `GameState`.
- Informacje potrzebne do migracji.

Migracje powinny zachowywać nieznane, zgodne dane, jeśli to możliwe.

Brakujący mod lub rekord nie może powodować cichego usuwania obiektów z zapisu.

W przypadku niezgodności system powinien wykrywać problem, informować użytkownika i zachowywać oryginalny zapis.

Zapisy atomowe, kopie bezpieczeństwa przed migracją oraz testy odtwarzania są obowiązkowe.

### 2.5. Wspólny model aktora

`MWActor` jest wspólną podstawą gracza, NPC i stworzeń.

Udostępnia wspólne mechanizmy dotyczące pozycji, ruchu, statystyk, animacji, efektów i stanu.

Różnice między typami aktorów implementujemy przez wyspecjalizowane komponenty lub kontrolery.

Nie tworzymy trzech niezależnych silników postaci.

### 2.6. Oddzielne komponenty

Launcher, konwerter, runtime Godot, Construction Set i MCP mogą rozwijać się niezależnie.

Łączą je dokumentowane kontrakty danych, wspólne usługi oraz jawne interfejsy.

Nie zakładamy, że zmiana komponentu wymaga przebudowy wszystkich pozostałych.

### 2.7. Testowanie

Weryfikacja ma trzy poziomy:

1. Automatyczne testy syntetyczne.
2. Integracyjne testy na rzeczywistych danych Morrowinda, wykonywane lokalnie.
3. Porównania z OpenMW tam, gdzie rzeczywiście istnieje wymóg zgodności.

Nie wymagamy podobieństwa piksel po pikselu.

Oddzielnie oceniamy poprawność geometrii, rozmieszczenia obiektów, logiki gry, mechaniki, animacji i wyglądu.

Świadoma poprawa oświetlenia czy efektów wizualnych nie jest regresją tylko dlatego, że obraz różni się od OpenMW.

### 2.8. Wymagania dotyczące zasobów

Nie publikujemy oryginalnych ani przekonwertowanych zasobów Morrowinda w repozytorium.

Konwersja odbywa się lokalnie z instalacji posiadanej przez użytkownika.

Dane referencyjne zawierające zasoby gry pozostają poza publicznymi artefaktami.

## 3. Aktualny stan projektu

Stan wynikający z dotychczasowej dokumentacji oraz prac do commita `193afc0`.

| Obszar | Status |
|---|---|
| Konwerter NIF, KF, tekstur, ESM/ESP, BSA | Działający prototyp na pełnej instalacji gry |
| Teren i statyczne obiekty świata | Działają |
| Wnętrza i drzwi | Działają, przejścia korzystają z teleportacji |
| Woda, pogoda, cykl dnia | Podstawowa implementacja |
| Remiros Groundcover | Działa w siedmiu regionach |
| Lokalizacja YAML | Podstawowa obsługa nazw |
| Launcher i manager modów | Działający prototyp |
| Construction Set 2.0 | Działający prototyp |
| MCP i zrzuty porównawcze | Narzędzia istnieją, stanowisko porównawcze jest rozwijane |
| Pełny model NPC i stworzeń | Nieukończony |
| Skrypty, dialogi, RPG i AI | Nieukończone |
| Zapis gry, pełne UI i audio | Nieukończone |

Status „działa” nie oznacza kompletnej zgodności z OpenMW ani braku błędów.

## 4. Roadmapa główna

### Etap 0 — Fundamenty runtime

**Priorytet: najwyższy.**

Zakres:

- `GameState` jako centralny system zmian świata.
- Stabilne ID rekordów i referencji.
- Format zapisu v1 oraz migracje.
- Manifest aktywnego profilu modów.
- `MWActor` jako wspólny model postaci.
- System zdarzeń i akcji wejścia.
- Obsługa obiektów początkowo wyłączonych.
- Minimalny HUD, menu pauzy oraz zapis/odczyt.
- Integracja obecnego stanowiska porównawczego.

**Odbiór:**

Można przemieszczać się po świecie, zapisać grę, zakończyć proces, uruchomić grę ponownie i wrócić do tej samej pozycji oraz czasu gry.

Stan wyłączonych lub zmienionych obiektów pozostaje zachowany.

Dotychczasowe funkcje świata nie ulegają regresji.

### Etap 1 — Komplet podstawowych danych postaci i przedmiotów

Rozszerzamy konwerter o pola wymagane przez kolejne funkcje.

Priorytetowe typy:

- `NPC_`, `CREA`, `RACE`, `CLAS`, `FACT`.
- `BODY`, `BSGN`, `SKIL`.
- Rekordy przedmiotów i ich właściwości.
- `GMST`, `GLOB`.
- Podstawowe dane statystyk.

Pozostałe typy (`MGEF`, `SPEL`, `ENCH`, `ALCH`, `INGR`, `LEVI`, `LEVC`, `DIAL`, `INFO`, `SCPT`, `SOUN`, `SNDG` i inne) rozwijamy zgodnie z potrzebami następnych etapów.

Nie wymagamy ukończenia i ostatecznego zamrożenia wszystkich schematów przed rozpoczęciem pracy nad NPC.

**Odbiór:**

Poprawna interpretacja rekordów i nadpisań w reprezentatywnej próbie danych porównanych z OpenMW.

Nie stosujemy sztywnej liczby 1000 rekordów każdego typu. Dla dużych kategorii używamy próbkowania, a przypadki graniczne testujemy celowo.

### Etap 2 — NPC, stworzenia i animacje

Zakres:

- Składanie postaci z części ciała.
- Rasy, płeć, głowy i włosy.
- Ubrania, zbroje i broń.
- Szkielety, animacje bazowe i pliki `.kf`.
- Animacje bezczynności, chodzenia i biegania.
- Poprawne pozycjonowanie postaci w komórkach.
- Współpraca z `MWActor`.

Na tym etapie NPC mogą być statyczni lub używać prostych zachowań demonstracyjnych.

Nie implementujemy jeszcze pełnego AI.

**Odbiór:**

Seyda Neen i Balmora są zaludnione poprawnymi modelami NPC. Stworzenia są widoczne w odpowiednich miejscach i mają podstawowe animacje.

Brak pozy T dla poprawnie obsługiwanych modeli.

### Etap 3 — Gracz, przedmioty i podstawowe interakcje

Zakres:

- Docelowy kontroler postaci.
- Ruch, skok, pływanie, upadek i kolizje.
- Aktywowanie obiektów.
- Podnoszenie i odkładanie przedmiotów.
- Pojemniki.
- Podstawowe zamki i pułapki.
- Ekwipunek.
- Podpowiedzi przedmiotów i lokalizacja.
- Minimalny system audio: zdarzenia, kroki i interakcje.

**Odbiór:**

Gracz podnosi przedmiot, wkłada go do pojemnika, zapisuje grę, odczytuje zapis i zastaje przedmiot we właściwym miejscu.

Interakcje zachowują trwałą tożsamość obiektów.

### Etap 4 — Podstawy postaci RPG

Zakres:

- Atrybuty i umiejętności.
- Rasy, klasy i znaki zodiaku.
- Początkowe statystyki.
- Zdrowie, mana, kondycja.
- Podstawowa reprezentacja efektów i wyposażenia.
- Minimalny interfejs tworzenia postaci.

Pełna oprawa graficzna kreatora może zostać dopracowana później.

**Odbiór:**

Można stworzyć postać z właściwymi parametrami początkowymi, zapisać ją i poprawnie odtworzyć.

### Etap 5 — MWScript i logika świata

Zakres:

- Konwersja lub kompilacja skryptów do formatu wykonywalnego przez runtime.
- Maszyna wykonująca skrypty.
- Zmienne globalne i lokalne.
- Skrypty startowe.
- Obsługa referencji.
- Funkcje `Enable` i `Disable`.
- Funkcje związane z przedmiotami i aktorami.
- Raportowanie nieobsługiwanych instrukcji.

Wdrażamy grupami, zgodnie z faktycznymi zależnościami.

**Odbiór:**

Skrypty wpływają na świat w sposób zgodny z OpenMW.

Obiekty wyłączone na początku gry, w tym odpowiednie elementy Raven Rock, nie są widoczne przed aktywacją.

Stan skryptów przeżywa zapis i odczyt gry.

### Etap 6 — Dialogi, zadania i dziennik

Zakres:

- `DIAL` i `INFO`.
- Filtry dialogowe.
- Tematy i powitania.
- Dziennik i etapy zadań.
- Wyniki dialogów i ich skrypty.
- Podstawowa perswazja.
- Lokalizacja dialogów.

**Odbiór:**

Gracz może rozmawiać z Caiusem Cosadesem, otrzymać zadanie i zobaczyć prawidłowy wpis w dzienniku.

To test działającego fragmentu fabuły, nie deklaracja pełnej grywalności początku Morrowinda.

### Etap 7 — Walka, magia i pozostała mechanika RPG

Zakres:

- Walka wręcz i dystansowa.
- Trafienia, obrażenia i śmierć.
- Magia, efekty i zaklęcia.
- Mikstury, alchemia i zaklinanie.
- Rozwój umiejętności.
- Awansowanie postaci.
- Handel i podstawowe usługi.
- Mechanika podróży i pozostałych usług NPC.

**Odbiór:**

Podstawowe scenariusze walki, rzucania czarów, handlu i awansowania działają.

Wzory mechaniki są porównywane z OpenMW na tych samych wejściach.

### Etap 8 — AI, nawigacja i reakcje świata

Zakres:

- Nawigacja z wykorzystaniem danych `PGRD` i odpowiednich rozwiązań Godota.
- Pakiety AI: wander, travel, escort, follow, activate.
- Wykrywanie zagrożeń.
- AI walki.
- Przestępstwa, świadkowie i strażnicy.
- Zachowania niezależne od aktualnie renderowanych komórek.
- Zapisywanie stanu aktorów.

**Odbiór:**

NPC poruszają się zgodnie z oczekiwaniami, reagują na gracza i zachowują logiczny stan po zmianie komórki oraz odczycie zapisu.

Straż reaguje na wykryte przestępstwo.

### Etap 9 — Integracja pełnej rozgrywki

To etap, w którym wcześniejsze mechaniki zaczynają być oceniane jako jedna gra.

Zakres:

- Integracja zadań z AI, walką i usługami.
- Scenariusze obejmujące wiele komórek.
- Przestępstwa, podróżowanie i efekty magiczne w rzeczywistych zadaniach.
- Testy stanów granicznych skryptów.
- Testy zapisu i migracji.
- Testy przy zmianach modów.

**Odbiór:**

Można przejść uzgodniony fragment początku Morrowinda od utworzenia postaci, przez Seyda Neen, do wykonania zadania w Balmorze.

Scenariusz zawiera prawdziwe interakcje, dialogi, wymagane zachowania NPC i trwały zapis gry.

### Etap 10 — Pełny interfejs i oprawa

Zakres:

- Mapa lokalna i świata.
- Pełne menu postaci, magii, alchemii i ekwipunku.
- Książki i zwoje.
- Pełny kreator postaci.
- Ustawienia dostępne w grze.
- Dźwięki otoczenia, głosy i muzyka kontekstowa.
- Dopracowanie nieba, mgły, wody, cieni i oświetlenia.
  - Woda: pełne poziomy odbić jak OpenMW „reflection detail” 0–5 (niebo → teren → statyki, aktywatory i drzwi →
    przedmioty, pojemniki i cząsteczki → aktorzy → roślinność; we wnętrzach co najmniej 2) – druga kamera
    odbijająca, warstwy renderowania wg rodzaju obiektu, rozdzielczość odbicia („rtt size” 512/1024/2048);
    przełącznik załamania („refraction”) i kręgi deszczu („rain ripple detail” 0–2). Teraz (10h): odbija się
    tylko niebo (poziom 0).
- Ulepszenia graficzne remastera.

Część tych prac można prowadzić wcześniej, równolegle, jeżeli nie blokują podstaw rozgrywki.

**Odbiór:**

Pełen zestaw najważniejszych ekranów i systemów prezentacji działa, a rozgrywka pozostaje zgodna z wcześniejszymi etapami.

### Etap 11 — Wydajność, kompatybilność i wydanie

Zakres:

- Streaming świata i zasobów.
- LOD oraz optymalizacja pamięci.
- Ograniczanie przycięć.
- Prefetch wnętrz i płynne przejścia.
- Opcjonalne maskowanie teleportacji animacją drzwi.
- Testy na rozbudowanych zestawach modów.
- Instalatory i paczki Linux/Windows.
- Dokumentacja użytkownika.

**Odbiór:**

Gra działa stabilnie na docelowych platformach, ma określone wymagania sprzętowe i przechodzi zestaw scenariuszy regresyjnych.

Bezszybowe przejścia nie wymagają fizycznego umieszczania wszystkich wnętrz wewnątrz modeli budynków.

Optymalizacja powinna być prowadzona przez cały projekt, a nie rozpoczynana dopiero na etapie 11.

## 5. Tory równoległe

### Launcher

Niezależna aplikacja desktopowa.

Rozwijamy:

- Konwersję zasobów.
- Instalowanie i aktywowanie modów.
- Profile.
- Ustawienia.
- Przycisk „Graj”.
- Uruchamianie Construction Set.

Nie dublujemy logiki konwertera.

Nie dodajemy obsługi osobistego klucza Nexus API bez zatwierdzonego mechanizmu integracji.

### Construction Set 2.0

Rozwijany równolegle z formatem danych.

Wspiera stopniowo nowe kategorie rekordów, dialogi, skrypty i edycję świata.

Zmiany edytora nie mogą modyfikować oryginalnych zasobów Morrowinda ani zapisów rozgrywki.

### MCP-openMW

Narzędzia porównawcze rozwijamy na aktywnej gałęzi `OpenMWGoDot`, w katalogu `tools/MCP-openMW/`, dopóki nie zostanie podjęta decyzja o osobnym repozytorium.

Gałąź `0.5-world` pozostaje zamrożona i nie może być modyfikowana.

MCP może nadal wykorzystywać zainstalowany fork OpenMW jako środowisko referencyjne.

Potrzebne narzędzia:

| Etap | Narzędzie |
|---|---|
| 0 | Profil porównawczy OpenMW ↔ Godot i zestaw regresji |
| 1 | Porównywanie rekordów |
| 2 | Inspekcja modeli i animacji aktorów |
| 5 | Śledzenie skryptów |
| 7 | Porównanie wzorów RPG |
| 8 | Porównanie zachowań AI |

Nie wszystkie narzędzia muszą powstać od razu.

## 6. Zasady testowania i odbioru

Każdy etap musi mieć:

- Zdefiniowany cel.
- Testy automatyczne.
- Scenariusz integracyjny.
- Informację o znanych ograniczeniach.
- Potwierdzenie testów lokalnych, jeśli dotyczą rzeczywistych zasobów gry.
- Aktualizację dokumentacji i `CHANGELOG.md`.

Rozróżniamy:

**Zgodność obowiązkowa:** dane świata, rozmieszczenie obiektów, identyfikatory, mechanika RPG, logika skryptów, zadania, stany zapisów.

**Zgodność referencyjna:** sylwetki modeli, animacje, tekstury, oświetlenie, woda, mgła i efekty wizualne.

Świadome ulepszenia graficzne mogą odbiegać od OpenMW, pod warunkiem że nie powodują błędów geometrii lub rozgrywki.

Nie wymagamy wielogodzinnego ręcznego sprawdzania każdej drobnej poprawki.

Rozszerzamy automatyczne testy regresji, ale nie blokujemy rozwoju arbitralnymi progami podobieństwa obrazu.

## 7. Kamienie milowe dla użytkownika

| Kamień milowy | Rezultat |
|---|---|
| A — Świat pamięta | Można zapisać i wczytać rozgrywkę |
| B — Świat żyje wizualnie | NPC i stworzenia mają poprawne modele oraz animacje |
| C — Świat reaguje | Można korzystać z ekwipunku i przedmiotów |
| D — Świat opowiada | Działają dialogi, skrypty i zadania |
| E — Świat walczy | Działają magia, walka, statystyki i AI |
| F — Morrowind jest grywalny | Da się przejść kompletny fragment fabuły |
| G — Remaster | Rozbudowana oprawa, optymalizacja i kompatybilność |

Kamienie milowe służą do oceny postępów, nie zastępują etapów technicznych.

## 8. Najbliższe działania

1. Ukończyć etap 0, wykorzystując istniejący system porównań i MCP.
2. W pierwszej kolejności przygotować stabilną identyfikację referencji, `GameState`, manifest profilu i zapis v1.
3. Przenieść sterowanie gracza na wspólny model `MWActor`.
4. Zweryfikować zapis i odczyt na rzeczywistym świecie Morrowinda.
5. Rozpocząć import kompletnych postaci i animacji.
6. Kontynuować prace nad launcherem i CS 2.0 równolegle.

Nie powtarzamy już opublikowanych commitów ani prac, które zostały ukończone i potwierdzone testami.

## 9. Zarządzanie zmianami planu

Roadmapa jest dokumentem aktualizowanym wraz z rozwojem projektu.

Każda istotna zmiana kolejności, kontraktu lub kryterium odbioru powinna być odnotowana w dokumencie.

Opus zachowuje autonomię techniczną w zakresie implementacji.

Nie rozpoczynamy przebudowy stabilnych systemów bez konkretnej potrzeby i uzasadnienia.

**Nadrzędna zasada: każda większa faza powinna przybliżać nas do działającej, grywalnej wersji Morrowinda, a nie wyłącznie do bardziej rozbudowanego szkieletu silnika.**
## Załącznik: stan realizacji

| Data | Etap | Stan |
|---|---|---|
| 2026-11-16 | 0 | **Ukończony.** Stabilne ID referencji (`<plik źródłowy>#<refnum>`, niezależne od kolejności modów – już były); `GameState` + zapis v1 (`docs/FORMAT-ZAPISU.md`) z manifestem wtyczek profilu, migracjami, kopiami i zapisem atomowym; `MWActor` + kontroler gracza; szyna zdarzeń; akcje wejścia; HUD + menu pauzy (Esc), F5/F9, `--load`. Stanowisko porównań: MCP-openMW 0.8.0 w `tools/MCP-openMW`, profil `openmwgodot`. Odbiór na prawdziwych danych: zapis → nowy proces → odczyt daje identyczny obraz (bajt w bajt); 8 ujęć regresji bez zmian po przebudowie gracza. Obiekty „początkowo wyłączone”: mechanizm w `GameState` gotowy; w Morrowindzie wyłączają je skrypty (np. Raven Rock) – pełne działanie w etapie 5. |
| 2026-11-16 | 1 | **Ukończony.** Konwerter: `world/records/` – 20 typów (NPC_, CREA, RACE, CLAS, FACT, BODY, BSGN, SKIL, WEAP, ARMO, CLOT, BOOK, MISC, APPA, LOCK, PROB, REPA, LIGH, GMST, GLOB), scalanie wg kolejności ładowania z historią nadpisań, reguły OpenMW dla przypadków granicznych (GLOB z NaN → floatCast, powtórzona reakcja frakcji → najniższa). Pełna gra: 10 189 rekordów w 4,5 s. MCP-openMW: `openmw_record_compare_start/status` – zrzut rekordów z silnika OpenMW przez Lua i porównanie pole po polu. Odbiór: próbka 2073 rekordów (wszystkie nadpisane przez Tribunal/Bloodmoon do 50 na typ + losowe) + 300 GMST + zmienne globalne, 20 029 pól – **0 rzeczywistych niezgodności** (ostatnie 2 to porównanie „brak tekstu” vs „pusty tekst”, poprawione w narzędziu). Pozostałe typy (MGEF, SPEL, ENCH, ALCH, INGR, LEVI, LEVC, DIAL/INFO, SCPT, SOUN…) – wg potrzeb kolejnych etapów. |
| 2026-11-16 | 2 | **Ukończony (z jednym znanym brakiem).** NPC składani jak w OpenMW (`mw_actor_visual.gd`): szkielet `base_anim`/`_female`/`kna` → `Skeleton3D`, części ciała rasy ze skinningiem przepinanym po nazwach kości i sztywne na kościach mocowania (lustro lewej strony), głowa i włosy z rekordu, zastępcze męskie części dla kobiet; animacje `xbase_anim` (+ żeńskie/zwierzęce) i bezczynność stworzeń; ekwipunek (`mw_equipment.gd`): `autoEquip` (broń wg umiejętności, zbroja wg pancerza skorygowanego umiejętnością i progu walki bez zbroi, ubrania wg wartości, zakazy ras zwierzęcych, autoobliczane umiejętności) i priorytety części (`updateParts`: zbroja > ubranie > ciało, szata/spódnica, hełm zdejmuje włosy, tarcza; broń schowana). NPC i stworzenia są węzłami `MWActor` (bez AI – etap 8). Konwerter: transformacja korzenia NIF jak w OpenMW (`nif2gltf-0.1.1`, ponowna konwersja tylko 502 modeli z obróconym korzeniem). MCP-openMW 0.9.0: ujęcia NPC z przodu (`openmw_capture_npcs`), zamrażanie aktorów w OpenMW na czas ujęcia, kolejka ujęć. Odbiór (przebieg `Raporty/mcp/zrzuty/2026-11-16-081415-porownanie`, 13 NPC z Seyda Neen i Balmory): wygląd, ubrania i zbroje zgodne z OpenMW w 12 ujęciach; różnica w 1 – strażnik cesarski ma w OpenMW hełm, naramienniki, tarczę i spódnicę z **list poziomowanych** (LEVI w inwentarzu – etap 3). Różnice oświetlenia – etap 10; pozy w OpenMW to zamrożone klatki chodu/pływania (porównanie referencyjne). Brak: pochodnie NPC nocą (etap 3), animacje chodu/biegu w ruchu (gotowe w bibliotece, użyje ich AI w etapie 8). |
| 2026-11-16 | 3 | **Ukończony (zakres podstawowy).** Konwerter: rekordy CONT, LEVI, LEVC, ALCH, INGR, DOOR, ACTI, SOUN; pliki dźwięków efektów (`sound/`, WAV/MP3 bez konwersji). Zapis v2 (`docs/FORMAT-ZAPISU.md`): inwentarze, przedmioty położone w świecie (`dyn#N`), ziarno losowania, zamki/pułapki; migracja v1→v2. `MWInventory`: zawartość pojemników i NPC z listami poziomowanymi jak OpenMW (`getLevelledItem`, flagi „każdy”/„wszystkie poziomy”, szansa braku, zagnieżdżenia), losowanie deterministyczne; ekwipunek NPC z list (strażnik cesarski dostaje hełm, naramienniki, tarczę, spódnicę) i pochodnie po zmroku (`useTorches`). `MWInteraction` + okno: podpowiedzi, podnoszenie (złoto jak OpenMW), pojemniki (przenoszenie, „weź wszystko”), ekwipunek (I) i odkładanie przedmiotów, zamki z kluczami, pułapki (rozbrajanie; efekt czaru – etap 7). Ruch: pływanie (`isSwimming`, fSwimHeightScale), sygnał upadku (obrażenia – etap 4). Dźwięk: `MWAudio` (3D, zasięgi z SOUN × mnożniki GMST), dźwięki przedmiotów wg klasy, drzwi, zamków, kroki gracza. Odbiór: test syntetyczny (podnieś → do pojemnika → zapis → odczyt) i ten sam scenariusz na prawdziwych danych (Seyda Neen: latarnia → beczka, zapis, odczyt – przedmiot w beczce, nie u gracza, nie w świecie); 530 dźwięków Morrowinda wczytywanych przez Godota. Brak (wg planu dalej): kradzież i właściciele (etap 8), wytrychy i sondy (etap 7), obrażenia od upadku (etap 4), kroki NPC i dźwięki zbroi (etap 10), sprzedaż/uzupełnianie kupców (etap 7). |
| 2026-11-16 | 4 | **Ukończony (zakres podstawowy).** Konwerter: rekordy SPEL (eksport świata v4). `MWCharacter`: statystyki początkowe jak OpenMW `buildPlayer` (atrybuty rasy wg płci, umiejętności 5 + premia rasy, +10 ulubionym atrybutom klasy, +25/+10 umiejętnościom głównym/drugorzędnym, +5 specjalizacji; moce i zdolności rasy oraz znaku), wartości pochodne (zdrowie z bazowych siły i wytrzymałości, magia = inteligencja × (fPCbaseMagickaMult + 0,1 × wzmocnienie maks. magii), kondycja), stałe efekty zdolności/chorób/klątw (wzmocnienie atrybutów, umiejętności, zdrowia, magii, kondycji, maks. magii), współczynnik zmęczenia i obrażenia od upadku (`getFallDamage`). Minimalny kreator (imię, rasa, płeć, głowa, włosy, klasa, znak, podgląd statystyk) przy nowej grze z launchera; pasek: imię, zdrowie, magia, kondycja. Postać w zapisie (`player.character`). Odbiór: test syntetyczny (wartości wyliczone ręcznie wg wzorów OpenMW, kreator → zapis → odczyt) i prawdziwe dane: Bretonka magiczka/Mag – magia 120, Altmer czarodziej/Atronach – 270, Cesarski rycerz/Uczeń – 100, Argonianin złodziej/Dama – wytrzymałość i osobowość 55, kondycja 185 (zgodne z wzorami i znanymi wartościami gry). Brak (wg planu dalej): czary startowe `autoCalcPlayerSpells` i rzucanie (etap 7), rozwój umiejętności i awans (etap 7), pytania o klasę i własna klasa (etap 10), śmierć (etap 7). |
| 2026-11-16 | 5 | **Ukończony (zakres podstawowy).** Konwerter: kompilator MWScript (`mwconv/mwscript.py`) – źródła SCTX → drzewo składni w `world/records/script.json` (składnia jak w OpenMW, tolerancja błędów spotykanych w danych: nadmiarowe `endif`, `[ ]`, `=` w warunku, `obiekt->( … )`); 1231 skryptów Morrowind/Tribunal/Bloodmoon, 1 z błędem składni; skrypty startowe SSCR; `world/refindex.json` (obiekty, do których skrypty odwołują się po nazwie – działa też na niewczytanych komórkach). Gra: `MWScripts` – skrypty globalne („main” + SSCR, StartScript/StopScript) i lokalne (obiekty we wczytanych komórkach, także wyłączone) co klatkę; zmienne lokalne, globalne i obiektów; funkcje: Enable/Disable/GetDisabled, OnActivate (przejmuje aktywację)/Activate, Journal/GetJournalIndex, MessageBox z przyciskami/GetButtonPressed, AddItem/RemoveItem/GetItemCount, PlaceAtPC/PlaceAtMe/PlaceItem, GetPos/SetPos/GetAngle/SetAngle/Position/PositionCell, GetDistance, GetPCCell, Lock/Unlock/GetLocked, SetDelete, PlaySound*, statystyki gracza i NPC (zdrowie NPC z autoobliczaniem jak OpenMW), GetSpell, Random, GetSecondsPassed, MenuMode, CellChanged; funkcje walki/AI zwracają stan spoczynku (0) i są raportowane jako częściowe; nieobsługiwane – raport (`scripts_report.json` w katalogu zapisów). Stan skryptów w zapisie (`scripts`, `journal`, `globals`). MCP: zrzut stanu włączenia obiektów ze skryptami w OpenMW (`RLF_ENABLED`). Odbiór: Raven Rock (komórki −25,19 i −24,19) po starcie nowej gry – **344 z 344 obiektów ze skryptami w tym samym stanie co w OpenMW** (w tym 159 wyłączonych, np. budynki kolonii z kolejnych etapów, `Colony_E_*`), przebieg `Raporty/mcp/zrzuty/2026-11-16-095922-porownanie/raven-rock-skrypty.json`; test syntetyczny (wyłączenie na starcie, OnActivate, dziennik, przedmioty, zapis/odczyt). Brak (wg planu dalej): AI (AiTravel, AiWander… – etap 8), walka i czary (etap 7), dialogi i teksty dziennika (Say, AddTopic, ForceGreeting – etap 6). |
| 2026-11-16 | 6 | **Ukończony (zakres podstawowy).** Konwerter: DIAL + INFO → `world/records/dialogue.json` (`mwconv/dialogue.py`; eksport świata v6) – kolejność odpowiedzi z PNAM jak `ESM::InfoOrder` (wstawianie za poprzednikiem, przenoszenie, usuwanie DELE po wczytaniu), dopisywanie odpowiedzi z późniejszych plików do istniejących dialogów, warunki SCVR (+INTV/FLTV) jako nazwy funkcji, skrypty wyniku (BNAM) kompilowane jak skrypty (MWScript: „:” jak biały znak – wersja kompilatora 3); Morrowind + Tribunal + Bloodmoon: 2884 dialogi, 31 822 odpowiedzi, 0 błędów kompilacji skryptów wyniku. Gra (`mw_dialogue.gd`): port `MWDialogue::Filter` (testActor/testPlayer/warunki/postawa, fallback „Info Refusal”), `DialogueManager` (powitania „Greeting 0–9”, tematy znane graczowi i dostępne u rozmówcy, poznawanie tematów z tekstu i z „@temat#”, pytania Choice, Goodbye, skrypt wyniku w kontekście rozmówcy), `KeywordSearch` (najdłuższe dopasowanie od początku słowa), podstawienia `%PCName`, `%Name`, `%Rank`, `%Faction`, `%PCRank`, `%Cell`… i zmienne globalne, postawa pochodna (`getDerivedDisposition`), perswazja (podziw, zastraszenie, drwina, łapówki – wzory `getPersuasionDispositionChange`, trwała zmiana przy pożegnaniu), dziennik (`Journal::addEntry`: wpisy z datą, zakończenie QSTF, wznowienie QSTR, nazwa zadania QSTN, nieznany indeks – tylko indeks), dziennik tematów, frakcje gracza (PCJoinFaction, PCRaiseRank, ModPCFacRep, GetPCRank, PCExpell…), ModDisposition/SetDisposition, reputacja, ustawienia AI, AddTopic, ForceGreeting, ClearInfoActor, ShowMap (znaczniki zapamiętane – mapa w etapie 10); tłumaczenia INFO (warianty płci) i nazw tematów (DIAL) z lokalizacji RLF. Okno rozmowy (E na NPC; hiperłącza, pytania, pasek postawy, Perswazja) i dziennik (J: wpisy, zadania, tematy). Zapis v3 (sekcja `dialogue`, `docs/FORMAT-ZAPISU.md`). Odbiór na danych z gry (komórka „Balmora, Caius Cosades' House”): skrypt wyniku kapitana w Seyda Neen („duties”) → paczka, Journal A1_1 = 1, tematy; rozmowa z Caiusem: powitanie (TalkedToPc = 0), temat „Report to Caius Cosades” → Choice Tak (1) → oddanie paczki → Choice Tak (3) → Journal A1_1 = 14, członkostwo w Blades (ranga Novice w tekście), „Orders” → 200 sztuk złota, Journal 18 (zadanie zakończone), ponownie „Orders” → Choice → **nowe zadanie „Antabolis Informant” (A1_2 = 1) z prawidłowym wpisem w dzienniku**, StartScript Sleepers; zapis/odczyt zachowuje wpisy, frakcje i indeksy; wczytanie dialogów 0,35 s, otwarcie rozmowy 36 ms, temat 12 ms. Test syntetyczny `test_dialogue.gd` (43 sprawdzenia). Znane ograniczenia: usługi NPC (handel, czary, podróże, trening) nie są pokazywane do etapu 7; głosy (Say, SNAM) – etap 10, napisy Say jako komunikat; warunki Detected/Alarmed/Attacked/ShouldAttack/CreatureTarget/FriendHit/PcClothingModifier, liczniki zabitych i choroby – stan spoczynku do etapów 7–8 (raport `partial`); postęp umiejętności Speechcraft przy perswazji – etap 7; wygląd okien w stylu Morrowinda – etap 10. |
| 2026-11-16 | 7 | **Ukończony (zakres podstawowy).** Konwerter: MGEF i ENCH (eksport świata v7). Gra – wzory OpenMW 0.51 (C++ i skrypty Lua `files/data-mw`): **rozwój i awans** (`mw_character.gd`: postęp za użycie z SKIL, wymaganie umiejętności, podniesienia z użycia/książek/treningu, postęp poziomu, premie atrybutów i specjalizacji, mnożniki iLevelUpNNMult, okno awansu po śnie; odpoczynek/czekanie T, odnowa zdrowia i magii; prędkości chodu/biegu/pływania/skoku, zmęczenie, obciążenie); **handel i usługi** (`mw_trade.gd`: usługi z AIDT/klasy, odmowa „Service Refusal”, ceny getBarterOffer, targowanie, złoto i odnawianie kupca, zakup zaklęć, trening, podróż, zaklinacz); **walka** (`mw_combat.gd`: szansa trafienia, obrażenia broni i wręcz, pancerz jak skrypty Lua OpenMW, zużycie broni i zbroi, blok gracza, powalenie, trudność, pociski z łuków/kusz/broni rzucanej, śmierć NPC/stworzeń i gracza, przeszukiwanie ciał; F – broń, lewy przycisk – atak); **magia** (`mw_magic.gd`: szansa i koszt zaklęć, moce raz na dobę, odporność i słabość, odbicie i pochłanianie, działające czary – efekty jednorazowe i ciągłe × dt jak applyMagicEffect, uszkodzenia/osłabienia atrybutów i umiejętności, wzmocnienia, leczenie trucizn/paraliżu/chorób, rozproszenie, znak/przywołanie, zbroje i bronie przyzwane, dezintegracja, otwieranie/zamykanie zamków, pociski czarów z obszarem; mikstury, składniki, alchemia z aparatami i rekordem dynamicznym; przedmioty zaklęte – użycie, ładunek i ładowanie, zwoje, stałe, przy uderzeniu; pułapka dusz i kamienie dusz; zaklinanie samodzielne i u zaklinacza; okno magii M, R – przygotuj magię), funkcje skryptów magii (GetEffect, Cast, ExplodeSpell, RemoveSpellEffects…). Zapis v4 (stan aktorów) i v5 (rekordy utworzone w grze). MCP-openMW 0.10.0: **porównanie wzorów z OpenMW na tych samych wejściach** (scenariusz Lua na graczu w silniku i `godot/tools/mech_compare.gd`) – przebieg `Raporty/mcp/mechanika/2026-11-16-etap7`: statystyki pochodne i wymagania 27 umiejętności, 24 użycia umiejętności, sekwencja 12 awansów umiejętności, 8 kompletów zbroi (ocena pancerza, wartości elementów, obrażenia po pancerzu), ładunki 40 przedmiotów zaklętych, 12 mikstur (w trakcie i po wygaśnięciu) – **156 z 156 porównań zgodnych (3152 liczby)**; jedyna różnica pierwszego przebiegu (kondycja po wygaśnięciu wzmocnienia wytrzymałości) poprawiona: zmiana maksimum zachowuje stosunek wartości bieżącej (`setAttribute`). Odbiór na danych z gry (`godot/tools/stage7_scenario.gd`, Ra'Virr i Gildia Magów w Balmorze): kupno i sprzedaż u 4 kupców, zakup 5 zaklęć, trening u 6 trenerów, podróże gildii, rzucenie każdego kupionego zaklęcia, trafienie bronią, śmierć i przeszukanie ciała, mikstura, awans na poziom 2, zapis/odczyt – wszystkie kroki zgodne z oczekiwaniami. Testy syntetyczne: `test_progress.gd`, `test_trade.gd`, `test_combat.gd`, `test_magic.gd` (62 sprawdzenia). Znane ograniczenia: reakcje NPC na atak, AI walki i rzucanie czarów przez NPC, przywołania, efekty AI (uspokojenie, szał…), boska interwencja, telekineza, choroby i wampiryzm, lewitacja, zsuwanie się NPC bez AI po zboczach – etap 8; animacje ataku/czarów, efekty wizualne i wygląd okien – etap 10; naprawa przedmiotów i tworzenie zaklęć – później. Szansa rzucenia, ceny i alchemia nie są dostępne w API Lua OpenMW – porównane z kodem źródłowym w testach syntetycznych (wartości liczone ręcznie). |
| 2026-11-16 | 8 | **Ukończony (zakres podstawowy).** Konwerter: siatki ścieżek PGRD w komórkach (punkty i krawędzie we współrzędnych świata; klucze komórek wnętrz jak w OpenMW), `world/markers.json` (znaczniki więzienia, Boskiej i Almsivi Interwencji – z wejściem z zewnątrz), stworzenia z punktów pojawiania się (LEVC) wraz z modelami; eksport świata v8/v9 („Aktualizuj” w launcherze). Gra: `mw_pathgrid.gd` (koszty i A* jak `PathgridGraph`, składowe spójności Tarjana, najbliższy osiągalny punkt), `mw_ai.gd` – stos pakietów `AiSequence` z rekordów (AI_W/AI_T/AI_E/AI_F/AI_A) i ze skryptów (AiWander, AiTravel, AiEscort, AiFollow, AiActivate, GetAIPackageDone, GetCurrentAIPackage), AiWander (punkty siatki w promieniu i spacer w pobliżu startu bez siatki – co reakcję 4% jak `wanderNearStart`, bezczynność `getRandomIdle`, czas trwania w godzinach gry), AiTravel/Escort/Follow/Activate, utknięcie i omijanie przeszkód (`ObstacleCheck`, rezygnacja z celu po 10 klatkach), powitania (Hello × iGreetDistanceMultiplier, iGreetDuration, fGreetDistanceReset), animacje chodu/biegu z prędkością ruchu (ruch korzenia usunięty); **wykrywanie** (`awarenessCheck`: skradanie – Ctrl, buty, odległość, przód/tył, niewidzialność, kameleon, ślepota); **AI walki** (`engageCombat`/getFightTerm, wybór akcji jak `aicombataction`: broń, czary dotyk/cel, łuk i strzały, ucieczka Flee; ataki stworzeń z rekordu, pociski NPC trafiają gracza); **przestępstwa** (`mw_crime.gd`: własność referencji i pojemników, kradzież ze zmapowanymi skradzionymi przedmiotami, wtargnięcie przy wytrychu/sondzie, napaść, morderstwo; świadkowie wg Alarm w fAlarmRadius, `reportCrime` – grzywny GMST, reakcje Fight, wydalenie z frakcji; strażnik: pościg AiPursue i rozmowa, próg iCrimeThreshold/×iCrimeThresholdMultiplier – atak; PayFine/PayFineThief/GoToJail – konfiskata, dni wg iDaysinPrisonMod, odsiadka, przeniesienie do znacznika); Security – wytrychy i sondy wg wzorów OpenMW, pułapki rzucają czar; warunki dialogów Alarmed/Attacked/Detected/ShouldAttack. Stan aktorów: pozycje NPC i stos pakietów zapisywane przy zmianie komórki, przejściu przez drzwi i w zapisie (`docs/FORMAT-ZAPISU.md`); koniec „dryfu” NPC (kolizje modeli usunięte z kapsuły), kapsuły stworzeń z modelu. MCP-openMW 0.11.0: **porównanie zachowań AI** (`openmw_ai_compare_start`, `lua/scripts/rlf_ai`, `godot/tools/ai_compare.gd`, `aicmp.py`). Odbiór na danych z gry (Seyda Neen, start nowej gry, 30 s): **14 z 14 dopasowanych aktorów z tym samym pakietem AI co w OpenMW (w tym AiTravel strażnika z przystani ze skryptu), 12 z 12 promieni wędrówki zgodnych, wszyscy aktorzy OpenMWGodot w promieniu wędrówki; ruch/bezruch zgodny u 12 z 14** (trasy i bezczynność są losowe po obu stronach); napaść gracza przy strażniku – w obu silnikach zauważona, grzywna 40, strażnik ściga (Pursue), ofiara walczy; stworzenia z punktów LEVC różnią się wynikiem losowania (raportowane osobno). Raport `Raporty/mcp/ai/2026-11-16-etap8`. Scenariusz `tools/stage8_scenario.gd` (Seyda Neen i Arrille's Tradehouse): siatki ścieżek, ruch bez upadków i wyjść poza promień, powitanie, kradzież (zgłaszają tylko świadkowie z Alarm 100 – Arrille, Tolvise Othralen; grzywna 1), napaść → strażnik zagaduje po ~3 s, walka, **powrót do komórki i odczyt zapisu bez zmian pozycji i pakietów** (15 i 7 aktorów). Testy syntetyczne: `test_ai.gd` (20), `test_combat_ai.gd` (13), `test_crime.gd` (25). Znane ograniczenia: NPC nie przechodzą między komórkami (pakiety podróży kończą się na granicy wczytanych komórek), kradzież kieszonkowa i walka NPC z NPC (poza strażnikami) – później, ruch po navmeshu Godota zamiast Recast (siatka ścieżek + omijanie), czary interwencji mogą już użyć `markers.json` (magia – lista „później”), pływanie/latanie stworzeń przy wędrówce uproszczone, animacje ataku/trafienia – etap 10. |
| 2026-11-16 | 9 | **Ukończony (uzgodniony fragment).** Fragment: nowa gra → statek więzienny → tworzenie postaci przez skrypty CharGen → Seyda Neen (urząd celny, kapitan Gravius, paczka) → łazik do Balmory → Caius Cosades (A1_1_FindSpymaster zakończone, Blades) → Gildia Wojowników: przyjęcie i zadanie FG_RatHunt u Drarayne Thelas (walka ze szczurami w domu i składziku, dziennik, nagroda). Silnik: nowa gra jak `World::startNewGame` (CharGenState 1, okna zablokowane, skrypty startowe 5× przed pierwszą klatką; tryb szybkiego kreatora: ustawienie `chargen_mode: quick`), blokady sterowania/walki/skoku/magii/rozglądania ze skryptów, menu imienia, rasy, klasy, znaku i przeglądu wywoływane skryptem (tryb menu wstrzymuje skrypty), Enable…Menu/EnableRest/DisableRest/ShowRestMenu, Say z napisami bez okna i SayDone, funkcje bez nawiasów (SayDone, GetAIPackageDone…), skrypty przedmiotów w ekwipunku gracza (OnPCAdd, OnPCEquip, zmienne przenoszone ze świata), GetRace, ChangeWeather/GetCurrentWeather, GetStandingPC, Rotate, PlayGroup/LoopGroup; gracz stawiany na podłożu po teleporcie (`World::adjustPosition` – koniec obrażeń od upadku po wyjściu z budynków); siła (min(1, 0,1 + los) u stworzeń) i odstęp ataków AI (animacja + fCombatDelay…) jak w OpenMW. Odbiór na danych z gry (`tools/stage9_playthrough.gd`, raport `Raporty/etap9-przejscie`): całe przejście – 33 cele, bez nieobsługiwanych funkcji i błędów skryptów; drugi przebieg z zapisem w połowie (dom Caiusa) → nowy proces → odczyt → dokończenie zadania; stan po odczycie końcowego zapisu: A1_1 = 18, FG_RatHunt = 105, Blades i Fighters Guild, CharGenState −1, okna i sterowanie odblokowane. Testy: `test_chargen.gd` (18 – menu, blokady, SayDone, OnPCAdd/OnPCEquip, pogoda, GetRace, zapis), `test_save_mods.gd` (zapis przy dodaniu wtyczki i przy jej braku – ostrzeżenia, stan i dziennik zachowane, brak cichego usuwania obiektów). Znane ograniczenia: głosy (pliki Vo) – etap 10 (napisy i czas kwestii z długości tekstu), menu klasy bez pytań i własnej klasy, mapa – etap 10, sterownik przechodzi między pomieszczeniami teleportem do celu (ruch i ścieżki gracza sprawdzone w etapach 3 i 8), NPC nie zmieniają komórek. |
