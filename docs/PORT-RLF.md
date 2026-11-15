# Przeniesienie zmian forka OpenMW RLF do OpenMWGodot

Źródło: `OpenMW RLF/Fork/repo`, gałąź `0.5-world` (zamrożona, tag `0.5-world-final` = `3bfa4c3`).
Punkt odniesienia: oryginalne OpenMW `openmw-0.51.0` (`f4bec41`) – fork to dokładnie 0.51.0 + **84 commity**
(154 pliki, ~92 tys. dodanych linii, z czego ~61 tys. to wygenerowana tabela danych roślinności).
Licencja: oba projekty GPL-3.0-or-later, więc kod forka można przenosić z podaniem pochodzenia.

Zasada: **bez integracji Nexus Mods** (API, przeglądanie, pobieranie, NXM, klucz API, aktualizacje z Nexus).

## Mapa zmian forka

| Grupa | Commity forka (skrót) | Decyzja | Etap |
|---|---|---|---|
| **Lokalizacja runtime** (YAML obok wtyczek, `components/translation`, `engine.cpp`, `mwgui`, `mwdialogue`, `mwlua/contentbindings`) | 8acb1f6, fa19a75, 97aa87b, f87d3c7, 557f851, 8553883 | przenosimy | **1 – zrobione** (dane + nazwy w grze); dialogi, dziennik, książki, podpowiedzi przedmiotów – gdy Runtime dostanie te okna |
| **Roślinność**: groundcover z wtyczek `groundcover=`, flora proceduralna z `world.cfg` (filtr LAND i nachylenia, wykluczenie przy obiektach, wagi tekstur, profile regionów), reguły Remirosa z liczbami na teksel (pach75/pach76) | 3b735aa…5629d38, 94e5fb4, 5ead2e9 | przenosimy: tabela reguł forka wbudowana, trawa bez ESP (tylko modele Remirosa) | **2 – zrobione** |
| **Launcher – mody**: sortowanie wg zależności, zasoby modów i konflikty (szczegóły), propozycje dla konfliktów rozdzielczości DDS, analiza archiwum, podgląd podpakietów BAIN, instalacja z archiwum, bezpieczna podmiana, usuwanie, synchronizacja priorytetów wtyczek i zasobów, przeglądanie plików moda, wersje modów, nakładki tłumaczeń | 5d92de4…726e6e9 (bez Nexus) | przenosimy funkcje, których launcher OpenMWGodot jeszcze nie ma | 3 |
| **Launcher – strona Świat** (flora, fauna) i ustawienia Groundcover | 07465d2, 7bd5677, eb37969 | przenosimy razem z etapem 2 | 2/3 |
| Nexus Mods: API, przeglądanie, pobieranie, metadane, NXM (rejestracja/obsługa/przywracanie), archiwalne pliki, tłumaczenia z Nexus, aktualizacje, zaszyfrowany klucz API | 2cbbb7e, 4165a51, a760064, 291c658, 2159306, 32608b3, 07f3525, f90e953, 3208a56, aea7e52, 66ec112*, 401db09, 0751919, 5cecd31 | **pomijamy** (wymaganie). *66ec112: z części „nakładki tłumaczeń” bierzemy mechanizm nakładek, bez źródła Nexus | – |
| MCP-openMW (`tools/MCP-openMW`) – narzędzia porównań dla OpenMW | 0b9ed5b, 478677c, 4a36722, 90be4b3, be3df96 | nie przenosimy jako narzędzie (Godot ma własne MCP); **kod eksportu reguł Remirosa** (`openmw_remiros_export`) wykorzystamy w etapie 2 | 2 |
| Dokumentacja, raporty, CI Windows, branding launchera, okładka, motywy przycisków | pozostałe | nie dotyczy | – |

## Etap 1 – lokalizacja runtime (zrobione)

Format i zachowanie jak w forku (`docs/runtime-localization-pl.md` w forku):

* plik-towarzysz dla każdej aktywnej wtyczki: `localization/language/<wtyczka bez rozszerzenia>.yaml`
  (w katalogu danych, w modzie albo w archiwum BSA); pliki bez aktywnej wtyczki są ignorowane, katalog nie jest skanowany;
* klucze `TYP|ID|POLE` (INFO: `INFO|temat|id|NAME`), ID bez rozróżniania wielkości liter;
* języki jako klucze (`EN`, `PL`, `PL_PL`); wybór wg listy preferencji, dokładny przed bazowym;
* późniejszy plik nadpisuje wcześniejszy **dla każdego języka osobno** (brak języka w późniejszym → zostaje wcześniejszy);
* INFO: warianty `default` / `npc` / `player` / `npc_player`;
* znaczniki `[c=#RRGGBB]`, `[b]`, `[i]` – tylko do wyświetlania (dane gry dostają czysty tekst), błędne → tekst bez formatowania;
* sekcja `fallbacks` (wartości Morrowind.ini);
* QA: tekst z wybranego modułu dostaje znacznik `QA:` (ustawienie „QA: wyróżnij tłumaczenia z modułu”).

Różnica architektury: OpenMW podmienia rekordy w pamięci przy starcie. W OpenMWGodot konwerter zapisuje
`world/localization/<JĘZYK>/{names,texts,fallbacks}.json` (z odciskiem zmian – zmiana tłumaczenia nie wymusza
eksportu świata), a gra wybiera język w trakcie działania (`scripts/mw/mw_localization.gd`). Zmiana języka
w launcherze (Ustawienia → Język → „Język gry”) nie wymaga ponownej konwersji.

Gdzie tłumaczenia są już widoczne: nazwa regionu i wnętrza w pasku, nazwa drzwi w podpowiedzi „[E]”.
Gotowe w danych i w API (`info_text`, `bbcode`, `fallback_value`), czekające na okna Runtime: dialogi (INFO
z wariantami płci), książki i zwoje (BOOK TEXT), dziennik, podpowiedzi przedmiotów, GMST, teksty skryptów.

Test na prawdziwych danych (u gracza, lokalnie): polskie tłumaczenie Morrowind + Tribunal + Bloodmoon + UMOPP –
52 326 wpisów, 0 ostrzeżeń, 2,5 s konwersji; w Godocie nazwy 21 ms, dialogi (na żądanie) 157 ms.

## Etap 2 – roślinność (zrobione, poprawione 2026-11-15 wieczorem)

Intencja forka: **trawa Remirosa generowana w grze bez jego ESP** – z moda potrzebne są wyłącznie modele i tekstury
(`meshes/grass/`, `textures/`), a rozmieszczenie wynika z reguł tekstur LAND i liczników na pola 128 j. (pach75 +
pach76) wkompilowanych w program. Pierwsza wersja portu źle to odczytała (wymagała `Rem_*.esp` i dodawała florę
z waniliowych traw, której fork w praktyce nie używał) – poprawione.

* **Tabela forka** `remirosgroundcoverdata.cpp` (39 reguł tekstur, 102 statyki, liczniki dla 715 komórek, 626 204
  grupy; wygenerowana przez MCP-openMW) → `converter/mwconv/data/remiros_rules.json.gz` (1,1 MB). Generator
  `RemirosGen::collectCell` przeniesiony 1:1 (bity wpisów i grup, ziarna, liczniki przy zgodnym odcisku terenu,
  reguły tekstur w pozostałych tekselach, rozrzut ±0,3 teksela, z + przesunięcie statyki, obrót wg normalnej).
* Ustawienia jak `world.cfg` forka: `[flora] enabled / source (automatic | groundcover | hybrid) / density (0–2)`
  oraz „legacy” `[Groundcover] enabled` z gęstością wtyczek (mapowanie z `RenderingManager` forka).
* **Wtyczki groundcover** (`groundcover=` albo mody rozpoznane automatycznie) – rozmieszczenie autora moda.
* **Modele i tekstury Remirosa są dołączone do programu** (`converter/mwconv/data/remiros_groundcover/`,
  26 NIF + 25 DDS, 27 MB; licencja moda pozwala – zob. LICENCJE.md). Konwerter dodaje ten katalog jako dane
  o najniższym priorytecie, więc zainstalowany mod Remirosa albo retekstury trawy go nadpisują. Roślinność jest
  domyślnie włączona w launcherze (Ustawienia → Świat).
* Gra: MultiMesh na model i komórkę, bez kolizji i cieni, test alfa 128/255, normalne „w górę” jak shader groundcover
  OpenMW, zasięg i gęstość rysowania w ustawieniach (Grafika).

Test na prawdziwym terenie (lokalnie u gracza, katalog modeli Remirosa bez ESP w VFS): odciski terenu zgodne
z tabelą forka w 714/715 komórkach; 49 komórek wokół Balmory – 50 180 roślin w 8,7 s; liczby vs rozmieszczenie
autora: (-3,-2) 130/127, (-2,-2) 769/755, (-3,-3) 680/682, (-4,-2) 522/534, (-5,-4) 2145/2160.

Nieprzeniesione: flora z waniliowych traw i jej wykluczenia (kod forka sprzed pach75, nieużywany), fauna (w forku
tylko flaga), wiatr/deptanie trawy (shader OpenMW) – osobny temat.

Poprawka przy okazji: woda – falowanie i wzór we współrzędnych świata (wcześniej lokalne współrzędne płaszczyzny
dawały szczeliny i szwy na łączeniach komórek).

## Etap 3 – launcher (mody, bez Nexus)

Porównanie z obecnym launcherem OpenMWGodot i przeniesienie brakujących funkcji: sortowanie wg zależności,
szczegóły konfliktów zasobów i propozycje dla DDS, analiza archiwum i BAIN, bezpieczna podmiana, wersje modów,
nakładki tłumaczeń (mod z samymi plikami `localization/` nakładany na mod bazowy).
