@tool
class_name MDSL10n
extends RefCounted
## The language of the MetDevSys panel (for translators: locale/README.md).
##
## The panel's text is English in its nodes. Godot translates it as it is shown, through a
## [TranslationDomain] that only this plugin uses, so the language is the plugin's own choice,
## whatever the editor's language is: [method apply] puts a control tree in that domain,
## [method set_language] switches it and [method refresh] makes a tree translate again. Text
## composed in code (Godot cannot translate a sentence put together with %) goes through
## [method t], [method tf], [method tn] and [method join]; so does text drawn on a canvas.
##
## Only UI code calls these. [code]core/[/code], [code]mcp/[/code] and the exporters stay
## English, so what MCP tools return and what the tests read is the same in every language.
## Before [method setup] (in a game, in the MCP server, in the tests) every function gives the
## English text.

## The domain's name: the plugin's path, as Godot's plugin tutorial advises.
const DOMAIN := &"addons/MetroidvaniaDeveloperSystem"
const LOCALE_DIR := "res://addons/MetroidvaniaDeveloperSystem/locale"
## The EditorSetting that keeps the choice, per user and for every project.
const SETTING := "metroidvania_developer_system/language"
## The choice that follows the editor's language.
const AUTO := "auto"
## The language of the text in the code.
const SOURCE := "en"
## Languages of the list that Godot does not count as the same as the code that names them here
## (Tagalog is Filipino; Nynorsk is read as Norwegian Bokmål).
const _ALIASES := {"tl": "fil", "nn": "nb"}
## Said after a language no native speaker has looked over. English on purpose: the menu has to
## read in every language.
const BETA := " (beta)"

## Code, native name, English name, written right to left, status ("source", "beta" or
## "reviewed"). In the order of the ranking they were picked by.
const _TABLE := [
	["en", "English", "English", false, "source"],
	["zh_CN", "简体中文", "Chinese (Simplified)", false, "beta"],
	["hi", "हिन्दी", "Hindi", false, "beta"],
	["es", "Español", "Spanish", false, "beta"],
	["ar", "العربية", "Arabic", true, "beta"],
	["fr", "Français", "French", false, "beta"],
	["bn", "বাংলা", "Bengali", false, "beta"],
	["pt_BR", "Português (Brasil)", "Portuguese (Brazil)", false, "beta"],
	["id", "Bahasa Indonesia", "Indonesian", false, "beta"],
	["ur", "اردو", "Urdu", true, "beta"],
	["ru", "Русский", "Russian", false, "beta"],
	["de", "Deutsch", "German", false, "beta"],
	["ja", "日本語", "Japanese", false, "beta"],
	["mr", "मराठी", "Marathi", false, "beta"],
	["vi", "Tiếng Việt", "Vietnamese", false, "beta"],
	["te", "తెలుగు", "Telugu", false, "beta"],
	["sw", "Kiswahili", "Swahili", false, "beta"],
	["ha", "Hausa", "Hausa", false, "beta"],
	["tr", "Türkçe", "Turkish", false, "beta"],
	["pa", "ਪੰਜਾਬੀ", "Punjabi", false, "beta"],
	["fil", "Filipino", "Filipino", false, "beta"],
	["ta", "தமிழ்", "Tamil", false, "beta"],
	["zh_TW", "繁體中文", "Chinese (Traditional)", false, "beta"],
	["fa", "فارسی", "Persian", true, "beta"],
	["ko", "한국어", "Korean", false, "beta"],
	["am", "አማርኛ", "Amharic", false, "beta"],
	["th", "ไทย", "Thai", false, "beta"],
	["jv", "Basa Jawa", "Javanese", false, "beta"],
	["it", "Italiano", "Italian", false, "beta"],
	["gu", "ગુજરાતી", "Gujarati", false, "beta"],
	["kn", "ಕನ್ನಡ", "Kannada", false, "beta"],
	["yo", "Yorùbá", "Yoruba", false, "beta"],
	["pl", "Polski", "Polish", false, "beta"],
	["uk", "Українська", "Ukrainian", false, "beta"],
	["nl", "Nederlands", "Dutch", false, "beta"],
	["ro", "Română", "Romanian", false, "beta"],
	["ml", "മലയാളം", "Malayalam", false, "beta"],
	["or", "ଓଡ଼ିଆ", "Odia", false, "beta"],
	["my", "မြန်မာ", "Burmese", false, "beta"],
	["ne", "नेपाली", "Nepali", false, "beta"],
	["ms", "Bahasa Melayu", "Malay", false, "beta"],
	["cs", "Čeština", "Czech", false, "beta"],
	["sv", "Svenska", "Swedish", false, "beta"],
	["el", "Ελληνικά", "Greek", false, "beta"],
	["hu", "Magyar", "Hungarian", false, "beta"],
	["he", "עברית", "Hebrew", true, "beta"],
	["bg", "Български", "Bulgarian", false, "beta"],
	["fi", "Suomi", "Finnish", false, "beta"],
	["da", "Dansk", "Danish", false, "beta"],
	["nb", "Norsk bokmål", "Norwegian", false, "beta"],
]

## Tells the panels the language changed.
class Events extends RefCounted:
	@warning_ignore("unused_signal")
	signal language_changed(code: String)

static var events := Events.new()
## Counts the changes of language, so a panel that was hidden for one can catch up when it is
## shown.
static var revision := 0
## Where the catalogs are (the tests point it elsewhere).
static var locale_dir := LOCALE_DIR

static var _languages: Array[Dictionary] = []
static var _domain: TranslationDomain
static var _translation: Translation
## The language the domain shows now.
static var _shown := SOURCE
## The choice, where there is no editor to keep it.
static var _choice := AUTO
## The language asked for on the command line for this session only ([code]godot -e --
## --mds-language=ru[/code]): it stands in for the saved choice until a language is picked from the
## menu, and the saved choice is never changed by it.
static var _session := ""
## The choice the domain was last set from (to notice a change made in Editor Settings).
static var _applied := ""
static var _pseudo := false
static var _signatures: Dictionary = {}
static var _spec_re: RegEx
static var _field_re: RegEx

# --- Setting up ----------------------------------------------------------------------------------

## Makes the domain and shows the language that was chosen. The plugin calls it as it enters
## the tree.
static func setup() -> void:
	if _domain:
		return
	_domain = TranslationServer.get_or_add_domain(DOMAIN)
	_domain.pseudolocalization_enabled = _pseudo
	_register_setting()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mds-language="):
			var wanted := arg.get_slice("=", 1)
			if wanted == AUTO or not language_info(wanted).is_empty():
				_session = wanted
	_applied = get_language()
	_show(resolve(_applied))

## Takes the domain away, as the plugin leaves the tree. Whatever still listens to
## [signal Events.language_changed] is let go: a connection left to a script that is freed
## first crashes Godot as it quits (static variables outlive scripts).
static func shutdown() -> void:
	for connection in events.language_changed.get_connections():
		events.language_changed.disconnect(connection.callable)
	if not _domain:
		return
	TranslationServer.remove_domain(DOMAIN)
	_domain = null
	_translation = null
	_shown = SOURCE
	_session = ""

static func is_active() -> bool:
	return _domain != null

## Puts [param root] and everything under it in the plugin's domain. Controls made by the panels
## are under the dock and inherit it; this is for a tree that hangs elsewhere (the floating
## window, a dialog the editor parents, a control of an inspector plugin).
static func apply(root: Node) -> void:
	if not _domain or not is_instance_valid(root):
		return
	root.set_translation_domain(DOMAIN)
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	# The panel's layout is not mirrored for right-to-left languages: the map and its tools
	# stay where they are, only the text runs the other way.
	if root is Control:
		(root as Control).layout_direction = Control.LAYOUT_DIRECTION_LTR

## Makes the controls under [param root] translate their text again. Godot does not do it when
## the language changes.
static func refresh(root: Node) -> void:
	if is_instance_valid(root):
		root.propagate_notification(Node.NOTIFICATION_TRANSLATION_CHANGED)

## Keeps [param node] in English: a list of room, area or world names, which belong to the user's
## data and must not be translated if one happens to read like a word of the panel.
static func raw(node: Node) -> void:
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if node is OptionButton:
		(node as OptionButton).get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	elif node is MenuButton:
		(node as MenuButton).get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

# --- Languages -----------------------------------------------------------------------------------

## Every language of the list, as {code, native, english, rtl, status}.
static func languages() -> Array[Dictionary]:
	if _languages.is_empty():
		for row in _TABLE:
			_languages.append({"code": row[0], "native": row[1], "english": row[2], "rtl": row[3], "status": row[4]})
	return _languages

static func language_info(code: String) -> Dictionary:
	for l in languages():
		if l.code == code:
			return l
	return {}

## True when [param code] can be shown: English, or a language whose catalog is in the addon.
static func has_catalog(code: String) -> bool:
	return code == SOURCE or FileAccess.file_exists(_catalog_path(code))

## The languages the menu offers (those that can be shown), by their English names.
static func available() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in languages():
		if has_catalog(l.code):
			out.append(l)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.english < b.english)
	return out

## What the menu says of a language: "Русский — Russian", and " (beta)" after one that no
## native speaker has looked over. Always the same text, so it reads in every language.
static func menu_label(code: String) -> String:
	var l := language_info(code)
	if l.is_empty():
		return code
	var text: String = l.native if l.native == l.english else "%s — %s" % [l.native, l.english]
	return text + BETA if l.status == "beta" else text

## The language as a few letters for a button: "RU", "PT-BR".
static func short_name(code: String) -> String:
	return code.replace("_", "-").to_upper()

static func is_rtl(code: String) -> bool:
	return bool(language_info(code).get("rtl", false))

## The language of the list nearest to [param locale] ("pt_PT" gives Portuguese (Brazil), "iw"
## Hebrew), or English when none is near.
static func best_match(locale: String) -> String:
	var wanted := locale.replace("-", "_")
	var language := wanted.get_slice("_", 0)
	if _ALIASES.has(language):
		wanted = _ALIASES[language]
	elif language == "zh":
		# Taiwan, Hong Kong, Macau and the Traditional script write Traditional Chinese.
		var traditional := "Hant" in wanted or wanted.ends_with("_TW") or wanted.ends_with("_HK") or wanted.ends_with("_MO")
		wanted = "zh_TW" if traditional else "zh_CN"
	var best := SOURCE
	var best_score := 0
	for l in available():
		var score := TranslationServer.compare_locales(wanted, l.code)
		if score > best_score:
			best = l.code
			best_score = score
	return best

## The language a choice comes to: Auto is the editor's language, as near as the catalogs get.
static func resolve(choice: String) -> String:
	if choice == AUTO:
		return best_match(TranslationServer.get_tool_locale())
	return choice if has_catalog(choice) else SOURCE

# --- The choice ----------------------------------------------------------------------------------

## The choice: [constant AUTO] or a language code.
static func get_language() -> String:
	if not _session.is_empty():
		return _session
	var es := _editor_settings()
	if es:
		return str(es.get_setting(SETTING)) if es.has_setting(SETTING) else AUTO
	return _choice

## The language shown now (English when nothing else is loaded).
static func current() -> String:
	return _shown

## Whether the language was asked for on the command line, for this session only.
static func is_session_choice() -> bool:
	return not _session.is_empty()

## Switches the panel to [param choice] ([constant AUTO] or a language code), keeps it, and tells
## the panels with [signal Events.language_changed]. They still have to [method refresh].
static func set_language(choice: String) -> void:
	if choice != AUTO and language_info(choice).is_empty():
		push_warning("MetDevSys: there is no language '%s'." % choice)
		return
	_session = ""
	var es := _editor_settings()
	if es:
		es.set_setting(SETTING, choice)
	else:
		_choice = choice
	_applied = choice
	_show(resolve(choice))
	events.language_changed.emit(_shown)

## Follows a change made to the setting in Editor Settings.
static func sync_from_settings() -> void:
	var choice := get_language()
	if _domain and choice != _applied:
		set_language(choice)

## Shows each string as Godot's pseudolocalization does ("[Ṡàvé]"), with room for longer words,
## in any language: for finding text that is not translated and text that does not fit.
static func set_pseudo(on: bool) -> void:
	_pseudo = on
	if _domain:
		_domain.pseudolocalization_enabled = on
		_domain.pseudolocalization_expansion_ratio = 0.3 if on else 0.0
		revision += 1
		events.language_changed.emit(_shown)

# --- Translating text composed in code ------------------------------------------------------------

## [param message] in the panel's language (as it is, in English or when there is no translation).
static func t(message: String, context := "") -> String:
	if not _domain or (_shown == SOURCE and not _pseudo):
		return message
	return String(_domain.translate(message, context))

## [param message] in the panel's language with its placeholders filled by [param args]: an
## Array for % or a Dictionary for {name}. A translation whose placeholders are not those of the
## English (a bad one is a runtime error in GDScript) is not used.
static func tf(message: String, args: Variant, context := "") -> String:
	var text := t(message, context)
	if text != message and _signature(text) != _signature(message):
		text = message
	if args is Dictionary:
		return text.format(args)
	return text % args

## The singular or the plural form of a message for [param n], in the panel's language (Russian
## has three forms, Arabic six). The count is not filled in: see [method tnf].
static func tn(singular: String, plural: String, n: int, context := "") -> String:
	if not _domain or (_shown == SOURCE and not _pseudo):
		return singular if n == 1 else plural
	return String(_domain.translate_plural(singular, plural, n, context))

## [method tn] with the count (and [param args], when the message has more placeholders) filled
## in: [code]tnf("%d room", "%d rooms", n)[/code].
static func tnf(singular: String, plural: String, n: int, args: Array = [], context := "") -> String:
	var text := tn(singular, plural, n, context)
	var english := singular if n == 1 else plural
	var signature := _signature(text)
	if text != english and signature != _signature(singular) and signature != _signature(plural):
		text = english
		signature = _signature(text)
	if signature.is_empty():
		return text
	return text % (args if not args.is_empty() else [n])

## The items one after another, set apart as the language does (", " in English).
static func join(items: Array) -> String:
	var parts := PackedStringArray()
	for item in items:
		parts.append(str(item))
	return t(", ", "list separator").join(parts)

# --- Inside ---------------------------------------------------------------------------------------

static func _catalog_path(code: String) -> String:
	return locale_dir.path_join(code + ".po")

## Loads the catalog of [param code] (English when there is none) into the domain.
static func _show(code: String) -> void:
	if not _domain:
		return
	if _translation:
		_domain.remove_translation(_translation)
		_translation = null
	var shown := SOURCE
	if code != SOURCE and FileAccess.file_exists(_catalog_path(code)):
		var loaded := ResourceLoader.load(_catalog_path(code), "Translation", ResourceLoader.CACHE_MODE_REPLACE)
		if loaded is Translation:
			_translation = loaded
			_domain.add_translation(_translation)
			shown = code
		else:
			push_warning("MetDevSys: the language file of '%s' could not be read; showing English." % code)
	_domain.set_locale_override(shown)
	_shown = shown
	revision += 1

## What a message needs of its arguments: the conversions of its % placeholders in order, and
## the names of its {fields}. Two texts with the same signature take the same arguments.
static func signature(text: String) -> String:
	return _signature(text)

static func _signature(text: String) -> String:
	if _signatures.has(text):
		return _signatures[text]
	if not _spec_re:
		_spec_re = RegEx.create_from_string("%[-+#0]*(?:\\*|\\d+)?(?:\\.(?:\\*|\\d+))?([sdfoxXcevV%])")
		_field_re = RegEx.create_from_string("\\{([A-Za-z_][A-Za-z0-9_]*)\\}")
	var conversions := ""
	for m in _spec_re.search_all(text):
		var c := m.get_string(1)
		if c != "%":
			conversions += c
	var names := PackedStringArray()
	for m in _field_re.search_all(text):
		if not m.get_string(1) in names:
			names.append(m.get_string(1))
	names.sort()
	var signature := conversions + "|" + ",".join(names)
	if signature == "|":
		signature = ""
	_signatures[text] = signature
	return signature

static func _editor_settings() -> Object:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		return Engine.get_singleton(&"EditorInterface").get_editor_settings()
	return null

## Makes the choice a setting of its own in Editor Settings.
static func _register_setting() -> void:
	var es := _editor_settings()
	if not es:
		return
	if not es.has_setting(SETTING):
		es.set_setting(SETTING, AUTO)
	es.set_initial_value(SETTING, AUTO, false)
	var codes := PackedStringArray([AUTO])
	for l in languages():
		codes.append(l.code)
	es.add_property_info({"name": SETTING, "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(codes)})
