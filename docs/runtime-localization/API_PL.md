# API Lua lokalizacji w czasie działania

[English](API.md) | **Polski**

Ten dokument opisuje API Lua przeznaczone dla lokalizacji, udostępniane przez
**OpenMW 0.51.0 — Runtime Localization Fork**.

API jest dostępne przez:

```lua
local content = require('openmw.content')
local translations = content.translations
```

Fork nie zawiera danych lokalizacyjnych. Oczekuje się, że zewnętrzny skrypt
zawartości wypełni te API w czasie działania.

## Konwencje wartości zwracanych

Funkcje można podzielić na dwie grupy:

- settery map tłumaczeń wypełniają `Translation::Storage` i obecnie nie zwracają
  statusu,
- settery pól rekordów zwracają `true` w przypadku powodzenia oraz `false`, gdy
  nie można znaleźć wskazanego rekordu lub indeksu.

`refreshDerivedLocalization()` zwraca liczbę całkowitą.

## API map tłumaczeń

### `setCellName(sourceName, displayName)`

Dodaje lub podmienia nazwę wyświetlaną komórki.

```lua
translations.setCellName('Kanoniczna nazwa komórki', 'Zlokalizowana nazwa komórki')
```

Źródłowa nazwa komórki pozostaje kanoniczną wartością używaną do wyszukiwania.

### `setTopicName(topicId, displayName)`

Ustawia widoczną etykietę kanonicznego identyfikatora tematu DIAL.

```lua
translations.setTopicName('kanoniczny temat', 'Zlokalizowany temat')
```

Techniczny identyfikator tematu nie jest zmieniany.

### `setTopicForm(phrase, topicId)`

Mapuje zlokalizowaną formę frazy na kanoniczny identyfikator tematu.

```lua
translations.setTopicForm('zlokalizowana fraza', 'kanoniczny temat')
```

Wywołania w czasie działania używają semantyki nadpisywania, dzięki czemu
późniejsza warstwa lokalizacyjna może zastąpić wcześniejsze mapowanie.

### `setTopicKeyword(topicId, keyword)`

Ustawia zlokalizowane słowo kluczowe hiperłącza / wyszukiwania powiązane
z kanonicznym identyfikatorem tematu.

```lua
translations.setTopicKeyword('kanoniczny temat', 'zlokalizowane słowo kluczowe')
```

### `setInfoResponse(topicId, infoId, response)`

Ustawia odpowiedź wyświetlaną dla jednego rekordu INFO.

```lua
translations.setInfoResponse(
    'kanoniczny temat',
    'kanoniczny-identyfikator-info',
    'Zlokalizowana odpowiedź dialogowa'
)
```

Mapowanie jest kontekstowe: klucz zawiera zarówno kanoniczny identyfikator
tematu, jak i kanoniczny identyfikator INFO.

Źródłowy rekord INFO pozostaje nietknięty.

### `setChoiceText(sourceText, displayText)`

Ustawia tłumaczenie widocznej etykiety TES3 `Choice`.

```lua
translations.setChoiceText('Wybór źródłowy', 'Wybór zlokalizowany')
```

Zmienia się wyłącznie etykieta. Numeryczna wartość Choice używana przez skrypty
pozostaje kanoniczna.

**Obecne ograniczenie:** mapa jest kluczowana wyłącznie przez `sourceText`.
Jeżeli kilka modułów lokalizacyjnych przypisze różne tłumaczenia temu samemu
tekstowi źródłowemu, wygrywa ostatnie przypisanie.

### `setScriptString(sourceText, displayText)`

Ustawia tłumaczenie wybranego tekstu MWScript widocznego dla użytkownika.

```lua
translations.setScriptString(
    'Komunikat źródłowy',
    'Komunikat zlokalizowany'
)
```

Obecna integracja silnika używa tego mechanizmu dla wybranych widocznych
literałów w `Say` oraz `MessageBox`.

**Obecne ograniczenie:** mapa jest kluczowana wyłącznie przez `sourceText`.
Późniejsze przypisanie dla tego samego tekstu źródłowego zastępuje wcześniejsze.

## API pól wyświetlanych rekordów

Poniższe settery kopiują bieżący rekord statyczny, aktualizują tylko wskazane
pole wyświetlane i ponownie wstawiają rekord używany w czasie działania.

Zwracają `true`, gdy rekord został odnaleziony i zaktualizowany.

### Frakcje

```text
translations.setFactionName(id, name) -> boolean
translations.setFactionRankName(id, rankIndex, name) -> boolean
```

`rankIndex` jest liczony od zera i musi mieścić się w zakresie `0..9`.

### Klasy

```text
translations.setClassName(id, name) -> boolean
translations.setClassDescription(id, description) -> boolean
```

### Rasy

```text
translations.setRaceName(id, name) -> boolean
translations.setRaceDescription(id, description) -> boolean
```

### Aktorzy

```text
translations.setNpcName(id, name) -> boolean
translations.setCreatureName(id, name) -> boolean
```

### Wyposażenie i obiekty ekwipunku

```text
translations.setWeaponName(id, name) -> boolean
translations.setArmorName(id, name) -> boolean
translations.setClothingName(id, name) -> boolean
translations.setContainerName(id, name) -> boolean
translations.setApparatusName(id, name) -> boolean
translations.setRepairName(id, name) -> boolean
translations.setLockpickName(id, name) -> boolean
```

### Umiejętności

```text
translations.setSkillDescription(skillIndex, description) -> boolean
```

`skillIndex` jest liczony od zera i musi być prawidłowym indeksem `ESM::Skill`.

Funkcja rozwiązuje kanoniczny rekord umiejętności na podstawie indeksu; nie
zależy od pozycji w tablicy widocznej z Lua.

Nazwy umiejętności są wyprowadzane z GMST i odświeżane osobno przez
`refreshDerivedLocalization()` po zastosowaniu zlokalizowanych wartości GMST.

### Znaki urodzeniowe

```text
translations.setBirthSignName(id, name) -> boolean
translations.setBirthSignDescription(id, description) -> boolean
```

### Regiony

```text
translations.setRegionName(id, name) -> boolean
```

### Efekty magiczne

```text
translations.setMagicEffectDescription(effectIndex, description) -> boolean
```

`effectIndex` jest kanonicznym indeksem efektu magicznego TES3. Funkcja rozwiązuje
rekord używany w czasie działania przez `ESM::MagicEffect::indexToRefId()`
zamiast zakładać, że magazyn widoczny z Lua jest gęstą tablicą.

Nazwy efektów magicznych są wyprowadzane z GMST i obsługiwane przez
`refreshDerivedLocalization()`.

## Odświeżanie lokalizacji wartości pochodnych

### `refreshDerivedLocalization()`

```lua
local refreshedEffects = translations.refreshDerivedLocalization()
```

Wywołaj tę funkcję po zastosowaniu zlokalizowanych tekstów GMST wpływających na
wartości wyświetlane pochodne.

Obecna implementacja:

1. ponownie buduje lokalizację umiejętności na podstawie bieżących ustawień gry,
2. ponownie buduje lokalizację atrybutów na podstawie bieżących ustawień gry,
3. aktualizuje nazwy efektów magicznych na podstawie odpowiadających im tekstów
   GMST `sEffect*`.

Wartość zwracana:

```text
liczba odświeżonych nazw efektów magicznych
```

Nie jest to liczba jawnie dostarczonych tłumaczeń opisów efektów magicznych.

## Zalecany wzorzec loadera

Loader lokalizacji powinien przechowywać w danych kanoniczne identyfikatory,
a zlokalizowane teksty traktować jako wartości do wyświetlenia.

```lua
local content = require('openmw.content')
local tr = content.translations

local applied = 0
local missing = 0

local function apply(ok)
    if ok == false then
        missing = missing + 1
    else
        applied = applied + 1
    end
end

tr.setTopicName('kanoniczny temat', 'Zlokalizowany temat')
applied = applied + 1

apply(tr.setWeaponName('canonical_weapon_id', 'Zlokalizowana broń'))

-- Przed tym wywołaniem zastosuj zlokalizowane teksty GMST.
local refreshedEffects = tr.refreshDerivedLocalization()
```

W prawdziwym projekcie lokalizacyjnym warto zliczać przypisania według typu
rekordu i raportować brakujące rekordy podczas uruchamiania. Raport z zerową
liczbą braków ułatwia wykrywanie niezgodnych wersji gry lub brakujących
zależności.

## Używanie istniejących mutowalnych rekordów `openmw.content`

API specyficzne dla lokalizacji nie duplikuje każdego mutowalnego API zawartości
dostępnego już w OpenMW.

Dla typów rekordów, które udostępniają odpowiednie mutowalne pole wyświetlane
przez `openmw.content`, warstwa lokalizacyjna może użyć istniejącego API
zawartości.

API lokalizacji w czasie działania opisane w tym dokumencie służy przede
wszystkim do:

- mapowań tłumaczeń, które muszą zachować kanoniczne wartości dialogowe
  i skryptowe,
- typów rekordów wymagających kontrolowanego settera lokalizacyjnego,
- pochodnych wartości wyświetlanych wymagających jawnego odświeżenia.

## Kolejność ładowania i konflikty

Warstwa lokalizacyjna powinna stosować dane zgodnie z zamierzoną kolejnością
priorytetów zawartości.

Settery wywoływane w czasie działania mogą zastępować wcześniejsze wartości.
Jest to przydatne dla dodatków i modów, ale oznacza, że kolejność modułów ma
znaczenie.

W szczególności `setChoiceText()` i `setScriptString()` używają obecnie kluczy
opartych tylko na tekście źródłowym. Jeśli dwa moduły wymagają różnych tłumaczeń
tego samego tekstu źródłowego, nie mogą współistnieć kontekstowo przy użyciu
obecnego API; wygrywa późniejsza wartość.

## Uwaga dotycząca zapisów gry

Teksty dziennika zapisane już w save nie są wstecznie przepisywane po zmianie
warstwy lokalizacyjnej. Nowo tworzone wpisy dziennika używają bieżącego
tłumaczenia INFO w czasie działania.

## Zakres

To API jest mechanizmem po stronie silnika dla zewnętrznych warstw
lokalizacyjnych. Nie służy do przechowywania ani dystrybucji chronionych prawem
autorskim danych tłumaczeniowych gry.

Uzasadnienie projektu i przepływ danych opisano w
[ARCHITECTURE_PL.md](ARCHITECTURE_PL.md).
