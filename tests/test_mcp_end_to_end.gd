extends "res://tests/mcp_test_case.gd"
## A small playable world built only through the MCP tools, in one batch, against the same world
## built the way the demo's build script does: if the tools drift from the authoring flow, this
## notices.

const MEADOW := Vector2(1536, 648)

func _run() -> void:
	start_server()
	var tiles := WORK + "/tiles/daylight.tres"
	var batch: Dictionary = await ok("mds_batch", {"ops": [
		{"tool": "mds_world_create", "args": {"path": WORLD, "name": "E2E", "settings": {"default_room_size": [MEADOW.x, MEADOW.y], "grid": 32, "room_tileset": tiles, "scene_folder": WORK + "/rooms"}}},
		{"tool": "mds_tileset_create", "args": {"path": tiles, "palette": "daylight"}},
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "Meadows", "title": "Meadows", "color": "#7cc043", "parallax": "misty_forest"}},
		{"tool": "mds_area_set", "args": {"world": WORLD, "area": "Hollow", "color": "#6b5a3e", "darkness": 0.25}},
		{"tool": "mds_room_add", "args": {"world": WORLD, "id": "Meadow_01", "rect": {"x": 0, "y": 0, "w": MEADOW.x, "h": MEADOW.y}, "area": "Meadows"}},
		{"tool": "mds_room_add", "args": {"world": WORLD, "id": "Hollow_01", "rect": {"x": 0, "y": MEADOW.y, "w": MEADOW.x, "h": MEADOW.y}, "area": "Hollow"}},
		{"tool": "mds_gate_add", "args": {"world": WORLD, "room": "Meadow_01", "pos": {"x": 768, "y": MEADOW.y}, "side": "bot", "name": "bot1", "snap_to_edge": false}},
		{"tool": "mds_gate_add", "args": {"world": WORLD, "room": "Hollow_01", "pos": {"x": 768, "y": MEADOW.y}, "side": "top", "name": "top1", "snap_to_edge": false}},
		{"tool": "mds_gate_connect", "args": {"world": WORLD, "a": "Meadow_01", "a_gate": "bot1", "b": "Hollow_01", "b_gate": "top1"}},
		{"tool": "mds_world_update", "args": {"world": WORLD, "start_room": "Meadow_01"}},
		{"tool": "mds_room_generate", "args": {"world": WORLD, "room": "Meadow_01", "style": "outdoor", "seed": 21}},
		{"tool": "mds_room_generate", "args": {"world": WORLD, "room": "Hollow_01", "style": "cave", "shape": "s", "seed": 22}},
		{"tool": "mds_room_place", "args": {"world": WORLD, "room": "Hollow_01", "kind": "enemy", "template": "walker", "pos": {"x": 800, "y": 500}, "name": "Walker"}},
		{"tool": "mds_enemy_configure", "args": {"world": WORLD, "room": "Hollow_01", "node": "Walker", "damage_type": "fire", "hurt_particles": "embers"}},
		{"tool": "mds_game_scene_create", "args": {"world": WORLD, "path": WORK + "/game.tscn", "stream_rooms": true, "save_file": "user://e2e_save.json"}},
	]})
	check(batch.undo_id > 0 and batch.changed.size() >= 5, "one step for all of it: %s" % [batch.get("changed")])
	check(batch.results[10].paths_joined and batch.results[11].paths_joined, "gates joined in both rooms")

	# By hand, as the demo's build script does.
	var by_hand := MDSWorld.new()
	by_hand.path = WORK + "/hand.mdsworld.json"
	by_hand.data.name = "E2E"
	by_hand.add_area("Meadows")
	by_hand.add_area("Hollow")
	by_hand.add_room("Meadow_01", Rect2(Vector2.ZERO, MEADOW), 0, "Meadows")
	by_hand.add_room("Hollow_01", Rect2(Vector2(0, MEADOW.y), MEADOW), 0, "Hollow")
	by_hand.add_gate("Meadow_01", Vector2(768, MEADOW.y), "bot", "bot1", false)
	by_hand.add_gate("Hollow_01", Vector2(768, MEADOW.y), "top", "top1", false)
	by_hand.connect_gates("Meadow_01", "bot1", "Hollow_01", "top1")

	var w := MDSWorld.load_world(WORLD)
	for id in by_hand.get_room_ids():
		check(w.get_room_bounds(id) == by_hand.get_room_bounds(id), "%s's bounds match" % id)
		check(w.get_room_area(id) == by_hand.get_room_area(id), "%s's area matches" % id)
		check(_canonical(w.get_gates(id)) == _canonical(by_hand.get_gates(id)), "%s's gates match: %s" % [id, w.get_gates(id)])
	check(w.get_start_room() == "Meadow_01" and w.get_areas().Hollow.darkness == 0.25, "the world's values")

	# The same cave as generate_cave called directly, on the same scene.
	var tileset := load(tiles) as TileSet
	var scene := w.get_scene_path("Hollow_01")
	var mine := _terrain(scene)
	var copy := WORK + "/rooms/copy.tscn"
	var root := Node2D.new()
	root.name = "Hollow_01"
	MDSWorldSceneTools.apply_gate_nodes(w, "Hollow_01", root, true)
	save_scene(root, copy)
	var p := MDSRoomPainter.open(copy, tileset)
	var rock: Array = p.get_terrains()[0]
	p.generate_cave(w, "Hollow_01", 22, rock[0], rock[1], {}, {"terrain": {"type": "terrain", "set": rock[0], "terrain": rock[1]}, "cave": {"style": "cave", "shape": "s"}})
	p.save()
	p.free_instance()
	check(_terrain(copy) == mine, "the tool makes the room the class makes")

	# It plays: the game scene loads with what was asked, the enemy is in its room.
	var game := MDSWorldSceneTools.load_fresh(WORK + "/game.tscn").instantiate() as MDSWorldGame
	check(game != null and game.stream_rooms and game.save_file == "user://e2e_save.json", "the game scene")
	if game:
		game.free()
	var room := MDSWorldSceneTools.load_fresh(scene).instantiate()
	check((room.get_node("Walker") as MDSEnemy).damage_type == "fire", "the enemy's look")
	room.free()

	var check_result: Dictionary = await ok("mds_room_check", {"world": WORLD, "rooms": ["Meadow_01", "Hollow_01"]})
	check(check_result.rooms.size() == 2, "rooms can be checked")
	var v: Dictionary = await ok("mds_validate", {"world": WORLD})
	check(not v.issues.any(func(i: Dictionary) -> bool: return i.severity == "error"), "no errors in the world: %s" % [v.issues])

	# One undo takes all of it back.
	await ok("mds_undo")
	check(not FileAccess.file_exists(WORLD) and not FileAccess.file_exists(WORK + "/game.tscn") and not FileAccess.file_exists(scene), "undo removes everything the batch made")
	end_server()

static func _canonical(value: Variant) -> String:
	return JSON.stringify(MDSMcpSchema.clean(value), "", true)

func _terrain(path: String) -> Dictionary:
	var painter := MDSRoomPainter.open_packed(MDSWorldSceneTools.load_fresh(path), path)
	var out := {}
	for c in painter.layer("Terrain").get_used_cells():
		out[c] = painter.layer("Terrain").get_cell_atlas_coords(c)
	painter.free_instance()
	return out
