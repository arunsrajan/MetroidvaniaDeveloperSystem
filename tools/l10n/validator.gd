extends RefCounted
## Checks a translation against the English text it translates. A translation that loses a
## placeholder, a BBCode tag or a mnemonic breaks the panel (a bad % is a runtime error in
## GDScript), so those are errors; the rest are warnings. Used by sync.gd and by
## tests/test_l10n.gd.

## The ranges of characters each language of the list is written in, for the languages that do
## not use the Latin script: a translation with none of them is probably not translated.
const SCRIPTS := {
	"ru": [[0x0400, 0x052F]], "uk": [[0x0400, 0x052F]], "bg": [[0x0400, 0x052F]],
	"el": [[0x0370, 0x03FF], [0x1F00, 0x1FFF]],
	"ar": [[0x0600, 0x06FF], [0x0750, 0x077F], [0xFB50, 0xFDFF], [0xFE70, 0xFEFF]],
	"ur": [[0x0600, 0x06FF], [0x0750, 0x077F], [0xFB50, 0xFDFF], [0xFE70, 0xFEFF]],
	"fa": [[0x0600, 0x06FF], [0x0750, 0x077F], [0xFB50, 0xFDFF], [0xFE70, 0xFEFF]],
	"he": [[0x0590, 0x05FF]],
	"hi": [[0x0900, 0x097F]], "mr": [[0x0900, 0x097F]], "ne": [[0x0900, 0x097F]],
	"bn": [[0x0980, 0x09FF]], "pa": [[0x0A00, 0x0A7F]], "gu": [[0x0A80, 0x0AFF]],
	"or": [[0x0B00, 0x0B7F]], "ta": [[0x0B80, 0x0BFF]], "te": [[0x0C00, 0x0C7F]],
	"kn": [[0x0C80, 0x0CFF]], "ml": [[0x0D00, 0x0D7F]], "th": [[0x0E00, 0x0E7F]],
	"my": [[0x1000, 0x109F]], "am": [[0x1200, 0x137F]],
	"ja": [[0x3040, 0x30FF], [0x4E00, 0x9FFF]], "ko": [[0x1100, 0x11FF], [0xAC00, 0xD7AF]],
	"zh_CN": [[0x4E00, 0x9FFF]], "zh_TW": [[0x4E00, 0x9FFF]],
}

static var _tag_re: RegEx

## What is wrong with [param msgstr] as the translation of [param msgid] into the language
## [param code]: {errors, warnings}, each a list of sentences. A string that is empty has
## nothing wrong with it: it is just not translated.
static func problems(code: String, msgid: String, msgstr: String) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	if msgstr.is_empty():
		return {"errors": errors, "warnings": warnings}
	if MDSL10n.signature(msgid) != MDSL10n.signature(msgstr):
		errors.append("placeholders differ (%s | %s)" % [MDSL10n.signature(msgid), MDSL10n.signature(msgstr)])
	if _tags(msgid) != _tags(msgstr):
		errors.append("BBCode tags differ (%s | %s)" % [", ".join(_tags(msgid)), ", ".join(_tags(msgstr))])
	if msgid.count("&") != msgstr.count("&"):
		errors.append("the number of & differs (&& is one & shown)")
	if msgid.count("\n") != msgstr.count("\n"):
		errors.append("the number of line breaks differs (%d | %d)" % [msgid.count("\n"), msgstr.count("\n")])
	if _edge(msgid, true) != _edge(msgstr, true) or _edge(msgid, false) != _edge(msgstr, false):
		errors.append("the spaces at its start or end differ")
	if msgstr == msgid and _letters(msgid) >= 5:
		warnings.append("is the same as the English")
	if msgstr.length() > 2.6 * msgid.length() + 12:
		warnings.append("is much longer than the English (%d | %d characters)" % [msgstr.length(), msgid.length()])
	if SCRIPTS.has(code) and _letters(msgid) >= 8 and not _has_script(code, msgstr):
		warnings.append("has no character of the language's script")
	return {"errors": errors, "warnings": warnings}

## Whether [param text] has a character in the ranges of the language [param code].
static func _has_script(code: String, text: String) -> bool:
	for c in text:
		var u := c.unicode_at(0)
		for r: Array in SCRIPTS[code]:
			if u >= r[0] and u <= r[1]:
				return true
	return false

## The BBCode tags of [param text], in order of their names, as they are written.
static func _tags(text: String) -> PackedStringArray:
	if not _tag_re:
		_tag_re = RegEx.create_from_string("\\[/?[a-z]+(?:[= ][^\\]]*)?\\]")
	var out := PackedStringArray()
	for m in _tag_re.search_all(text):
		out.append(m.get_string())
	out.sort()
	return out

## The spaces at the start ([param start]) or the end of [param text].
static func _edge(text: String, start: bool) -> String:
	var kept := text.strip_edges(start, not start)
	return text.substr(0, text.length() - kept.length()) if start else text.substr(kept.length())

static func _letters(text: String) -> int:
	var n := 0
	for c in text:
		if c.to_lower() != c.to_upper():
			n += 1
	return n
