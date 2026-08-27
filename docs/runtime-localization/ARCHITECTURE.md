# Runtime Localization Architecture

This document describes the runtime localization architecture added by the
**OpenMW — Runtime Localization Fork**.

The fork is based on OpenMW 0.51.0. It adds engine-side hooks that allow an
external content layer to provide localized display strings at runtime without
requiring a translated copy of the original TES3 ESM/ESP data.

No game localization data is included in this repository.

## Goals

The runtime localization layer is designed around four goals:

1. Keep canonical TES3 records and technical identifiers intact.
2. Replace user-visible text at display time or through controlled runtime
   record updates.
3. Allow localization data to live outside the engine repository.
4. Preserve normal OpenMW gameplay, dialogue, scripting and save-game behavior
   as far as possible.

This makes it possible to use an original source-language master file while
displaying another language to the player.

## Non-goals

The fork does not:

- contain translated Morrowind, Tribunal, Bloodmoon or mod text,
- generate a translated `.esm` or `.esp`,
- replace the OpenMW l10n system used by native OpenMW Lua mods,
- change canonical TES3 record IDs,
- provide a universal translation-file generator.

A localization layer is responsible for obtaining, storing and applying its own
translation data.

## High-level data flow

A typical localization layer works like this:

```text
source ESM/ESP records
        |
        v
external localization data
        |
        v
OpenMW LOAD/content script
        |
        +--> content.translations runtime API
        |
        +--> existing mutable openmw.content record APIs where appropriate
        |
        v
runtime display state
        |
        v
GUI / dialogue / journal / subtitles / script messages
```

The original content files remain the authoritative source for gameplay-facing
IDs and record relationships.

## Canonical data versus display data

The central design rule is:

> Gameplay logic should continue to use canonical source values whenever the
> value acts as an identifier, lookup key or script-visible technical value.

Localized text is introduced only where a value is meant for presentation.

Examples:

- A DIAL topic keeps its canonical topic ID while the topic list can show a
  localized label.
- An INFO record keeps its original response text in the ESM store while the
  dialogue window receives a localized display response.
- A `Choice` statement keeps its numeric choice value while only its visible
  label is localized.
- `Say` keeps the canonical sound path while subtitle text may be localized.
- Journal topic and INFO IDs remain canonical while newly constructed journal
  text may use localized INFO responses.

This separation is important for compatibility with original content and mods
that expect canonical identifiers.

## Translation::Storage

`Translation::Storage` remains the central display-translation store.

The fork extends it with runtime-populated mappings for:

- cell display names,
- topic display names,
- topic phrase forms,
- topic hyperlink keywords,
- INFO responses,
- Choice labels,
- selected MWScript-visible strings.

The existing file-based translation mechanism remains available. Runtime
population is additive and is exposed to content scripts through
`openmw.content.translations`.

### Context-sensitive and source-only mappings

INFO responses are keyed by canonical topic ID plus INFO ID, so they retain
record context.

Choice labels and selected MWScript strings are currently keyed only by source
text. If two independently loaded localization layers assign different display
text to the same source string, the last runtime assignment wins.

This is a known limitation of the current API and may be extended with
context-sensitive keys in a future version if mod-localization conflicts require
it.

## Dialogue

Dialogue localization deliberately separates presentation from topic discovery
and dialogue mechanics.

### Topic names

A topic can have:

- a canonical topic ID,
- a localized display name,
- a localized phrase form used for recognition,
- a localized hyperlink keyword.

The dialogue UI shows the localized label but emits and processes the canonical
topic value.

The list widget was hardened so its internal MyGUI widget identity is based on a
stable list index rather than the visible caption. This avoids collisions when
two different canonical topics have the same localized display text.

### INFO responses

INFO records themselves are not rewritten.

When OpenMW displays an INFO response, the fork asks `Translation::Storage` for
a display translation using:

```text
canonical topic ID + canonical INFO ID
```

Canonical source response text remains available for internal topic discovery
and normal Lua dialogue notifications.

### Choice

Only the visible `Choice` label is translated.

The numeric choice value used by TES3 scripting remains unchanged.

## MWScript-visible strings

The fork adds a display-translation hook to the MWScript interpreter context.

The current integration covers selected user-visible literals used by:

- `Say`
- `MessageBox`

For `Say`, the sound path remains canonical and only subtitle/display text is
translated.

For `MessageBox`, the template is translated before formatting. Visible literal
string arguments and literal button labels can also be translated. Numeric
format arguments are not localization strings.

The engine hook is intentionally narrow rather than treating every quoted
MWScript string as translatable text.

## Journal and quest display

Journal entries created from INFO records request the localized INFO response
before OpenMW expands dialogue defines.

Quest display names derived from journal INFO records follow the same display
translation path.

A save game stores already-created journal text. Therefore, changing the
localization layer does not retroactively rewrite journal strings that were
already serialized into an existing save.

## Runtime record display fields

Some TES3 records store their user-visible name or description directly in the
record. For those records, the fork provides controlled setters that clone the
existing static record, replace only the localized display field and reinsert
the runtime copy.

Examples include:

- factions and faction ranks,
- classes,
- races,
- NPCs and creatures,
- weapons, armor and clothing,
- containers and tools,
- birth signs,
- regions,
- skill descriptions,
- magic-effect descriptions.

The record ID is not changed.

For content types that already have suitable mutable `openmw.content` APIs, an
external localization layer may use those existing APIs instead of adding
duplicate localization-specific engine bindings.

## Derived localization

Some visible values are derived from GMST records during OpenMW startup rather
than read directly each time they are displayed.

After a localization layer changes relevant GMST strings, it should call:

```lua
content.translations.refreshDerivedLocalization()
```

The current implementation refreshes:

- skill names and magic-school names,
- attribute names/descriptions,
- magic-effect display names derived from `sEffect*` GMST values.

The function returns the number of runtime magic-effect names refreshed. That
number is not the same thing as the number of explicit magic-effect description
translations supplied by a localization layer.

## Load order

Runtime mappings use overwrite semantics where a later assignment needs to
replace an earlier one.

This allows a localization layer to apply data in content/load order, but it
also means the localization layer is responsible for applying modules in the
intended priority order.

A practical architecture for a complete game localization is to keep separate
data modules for the base game, expansions and individual mods, then apply them
in the same effective order as the corresponding content.

## Failure behavior

Most record-field setters return `false` when the requested canonical record
cannot be found or an index is invalid.

A localization loader should count or report failed assignments rather than
silently ignoring them. This makes version mismatches and missing dependencies
visible during startup.

Pure translation-map setters do not currently return a success value because
they populate runtime maps directly.

## Compatibility principles

The implementation follows these compatibility rules:

- canonical ESM/ESP IDs remain unchanged,
- original content files do not need to be modified,
- display localization is separated from gameplay lookup values where possible,
- subtitle visibility still follows the normal OpenMW subtitle setting,
- the standard OpenMW file-based translation system remains available,
- the fork does not ship proprietary localization content.

## Relevant source areas

The main implementation is concentrated in:

```text
components/translation/
components/widgets/list.*
apps/openmw/mwlua/contentbindings.cpp
apps/openmw/mwdialogue/
apps/openmw/mwgui/dialogue.cpp
apps/openmw/mwscript/
components/interpreter/
```

The public Lua API is documented in [API.md](API.md).

## Future work

Potential future extensions include:

- context-sensitive Choice and script-string mappings,
- richer module-aware conflict handling,
- optional grammatical variants selected by an external Lua localization layer,
- additional narrowly scoped display hooks if real content exposes uncovered
  user-visible strings.

Such extensions should continue to preserve the canonical/display separation
described above.
