# Runtime Localization Lua API

This document describes the localization-specific Lua API provided by the
**OpenMW — Runtime Localization Fork**.

The API is available through:

```lua
local content = require('openmw.content')
local translations = content.translations
```

No localization data is bundled with the fork. An external content script is
expected to populate these APIs at runtime.

## Return-value conventions

There are two groups of functions:

- translation-map setters populate `Translation::Storage` and currently return
  no status value,
- record-field setters return `true` on success and `false` when the target
  record or index cannot be resolved.

`refreshDerivedLocalization()` returns an integer count.

## Translation map API

### `setCellName(sourceName, displayName)`

Adds or replaces a display name for a cell name.

```lua
translations.setCellName('Canonical Cell Name', 'Localized Cell Name')
```

The source cell name remains the canonical lookup value.

### `setTopicName(topicId, displayName)`

Sets the visible label for a canonical DIAL topic ID.

```lua
translations.setTopicName('canonical topic', 'Localized topic')
```

The technical topic ID is not changed.

### `setTopicForm(phrase, topicId)`

Maps a localized phrase form to a canonical topic ID.

```lua
translations.setTopicForm('localized phrase', 'canonical topic')
```

Runtime calls use overwrite semantics so a later localization layer can replace
an earlier mapping.

### `setTopicKeyword(topicId, keyword)`

Sets the localized hyperlink/search keyword associated with a canonical topic
ID.

```lua
translations.setTopicKeyword('canonical topic', 'localized keyword')
```

### `setInfoResponse(topicId, infoId, response)`

Sets a display response for one INFO record.

```lua
translations.setInfoResponse(
    'canonical topic',
    'canonical-info-id',
    'Localized dialogue response'
)
```

The mapping is context-sensitive: the key contains both the canonical topic ID
and canonical INFO ID.

The source INFO record remains untouched.

### `setChoiceText(sourceText, displayText)`

Sets a display translation for a visible TES3 `Choice` label.

```lua
translations.setChoiceText('Source choice', 'Localized choice')
```

Only the label changes. The numeric Choice value used by scripts remains
canonical.

**Current limitation:** the map is keyed only by `sourceText`. If multiple
localization modules assign different translations to the same source string,
the last assignment wins.

### `setScriptString(sourceText, displayText)`

Sets a display translation for a selected user-visible MWScript string.

```lua
translations.setScriptString(
    'Source message',
    'Localized message'
)
```

The current engine integration uses this hook for selected visible literals in
`Say` and `MessageBox`.

**Current limitation:** the map is keyed only by `sourceText`. A later
assignment for the same source string replaces the earlier one.

## Record display-field API

The following setters clone the current static record, update only the specified
display field and reinsert the runtime record.

They return `true` when the record was found and updated.

### Factions

```text
translations.setFactionName(id, name) -> boolean
translations.setFactionRankName(id, rankIndex, name) -> boolean
```

`rankIndex` is zero-based and must be in the range `0..9`.

### Classes

```text
translations.setClassName(id, name) -> boolean
translations.setClassDescription(id, description) -> boolean
```

### Races

```text
translations.setRaceName(id, name) -> boolean
translations.setRaceDescription(id, description) -> boolean
```

### Actors

```text
translations.setNpcName(id, name) -> boolean
translations.setCreatureName(id, name) -> boolean
```

### Equipment and inventory objects

```text
translations.setWeaponName(id, name) -> boolean
translations.setArmorName(id, name) -> boolean
translations.setClothingName(id, name) -> boolean
translations.setContainerName(id, name) -> boolean
translations.setApparatusName(id, name) -> boolean
translations.setRepairName(id, name) -> boolean
translations.setLockpickName(id, name) -> boolean
```

### Skills

```text
translations.setSkillDescription(skillIndex, description) -> boolean
```

`skillIndex` is zero-based and must be a valid `ESM::Skill` index.

The function resolves the canonical skill record from the index; it does not
depend on array position in Lua.

Skill display names are GMST-derived and are refreshed separately by
`refreshDerivedLocalization()` after localized GMST values have been applied.

### Birth signs

```text
translations.setBirthSignName(id, name) -> boolean
translations.setBirthSignDescription(id, description) -> boolean
```

### Regions

```text
translations.setRegionName(id, name) -> boolean
```

### Magic effects

```text
translations.setMagicEffectDescription(effectIndex, description) -> boolean
```

`effectIndex` is the canonical TES3 magic-effect index. The function resolves
the runtime record through `ESM::MagicEffect::indexToRefId()` rather than
assuming that the Lua-visible store is a dense array.

Magic-effect display names are GMST-derived and are handled by
`refreshDerivedLocalization()`.

## Derived localization refresh

### `refreshDerivedLocalization()`

```lua
local refreshedEffects = translations.refreshDerivedLocalization()
```

Call this after applying localized GMST strings that affect derived display
values.

The current implementation:

1. rebuilds skill-derived localization from the current game settings,
2. rebuilds attribute-derived localization from the current game settings,
3. updates magic-effect display names from their corresponding `sEffect*` GMST
   strings.

Return value:

```text
number of magic-effect display names refreshed
```

It is not a count of explicit magic-effect description translations.

## Recommended loader pattern

A localization loader should keep canonical IDs in its data and treat localized
strings as display values.

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

tr.setTopicName('canonical topic', 'Localized topic')
applied = applied + 1

apply(tr.setWeaponName('canonical_weapon_id', 'Localized weapon'))

-- Apply localized GMST strings before this call.
local refreshedEffects = tr.refreshDerivedLocalization()
```

For a real localization project, count assignments by record type and report
missing records at startup. A zero-missing startup report is useful for
detecting mismatched game versions or missing dependencies.

## Using existing `openmw.content` mutable records

The localization-specific API does not duplicate every mutable content API
already available in OpenMW.

For record types that already expose a suitable mutable display field through
`openmw.content`, a localization layer can use the existing content API.

The runtime localization API in this document is primarily for:

- translation mappings that must preserve canonical dialogue/script values,
- record types that need a controlled localization setter,
- derived display values that require an explicit refresh.

## Load order and conflicts

A localization layer should apply its data in the intended content priority
order.

Runtime setters can replace earlier runtime values. This is useful for
expansions and mods, but it means module ordering is significant.

In particular, `setChoiceText()` and `setScriptString()` currently use
source-only keys. If two modules require different translations for the same
source text, they cannot coexist context-sensitively through the current API;
the later value wins.

## Save-game note

Journal strings already stored in a save game are not retroactively rewritten
when a localization layer changes. Newly constructed journal entries use the
current runtime INFO translation.

## Scope

This API is an engine hook for external localization layers. It is not intended
to contain or distribute copyrighted game translation data.

For the design rationale and data flow, see
[ARCHITECTURE.md](ARCHITECTURE.md).
