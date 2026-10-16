extends "res://tests/test_case.gd"
## Merging rooms on the map (MDSWorld.merge_rooms): one room keeps its key, origin and scene, the
## others' rectangles and outer gates join it (clashing names renamed), the gates between them
## go (kept as doors between its parts), and everything that named them names it: other rooms'
## gates, links (their gate ends too), the start room, objectives. One undo takes it back.
## Generate cave keeps walls where the old rooms met, with openings at their doors, and New
## variation changes the paths too. Their scenes come together: tiles, items and other nodes
## where they were, gate nodes and map guides made for the merged room.

const DIR := TMP + "/merge_rooms"

var world: MDSWorld
var ts: TileSet

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	ts = MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	_merge_data()
	_refusals()
	_shapes()
	_generation()
	_scenes()

## A, B right of it and C under it, D right of B outside the merge.
func _make_world() -> MDSWorld:
	var w := MDSWorld.new()
	w.path = DIR + "/merge.mdsworld.json"
	for r in [["A", Rect2(0, 0, 1152, 648)], ["B", Rect2(1152, 0, 1152, 648)], ["C", Rect2(0, 648, 1152, 648)], ["D", Rect2(2304, 0, 1152, 648)]]:
		w.add_room(r[0], r[1], 0, "Caves")
	w.get_gates("A")["right1"] = {"pos": [1152, 400], "side": "right"}
	w.get_gates("B")["left1"] = {"pos": [0, 400], "side": "left"}
	w.get_gates("A")["bot1"] = {"pos": [500, 648], "side": "bot"}
	w.get_gates("C")["top1"] = {"pos": [500, 0], "side": "top"}
	w.get_gates("B")["right1"] = {"pos": [1152, 300], "side": "right"}
	w.get_gates("D")["left1"] = {"pos": [0, 300], "side": "left"}
	w.get_gates("A")["left1"] = {"pos": [0, 300], "side": "left"}
	w.get_gates("C")["left1"] = {"pos": [0, 400], "side": "left"}
	w.connect_gates("A", "right1", "B", "left1")
	w.connect_gates("A", "bot1", "C", "top1")
	w.connect_gates("B", "right1", "D", "left1")
	w.add_link("C", "D")
	w.get_links()[0].a_gate = "left1"
	w.add_link("A", "B")
	w.set_start_room("C")
	w.add_area("Caves")
	w.set_area_value("Caves", "objective_done_when", "object:B/Chest")
	return w

func _merge_data() -> void:
	world = _make_world()
	var before: Dictionary = world.data.duplicate(true)
	world.checkpoint()
	var r := world.merge_rooms(["A", "B", "C"], "A")
	check(not r.has("error"), "three touching rooms merge (%s)" % r.get("error", ""))
	check(r.id == "A" and r.removed == ["B", "C"], "A is kept, B and C are absorbed (%s)" % [r.get("removed")])
	check(not world.has_room("B") and not world.has_room("C") and world.has_room("A"), "B and C are gone from the map")
	var rects := world.get_local_rects("A")
	check(rects.size() == 3 and rects.has(Rect2(1152, 0, 1152, 648)) and rects.has(Rect2(0, 648, 1152, 648)), "the merged room has the three rectangles, relative to A (%s)" % [rects])
	var gates := world.get_gates("A")
	check(gates.keys().size() == 3 and gates.has("left1") and gates.has("right1") and gates.has("left2"), "its gates are the outer ones: left1, right1 (B's), left2 (C's left1) (%s)" % [gates.keys()])
	check(world.get_gate_local_pos("A", "right1") == Vector2(2304, 300), "B's right1 is where it was on the map (%s)" % world.get_gate_local_pos("A", "right1"))
	check(world.get_gate_local_pos("A", "left2") == Vector2(0, 1048), "C's left1, now left2, is where it was (%s)" % world.get_gate_local_pos("A", "left2"))
	check(r.renamed.get("C/left1", "") == "left2" and r.renamed.get("B/right1", "") == "right1", "the renames are reported (%s)" % [r.renamed])
	check(r.dropped.size() == 4, "the four gates between the merged rooms go (%s)" % [r.dropped])
	var dl := world.get_gate("D", "left1")
	check(dl.get("to", "") == "A" and dl.get("to_gate", "") == "right1", "D's gate leads to the merged room's right1 (%s)" % [dl])
	check(gates.right1.get("to", "") == "D" and gates.right1.get("to_gate", "") == "left1", "and back")
	check(world.get_part_doors("A").size() == 2, "the merged room keeps the 2 doors between its parts (%s)" % [world.get_part_doors("A")])
	check(world.get_room_parts("A").size() == 3 and world.is_merged_room("A"), "and its 3 old rooms as parts")
	var links := world.get_links()
	check(links.size() == 1 and links[0].a == "A" and links[0].b == "D" and links[0].get("a_gate", "") == "left2", "the link C-D is A-D from left2; the link A-B (now inside) is gone (%s)" % [links])
	check(world.get_start_room() == "A", "the start room was C: it is the merged room")
	check(str(world.get_areas().Caves.objective_done_when) == "object:A/Chest", "the objective's object in B is in A (%s)" % world.get_areas().Caves.objective_done_when)
	check(_dangling() == 0, "no gate or link leads to a room or gate that is gone (%d)" % _dangling())
	world.undo()
	check(world.has_room("B") and world.has_room("C") and world.get_gates("A").size() == 3 and world.get_gate("D", "left1").to == "B", "one undo takes the whole merge back")
	check(JSON.stringify(world.data, "", true) == JSON.stringify(before, "", true), "exactly as it was")
	# Links follow gate renames and removals.
	world = _make_world()
	world.rename_gate("C", "left1", "left9")
	check(world.get_links()[0].get("a_gate", "") == "left9", "renaming a gate renames a link's end")
	world.remove_gate("C", "left9")
	check(not world.get_links()[0].has("a_gate"), "removing it clears it")

## Gates and links that name a room or gate that isn't there.
func _dangling() -> int:
	var n := 0
	for id in world.get_room_ids():
		for g: Dictionary in world.get_gates(id).values():
			var to := str(g.get("to", ""))
			if not to.is_empty() and not world.has_gate(to, str(g.get("to_gate", ""))):
				n += 1
	for link: Dictionary in world.get_links():
		for end in ["a", "b"]:
			if not world.has_room(str(link[end])) or (link.has(end + "_gate") and not world.has_gate(str(link[end]), str(link[end + "_gate"]))):
				n += 1
	return n

func _refusals() -> void:
	world = _make_world()
	check(world.merge_rooms(["A"]).has("error"), "one room doesn't merge")
	check(world.merge_rooms(["A", "Nope"]).has("error"), "a missing room doesn't merge")
	world.data.rooms.B.layer = 1
	check(world.merge_rooms(["A", "B"]).has("error"), "rooms of different layers don't merge")
	check(world.has_room("B"), "and nothing changed")
	world.data.rooms.B.layer = 0
	check(world.merge_rooms(["A", "B"], "C").has("error"), "the kept room must be one of them")
	# Merging a merged room again keeps all the old parts.
	var r := world.merge_rooms(["A", "B"])
	check(r.id == "A" and world.get_room_parts("A").size() == 2, "A and B merge into A")
	r = world.merge_rooms(["C", "A"], "C")
	check(r.id == "C" and world.get_room_parts("C").size() == 3, "merging it with C keeps 3 parts (%d)" % world.get_room_parts("C").size())
	check(world.get_part_doors("C").size() == 2, "and both old doors (%d)" % world.get_part_doors("C").size())
	check(world.get_local_rects("C").has(Rect2(0, -648, 1152, 648)), "relative to C's origin now")

func _shapes() -> void:
	world = _make_world()
	world.set_room_shape("A", [PackedVector2Array([Vector2(0, 0), Vector2(1152, 0), Vector2(1152, 648), Vector2(200, 648), Vector2(0, 400)])])
	world.merge_rooms(["A", "B"])
	check(world.has_room_shape("A"), "a room with a curved outline keeps one when merged")
	var poly: Array[PackedVector2Array] = world.get_room_shape("A")
	check(poly.size() == 1 and MDSGeometry.point_in_any(poly, Vector2(2000, 300)) and not MDSGeometry.point_in_any(poly, Vector2(20, 640)), "it is the union of both outlines (%d polygons)" % poly.size())
	world = _make_world()
	world.merge_rooms(["A", "B"])
	check(not world.has_room_shape("A"), "rooms without outlines merge into one without")

func _painter_for(id: String) -> MDSRoomPainter:
	var path := DIR + "/%s.tscn" % id.to_lower()
	MDSWorldSceneTools.create_scene_for_room(world, id, path)
	load_fresh(path)
	return MDSRoomPainter.open(path, ts)

func _generation() -> void:
	world = _make_world()
	world.merge_rooms(["A", "B"])
	var painter := _painter_for("A")
	painter.generate_cave(world, "A", 11)
	var solid := _wall_cells(painter)
	painter.generate_cave(world, "A", 11, 0, 0, {}, {"parts": false})
	var open_cave := _wall_cells(painter)
	check(solid >= 12, "with parts, a wall stands where A and B met (%d of 16 cells solid)" % solid)
	check(open_cave < solid, "without, it is one open cave (%d)" % open_cave)
	painter.generate_cave(world, "A", 11)
	var door: Vector2 = world.get_part_doors("A")[0].pos
	var dc := painter.cell_at("Terrain", door)
	var open_door := 0
	for a in range(-2, 2):
		for dx in range(-3, 4):
			if painter.layers.Terrain.get_cell_source_id(dc + Vector2i(dx, a)) < 0:
				open_door += 1
	check(open_door >= 24, "the wall has an opening where their door was (%d of 28 open)" % open_door)
	var first: PackedByteArray = painter.layers.Terrain.tile_map_data
	painter.generate_cave(world, "A", 11 + 7919)
	check(painter.layers.Terrain.tile_map_data != first, "New variation (another seed) makes another cave")
	painter.free_instance()

## Solid cells in the two columns where A and B meet, away from their door (rows 2-9).
func _wall_cells(painter: MDSRoomPainter) -> int:
	var n := 0
	for y in range(2, 10):
		for x in [35, 36]:
			if painter.layers.Terrain.get_cell_source_id(Vector2i(x, y)) >= 0:
				n += 1
	return n

func _scenes() -> void:
	world = _make_world()
	for id in ["A", "B"]:
		var p := _painter_for(id)
		var src: int = p.get_atlas_sources()[0][0]
		p.place_tile("Terrain", Vector2i(5, 5), src, Vector2i.ZERO)
		p.add_freeform(PackedVector2Array([Vector2(100, 100), Vector2(200, 100), Vector2(150, 200)]), MDSFreeformStyle.new())
		p.save()
		p.free_instance()
	# Something placed in B: a marker.
	var b_path := world.get_scene_path("B")
	var b_packed := load_fresh(b_path) as PackedScene
	var b_root := b_packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var marker := Marker2D.new()
	marker.name = "Spawn"
	marker.position = Vector2(300, 200)
	b_root.add_child(marker)
	marker.owner = b_root
	MDSWorldSceneTools.repack_safely(b_root, b_packed, b_path)
	b_root.free()
	var r := world.merge_rooms(["A", "B"], "A")
	var got := MDSWorldSceneTools.combine_room_scenes(world, "A", r.sources, ts)
	check(got.error == OK, "B's scene comes into A's (%s)" % MDSWorldSceneTools.last_error)
	check(got.tiles == 1 and got.items == 1 and got.nodes == 1, "its tile, shape and marker (%s)" % [got])
	var drop: PackedStringArray = []
	for d: String in r.dropped:
		if d.begins_with("A/"):
			drop.append(d.get_slice("/", 1))
	check(MDSWorldSceneTools.prepare_merged_scene(world, "A", drop) == OK, "A's scene is made ready for the merged room")
	var root := (load_fresh(world.get_scene_path("A")) as PackedScene).instantiate()
	var terrain := root.get_node("Terrain") as TileMapLayer
	check(terrain.get_cell_source_id(Vector2i(5, 5)) >= 0 and terrain.get_cell_source_id(Vector2i(41, 5)) >= 0, "A's tile and B's (36 cells right) are both there")
	var spawn := root.get_node_or_null("Spawn") as Marker2D
	check(spawn != null and spawn.position == Vector2(1452, 200), "B's marker is where it was on the map (%s)" % (spawn.position if spawn else "missing"))
	var shapes := root.find_children("*", "MDSFreeform", true, false)
	check(shapes.size() == 2, "both rooms' shapes are in it (%d)" % shapes.size())
	var gate_nodes: Dictionary = {}
	MDSWorldSceneTools._collect_gate_nodes(root, root, gate_nodes)
	check(gate_nodes.has("left1") and gate_nodes.has("right1") and gate_nodes.has("bot1") and gate_nodes.size() == 3, "its gate nodes are the merged room's gates: left1, bot1, right1 (%s)" % [gate_nodes.keys()])
	check(gate_nodes.has("right1") and MDSWorldSceneTools._local_transform(gate_nodes.right1, root).origin.x == 2304.0, "right1 (B's) is at B's right side, not where A's right1 was")
	var guides := root.get_node("MapBounds").get_children()
	check(guides.size() == 2, "its map guides are the merged room's 2 rectangles (%d)" % guides.size())
	root.free()
