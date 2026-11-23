# Translating the panel with an AI assistant

How the catalogs of `addons/MetroidvaniaDeveloperSystem/locale/` are made, so that a language can be
made again, or a new one added, the same way. A native speaker's review comes after, and is what
turns `beta` into `reviewed` in `ui/l10n.gd`.

## The steps

All commands run from the repository root with Godot 4.6 or newer
(`godot --headless --path . --script res://tools/l10n/sync.gd -- ...`).

1. `tools/l10n/extract.gd` makes `locale/mds.pot` from the scripts (see its header).
2. `sync.gd -- --chunks <code> <folder> 60` cuts what the language lacks into
   `<folder>/in_001.json`, ...: an array of `{id, english, context, note, where}`.
3. The translator writes `<folder>/out_001.json`, ...: an object `{"<id>": "<translation>"}` for
   each chunk. JSON keyed by id keeps the `.po` escaping out of the translator's hands.
4. `sync.gd -- --import <code> <folder>` checks each translation (tools/l10n/validator.gd) and
   writes `locale/<code>.po`. A translation that loses a placeholder, changes a BBCode tag, a `&&`
   or the line breaks is left out and listed in `<folder>/rejected.txt`; cut the chunks again
   (`--chunks` lists what is still missing) and translate those.
5. `sync.gd -- --check <code>` reports the coverage and what is wrong. `tests/test_l10n.tscn` runs
   the same checks.

## The brief

Give the translator this, with the language filled in (the brief for Russian, Hindi and Tamil
used exactly this):

> You are translating the user-interface text of a Godot editor plugin into {language} ({native},
> code `{code}`). "Metroidvania Developer System" (MDS; its panel is called "MetDevSys") helps game
> developers design and build a metroidvania's world: a world map of rooms joined by gates, rooms
> painted with terrain, stamps, effects and generated caves, checks of the rooms, a Fight editor
> for boss fights. The strings are the labels, buttons, menu items, tooltips (some long), dialog
> texts and status messages of its editor panel.
>
> Work in `{folder}`: translate every `in_NNN.json` into `out_NNN.json`. First write
> `glossary.json`, about 60 frequent domain terms (Room, Gate, Area, Stamp, Tile, Terrain,
> Foreground, Background, Decor, Freeform, Scene, Layer, Pin, Marker, Bench / Save point, Boss,
> Effect, Weather, Parallax, Cave, Seed, Merge, Export, Issues, Progress, Fight, Move, Phase,
> Preview, Generate ...) and use it in every chunk. For engine concepts use the terms Godot's own
> editor uses in {language}; for generic commands the standard software terms of {language}.
> Then import (step 4), fix what is rejected, and run the check (step 5).
>
> Rules: keep every placeholder (`%d`, `%s`, `%.1f`, `%%`) exactly and in the same order, and
> `{name}` fields (they may move); keep BBCode tags (`[b]`, `[color=...]`, `[url=room:%s]`) and
> translate only the text between them; keep `&&` (it shows one `&`), the number of line breaks,
> and spaces at the start or end of a string. Do not translate product and technology names
> (MetDevSys, MetSys, MDS, Godot, MCP, JSON, PNG ...), class names and code identifiers, file
> names and extensions, key names and shortcuts (Ctrl+Z, Shift, V, R, G ...), units (px, s) and
> example values in quotes. Digits stay 0-9; keep "..." for ellipses. Labels, buttons and menu
> items must be about as short as the English (a 220 px column); tooltips may be longer but
> concise. Read `note` and the code at `where` when a word is ambiguous: "Gate" is a door or
> passage between rooms, "Room" a room of the game's world, "Stamps" decoration sprites, "Pin" a
> map note marker, "Bench" a save point.

Add a line on the register of the language: the polite form software uses (Russian: infinitives on
buttons and the formal «вы» in sentences; Hindi: «आप» with «करें»; Tamil: polite imperatives).

## After the translation

- Read a few of the longest strings and the shortest labels in the panel itself (the panel's
  `--mds-language=<code>` run option shows a language for that session).
- Ask a native speaker to look it over. Their fixes go straight into the `.po`; run the check
  again, then set the language's status to `reviewed` in the table of `ui/l10n.gd`.
