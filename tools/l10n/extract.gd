extends SceneTree
## Writes the catalog template, addons/MetroidvaniaDeveloperSystem/locale/mds.pot, from the
## scripts:
##   godot --headless --path . --script res://tools/l10n/extract.gd
## Add [code]-- --check[/code] to only say whether the file is current (it exits with 1 when it
## is not), and [code]-- --todo[/code] to list the strings that are put together in code, which
## the catalog cannot hold until the code is written to translate them.

const Extractor := preload("res://tools/l10n/extractor.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--unclaimed" in args:
		_list_unclaimed()
		quit(0)
		return
	var result := Extractor.extract()
	var text := Extractor.pot_text(result.messages)
	var current := FileAccess.get_file_as_string(Extractor.POT) if FileAccess.file_exists(Extractor.POT) else ""
	print("l10n: %d messages; %d strings put together in code, not in the catalog yet" % [result.messages.size(), result.todo.size()])
	if "--todo" in args:
		for item in result.todo:
			print("  %s:%d  %s  %s" % [item.file, item.line, item.via, Extractor.quote(item.text)])
	if "--check" in args:
		if text == current:
			print("l10n: mds.pot is current")
			quit(0)
		else:
			printerr("l10n: mds.pot is out of date: run tools/l10n/extract.gd")
			quit(1)
		return
	if text != current:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Extractor.POT.get_base_dir()))
		var file := FileAccess.open(Extractor.POT, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		print("l10n: wrote ", Extractor.POT)
	else:
		print("l10n: mds.pot was already current")
	quit(0)

## Strings that read like text and that no sink claims, grouped by the call or list they are in
## (most first): what to teach the extractor next.
func _list_unclaimed() -> void:
	var groups: Dictionary = {}
	for path in Extractor.scripts():
		var rel := path.trim_prefix(Extractor.ADDON + "/")
		for item in Extractor.unclaimed(FileAccess.get_file_as_string(path), rel):
			var group: Dictionary = groups.get(item.context, {"count": 0, "examples": []})
			group.count += 1
			if group.examples.size() < 2:
				group.examples.append("%s:%d %s" % [rel, item.line, Extractor.quote(item.text).left(60)])
			groups[item.context] = group
	var names := groups.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return groups[a].count > groups[b].count)
	var total := 0
	for n in names:
		total += groups[n].count
	print("l10n: %d unclaimed strings in %d places" % [total, names.size()])
	for n in names.slice(0, 90):
		print("%4d  %s   e.g. %s" % [groups[n].count, n, " | ".join(groups[n].examples)])
