extends RefCounted
## Finds the text of the MetDevSys panel in the addon's scripts, for locale/mds.pot.
## Used by extract.gd (which writes the file) and by tests/test_l10n.gd (which checks it is
## current). Not shipped: only the addon is.
##
## Strings and comments are masked first, so that what is looked for (a property set to a
## string, a call with a string argument) is found in the code and not inside text. A string
## that is the whole value is a message. A string put together with % or + is not: Godot cannot
## translate the result, so it goes to the to-do list until the code is written to translate it
## (MDSL10n.tf and tn, see ui/l10n.gd).
##
## A line with [code]# l10n: skip[/code] at its end, or the line after a comment that is
## only that, is left out: text that is data, not for the user's eyes. A comment that is only
## [code]# l10n: text[/code] claims every string of the statement below it (a table of names, a
## list of labels), whatever shape the code gives it.

const ADDON := "res://addons/MetroidvaniaDeveloperSystem"
const POT := ADDON + "/locale/mds.pot"
const TABLES := "res://tools/l10n/tables.json"
const NOTES := "res://tools/l10n/notes.json"

## Folders of the addon whose scripts are not the panel's own text: the MCP server and exports
## answer AI tools in English, the game kit and the nodes are the game's, the rest is not code.
const SKIP_DIRS := ["mcp", "gameplay", "nodes", "core", "shaders", "styles", "assets", "icons", "locale"]
## Properties that hold text the user reads.
const PROPERTIES := ["text", "tooltip_text", "placeholder_text", "title", "ok_button_text", "cancel_button_text", "dialog_text"]
## Calls that show an argument, by name: the places of the arguments that are text. A name with
## a dot is matched with the class in front of it; one without, whatever it is called on.
const CALLS := {
	"add_item": [0], "add_check_item": [0], "add_radio_check_item": [0], "add_separator": [0],
	"add_submenu_item": [0], "add_tab": [0], "set_tab_title": [1], "add_section": [0],
	"MDSUi.label": [0], "MDSUi.hint": [0], "MDSUi.button": [0, 1], "MDSUi.menu_button": [0, 1],
	"MDSUi.title": [0], "MDSUi.field_line": [1, 3], "MDSUi.field_option": [1, 4],
	"MDSUi.weather_field": [1, 3], "MDSUi.parallax_field": [1, 3], "MDSUi.background_field": [1, 3],
	"MDSSidePanel.field": [1], "set_column_title": [1], "set_item_tooltip": [1],
	"add_button": [0], "add_cancel_button": [0], "status_message.emit": [0],
	"MDSL10n.t": [0], "MDSL10n.tf": [0], "MDSL10n.tn": [0, 1], "MDSL10n.tnf": [0, 1],
}
## In these scripts the class's own functions are called without its name.
const SELF_CLASS := {"ui/ui_util.gd": "MDSUi.", "ui/side_panel.gd": "MDSSidePanel.", "ui/l10n.gd": "MDSL10n."}
## Of the calls above, which argument is the context, and which the plural of the first.
const CONTEXT_ARG := {"MDSL10n.t": 1, "MDSL10n.tf": 2, "MDSL10n.tn": 3, "MDSL10n.tnf": 4}
const PLURAL_CALLS := ["MDSL10n.tn", "MDSL10n.tnf"]

## Mark a masked string in the code: private-use characters, which strip_edges() leaves alone
## (it strips control characters).
const _OPEN := ""
const _CLOSE := ""

static var _spec_re: RegEx
static var _extras: Dictionary = {}
static var _extras_loaded := false
static var _quote_re: RegEx
static var _token_re: RegEx
static var _prop_re: RegEx
static var _call_re: RegEx

# --- The whole addon ------------------------------------------------------------------------------

## Everything found in the addon: {messages: {key: message}, todo: [item]}. A message is
## {msgid, plural, context, refs, notes}; a to-do item {file, line, kind, text}. The messages
## are in the order of the files and lines they are at.
static func extract() -> Dictionary:
	var entries: Array = []
	var todo: Array = []
	for path in scripts(true):
		var rel := path.trim_prefix(ADDON + "/")
		var found := scan_source(FileAccess.get_file_as_string(path), rel, marked_only(rel))
		entries.append_array(found.entries)
		todo.append_array(found.todo)
	for table in _read_json(TABLES, []):
		if table.has("calls"):
			continue # helpers of a script: read as the script is scanned
		if table.has("msgid"):
			# A message that no call shows by name, given as it is.
			entries.append({"file": str(table.file), "line": int(table.get("line", 0)), "msgid": str(table.msgid), "plural": str(table.get("plural", "")), "context": str(table.get("context", ""))})
			continue
		var path := ADDON.path_join(str(table.file))
		if not FileAccess.file_exists(path):
			push_error("l10n: table file %s is missing" % path)
			continue
		var found := scan_table(FileAccess.get_file_as_string(path), str(table.file), table)
		entries.append_array(found)
	var notes: Dictionary = _read_json(NOTES, {})
	var messages: Dictionary = {}
	for e in entries:
		var key := message_key(e.msgid, e.context)
		if not messages.has(key):
			messages[key] = {"msgid": e.msgid, "plural": e.get("plural", ""), "context": e.context, "refs": [], "notes": []}
			if notes.has(e.msgid):
				messages[key].notes.append(str(notes[e.msgid]))
		var ref: String = "%s:%d" % [e.file, e.line] if e.line > 0 else str(e.file)
		if not ref in messages[key].refs:
			messages[key].refs.append(ref)
		if messages[key].plural.is_empty() and not e.get("plural", "").is_empty():
			messages[key].plural = e.plural
	return {"messages": messages, "todo": todo}

## The scripts of the panel, by path; with [param include_skipped] those of the folders in
## SKIP_DIRS too.
static func scripts(include_skipped := false) -> PackedStringArray:
	var out := PackedStringArray()
	_collect(ADDON, "", out, include_skipped)
	out.sort()
	return out

static func _collect(dir: String, rel: String, out: PackedStringArray, include_skipped := false) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if rel.is_empty() and d in SKIP_DIRS and not include_skipped:
			continue
		_collect(dir.path_join(d), rel.path_join(d), out, include_skipped)

## Whether only the statements marked "# l10n: text" of the script [param rel] are looked at:
## the scripts of the folders in SKIP_DIRS (the game's, the MCP server's) have tables of names
## the panel shows, and nothing else of theirs is the panel's text.
static func marked_only(rel: String) -> bool:
	return "/" in rel and rel.get_slice("/", 0) in SKIP_DIRS

static func message_key(msgid: String, context: String) -> String:
	return context + "\u0004" + msgid

# --- One script -----------------------------------------------------------------------------------

## What is shown as text in [param source] (the contents of the script [param file]):
## {entries: [{file, line, msgid, plural, context}], todo: [{file, line, kind, text}]}.
static func scan_source(source: String, file: String, only_marked := false) -> Dictionary:
	_prepare()
	var masked := _mask(source)
	var code: String = masked.code
	var lits: Array = masked.lits
	var skip: Dictionary = masked.skip
	var entries: Array = []
	var todo: Array = []
	var claimed: Dictionary = {}
	# Properties set to text.
	for m in ([] if only_marked else _prop_re.search_all(code)):
		var end := _statement_end(code, m.get_end())
		var found := _literals_of(code.substr(m.get_end(), end - m.get_end()), lits)
		for id: int in found.ids:
			claimed[id] = true
		_take(found, lits, file, "", "", skip, entries, todo, m.get_string(1) + " =")
	# Calls with text arguments.
	var extra := _extra_calls(file)
	for m in ([] if only_marked else _call_re.search_all(code)):
		var spec := _call_spec(m.get_string(1), file, extra)
		if spec.is_empty():
			continue
		var name: String = spec.name
		var args := _call_args(code, m.get_end() - 1)
		var context_at: int = CONTEXT_ARG.get(name, -1)
		var context := ""
		if context_at >= 0 and context_at < args.size():
			var ctx := _literals_of(args[context_at], lits)
			if ctx.ok and ctx.ids.size() == 1:
				context = str(lits[ctx.ids[0]].value)
		var plural := ""
		if name in PLURAL_CALLS and args.size() > 1:
			var pl := _literals_of(args[1], lits)
			if pl.ok and pl.ids.size() == 1:
				plural = str(lits[pl.ids[0]].value)
		for p in spec.places:
			var place := int(p)
			if name in PLURAL_CALLS and place == 1:
				continue
			if place >= args.size():
				continue
			var found := _literals_of(args[place], lits)
			for id: int in found.ids:
				claimed[id] = true
			_take(found, lits, file, context, plural, skip, entries, todo, name + "(#%d)" % place)
	# Statements marked "# l10n: text": every string in the statement below the comment is text
	# (a table of names, a list of labels), whatever shape the code gives it.
	for offset: int in masked.marks:
		var newline := code.find("\n", offset)
		if newline == -1:
			continue
		var start := newline + 1
		# Comments are gone from the masked code, but their lines are not: the statement is the
		# first thing after them.
		while start < code.length() and code[start] in " \t\n\r":
			start += 1
		var end := _statement_end(code, start)
		var pos := start
		while true:
			var open := code.find(_OPEN, pos)
			if open == -1 or open >= end:
				break
			var close := code.find(_CLOSE, open)
			if close == -1:
				break
			var id := int(code.substr(open + 1, close - open - 1))
			claimed[id] = true
			var lit: Dictionary = lits[id]
			# The ids, class names and paths that are in such a table are not text.
			if lit.kind == "string" and not skip.has(lit.line) and _has_letters(str(lit.value)) and _reads_like_text(str(lit.value)):
				entries.append({"file": file, "line": lit.line, "msgid": str(lit.value), "plural": "", "context": ""})
			pos = close + 1
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.line < b.line)
	return {"entries": entries, "todo": todo, "code": code, "lits": lits, "claimed": claimed, "skip": skip}

## Strings of [param source] that read like text for the user but that no sink claims, each with
## the call or the list it is in: [code]tools/l10n/extract.gd -- --unclaimed[/code] groups them,
## to find the helpers and tables that show text and are not known yet.
static func unclaimed(source: String, file: String) -> Array:
	var found := scan_source(source, file)
	var code: String = found.code
	var lits: Array = found.lits
	var out: Array = []
	for id in lits.size():
		var lit: Dictionary = lits[id]
		if found.claimed.has(id) or lit.kind != "string" or found.skip.has(lit.line):
			continue
		var text: String = lit.value
		if text.length() < 3 or not _has_letters(text) or not _reads_like_text(text):
			continue
		out.append({"line": lit.line, "text": text, "context": _context_at(code, code.find(_OPEN + str(id) + _CLOSE))})
	return out

## A phrase or a capitalized word, not an identifier, a path or a format.
static func _reads_like_text(text: String) -> bool:
	if text.length() < 2 or "://" in text:
		return false
	# A weather like "dust_storm(blows_toward=right), fog(density=0.35)" is code.
	if not _spec_re:
		_spec_re = RegEx.create_from_string("[a-z_]+\\([a-z_]+=")
	if _spec_re.search(text):
		return false
	if " " in text:
		return true
	if "/" in text or "_" in text or text.begins_with("%") or text.begins_with("."):
		return false
	var first := text[0]
	return first != first.to_lower()

## The call or list a string at [param at] of the masked [param code] is in.
static func _context_at(code: String, at: int) -> String:
	var depth := 0
	var i := at - 1
	while i >= 0:
		var c := code[i]
		if c == ")" or c == "]" or c == "}":
			depth += 1
		elif c == "(" or c == "[" or c == "{":
			if depth == 0:
				if c == "(":
					var j := i - 1
					while j >= 0 and (_is_identifier_char(code[j]) or code[j] == "."):
						j -= 1
					return code.substr(j + 1, i - j - 1) + "()"
				var line_start := code.rfind("\n", i) + 1
				return code.substr(line_start, i - line_start).strip_edges().right(48) + c
			depth -= 1
		elif c == "\n" and depth == 0:
			break
		i -= 1
	var start := code.rfind("\n", at) + 1
	return code.substr(start, at - start).strip_edges().right(28)

static func _take(found: Dictionary, lits: Array, file: String, context: String, plural: String, skip: Dictionary, entries: Array, todo: Array, via: String) -> void:
	for id: int in found.ids:
		var lit: Dictionary = lits[id]
		if lit.kind != "string" or skip.has(lit.line):
			continue
		var text: String = lit.value
		# A glyph, a bare format and an example path are not text; a string with a context is
		# translated on purpose, even a separator.
		if (not _has_letters(text) and context.is_empty()) or "://" in text:
			continue
		if found.ok:
			entries.append({"file": file, "line": lit.line, "msgid": text, "plural": plural, "context": context})
		else:
			todo.append({"file": file, "line": lit.line, "kind": "composed", "text": text, "via": via})

## The strings of a constant table: {file, const, index} from tables.json. Every string inside
## the constant's value is a message, or only the one at [code]index[/code] of each inner array
## when that is given. A [code]capitalize[/code] transform is applied to what is found.
static func scan_table(source: String, file: String, table: Dictionary) -> Array:
	_prepare()
	var masked := _mask(source)
	var code: String = masked.code
	var lits: Array = masked.lits
	var entries: Array = []
	var re := RegEx.create_from_string("(?<![A-Za-z0-9_])(?:const|static var|var)[ \\t]+" + str(table.const) + "(?![A-Za-z0-9_])[^=\\n]*=")
	var m := re.search(code)
	if not m:
		push_error("l10n: %s has no %s" % [file, table.const])
		return entries
	var end := _statement_end(code, m.get_end())
	var body := code.substr(m.get_end(), end - m.get_end())
	# Walks the value, counting where each string is among the elements of the bracket it is in.
	var index: int = int(table.get("index", -1))
	var places: Array[int] = []
	var current: Array = []
	var i := 0
	while i < body.length():
		var c := body[i]
		if c == _OPEN:
			var close := body.find(_CLOSE, i)
			if close == -1:
				break
			var id := int(body.substr(i + 1, close - i - 1))
			if index < 0 or (places.size() >= 2 and places[places.size() - 1] == index):
				current.append(id)
			i = close
		elif c == "[" or c == "{" or c == "(":
			places.append(0)
		elif c == "]" or c == "}" or c == ")":
			if not places.is_empty():
				places.pop_back()
		elif c == "," and not places.is_empty():
			places[places.size() - 1] += 1
		i += 1
	for id: int in current:
		var lit: Dictionary = lits[id]
		if lit.kind != "string" or not _has_letters(str(lit.value)):
			continue
		var text: String = lit.value
		if table.get("transform", "") == "capitalize":
			text = text.capitalize()
		entries.append({"file": file, "line": lit.line, "msgid": text, "plural": "", "context": str(table.get("context", ""))})
	return entries

# --- Looking at the code --------------------------------------------------------------------------

static func _prepare() -> void:
	if _quote_re:
		return
	_quote_re = RegEx.create_from_string("[\"'#]")
	_token_re = RegEx.create_from_string("^" + _OPEN + "(\\d+)" + _CLOSE + "$")
	_prop_re = RegEx.create_from_string("(?<![A-Za-z0-9_$.])(?:[A-Za-z0-9_]+\\.)*(" + "|".join(PROPERTIES) + ")[ \\t]*=(?!=)[ \\t]*")
	_call_re = RegEx.create_from_string("((?:[A-Za-z_][A-Za-z0-9_]*\\.)*[A-Za-z_][A-Za-z0-9_]*)\\(")

## How the call written as [param dotted] shows text: {name, places}, or {} when it does not.
## [param extra] holds the helpers of [param file] itself (from tables.json).
static func _call_spec(dotted: String, file: String, extra: Dictionary) -> Dictionary:
	var last := dotted.get_slice(".", dotted.count("."))
	if extra.has(last) and (dotted == last or dotted.begins_with("self.")):
		return {"name": "local:" + last, "places": extra[last]}
	if CALLS.has(dotted):
		return {"name": dotted, "places": CALLS[dotted]}
	for key: String in CALLS:
		if "." in key and dotted.ends_with("." + key):
			return {"name": key, "places": CALLS[key]}
	# Inside the class that makes them, MDSUi's and MDSL10n's functions are called bare.
	if SELF_CLASS.has(file) and dotted == last and CALLS.has(str(SELF_CLASS[file]) + last):
		var qualified := str(SELF_CLASS[file]) + last
		return {"name": qualified, "places": CALLS[qualified]}
	if CALLS.has(last) and not "." in last:
		return {"name": last, "places": CALLS[last]}
	return {}

## The helpers a script defines for itself that show an argument as text, from tables.json:
## {call name: places of the text arguments}.
static func _extra_calls(file: String) -> Dictionary:
	if not _extras_loaded:
		_extras_loaded = true
		for table in _read_json(TABLES, []):
			if table.has("calls"):
				_extras[str(table.file)] = table.calls
	return _extras.get(file, {})

## Masks strings and comments: {code, lits, skip}. In [code] every string is a token
## (\u0001 index \u0002), every comment is gone; [code]lits[/code] holds the strings as
## {value, line, kind} ("string", or "name" for &"x" and ^"x"); [code]skip[/code] the lines
## marked "l10n: skip".
static func _mask(source: String) -> Dictionary:
	var out := PackedStringArray()
	var lits: Array = []
	var skip: Dictionary = {}
	var marks: Array[int] = []
	var line := 1
	var i := 0
	var n := source.length()
	while i < n:
		var m := _quote_re.search(source, i)
		if not m:
			out.append(source.substr(i))
			break
		var at := m.get_start()
		var chunk := source.substr(i, at - i)
		line += chunk.count("\n")
		var c := source[at]
		if c == "#":
			out.append(chunk)
			var eol := source.find("\n", at)
			if eol == -1:
				eol = n
			if "l10n: skip" in source.substr(at, eol - at):
				skip[line] = true
				var line_start := source.rfind("\n", at) + 1
				if source.substr(line_start, at - line_start).strip_edges().is_empty():
					skip[line + 1] = true
			if "l10n: text" in source.substr(at, eol - at):
				# On a line of its own: the statement below holds text.
				var own_start := source.rfind("\n", at) + 1
				if source.substr(own_start, at - own_start).strip_edges().is_empty():
					marks.append("".join(out).length())
			i = eol
			continue
		# A string. &"x" and ^"x" are names, r"x" is raw.
		var kind := "string"
		var raw := false
		if chunk.length() > 0:
			var last := chunk[chunk.length() - 1]
			if last == "&" or last == "^":
				kind = "name"
				chunk = chunk.left(chunk.length() - 1)
			elif last == "r" and (at < 2 or not _is_identifier_char(source[at - 2])):
				raw = true
				chunk = chunk.left(chunk.length() - 1)
		out.append(chunk)
		var triple := source.substr(at, 3) == c.repeat(3)
		var j := at + (3 if triple else 1)
		var value := PackedStringArray()
		var seg := j
		while j < n:
			var ch := source[j]
			if ch == "\\" and not raw and j + 1 < n:
				value.append(source.substr(seg, j - seg))
				var e := source[j + 1]
				j += 2
				match e:
					"n": value.append("\n")
					"t": value.append("\t")
					"r": value.append("\r")
					"u", "U":
						var digits := 4 if e == "u" else 6
						value.append(char(source.substr(j, digits).hex_to_int()))
						j += digits
					_: value.append(e)
				seg = j
			elif ch == c and (not triple or source.substr(j, 3) == c.repeat(3)):
				break
			else:
				j += 1
		value.append(source.substr(seg, j - seg))
		var raw_text := source.substr(at, j + (3 if triple else 1) - at)
		lits.append({"value": "".join(value), "line": line, "kind": kind})
		out.append(_OPEN + str(lits.size() - 1) + _CLOSE)
		line += raw_text.count("\n")
		i = j + (3 if triple else 1)
	return {"code": "".join(out), "lits": lits, "skip": skip, "marks": marks}

static func _is_identifier_char(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")

## Where the statement that starts at [param start] ends: its line, unless a bracket is open,
## or the bracket that closes the call it is in.
static func _statement_end(code: String, start: int) -> int:
	var depth := 0
	var i := start
	var n := code.length()
	while i < n:
		var c := code[i]
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			if depth == 0:
				return i
			depth -= 1
		elif c == "\n" and depth == 0:
			return i
		i += 1
	return n

## The arguments of the call whose "(" is at [param open], as text.
static func _call_args(code: String, open: int) -> Array[String]:
	var args: Array[String] = []
	var depth := 0
	var i := open + 1
	var from := i
	var n := code.length()
	while i < n:
		var c := code[i]
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			if depth == 0:
				var last := code.substr(from, i - from).strip_edges()
				if not last.is_empty() or not args.is_empty():
					args.append(last)
				return args
			depth -= 1
		elif c == "," and depth == 0:
			args.append(code.substr(from, i - from).strip_edges())
			from = i + 1
		i += 1
	return args

## The strings an expression is made of when it is only a string, or a choice between strings
## ("A" if x else "B"): {ok: true, ids}. Any other expression (a % or a + on a string) is
## {ok: false, ids: [the strings in it]}.
static func _literals_of(expr: String, lits: Array) -> Dictionary:
	expr = expr.strip_edges()
	while expr.begins_with("(") and expr.ends_with(")") and _balanced(expr.substr(1, expr.length() - 2)):
		expr = expr.substr(1, expr.length() - 2).strip_edges()
	var m := _token_re.search(expr)
	if m:
		return {"ok": true, "ids": [int(m.get_string(1))]}
	var parts := _split_ternary(expr)
	if not parts.is_empty():
		var a := _literals_of(parts[0], lits)
		var b := _literals_of(parts[2], lits)
		if a.ok and b.ok:
			return {"ok": true, "ids": a.ids + b.ids}
	var ids: Array = []
	var from := 0
	while true:
		var open := expr.find(_OPEN, from)
		if open == -1:
			break
		var close := expr.find(_CLOSE, open)
		if close == -1:
			break
		ids.append(int(expr.substr(open + 1, close - open - 1)))
		from = close + 1
	return {"ok": false, "ids": ids}

static func _balanced(text: String) -> bool:
	var depth := 0
	for c in text:
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
			if depth < 0:
				return false
	return depth == 0

## [value if condition else other] as [value, condition, other], or [] when it is not one.
static func _split_ternary(expr: String) -> Array[String]:
	var depth := 0
	var if_at := -1
	var else_at := -1
	var n := expr.length()
	var i := 0
	while i < n:
		var c := expr[i]
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		elif depth == 0 and c == " ":
			if if_at == -1 and expr.substr(i, 4) == " if ":
				if_at = i
			elif if_at != -1 and else_at == -1 and expr.substr(i, 6) == " else ":
				else_at = i
		i += 1
	var out: Array[String] = []
	if if_at != -1 and else_at != -1:
		out.append(expr.substr(0, if_at))
		out.append(expr.substr(if_at + 4, else_at - if_at - 4))
		out.append(expr.substr(else_at + 6))
	return out

## Whether there is a word in [param text]: a glyph like "⧉", a number or a bare "%d" is not text
## to translate.
static func _has_letters(text: String) -> bool:
	var bare := RegEx.create_from_string("%[-+ #0-9.*]*[sdfoxXcevV%]|\\{[A-Za-z_0-9]*\\}").sub(text, "", true)
	for c in bare:
		if c.to_lower() != c.to_upper():
			return true
	return false

static func _read_json(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed != null else fallback

# --- The catalog file -----------------------------------------------------------------------------

## The messages as the text of a .pot file.
static func pot_text(messages: Dictionary) -> String:
	var lines := PackedStringArray([
		"# Texts of the Metroidvania Developer System panel.",
		"# Made by tools/l10n/extract.gd from the scripts; do not edit it by hand.",
		"msgid \"\"",
		"msgstr \"\"",
		"\"Project-Id-Version: Metroidvania Developer System\\n\"",
		"\"Report-Msgid-Bugs-To: https://github.com/arunsrajan/MetroidvaniaDeveloperSystem/issues\\n\"",
		"\"MIME-Version: 1.0\\n\"",
		"\"Content-Type: text/plain; charset=UTF-8\\n\"",
		"\"Content-Transfer-Encoding: 8bit\\n\"",
		"",
	])
	for key in messages:
		var msg: Dictionary = messages[key]
		for note in msg.notes:
			lines.append("#. " + str(note))
		# The files, not the lines: a line number would make the template out of date whenever
		# code above a string moves.
		var files: Array = []
		for ref in msg.refs:
			var file_name: String = str(ref).rsplit(":", true, 1)[0]
			if not file_name in files:
				files.append(file_name)
		for file_name in files.slice(0, 3):
			lines.append("#: " + str(file_name))
		if files.size() > 3:
			lines.append("# and %d more files" % (files.size() - 3))
		if not msg.context.is_empty():
			lines.append("msgctxt " + quote(msg.context))
		lines.append("msgid " + quote(msg.msgid))
		if msg.plural.is_empty():
			lines.append("msgstr \"\"")
		else:
			lines.append("msgid_plural " + quote(msg.plural))
			lines.append("msgstr[0] \"\"")
			lines.append("msgstr[1] \"\"")
		lines.append("")
	return "\n".join(lines)

## [param text] as a quoted string of a .po file.
static func quote(text: String) -> String:
	return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r") + "\""
