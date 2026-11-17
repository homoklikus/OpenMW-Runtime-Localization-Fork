# Inwentaryzacja braków OpenMWGodot względem OpenMW

Stan na 2026-11-17 (commit 1738e0a). Cel: wierne odtworzenie OpenMW, zanim zajmiemy się remasterem.
Oznaczenia: ✔ jest, ◐ częściowo / inaczej niż w OpenMW, ✘ brak, ? do sprawdzenia porównaniem z OpenMW.
Priorytet: **P1** – psuje wierność od pierwszych minut gry, **P2** – zauważalne w zwykłej grze, **P3** – rzadkie.

Sposób sprawdzenia: przegląd kodu, sondy na prawdziwych danych (VM użytkownika – tylko identyfikatory i liczby),
porównanie z kodem OpenMW (fork, `apps/openmw`). Raport nie zawiera tekstów gry.

## 1. Start gry i menu

| Element | Stan | Uwagi | Prio |
|---|---|---|---|
| Filmy: logo Bethesdy, logo Morrowinda, wstęp po „Nowej grze” | ✘ | pliki `Video/*.bik` gracza; ffmpeg dekoduje Bink → konwersja lokalna do Ogg Theora (Godot odtwarza) – sprawdzone na VM | P1 |
| Menu główne (Nowa gra, Wczytaj, Opcje, Zasługi, Wyjdź), tło `mw_menu.bik`, muzyka tytułowa | ✘ | gra startuje od razu w świecie z launchera | P1 |
| Ekran ładowania (losowy obraz z `Splash/`, pasek postępu) | ✘ | | P2 |
| Okno zapisu/wczytywania (lista zapisów, nazwa, postać, miejsce, zrzut) | ✘ | jest tylko szybki zapis/wczytanie (F5/F9) | P1 |
| Menu pauzy (Esc) | ◐ | prosty, bez zapisu/wczytania z listą | P2 |
| Ekran śmierci | ◐ | prosty; OpenMW: wczytanie ostatniego zapisu albo menu | P2 |
| `PlayBink`, `FadeIn`/`FadeOut`/`FadeTo`, `WakeUpPC` w skryptach | ✘ | 10 / 7 / 8 skryptów | P1 |

## 2. Nowa gra (statek więzienny → urząd celny)

| Element | Stan | Uwagi | Prio |
|---|---|---|---|
| Skrypty CharGen (stan, kwestie, menu kreatora w kolejności) | ◐ | działają: Jiub mówi, okno imienia otwiera się po kwestii | P1 |
| Strażnik schodzi pod pokład po gracza | ✘ | **przyczyna znaleziona:** AI uznaje cel za osiągnięty po odległości w poziomie (OpenMW: w 3D) i idzie „na skróty” prosto do celu bez sprawdzenia linii widzenia (OpenMW: tylko przy widocznym celu); strażnik zostaje na górnym pokładzie nad graczem, `GetAIPackageDone` = 1 | P1 |
| Dalsza sekwencja (eskorta na pokład, kapitan, urząd, Sellus Gravius, skrzynia, wyjście do Seyda Neen) | ? | sonda przejdzie całość po naprawie strażnika | P1 |
| Okna kreatora jak w OpenMW: imię (pole tekstowe), rasa (podgląd 3D głowy, płeć, twarz, włosy, premie, cechy), klasa (wybór / pytania / własna, obraz klasy), znak (obraz, zaklęcia), przegląd z „Wstecz” | ◐ | u nas jeden wspólny formularz z wierszami | P1 |

## 3. Interfejs

| Element | Stan | Uwagi | Prio |
|---|---|---|---|
| Tryb menu (statystyki, ekwipunek, magia, mapa), HUD, pojemnik, handel, alchemia, rozmowa | ✔ | etap 10i–10k | – |
| Pasek zdrowia wroga w HUD | ✘ | | P2 |
| Szybkie klawisze (F1, 1–9) | ✘ | | P1 |
| Okno ilości (dzielenie stosów, Shift przy przeciąganiu) | ✘ | dziś zawsze cały stos / 1 sztuka | P2 |
| Dziennik jak książka (zadania, indeks tematów, strony) | ✘ | dziś lista | P2 |
| Okno awansu (obraz klasy, mnożniki atrybutów) | ◐ | | P2 |
| Odpoczynek/czekanie (układ OpenMW, „do wyleczenia”) | ◐ | | P2 |
| Tworzenie zaklęć (usługa) | ✘ | | P2 |
| Naprawa u kupca / młotkiem, ładowanie kamieniem duszy | ◐ | logika częściowo, okna OpenMW brak | P2 |
| Zaklinanie, kupno zaklęć, trening, podróż w układzie OpenMW | ◐ | wygląd Morrowinda, układ list | P3 |
| Więzienie (okno odsiadki, utrata umiejętności) | ? | | P2 |
| Towarzysz (dzielenie ekwipunku), przechodzenie przez drzwi | ✘ | | P2 |
| Konsola (~) | ✘ | przydatna też do testów | P3 |
| Ustawienia jak OpenMW (zakładki, klawisze) | ◐ | mniej opcji | P3 |
| Kursor z gry (`tx_cursor`) | ✘ | | P3 |
| Podpowiedź nad obiektem w świecie: waga, wartość, właściciel na czerwono | ◐ | dziś tekst akcji | P2 |
| Okno komunikatu (MessageBox) w stylu i położeniu OpenMW | ◐ | | P3 |

## 4. Skrypty (Morrowind, Tribunal, Bloodmoon)

253 różne funkcje w skryptach danych. Wywołanie każdej na sucho (cel: gracz):
**127 działa, 13 zwraca stałe 0, 96 nieobsłużonych**, 17 funkcji interfejsu nie badano (patrz punkt 1).

- Stałe 0 (zachowanie niezgodne): `OnPCHitMe` (31 skryptów), `GetTarget` (15), `IsWerewolf` (14), `GetPCSleep` (11),
  `GetDetected` (10), `OnKnockout`, `OnMurder`, `GetAttacked` (po 5), `GetWerewolfKills`, `GetPCInJail`,
  `GetPCTraveling`, `GetPCSneaking`, `GetLOS`.
- Nieobsłużone, najczęstsze: `SetHealth` (33), `BecomeWerewolf` (18), `ModHealth` (16), `Resurrect` (10),
  `GetWaterLevel` (9), `ModCurrentHealth` (9), `Set*`/`Mod*` atrybutów, umiejętności i odporności (kilkadziesiąt
  wariantów), `SetScale`, `Move`/`MoveWorld`, `ForceSneak`/`ClearForceSneak`, `ModRegion`, `Drop`,
  `HurtStandingActor`/`HurtCollidingActor`, `Enable/DisableLevitation`, `Enable/DisableTeleporting`,
  `SetWaterLevel`/`ModWaterLevel`, `TurnMoonRed`/`TurnMoonWhite`, `Face`, `Fall`, `PlaceItemCell`, `RaiseRank`,
  `GetSquareRoot`, `GetStandingActor`, `GetCollidingPC`, `HasItemEquipped`, `RemoveSoulGem`, `OnPCSoulGemUse`.
- Uwaga: część funkcji może działać dla NPC, a nie dla gracza – szczegółowa lista powstanie przy wdrażaniu.

## 5. Magia

Efekty bez działania (oznaczone w kodzie jako „później”) albo bez odbiorcy: oddychanie pod wodą, chodzenie po
wodzie, lewitacja, powolne spadanie, tarcza, niewidzialność, kameleon, światło, widzenie w ciemności, ślepota,
wykrywanie (zwierzęta, zaklęcia, klucze), telekineza, Boska interwencja, interwencja Almsivi, **wszystkie
przywołania**, przedmioty przywołane (bound), uspokojenie/szał/demoralizacja/zebranie odwagi/odpędzanie
nieumarłych, kontrola istot i humanoidów, choroby, wampiryzm (częściowo), obrażenia od słońca.
? do sprawdzenia: odporności i słabości (część działa w obrażeniach), tarcze żywiołów.

## 6. Świat i obraz

| Element | Stan | Uwagi | Prio |
|---|---|---|---|
| Widok pierwszoosobowy z rękami i bronią, animacje ataku i rzucania | ✘ | dziś sama kamera | P1 |
| Widok trzecioosobowy (Tab) | ✘ | | P2 |
| Efekty wizualne czarów (rzucanie, pociski, trafienia, poświata zaklętych przedmiotów) | ✘ | | P1 |
| Opady (deszcz, śnieg, popiół, zaraza), błyskawice | ◐ | dźwięki są, cząsteczek brak | P2 |
| Księżyce Masser i Secunda (fazy) | ✘ | | P2 |
| Kręgi i plusk na wodzie, ślady | ✘ | | P3 |
| Wierność oświetlenia (Godot liczy światło liniowo + tonowanie, OpenMW w przestrzeni gamma) | ◐ | porównać zrzutami dzień/noc/wnętrza | P1 |
| Daleki teren i obiekty na horyzoncie | ✘ | | P3 |
| Odbicia wody (poziomy 0–5) | ◐ | tylko niebo | P3 |

## 7. AI i mechanika

| Element | Stan | Uwagi | Prio |
|---|---|---|---|
| Szukanie drogi | ◐ | siatki ścieżek (pathgrid), test celu w poziomie, skrót bez linii widzenia (punkt 2) | P1 |
| Aresztowanie przez strażnika, płacenie grzywny, więzienie | ? | do sondy | P2 |
| Wilkołactwo (Bloodmoon) | ✘ | | P3 |
| Choroby, wampiryzm | ◐ | | P3 |

## Proponowana kolejność

1. **Nowa gra jak w OpenMW:** naprawa szukania drogi (3D, linia widzenia), sonda przez całą sekwencję statek →
   urząd → Seyda Neen, brakujące funkcje skryptów na tej drodze.
2. **Start gry:** filmy (konwersja lokalna ffmpeg → Theora), menu główne z tłem i muzyką, ekrany ładowania,
   okno zapisu/wczytywania, `FadeIn`/`FadeOut`/`PlayBink`.
3. **Okna kreatora postaci** jak w OpenMW.
4. **Funkcje skryptów** (Set/Mod statystyk, SetHealth, Resurrect, …) i stałe zera.
5. **Efekty magii** z punktu 5.
6. **Interfejs:** szybkie klawisze, okno ilości, dziennik-książka, awans, więzienie, podpowiedzi w świecie,
   pasek wroga, tworzenie zaklęć, naprawa, kursor.
7. **Obraz:** widok pierwszoosobowy z rękami, efekty czarów, opady, księżyce, wierność oświetlenia, widok 3-os.
8. **Bloodmoon/Tribunal:** wilkołactwo i pozostałe.

Każdy krok kończy się porównaniem z OpenMW (zrzuty/sondy MCP) i aktualizacją tej listy.
