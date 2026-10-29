extends "res://tests/test_case.gd"
## An open world (MDSWorldGame.stream_rooms): the rooms around the player stay loaded beside the
## room it is in, so the camera looks across them and walking on into one makes it the current
## room in place, nothing reloaded, the player never moved (a gate at the shared side is walked
## through, not taken). Rooms far behind are freed; a node in a room loaded around the player
## knows its own room's object id, and with 2.5D on each has its depth.
##
## Room_A, Room_B and Room_C lie in a row, 1152 px wide each, a floor along their bottoms;
## right1 of Room_A leads to left1 of Room_B. Room_Far is far away. Room_B has a Gem.

const DIR := TMP + "/open_world"
const WORLD := DIR + "/open.mdsworld.json"
const W := 1152.0

var game: MDSWorldGame
var player: CharacterBody2D
var world: MDSWorld

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	world = _world()
	game = MDSWorldGame.new()
	game.world_file = WORLD
	game.save_file = ""
	game.exploration_file = ""
	game.load_on_start = false
	game.gate_cooldown = 0.0
	game.fade_time = 0.0
	game.stream_rooms = true
	game.depth_25d = 1
	game.starting_room = "Room_A"
	player = CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group(&"player", true)
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(32, 64)
	cs.shape = box
	player.add_child(cs)
	var script := GDScript.new()
	script.source_code = "extends CharacterBody2D\nvar run := 0.0\nfunc _physics_process(delta: float) -> void:\n\tvelocity.x = run\n\tvelocity.y = minf(velocity.y + 980.0 * delta, 900.0)\n\tmove_and_slide()\n"
	script.reload()
	player.set_script(script)
	var cam := Camera2D.new()
	player.add_child(cam)
	game.add_child(player)
	game.player = player
	game.camera = cam
	var rc := MDSRoomCamera.new()
	rc.camera = cam
	rc.target = player
	game.add_child(rc)
	game.room_camera = rc
	var loads: Array[String] = []
	game.room_loaded.connect(func(id: String) -> void: loads.append(id))
	add_child(game)
	await _until_loaded()
	await _until_streamed()
	check(game.current_room == "Room_A" and game.streamed.keys() == ["Room_B"], "in Room_A, Room_B is loaded beside it, Room_C and Room_Far aren't (%s)" % [game.streamed.keys()])
	var b: Node2D = game.streamed.get("Room_B")
	check(b and b.is_inside_tree() and b.position.is_equal_approx(world.get_origin("Room_B")), "in place on the map")
	check(b and b.get_node_or_null(^"Depth25D") is MDSDepth25D, "with its 2.5D")
	var gem := b.get_node_or_null(^"Gem") if b else null
	check(gem and str(gem.get_meta(&"id", "")) == "Room_B/Gem", "a node in it has its own room's object id (%s)" % [gem.get_meta(&"id", "") if gem else ""])
	var a_and_b := world.get_room_bounds("Room_A").merge(world.get_room_bounds("Room_B"))
	check(game.get_camera_bounds() == a_and_b and _limits(cam).is_equal_approx(a_and_b), "the camera looks across both (%s)" % _limits(cam))

	# Walk right, through right1, into Room_B.
	var a: Node2D = game.room_node
	player.global_position = Vector2(W - 200, 560)
	player.velocity = Vector2.ZERO
	player.set(&"run", 500.0)
	var last_x := player.global_position.x
	var jumped := false
	var changes: Array = []
	game.room_changed.connect(func(from: String, to: String) -> void: changes.append([from, to]))
	for i in 120:
		await get_tree().physics_frame
		if player.global_position.x < last_x - 1.0 or player.global_position.x > last_x + 40.0:
			jumped = true
		last_x = player.global_position.x
		if player.global_position.x > W + 200:
			break
	player.set(&"run", 0.0)
	await _until_loaded()
	check(game.current_room == "Room_B" and changes == [["Room_A", "Room_B"]], "walked on into Room_B (%s)" % [changes])
	check(game.room_node == b, "the room loaded beside it, not loaded again")
	check(not jumped, "the player walked on, never moved by the gate")
	check(game.streamed.get("Room_A") == a and is_instance_valid(a), "Room_A stays loaded, beside it now")
	await _until_streamed()
	check(game.streamed.has("Room_C") and not game.streamed.has("Room_Far"), "and Room_C comes in (%s)" % [game.streamed.keys()])
	check(_limits(cam).is_equal_approx(game.get_camera_bounds()) and game.get_camera_bounds().size.x == 3 * W, "the camera looks across all three")
	var gate := MDSGate.find_gate(a, "right1")
	check(gate and not gate.player_entered.is_connected(game._on_gate_entered), "Room_A's gates lead nowhere now")

	# On into Room_C: Room_A, far behind, goes.
	player.global_position = Vector2(2 * W + 300, 560)
	await _until_loaded()
	await get_tree().physics_frame
	await _until_loaded()
	check(game.current_room == "Room_C", "into Room_C")
	await get_tree().process_frame
	check(game.streamed.keys() == ["Room_B"] and not is_instance_valid(a), "Room_A, far behind, is freed (%s)" % [game.streamed.keys()])
	check(loads.count("Room_A") == 1, "nothing loaded again on the way")

	# Off: one room at a time, as before.
	game.stream_rooms = false
	game.load_room("Room_A", "", Vector2(300, 560))
	await _until_loaded()
	check(game.streamed.is_empty() and game.get_camera_bounds() == world.get_room_bounds("Room_A"), "without stream_rooms, only the room the player is in")
	# The fade back in ends first.
	await get_tree().create_timer(0.5).timeout
	game.queue_free()
	await get_tree().process_frame

func _limits(cam: Camera2D) -> Rect2:
	return Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top)

func _world() -> MDSWorld:
	var w := MDSWorld.new()
	w.path = WORLD
	w.data.areas["Plains"] = {"color": "#81b853"}
	for i in 3:
		w.add_room("Room_%s" % "ABC"[i], Rect2(i * W, 0, W, 648), 0, "Plains")
	w.add_room("Room_Far", Rect2(20 * W, 0, W, 648), 0, "Plains")
	w.get_gates("Room_A")["right1"] = {"pos": [W, 560], "side": "right"}
	w.get_gates("Room_B")["left1"] = {"pos": [0, 560], "side": "left"}
	w.connect_gates("Room_A", "right1", "Room_B", "left1")
	var gem_script := GDScript.new()
	gem_script.source_code = "extends Node2D\nfunc _ready() -> void:\n\tset_meta(&\"id\", MDSWorldGame.instance.object_id(self))\n"
	gem_script.reload()
	var gem_path := DIR + "/gem.gd"
	ResourceSaver.save(gem_script, gem_path)
	for id in w.get_room_ids():
		var root := Node2D.new()
		root.name = id
		var floor_body := StaticBody2D.new()
		floor_body.name = "Floor"
		var fs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(W, 48)
		fs.shape = shape
		fs.position = Vector2(W / 2.0, 624)
		floor_body.add_child(fs)
		root.add_child(floor_body)
		for g in w.get_gates(id):
			var gate := MDSWorldSceneTools.new_gate_node(w, id, g)
			gate.position = Vector2(w.get_gate_local_pos(id, g))
			gate.collision_mask = 1
			root.add_child(gate)
		if id == "Room_B":
			var gem := Node2D.new()
			gem.name = "Gem"
			gem.set_script(load(gem_path))
			root.add_child(gem)
		var path := "%s/%s.tscn" % [DIR, id.to_lower()]
		save_scene(root, path)
		root.free()
		w.set_room_scene(id, path)
	w.save()
	MDSWorld._cache.erase(WORLD)
	return w

func _until_loaded() -> void:
	for i in 600:
		if not game.current_room.is_empty() and not game.changing_room:
			return
		await get_tree().physics_frame

func _until_streamed() -> void:
	for i in 600:
		if game.is_stream_ready() and not game.changing_room:
			return
		await get_tree().physics_frame
