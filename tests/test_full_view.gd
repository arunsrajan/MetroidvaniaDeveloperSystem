extends "res://tests/test_case.gd"
## The Full view (MDSRoomView.open_full): every room of a layer at its real size, none edited until
## a press in one. Works on an empty world: rooms are drawn as outlines (Rectangle, Ellipse,
## Polygon, Curvy), Generate map makes them rooms; a press in a room paints it (one without a
## scene gets one) and the view stays where it is; the Rooms tool selects, moves (Ctrl+Z on the
## map takes it back) and deletes rooms, a double-click asks for the Room view; scenes dropped on
## it are asked to be placed where they were dropped; Generate all makes caves in every room;
## Save saves them all.

const DIR := TMP + "/full_view"

var world: MDSWorld
var view: MDSRoomView
var canvas: MDSRoomCanvas
var tools: MDSFullViewTools

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	world = MDSWorld.new()
	world.path = DIR + "/full.mdsworld.json"
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	view = MDSRoomView.new()
	view.size = Vector2(1400, 900)
	view.scene_path_for = func(id: String) -> String: return DIR.path_join(id.to_snake_case() + ".tscn")
	add_child(view)
	await get_tree().process_frame
	canvas = view.canvas
	tools = view.full_tools
	var s := world.get_paint_cell()

	# An empty world opens: nothing edited, ready to draw rooms.
	check(view.open_full(world, 0).is_empty() and view.is_full() and canvas.full, "the Full view opens on an empty world")
	check(view.painter == null and view.session_rooms().is_empty(), "no room edited, none shown")
	check(tools.tool == MDSFullViewTools.Tool.RECTANGLE, "with Rectangle picked, to draw the first room")
	var tiles := MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	check(view.palette.painter != null and view.palette.painter.tile_set == tiles and view.palette.source_opt.item_count > 0, "the tile palette shows the rooms' tileset and its sheets, no room edited (%d)" % view.palette.source_opt.item_count)
	canvas.zoom = 0.25
	canvas.pan = Vector2(40, 40)
	canvas._apply_view()
	await get_tree().process_frame

	# Drawn with the mouse: a rectangle on the paint cells, an ellipse, a polygon, a curvy outline.
	_drag(_screen(Vector2(10, 5)), _screen(Vector2(864 + 20, 324 - 10)))
	check(MDSRoomSketches.count(world, 0) == 1, "a rectangle drawn")
	check(MDSGeometry.bounds(MDSRoomSketches.polygon(world, 0)) == Rect2(0, 0, 864, 324), "on the paint cells' corners")
	view.set_full_tool(MDSFullViewTools.Tool.ELLIPSE)
	_drag(_screen(Vector2(864, 0)), _screen(Vector2(864 + 1152, 648)))
	check(MDSRoomSketches.count(world, 0) == 2 and str(MDSRoomSketches.get_sketch(world, 1).draw) == "ellipse", "an ellipse")
	view.set_full_tool(MDSFullViewTools.Tool.POLYGON)
	for q in [Vector2(0, 700), Vector2(800, 700), Vector2(800, 1300), Vector2(400, 1100), Vector2(0, 1300)]:
		_click(_screen(q))
	_key(KEY_ENTER)
	check(MDSRoomSketches.count(world, 0) == 3 and MDSRoomSketches.polygon(world, 2).size() == 5, "a polygon of five corners, closed with Enter")
	view.set_full_tool(MDSFullViewTools.Tool.CURVY)
	var stroke: Array[Vector2] = []
	for i in 40:
		var t := TAU * i / 40.0
		stroke.append(Vector2(1700, 1100) + Vector2(cos(t) * 500.0, sin(t) * 300.0))
	_stroke(stroke)
	check(MDSRoomSketches.count(world, 0) == 4 and MDSGeometry.is_simple(MDSRoomSketches.polygon(world, 3)), "a curvy outline, smoothed")
	world.undo()
	check(MDSRoomSketches.count(world, 0) == 3, "Ctrl+Z on the map takes an outline back")
	world.redo()
	await get_tree().process_frame

	# Generate map: the outlines are rooms on the map, shown in the Full view.
	var r := view.generate_map()
	check(r.rooms.size() == 4 and MDSRoomSketches.count(world, 0) == 0, "Generate map makes the four outlines rooms (%d)" % r.rooms.size())
	check(view.session_rooms().size() == 4 and canvas._context.size() == 4, "every room shows in the Full view (%d)" % canvas._context.size())
	var rect_room := world.room_at(Vector2(100, 100), 0)
	var oval_room := world.room_at(Vector2(1440, 324), 0)
	check(not rect_room.is_empty() and not oval_room.is_empty() and rect_room != oval_room, "the rectangle and the ellipse are two rooms")
	check(MDSAreaTools.rooms_connected(world, rect_room, oval_room), "joined by a door where they touch")
	await get_tree().process_frame

	# A press in a room with a painting tool: it gets a scene and is painted, the view stays.
	view.set_tool(MDSRoomCanvas.Tool.TERRAIN)
	check(tools.tool == -1, "a painting tool takes over from the Full view's tools")
	var terrains := range(view.fill_opt.item_count).filter(func(i: int) -> bool: return view.fill_opt.get_item_text(i).begins_with("Terrain:"))
	check(view.painter == null and not view.fill_opt.disabled and not terrains.is_empty(), "its fills list the tileset's terrains before a room is edited (%d)" % view.fill_opt.item_count)
	view.palette.select_region(Rect2i(0, 0, 1, 1))
	check(view.palette.has_selection() and canvas.fills[MDSRoomCanvas.Tool.TERRAIN].get("type") == "stamp", "tiles picked in the palette are the brush's fill")
	view.set_tool(MDSRoomCanvas.Tool.TERRAIN)
	canvas.fills[MDSRoomCanvas.Tool.TERRAIN] = {"type": "terrain", "set": 0, "terrain": 0}
	canvas.shape = MDSTerrainShapes.Shape.BRUSH
	canvas.brush_size = 1
	var spot := Vector2(300, 150)
	var screen := _screen(spot)
	_press(screen, true)
	_press(screen, false)
	check(view.room_id == rect_room and view.painter != null, "a press in a room edits it (%s)" % view.room_id)
	check(not world.get_scene_path(rect_room).is_empty() and FileAccess.file_exists(world.get_scene_path(rect_room)), "it got a scene")
	check(_screen(spot).is_equal_approx(screen), "the view stays where it was")
	var cell := view.painter.cell_at("Terrain", spot - world.get_origin(rect_room))
	check(view.painter.layers.Terrain.get_cell_source_id(cell) >= 0, "and the press painted there")
	var first := view.painter
	var spot2 := Vector2(1440, 324)
	_press(_screen(spot2), true)
	_press(_screen(spot2), false)
	check(view.room_id == oval_room and first.dirty, "a press in another room edits that one; the first keeps its change")

	# The Rooms tool: select, move by paint cells, undo, box select, double-click, delete.
	view.set_full_tool(MDSFullViewTools.Tool.ROOMS)
	var poly_room := world.room_at(Vector2(200, 900), 0)
	var origin := world.get_origin(poly_room)
	var before_edit := _screen(spot2)
	check(tools.selected_rooms().size() == 4, "Generate map left its new rooms selected")
	_click(_screen(Vector2(-600, -600)))
	check(tools.selected_rooms().is_empty(), "a click on empty space lets them go")
	_drag(_screen(Vector2(200, 900)), _screen(Vector2(200, 900 + s.y * 2 + 10)))
	check(tools.selected_rooms().size() == 1 and tools.selected_rooms()[0] == poly_room, "a press on a room selects it")
	check(world.get_origin(poly_room) == origin + Vector2(0, s.y * 2), "dragged, it moves by whole paint cells (%s)" % (world.get_origin(poly_room) - origin))
	check(_screen(spot2).is_equal_approx(before_edit), "the room edited stays where it is")
	_key(KEY_Z, true)
	check(world.get_origin(poly_room) == origin, "Ctrl+Z takes the move back")
	var asked: Array = []
	view.rooms_requested.connect(func(ids: Array[String]) -> void: asked.append(ids))
	_drag(_screen(Vector2(-200, -200)), _screen(Vector2(2100, 600)))
	check(tools.selected_rooms().size() == 2 and tools.selected_rooms().has(rect_room) and tools.selected_rooms().has(oval_room), "a box on empty space selects the rooms in it (%d)" % tools.selected_rooms().size())
	check(view.full_selection().size() == 2, "the Room view button takes them")
	_click(_screen(Vector2(100, 100)), true)
	check(asked.size() == 1 and (asked[0] as Array).size() == 2, "a double-click asks for the Room view of the rooms selected")
	var curvy_room := world.room_at(Vector2(1700, 1100), 0)
	tools.select([curvy_room])
	_key(KEY_DELETE)
	check(not world.has_room(curvy_room), "Delete removes the room selected")
	view.refresh_full()
	check(view.session_rooms().size() == 3 and not canvas._context.has(curvy_room), "and it is gone from the view")
	world.undo()
	view.refresh_full()
	check(world.has_room(curvy_room) and view.session_rooms().size() == 4, "Ctrl+Z brings it back")

	# A scene dropped on empty space is asked to be placed where it was dropped.
	var dropped: Array = []
	view.scenes_dropped.connect(func(files: PackedStringArray, at: Vector2) -> void: dropped.append([files, at]))
	var data := {"type": "files", "files": PackedStringArray([world.get_scene_path(rect_room)])}
	var at := _screen(Vector2(3000, 200))
	check(canvas._can_drop_data(at, data), "scenes can be dropped on the Full view")
	canvas._drop_data(at, data)
	check(dropped.size() == 1 and (dropped[0][1] as Vector2).distance_to(Vector2(3000, 200)) < 1.0, "placed where they were dropped, in world px")

	# A room whose rectangles leave a notch in its box goes under the others: Generate cave fills
	# its whole box with rock, and in the notch is another room.
	world.checkpoint()
	var l_room := world.add_room("Ell", Rect2(0, 3000, 864, 324), 0)
	world.add_rect(l_room, Rect2(0, 3324, 288, 324))
	world.add_room("InTheNotch", Rect2(288, 3324, 576, 324), 0)
	MDSWorldSceneTools.create_scene_for_room(world, l_room, DIR + "/ell.tscn")
	load_fresh(DIR + "/ell.tscn")
	view.refresh_full()
	canvas.pan = canvas.size / 2.0 - canvas.world_to_local(Vector2(432, 3324)) * canvas.zoom
	view.refresh_full()
	check(MDSRoomCanvas.has_notches(world, l_room) and not MDSRoomCanvas.has_notches(world, "InTheNotch"), "an L room has a notch, a rectangle none")
	check((canvas._context[l_room] as Node2D).z_index == MDSRoomCanvas.NOTCHED_Z and (canvas._context["InTheNotch"] as Node2D).z_index == 0, "the L room is drawn under the room in its notch")
	# Its scene comes in a frame or so later (see test_full_view_loading).
	for i in 120:
		if canvas.is_room_live(l_room) and not canvas.is_full_loading():
			break
		await get_tree().process_frame
	var ell_layers: Array[Node] = (canvas._context[l_room] as Node2D).find_children("*", "TileMapLayer", true, false)
	check(not ell_layers.is_empty() and ell_layers.all(func(l: Node) -> bool: return (l as TileMapLayer).material is ShaderMaterial and ((l as TileMapLayer).material as ShaderMaterial).shader == MDSRoomCanvas.ROOM_MASK), "and its tiles show only inside its rectangles")
	world.undo()
	view.refresh_full()
	check(not canvas._context.has(l_room), "and goes with Ctrl+Z")

	# Generate all: a cave in every room (scenes made for those without), Save saves them all.
	tools.clear_selection()
	check(view.generate_all(false) == 4, "Generate all makes a cave in each of the 4 rooms")
	for id in view.session_rooms():
		var p: MDSRoomPainter = view._painters.get(id)
		check(p != null and p.dirty and p.layers.Terrain.get_used_cells().size() > 30, "%s has its cave" % id)
	check(view.save() == OK and not view.has_unsaved(), "Save saves them all")
	# Leaving: back to one room at a time.
	view.close_room(false)
	check(not view.is_full() and not canvas.full and canvas._context.is_empty() and tools.tool == -1, "closing ends the Full view")
	check(view.open_room(world, rect_room).is_empty() and not view.is_full(), "a room opened then is the Room view's alone")
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame

func _screen(world_pos: Vector2) -> Vector2:
	return canvas.local_to_screen(canvas.world_to_local(world_pos))

func _press(p: Vector2, pressed: bool, double := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.double_click = double
	mb.position = p
	canvas._gui_input(mb)

func _move(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(mm)

func _drag(a: Vector2, b: Vector2) -> void:
	_press(a, true)
	for k in 4:
		_move(a.lerp(b, (k + 1) / 4.0))
	_press(b, false)

func _click(p: Vector2, double := false) -> void:
	_press(p, true, double)
	_press(p, false)

func _stroke(points: Array[Vector2]) -> void:
	_press(_screen(points[0]), true)
	for q in points:
		_move(_screen(q))
	_press(_screen(points[points.size() - 1]), false)

func _key(code: Key, ctrl := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	canvas._gui_input(k)
