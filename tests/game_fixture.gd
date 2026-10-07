extends RefCounted
## A small world for the runtime tests, written to tests/tmp:
##
##   Garden_01 --right1/left1-- Garden_02 --right1/left1-- Crypt_01
##   (area Gardens)              (Gardens)                  (Crypt, dark)
##   door1 <------------------- link ----------------------> door1
##
## Garden_01 has a Guard (enemy). Garden_02 has a Follower (carry_over) by right1 and a
## barrier on right1 that needs "crypt_key". Crypt_01 has a Bat (enemy) and an interact
## door. Areas have titles, music, objectives; the Crypt is dark.

const DIR := "res://tests/tmp/world"
const WORLD := DIR + "/test.idpworld.json"
const FOLLOWER := DIR + "/follower.tscn"
const MUSIC_A := DIR + "/music_gardens.tres"
const MUSIC_B := DIR + "/music_crypt.tres"
const BOSS := DIR + "/music_boss.tres"

static func build() -> MDSWorld:
	DirAccess.make_dir_recursive_absolute(DIR)
	for p in [MUSIC_A, MUSIC_B, BOSS]:
		ResourceSaver.save(_wav(p.length()), p)
	_save_follower()
	var world := MDSWorld.new()
	world.path = WORLD
	world.data.areas["Gardens"] = {"color": "#5a8a3c", "title": "The Sunken Gardens", "subtitle": "Where the old city drowned",
		"music": MUSIC_A, "music_volume_db": -6.0, "objective": "Find the crypt key", "objective_done_when": "ability:crypt_key"}
	world.data.areas["Crypt"] = {"color": "#6a5a8a", "title": "The Crypt", "music": MUSIC_B, "boss_music": BOSS, "darkness": 0.6,
		"objective": "Defeat the Warden", "objective_done_when": "boss:Warden"}
	var g1 := world.add_room("Garden_01", Rect2(0, 0, 1152, 648), 0, "Gardens")
	var g2 := world.add_room("Garden_02", Rect2(1152, 0, 1152, 648), 0, "Gardens")
	var c1 := world.add_room("Crypt_01", Rect2(2304, 0, 1152, 648), 0, "Crypt")
	world.get_gates(g1)["right1"] = {"pos": [1152, 520], "side": "right"}
	world.get_gates(g1)["door1"] = {"pos": [300, 540], "side": "door"}
	world.get_gates(g2)["left1"] = {"pos": [0, 520], "side": "left"}
	world.get_gates(g2)["right1"] = {"pos": [1152, 520], "side": "right"}
	world.get_gates(c1)["left1"] = {"pos": [0, 520], "side": "left"}
	world.get_gates(c1)["door1"] = {"pos": [800, 540], "side": "door"}
	world.connect_gates(g1, "right1", g2, "left1")
	world.connect_gates(g2, "right1", c1, "left1")
	world.data.links.append({"a": g1, "b": c1, "a_gate": "door1", "b_gate": "door1", "note": "Old lift", "requires": []})
	world.set_start_room(g1)
	for id in [g1, g2, c1]:
		var path := "%s/%s.tscn" % [DIR, id.to_lower()]
		var root := _room(world, id)
		var packed := PackedScene.new()
		_own(root, root)
		packed.pack(root)
		ResourceSaver.save(packed, path)
		root.free()
		world.set_room_scene(id, path)
	world.save()
	MDSWorld._cache.erase(WORLD)
	return world

static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		if not c.owner:
			c.owner = root
		if c.scene_file_path.is_empty():
			_own(c, root)

static func _wav(seed_len: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = 11025
	var data := PackedByteArray()
	data.resize(11025 * 2)
	for i in data.size():
		data[i] = 128 + (i * seed_len) % 3
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = data.size()
	return w

static func _save_follower() -> void:
	var f := CharacterBody2D.new()
	f.name = "Follower"
	f.add_to_group(&"carry_over", true)
	f.add_to_group(&"enemy", true)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(30, 50)
	cs.shape = r
	f.add_child(cs)
	cs.owner = f
	var packed := PackedScene.new()
	packed.pack(f)
	ResourceSaver.save(packed, FOLLOWER)
	f.free()

static func _room(world: MDSWorld, id: String) -> Node2D:
	var root := Node2D.new()
	root.name = id.to_pascal_case()
	var floor_body := StaticBody2D.new()
	floor_body.name = "Floor"
	root.add_child(floor_body)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(1400, 72)
	cs.shape = r
	cs.position = Vector2(576, 612)
	floor_body.add_child(cs)
	var gates := Node2D.new()
	gates.name = "Gates"
	root.add_child(gates)
	for g in world.get_gates(id):
		var gate := MDSWorldSceneTools.new_gate_node(world, id, g)
		gate.position = world.get_gate_local_pos(id, g)
		if g == "door1":
			gate.mode = MDSGate.Mode.INTERACT
			gate.link = true
		gates.add_child(gate)
	match id:
		"Garden_01":
			var guard := CharacterBody2D.new()
			guard.name = "Guard"
			guard.position = Vector2(700, 540)
			guard.add_to_group(&"enemy", true)
			root.add_child(guard)
		"Garden_02":
			var follower := (load(FOLLOWER) as PackedScene).instantiate()
			follower.position = Vector2(1000, 540)
			root.add_child(follower)
			var barrier := MDSGateBarrier.new()
			barrier.name = "Barrier"
			barrier.requires = PackedStringArray(["crypt_key"])
			barrier.position = Vector2(1100, 500)
			var bs := CollisionShape2D.new()
			var br := RectangleShape2D.new()
			br.size = Vector2(32, 160)
			bs.shape = br
			barrier.add_child(bs)
			root.add_child(barrier)
		"Crypt_01":
			var bat := CharacterBody2D.new()
			bat.name = "Bat"
			bat.position = Vector2(500, 300)
			bat.add_to_group(&"enemy", true)
			root.add_child(bat)
	return root

## A game for the world: a player with a capsule and camera, UI with title, music, banner and
## map. Add it to the tree and await [signal MDSWorldGame.room_loaded].
static func make_game(exploration := "") -> MDSWorldGame:
	var game := MDSWorldGame.new()
	game.world_file = WORLD
	game.fade_time = 0.0
	game.gate_cooldown = 0.0
	game.exploration_file = exploration
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group(&"player", true)
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 16
	cap.height = 64
	cs.shape = cap
	player.add_child(cs)
	game.add_child(player)
	game.player = player
	var ui := CanvasLayer.new()
	ui.name = "UI"
	game.add_child(ui)
	var title := MDSAreaTitle.new()
	title.name = "Title"
	ui.add_child(title)
	var banner := MDSObjectiveBanner.new()
	banner.name = "Banner"
	ui.add_child(banner)
	var map := MDSWorldMapView.new()
	map.name = "Map"
	map.world_file = WORLD
	ui.add_child(map)
	game.map_view = map
	var music := MDSMusic.new()
	music.name = "Music"
	music.crossfade_time = 0.2
	music.boss_fade_in = 0.2
	game.add_child(music)
	return game
