extends "res://tests/test_case.gd"
## The panel waits for the editor's files on every Godot it supports: 4.6 has no is_importing().

class Files46 extends RefCounted:
	var scanning := false
	func is_scanning() -> bool:
		return scanning

class Files47 extends Files46:
	var importing := false
	func is_importing() -> bool:
		return importing

func _run() -> void:
	var old := Files46.new()
	check(not MDSWorldPanel._editor_files_busy(old), "4.6: nothing going on")
	old.scanning = true
	check(MDSWorldPanel._editor_files_busy(old), "4.6: scanning")

	var new := Files47.new()
	check(not MDSWorldPanel._editor_files_busy(new), "4.7: nothing going on")
	new.scanning = true
	check(MDSWorldPanel._editor_files_busy(new), "4.7: scanning")
	new.scanning = false
	new.importing = true
	check(MDSWorldPanel._editor_files_busy(new), "4.7: importing")
