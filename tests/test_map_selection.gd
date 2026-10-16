extends "res://tests/test_case.gd"
## Several rooms selected on the world map (MDSWorldCanvas): Ctrl+click adds a room or takes it
## out, Ctrl+drag on empty space selects the rooms in a box, Ctrl+A all of the layer's, Esc
## none; dragging one of them moves them all (stopping against other rooms, doors made where
## they touch), the arrows nudge them, Delete deletes them with one undo. Map images dropped on
## the map are offered for import.

var world: MDSWorld
var canvas: MDSWorldCanvas

func _run() -> void:
	world = MDSWorld.new()
	for r in [["R1", Vector2i(0, 0)], ["R2", Vector2i(4, 0)], ["R3", Vector2i(8, 0)], ["Far", Vector2i(20, 8)]]:
		world.add_room(r[0], Rect2(Vector2(r[1]) * Vector2(288, 162), Vector2(288 * 2, 162 * 2)))
	canvas = MDSWorldCanvas.new()
	canvas.size = Vector2(900, 600)
	add_child(canvas)
	canvas.set_data(world, null, {})
	canvas.zoom = 0.1
	canvas.pan = Vector2(20, 20)
	canvas.set_tool(MDSWorldCanvas.Tool.SELECT)
	var changed: Array = []
	canvas.selection_changed.connect(func(ids: Array[String]) -> void: changed.append(ids.size()))
	_click(_at("R1"), true)
	_click(_at("R1"), false)
	check(canvas.get_selected_rooms() == ["R1"], "a click selects one room")
	_click(_at("R2"), true, true)
	_click(_at("R2"), false, true)
	check(canvas.get_selected_rooms() == ["R1", "R2"], "Ctrl+click adds another (%s)" % [canvas.get_selected_rooms()])
	check(not changed.is_empty() and changed.back() == 2, "and says so")
	_click(_at("R2"), true, true)
	_click(_at("R2"), false, true)
	check(canvas.get_selected_rooms() == ["R1"], "Ctrl+click on a selected one takes it out")
	# A box.
	var a := canvas.world_to_screen(Vector2(-100, -100))
	var b := canvas.world_to_screen(Vector2(288 * 9, 162 * 3))
	_click(a, true, true)
	_move(a.lerp(b, 0.5))
	_move(b)
	_click(b, false, true)
	check(canvas.get_selected_rooms().size() == 3 and not canvas.get_selected_rooms().has("Far"), "Ctrl+drag on empty space selects the rooms in the box (%s)" % [canvas.get_selected_rooms()])
	# Dragging one moves them all, in paint cells.
	var before := world.get_origin("R3")
	var grab := _at("R2")
	_click(grab, true)
	_move(grab + Vector2(0, 162 * 0.1 * 2))
	_move(grab + Vector2(0, 162 * 0.1 * 4))
	_click(grab + Vector2(0, 162 * 0.1 * 4), false)
	check(world.get_origin("R1") == Vector2(0, 162 * 4) and world.get_origin("R3") == before + Vector2(0, 162 * 4), "dragging one of them moves all three (%s)" % world.get_origin("R1"))
	check(canvas.get_selected_rooms().size() == 3, "and they stay selected")
	world.undo()
	check(world.get_origin("R1") == Vector2.ZERO, "one undo puts them back")
	# Arrows.
	canvas.select_rooms(["R1", "R2"])
	_key(KEY_RIGHT)
	check(world.get_origin("R1") == Vector2(288, 0) and world.get_origin("R2") == Vector2(288 * 5, 0), "an arrow nudges them a cell")
	_key(KEY_RIGHT)
	check(world.get_origin("R2") == Vector2(288 * 6, 0) and world.get_origin("R1") == Vector2(288 * 2, 0), "up to the room beside them")
	_key(KEY_RIGHT)
	check(world.get_origin("R2") == Vector2(288 * 6, 0), "not into it")
	var doors := 0
	for g: Dictionary in world.get_gates("R2").values():
		if str(g.get("to", "")) == "R3":
			doors += 1
	check(doors == 1, "a door where they touch it now")
	# A click on one of them picks just it.
	_click(_at("R1"), true)
	_click(_at("R1"), false)
	check(canvas.get_selected_rooms() == ["R1"], "a click on one of them selects just it")
	# Ctrl+A, Esc, Delete.
	_key(KEY_A, true)
	check(canvas.get_selected_rooms().size() == 4, "Ctrl+A selects every room of the layer")
	_key(KEY_ESCAPE)
	check(canvas.selected_rooms.is_empty(), "Esc lets them go")
	canvas.select_rooms(["R1", "R3"])
	canvas.delete_selection()
	check(not world.has_room("R1") and not world.has_room("R3") and world.has_room("R2"), "Delete deletes the rooms selected")
	world.undo()
	check(world.has_room("R1") and world.has_room("R3"), "with one undo")
	check(canvas.get_selected_rooms().size() <= 1, "rooms gone from the selection are dropped from it")
	# Map images dropped.
	var dropped: Array = []
	canvas.image_dropped.connect(func(path: String, at: Vector2) -> void: dropped.append([path, at]))
	check(canvas._can_drop_data(Vector2(10, 10), {"type": "files", "files": ["res://maps/castle.png"]}), "a map image can be dropped on the map")
	canvas._drop_data(Vector2(10, 10), {"type": "files", "files": ["res://maps/castle.png"]})
	check(dropped.size() == 1 and dropped[0][0] == "res://maps/castle.png" and (dropped[0][1] as Vector2).is_equal_approx(canvas.screen_to_world(Vector2(10, 10))), "dropping one offers it for import, where it was let go")
	canvas.queue_free()
	await get_tree().process_frame

func _at(id: String) -> Vector2:
	return canvas.world_to_screen(world.get_room_bounds(id).get_center())

func _click(at: Vector2, pressed: bool, ctrl := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.ctrl_pressed = ctrl
	mb.position = at
	canvas._gui_input(mb)

func _move(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(mm)

func _key(code: Key, ctrl := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	canvas._gui_input(k)
