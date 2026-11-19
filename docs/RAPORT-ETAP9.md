# Etap 9 – domknięcie klasycznego interfejsu OpenMW 0.51

Stan na 2026-11-19. Baza: lokalny HEAD po etapie 8 (`e90ab5b6fb`, części 1–9). Zasada: wierny port OpenMW 0.51
(okno i mechanika), bez uproszczeń i bez danych gry w kodzie; nowoczesny interfejs dopiero po ukończeniu portu.
Zrzuty z porównań leżą lokalnie (`OpenMW RLF/Raporty/ui-etap8/`, katalog roboczy `/tmp/uicmp` na VM) – nie
trafiają do repozytorium ani raportu; tu tylko liczby (ramki, krawędzie, pasma tekstu).

## 1. Weryfikacja etapu 8

| Punkt | Wynik |
|---|---|
| 9 commitów etapu 8 | obecne lokalnie, drzewa zgodne z kopią roboczą w chmurze (porównanie `HEAD^{tree}`) |
| Skalowanie 720 / 1080 / 1440 / 2160 | ramki i wewnętrzne krawędzie zgodne; dziennik ±1 px (zaokrąglenie float) |
| MW_Window / MW_Dialog / MW_Box | zgodne; margines 7 px MW_Dialog dotyczy tylko okien potwierdzenia, zapisu i ustawień (kreator i usługi mają obszar Client od 4, 4) – pozycja audytu |
| MysticCards, gamma oświetlenia wnętrz | bez regresji (porównania light_census / light_seyda z cz. 9) |
| Stabilność testów AI | pełny zestaw zielony w każdym przebiegu etapu (5 przebiegów, 50–52 testy) |

## 2. Okna odtworzone w etapie

Każde okno: układ z pliku `.layout` OpenMW, mechanika z kodu OpenMW, test regresyjny, porównanie zrzutem
z oficjalnym OpenMW 0.51 na Xvfb (`tools/openmw-xvfb/ui_cases/*_e9_1080.json`).

| Okno | Commit | Mechanika | Test | Porównanie z OpenMW (1080p) |
|---|---|---|---|---|
| Naprawa narzędziem i u NPC (Repair, MerchantRepair) | cz. 1 | Repair::repair, stan przedmiotu jak CellRef::charge (stos „id#c:N”), cena naprawy | test_repair (24) | ramki IoU 1,0; wiersze ±1–2 px, ikona narzędzia piksel w piksel |
| Alchemia (AlchemyWindow) | cz. 2 | getReadyStatus, countPotionsToBrew, createPotions(n), progi znajomości efektów, komunikaty | test_alchemy (19), test_magic | ramka IoU 1,0; aparaty i składniki dokładnie; filtry i przyciski ±1 px |
| Zaklinanie (EnchantingDialog) | cz. 3 | Enchanting: nextCastStyle, punkty, pojemność, szansa, cena, create (rekord zaklęcia i nowy przedmiot), NPC i samodzielnie, kradzione od zaklinacza | test_enchanting | ramka IoU 1,0; listy i przyciski ±1 px |
| Edycja efektu, wybór umiejętności/atrybutu (EffectEditorBase, EditEffectDialog) | cz. 3 | znane efekty, limit 8, powtórzenia, zasięgi, suwaki, Anuluj/Usuń | test_enchanting | (część okien zaklinania i tworzenia czarów) |
| Tworzenie czarów (SpellCreationDialog) + usługa w rozmowie | cz. 3 | koszt narastający, cena, szansa, zakup | test_enchanting | ramka IoU 1,0; ±1 px |
| Ładowanie przedmiotów (Recharge) + SoulgemDialog | cz. 3 | rechargeItem | test_enchanting | (układ jak naprawa) |
| Awans (LevelupDialog) | cz. 4 | getLevelupClassImage, mnożniki, monety, NpcStats::levelUp | test_progress | ramka IoU 1,0; obraz klasy i opis piksel w piksel, przycisk OK dokładnie |
| Perswazja (PersuasionDialog) | cz. 4 | getPersuasionDispositionChange (zgodne, bez zmian) | test_enchanting | ramki IoU 1,0; wiersze akcji ±1 px (okno otwierane kliknięciem tematu – nowy krok „click”) |
| Komunikaty (MessageBox, InteractiveMessageBox) | cz. 5 | MessageBoxManager: 3 komunikaty, czas = znaki × fMessageTimePerChar, układ przycisków | test_messagebox (13) | ramki trzech komunikatów dokładnie; tekst ±1–2 px w poziomie |

Stare okno `mw_magic_window.gd` (alchemia/zaklinanie w układzie Godota) zostało usunięte; stare okno awansu
w oknie odpoczynku i stara perswazja zastąpione.

### Błędy wykryte i naprawione (błąd → przyczyna → naprawa → test)

| Błąd | Przyczyna | Naprawa | Test regresyjny |
|---|---|---|---|
| Zdjęcie slotu ekwipunku przy zmianie stanu przedmiotu | `_check_equipment` po usunięciu starego stosu | id w slocie zmieniane przed dodaniem/usunięciem stosu (naprawa, walka) | test_repair |
| Zaklęty przedmiot: zawsze ten sam rekord, skrypt usuwany, ładunek ustawiany ręcznie | uproszczenie zamiast applyEnchantment | nowy rekord przy każdym zaklęciu (ESMStore::insert), skrypt zostaje, pojemność = ładunek kamienia, ładunek −1 = pełny | test_enchanting |
| Brak ograniczeń broni rzucanej/amunicji, mnożnika typu, liczby sztuk | brak getEnchantItemsCount/getTypeMultiplier | port z enchanting.cpp ([Game] projectiles enchant multiplier) | test_enchanting |
| Brak usługi tworzenia czarów | brak pozycji sSpellmakingMenuTitle | lista usług w kolejności DialogueWindow::updateTopicsPane | test_trade, test_enchanting |
| Użycie kamienia dusz od razu otwierało zaklinanie | brak SoulgemDialog i Recharge | ActionSoulgem → pytanie sDoYouWantTo, Recharge | test_enchanting |
| Komunikaty jako etykieta w rogu ekranu, okna z pytaniem w ogólnym kontenerze | brak MessageBoxManager | port messagebox.cpp | test_messagebox, test_settings |
| Komunikaty, których OpenMW nie ma („Upadek: −N zdrowia”, „Broń dobyta/schowana”, „Magia gotowa/schowana”, „Skopiowano do schowka”, „Poziom N”, „Wybierz N atrybuty”) | dodatki Godota | usunięte | – (przegląd kodu) |
| Ustawienia okien (pozycja, przypięcie, ukrycie, maksymalizacja) w zapisie gry | stan w `state.player` | globalny plik jak [Windows] w settings.cfg, migracja starych zapisów | test_window_settings (8) |
| Centrowanie okna awansu | OpenMW centruje, zanim policzy wysokość opisu | odtworzone (górna krawędź jak bez opisu) | porównanie ui_levelup |
| Zawijanie opisu awansu o wyraz wcześniej | Label Godota łamie z innym marginesem niż MyGUI::TextView | `mw_box_layout.wrap_lines` jak TextView | porównanie ui_levelup |
| Przycisk OK awansu z tekstem sDone | sDone tylko w trybie kontrolera | Interface:OK | porównanie ui_levelup |
| Lua w porównaniach: błąd przy polskich znakach w krokach | `json.dumps` z `\u` (LuaJIT tego nie zna) | literał UTF-8 | ui_messagebox |

## 3. Ustawienia okien globalnie (jak [Windows] w OpenMW)

Położenie i rozmiar okien trybu menu (ułamki ekranu), przypięcie, ukrycie i maksymalizacja są zapisywane
atomowo przy każdej zmianie do `window_settings.json` obok ustawień z gry (`ingame_settings.json`), niezależnie
od zapisu gry. `--window-settings=PLIK` wskazuje inny plik; przebiegi testowe (`-s`) bez tego parametru trzymają
ustawienia w pamięci (testy nie wpływają na siebie). Zgodność: zapis sprzed etapu 9 z kluczami `ui_*` w postaci –
przy wczytaniu, gdy pliku globalnego jeszcze nie ma, ustawienia są przejmowane; klucze są usuwane z postaci,
nowe zapisy ich nie zawierają. Test: `test_window_settings.gd`.

## 4. Narzędzia porównań

- `mw_box_layout.gd` – wierny Gui::HBox/VBox (AutoSized*, Spacer, Hidden, AutoResize, błąd OpenMW z dopełnieniem
  liczonym przy każdym dziecku), zawijanie wierszy jak MyGUI.
- Kroki porównań: tryby z celem-przedmiotem i celem-NPC (Enchanting, SpellCreation, Recharge, LevelUp),
  `click` (mysz przez XTest w OpenMW i zdarzenie w Godocie), `message` (ui.showMessage).

## 5. Audyt pozostałego GUI

Punkty: **U** – wymiary i układ z `.layout`, **S** – skórki, **F** – czcionki, **K** – kontrolki, **M** – mysz,
**Kl** – klawiatura, **R** – zmiana rozdzielczości, **G** – rozgrywka/mechanika, **Us** – trwałość ustawień,
**L** – l10n/GMST. ✓ – sprawdzone (test lub porównanie zrzutem), ~ – częściowo, ✗ – niezgodne/brak, – – nie dotyczy.
Okno uznane za ukończone tylko wtedy, gdy jego funkcja jest przetestowana.

| Okno | U | S | F | K | M | Kl | R | G | Us | L | Stan / uwagi |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Menu główne | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | – | ✓ | etap 8 (ui_mainmenu_e8) |
| Ustawienia | ~ | ~ | ✓ | ~ | ✓ | ~ | ~ | ✓ | ✓ | ~ | mniej zakładek i opcji niż `openmw_settings_window`; margines MW_Dialog 7 px |
| Zapis / wczytanie | ~ | ~ | ✓ | ✓ | ✓ | ~ | ~ | ✓ | – | ✓ | margines MW_Dialog 7 px do sprawdzenia porównaniem |
| Konsola | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | – | – | brak (P3) |
| Kreator postaci (5 okien + wybory) | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | – | ✓ | etap 7; SelectSkill/Attribute także w edytorze efektów (etap 9) |
| HUD | ✓ | ✓ | ✓ | – | ✓ | – | ✓ | ✓ | ✓ | ✓ | etap 7; brak paska zdrowia wroga |
| Statystyki, ekwipunek, magia, mapa | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ustawienia [Windows] globalnie (etap 9) |
| Dziennik | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | etap 7 |
| Rozmowa | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | – | ✓ | etap 8; usługa tworzenia czarów dodana (etap 9) |
| Handel, pojemnik | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | – | ✓ | etap 8; brak okna ilości (dzielenie stosu) |
| Perswazja | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | – | ✓ | – | ✓ | etap 9 |
| Usługi: zaklęcia, podróże, trening, naprawa u NPC | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | – | ✓ | etapy 8–9 |
| Naprawa, ładowanie, alchemia, zaklinanie, tworzenie czarów, edycja efektu | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ~ | ✓ | – | ✓ | etap 9; porównania tylko 1080p; sterowanie klawiaturą (strzałki, Tab) nie odtworzone |
| Odpoczynek / czekanie | ✗ | ~ | ✓ | ~ | ✓ | ✗ | ~ | ~ | – | ✓ | układ Godota; brak paska postępu (`openmw_wait_dialog_progressbar`), przyciemnienia 0,2 s, przerywania snu (lista snu regionu, fSleepRandMod/fSleepRestMod, sSleepInterrupt), sNotifyMessage2 (wrogowie w pobliżu), autozapisu – P2 |
| Awans | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | – | ✓ | – | ✓ | etap 9 |
| Książki i zwoje | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ | etap 7 |
| Komunikaty (MessageBox, okno z pytaniem) | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ~ | ✓ | – | ✓ | etap 9; klawisz domyślny (sOk/sYes, Enter) nie odtworzony |
| Potwierdzenia (`openmw_confirmation_dialog`) | ~ | ~ | ✓ | ✓ | ✓ | ~ | ~ | ✓ | – | ✓ | margines MW_Dialog 7 px |
| Podpowiedzi (`openmw_tooltips`) | ✗ | ✗ | ~ | – | ~ | – | ~ | ~ | – | ~ | zwykłe podpowiedzi Godota (tekst) zamiast układów ToolTip (ikony, kolory, MagicEffectToolTip) – P2 |
| Szybkie klawisze, wybór magii (`quickkeys_menu`, `magicselection_dialog`) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | brak (P1) |
| Okno ilości (`count_window`) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | – | ✗ | brak (P2) |
| Więzienie (`jail_screen`) | ✗ | ✗ | ✗ | – | – | – | ✗ | ~ | – | ✗ | nieprzetestowane (P2) |
| Towarzysz (`companion_window`) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | – | ✗ | brak (P2) |
| Notatka mapy (`edit_note`), wpisywanie tekstu (`text_input`) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | – | ✗ | brak (P3) |
| Ekran wczytywania | ~ | ~ | ✓ | – | – | – | ~ | ✓ | – | ✓ | szybkie wczytanie – komunikat jak LoadingScreen::loadingOff |
| Pad (menu kontrolera) | ✗ | ✗ | – | ✗ | – | – | – | – | ✗ | ✗ | brak (`[GUI] controller menus`) |

Wnioski: najważniejsze braki to szybkie klawisze (P1), okno ilości, okno czekania z paskiem postępu i przerywaniem
snu, podpowiedzi w układach OpenMW, więzienie i towarzysz (P2). Sterowanie klawiaturą w nowych oknach (strzałki,
domyślny przycisk) i porównania w 720p/1440p/2160p dla okien etapu 9 – do zrobienia.

## 6. Treści: Morrowind, Tribunal, Bloodmoon, mody

- Mechanika okien etapu korzysta wyłącznie z rekordów i GMST (MGEF, SPEL, ENCH, CREA, przedmioty) i ustawień;
  w kodzie zostały tylko stałe silnika OpenMW: `Misc_SoulGem_Azura` (Enchanting::create, rechargeItem),
  przedrostek `misc_soulgem` (isSoulGem), `gold_001` (ContainerStore::sGoldId), klasy broni z `weapontype.hpp`.
- Porównania zrzutami wykonano na Morrowind.esm (Arrille's Tradehouse); Tribunal, Bloodmoon i typowe mody
  (składniki, efekty, zaklęcia z modów) w tym etapie **nie były sprawdzane** – status „nieprzetestowane”.
- Konwerter: tylko dane syntetyczne (kupiec z usługami tworzenia czarów i zaklinania, GMST fSpellMakingValueMult);
  zmiany w konwersji prawdziwych danych nie były potrzebne. Oryginalne pliki gry nie były modyfikowane.

## 7. Przeszkody

- Okna z pytaniem (InteractiveMessageBox) nie da się otworzyć z Lua – porównanie zrzutem tylko dla komunikatów
  zwykłych; układ okna z pytaniem sprawdza test (wzory z messagebox.cpp).
- Godot nie ma stosu trybów GUI (pushGuiMode/popGuiMode): okna otwierane z ekwipunku (alchemia, naprawa,
  zaklinanie z kamienia) zamykają tryb menu i po zamknięciu wracają do gry, a nie do ekwipunku.

## 8. Testy

Pełny `tools/run_tests.sh` przed każdym commitem: „WSZYSTKIE TESTY ZALICZONE” (49–52 pozycji ✔, zależnie od części).
Nowe testy: test_repair (24), test_alchemy (19), test_enchanting (73), test_window_settings (8),
test_messagebox (13). Zmienione oczekiwania tylko tam, gdzie zmieniły się dane syntetyczne albo usunięto
stary kod (test_trade – lista usług z nowych danych; test_magic – okna OpenMW zamiast starego okna magii;
test_progress, test_settings, test_menu_mode, test_ui_geometry – nowe API okien), z uzasadnieniem w commitach.

## 9. Commity (lokalne, bez push)

| Commit | Zakres |
|---|---|
| `c46055df76` | cz. 1: stan przedmiotów jak CellRef::charge, naprawa narzędziem i u NPC |
| `fecc56fe30` | cz. 2: alchemia |
| `dbe879dab9` | cz. 3: zaklinanie, tworzenie czarów, ładowanie, usunięcie starego okna magii |
| `5d525476d8` | cz. 4: awans i perswazja, krok „click” w porównaniach |
| `4133e3c15a` | cz. 5: ustawienia okien poza zapisem, MessageBoxManager |
| (ten raport) | cz. 6: raport etapu 9, inwentaryzacja |

Każdy commit przygotowany w kopii roboczej w chmurze i zastosowany lokalnie przez `git am`; drzewa
(`HEAD^{tree}`) porównane po każdym zastosowaniu – zgodne.
