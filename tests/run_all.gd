extends Node
## Runs every res://tests/test_*.tscn in turn and exits with 1 when any check failed.
##   godot --headless --path . res://tests/run_all.tscn
## Pass a name filter after "--": godot --headless --path . res://tests/run_all.tscn -- freeform

## A test scene still running after this many seconds (real time) fails the run, which stops
## there: an await that never resumes would otherwise hold it until CI's own timeout, unnamed.
const TEST_TIME_LIMIT := 300.0

var _running := 0 ## counts test scenes started; a time limit only stops the one it was set for

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
		_running += 1
		var running := _running
		# Counts real time and runs while the tree is paused (an open menu).
		get_tree().create_timer(TEST_TIME_LIMIT, true, false, true).timeout.connect(func() -> void:
			if running == _running:
				printerr("  FAIL: %s did not finish in %d s" % [f, int(TEST_TIME_LIMIT)])
				print("\n%s timed out after %s" % [f, ", ".join(failed_tests) + " failed" if failed > 0 else "the scenes before it passed"])
				get_tree().quit(1))
		var n: int = await test.run_tests()
		_running += 1
		if n > 0:
			failed += n
			failed_tests.append(f)
		test.queue_free()
		await get_tree().process_frame
		get_tree().paused = false
		Engine.time_scale = 1.0
	print("\n%d test scene(s), %d failed check(s)%s" % [files.size(), failed, (": " + ", ".join(failed_tests)) if failed > 0 else ""])
	get_tree().quit(1 if failed > 0 else 0)
