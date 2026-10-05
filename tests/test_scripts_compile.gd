extends "res://tests/test_case.gd"
## Every script of the addon and the asset packs compiles, editor-only ones included (the
## other tests only run the runtime and core code).

func _run() -> void:
	var files: PackedStringArray = []
	for dir in ["res://addons/MetroidvaniaDeveloperSystem", "res://asset_packs"]:
		_find(dir, files)
	check(files.size() > 20, "found the scripts (%d)" % files.size())
	for path in files:
		var script := load(path) as GDScript
		check(script != null and script.can_instantiate(), "%s compiles" % path)

func _find(dir: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_find(dir.path_join(d), out)
