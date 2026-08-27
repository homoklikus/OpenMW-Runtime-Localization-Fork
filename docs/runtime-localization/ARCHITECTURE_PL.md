# Architektura lokalizacji w czasie działania

[English](ARCHITECTURE.md) | **Polski**

Ten dokument opisuje architekturę lokalizacji w czasie działania dodaną przez
**OpenMW 0.51.0 — Runtime Localization Fork**.

Fork bazuje na OpenMW 0.51.0. Dodaje po stronie silnika mechanizmy pozwalające
zewnętrznej warstwie zawartości dostarczać zlokalizowane teksty wyświetlane
w czasie działania, bez konieczności tworzenia przetłumaczonej kopii
oryginalnych danych TES3 ESM/ESP.

To repozytorium nie zawiera danych lokalizacyjnych gry.

## Cele

Warstwa lokalizacji w czasie działania została zaprojektowana wokół czterech
głównych celów:

1. Zachowanie kanonicznych rekordów TES3 i identyfikatorów technicznych.
2. Podmienianie tekstu widocznego dla użytkownika w momencie wyświetlania lub
   poprzez kontrolowane aktualizacje rekordów w czasie działania.
3. Umożliwienie przechowywania danych lokalizacyjnych poza repozytorium silnika.
4. Zachowanie standardowego działania OpenMW, dialogów, skryptów i zapisów gry
   w możliwie największym stopniu.

Dzięki temu można używać oryginalnego pliku głównego w języku źródłowym,
wyświetlając graczowi zawartość w innym języku.

## Czego fork nie robi

Fork nie:

- zawiera przetłumaczonych tekstów Morrowinda, Tribunal, Bloodmoon ani modów,
- generuje przetłumaczonego pliku `.esm` lub `.esp`,
- zastępuje systemu l10n OpenMW używanego przez natywne mody Lua OpenMW,
- zmienia kanonicznych identyfikatorów rekordów TES3,
- dostarcza uniwersalnego generatora plików tłumaczeń.

Warstwa lokalizacyjna odpowiada za pozyskanie, przechowywanie i zastosowanie
własnych danych tłumaczeniowych.

## Ogólny przepływ danych

Typowa warstwa lokalizacyjna działa następująco:

```text
źródłowe rekordy ESM/ESP
        |
        v
zewnętrzne dane lokalizacyjne
        |
        v
skrypt LOAD/content OpenMW
        |
        +--> API content.translations
        |
        +--> istniejące mutowalne API rekordów openmw.content, gdy ma to sens
        |
        v
stan wyświetlany w czasie działania
        |
        v
GUI / dialogi / dziennik / napisy / komunikaty skryptowe
```

Oryginalne pliki zawartości pozostają autorytatywnym źródłem identyfikatorów
używanych przez logikę gry oraz relacji między rekordami.

## Dane kanoniczne a dane wyświetlane

Główna zasada projektowa brzmi:

> Logika gry powinna nadal używać kanonicznych wartości źródłowych wszędzie tam,
> gdzie dana wartość pełni rolę identyfikatora, klucza wyszukiwania albo
> technicznej wartości widocznej dla skryptu.

Zlokalizowany tekst jest wprowadzany tylko tam, gdzie wartość ma służyć
prezentacji użytkownikowi.

Przykłady:

- Temat DIAL zachowuje swój kanoniczny identyfikator, natomiast lista tematów
  może wyświetlać zlokalizowaną nazwę.
- Rekord INFO zachowuje oryginalną odpowiedź w magazynie ESM, a okno dialogowe
  otrzymuje zlokalizowaną wersję do wyświetlenia.
- Polecenie `Choice` zachowuje numeryczną wartość wyboru, a lokalizowana jest
  wyłącznie widoczna etykieta.
- `Say` zachowuje kanoniczną ścieżkę dźwięku, natomiast tekst napisów może zostać
  zlokalizowany.
- Identyfikatory tematów dziennika i INFO pozostają kanoniczne, podczas gdy nowo
  tworzone wpisy dziennika mogą używać zlokalizowanych odpowiedzi INFO.

To rozdzielenie jest ważne dla zgodności z oryginalną zawartością i modami,
które oczekują kanonicznych identyfikatorów.

## Translation::Storage

`Translation::Storage` pozostaje centralnym magazynem tłumaczeń przeznaczonych
do wyświetlania.

Fork rozszerza go o mapowania wypełniane w czasie działania dla:

- nazw komórek,
- nazw tematów,
- form fraz tematów,
- słów kluczowych hiperłączy tematów,
- odpowiedzi INFO,
- etykiet Choice,
- wybranych tekstów MWScript widocznych dla użytkownika.

Istniejący mechanizm tłumaczeń oparty na plikach pozostaje dostępny.
Wypełnianie danych w czasie działania jest dodatkiem i jest udostępnione
skryptom zawartości przez `openmw.content.translations`.

### Mapowania kontekstowe i oparte wyłącznie na tekście źródłowym

Odpowiedzi INFO są kluczowane kanonicznym identyfikatorem tematu oraz
identyfikatorem INFO, dzięki czemu zachowują kontekst rekordu.

Etykiety Choice oraz wybrane teksty MWScript są obecnie kluczowane wyłącznie
tekstem źródłowym. Jeżeli dwie niezależnie ładowane warstwy lokalizacyjne
przypiszą różne tłumaczenia temu samemu tekstowi źródłowemu, wygrywa ostatnie
przypisanie wykonane w czasie działania.

Jest to znane ograniczenie obecnego API. W przyszłości może zostać rozszerzone
o klucze kontekstowe, jeśli konflikty lokalizacji modów będą tego wymagały.

## Dialogi

Lokalizacja dialogów celowo rozdziela sposób prezentacji od wykrywania tematów
oraz mechaniki dialogowej.

### Nazwy tematów

Temat może posiadać:

- kanoniczny identyfikator tematu,
- zlokalizowaną nazwę wyświetlaną,
- zlokalizowaną formę frazy używaną do rozpoznawania,
- zlokalizowane słowo kluczowe hiperłącza.

Interfejs dialogowy pokazuje zlokalizowaną etykietę, ale wysyła i przetwarza
kanoniczną wartość tematu.

Widżet listy został wzmocniony tak, aby jego wewnętrzna tożsamość MyGUI była
oparta na stabilnym indeksie listy, a nie na widocznym podpisie. Zapobiega to
kolizjom, gdy dwa różne kanoniczne tematy otrzymają identyczny zlokalizowany
tekst wyświetlany.

### Odpowiedzi INFO

Same rekordy INFO nie są przepisywane.

Kiedy OpenMW wyświetla odpowiedź INFO, fork pyta `Translation::Storage`
o tłumaczenie do wyświetlenia, używając:

```text
kanoniczny identyfikator tematu + kanoniczny identyfikator INFO
```

Kanoniczny tekst odpowiedzi źródłowej pozostaje dostępny dla wewnętrznego
wykrywania tematów i standardowych powiadomień dialogowych Lua.

### Choice

Tłumaczona jest wyłącznie widoczna etykieta `Choice`.

Numeryczna wartość wyboru używana przez skrypty TES3 pozostaje bez zmian.

## Teksty widoczne z MWScript

Fork dodaje do kontekstu interpretera MWScript mechanizm tłumaczenia tekstu
przeznaczonego do wyświetlenia.

Obecna integracja obejmuje wybrane literały widoczne dla użytkownika używane
przez:

- `Say`
- `MessageBox`

W przypadku `Say` ścieżka dźwięku pozostaje kanoniczna, a tłumaczony jest tylko
tekst napisów / tekst wyświetlany.

W przypadku `MessageBox` szablon jest tłumaczony przed formatowaniem.
Widoczne tekstowe argumenty literalne oraz literalne etykiety przycisków również
mogą być tłumaczone. Numeryczne argumenty formatujące nie są tekstami
lokalizacyjnymi.

Mechanizm po stronie silnika jest celowo ograniczony, zamiast traktować każdy
tekst w cudzysłowie w MWScript jako tekst do tłumaczenia.

## Dziennik i nazwy zadań

Wpisy dziennika tworzone z rekordów INFO pobierają zlokalizowaną odpowiedź INFO
przed rozwinięciem przez OpenMW znaczników dialogowych.

Nazwy zadań wyświetlane na podstawie rekordów INFO dziennika korzystają z tej
samej ścieżki lokalizacji tekstu.

Zapis gry przechowuje już utworzony tekst wpisu dziennika. Z tego powodu zmiana
warstwy lokalizacyjnej nie przepisuje wstecznie tekstów dziennika, które zostały
już zapisane w istniejącym save.

## Pola wyświetlane rekordów w czasie działania

Niektóre rekordy TES3 przechowują nazwę lub opis widoczny dla użytkownika
bezpośrednio w rekordzie. Dla takich rekordów fork udostępnia kontrolowane
settery, które kopiują istniejący rekord statyczny, podmieniają wyłącznie pole
przeznaczone do lokalizacji i ponownie wstawiają kopię używaną w czasie
działania.

Przykłady obejmują:

- frakcje i rangi frakcji,
- klasy,
- rasy,
- NPC i stworzenia,
- broń, pancerze i ubrania,
- pojemniki i narzędzia,
- znaki urodzeniowe,
- regiony,
- opisy umiejętności,
- opisy efektów magicznych.

Identyfikator rekordu nie jest zmieniany.

Dla typów zawartości, które posiadają już odpowiednie mutowalne API
`openmw.content`, zewnętrzna warstwa lokalizacyjna może użyć istniejącego API
zamiast dodawać zdublowane mechanizmy specyficzne dla lokalizacji.

## Lokalizacja wartości pochodnych

Niektóre widoczne wartości są wyprowadzane z rekordów GMST podczas uruchamiania
OpenMW, zamiast być odczytywane bezpośrednio za każdym razem, gdy są
wyświetlane.

Po zmianie odpowiednich tekstów GMST warstwa lokalizacyjna powinna wywołać:

```lua
content.translations.refreshDerivedLocalization()
```

Obecna implementacja odświeża:

- nazwy umiejętności i szkół magii,
- nazwy i opisy atrybutów,
- nazwy efektów magicznych wyprowadzane z wartości GMST `sEffect*`.

Funkcja zwraca liczbę nazw efektów magicznych odświeżonych w czasie działania.
Nie jest to ta sama liczba co liczba jawnie dostarczonych tłumaczeń opisów
efektów magicznych.

## Kolejność ładowania

Mapowania ustawiane w czasie działania używają semantyki nadpisywania tam,
gdzie późniejsze przypisanie powinno zastąpić wcześniejsze.

Pozwala to warstwie lokalizacyjnej stosować dane zgodnie z kolejnością
zawartości / ładowania, ale oznacza też, że warstwa lokalizacyjna odpowiada za
zastosowanie modułów we właściwej kolejności priorytetów.

Praktyczna architektura pełnej lokalizacji gry może przechowywać osobne moduły
danych dla gry podstawowej, dodatków i poszczególnych modów, a następnie
stosować je w tej samej efektywnej kolejności co odpowiadająca im zawartość.

## Zachowanie w przypadku błędów

Większość setterów pól rekordów zwraca `false`, gdy wskazany kanoniczny rekord
nie istnieje albo indeks jest nieprawidłowy.

Loader lokalizacji powinien zliczać lub raportować nieudane przypisania zamiast
je po cichu ignorować. Pozwala to wykrywać niezgodności wersji i brakujące
zależności już podczas uruchamiania.

Settery czystych map tłumaczeń nie zwracają obecnie informacji o powodzeniu,
ponieważ bezpośrednio wypełniają mapy używane w czasie działania.

## Zasady zgodności

Implementacja przestrzega następujących zasad zgodności:

- kanoniczne identyfikatory ESM/ESP pozostają bez zmian,
- oryginalne pliki zawartości nie wymagają modyfikacji,
- lokalizacja tekstu wyświetlanego jest w miarę możliwości oddzielona od
  wartości używanych do wyszukiwania przez logikę gry,
- widoczność napisów nadal podlega standardowemu ustawieniu napisów OpenMW,
- standardowy system tłumaczeń OpenMW oparty na plikach pozostaje dostępny,
- fork nie zawiera własnościowych danych lokalizacyjnych.

## Istotne obszary kodu źródłowego

Główna implementacja znajduje się w:

```text
components/translation/
components/widgets/list.*
apps/openmw/mwlua/contentbindings.cpp
apps/openmw/mwdialogue/
apps/openmw/mwgui/dialogue.cpp
apps/openmw/mwscript/
components/interpreter/
```

Publiczne API Lua opisano w [API_PL.md](API_PL.md).

## Możliwe przyszłe rozszerzenia

Potencjalne przyszłe rozszerzenia obejmują:

- kontekstowe mapowania Choice i tekstów skryptowych,
- bardziej rozbudowaną obsługę konfliktów świadomą modułów,
- opcjonalne warianty gramatyczne wybierane przez zewnętrzną warstwę
  lokalizacyjną Lua,
- dodatkowe, wąsko wyspecjalizowane mechanizmy wyświetlania, jeśli rzeczywista
  zawartość ujawni nieobsługiwane teksty widoczne dla użytkownika.

Takie rozszerzenia powinny nadal zachowywać opisany wyżej podział między danymi
kanonicznymi a danymi przeznaczonymi do wyświetlenia.
