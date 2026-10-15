extends "res://tests/test_case.gd"
## Generate cave and New variation put the room's gate nodes on the doorways they carve: each
## gate node at its opening's middle on the room's edge, its collision box across the opening
## (128 px along it, 48 across), clear of rock, a side gate's box standing on the ground kept
## under it. It is an edit of the scene: saving writes it, Ctrl+Z takes it back. The Room view
## says so, and names the gates with no node.

const DIR := TMP + "/gate_fit"
const ROOM := DIR + "/hall.tscn"

var world: MDSWorld

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var ts := MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	world = MDSWorld.new()
	world.path = DIR + "/fit.mdsworld.json"
	world.add_room("Hall", Rect2(0, 0, 1152, 648))
	var gates := {"left1": [[0, 400], "left"], "right1": [[1152, 240], "right"], "top1": [[432, 0], "top"], "bot1": [[700, 648], "bot"], "left2": [[0, 150], "left"]}
	for g in gates:
		world.get_gates("Hall")[g] = {"pos": gates[g][0], "side": gates[g][1]}
	var root := Node2D.new()
	root.name = "Hall"
	var t := TileMapLayer.new()
	t.name = "Terrain"
	t.tile_set = ts
	root.add_child(t)
	var gate_root := Node2D.new()
	gate_root.name = "Gates"
	root.add_child(gate_root)
	# Gate nodes off their doorways, with boxes of their own sizes (left2 has none).
	for g in ["left1", "right1", "top1", "bot1"]:
		var node := MDSWorldSceneTools.new_gate_node(world, "Hall", g)
		node.position = Vector2(gates[g][0][0], gates[g][0][1]) + Vector2(13, -9)
		(node.get_child(0) as CollisionShape2D).shape.size = Vector2(30, 90)
		gate_root.add_child(node)
	save_scene(root, ROOM)
	root.free()
	load_fresh(ROOM)
	world.set_room_scene("Hall", ROOM)
	_generated()
	await _room_view()

func _generated() -> void:
	var painter := MDSRoomPainter.open(ROOM)
	var before := painter.gate_boxes()
	painter.checkpoint()
	painter.generate_cave(world, "Hall", 5)
	var openings := painter.gate_openings
	check(openings.size() == 5, "generating carves a doorway for each of the 5 gates (%d)" % openings.size())
	var boxes := painter.gate_boxes()
	for g in ["left1", "right1", "top1", "bot1"]:
		var r: Rect2 = openings[g]
		check(boxes.has(g) and (boxes[g] as Rect2).is_equal_approx(r), "%s's gate node is moved onto its doorway (%s, want %s)" % [g, boxes.get(g), r])
		var along := r.size.y if g.begins_with("left") or g.begins_with("right") else r.size.x
		var across := r.size.x if g.begins_with("left") or g.begins_with("right") else r.size.y
		check(is_equal_approx(along, 128.0) and is_equal_approx(across, 48.0), "%s's box is across the opening: 128 px along it, 48 across (%s)" % [g, r.size])
		check(_rock_in(painter, r) == 0, "no rock in %s's box" % g)
		var edge: Vector2 = world.get_gate_local_pos("Hall", g)
		var on_edge := is_equal_approx(r.get_center().x, edge.x) if g.begins_with("left") or g.begins_with("right") else is_equal_approx(r.get_center().y, edge.y)
		check(on_edge and r.get_center().distance_to(edge) <= 32.0, "%s stays on the room's edge, by its map gate (%s, map %s)" % [g, r.get_center(), edge])
	for g in ["left1", "right1"]:
		var r: Rect2 = openings[g]
		var t: TileMapLayer = painter.layers["Terrain"]
		var under := t.local_to_map(Vector2(r.get_center().x + (40.0 if g == "left1" else -40.0), r.end.y + 8.0))
		check(t.get_cell_source_id(under) != -1, "%s's box stands on the ground kept under it" % g)
	check(painter.save() == OK, "the room saves")
	var saved := (load_fresh(ROOM) as PackedScene).instantiate()
	var nodes := {}
	MDSWorldSceneTools._collect_gate_nodes(saved, saved, nodes)
	var bot: Node2D = nodes["bot1"]
	check(bot.position == openings.bot1.get_center() and ((bot.get_child(0) as CollisionShape2D).shape as RectangleShape2D).size == Vector2(128, 48), "saved: the gate node is there, its box across the doorway (%s)" % bot.position)
	saved.free()
	check(painter.undo() and (painter.gate_boxes().bot1 as Rect2).is_equal_approx(before.bot1), "Ctrl+Z takes the gate nodes back where they were")
	painter.checkpoint()
	painter.generate_cave(world, "Hall", 99)
	check((painter.gate_boxes().top1 as Rect2).is_equal_approx(painter.gate_openings.top1), "a new variation puts them on its doorways again")
	painter.free_instance()

## Rock cells of the room inside [param r] (scene-local).
func _rock_in(painter: MDSRoomPainter, r: Rect2) -> int:
	var t: TileMapLayer = painter.layers["Terrain"]
	var n := 0
	var x := r.position.x + 8.0
	while x < r.end.x:
		var y := r.position.y + 8.0
		while y < r.end.y:
			if world.room_contains("Hall", world.get_origin("Hall") + Vector2(x, y)) and t.get_cell_source_id(t.local_to_map(Vector2(x, y))) != -1:
				n += 1
			y += 16.0
		x += 16.0
	return n

func _room_view() -> void:
	var view := MDSRoomView.new()
	view.size = Vector2(1200, 800)
	add_child(view)
	await get_tree().process_frame
	check(view.open_room(world, "Hall").is_empty(), "the Room view opens the room")
	var said: Array = []
	view.status_message.connect(func(t: String) -> void: said.append(t))
	view.generate(true)
	check(not said.is_empty() and said.back().contains("gate nodes on the new openings") and said.back().contains("no gate node for left2"), "New variation says the gate nodes moved, and which gate has none (%s)" % [said.back() if not said.is_empty() else ""])
	check((view.painter.gate_boxes().bot1 as Rect2).is_equal_approx(view.painter.gate_openings.bot1), "and they are on its doorways")
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame
