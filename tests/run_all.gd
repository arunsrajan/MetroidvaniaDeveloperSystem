extends Node
## Runs every res://tests/test_*.tscn in turn and exits with 1 when any check failed.
##   godot --headless --path . res://tests/run_all.tscn
## Pass a name filter after "--": godot --headless --path . res://tests/run_all.tscn -- freeform

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		filter = a
	var files := Array(DirAccess.get_files_at("res://tests")).filter(func(f: String) -> bool:
		return f.begins_with("test_") and f.ends_with(".tscn") and (filter.is_empty() or f.contains(filter)))
	files.sort()
	var failed := 0
	var failed_tests: PackedStringArray = []
	for f in files:
		var test: Node = (load("res://tests/" + f) as PackedScene).instantiate()
		if not test.has_method("run_tests"):
			# Its script failed to compile (the error is above).
			printerr("  FAIL: %s did not compile" % f)
			failed += 1
			failed_tests.append(f)
			test.free()
			continue
		add_child(test)
		var n: int = await test.run_tests()
		if n > 0:
			failed += n
			failed_tests.append(f)
		test.queue_free()
		await get_tree().process_frame
	print("\n%d test scene(s), %d failed check(s)%s" % [files.size(), failed, (": " + ", ".join(failed_tests)) if failed > 0 else ""])
	get_tree().quit(1 if failed > 0 else 0)
