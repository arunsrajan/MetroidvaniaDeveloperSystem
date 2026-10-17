extends "res://tests/test_case.gd"
## Several rooms in the Room view (MDSRoomView.open_rooms): an area or the rooms selected on the
## map show together where they are on the map. One is edited, the others show around it,
## dimmed; a press in one of them edits that one (the press goes on there), each keeps its
## changes and its own undo meanwhile, painting stops where another room is, Save saves them
## all, Generate all makes a cave in each, and < > go from one to the next.

const DIR := TMP + "/room_session"

var world: MDSWorld
var view: MDSRoomView
var canvas: MDSRoomCanvas

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	world = MDSWorld.new()
	world.path = DIR + "/session.mdsworld.json"
	world.add_room("A", Rect2(0, 0, 1152, 648), 0, "Caves")
	world.add_room("B", Rect2(1152, 0, 1152, 648), 0, "Caves")
	world.add_room("C", Rect2(0, 648, 1152, 648), 0, "Caves")
	world.get_gates("A")["right1"] = {"pos": [1152, 400], "side": "right"}
	world.get_gates("B")["left1"] = {"pos": [0, 400], "side": "left"}
	world.get_gates("A")["bot1"] = {"pos": [500, 648], "side": "bot"}
	world.get_gates("C")["top1"] = {"pos": [500, 0], "side": "top"}
	world.connect_gates("A", "right1", "B", "left1")
	world.connect_gates("A", "bot1", "C", "top1")
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	for id in ["A", "B", "C"]:
		var path := DIR + "/%s.tscn" % id.to_lower()
		MDSWorldSceneTools.create_scene_for_room(world, id, path)
		load_fresh(path)
	view = MDSRoomView.new()
	view.size = Vector2(1300, 800)
	add_child(view)
	await get_tree().process_frame
	canvas = view.canvas
	check(view.open_rooms(world, ["A", "B", "C"], "A", "Area Caves").is_empty(), "the three rooms open together")
	check(view.is_session() and view.room_id == "A" and view.session_rooms().size() == 3, "A is edited, B and C shown with it")
	check(canvas._context.size() == 2, "B and C show around it (%d)" % canvas._context.size())
	check((canvas._context.B as Node2D).position == Vector2(1152, 0) and (canvas._context.C as Node2D).position == Vector2(0, 648), "where they are on the map, from A")
	canvas.zoom = 0.5
	canvas.pan = Vector2(20, 20)
	canvas._apply_view()
	# Paint in A.
	var src: int = view.painter.get_atlas_sources()[0][0]
	view.painter.checkpoint()
	view.painter.place_tile("Terrain", Vector2i(3, 3), src, Vector2i.ZERO)
	view.painter.dirty = true
	var a_painter := view.painter
	# A press in B: B is edited now, and the press paints there.
	view.set_tool(MDSRoomCanvas.Tool.TERRAIN)
	canvas.shape = MDSTerrainShapes.Shape.BRUSH
	canvas.brush_size = 1
	var world_point := Vector2(1152 + 300, 300)
	var screen := canvas.local_to_screen(world_point - world.get_origin("A"))
	_press(screen, true)
	_press(screen, false)
	check(view.room_id == "B", "a press in B edits B (%s)" % view.room_id)
	check(canvas.local_to_screen(world_point - world.get_origin("B")).is_equal_approx(screen), "the view stays where it was: the same place on the map, the same place on screen")
	var b_cell := view.painter.cell_at("Terrain", Vector2(300, 300))
	check(view.painter.layers.Terrain.get_cell_source_id(b_cell) >= 0, "and the press painted in B, where it was")
	check(a_painter.dirty and a_painter.layers.Terrain.get_cell_source_id(Vector2i(3, 3)) >= 0, "A keeps its change, not saved yet")
	check(canvas._context.has("A") and a_painter.layers.Terrain.get_parent() == canvas._context.A, "A shows around B with its own tiles (unsaved too)")
	# Painting stops where another room is.
	canvas._apply([view.painter.cell_at("Terrain", Vector2(-300, 300)), view.painter.cell_at("Terrain", Vector2(600, 300))], false)
	check(view.painter.layers.Terrain.get_cell_source_id(view.painter.cell_at("Terrain", Vector2(-300, 300))) < 0, "B's painting stops where A is")
	check(view.painter.layers.Terrain.get_cell_source_id(view.painter.cell_at("Terrain", Vector2(600, 300))) >= 0, "and goes on inside B")
	# Each room its own undo.
	view.painter.undo()
	view.painter.undo()
	check(view.painter.layers.Terrain.get_cell_source_id(b_cell) < 0, "Ctrl+Z in B undoes B's painting")
	check(a_painter.layers.Terrain.get_cell_source_id(Vector2i(3, 3)) >= 0, "not A's")
	view.painter.redo()
	view.painter.dirty = true
	# Back to A: the same painter, its undo kept.
	check(view.activate_room("A") and view.painter == a_painter and a_painter.can_undo(), "back in A, its changes and undo are still there")
	# Save saves them all.
	check(view.save() == OK, "Save")
	check(not a_painter.dirty and not (view._painters.B as MDSRoomPainter).dirty, "saves A and B")
	var b_saved := (load_fresh(world.get_scene_path("B")) as PackedScene).instantiate()
	check((b_saved.get_node("Terrain") as TileMapLayer).get_cell_source_id(b_cell) >= 0, "B's tile is in its scene")
	b_saved.free()
	# Generate all: a cave in each room shown, each undoable on its own.
	check(view.generate_all(false) == 3, "Generate all makes a cave in each of the 3 rooms")
	for id in ["A", "B", "C"]:
		var p: MDSRoomPainter = view._painters[id]
		check(p.dirty and p.layers.Terrain.get_used_cells().size() > 100, "%s has its cave (%d tiles)" % [id, p.layers.Terrain.get_used_cells().size()])
	var c_tiles: PackedByteArray = (view._painters.C as MDSRoomPainter).layers.Terrain.tile_map_data
	view.generate_all(true)
	check((view._painters.C as MDSRoomPainter).layers.Terrain.tile_map_data != c_tiles, "New variation for all makes other caves")
	# < and > edit the next room.
	view._area_step(1)
	check(view.room_id == "B", "> edits the next room (%s)" % view.room_id)
	view._area_step(-2)
	check(view.room_id == "C", "< goes round (%s)" % view.room_id)
	# One room opened: no more rooms shown with it.
	view.close_room(false)
	check(not view.is_session() and canvas._context.is_empty() and view._painters.is_empty(), "closing lets go of them all")
	check(view.open_room(world, "A").is_empty() and not view.is_session() and canvas.session.is_empty(), "a room opened on its own is shown alone")
	# Saving it says it saved, and nothing else after.
	var said: Array[String] = []
	view.status_message.connect(func(t: String) -> void: said.append(t))
	view.painter.dirty = true
	check(view.save() == OK and not said.is_empty() and said[-1].begins_with("Saved"), "Save on one room says it saved (%s)" % (said[-1] if not said.is_empty() else ""))
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame

func _press(p: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = p
	canvas._gui_input(mb)
