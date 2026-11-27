extends "res://tests/test_case.gd"
## The world map's two drawing modes (MDSWorldCanvas.DrawMode). MDS draws free-form, on the world
## grid. MetSys draws on map cells a screen each, like MetSys' editor: the Room tool's left drag
## draws a box of cells (a click one cell), its right drag erases cells from any room; cells
## another room has are left out; the Gate tool's click on a cell's border puts a passage there
## (a door each side, connected; a door to nowhere on an outer wall), a click again takes it out;
## rooms move and resize by whole cells. Switching modes leaves the rooms already drawn as they are.
## The previews of rooms' scenes follow their rooms when they move without a drag (undo).

var world: MDSWorld
var canvas: MDSWorldCanvas
var m: Vector2
var scenes: Dictionary = {} ## the scene list the panel passes (the same one each time)

func _run() -> void:
	world = MDSWorld.new()
	canvas = MDSWorldCanvas.new()
	canvas.size = Vector2(1200, 800)
	add_child(canvas)
	canvas.set_data(world, null, scenes)
	m = world.get_default_room_size()
	# A map cell a 100 px on screen: (0, 0) of the world at (50, 50).
	canvas.zoom = 100.0 / m.x
	canvas.pan = Vector2(50, 50)
	canvas._after_view_change()
	_free_form_room()
	_draw_and_erase()
	_passages()
	_moves()
	_switching()
	_previews_follow()
	canvas.queue_free()
	await get_tree().process_frame

## The screen point in the middle of map cell [param c] (plus [param f] of a cell).
func _at(c: Vector2, f := Vector2(0.5, 0.5)) -> Vector2:
	return canvas.world_to_screen((c + f) * m)

func _button(at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = button
	mb.pressed = pressed
	mb.position = at
	canvas._gui_input(mb)

func _drag(from: Vector2, to: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	_button(from, true, button)
	for k in range(1, 5):
		var mm := InputEventMouseMotion.new()
		mm.position = from.lerp(to, k / 4.0)
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		canvas._gui_input(mm)
	_button(to, false, button)

func _free_form_room() -> void:
	check(canvas.draw_mode == MDSWorldCanvas.DrawMode.MDS, "free-form (MDS) by default")
	canvas.set_tool(MDSWorldCanvas.Tool.ROOM)
	# A room off the map cells: 10 grid steps wide, from (2 grid steps, 1) into cell (6, 0).
	var g := world.get_grid()
	_drag(canvas.world_to_screen(Vector2(6 * m.x + 2 * g, g)), canvas.world_to_screen(Vector2(6 * m.x + 12 * g, 9 * g)))
	check(world.get_room_ids().size() == 1, "MDS mode: a box drawn is a room")
	var b := world.get_room_bounds(world.get_room_ids()[0])
	check(b.size == Vector2(10, 8) * g and not is_zero_approx(fposmod(b.position.x, m.x)), "on the world grid, any size (%s)" % b)

func _draw_and_erase() -> void:
	var free_form := world.get_room_ids()[0]
	var shape_before: Array = world.data.rooms[free_form].rects.duplicate(true)
	canvas.set_draw_mode(MDSWorldCanvas.DrawMode.METSYS)
	check(canvas.is_metsys() and world.get_room_ids().size() == 1 and world.data.rooms[free_form].rects == shape_before, "switching to MetSys leaves the room drawn as it was")
	canvas.set_tool(MDSWorldCanvas.Tool.ROOM)
	# A click: a room of one cell.
	_button(_at(Vector2(0, 0)), true)
	_button(_at(Vector2(0, 0)), false)
	var one := canvas.selected_room
	check(world.has_room(one) and world.get_room_bounds(one) == Rect2(Vector2.ZERO, m), "a click draws a room of one map cell (%s)" % world.get_room_bounds(one))
	# A drag from cell (1, 0) to (3, 1): a room of 3 x 2 cells.
	_drag(_at(Vector2(1, 0), Vector2(0.3, 0.6)), _at(Vector2(3, 1), Vector2(0.8, 0.2)))
	var big := canvas.selected_room
	check(big != one and world.get_room_bounds(big) == Rect2(Vector2(m.x, 0), m * Vector2(3, 2)), "a drag draws the box of cells, both ends in (%s)" % world.get_room_bounds(big))
	# Over cells taken: only the free ones.
	_drag(_at(Vector2(0, 0)), _at(Vector2(0, 1)))
	var below := canvas.selected_room
	check(world.get_room_bounds(below) == Rect2(Vector2(0, m.y), m), "a box over a room takes only the cells free (%s)" % world.get_room_bounds(below))
	check(world.get_room_bounds(one) == Rect2(Vector2.ZERO, m), "and leaves the room there as it was")
	var n := world.get_room_ids().size()
	_button(_at(Vector2(2, 0)), true)
	_button(_at(Vector2(2, 0)), false)
	check(world.get_room_ids().size() == n, "a click on a taken cell draws nothing")
	# Right drag: erase cells (3, 0) to (3, 1) from the big room.
	_drag(_at(Vector2(3, 0)), _at(Vector2(3, 1)), MOUSE_BUTTON_RIGHT)
	check(world.get_room_bounds(big) == Rect2(Vector2(m.x, 0), m * Vector2(2, 2)), "a right drag erases the cells under it (%s)" % world.get_room_bounds(big))
	world.undo()
	check(world.get_room_bounds(big) == Rect2(Vector2(m.x, 0), m * Vector2(3, 2)), "in one undo step")
	world.redo()
	# A right drag over a whole room removes it.
	_drag(_at(Vector2(0, 1)), _at(Vector2(0, 1), Vector2(0.9, 0.9)), MOUSE_BUTTON_RIGHT)
	check(not world.has_room(below), "a room left without cells goes")

func _passages() -> void:
	canvas.set_tool(MDSWorldCanvas.Tool.GATE)
	var rooms := world.get_room_ids()
	var one := world.room_at(Vector2(0.5, 0.5) * m, 0)
	var big := world.room_at(Vector2(1.5, 0.5) * m, 0)
	# The border between cell (0, 0) (room one) and (1, 0) (the big room): near it, inside (0, 0).
	_button(_at(Vector2(0, 0), Vector2(0.9, 0.5)), true)
	_button(_at(Vector2(0, 0), Vector2(0.9, 0.5)), false)
	check(world.get_gates(one).size() == 1 and world.get_gates(big).size() == 1, "a click on the border between two rooms puts a door each side")
	var ga: String = world.get_gates(one).keys()[0]
	var gb: String = world.get_gates(big).keys()[0]
	check(world.get_gate(one, ga).get("to", "") == big and world.get_gate(one, ga).get("to_gate", "") == gb and world.get_gate(big, gb).get("to", "") == one, "connected to each other")
	check(world.get_gate_side(one, ga) == "right" and world.get_gate_side(big, gb) == "left", "on the sides facing each other (%s, %s)" % [world.get_gate_side(one, ga), world.get_gate_side(big, gb)])
	check(world.get_gate_world_pos(one, ga).distance_to(Vector2(m.x, m.y * 0.5)) < m.y * 0.3, "in the middle of the border (%s)" % world.get_gate_world_pos(one, ga))
	# Again (from the other side of the border): taken out.
	_button(_at(Vector2(1, 0), Vector2(0.08, 0.5)), true)
	_button(_at(Vector2(1, 0), Vector2(0.08, 0.5)), false)
	check(world.get_gates(one).is_empty() and world.get_gates(big).is_empty(), "a click on it again takes both doors out")
	# A room's outer wall: a door to nowhere.
	_button(_at(Vector2(0, 0), Vector2(0.5, 0.05)), true)
	_button(_at(Vector2(0, 0), Vector2(0.5, 0.05)), false)
	check(world.get_gates(one).size() == 1 and world.get_gate_side(one, world.get_gates(one).keys()[0]) == "top", "on an outer wall: a door to nowhere")
	# Between two cells of one room: nothing.
	_button(_at(Vector2(1, 0), Vector2(0.95, 0.5)), true)
	_button(_at(Vector2(1, 0), Vector2(0.95, 0.5)), false)
	check(world.get_gates(big).is_empty(), "between two cells of one room: none")
	# In the middle of a cell (far from its borders): nothing.
	_button(_at(Vector2(2, 1)), true)
	_button(_at(Vector2(2, 1)), false)
	check(world.get_gates(big).is_empty() and world.get_room_ids() == rooms, "the middle of a cell: nothing")

func _moves() -> void:
	canvas.set_tool(MDSWorldCanvas.Tool.SELECT)
	var one := world.room_at(Vector2(0.5, 0.5) * m, 0)
	# Down a cell and a third: by whole cells.
	_drag(_at(Vector2(0, 0)), _at(Vector2(0, 1), Vector2(0.5, 0.85)))
	check(world.get_room_bounds(one).position == Vector2(0, m.y), "a room moves by whole map cells (%s)" % world.get_room_bounds(one).position)
	world.undo()
	check(world.get_room_bounds(one).position == Vector2.ZERO, "undone")

func _switching() -> void:
	var shapes: Dictionary = {}
	for id in world.get_room_ids():
		shapes[id] = [world.get_origin(id), world.data.rooms[id].rects.duplicate(true)]
	canvas.set_draw_mode(MDSWorldCanvas.DrawMode.MDS)
	check(not canvas.is_metsys(), "back to MDS")
	var same := true
	for id in shapes:
		same = same and world.get_origin(id) == shapes[id][0] and world.data.rooms[id].rects == shapes[id][1]
	check(same and world.get_room_ids().size() == shapes.size(), "switching back leaves every room as it is")
	canvas.set_tool(MDSWorldCanvas.Tool.ROOM)
	var g := world.get_grid()
	var before := world.get_room_ids().size()
	_drag(canvas.world_to_screen(Vector2(0, 3 * m.y + g)), canvas.world_to_screen(Vector2(5 * g, 3 * m.y + 4 * g)))
	check(world.get_room_ids().size() == before + 1 and world.get_room_bounds(canvas.selected_room).size == Vector2(5, 3) * g, "and draws free-form again")

func _previews_follow() -> void:
	# A preview node stands for a scene's: it goes where its room is on an undo.
	var id := world.room_at(Vector2(1.5, 0.5) * m, 0)
	var node := Node2D.new()
	canvas._preview_root.add_child(node)
	canvas._preview_nodes[id] = node
	canvas.show.previews = true
	canvas._preview_layer = canvas.layer
	canvas._preview_sig = canvas._preview_signature()
	world.checkpoint()
	world.set_origin(id, world.get_origin(id) + Vector2(0, m.y * 3))
	canvas.set_data(world, null, scenes)
	check(node.position == world.get_origin(id), "a room's preview goes with it when it moves (%s)" % node.position)
	world.undo()
	canvas.set_data(world, null, scenes)
	check(is_instance_valid(node) and node.position == world.get_origin(id), "and back on undo (%s)" % node.position)
	canvas.show.previews = false
