extends "res://tests/test_case.gd"
## Map Dev's windows fit the screen: the floating window and the dialogs are never bigger
## than the screen (or the window they open over) and stay on it, dialogs scroll what doesn't
## fit, and the panel's row shrinks (the tool panel collapses) instead of running off the edge
## of a small window or a narrow dock.

func _run() -> void:
	_fit_rect()
	_row()
	await _dialogs()

func _fit_rect() -> void:
	var usable := Rect2i(0, 40, 1366, 728)
	check(MDSUi.fit_rect(Rect2i(100, 100, 2560, 1600), usable) == Rect2i(0, 40, 1366, 728), "a window bigger than the screen is shrunk to it")
	check(MDSUi.fit_rect(Rect2i(1200, 600, 640, 420), usable) == Rect2i(726, 348, 640, 420), "one hanging off its edge is moved back on it")
	check(MDSUi.fit_rect(Rect2i(-900, 10, 640, 420), usable) == Rect2i(0, 40, 640, 420), "on any side")
	check(MDSUi.fit_rect(Rect2i(5, 5, 50, 50), Rect2i()) == Rect2i(5, 5, 50, 50), "no screen (headless): left as it is")

func _row() -> void:
	var side := MDSSidePanel.new()
	var canvas := Control.new()
	var tabs := Control.new()
	add_child(side)
	MDSSidePanel.fit_row(470.0, side, canvas, tabs)
	var row_min := (0.0 if side.is_collapsed() else MDSSidePanel.WIDTH) + canvas.custom_minimum_size.x + tabs.custom_minimum_size.x
	check(side.is_collapsed() and row_min <= 470.0, "a narrow dock: the tool panel collapses and the row fits (%.0f px)" % row_min)
	MDSSidePanel.fit_row(1400.0, side, canvas, tabs)
	check(not side.is_collapsed() and tabs.custom_minimum_size.x == 300.0 and canvas.custom_minimum_size.x == 200.0, "room again: it opens and everything has its usual width")
	side._collapse.pressed.emit()
	MDSSidePanel.fit_row(1400.0, side, canvas, tabs)
	check(side.is_collapsed(), "a panel the user collapsed stays collapsed")
	side.free()
	canvas.free()
	tabs.free()

## Collects the engine errors logged while it is added (OS.add_logger).
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []
	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s: %s %s" % [function, code, rationale])

func _dialogs() -> void:
	var root := get_tree().root
	var was := root.size
	root.size = Vector2i(800, 480)
	await get_tree().process_frame
	var lim := MDSUi.popup_limit(root)
	check(lim.x <= 800 and lim.y <= 480, "a dialog may be at most %s over an 800x480 window" % lim)
	var d := ConfirmationDialog.new()
	var box := VBoxContainer.new()
	for i in 60:
		var l := MDSUi.label("A long settings field %d" % i)
		box.add_child(l)
	MDSUi.scroll_content(d, box)
	add_child(d)
	MDSUi.popup_fitted(d, 2000)
	await get_tree().process_frame
	await get_tree().process_frame
	check(d.size.x <= lim.x and d.size.y <= lim.y, "a tall, wide dialog is capped (%s)" % d.size)
	check(Rect2i(Vector2i.ZERO, root.size).encloses(Rect2i(d.position, d.size)), "and stays inside the window (%s at %s)" % [d.size, d.position])
	var scroll: ScrollContainer = d.get_meta(&"mds_scroll")
	check(box.get_combined_minimum_size().y > scroll.size.y, "what doesn't fit scrolls")
	d.hide()
	var small := ConfirmationDialog.new()
	var one := VBoxContainer.new()
	one.add_child(MDSUi.label("Short"))
	MDSUi.scroll_content(small, one)
	add_child(small)
	MDSUi.popup_fitted(small, 300)
	await get_tree().process_frame
	await get_tree().process_frame
	check(small.size.x == 300 and small.size.y < 240, "a short dialog is only as tall as it needs (%s)" % small.size)
	small.hide()
	var trace := MDSTraceDialog.new()
	add_child(trace)
	MDSUi.popup_fitted(trace, 640)
	await get_tree().process_frame
	await get_tree().process_frame
	check(trace.size.x <= lim.x and trace.size.y <= lim.y and Rect2i(Vector2i.ZERO, root.size).encloses(Rect2i(trace.position, trace.size)), "the Trace drawing dialog fits too (%s at %s)" % [trace.size, trace.position])
	trace.hide()
	# A dialog with its content added directly (no scroll_content) fits too, quietly.
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var plain := ConfirmationDialog.new()
	var edit := LineEdit.new()
	edit.custom_minimum_size.x = 320
	plain.add_child(edit)
	add_child(plain)
	MDSUi.popup_fitted(plain, 360)
	await get_tree().process_frame
	await get_tree().process_frame
	OS.remove_logger(catcher)
	check(catcher.errors.is_empty() and plain.size.x == 360, "a dialog without a scroll fits with no errors (%s)" % "; ".join(catcher.errors))
	plain.hide()
	var gen := MDSAreaGenerateDialog.new()
	add_child(gen)
	gen.open(MDSWorld.new(), Rect2i(0, 0, 16, 10), 0, MDSAreaGenerator.new())
	await get_tree().process_frame
	await get_tree().process_frame
	check(gen.size.x <= lim.x and gen.size.y <= lim.y and Rect2i(Vector2i.ZERO, root.size).encloses(Rect2i(gen.position, gen.size)), "the Generate area dialog fits too (%s at %s)" % [gen.size, gen.position])
	gen.hide()
	for n in [d, small, trace, plain, gen]:
		n.queue_free()
	root.size = was
	await get_tree().process_frame
