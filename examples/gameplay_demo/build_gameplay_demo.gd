@tool
extends SceneTree
## Generates the 12-room gameplay demo world and game scene:
##   examples/gameplay_demo/gameplay_demo.mdsworld.json
##   examples/gameplay_demo/rooms/grove_*.tscn
##   examples/gameplay_demo/rooms/gardens_*.tscn
##   examples/gameplay_demo/game.tscn

const DEMO_DIR := "res://examples/gameplay_demo"
const ROOMS_DIR := "res://examples/gameplay_demo/rooms"
const WORLD_PATH := DEMO_DIR + "/gameplay_demo.mdsworld.json"
const GAME_PATH := DEMO_DIR + "/game.tscn"

func _init() -> void:
	build_all()
	quit(0)

static func build_all() -> MDSWorld:
	DirAccess.make_dir_recursive_absolute(ROOMS_DIR)
	var world := _build_world()
	_build_room_scenes(world)
	_build_game_scene(world)
	print("Gameplay demo successfully built at %s" % DEMO_DIR)
	return world

static func _build_world() -> MDSWorld:
	var w := MDSWorld.new()
	w.path = WORLD_PATH
	w.data.name = "Gameplay Demo"
	w.data.format = "mds_world"
	w.data.version = 1
	w.data.start_room = "Grove_01"
	w.data.settings = {
		"default_room_size": [1152, 648],
		"grid": 64,
		"save_distance_warn": 4,
	}
	w.data.areas["Mossgrove"] = {
		"title": "Mossgrove",
		"subtitle": "The ancient tangled forest",
		"color": "#4d784e",
		"weather": "rain",
		"background": "forest_canopy",
		"objective": "Defeat the Warden",
		"objective_done_when": "boss:Warden",
	}
	w.data.areas["Sunken Gardens"] = {
		"title": "The Sunken Gardens",
		"subtitle": "Ruins beneath the canopy",
		"color": "#3d6b7d",
		"weather": "cave_mist",
		"background": "deep_water",
		"objective": "Find the Wall Jump",
		"objective_done_when": "ability:wall_jump",
	}

	# 12 Rooms:
	# Grove_01: Start, Bench, Lore Tablet
	w.add_room("Grove_01", Rect2(0, 648, 1152, 648), 0, "Mossgrove")
	w.set_room_scene("Grove_01", ROOMS_DIR + "/grove_01.tscn")
	w.get_gates("Grove_01")["right1"] = {"pos": [1152, 500], "side": "right"}

	# Grove_02: Walkers, High ledge (requires double_jump)
	w.add_room("Grove_02", Rect2(1152, 648, 1152, 648), 0, "Mossgrove")
	w.set_room_scene("Grove_02", ROOMS_DIR + "/grove_02.tscn")
	w.get_gates("Grove_02")["left1"] = {"pos": [0, 500], "side": "left"}
	w.get_gates("Grove_02")["top1"] = {"pos": [576, 0], "side": "top"}
	w.get_gates("Grove_02")["right1"] = {"pos": [1152, 200], "side": "right", "requires": ["double_jump"]}

	# Grove_03: double_jump pickup
	w.add_room("Grove_03", Rect2(1152, 0, 1152, 648), 0, "Mossgrove")
	w.set_room_scene("Grove_03", ROOMS_DIR + "/grove_03.tscn")
	w.get_gates("Grove_03")["bot1"] = {"pos": [576, 648], "side": "bot"}

	# Grove_04: Spikes, Checkpoint, Breakable Wall, Health Fragment
	w.add_room("Grove_04", Rect2(2304, 648, 1152, 648), 0, "Mossgrove")
	w.set_room_scene("Grove_04", ROOMS_DIR + "/grove_04.tscn")
	w.get_gates("Grove_04")["left1"] = {"pos": [0, 200], "side": "left"}
	w.get_gates("Grove_04")["right1"] = {"pos": [1152, 500], "side": "right"}

	# Grove_05: Boss Warden, Boss Arena, Barrier (requires boss:Warden)
	w.add_room("Grove_05", Rect2(3456, 648, 1152, 648), 0, "Mossgrove")
	w.set_room_scene("Grove_05", ROOMS_DIR + "/grove_05.tscn")
	w.set_room_value("Grove_05", "boss", "Warden")
	w.set_room_value("Grove_05", "type", "boss")
	w.get_gates("Grove_05")["left1"] = {"pos": [0, 500], "side": "left"}
	w.get_gates("Grove_05")["right1"] = {"pos": [1152, 500], "side": "right", "requires": ["boss:Warden"]}

	# Grove_06: dash pickup, Bench
	w.add_room("Grove_06", Rect2(4608, 648, 1152, 648), 0, "Mossgrove")
	w.set_room_scene("Grove_06", ROOMS_DIR + "/grove_06.tscn")
	w.get_gates("Grove_06")["left1"] = {"pos": [0, 500], "side": "left"}
	w.get_gates("Grove_06")["right1"] = {"pos": [1152, 500], "side": "right"}

	# Grove_07: Long gap, Flyers, Lava, requires dash
	w.add_room("Grove_07", Rect2(5760, 648, 1152, 648), 0, "Mossgrove")
	w.set_room_scene("Grove_07", ROOMS_DIR + "/grove_07.tscn")
	w.get_gates("Grove_07")["left1"] = {"pos": [0, 500], "side": "left"}
	w.get_gates("Grove_07")["right1"] = {"pos": [1152, 500], "side": "right", "requires": ["dash"]}

	# Gardens_01: Locked door (item:red_key), Shop NPC
	w.add_room("Gardens_01", Rect2(6912, 648, 1152, 648), 0, "Sunken Gardens")
	w.set_room_scene("Gardens_01", ROOMS_DIR + "/gardens_01.tscn")
	w.get_gates("Gardens_01")["left1"] = {"pos": [0, 500], "side": "left"}
	w.get_gates("Gardens_01")["bot1"] = {"pos": [576, 648], "side": "bot"}
	w.get_gates("Gardens_01")["right1"] = {"pos": [1152, 500], "side": "right", "requires": ["item:red_key"]}

	# Gardens_02: Turret, Charger, red_key pickup
	w.add_room("Gardens_02", Rect2(6912, 1296, 1152, 648), 0, "Sunken Gardens")
	w.set_room_scene("Gardens_02", ROOMS_DIR + "/gardens_02.tscn")
	w.get_gates("Gardens_02")["top1"] = {"pos": [576, 0], "side": "top"}

	# Gardens_03: Bridge switch (flag:bridge_lowered)
	w.add_room("Gardens_03", Rect2(8064, 648, 1152, 648), 0, "Sunken Gardens")
	w.set_room_scene("Gardens_03", ROOMS_DIR + "/gardens_03.tscn")
	w.get_gates("Gardens_03")["left1"] = {"pos": [0, 500], "side": "left"}
	w.get_gates("Gardens_03")["right1"] = {"pos": [1152, 500], "side": "right", "requires": ["flag:bridge_lowered"]}

	# Gardens_04: wall_jump pickup, Bench
	w.add_room("Gardens_04", Rect2(9216, 648, 1152, 648), 0, "Sunken Gardens")
	w.set_room_scene("Gardens_04", ROOMS_DIR + "/gardens_04.tscn")
	w.get_gates("Gardens_04")["left1"] = {"pos": [0, 500], "side": "left"}
	w.get_gates("Gardens_04")["right1"] = {"pos": [1152, 500], "side": "right"}

	# Gardens_05: Ending trigger, requires wall_jump
	w.add_room("Gardens_05", Rect2(10368, 648, 1152, 648), 0, "Sunken Gardens")
	w.set_room_scene("Gardens_05", ROOMS_DIR + "/gardens_05.tscn")
	w.get_gates("Gardens_05")["left1"] = {"pos": [0, 500], "side": "left"}
	w.get_gates("Gardens_05")["top1"] = {"pos": [576, 0], "side": "top", "requires": ["wall_jump"]}

	# Gate Connections:
	w.connect_gates("Grove_01", "right1", "Grove_02", "left1")
	w.connect_gates("Grove_02", "top1", "Grove_03", "bot1")
	w.connect_gates("Grove_02", "right1", "Grove_04", "left1")
	w.connect_gates("Grove_04", "right1", "Grove_05", "left1")
	w.connect_gates("Grove_05", "right1", "Grove_06", "left1")
	w.connect_gates("Grove_06", "right1", "Grove_07", "left1")
	w.connect_gates("Grove_07", "right1", "Gardens_01", "left1")
	w.connect_gates("Gardens_01", "bot1", "Gardens_02", "top1")
	w.connect_gates("Gardens_01", "right1", "Gardens_03", "left1")
	w.connect_gates("Gardens_03", "right1", "Gardens_04", "left1")
	w.connect_gates("Gardens_04", "right1", "Gardens_05", "left1")

	w.set_start_room("Grove_01")
	w.save()
	MDSWorld._cache.erase(WORLD_PATH)
	return w

static func _build_room_scenes(world: MDSWorld) -> void:
	for id in world.get_room_ids():
		var scene_path: String = world.data.rooms[id].get("scene", "")
		var root := _create_room_node(world, id)
		MDSWorldSceneTools.apply_gate_nodes(world, id, root, true)
		_own(root, root)
		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, scene_path)
		root.free()

static func _create_room_node(world: MDSWorld, id: String) -> Node2D:
	var root := Node2D.new()
	root.name = id.to_pascal_case()

	# MapBounds guide
	var bounds := Node2D.new()
	bounds.name = "MapBounds"
	root.add_child(bounds)
	var rect := ReferenceRect.new()
	rect.name = "Rect1"
	rect.editor_only = true
	rect.size = Vector2(1152, 648)
	bounds.add_child(rect)

	# Base floor StaticBody2D
	var floor_body := StaticBody2D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = MDSGameplaySetup.bit("terrain")
	floor_body.collision_mask = 0
	root.add_child(floor_body)

	# Specific layouts and gameplay components
	match id:
		"Grove_01":
			# Normal floor across bottom
			_add_box_col(floor_body, Vector2(0, 560), Vector2(1152, 88))
			# Bench
			var bench := MDSBench.new()
			bench.name = "Bench"
			bench.position = Vector2(300, 560)
			root.add_child(bench)
			# Lore Tablet
			var lore := MDSLoreTablet.new()
			lore.name = "LoreTablet"
			lore.title = "Welcome to Mossgrove"
			lore.text = "Ancient powers lie deep within these woods. Leap into the canopies to seek them."
			lore.position = Vector2(650, 560)
			root.add_child(lore)

		"Grove_02":
			# Ground floor
			_add_box_col(floor_body, Vector2(0, 560), Vector2(800, 88))
			# High ledge (requires double jump to reach)
			_add_box_col(floor_body, Vector2(800, 260), Vector2(352, 388))
			# Walkers
			_add_walker(root, Vector2(350, 550))
			_add_walker(root, Vector2(550, 550))

		"Grove_03":
			# Floor
			_add_box_col(floor_body, Vector2(0, 560), Vector2(1152, 88))
			# double_jump pickup
			var dj := MDSAbilityPickup.new()
			dj.name = "AbilityPickup_DoubleJump"
			var dj_res: MDSAbilityData = load("res://addons/MetroidvaniaDeveloperSystem/gameplay/data/double_jump.tres")
			dj.ability = dj_res
			dj.position = Vector2(576, 500)
			root.add_child(dj)

		"Grove_04":
			# Floor with spike pit
			_add_box_col(floor_body, Vector2(0, 560), Vector2(350, 88))
			_add_box_col(floor_body, Vector2(750, 560), Vector2(402, 88))
			# Spikes in pit
			var spikes := MDSHazard.new()
			spikes.name = "Spikes"
			spikes.look = MDSHazard.Look.SPIKES
			spikes.size = Vector2(400, 40)
			spikes.position = Vector2(350, 600)
			root.add_child(spikes)
			# Checkpoint
			var cp := MDSCheckpoint.new()
			cp.name = "Checkpoint"
			cp.position = Vector2(250, 560)
			root.add_child(cp)
			# Breakable wall hiding health fragment
			var wall := MDSBreakable.new()
			wall.name = "BreakableWall"
			wall.kind = "wall"
			wall.size = Vector2(40, 100)
			wall.position = Vector2(900, 510)
			root.add_child(wall)
			var frag := MDSHealthUpgrade.new()
			frag.name = "HealthFragment"
			frag.position = Vector2(1000, 540)
			root.add_child(frag)

		"Grove_05":
			# Floor
			_add_box_col(floor_body, Vector2(0, 560), Vector2(1152, 88))
			# Boss Warden
			var boss := MDSBoss.new()
			boss.name = "Warden"
			boss.boss_name = "Warden"
			boss.position = Vector2(750, 520)
			root.add_child(boss)
			# Arena Doors
			var doors: Array[MDSArenaDoor] = []
			for x in [150, 1000]:
				var door := MDSArenaDoor.new()
				door.name = "Door%d" % x
				door.position = Vector2(x, 460)
				root.add_child(door)
				doors.append(door)
			# Boss Arena
			var arena := MDSBossArena.new()
			arena.name = "BossArena"
			arena.position = Vector2(576, 400)
			arena.size = Vector2(800, 350)
			root.add_child(arena)
			arena.boss = boss
			arena.doors = doors
			# Gate Barrier on exit
			var barrier := MDSGateBarrier.new()
			barrier.name = "BossBarrier"
			barrier.requires = PackedStringArray(["boss:Warden"])
			barrier.position = Vector2(1130, 480)
			_add_box_col(barrier, Vector2(0, -60), Vector2(30, 120))
			root.add_child(barrier)

		"Grove_06":
			# Floor
			_add_box_col(floor_body, Vector2(0, 560), Vector2(1152, 88))
			# Bench
			var bench := MDSBench.new()
			bench.name = "Bench"
			bench.position = Vector2(300, 560)
			root.add_child(bench)
			# dash pickup
			var dash := MDSAbilityPickup.new()
			dash.name = "AbilityPickup_Dash"
			var dash_res: MDSAbilityData = load("res://addons/MetroidvaniaDeveloperSystem/gameplay/data/dash.tres")
			dash.ability = dash_res
			dash.position = Vector2(600, 520)
			root.add_child(dash)

		"Grove_07":
			# Start ledge
			_add_box_col(floor_body, Vector2(0, 560), Vector2(250, 88))
			# End ledge
			_add_box_col(floor_body, Vector2(900, 560), Vector2(252, 88))
			# Lava pit across middle
			var lava := MDSLava.new()
			lava.name = "Lava"
			lava.position = Vector2(250, 560)
			lava.size = Vector2(650, 88)
			root.add_child(lava)
			# Flyer enemy over lava
			_add_flyer(root, Vector2(576, 350))

		"Gardens_01":
			# Floor
			_add_box_col(floor_body, Vector2(0, 560), Vector2(1152, 88))
			# Shop NPC
			var shop := MDSShop.new()
			shop.name = "Shopkeeper"
			shop.position = Vector2(400, 560)
			root.add_child(shop)
			# Locked Door requiring item:red_key
			var barrier := MDSGateBarrier.new()
			barrier.name = "RedKeyBarrier"
			barrier.requires = PackedStringArray(["item:red_key"])
			barrier.consume_items = true
			barrier.position = Vector2(1130, 480)
			_add_box_col(barrier, Vector2(0, -60), Vector2(30, 120))
			root.add_child(barrier)

		"Gardens_02":
			# Floor & platforms
			_add_box_col(floor_body, Vector2(0, 560), Vector2(1152, 88))
			_add_box_col(floor_body, Vector2(300, 400), Vector2(200, 20))
			# Enemies: Turret & Charger
			_add_turret(root, Vector2(400, 390))
			_add_charger(root, Vector2(650, 550))
			# red_key pickup
			var key := MDSPickup.new()
			key.name = "RedKeyPickup"
			var kdata := MDSItemData.new()
			kdata.id = "red_key"
			kdata.display_name = "Red Key"
			kdata.category = MDSItemData.Category.KEY
			key.item = kdata
			key.persistent = true
			key.position = Vector2(950, 520)
			root.add_child(key)

		"Gardens_03":
			# Floor with gap
			_add_box_col(floor_body, Vector2(0, 560), Vector2(450, 88))
			_add_box_col(floor_body, Vector2(700, 560), Vector2(452, 88))
			# Bridge Switch
			var sw := MDSSwitch.new()
			sw.name = "BridgeSwitch"
			sw.flag = "bridge_lowered"
			sw.trigger = MDSSwitch.Trigger.HIT
			sw.position = Vector2(350, 540)
			root.add_child(sw)
			# Gate barrier on right exit requiring flag:bridge_lowered
			var barrier := MDSGateBarrier.new()
			barrier.name = "BridgeBarrier"
			barrier.requires = PackedStringArray(["flag:bridge_lowered"])
			barrier.position = Vector2(1130, 480)
			_add_box_col(barrier, Vector2(0, -60), Vector2(30, 120))
			root.add_child(barrier)

		"Gardens_04":
			# Floor
			_add_box_col(floor_body, Vector2(0, 560), Vector2(1152, 88))
			# Bench
			var bench := MDSBench.new()
			bench.name = "Bench"
			bench.position = Vector2(300, 560)
			root.add_child(bench)
			# wall_jump pickup
			var wj := MDSAbilityPickup.new()
			wj.name = "AbilityPickup_WallJump"
			var wj_res: MDSAbilityData = load("res://addons/MetroidvaniaDeveloperSystem/gameplay/data/wall_jump.tres")
			wj.ability = wj_res
			wj.position = Vector2(700, 520)
			root.add_child(wj)

		"Gardens_05":
			# Floor & vertical walls for wall-jumping
			_add_box_col(floor_body, Vector2(0, 560), Vector2(1152, 88))
			_add_box_col(floor_body, Vector2(450, 100), Vector2(30, 460))
			_add_box_col(floor_body, Vector2(700, 100), Vector2(30, 460))
			# Ending trigger at top of chute
			var end_area := Area2D.new()
			end_area.name = "EndingTrigger"
			end_area.position = Vector2(576, 120)
			end_area.collision_layer = MDSGameplaySetup.bit("interact")
			end_area.collision_mask = MDSGameplaySetup.player_detect_mask()
			_add_box_col(end_area, Vector2(-60, -30), Vector2(120, 60))
			var end_script := GDScript.new()
			end_script.source_code = "@tool\nextends Area2D\nsignal demo_completed\nfunc _ready() -> void:\n\tbody_entered.connect(func(b: Node) -> void:\n\t\tif b.is_in_group(&\"player\"):\n\t\t\tset_meta(&\"demo_completed\", true)\n\t\t\tdemo_completed.emit()\n\t\t\tvar game := MDSWorldGame.instance\n\t\t\tif game:\n\t\t\t\tvar kit := MDSGameplay.find(game)\n\t\t\t\tif kit:\n\t\t\t\t\tkit.notice.emit(\"Demo Completed! Thank you for playing!\"))\n"
			end_script.reload()
			end_area.set_script(end_script)
			root.add_child(end_area)

	return root

static func _build_game_scene(world: MDSWorld) -> void:
	var err := MDSWorldSceneTools.create_game_scene(world, GAME_PATH, true)
	if err != OK:
		push_error("Failed to create game scene: %d" % err)

static func _add_box_col(parent: Node2D, pos: Vector2, size: Vector2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	cs.position = pos + size * 0.5
	parent.add_child(cs)
	return cs

static func _add_walker(parent: Node2D, pos: Vector2) -> Node:
	var walker_scene := load("res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/mds_walker.tscn") as PackedScene
	var enemy: Node = walker_scene.instantiate() if walker_scene else MDSEnemy.new()
	enemy.name = "Walker"
	enemy.position = pos
	parent.add_child(enemy)
	return enemy

static func _add_flyer(parent: Node2D, pos: Vector2) -> Node:
	var flyer_scene := load("res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/mds_flyer.tscn") as PackedScene
	var enemy: Node = flyer_scene.instantiate() if flyer_scene else MDSEnemy.new()
	enemy.name = "Flyer"
	enemy.position = pos
	parent.add_child(enemy)
	return enemy

static func _add_turret(parent: Node2D, pos: Vector2) -> Node:
	var turret_scene := load("res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/mds_turret.tscn") as PackedScene
	var enemy: Node = turret_scene.instantiate() if turret_scene else MDSEnemy.new()
	enemy.name = "Turret"
	enemy.position = pos
	parent.add_child(enemy)
	return enemy

static func _add_charger(parent: Node2D, pos: Vector2) -> Node:
	var charger_scene := load("res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/mds_charger.tscn") as PackedScene
	var enemy: Node = charger_scene.instantiate() if charger_scene else MDSEnemy.new()
	enemy.name = "Charger"
	enemy.position = pos
	parent.add_child(enemy)
	return enemy

static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		if not c.owner and c != root:
			c.owner = root
		_own(c, root)
