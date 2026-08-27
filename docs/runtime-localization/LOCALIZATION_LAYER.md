# External Localization Layer

The **OpenMW 0.51.0 — Runtime Localization Fork** provides engine hooks for
runtime localization. It does not define or ship a mandatory translation
database format.

A localization project may use YAML, JSON, a database, generated Lua tables or
another format as long as a content script eventually applies the data through
the runtime API.

This separation is intentional:

```text
engine fork              localization project
-----------              --------------------
runtime hooks      <---  loader
canonical/display        translation data
separation               fonts/assets if needed
OpenMW integration       project-specific tooling
```

## Legal and distribution scope

This repository contains only engine source code and documentation.

Do not add extracted game text, third-party translated game text, Bethesda
assets or other copyrighted localization material unless you have the rights to
redistribute it.

A user may build a localization layer from game files they legally own, but the
resulting data is separate from this engine repository.

## Canonical IDs are the key

A runtime localization layer should keep canonical TES3 identifiers as its
stable keys.

Localized text is a display value.

For example:

```yaml
records:
  - type: WEAP
    id: example_weapon_id
    name: "Localized example weapon"
```

The synthetic `example_weapon_id` above represents the canonical record ID. The
loader should change the visible name, not replace the technical ID.

## YAML is optional

The fork does not parse YAML itself.

If you choose YAML, the architecture is:

```text
YAML file
   |
   v
localization loader
   |
   v
openmw.content / content.translations
   |
   v
runtime display state
```

The loader is responsible for:

- reading the YAML data,
- validating required fields,
- applying modules in the intended order,
- reporting missing records,
- calling the appropriate runtime API,
- refreshing derived values after localized GMST data is applied.

## Suggested project structure

A localization project may use a structure similar to:

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
└── project-specific metadata
```

This is only a recommendation. The exact OpenMW content packaging and manifest
files should follow the OpenMW version you are targeting.

Keeping modules separate makes load order and conflict resolution easier.

## Suggested YAML model

The following schema is illustrative, not an engine requirement.

```yaml
version: 1

translations:
  cells:
    - source: "Source Cell"
      display: "Localized Cell"

  topics:
    - id: "source topic id"
      display: "Localized topic"
      keyword: "localized keyword"

  info:
    - topic_id: "source topic id"
      info_id: "source-info-id"
      display: "Localized dialogue response"

  choices:
    - source: "Source choice"
      display: "Localized choice"

  script_strings:
    - source: "Source message"
      display: "Localized message"

records:
  factions:
    - id: "example_faction_id"
      name: "Localized faction"

  weapons:
    - id: "example_weapon_id"
      name: "Localized weapon"
```

All strings above are synthetic examples.

A real project may prefer maps instead of lists, separate files per record type,
or a generated binary/indexed representation.

## Loader example

The loader converts project data into engine calls.

Conceptually:

```lua
local content = require('openmw.content')
local tr = content.translations

tr.setCellName('Source Cell', 'Localized Cell')
tr.setTopicName('source topic id', 'Localized topic')
tr.setTopicKeyword('source topic id', 'localized keyword')

tr.setInfoResponse(
    'source topic id',
    'source-info-id',
    'Localized dialogue response'
)

tr.setChoiceText('Source choice', 'Localized choice')
tr.setScriptString('Source message', 'Localized message')

local ok = tr.setWeaponName('example_weapon_id', 'Localized weapon')
if not ok then
    -- report a missing or incompatible record
end
```

See [API.md](API.md) for the complete fork-specific API.

## Data extraction workflow

A translation project can build its data in several stages.

### 1. Start from legally owned content

Use the source ESM/ESP files that correspond to the game or mod version you are
localizing.

### 2. Export canonical identifiers and user-visible fields

Use a suitable TES3 inspection/export tool to produce a working dataset
containing:

- record type,
- canonical record ID,
- canonical dialogue topic/INFO identifiers where applicable,
- source display text,
- any context required by translators.

Do not replace canonical IDs with translated IDs.

### 3. Translate display fields

Store the translated value beside the canonical key.

A useful translator dataset normally contains both the source text and the
localized text even if the final runtime file is optimized later.

### 4. Validate against the target content set

Before runtime application, verify that every record referenced by the
localization data exists in the intended game/mod loadout.

### 5. Apply in content priority order

A practical order is:

```text
base game
expansions
mods
mod-specific corrections
```

The exact order should mirror the effective content dependencies of the
localization project.

## Translation maps versus record setters

Use `content.translations` when the engine must keep a canonical value separate
from the displayed value.

This is particularly important for:

- dialogue topic names,
- INFO responses,
- Choice labels,
- selected MWScript display strings,
- cell names handled by the translation store.

For records whose display name/description is safely represented by a runtime
record copy, use the corresponding setter documented in [API.md](API.md).

For content types already supported by suitable mutable `openmw.content` APIs,
a loader may use the upstream mutable API directly.

## Topic forms and keywords

A localized dialogue topic may need more than one piece of data:

```text
canonical topic ID
localized display name
localized phrase form
localized hyperlink/search keyword
```

The fork deliberately keeps the canonical topic ID separate from all of these
display/search forms.

Use:

```lua
tr.setTopicName(topicId, displayName)
tr.setTopicForm(phrase, topicId)
tr.setTopicKeyword(topicId, keyword)
```

A later `setTopicForm()` call for the same phrase replaces the earlier runtime
mapping.

## INFO records

Use both the canonical topic ID and canonical INFO ID:

```lua
tr.setInfoResponse(topicId, infoId, displayResponse)
```

Do not key INFO responses only by source text. The runtime API already supports
record context for INFO.

## Choice and script-string limitation

`setChoiceText()` and `setScriptString()` are currently keyed only by source
text.

Therefore:

```text
same source string + different required translations in different modules
```

cannot currently be represented context-sensitively. The later runtime
assignment wins.

A localization project should detect such collisions during data generation or
validation and report them.

## GMST and derived localization

Some visible names are derived from game settings during startup.

If your localization layer changes relevant GMST strings, apply those changes
first and then call:

```lua
local refreshed = tr.refreshDerivedLocalization()
```

This rebuilds the currently supported derived display values.

See [API.md](API.md) for the exact scope and return value.

## Missing-record reporting

Do not silently ignore failed record setters.

A useful loader should track at least:

```text
applied entries
missing entries
counts per record type
conflicts/collisions
```

Example:

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

apply(tr.setWeaponName('example_weapon_id', 'Localized weapon'))
```

For translation-map setters that do not return a status value, validate their
canonical keys in your own data-generation or loading process when possible.

## Save games

New journal entries are constructed using the currently active INFO display
translation.

Journal text already serialized into an existing save is not retroactively
rewritten when the localization data changes.

Localization projects should test both new games and existing saves.

## Fonts, textures, audio and video

The runtime localization API only addresses engine-visible text and selected
record display fields.

Language-specific fonts or replacement assets are separate OpenMW content and
should be packaged by the localization project, not by this engine repository.

## Testing without copyrighted data

Engine developers can test the public fork with a synthetic localization layer
containing invented IDs/text plus a small test plugin created for that purpose.

This is preferable for public regression tests because it keeps proprietary game
localization data out of the repository.

## Related documentation

- [Architecture](ARCHITECTURE.md)
- [Runtime Localization Lua API](API.md)
- [Building on Linux](BUILD_LINUX.md)
- [Building on Windows](BUILD_WINDOWS.md)
