extends "res://tests/test_case.gd"
## The panel's languages: the list and the switch (ui/l10n.gd), the catalogs (locale/), and the
## tools that make them (tools/l10n/):
## - the list has 50 languages, with Russian, Hindi and Tamil, and each is one Godot knows;
## - the extractor finds the text in the code, and leaves out what is data;
## - mds.pot is current, and every catalog loads and breaks nothing: no translation loses a
##   placeholder, a BBCode tag or a mnemonic;
## - Auto finds the nearest language; a translation with other placeholders is not used;
##   plural forms follow the language's rules;
## - after a switch the controls show the new language and keep their English text, which the
##   other tests read; the side panel's sections are still found by their English title;
## - the dialogs and panels show text the catalog has.

const Extractor := preload("res://tools/l10n/extractor.gd")
const Validator := preload("res://tools/l10n/validator.gd")
const DIR := TMP + "/l10n"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_list()
	_extractor()
	_catalogs()
	_matching()
	_formats()
	await _switch()
	await _walk()
	_end()

# --- The list -------------------------------------------------------------------------------------

func _list() -> void:
	var langs := MDSL10n.languages()
	check(langs.size() == 50, "the list has 50 languages (%d)" % langs.size())
	var seen := {}
	var rtl := []
	var sources := 0
	for l in langs:
		check(not seen.has(l.code), "%s is in the list once" % l.code)
		seen[l.code] = true
		check(not str(l.native).is_empty() and not str(l.english).is_empty(), "%s has its names" % l.code)
		check(l.status in ["source", "beta", "reviewed"], "%s has a status (%s)" % [l.code, l.status])
		sources += 1 if l.status == "source" else 0
		if l.rtl:
			rtl.append(l.code)
		check(not TranslationServer.get_language_name(str(l.code).get_slice("_", 0)).is_empty(), "%s is a language Godot knows" % l.code)
		check(not TranslationServer.get_plural_rules(l.code).is_empty(), "%s has plural rules" % l.code)
	check(langs[0].code == "en" and sources == 1, "English comes first and is the only source")
	for code in ["ru", "hi", "ta"]:
		check(seen.has(code), "%s, which was asked for, is in the list" % code)
	rtl.sort()
	check(rtl == ["ar", "fa", "he", "ur"], "the languages written right to left are ar, fa, he, ur (%s)" % [rtl])
	for code in Validator.SCRIPTS:
		check(seen.has(code), "the script table's %s is a language of the list" % code)
	check(MDSL10n.menu_label("en") == "English" and MDSL10n.menu_label("ru") == "Русский — Russian (beta)", "the menu says a language in its own words and in English: %s" % MDSL10n.menu_label("ru"))

# --- The extractor --------------------------------------------------------------------------------

func _texts(source: String, file := "ui/test.gd") -> Array:
	var found := Extractor.scan_source(source, file)
	var out := []
	for e in found.entries:
		out.append(e.msgid)
	return out

func _extractor() -> void:
	check(_texts('b.text = "Save"\n') == ["Save"], "a property set to a string is a message")
	check(_texts('b.text = "A" if x else "B"\n') == ["A", "B"], "a choice between two strings gives both")
	var composed := Extractor.scan_source('b.text = "Rooms: %d" % n\nb.text = "a" + x\n', "ui/test.gd")
	check(composed.entries.is_empty() and composed.todo.size() == 2, "a string put together goes on the to-do list, not into the catalog")
	check(_texts('x = MDSUi.button("Open", "Open the file")\n') == ["Open", "Open the file"], "the helpers' text arguments are messages")
	check(_texts('p.add_item("Rescan", ID)\n') == ["Rescan"], "a menu item is a message")
	check(_texts('label("Hello world")\n', "ui/ui_util.gd") == ["Hello world"], "inside ui_util.gd the helpers are called bare")
	check(_texts('b.text = "Secret" # l10n: skip\n') == [], "a line marked skip is left out")
	check(_texts('# l10n: skip\nb.text = "Secret"\n') == [], "so is the line after a comment that says skip")
	check(_texts('# l10n: text\nconst N := ["Alpha", "beta_id", "Gamma ray", "res://x/y.tscn"]\n') == ["Alpha", "Gamma ray"], "a text marker claims the strings that read like text")
	check(_texts('b.text = "Use # to comment" # a comment\n') == ["Use # to comment"], "a # inside a string does not start a comment")
	check(_texts('b.text = "Line\\nbreak"\n') == ["Line\nbreak"], "an escape is decoded")
	check(_texts('b.text = "Go \\u2192 there"\n') == ["Go → there"], "a \\u escape is decoded")
	check(_texts('b.text = "⧉"\nb.text = "%d"\ne.placeholder_text = "res://rooms"\n') == [], "a glyph, a bare format and an example path are not text")
	check(_texts('var d := {"text": "x"}\n') == [], "a dictionary key is not a sink")
	check(_texts('func f():\n\tb.text = "Save"\n\tt.name = &"NotText"\n') == ["Save"], "a StringName is not text")
	var marked := Extractor.scan_source('MDSL10n.t(", ", "list separator")\nMDSL10n.tn("%d room", "%d rooms", n)\n', "ui/test.gd")
	check(marked.entries.size() == 2 and marked.entries[0].context == "list separator" and marked.entries[1].plural == "%d rooms", "MDSL10n calls carry their context and their plural")
	check(Extractor.quote("a \"b\"\n\\") == "\"a \\\"b\\\"\\n\\\\\"", "text is quoted for a .po file")

# --- The catalogs ---------------------------------------------------------------------------------

func _catalogs() -> void:
	var messages: Dictionary = Extractor.extract().messages
	check(messages.size() > 500, "the catalog holds the panel's text (%d messages)" % messages.size())
	check(FileAccess.get_file_as_string(Extractor.POT) == Extractor.pot_text(messages), "locale/mds.pot is current (tools/l10n/extract.gd makes it)")
	var known := MDSL10n.languages().map(func(l: Dictionary) -> String: return l.code)
	for f in DirAccess.get_files_at(MDSL10n.LOCALE_DIR):
		if not f.ends_with(".po"):
			continue
		var code := f.trim_suffix(".po")
		check(code in known, "%s is a language of the list" % f)
		var t := ResourceLoader.load(MDSL10n.LOCALE_DIR.path_join(f), "Translation", ResourceLoader.CACHE_MODE_IGNORE) as Translation
		check(t != null and TranslationServer.compare_locales(t.locale, code) == 10, "%s loads and its Language header is %s (%s)" % [f, code, t.locale if t else "?"])
		if not t:
			continue
		var have := 0
		var errors := 0
		for key in messages:
			var m: Dictionary = messages[key]
			var text := str(t.get_message(m.msgid, m.context))
			if text.is_empty():
				continue
			have += 1
			var found := Validator.problems(code, m.msgid, text)
			if not found.errors.is_empty():
				errors += 1
				check(false, "%s: %s: %s" % [code, Extractor.quote(m.msgid).left(50), "; ".join(found.errors)])
		check(errors == 0, "%s: no translation loses a placeholder, a tag or a mnemonic (%d of %d translated)" % [code, have, messages.size()])
		print("  %s: %d of %d messages translated (%.0f%%)" % [code, have, messages.size(), 100.0 * have / messages.size()])

# --- Choosing a language --------------------------------------------------------------------------

## Writes a catalog of [param code] into the test's folder: [param entries] are [msgid, msgstr],
## [context, msgid, msgstr], or [msgid, plural, [forms]].
func _po(code: String, entries: Array, plural_rule := "") -> void:
	var lines := PackedStringArray(["msgid \"\"", "msgstr \"\"", "\"Language: %s\\n\"" % code, "\"Content-Type: text/plain; charset=UTF-8\\n\""])
	if not plural_rule.is_empty():
		lines.append("\"Plural-Forms: %s\\n\"" % plural_rule)
	lines.append("")
	for e: Array in entries:
		if e.size() == 3 and e[2] is Array:
			lines.append("msgid " + Extractor.quote(e[0]))
			lines.append("msgid_plural " + Extractor.quote(e[1]))
			for i in e[2].size():
				lines.append("msgstr[%d] %s" % [i, Extractor.quote(e[2][i])])
		elif e.size() == 3:
			lines.append("msgctxt " + Extractor.quote(e[0]))
			lines.append("msgid " + Extractor.quote(e[1]))
			lines.append("msgstr " + Extractor.quote(e[2]))
		else:
			lines.append("msgid " + Extractor.quote(e[0]))
			lines.append("msgstr " + Extractor.quote(e[1]))
		lines.append("")
	var f := FileAccess.open(DIR + "/%s.po" % code, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()

func _matching() -> void:
	for code in ["ru", "pt_BR", "zh_CN", "he", "nb", "fil", "id", "hi", "ta", "ar"]:
		_po(code, [["Save", "[%s]" % code]])
	MDSL10n.locale_dir = DIR
	var cases := [["ru_RU", "ru"], ["ru", "ru"], ["pt_PT", "pt_BR"], ["pt-BR", "pt_BR"], ["zh_TW", "zh_CN"], ["zh_HK", "zh_CN"], ["zh_Hans", "zh_CN"],
		["iw", "he"], ["he", "he"], ["no", "nb"], ["nb_NO", "nb"], ["nn", "nb"], ["tl", "fil"], ["fil", "fil"], ["in", "id"], ["hi_IN", "hi"],
		["ta_IN", "ta"], ["ar_EG", "ar"], ["en_GB", "en"], ["en_US", "en"], ["xx", "en"], ["de", "en"]]
	for c: Array in cases:
		check(MDSL10n.best_match(c[0]) == c[1], "Auto: the editor's %s is shown as %s (%s)" % [c[0], c[1], MDSL10n.best_match(c[0])])
	_po("zh_TW", [["Save", "[zh_TW]"]])
	check(MDSL10n.best_match("zh_HK") == "zh_TW" and MDSL10n.best_match("zh_Hant") == "zh_TW" and MDSL10n.best_match("zh_CN") == "zh_CN", "Traditional Chinese goes to its own catalog when there is one")
	check("ru" in MDSL10n.available().map(func(l: Dictionary) -> String: return l.code) and not "fr" in MDSL10n.available().map(func(l: Dictionary) -> String: return l.code), "the menu offers the languages that have a catalog")
	check(MDSL10n.resolve("fr") == "en" and MDSL10n.resolve("ru") == "ru", "a choice without a catalog comes to English")

func _formats() -> void:
	var rule := "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);"
	_po("ru", [["Save", "Сохранить"], ["Rooms: %d", "Комнат: %s"], ["{a} to {b}", "{b} <- {a}"], ["list separator", ", ", "; "], ["%d room", "%d rooms", ["%d комната", "%d комнаты", "%d комнат"]]], rule)
	check(MDSL10n.t("Save") == "Save" and MDSL10n.tf("Rooms: %d", [3]) == "Rooms: 3" and MDSL10n.tnf("%d room", "%d rooms", 5) == "5 rooms", "before setup everything is English")
	MDSL10n.setup()
	check(MDSL10n.is_active() and MDSL10n.current() == "en", "setup shows English on an editor with no catalog for its language (%s)" % MDSL10n.current())
	MDSL10n.set_language("ru")
	check(MDSL10n.current() == "ru" and MDSL10n.get_language() == "ru", "set_language(ru)")
	check(MDSL10n.t("Save") == "Сохранить" and MDSL10n.t("Missing message") == "Missing message", "t translates what the catalog has, and gives the rest as it is")
	check(MDSL10n.tf("Rooms: %d", [3]) == "Rooms: 3", "tf does not use a translation whose placeholder is another (%s for %d)")
	check(MDSL10n.tf("{a} to {b}", {"a": 1, "b": 2}) == "2 <- 1", "tf fills {fields} wherever the translation puts them")
	var forms := []
	for n in [1, 2, 5, 11, 21, 22]:
		forms.append(MDSL10n.tnf("%d room", "%d rooms", n))
	check(forms == ["1 комната", "2 комнаты", "5 комнат", "11 комнат", "21 комната", "22 комнаты"], "plural forms follow the Russian rules (%s)" % [forms])
	check(MDSL10n.join([1, 2, 3]) == "1; 2; 3", "a list is joined with the language's separator")
	check(MDSL10n.signature("%d of %s, {x}") == "ds|x" and MDSL10n.signature("100%% of it") == "", "the signature tells what a text takes")
	var rev := MDSL10n.revision
	MDSL10n.set_language("en")
	check(MDSL10n.t("Save") == "Save" and MDSL10n.revision > rev, "back to English, and the revision counts the change")
	var heard := []
	var listener := func(code: String) -> void: heard.append(code)
	MDSL10n.events.language_changed.connect(listener)
	MDSL10n.set_language("ru")
	check(heard == ["ru"], "a change is announced once (%s)" % [heard])
	MDSL10n.shutdown()
	check(not MDSL10n.events.language_changed.is_connected(listener) and not MDSL10n.is_active() and MDSL10n.t("Save") == "Save", "shutdown lets go of the listeners and the domain")

# --- The switch -----------------------------------------------------------------------------------

func _switch() -> void:
	_po("ru", [["Save", "Сохранить"], ["World", "Мир"], ["Save the world", "Сохранить мир"]])
	MDSL10n.locale_dir = DIR
	MDSL10n.setup()
	var holder := Control.new()
	add_child(holder)
	var button := Button.new()
	button.text = "Save"
	holder.add_child(button)
	var picker := OptionButton.new()
	picker.add_item("Save")
	MDSL10n.raw(picker)
	holder.add_child(picker)
	var side := MDSSidePanel.new()
	holder.add_child(side)
	var content := side.add_section("World")
	MDSL10n.apply(holder)
	check(button.get_translation_domain() == MDSL10n.DOMAIN, "a control under an applied root is in the panel's domain")
	MDSL10n.set_language("ru")
	MDSL10n.refresh(holder)
	side.refresh_language()
	await get_tree().process_frame
	check(button.atr("Save") == "Сохранить", "the button is shown in Russian (%s)" % button.atr("Save"))
	check(button.text == "Save", "and keeps its English text, which the tests and the code read")
	check(picker.atr("Save") == "Save" and picker.get_item_text(0) == "Save", "a list marked raw stays English")
	check(side.get_section("World") == content, "the side panel's sections are still found by their English title")
	var header: Button = side._sections["World"][0]
	check(header.text == "▾ Мир", "the section's title is in Russian (%s)" % header.text)
	header.button_pressed = false
	check(header.text == "▸ Мир", "also when the section is closed (%s)" % header.text)
	MDSL10n.set_language("en")
	side.refresh_language()
	check(header.text == "▸ World" and button.atr("Save") == "Save", "and English again")
	MDSL10n.set_pseudo(true)
	check(MDSL10n.t("Save") != "Save", "pseudolocalization shows what is translated and what is not (%s)" % MDSL10n.t("Save"))
	MDSL10n.set_pseudo(false)
	holder.queue_free()
	await get_tree().process_frame

# --- The text of the panels ------------------------------------------------------------------------

## The texts [param node] and what is under it show.
func _shown(node: Node, out: Dictionary) -> void:
	if node is Button:
		out[(node as Button).text] = true
	if node is Label:
		out[(node as Label).text] = true
	if node is LineEdit:
		out[(node as LineEdit).placeholder_text] = true
	if node is RichTextLabel:
		out[(node as RichTextLabel).text] = true
	if node is Control:
		out[(node as Control).tooltip_text] = true
	if node is PopupMenu:
		for i in (node as PopupMenu).item_count:
			out[(node as PopupMenu).get_item_text(i)] = true
	if node is TabContainer:
		for i in (node as TabContainer).get_tab_count():
			out[(node as TabContainer).get_tab_title(i)] = true
	if node is AcceptDialog:
		out[(node as AcceptDialog).title] = true
		out[(node as AcceptDialog).dialog_text] = true
	for c in node.get_children(true):
		_shown(c, out)

func _walk() -> void:
	var messages: Dictionary = Extractor.extract().messages
	var catalog := {}
	for key in messages:
		catalog[messages[key].msgid] = true
	var seen := 0
	var missing: Array = []
	var shown := {}
	var holder := Control.new()
	add_child(holder)
	for node: Node in [MDSMergeRoomsDialog.new(), MDSAreaGenerateDialog.new(), MDSTraceDialog.new(), MDSFightPanel.new(), MDSSidePanel.new()]:
		holder.add_child(node)
	await get_tree().process_frame
	_shown(holder, shown)
	for shown_text: String in shown:
		# A section's header is its title after a glyph; ids (recipe names...) are not text.
		var text := shown_text.substr(2) if shown_text.begins_with("▾ ") or shown_text.begins_with("▸ ") else shown_text
		if text.is_empty() or not Extractor._has_letters(text) or not Extractor._reads_like_text(text):
			continue
		seen += 1
		if not catalog.has(text):
			missing.append(text)
	var covered := 1.0 - float(missing.size()) / maxi(1, seen)
	print("  the dialogs and panels show %d texts; %d are in the catalog (%.0f%%)" % [seen, seen - missing.size(), 100.0 * covered])
	for text in missing.slice(0, 70):
		print("    not in the catalog: ", Extractor.quote(str(text)).left(100))
	# The rest is put together in code (the Fight editor's "Add a MDSMoveDash"), or comes from tables
	# of core/ and the engine's own controls: see the to-do list of tools/l10n/extract.gd.
	check(seen > 50 and covered >= 0.6, "the panels show text the catalog has (%d of %d)" % [seen - missing.size(), seen])
	holder.queue_free()
	await get_tree().process_frame

func _end() -> void:
	MDSL10n.set_pseudo(false)
	MDSL10n.set_language(MDSL10n.AUTO)
	MDSL10n.shutdown()
	MDSL10n.locale_dir = MDSL10n.LOCALE_DIR
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
