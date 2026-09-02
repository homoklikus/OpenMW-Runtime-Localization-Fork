# Runtime Localization — dokumentacja formatu YAML

## 1. Założenia

System Runtime Localization umożliwia tłumaczenie zawartości Morrowinda, dodatków oraz modów **bez modyfikowania plików ESM/ESP na dysku**.

Tłumaczenia są ładowane podczas uruchamiania gry z osobnych plików YAML i nakładane na rekordy znajdujące się w pamięci OpenMW.

System:

- nie wymaga Lua,
- nie wymaga modyfikowania ESM/ESP,
- respektuje kolejność aktywnych plików zawartości,
- pozwala przechowywać tłumaczenia osobno dla każdego moda,
- korzysta z ustawienia języka OpenMW,
- obsługuje formatowanie wybranych tekstów,
- posiada opcjonalny tryb QA do identyfikowania tłumaczeń pochodzących z wybranego moda.

## 2. Sidecary YAML

Każdy aktywny plik zawartości może posiadać odpowiadający mu plik YAML.

Przykłady:

```text
Morrowind.esm
→ localization/language/Morrowind.yaml

Tribunal.esm
→ localization/language/Tribunal.yaml

SomeMod.esp
→ localization/language/SomeMod.yaml

SomeAddon.omwaddon
→ localization/language/SomeAddon.yaml
```

Obsługiwane pliki zawartości:

```text
.esm
.esp
.omwaddon
.omwgame
```

Pliki:

```text
.omwscripts
```

nie są traktowane jako źródła Runtime Localization.

System **nie skanuje katalogu w poszukiwaniu YAML-i**.

Nazwa sidecara jest wyprowadzana bezpośrednio z nazwy aktywnego pliku zawartości.

Dla:

```text
My Great Mod.esp
```

oczekiwany plik to:

```text
localization/language/My Great Mod.yaml
```

## 3. Kolejność ładowania

Sidecary są ładowane zgodnie z kolejnością aktywnych plików zawartości OpenMW.

Oznacza to, że późniejszy mod może nadpisać tłumaczenie rekordu pochodzącego z wcześniejszego moda lub z podstawowej gry.

Przykład:

```text
Morrowind.esm
SomePatch.esp
```

oraz:

```text
localization/language/Morrowind.yaml
localization/language/SomePatch.yaml
```

Jeżeli oba YAML-e definiują tłumaczenie tego samego rekordu, obowiązuje wartość z:

```text
SomePatch.yaml
```

## 4. Podstawowa struktura YAML

Każdy plik musi posiadać dwa główne elementy:

```yaml
meta:
  module: ExampleMod
  source_language: en

strings:
```

Przykład:

```yaml
meta:
  module: ExampleMod
  source_language: en

strings:
  'CLOT|ring_keley|FNAM':
    EN: 'Engraved Ring of Healing'
    PL: 'Zdobiony Pierścień Uzdrawiania'
```

### `meta`

Przechowuje informacje opisowe o module tłumaczenia.

Przykład:

```yaml
meta:
  module: ExampleMod
  source_language: en
```

### `strings`

Zawiera właściwe rekordy lokalizacji.

## 5. Klucze rekordów

Klucz identyfikuje konkretny rekord i jego pole.

Przykład:

```yaml
'CLOT|ring_keley|FNAM'
```

oznacza:

```text
CLOT
→ typ rekordu

ring_keley
→ ID rekordu

FNAM
→ tłumaczone pole
```

Pełny zapis:

```yaml
strings:
  'CLOT|ring_keley|FNAM':
    EN: 'Engraved Ring of Healing'
    PL: 'Zdobiony Pierścień Uzdrawiania'
```

## 6. Języki

System Runtime Localization używa tej samej listy preferowanych języków co OpenMW.

Przykład:

```ini
[General]
preferred locales = pl,en
```

oznacza:

1. spróbuj `PL`,
2. jeżeli brak — użyj `EN`.

Nie istnieje osobny przełącznik języka Runtime Localization.

Przykład YAML:

```yaml
'CLOT|ring_keley|FNAM':
  EN: 'Engraved Ring of Healing'
  PL: 'Zdobiony Pierścień Uzdrawiania'
```

Przy:

```ini
preferred locales = pl,en
```

zostanie wybrane:

```text
Zdobiony Pierścień Uzdrawiania
```

Przy:

```ini
preferred locales = en
```

zostanie wybrane:

```text
Engraved Ring of Healing
```

## 7. Dialogi INFO

Rekordy `INFO|...|NAME` obsługują dodatkowe warianty zależne od płci NPC i gracza.

Najprostsza forma:

```yaml
'INFO|Greeting 0|example_info|NAME':
  EN: 'Hello.'
  PL: 'Witaj.'
```

Możliwa jest również forma rozszerzona.

### Wartość domyślna

```yaml
PL:
  default: 'Witaj.'
```

### Płeć NPC

```yaml
PL:
  npc:
    male: 'Witaj, mój panie.'
    female: 'Witaj, moja pani.'
```

### Płeć gracza

```yaml
PL:
  player:
    male: 'Witaj, bohaterze.'
    female: 'Witaj, bohaterko.'
```

### Płeć NPC + gracza

```yaml
PL:
  npc_player:
    male:
      male: 'NPC mężczyzna, gracz mężczyzna.'
      female: 'NPC mężczyzna, gracz kobieta.'

    female:
      male: 'NPC kobieta, gracz mężczyzna.'
      female: 'NPC kobieta, gracz kobieta.'
```

Pełny przykład:

```yaml
'INFO|Greeting 0|example_info|NAME':
  EN: 'Hello.'

  PL:
    default: 'Witaj.'

    npc:
      male: 'Witaj od NPC mężczyzny.'
      female: 'Witaj od NPC kobiety.'

    player:
      male: 'Witaj, graczu.'
      female: 'Witaj, graczko.'

    npc_player:
      male:
        male: 'NPC mężczyzna + gracz mężczyzna.'
        female: 'NPC mężczyzna + gracz kobieta.'

      female:
        male: 'NPC kobieta + gracz mężczyzna.'
        female: 'NPC kobieta + gracz kobieta.'
```

## 8. Formatowanie tekstu

Runtime Localization obsługuje specjalne znaczniki przeznaczone wyłącznie dla YAML.

Nie należy dodawać tych znaczników do ESM/ESP.

Obsługiwane są:

```text
[c=#RRGGBB]
[b]
[i]
```

### Kolor

```yaml
PL: '[c=#ffd060]Pradawny artefakt[/c]'
```

### Pogrubienie

```yaml
PL: '[b]Pradawny artefakt[/b]'
```

### Kursywa

```yaml
PL: '[i]Pradawny artefakt[/i]'
```

### Łączenie formatowania

```yaml
PL: '[b][c=#ffd060]Pradawny artefakt[/c][/b]'
```

lub:

```yaml
PL: '[c=#ffd060][b][i]Pradawny artefakt[/i][/b][/c]'
```

Znaczniki muszą być poprawnie zamknięte i zagnieżdżone.

## 9. Gdzie działa formatowanie

Obsługa formatowania jest celowo ograniczona do wybranych elementów interfejsu.

### Tooltipy przedmiotów

```text
[c] ✅
[b] ❌ wizualnie
[i] ❌ wizualnie
```

Pogrubienie i kursywa są rozpoznawane przez parser, ale nie zmieniają wyglądu nazwy w tooltipie.

### Dialogi INFO

```text
[c] ✅
[b] ✅
[i] ✅
zagnieżdżanie ✅
```

### Książki / Zwoje (rekordy BOOK / SCROLL)

```text
[c] ✅
[b] ✅
[i] ✅
zagnieżdżanie ✅
```

Formatowanie nie jest automatycznie interpretowane we wszystkich pozostałych polach UI.

Jest to działanie zamierzone.

## 10. Bezpieczeństwo danych gry

Znaczniki formatowania nie są zapisywane bezpośrednio do tekstu rekordu ESM używanego przez logikę gry.

Przykład YAML:

```yaml
PL: '[c=#ffd060]Zdobiony[/c] Pierścień Uzdrawiania'
```

do rekordu runtime trafia zwykły tekst:

```text
Zdobiony Pierścień Uzdrawiania
```

a informacja:

```text
[c=#ffd060]...[/c]
```

jest przechowywana osobno i wykorzystywana wyłącznie podczas renderowania interfejsu.

Dzięki temu znaczniki nie wpływają na:

- skrypty,
- wyszukiwanie,
- logikę gry,
- porównywanie nazw,
- dane zapisane w ESM/ESP.

## 11. Błędny markup

Jeżeli znaczniki są niepoprawnie zagnieżdżone lub niedomknięte, Runtime Localization nie próbuje ich częściowo naprawiać.

Przykład błędny:

```yaml
PL: '[b][i]Tekst[/b][/i]'
```

lub:

```yaml
PL: '[c=#ffd060]Tekst'
```

W takim przypadku tekst pozostaje widoczny jako zwykły tekst, a do logu trafia ostrzeżenie o błędnym markupie.

## 12. Nadpisywanie formatowania

Jeżeli wcześniejszy sidecar posiada markup:

```yaml
PL: '[c=#ffd060]Artefakt[/c]'
```

a późniejszy sidecar nadpisze rekord zwykłym tekstem:

```yaml
PL: 'Artefakt'
```

wcześniejsze formatowanie zostaje usunięte.

Nie pozostaje „stary” kolor lub styl po poprzednim tłumaczeniu.

## 13. QA Highlight

QA Highlight jest narzędziem dla tłumaczy i testerów.

Pozwala automatycznie oznaczyć teksty pochodzące z konkretnego sidecara.

Nie wymaga żadnych zmian w YAML.

Ustawienie:

```ini
[General]
runtime localization qa source = ExampleMod
```

Można wskazać źródło odpowiadające np.:

```text
ExampleMod.esp
ExampleMod.yaml
```

System normalizuje nazwę źródła.

Po aktywowaniu QA wybrane teksty otrzymują dodatkowy marker:

```text
QA:
```

w jaskrawym kolorze.

Przykład:

```text
QA: Zdobiony Pierścień Uzdrawiania
```

QA działa obecnie w:

```text
tooltipach
INFO
Książkach / Zwojach
```

## 14. QA a formatowanie tłumacza

QA Highlight nie zastępuje formatowania określonego w YAML.

Przykład:

```yaml
PL: '[c=#ffd060]Zdobiony[/c] Pierścień [c=#60d0ff]Uzdrawiania[/c]'
```

przy aktywnym QA nadal zachowuje kolory tłumacza.

Marker:

```text
QA:
```

jest osobnym elementem.

Czyli:

```text
YAML markup
→ formatowanie zamierzone przez tłumacza

QA highlight
→ automatyczna informacja o źródle rekordu
```

## 15. Wyłączenie QA

Puste ustawienie wyłącza funkcję:

```ini
runtime localization qa source =
```

Wtedy:

- marker `QA:` nie jest wyświetlany,
- tłumaczenia działają normalnie,
- markup tłumacza pozostaje aktywny.

## 16. QA i kolejność modów

QA działa na podstawie **faktycznego źródła ostatniego tłumaczenia rekordu**.

Jeżeli:

```text
Morrowind.yaml
```

tłumaczy rekord, a później:

```text
ExampleMod.yaml
```

nadpisuje ten sam rekord, jego provenance wskazuje:

```text
ExampleMod
```

Dzięki temu QA może pokazać teksty faktycznie pochodzące z wybranego moda po uwzględnieniu load orderu.

## 17. Przykładowy kompletny plik

```yaml
meta:
  module: ExampleMod
  source_language: en

strings:

  'CLOT|ring_keley|FNAM':
    EN: 'Engraved Ring of Healing'
    PL: '[c=#ffd060]Zdobiony[/c] Pierścień [c=#60d0ff]Uzdrawiania[/c]'

  'INFO|Greeting 0|example_info|NAME':
    EN: 'Hello.'

    PL:
      default: 'Witaj.'

      npc_player:
        male:
          male: '[c=#ffd060]NPC mężczyzna[/c] + gracz mężczyzna.'
          female: '[c=#ffd060]NPC mężczyzna[/c] + [c=#60d0ff]gracz kobieta[/c].'

        female:
          male: '[c=#ff70c8]NPC kobieta[/c] + gracz mężczyzna.'
          female: '[c=#ff70c8]NPC kobieta[/c] + [c=#60d0ff]gracz kobieta[/c].'

  'BOOK|BookSkill_Enchant1|TEXT':
    EN: '<DIV ALIGN="CENTER">Example book'

    PL: '<DIV ALIGN="CENTER">Przykładowa książka<BR><BR><DIV ALIGN="LEFT">Zwykły tekst.<BR>[i]Kursywa[/i]<BR>[b]Pogrubienie[/b]<BR>[c=#ffd060][b][i]Kolor + pogrubienie + kursywa[/i][/b][/c]'
```

## 18. Czego Runtime Localization nie robi

System nie:

- modyfikuje plików ESM/ESP na dysku,
- zapisuje znaczników `[c]`, `[b]`, `[i]` do pluginów,
- wymaga Lua,
- skanuje całego katalogu w poszukiwaniu przypadkowych YAML-i,
- traktuje `.omwscripts` jako sidecarów,
- formatuje automatycznie każdego rodzaju tekstu w całym interfejsie.
