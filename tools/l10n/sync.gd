extends SceneTree
## The translators' side of the catalog:
##   godot --headless --path . --script res://tools/l10n/sync.gd -- <command>
## Commands:
##   --chunks <lang> <dir> [size]   cuts what <lang> still lacks into <dir>/in_001.json, ...: each
##                                  entry has an id, the English, a note and where it is shown
##   --import <lang> <dir>          reads <dir>/out_*.json ({"id": "translation"}) into
##                                  locale/<lang>.po; a translation that fails the checks is
##                                  left out and listed in <dir>/rejected.txt
##   --check [lang ...] [--complete]  each language's coverage and what is wrong with it; exits
##                                  with 1 on an error, or with --complete on a language that
##                                  lacks a string

const Extractor := preload("res://tools/l10n/extractor.gd")
const Validator := preload("res://tools/l10n/validator.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var code := 0
	if args.size() >= 3 and args[0] == "--chunks":
		_chunks(args[1], args[2], int(args[3]) if args.size() > 3 else 70)
	elif args.size() >= 3 and args[0] == "--import":
		code = _import(args[1], args[2])
	elif args.size() >= 1 and args[0] == "--check":
		var langs: Array = []
		for a in args.slice(1):
			if not a.begins_with("--"):
				langs.append(a)
		code = _check(langs, "--complete" in args)
	else:
		print("see the comment at the top of tools/l10n/sync.gd")
	quit(code)

# --- Reading and writing .po files ------------------------------------------------------------------

static func po_path(lang: String) -> String:
	return Extractor.ADDON + "/locale/" + lang + ".po"

## The catalog of [param lang] as Godot reads it, or null when there is none.
static func load_po(lang: String) -> Translation:
	if not FileAccess.file_exists(po_path(lang)):
		return null
	return ResourceLoader.load(po_path(lang), "Translation", ResourceLoader.CACHE_MODE_IGNORE) as Translation

static func translation_of(t: Translation, message: Dictionary) -> String:
	return str(t.get_message(message.msgid, message.context)) if t else ""

## The text of the .po file of [param lang] with [param translations] (message key -> text).
static func po_text(lang: String, messages: Dictionary, translations: Dictionary) -> String:
	var info := MDSL10n.language_info(lang)
	var lines := PackedStringArray([
		"# %s translation of the Metroidvania Developer System panel." % info.get("english", lang),
		"# Edit the strings after msgstr; keep placeholders (%s, %d, {name}), [tags] and && as they are.",
		"msgid \"\"",
		"msgstr \"\"",
		"\"Project-Id-Version: Metroidvania Developer System\\n\"",
		"\"Language: %s\\n\"" % lang,
		"\"MIME-Version: 1.0\\n\"",
		"\"Content-Type: text/plain; charset=UTF-8\\n\"",
		"\"Content-Transfer-Encoding: 8bit\\n\"",
		"\"Plural-Forms: %s;\\n\"" % TranslationServer.get_plural_rules(lang).trim_suffix(";"),
		"\"X-MDS-Status: %s\\n\"" % info.get("status", "beta"),
		"",
	])
	for key in messages:
		var m: Dictionary = messages[key]
		if not str(m.context).is_empty():
			lines.append("msgctxt " + Extractor.quote(m.context))
		lines.append("msgid " + Extractor.quote(m.msgid))
		lines.append("msgstr " + Extractor.quote(translations.get(key, "")))
		lines.append("")
	return "\n".join(lines)

# --- Commands ---------------------------------------------------------------------------------------

func _chunks(lang: String, dir: String, size: int) -> void:
	var extracted := Extractor.extract()
	var existing := load_po(lang)
	DirAccess.make_dir_recursive_absolute(dir)
	var pending: Array = []
	var id := 0
	for key in extracted.messages:
		var m: Dictionary = extracted.messages[key]
		id += 1
		if not translation_of(existing, m).is_empty():
			continue
		pending.append({"id": id, "english": m.msgid, "context": m.context, "note": " ".join(m.notes), "where": m.refs[0] if not m.refs.is_empty() else ""})
	var n := 0
	for i in range(0, pending.size(), size):
		n += 1
		var file := FileAccess.open(dir.path_join("in_%03d.json" % n), FileAccess.WRITE)
		file.store_string(JSON.stringify(pending.slice(i, i + size), "\t"))
		file.close()
	print("sync: %s lacks %d of %d messages: %d chunk(s) of up to %d in %s" % [lang, pending.size(), extracted.messages.size(), n, size, dir])

func _import(lang: String, dir: String) -> int:
	if MDSL10n.language_info(lang).is_empty():
		printerr("sync: '%s' is not a language of the list (ui/l10n.gd)" % lang)
		return 1
	var extracted := Extractor.extract()
	var by_id: Dictionary = {}
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("in_") and f.ends_with(".json"):
			for e in JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f))):
				by_id[int(e.id)] = e
	var incoming: Dictionary = {}
	var rejected := PackedStringArray()
	var unknown := 0
	for f in DirAccess.get_files_at(dir):
		if not (f.begins_with("out_") and f.ends_with(".json")):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not parsed is Dictionary:
			printerr("sync: %s is not a JSON object {id: translation}" % f)
			continue
		for k in parsed:
			var e: Variant = by_id.get(int(k))
			if e == null:
				unknown += 1
				continue
			incoming[Extractor.message_key(e.english, e.context)] = str(parsed[k])
	var existing := load_po(lang)
	var result: Dictionary = {}
	var taken := 0
	var warned := 0
	for key in extracted.messages:
		var m: Dictionary = extracted.messages[key]
		var text := ""
		if incoming.has(key):
			var found := Validator.problems(lang, m.msgid, incoming[key])
			if found.errors.is_empty():
				text = incoming[key]
				taken += 1
				warned += 1 if not found.warnings.is_empty() else 0
			else:
				rejected.append("%s | %s | %s" % [Extractor.quote(m.msgid).left(70), "; ".join(found.errors), Extractor.quote(incoming[key]).left(70)])
		if text.is_empty():
			text = translation_of(existing, m)
		result[key] = text
	var file := FileAccess.open(po_path(lang), FileAccess.WRITE)
	file.store_string(po_text(lang, extracted.messages, result))
	file.close()
	var have := 0
	for key in result:
		have += 0 if str(result[key]).is_empty() else 1
	if not rejected.is_empty():
		var rf := FileAccess.open(dir.path_join("rejected.txt"), FileAccess.WRITE)
		rf.store_string("\n".join(rejected))
		rf.close()
	print("sync: %s: %d new translations taken (%d with warnings), %d rejected, %d unknown ids; %d of %d messages are translated now (%s)" % [lang, taken, warned, rejected.size(), unknown, have, result.size(), po_path(lang)])
	for line in rejected.slice(0, 8):
		print("  rejected: ", line)
	return 0

func _check(langs: Array, complete: bool) -> int:
	var extracted := Extractor.extract()
	if langs.is_empty():
		for f in DirAccess.get_files_at(Extractor.ADDON + "/locale"):
			if f.ends_with(".po"):
				langs.append(f.trim_suffix(".po"))
		langs.sort()
	var failed := 0
	for lang: String in langs:
		var t := load_po(lang)
		if not t:
			printerr("sync: %s: no catalog" % lang)
			failed += 1
			continue
		var have := 0
		var errors := PackedStringArray()
		var warnings := 0
		for key in extracted.messages:
			var m: Dictionary = extracted.messages[key]
			var text := translation_of(t, m)
			if text.is_empty():
				continue
			have += 1
			var found := Validator.problems(lang, m.msgid, text)
			for e in found.errors:
				errors.append("%s: %s" % [Extractor.quote(m.msgid).left(60), e])
			warnings += found.warnings.size()
		var wrong_locale := t.locale != lang
		print("sync: %-6s %4d/%d (%5.1f%%)  %d errors, %d warnings%s" % [lang, have, extracted.messages.size(), 100.0 * have / maxi(1, extracted.messages.size()), errors.size(), warnings, "  LOCALE HEADER IS '%s'" % t.locale if wrong_locale else ""])
		for line in errors.slice(0, 6):
			print("      error: ", line)
		if not errors.is_empty() or wrong_locale or (complete and have < extracted.messages.size()):
			failed += 1
	return 1 if failed > 0 else 0
