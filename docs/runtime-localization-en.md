# Runtime Localization — YAML format documentation

## 1. Overview

The Runtime Localization system allows Morrowind, its expansions, and mods to be translated **without modifying ESM/ESP files on disk**.

Translations are loaded at game startup from separate YAML files and applied to records stored in OpenMW memory.

The system:

- does not require Lua,
- does not require modifying ESM/ESP files,
- respects the order of active content files,
- allows translations to be stored separately for each mod,
- uses OpenMW's language settings,
- supports formatting for selected text surfaces,
- provides an optional QA mode for identifying translations originating from a selected mod.

## 2. YAML sidecars

Each active content file may have a corresponding YAML file.

Examples:

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

Supported content file types:

```text
.esm
.esp
.omwaddon
.omwgame
```

Files with the extension:

```text
.omwscripts
```

are not treated as Runtime Localization sources.

The system **does not scan the directory for YAML files**.

The sidecar name is derived directly from the active content file name.

For:

```text
My Great Mod.esp
```

the expected file is:

```text
localization/language/My Great Mod.yaml
```

## 3. Load order

Sidecars are loaded according to OpenMW's active content file order.

This means that a later mod may override a translation originating from an earlier mod or from the base game.

Example:

```text
Morrowind.esm
SomePatch.esp
```

with:

```text
localization/language/Morrowind.yaml
localization/language/SomePatch.yaml
```

If both YAML files define a translation for the same record, the value from:

```text
SomePatch.yaml
```

is used.

## 4. Basic YAML structure

Each file must contain two top-level elements:

```yaml
meta:
  module: ExampleMod
  source_language: en

strings:
```

Example:

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

Contains descriptive information about the translation module.

Example:

```yaml
meta:
  module: ExampleMod
  source_language: en
```

### `strings`

Contains the actual localization records.

## 5. Record keys

A key identifies a specific record and field.

Example:

```yaml
'CLOT|ring_keley|FNAM'
```

means:

```text
CLOT
→ record type

ring_keley
→ record ID

FNAM
→ translated field
```

Complete example:

```yaml
strings:
  'CLOT|ring_keley|FNAM':
    EN: 'Engraved Ring of Healing'
    PL: 'Zdobiony Pierścień Uzdrawiania'
```

## 6. Languages

Runtime Localization uses the same preferred language list as OpenMW.

Example:

```ini
[General]
preferred locales = pl,en
```

means:

1. try `PL`,
2. if unavailable, use `EN`.

There is no separate Runtime Localization language selector.

Example YAML:

```yaml
'CLOT|ring_keley|FNAM':
  EN: 'Engraved Ring of Healing'
  PL: 'Zdobiony Pierścień Uzdrawiania'
```

With:

```ini
preferred locales = pl,en
```

the selected value is:

```text
Zdobiony Pierścień Uzdrawiania
```

With:

```ini
preferred locales = en
```

the selected value is:

```text
Engraved Ring of Healing
```

## 7. INFO dialogue records

`INFO|...|NAME` records support additional variants based on NPC and player gender.

The simplest form is:

```yaml
'INFO|Greeting 0|example_info|NAME':
  EN: 'Hello.'
  PL: 'Witaj.'
```

An extended form is also supported.

### Default value

```yaml
PL:
  default: 'Witaj.'
```

### NPC gender

```yaml
PL:
  npc:
    male: 'Witaj, mój panie.'
    female: 'Witaj, moja pani.'
```

### Player gender

```yaml
PL:
  player:
    male: 'Witaj, bohaterze.'
    female: 'Witaj, bohaterko.'
```

### NPC + player gender

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

Complete example:

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

## 8. Text formatting

Runtime Localization supports special markup intended exclusively for YAML.

These tags should not be added to ESM/ESP files.

Supported tags:

```text
[c=#RRGGBB]
[b]
[i]
```

### Colour

```yaml
PL: '[c=#ffd060]Pradawny artefakt[/c]'
```

### Bold

```yaml
PL: '[b]Pradawny artefakt[/b]'
```

### Italic

```yaml
PL: '[i]Pradawny artefakt[/i]'
```

### Combining formatting

```yaml
PL: '[b][c=#ffd060]Pradawny artefakt[/c][/b]'
```

or:

```yaml
PL: '[c=#ffd060][b][i]Pradawny artefakt[/i][/b][/c]'
```

Tags must be properly closed and nested.

## 9. Where formatting is supported

Formatting support is intentionally limited to selected UI surfaces.

### Item tooltips

```text
[c] ✅
[b] ❌ visually
[i] ❌ visually
```

Bold and italic tags are recognized by the parser, but do not change the visual appearance of the item name in tooltips.

### INFO dialogue

```text
[c] ✅
[b] ✅
[i] ✅
nesting ✅
```

### Books / Scrolls (BOOK / SCROLL records)

```text
[c] ✅
[b] ✅
[i] ✅
nesting ✅
```

Formatting is not automatically interpreted in every other UI text field.

This is intentional.

## 10. Game data safety

Formatting tags are not written directly into the ESM record text used by game logic.

Example YAML:

```yaml
PL: '[c=#ffd060]Zdobiony[/c] Pierścień Uzdrawiania'
```

The runtime record receives plain text:

```text
Zdobiony Pierścień Uzdrawiania
```

while the formatting information:

```text
[c=#ffd060]...[/c]
```

is stored separately and used only when rendering the UI.

As a result, formatting tags do not affect:

- scripts,
- searching,
- game logic,
- name comparisons,
- data stored in ESM/ESP files.

## 11. Invalid markup

If tags are incorrectly nested or left unclosed, Runtime Localization does not attempt to partially repair them.

Invalid example:

```yaml
PL: '[b][i]Tekst[/b][/i]'
```

or:

```yaml
PL: '[c=#ffd060]Tekst'
```

In such a case, the text remains visible as plain text, and a warning about malformed markup is written to the log.

## 12. Overriding formatting

If an earlier sidecar contains markup:

```yaml
PL: '[c=#ffd060]Artefakt[/c]'
```

and a later sidecar overrides the record with plain text:

```yaml
PL: 'Artefakt'
```

the previous formatting is removed.

No stale colour or style remains from the earlier translation.

## 13. QA Highlight

QA Highlight is a tool for translators and testers.

It allows text originating from a specific sidecar to be marked automatically.

It does not require any changes to the YAML file.

Setting:

```ini
[General]
runtime localization qa source = ExampleMod
```

The source may correspond, for example, to:

```text
ExampleMod.esp
ExampleMod.yaml
```

The system normalizes the source name.

When QA is enabled, selected text receives an additional marker:

```text
QA:
```

displayed in a bright colour.

Example:

```text
QA: Zdobiony Pierścień Uzdrawiania
```

QA currently works in:

```text
tooltips
INFO
Books / Scrolls
```

## 14. QA and translator formatting

QA Highlight does not replace formatting defined in YAML.

Example:

```yaml
PL: '[c=#ffd060]Zdobiony[/c] Pierścień [c=#60d0ff]Uzdrawiania[/c]'
```

With QA enabled, the translator-defined colours remain intact.

The marker:

```text
QA:
```

is a separate element.

In other words:

```text
YAML markup
→ formatting intentionally defined by the translator

QA highlight
→ automatic information about the record source
```

## 15. Disabling QA

An empty setting disables the feature:

```ini
runtime localization qa source =
```

Then:

- the `QA:` marker is not displayed,
- translations continue to work normally,
- translator markup remains active.

## 16. QA and mod load order

QA uses the **actual source of the final translation applied to the record**.

If:

```text
Morrowind.yaml
```

translates a record, and later:

```text
ExampleMod.yaml
```

overrides the same record, its provenance points to:

```text
ExampleMod
```

This allows QA to show text that truly originates from the selected mod after load order has been taken into account.

## 17. Complete example file

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

## 18. What Runtime Localization does not do

The system does not:

- modify ESM/ESP files on disk,
- write `[c]`, `[b]`, or `[i]` tags into plugins,
- require Lua,
- scan the entire directory for arbitrary YAML files,
- treat `.omwscripts` files as sidecars,
- automatically format every type of text throughout the entire UI.
