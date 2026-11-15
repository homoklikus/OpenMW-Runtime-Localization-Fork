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