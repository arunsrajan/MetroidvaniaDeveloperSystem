@tool
extends SceneTree
## Generates the 12-room gameplay demo world and game scene:
##   examples/gameplay_demo/gameplay_demo.mdsworld.json
##   examples/gameplay_demo/rooms/grove_*.tscn
##   examples/gameplay_demo/rooms/gardens_*.tscn
##   examples/gameplay_demo/game.tscn
##
## The rooms are built with MDS's own tools, as the Room view does: each is blocked out with
## straight-edged freeform shapes (rock, one-way ledges) and the Gameplay Kit's objects, then goes
## through Convert to freeform ([MDSFreeformConverter]) and Decorate freeform
## ([MDSFreeformDecorator]) with the Mossgrove pack (Grove_*) or the Sunken Gardens pack
## (Gardens_*). Fixed seeds: a run always builds the same rooms.
##
## The blockouts are sized for the player's default movement ([MDSMovementConfig]: a jump of
## about 90 px, a double jump of about 180 px, a dash of 96 px): Grove_02's high ledge needs the
## double jump, Grove_07's lava cavern the dash and Gardens_05's shaft the wall jump.
## [code]KeepClear[/code] rectangles ([code]mds_protected[/code]) keep the converted rock out of
## the spaces those moves need.
##
##   godot --headless --path . --script res://examples/gameplay_demo/build_gameplay_demo.gd

const DEMO_DIR := "res://examples/gameplay_demo"
const ROOMS_DIR := "res://examples/gameplay_demo/rooms"
const WORLD_PATH := DEMO_DIR + "/gameplay_demo.mdsworld.json"
const GAME_PATH := DEMO_DIR + "/game.tscn"
const ROOM_SIZE := Vector2(1152, 648)
const SEED := 14
## How much converted rock grows (Convert to freeform's Growth): a little less than its default,
## the rooms being one screen each.
const GROWTH := 0.8

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

# --- Rooms ---------------------------------------------------------------------------------------

## Each room: blocked out and saved, then converted and decorated with its area's pack.
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
		var err := _dress_room(world, id, scene_path)
		if err != OK:
			push_error("Failed to dress room %s: %s" % [id, error_string(err)])

## The pack a room of [param area] is painted with: styles, stamps and the decorator's choices.
static func _pack(area: String) -> Dictionary:
	if area == "Sunken Gardens":
		var sg := "res://asset_packs/sunken_gardens/freeform/"
		return {
			"rock": sg + "styles/garden_limestone.freeform.tres",
			"ledge": sg + "styles/garden_ledge.freeform.tres",
			"stamps": sg + "sunken_gardens.stamps.tres",
			"hanging": "ivy",
			"floor": PackedStringArray(["grass", "flower", "fern"]),
			"structure": sg + "styles/sunken_ruin.freeform.tres",
			"structure_kinds": [MDSShapeGenerators.Kind.COLUMN, MDSShapeGenerators.Kind.ARCH, MDSShapeGenerators.Kind.GARDEN_WALL],
			"leaf": "leaf_bg",
			"front": sg + "styles/garden_foreground.freeform.tres",
		}
	var mg := "res://asset_packs/mossgrove/freeform/"
	return {
		"rock": mg + "styles/mossy_rock.freeform.tres",
		"ledge": "",
		"stamps": mg + "mossgrove.stamps.tres",
		"hanging": "hanging",
		"floor": PackedStringArray(["moss", "fern"]),
		"structure": mg + "styles/jungle_foliage.freeform.tres",
		"structure_kinds": [MDSShapeGenerators.Kind.MOUND, MDSShapeGenerators.Kind.STALACTITES],
		"leaf": "leaf",
		"front": mg + "styles/foreground_silhouette.freeform.tres",
	}

## Convert to freeform and Decorate freeform on the blocked-out room at [param path].
static func _dress_room(world: MDSWorld, id: String, path: String) -> Error:
	var pack := _pack(world.get_room_area(id))
	var painter := MDSRoomPainter.open(path, TileSet.new())
	if not painter:
		return ERR_CANT_OPEN
	var conv := MDSFreeformConverter.new()
	conv.rock_style = load(pack.rock)
	if not str(pack.ledge).is_empty():
		conv.ledge_style = load(pack.ledge)
	conv.growth = GROWTH
	conv.seed_value = SEED
	conv.keep_old = false
	conv.use_world_room(world, id)
	var report := conv.convert(painter)
	if not str(report.error).is_empty():
		push_error("%s: %s" % [id, report.error])
	for warning in report.warnings:
		print("%s: %s" % [id, warning])
	var deco := MDSFreeformDecorator.new()
	deco.stamp_set = load(pack.stamps)
	deco.hanging_category = pack.hanging
	deco.floor_categories = pack.floor
	deco.structure_style = load(pack.structure)
	deco.structure_kinds.assign(pack.structure_kinds)
	deco.leaf_category = pack.leaf
	deco.foreground_style = load(pack.front)
	# Foreground framing hangs a mass from the room's top down to the first rock it finds 200 px
	# in from each side; in these small rooms that hides doorways and ledges.
	deco.foreground = false
	deco.seed_value = SEED
	deco.use_world_room(world, id)
	deco.decorate(painter)
	var err := painter.save()
	painter.free_instance()
	return err

## A room's blockout, in its scene's coordinates (the room is 1152 x 648, its floors mostly at
## y 560): rock rectangles, one-way ledges and the KeepClear areas converted rock stays out of.
static func _layout(id: String) -> Dictionary:
	match id:
		"Grove_01":
			return {"rock": [Rect2(0, 560, 1152, 88), Rect2(0, 0, 1152, 72), Rect2(0, 0, 64, 648), Rect2(1088, 0, 64, 420)]}
		"Grove_02":
			# A climb of one-way ledges (single jumps) to the canopy hole above; on the right the
			# high ledge to Grove_04, 120 px over a hanging ledge 140 px over the floor: double
			# jumps only.
			return {
				"rock": [Rect2(0, 560, 1152, 88), Rect2(0, 0, 512, 40), Rect2(640, 0, 512, 72), Rect2(0, 0, 48, 420),
					Rect2(860, 300, 292, 348), Rect2(1088, 0, 64, 132)],
				"ledges": [Rect2(130, 490, 160, 24), Rect2(320, 420, 150, 24), Rect2(130, 350, 160, 24),
					Rect2(320, 280, 150, 24), Rect2(130, 210, 160, 24), Rect2(330, 140, 210, 24), Rect2(640, 420, 140, 24)],
				"keep_clear": [Rect2(100, 40, 412, 100), Rect2(780, 220, 80, 200), Rect2(860, 232, 228, 68)],
			}
		"Grove_03":
			return {"rock": [Rect2(0, 560, 512, 88), Rect2(640, 560, 512, 88), Rect2(0, 0, 1152, 80), Rect2(0, 0, 64, 648), Rect2(1088, 0, 64, 648)]}
		"Grove_04":
			# The way in is high on the left; spikes in a pit a jump wide; the way out a low passage
			# behind a breakable wall.
			return {
				"rock": [Rect2(0, 230, 260, 418), Rect2(0, 0, 64, 132), Rect2(0, 0, 1152, 64), Rect2(260, 560, 180, 88),
					Rect2(440, 640, 180, 8), Rect2(620, 560, 532, 88), Rect2(860, 64, 292, 386)],
				"keep_clear": [Rect2(420, 470, 220, 90), Rect2(860, 450, 292, 110)],
			}
		"Grove_05":
			# The arena: a high hall, lintels over its two doors.
			return {
				"rock": [Rect2(0, 560, 1152, 88), Rect2(0, 0, 1152, 160), Rect2(0, 0, 64, 420), Rect2(1088, 0, 64, 420),
					Rect2(120, 160, 60, 220), Rect2(970, 160, 60, 220)],
				"keep_clear": [Rect2(180, 300, 790, 260)],
			}
		"Grove_06":
			return {"rock": [Rect2(0, 560, 1152, 88), Rect2(0, 0, 1152, 80), Rect2(0, 0, 64, 420), Rect2(1088, 0, 64, 420)]}
		"Grove_07":
			# A lava cavern too low to jump in: stepping stones 80 px apart, dashed across.
			return {
				"rock": [Rect2(0, 560, 300, 88), Rect2(380, 560, 80, 88), Rect2(540, 560, 80, 88), Rect2(700, 560, 80, 88),
					Rect2(860, 560, 292, 88), Rect2(300, 630, 560, 18), Rect2(0, 0, 1152, 120), Rect2(260, 120, 640, 368),
					Rect2(0, 0, 64, 420), Rect2(1088, 0, 64, 420)],
				"keep_clear": [Rect2(230, 488, 700, 72)],
			}
		"Gardens_01":
			return {"rock": [Rect2(0, 560, 512, 88), Rect2(640, 560, 512, 88), Rect2(0, 0, 1152, 100), Rect2(0, 0, 64, 420), Rect2(1088, 0, 64, 420)]}
		"Gardens_02":
			# Down from Gardens_01 through the hole above; back up by garden ledges 130 px apart.
			return {
				"rock": [Rect2(0, 560, 1152, 88), Rect2(0, 0, 512, 40), Rect2(640, 0, 512, 72), Rect2(0, 0, 64, 648),
					Rect2(1088, 0, 64, 648)],
				"ledges": [Rect2(330, 430, 150, 24), Rect2(140, 300, 150, 24), Rect2(380, 170, 170, 24)],
				"keep_clear": [Rect2(100, 40, 412, 110)],
			}
		"Gardens_03":
			return {"rock": [Rect2(0, 560, 450, 88), Rect2(450, 640, 250, 8), Rect2(700, 560, 452, 88), Rect2(0, 0, 1152, 100),
				Rect2(0, 0, 64, 420), Rect2(1088, 0, 64, 420)]}
		"Gardens_04":
			return {"rock": [Rect2(0, 560, 1152, 88), Rect2(0, 0, 1152, 90), Rect2(0, 0, 64, 420), Rect2(1088, 0, 64, 420)]}
		"Gardens_05":
			# A low hall with a shaft 128 px wide going up from its middle: wall jumps only.
			return {
				"rock": [Rect2(0, 560, 1152, 88), Rect2(0, 0, 512, 400), Rect2(640, 0, 512, 400), Rect2(1088, 0, 64, 648)],
				"keep_clear": [Rect2(512, 0, 128, 400), Rect2(420, 400, 312, 160)],
			}
	return {}

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
	rect.size = ROOM_SIZE
	bounds.add_child(rect)

	# The blockout: straight-edged freeform shapes, converted by _dress_room().
	var layout := _layout(id)
	var style: MDSFreeformStyle = load(_pack(world.get_room_area(id)).rock)
	var group := Node2D.new()
	group.name = "Freeform"
	group.z_index = MDSRoomPainter.ITEM_GROUPS["Freeform"]
	root.add_child(group)
	var n := 0
	for r: Rect2 in layout.get("rock", []):
		n += 1
		_blockout_shape(group, "Rock%d" % n, r, style, false)
	n = 0
	for r: Rect2 in layout.get("ledges", []):
		n += 1
		_blockout_shape(group, "Ledge%d" % n, r, style, true)
	if not layout.get("keep_clear", []).is_empty():
		var keep := Node2D.new()
		keep.name = "KeepClear"
		root.add_child(keep)
		n = 0
		for r: Rect2 in layout.keep_clear:
			n += 1
			var area := ReferenceRect.new()
			area.name = "Area%d" % n
			area.editor_only = true
			area.border_color = Color(0.4, 0.9, 1.0, 0.6)
			area.position = r.position
			area.size = r.size
			area.add_to_group(&"mds_protected", true)
			keep.add_child(area)

	# Specific layouts and gameplay components
	match id:
		"Grove_01":
			var bench := MDSBench.new()
			bench.name = "Bench"
			bench.position = Vector2(300, 560)
			root.add_child(bench)
			var lore := MDSLoreTablet.new()
			lore.name = "LoreTablet"
			lore.title = "Welcome to Mossgrove"
			lore.text = "Ancient powers lie deep within these woods. Leap into the canopies to seek them."
			lore.position = Vector2(650, 560)
			root.add_child(lore)

		"Grove_02":
			_add_walker(root, Vector2(560, 542))
			_add_walker(root, Vector2(760, 542))

		"Grove_03":
			var dj := MDSAbilityPickup.new()
			dj.name = "AbilityPickup_DoubleJump"
			dj.ability = load("res://addons/MetroidvaniaDeveloperSystem/gameplay/data/double_jump.tres")
			dj.position = Vector2(300, 516)
			root.add_child(dj)

		"Grove_04":
			var spikes := MDSHazard.new()
			spikes.name = "Spikes"
			spikes.look = MDSHazard.Look.SPIKES
			spikes.size = Vector2(180, 40)
			spikes.position = Vector2(530, 620)
			root.add_child(spikes)
			var cp := MDSCheckpoint.new()
			cp.name = "Checkpoint"
			cp.position = Vector2(340, 560)
			root.add_child(cp)
			# The low passage out is shut by a breakable wall, the health fragment behind it.
			var wall := MDSBreakable.new()
			wall.name = "BreakableWall"
			wall.kind = "wall"
			wall.size = Vector2(40, 110)
			wall.position = Vector2(900, 505)
			root.add_child(wall)
			var frag := MDSHealthUpgrade.new()
			frag.name = "HealthFragment"
			frag.position = Vector2(1010, 530)
			root.add_child(frag)

		"Grove_05":
			var boss := MDSBoss.new()
			boss.name = "Warden"
			boss.boss_name = "Warden"
			boss.data = _warden_data()
			boss.attack_damage = 1
			boss.volley_count = 3
			boss.rest_time = 1.2
			boss.position = Vector2(720, 512)
			root.add_child(boss)
			var doors: Array[MDSArenaDoor] = []
			for x in [150, 1000]:
				var door := MDSArenaDoor.new()
				door.name = "Door%d" % x
				door.position = Vector2(x, 470)
				root.add_child(door)
				doors.append(door)
			var arena := MDSBossArena.new()
			arena.name = "BossArena"
			arena.position = Vector2(612, 420)
			arena.size = Vector2(704, 280)
			root.add_child(arena)
			arena.boss = boss
			arena.doors = doors
			var barrier := MDSGateBarrier.new()
			barrier.name = "BossBarrier"
			barrier.requires = PackedStringArray(["boss:Warden"])
			barrier.position = Vector2(1110, 498)
			_add_box_col(barrier, Vector2(-15, -62), Vector2(30, 124))
			root.add_child(barrier)

		"Grove_06":
			var bench := MDSBench.new()
			bench.name = "Bench"
			bench.position = Vector2(300, 560)
			root.add_child(bench)
			var dash := MDSAbilityPickup.new()
			dash.name = "AbilityPickup_Dash"
			dash.ability = load("res://addons/MetroidvaniaDeveloperSystem/gameplay/data/dash.tres")
			dash.position = Vector2(620, 516)
			root.add_child(dash)

		"Grove_07":
			# Lava under the stepping stones: falling in costs a health and puts the player back
			# on the ledge it left.
			var effects := Node2D.new()
			effects.name = "Effects"
			root.add_child(effects)
			var lava := MDSLava.new()
			lava.name = "Lava"
			lava.position = Vector2(300, 610)
			lava.size = Vector2(560, 60)
			lava.damage = 1.0
			effects.add_child(lava)
			_add_flyer(root, Vector2(1000, 300))

		"Gardens_01":
			var shop := MDSShop.new()
			shop.name = "Shopkeeper"
			shop.position = Vector2(300, 560)
			root.add_child(shop)
			var barrier := MDSGateBarrier.new()
			barrier.name = "RedKeyBarrier"
			barrier.requires = PackedStringArray(["item:red_key"])
			barrier.consume_items = true
			barrier.position = Vector2(1110, 498)
			_add_box_col(barrier, Vector2(-15, -62), Vector2(30, 124))
			root.add_child(barrier)

		"Gardens_02":
			# On the right wall, covering the key (the ledges are out of its range).
			_add_turret(root, Vector2(1062, 300))
			_add_charger(root, Vector2(780, 540))
			var key := MDSPickup.new()
			key.name = "RedKeyPickup"
			var kdata := MDSItemData.new()
			kdata.id = "red_key"
			kdata.display_name = "Red Key"
			kdata.category = MDSItemData.Category.KEY
			key.item = kdata
			key.persistent = true
			key.position = Vector2(990, 530)
			root.add_child(key)

		"Gardens_03":
			var sw := MDSSwitch.new()
			sw.name = "BridgeSwitch"
			sw.flag = "bridge_lowered"
			sw.trigger = MDSSwitch.Trigger.HIT
			sw.position = Vector2(350, 536)
			root.add_child(sw)
			var barrier := MDSGateBarrier.new()
			barrier.name = "BridgeBarrier"
			barrier.requires = PackedStringArray(["flag:bridge_lowered"])
			barrier.position = Vector2(1110, 498)
			_add_box_col(barrier, Vector2(-15, -62), Vector2(30, 124))
			root.add_child(barrier)

		"Gardens_04":
			var bench := MDSBench.new()
			bench.name = "Bench"
			bench.position = Vector2(300, 560)
			root.add_child(bench)
			var wj := MDSAbilityPickup.new()
			wj.name = "AbilityPickup_WallJump"
			wj.ability = load("res://addons/MetroidvaniaDeveloperSystem/gameplay/data/wall_jump.tres")
			wj.position = Vector2(700, 516)
			root.add_child(wj)

		"Gardens_05":
			# Ending trigger at the top of the shaft
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

## The Warden's stats: beaten by the player's default attacks (1 and 2 damage a hit) in five or
## six combos; it hurts 1 by touch.
static func _warden_data() -> MDSEnemyData:
	var d := MDSEnemyData.new()
	d.id = "warden"
	d.display_name = "Warden"
	d.stats = MDSCombatStats.make(18, 0, 1)
	d.currency_drop = Vector2i(40, 60)
	return d

static func _blockout_shape(parent: Node2D, shape_name: String, r: Rect2, style: MDSFreeformStyle, ledge: bool) -> void:
	var f := MDSFreeform.new()
	f.name = shape_name
	f.style = style
	f.smooth = false
	f.points = MDSGeometry.rect_polygon(r)
	if ledge:
		f.set_collision_override(MDSFreeformStyle.Role.PLATFORM, true)
	parent.add_child(f)

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
	parent.add_child(enemy, true)
	return enemy

static func _add_flyer(parent: Node2D, pos: Vector2) -> Node:
	var flyer_scene := load("res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/mds_flyer.tscn") as PackedScene
	var enemy: Node = flyer_scene.instantiate() if flyer_scene else MDSEnemy.new()
	enemy.name = "Flyer"
	enemy.position = pos
	parent.add_child(enemy, true)
	return enemy

static func _add_turret(parent: Node2D, pos: Vector2) -> Node:
	var turret_scene := load("res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/mds_turret.tscn") as PackedScene
	var enemy: Node = turret_scene.instantiate() if turret_scene else MDSEnemy.new()
	enemy.name = "Turret"
	enemy.position = pos
	parent.add_child(enemy, true)
	return enemy

static func _add_charger(parent: Node2D, pos: Vector2) -> Node:
	var charger_scene := load("res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/mds_charger.tscn") as PackedScene
	var enemy: Node = charger_scene.instantiate() if charger_scene else MDSEnemy.new()
	enemy.name = "Charger"
	enemy.position = pos
	parent.add_child(enemy, true)
	return enemy

static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		if not c.owner and c != root:
			c.owner = root
		_own(c, root)
