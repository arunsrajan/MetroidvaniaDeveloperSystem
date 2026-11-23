# Languages of the MetDevSys panel

The panel (the **MetDevSys** tab, its dialogs and tooltips) is translated into the languages of
this folder. Pick one with the language button (a translation icon and the language's code, such
as `EN`) in the top row of the panel's left column: **Auto** follows the editor's language, the
others are the language's own name followed by its English name. The choice is yours alone (an
Editor Setting, the same in every project) and takes effect at once. A string without a
translation shows in English.

A language marked **(beta)** was translated by machine, with checks, and no native speaker has
looked it over yet. If you read one of these languages, fixes are very welcome.

## The files

- `mds.pot` is the template: every English string of the panel. It is made from the scripts by
  `tools/l10n/extract.gd` (in the repository, not in the addon's download); do not edit it.
- `<code>.po` is one language: `ru.po`, `hi.po`, `ta.po`, `pt_BR.po`, `zh_CN.po`... The code is
  Godot's locale code.
- The language list, with the names shown in the menu, is `MDSL10n` in `ui/l10n.gd`.

## Fixing a translation

Open the `.po` file in a text editor or in [Poedit](https://poedit.net/) and change the text after
`msgstr`. Keep these as they are in the English:

- placeholders: `%d`, `%s`, `%.1f`, `%%` and `{name}`. The program fills them in; a changed one
  breaks the text (a missing `%s` is an error). Keep `%` placeholders in the same order; `{name}`
  fields may move;
- BBCode tags: `[b]`, `[/b]`, `[color=...]`, `[url=room:%s]`;
- `&&` (it shows one `&`), the line breaks, and the spaces at the start or end of a string;
- names that are not words: MetDevSys, MetSys, Godot, MCP, JSON, PNG, class names such as
  `MDSRoomCamera`, file names, key names such as Ctrl+Z, and units (px).

Labels and buttons sit in a narrow column, so keep them about as long as the English.

To see a translation as you work, start the editor with the language for that session only (your
setting is not changed) and the MetDevSys tab opens by itself:

    godot --editor --path . -- --mds-language=ru

To check a language, from the repository (Godot 4.6 or newer):

    godot --headless --path . --script res://tools/l10n/sync.gd -- --check ru

It lists what is wrong with a translation (a lost placeholder or tag) and how much of the panel the
language covers. `tests/test_l10n.tscn` runs the same checks on every language.

## Adding a language

1. Add a line to the table in `ui/l10n.gd` (code, name in its own language, English name, whether
   it is written right to left, `beta`).
2. Make its `.po`: `sync.gd -- --chunks <code> <folder>` cuts the missing strings into JSON files,
   and `sync.gd -- --import <code> <folder>` reads your translations of them
   (`{"id": "translation"}` in `out_NNN.json`) into `<code>.po`, rejecting any that would break the
   panel. Or copy `mds.pot` to `<code>.po`, put `"Language: <code>\n"` in its header and fill in
   the `msgstr` lines.
3. Run `tests/test_l10n.tscn`.

## After the extractor changes

When the panel's English text changes, `tools/l10n/extract.gd` makes a new `mds.pot` and
`tests/test_l10n.tscn` fails until it is committed. The `.po` files then lack the new strings,
which show in English until `sync.gd -- --chunks <code>` and `--import` bring them in.
