# OpenMWGodot — plan wdrożenia całej gry (etapami)

Stan na 2026-11-15. Dokument nadrzędny: kolejność prac, kontrakty i kryteria odbioru. Zmiany planu wpisujemy
tutaj (z datą), a nie w rozmowie.

## 1. Zasady, które chronią poprzednie etapy

1. **Najpierw fundamenty, potem treść.** Rzeczy, które najczęściej „wywracają” projekt, ustalamy na samym
   początku (etap 0), zanim powstanie pierwsza mechanika: stan gry, zapis, model postaci (aktora), zdarzenia,
   wejście, szkielet UI. Późniejsze etapy tylko je *wypełniają*.
2. **Kontrakty z wersją.** Każda granica między częściami ma opisany format z numerem wersji:
   dane konwertera (`world/…`, `mwgodot-world vN`), API runtime (`MWWorldDB`, `GameState`, usługi),
   format zapisu. Zmiana niezgodna = nowa wersja + migracja + test; nigdy „po cichu”.
3. **Konwerter tylko dokłada.** Nowy etap dodaje nowe pliki/pola do `world/`; istniejących nie zmienia.
   Gra ignoruje pola, których jeszcze nie zna.
4. **Dane bazowe są tylko do odczytu.** Wszystko, co zmienia się w trakcie gry (pozycje, włącz/wyłącz,
   ekwipunek, zmienne, dziennik), żyje w `GameState` jako różnica względem danych bazowych. Dzięki temu
   zapis gry, skrypty i CS 2.0 nie wchodzą sobie w drogę.
5. **Etap jest zamknięty dopiero po odbiorze:** testy automatyczne (dane syntetyczne, w repo) + porównanie
   z OpenMW na prawdziwych danych (lokalnie, przez MCP) + wpis w CHANGELOG i w tym planie.
6. **Regresja jest pilnowana stale.** Zestaw ujęć porównawczych i testów rośnie z każdym etapem i jest
   uruchamiany po każdej zmianie. Etap nie może pogorszyć wyniku wcześniejszego.
7. **Licencje bez zmian:** żadnych zasobów Bethesdy w repozytorium ani artefaktach; zrzuty i wyniki
   porównań z prawdziwych danych zostają lokalnie (`OpenMW RLF/Raporty/…`). W repo tylko liczby i kod.
8. **Tory równoległe** (launcher, CS 2.0, narzędzia MCP) nie mogą blokować toru głównego (runtime) i
   odwrotnie — łączy je wyłącznie `mwcore` i format danych.

## 2. Gdzie jesteśmy

| Obszar | Stan |
|---|---|
| Konwerter: NIF→glTF (geometria, materiały, skin, kontrolery, cząsteczki, `.kf`), tekstury, BSA/VFS, ESM (obiekty z modelem, CELL, LAND, LTEX, REGN, PGRD), wypiekanie `.scn` | działa na pełnej grze |
| Świat w grze: teren, obiekty statyczne, światła, wnętrza, drzwi, woda, pora dnia i pogoda (uproszczone), roślinność Remirosa (7 regionów zgodne z OpenMW co do rośliny) | działa |
| Lokalizacja runtime (port forka) | działa (nazwy); dialogi/książki czekają na UI |
| Launcher (konwersja, mody, profile, ustawienia), CS 2.0 (komórki, teren, rekordy) | działa |
| Postacie, animacje postaci, skrypty, dialogi, ekwipunek, walka, magia, AI, dźwięk, zapis gry, UI gry | **brak** |
| Znane rozjazdy z OpenMW: oświetlenie/mgła/niebo jaśniejsze i bardziej niebieskie; obiekty wyłączane skryptem widoczne (Raven Rock); NPC w pozie T | do etapów 1, 3, 5 |

## 3. Etapy toru głównego

Każdy etap: **cel → zakres → kontrakt, który zamraża → odbiór (testy + MCP)**.

### Etap 0 — Fundamenty runtime i stanowisko porównań  *(następny)*

Cel: szkielet, na którym wszystkie dalsze etapy tylko dokładają funkcje.

* `GameState` (autoload): różnice względem danych bazowych — referencje (pozycja, włączona/wyłączona,
  usunięta, licznik, właściciel), zmienne globalne i lokalne skryptów, czas gry, gracz; zdarzenia zmian.
* Format zapisu gry v1 = serializacja `GameState` (JSON + kompresja), wersja + migracje; zapis/odczyt
  działa od razu, choć zapisuje mało (pozycja, czas, włączone/wyłączone). Każdy następny etap dopisuje swoje
  pole — format się nie zmienia, rośnie.
* Model aktora: jeden węzeł `MWActor` dla gracza, NPC i stworzeń (dane rekordu + stan + „wygląd”);
  gracz przestaje być osobnym bytem. Na razie tylko pozycja/ruch.
* Szyna zdarzeń (aktywacja, wejście do komórki, zmiana czasu…) i warstwa wejścia (akcje, nie klawisze).
* Szkielet UI gry: motyw, okna, kursor/tryb menu, pierwsze okno (HUD + menu pauzy z zapisem/odczytem).
* Obsługa referencji wyłączonych w danych (flaga w ESM) — fundament pod skrypty.
* **Stanowisko porównań**: lista ujęć referencyjnych (8 ujęć roślinności + miasta: Seyda Neen, Balmora,
  Vivec; wnętrza; noc; deszcz), uruchamiana jednym poleceniem, z metrykami (różnica obrazu, histogram
  kolorów, udział roślinności) zapisywanymi lokalnie; wynik liczbowy w raporcie testów.
* Kontrakt: API `GameState`, format zapisu v1, `MWActor`, zdarzenia, akcje wejścia.
* Odbiór: wszystkie obecne funkcje działają na nowym szkielecie bez zmian w obrazie (te same ujęcia, te same
  liczby); zapis → wyjście → odczyt przywraca pozycję i czas.

### Etap 1 — Świat statyczny 1:1 z OpenMW

Cel: zanim pojawią się postacie, świat ma wyglądać jak w OpenMW, żeby późniejsze porównania mierzyły
tylko nowe rzeczy.

* Oświetlenie, niebo, słońce, mgła i pogoda wg wartości zastępczych Morrowind.ini (kolory pory dnia per
  pogoda, przejścia), światło otoczenia wnętrz, opcjonalne cienie (domyślnie jak OpenMW).
* Teren: kalibracja mieszania tekstur (narzędzie MCP `openmw_land_texture_mapping_check`), woda (kolor,
  przezroczystość, odbicia uproszczone), roślinność: jasność względem terenu.
* Odległość widzenia, wczytywanie bez przycięć; daleki ląd (uproszczony) jako opcja.
* Kontrakt: parametry środowiska z danych (`world/environment.json` z fallbacków).
* Odbiór: wszystkie ujęcia referencyjne w progu podobieństwa do OpenMW (próg ustalony w etapie 0).

### Etap 2 — Komplet rekordów w danych (bez użycia w grze)

Cel: konwerter eksportuje wszystkie rekordy potrzebne do końca projektu, zanim powstanie kod, który ich
używa — dzięki temu dalsze etapy nie zmieniają formatu danych.

* NPC_, CREA, RACE, CLAS, FACT, BSGN, SKIL, MGEF, SPEL, ENCH, ALCH/INGR, przedmioty (pełne pola), LEVI/LEVC,
  GMST, GLOB, DIAL/INFO (filtry), SCPT (tekst + skompilowane dane), SOUN/SNDG, BODY, PGRD (jest).
* Scalanie wg kolejności ładowania i nadpisań jak w OpenMW; lokalizacja nakładana na nowe pola.
* Kontrakt: `mwgodot-world v2` (opis pól w `docs/FORMAT-SWIATA.md`).
* Odbiór: testy syntetyczne + porównanie z odczytem OpenMW przez MCP (nowe narzędzie: zrzut rekordu
  i porównanie pól dla losowej próbki 1000 rekordów każdego typu).

### Etap 3 — Postacie i animacje

* Składanie NPC z części ciała (rasa, płeć, głowa, włosy, ubiór, zbroja) i stworzeń; szkielet
  `base_anim` + `.kf`; animacje bezczynności, chodu, biegu; wybór ekwipunku do pokazania.
* Kontrakt: „wygląd” w `MWActor` (lista części + szkielet + zestaw animacji).
* Odbiór: ujęcia Seyda Neen i Balmory z NPC zgodne z OpenMW (sylwetka, ubiór, poza); brak pozy T.

### Etap 4 — Gracz i interakcja ze światem

* Kontroler postaci zgodny z OpenMW (prędkości, skok, kolizje, pływanie, upadek), aktywacja, podnoszenie,
  pojemniki, zamki i pułapki (podstawowo), ekwipunek gracza w `GameState`.
* Okna: ekwipunek, pojemnik, podpowiedzi przedmiotów (z lokalizacją).
* Odbiór: scenariusze testowe (podnieś → zapisz → wczytaj → przedmiot w ekwipunku i zniknął ze świata).

### Etap 5 — Skrypty MWScript

* Kompilator w konwerterze (tekst SCPT → drzewo/kod pośredni w `world/scripts/`) + maszyna w runtime;
  zmienne globalne/lokalne w `GameState`, skrypty startowe, funkcje dodawane grupami (świat → przedmioty →
  aktorzy → dialogi → reszta), raport nieobsłużonych funkcji.
* Odbiór: Enable/Disable (Raven Rock niewidoczny na starcie), skrypty startowe Seyda Neen, liczba
  nieobsłużonych wywołań w pełnej grze spada etapami do zera; porównanie przebiegu skryptu z OpenMW
  (nowe narzędzie MCP: ślad skryptu).

### Etap 6 — Dialogi, dziennik, zadania

* Filtry INFO, tematy, powitania, perswazja (podstawowo), wyniki dialogów (skrypty z etapu 5), dziennik,
  zadania; teksty z lokalizacji (gotowe dane z etapu 1 portu).
* Odbiór: początek gry (Seyda Neen → Balmora, zadanie Caiusa) przechodzi od początku do końca.

### Etap 7 — Mechanika RPG

* Atrybuty, umiejętności, poziomy, efekty magiczne, czary, zaklinanie, alchemia, walka (wręcz, dystans,
  magia), obrażenia, śmierć, handel, usługi (nauka, podróże, tworzenie czarów).
* Odbiór: wzory porównane z OpenMW (tabele wyników dla tych samych wejść).

### Etap 8 — AI i nawigacja

* Nawigacja (PGRD + navmesh Godota), pakiety AI (wander, travel, escort, follow, activate), walka AI,
  przestępstwa i straże.
* Odbiór: scenariusze (straż reaguje na kradzież; NPC wraca na miejsce).

### Etap 9 — Dźwięk i muzyka

* Dźwięki obiektów i kroków, otoczenie regionów, muzyka (eksploracja/walka), głosy.

### Etap 10 — Pełne UI i menu

* Mapa lokalna i świata, okno postaci, magia, książki i zwoje, alchemia, menu główne, ustawienia w grze,
  tworzenie postaci.

### Etap 11 — Wydanie

* Wydajność (LOD, strumieniowanie w tle), paczki Linux/Windows, dokumentacja gracza.

## 4. Tory równoległe

| Tor | Zakres | Zależność |
|---|---|---|
| Launcher | port forka etap 3: funkcje modów bez Nexusa | `mwcore`; niezależny od runtime |
| Construction Set 2.0 | edycja nowych rekordów wraz z etapem 2; skrypty po etapie 5 | format danych |
| Narzędzia MCP | rozwijane wtedy, gdy etap ich potrzebuje (niżej) | — |

## 5. Narzędzia MCP (rozwijane wg potrzeb)

| Etap | Narzędzie | Po co |
|---|---|---|
| 0 | profil `openmwgodot` w `openmw_capture_*` | jedno wywołanie robi zrzut OpenMW **i** naszej gry z tą samą kamerą oraz liczy metryki (dziś robione ręcznie przez `override.cfg`) |
| 0 | `openmw_parity_suite` | lista ujęć referencyjnych + wynik regresji |
| 2 | `openmw_record_dump` / `_compare` | pola rekordu wg OpenMW vs `world/` |
| 3 | `openmw_actor_inspect` | części ciała, szkielet, animacje NPC wg OpenMW |
| 5 | `openmw_script_trace` | przebieg skryptu w OpenMW (Lua) do porównania z naszą maszyną |
| 7 | `openmw_formula_probe` | wyniki wzorów (obrażenia, ceny, szanse) dla zadanych wejść |

Zmiany w MCP-openMW idą do jego repozytorium (`Fork/repo/tools/MCP-openMW`, gałąź `0.5-world`) — za zgodą,
bo to repozytorium forka.

## 6. Najbliższe kroki

1. Zatwierdzenie tego planu (ewentualne zmiany kolejności).
2. Push oczekującego commitu (tryb zrzutu) — po zatwierdzeniu.
3. Etap 0: najpierw stanowisko porównań (profil `openmwgodot` w MCP), potem `GameState` i zapis v1, potem
   przeniesienie gracza na `MWActor`.
