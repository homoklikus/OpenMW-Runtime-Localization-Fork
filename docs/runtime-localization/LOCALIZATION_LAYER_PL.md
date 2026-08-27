# Zewnętrzna warstwa lokalizacyjna

[English](LOCALIZATION_LAYER.md) | **Polski**

**OpenMW — Runtime Localization Fork** udostępnia mechanizmy silnika
pozwalające lokalizować zawartość w czasie działania. Nie definiuje ani nie
dostarcza obowiązkowego formatu bazy tłumaczeń.

Projekt lokalizacyjny może używać YAML, JSON, bazy danych, wygenerowanych tablic
Lua albo innego formatu, o ile skrypt zawartości ostatecznie zastosuje dane przez
API runtime.

Ten podział jest celowy:

```text
fork silnika              projekt lokalizacyjny
-----------               ----------------------
mechanizmy runtime  <---  loader
podział canonical/display dane tłumaczeniowe
integracja OpenMW         fonty/zasoby, jeśli potrzebne
                          narzędzia specyficzne dla projektu
```

## Zakres prawny i dystrybucyjny

To repozytorium zawiera wyłącznie kod źródłowy silnika i dokumentację.

Nie dodawaj wyeksportowanego tekstu gry, cudzych przetłumaczonych tekstów gry,
zasobów Bethesdy ani innych materiałów chronionych prawem autorskim, chyba że
masz prawo je redystrybuować.

Użytkownik może zbudować warstwę lokalizacyjną na podstawie plików gry, które
legalnie posiada, ale powstałe dane pozostają oddzielone od tego repozytorium
silnika.

## Kanoniczne identyfikatory są kluczem

Warstwa lokalizacji w czasie działania powinna zachowywać kanoniczne
identyfikatory TES3 jako stabilne klucze.

Zlokalizowany tekst jest wartością przeznaczoną do wyświetlenia.

Przykład:

```yaml
records:
  - type: WEAP
    id: example_weapon_id
    name: "Zlokalizowany przykład broni"
```

Syntetyczny `example_weapon_id` reprezentuje kanoniczny identyfikator rekordu.
Loader powinien zmienić widoczną nazwę, a nie techniczny identyfikator.

## YAML jest opcjonalny

Sam fork nie parsuje YAML.

Jeśli wybierzesz YAML, architektura wygląda tak:

```text
plik YAML
   |
   v
loader lokalizacji
   |
   v
openmw.content / content.translations
   |
   v
stan wyświetlany w czasie działania
```

Loader odpowiada za:

- odczyt danych YAML,
- walidację wymaganych pól,
- zastosowanie modułów we właściwej kolejności,
- raportowanie brakujących rekordów,
- wywoływanie odpowiedniego API runtime,
- odświeżenie wartości pochodnych po zastosowaniu zlokalizowanych danych GMST.

## Sugerowana struktura projektu

Projekt lokalizacyjny może używać struktury podobnej do:

```text
MyLocalization/
├── data/
│   ├── base.yaml
│   ├── expansion-a.yaml
│   ├── expansion-b.yaml
│   └── mods/
│       └── example-mod.yaml
├── scripts/
│   └── load.lua
└── metadane specyficzne dla projektu
```

To tylko zalecenie. Dokładny sposób pakowania zawartości OpenMW i pliki
manifestów powinny odpowiadać wersji OpenMW, dla której tworzysz lokalizację.

Rozdzielenie modułów ułatwia kontrolę kolejności ładowania i rozwiązywanie
konfliktów.

## Sugerowany model YAML

Poniższy schemat ma charakter przykładowy i nie jest wymaganiem silnika.

```yaml
version: 1

translations:
  cells:
    - source: "Source Cell"
      display: "Zlokalizowana komórka"

  topics:
    - id: "source topic id"
      display: "Zlokalizowany temat"
      keyword: "zlokalizowane słowo kluczowe"

  info:
    - topic_id: "source topic id"
      info_id: "source-info-id"
      display: "Zlokalizowana odpowiedź dialogowa"

  choices:
    - source: "Source choice"
      display: "Zlokalizowany wybór"

  script_strings:
    - source: "Source message"
      display: "Zlokalizowany komunikat"

records:
  factions:
    - id: "example_faction_id"
      name: "Zlokalizowana frakcja"

  weapons:
    - id: "example_weapon_id"
      name: "Zlokalizowana broń"
```

Wszystkie powyższe teksty są syntetycznymi przykładami.

Prawdziwy projekt może preferować mapy zamiast list, osobne pliki dla każdego
typu rekordu albo wygenerowaną reprezentację binarną / indeksowaną.

## Przykład loadera

Loader zamienia dane projektu na wywołania silnika.

Koncepcyjnie:

```lua
local content = require('openmw.content')
local tr = content.translations

tr.setCellName('Source Cell', 'Zlokalizowana komórka')
tr.setTopicName('source topic id', 'Zlokalizowany temat')
tr.setTopicKeyword('source topic id', 'zlokalizowane słowo kluczowe')

tr.setInfoResponse(
    'source topic id',
    'source-info-id',
    'Zlokalizowana odpowiedź dialogowa'
)

tr.setChoiceText('Source choice', 'Zlokalizowany wybór')
tr.setScriptString('Source message', 'Zlokalizowany komunikat')

local ok = tr.setWeaponName('example_weapon_id', 'Zlokalizowana broń')
if not ok then
    -- zgłoś brakujący lub niezgodny rekord
end
```

Pełne API specyficzne dla forka opisano w [API_PL.md](API_PL.md).

## Przepływ pozyskiwania danych

Projekt tłumaczeniowy może budować swoje dane w kilku etapach.

### 1. Zacznij od legalnie posiadanej zawartości

Używaj źródłowych plików ESM/ESP odpowiadających wersji gry lub moda, którą
lokalizujesz.

### 2. Wyeksportuj kanoniczne identyfikatory i pola widoczne dla użytkownika

Użyj odpowiedniego narzędzia do inspekcji / eksportu TES3, aby utworzyć roboczy
zbiór danych zawierający:

- typ rekordu,
- kanoniczny identyfikator rekordu,
- kanoniczne identyfikatory tematu dialogowego / INFO tam, gdzie są potrzebne,
- tekst źródłowy przeznaczony do wyświetlenia,
- kontekst potrzebny tłumaczom.

Nie zastępuj kanonicznych identyfikatorów ich przetłumaczonymi odpowiednikami.

### 3. Przetłumacz pola wyświetlane

Przechowuj przetłumaczoną wartość obok kanonicznego klucza.

Praktyczny zbiór danych dla tłumaczy zwykle zawiera zarówno tekst źródłowy, jak
i tekst zlokalizowany, nawet jeśli końcowy plik runtime zostanie później
zoptymalizowany.

### 4. Zweryfikuj dane względem docelowego zestawu zawartości

Przed zastosowaniem danych w czasie działania sprawdź, czy każdy rekord
wskazywany przez lokalizację istnieje w planowanym zestawie gry / modów.

### 5. Stosuj dane zgodnie z priorytetem zawartości

Praktyczna kolejność:

```text
gra podstawowa
dodatki
mody
poprawki specyficzne dla modów
```

Dokładna kolejność powinna odpowiadać rzeczywistym zależnościom zawartości
projektu lokalizacyjnego.

## Mapy tłumaczeń a settery rekordów

Używaj `content.translations`, gdy silnik musi zachować kanoniczną wartość
oddzielnie od wartości wyświetlanej.

Jest to szczególnie ważne dla:

- nazw tematów dialogowych,
- odpowiedzi INFO,
- etykiet Choice,
- wybranych tekstów MWScript przeznaczonych do wyświetlenia,
- nazw komórek obsługiwanych przez magazyn tłumaczeń.

Dla rekordów, których nazwę / opis można bezpiecznie reprezentować przez kopię
rekordu w czasie działania, użyj odpowiedniego settera opisanego w
[API_PL.md](API_PL.md).

Dla typów zawartości obsługiwanych już przez odpowiednie mutowalne API
`openmw.content`, loader może używać bezpośrednio upstreamowego API mutowalnego.

## Formy tematów i słowa kluczowe

Zlokalizowany temat dialogowy może wymagać więcej niż jednej wartości:

```text
kanoniczny identyfikator tematu
zlokalizowana nazwa wyświetlana
zlokalizowana forma frazy
zlokalizowane słowo kluczowe hiperłącza/wyszukiwania
```

Fork celowo oddziela kanoniczny identyfikator tematu od wszystkich tych form
wyświetlania i wyszukiwania.

Użyj:

```lua
tr.setTopicName(topicId, displayName)
tr.setTopicForm(phrase, topicId)
tr.setTopicKeyword(topicId, keyword)
```

Późniejsze wywołanie `setTopicForm()` dla tej samej frazy zastępuje wcześniejsze
mapowanie runtime.

## Rekordy INFO

Używaj zarówno kanonicznego identyfikatora tematu, jak i kanonicznego
identyfikatora INFO:

```lua
tr.setInfoResponse(topicId, infoId, displayResponse)
```

Nie kluczuj odpowiedzi INFO wyłącznie tekstem źródłowym. API runtime obsługuje
już kontekst rekordu INFO.

## Ograniczenie Choice i tekstów skryptowych

`setChoiceText()` i `setScriptString()` są obecnie kluczowane wyłącznie tekstem
źródłowym.

Oznacza to, że:

```text
ten sam tekst źródłowy + różne wymagane tłumaczenia w różnych modułach
```

nie może obecnie zostać zapisane kontekstowo. Wygrywa późniejsze przypisanie
runtime.

Projekt lokalizacyjny powinien wykrywać takie kolizje podczas generowania lub
walidacji danych i je raportować.

## GMST i lokalizacja wartości pochodnych

Niektóre widoczne nazwy są wyprowadzane z ustawień gry podczas uruchamiania.

Jeżeli warstwa lokalizacyjna zmienia odpowiednie teksty GMST, najpierw zastosuj
te zmiany, a potem wywołaj:

```lua
local refreshed = tr.refreshDerivedLocalization()
```

Powoduje to ponowne zbudowanie obecnie obsługiwanych pochodnych wartości
wyświetlanych.

Dokładny zakres i wartość zwracaną opisano w [API_PL.md](API_PL.md).

## Raportowanie brakujących rekordów

Nie ignoruj po cichu nieudanych setterów rekordów.

Przydatny loader powinien śledzić co najmniej:

```text
zastosowane wpisy
brakujące wpisy
liczby według typu rekordu
konflikty/kolizje
```

Przykład:

```lua
local applied = 0
local missing = 0

local function apply(result)
    if result == false then
        missing = missing + 1
    else
        applied = applied + 1
    end
end

apply(tr.setWeaponName('example_weapon_id', 'Zlokalizowana broń'))
```

Dla setterów map tłumaczeń, które nie zwracają statusu, w miarę możliwości
waliduj kanoniczne klucze we własnym procesie generowania lub ładowania danych.

## Zapisy gry

Nowe wpisy dziennika są tworzone z użyciem aktualnie aktywnego tłumaczenia INFO
do wyświetlenia.

Tekst dziennika zapisany już w istniejącym save nie jest wstecznie przepisywany
po zmianie danych lokalizacyjnych.

Projekt lokalizacyjny powinien testować zarówno nowe gry, jak i istniejące
zapisy.

## Fonty, tekstury, audio i wideo

API lokalizacji w czasie działania obejmuje wyłącznie tekst widoczny przez
silnik oraz wybrane pola wyświetlane rekordów.

Specyficzne dla języka fonty lub zasoby zastępcze są osobną zawartością OpenMW
i powinny być pakowane przez projekt lokalizacyjny, a nie przez to repozytorium
silnika.

## Testowanie bez materiałów chronionych prawem autorskim

Twórcy silnika mogą testować publiczny fork za pomocą syntetycznej warstwy
lokalizacyjnej zawierającej wymyślone identyfikatory / teksty oraz mały plugin
testowy utworzony w tym celu.

Jest to preferowane rozwiązanie dla publicznych testów regresji, ponieważ
chronione dane lokalizacyjne gry nie trafiają do repozytorium.

## Powiązana dokumentacja

- [Architektura](ARCHITECTURE_PL.md)
- [API Lua lokalizacji w czasie działania](API_PL.md)
- [Budowanie w systemie Linux](BUILD_LINUX_PL.md)
- [Budowanie w systemie Windows](BUILD_WINDOWS_PL.md)
