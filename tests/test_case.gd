extends Node
## Base of the headless tests. A test scene's root extends this and overrides [method _run]
## (which may await). Run one test, or all of them with run_all.tscn:
## [codeblock]
## godot --headless --path . res://tests/test_freeform_collision.tscn
## godot --headless --path . res://tests/run_all.tscn
## [/codeblock]
## Tests run as scenes, not with --script, so autoloads load. The process exits with 1 when a
## check failed. A test scene whose script doesn't compile has nothing to quit it: run it with
## a timeout, or through run_all.tscn, which reports it.

const TMP := "res://tests/tmp"

var failures := 0
var checks := 0

func _ready() -> void:
	if get_parent() == get_tree().root:
		_standalone.call_deferred()

func _standalone() -> void:
	var failed: int = await run_tests()
	get_tree().quit(1 if failed > 0 else 0)

## Runs the test; returns the number of failed checks.
func run_tests() -> int:
	print("== %s" % name)
	DirAccess.make_dir_recursive_absolute(TMP)
	await _run()
	print("%s: %d checks, %d failed" % [name, checks, failures])
	return failures

func _run() -> void:
	pass

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("  FAIL: ", label)
	return ok

func check_near(value: float, want: float, tolerance: float, label: String) -> bool:
	return check(absf(value - want) <= tolerance, "%s (got %.2f, want %.2f ±%.2f)" % [label, value, want, tolerance])

## Waits [param n] physics frames.
func physics_frames(n := 2) -> void:
	for i in n:
		await get_tree().physics_frame

## Saves [param root] as a scene at [param path] (owners set for its whole tree).
func save_scene(root: Node, path: String) -> Error:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	return err

func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		if not c.owner:
			c.owner = root
		if c.scene_file_path.is_empty():
			_own(c, root)

## A fresh load of [param path], bypassing the resource cache.
func load_fresh(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)

func rect_points(r: Rect2) -> PackedVector2Array:
	return IDPGeometry.rect_polygon(r)
