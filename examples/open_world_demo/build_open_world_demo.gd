@tool
extends SceneTree
## Generates the open world demo, a 2.5D side-scroller under the sky:
##   examples/open_world_demo/open_world_demo.mdsworld.json
##   examples/open_world_demo/rooms/*.tscn
##   examples/open_world_demo/tiles/daylight_tileset.tres (and its PNG)
##   examples/open_world_demo/game.tscn
##
## Sunlit Meadows: four wide outdoor rooms in a row with no gates between them, generated with
## Generate cave's Outdoor style (open sky, rolling hills, ledges; the grounds meet at the rooms'
## edges). Under Meadow_02, a hole down into the Hollow, a cave of an S. Past Meadow_04, the Ridge
## Arena (Arena style), a Walker in it. The game streams the rooms around the player
## ([member MDSWorldGame.stream_rooms]), so the meadows are one long walk; 2.5D with the bright
## daylight style, the daylight tileset, parallax hills behind. Fixed seeds: a run always builds the
## same rooms.
##
##   godot --headless --path . --script res://examples/open_world_demo/build_open_world_demo.gd

const DEMO_DIR := "res://examples/open_world_demo"
const ROOMS_DIR := DEMO_DIR + "/rooms"
const TILES := DEMO_DIR + "/tiles/daylight_tileset.tres"
const WORLD_PATH := DEMO_DIR + "/open_world_demo.mdsworld.json"
const GAME_PATH := DEMO_DIR + "/game.tscn"
const MEADOW := Vector2(2304, 864)
const SEED := 21

func _init() -> void:
	build_all()
	quit(0)

static func build_all() -> MDSWorld:
	DirAccess.make_dir_recursive_absolute(ROOMS_DIR)
	DirAccess.make_dir_recursive_absolute(TILES.get_base_dir())
	MDSTilesetFactory.get_or_create(TILES, "daylight")
	var world := _build_world()
	_build_rooms(world)
	_build_game_scene(world)
	print("Open world demo built at %s" % DEMO_DIR)
	return world

static func _build_world() -> MDSWorld:
	var w := MDSWorld.new()
	w.path = WORLD_PATH
	w.data.name = "Open World Demo"
	w.data.settings = {
		"default_room_size": [MEADOW.x, MEADOW.y],
		"grid": 32,
		"room_tileset": TILES,
		"depth_25d": true,
		"depth_style": MDSDepthStyle.DAYLIGHT,
		"brightness": 1.1,
	}
	w.data.areas["Sunlit Meadows"] = {"title": "Sunlit Meadows", "subtitle": "Where the valley opens", "color": "#7cc043", "parallax": "misty_forest"}
	w.data.areas["Under Hollow"] = {"title": "Under Hollow", "color": "#6b5a3e", "parallax": "deep_cavern", "darkness": 0.25}
	w.data.areas["Ridge Arena"] = {"title": "Ridge Arena", "color": "#c0703f", "parallax": "dusk_mountains"}
	for i in 4:
		w.add_room("Meadow_%02d" % (i + 1), Rect2(Vector2(i * MEADOW.x, 0), MEADOW), 0, "Sunlit Meadows")
	w.add_room("Hollow_01", Rect2(Vector2(MEADOW.x + 288, MEADOW.y), Vector2(1728, 648)), 0, "Under Hollow")
	w.add_room("Ridge_Arena", Rect2(Vector2(4 * MEADOW.x, 0), Vector2(1728, MEADOW.y)), 0, "Ridge Arena")
	w.data.rooms["Ridge_Arena"]["type"] = "boss"
	# A hole in Meadow_02's ground down into the Hollow, and the Hollow's way back up.
	w.add_gate("Meadow_02", Vector2(MEADOW.x + 1152, MEADOW.y), "bot", "bot1", false)
	w.add_gate("Hollow_01", Vector2(MEADOW.x + 1152, MEADOW.y), "top", "top1", false)
	w.connect_gates("Meadow_02", "bot1", "Hollow_01", "top1")
	# The arena's door, at its floor.
	w.add_gate("Meadow_04", Vector2(4 * MEADOW.x, 704), "right", "right1", false)
	w.add_gate("Ridge_Arena", Vector2(4 * MEADOW.x, 704), "left", "left1", false)
	w.connect_gates("Meadow_04", "right1", "Ridge_Arena", "left1")
	for id in w.get_room_ids():
		w.set_room_scene(id, "%s/%s.tscn" % [ROOMS_DIR, id.to_lower()])
	w.set_start_room("Meadow_01")
	w.save()
	MDSWorld._cache.erase(WORLD_PATH)
	return w

## Each room: an empty scene with its gates, then generated as Generate cave does in the Room view.
static func _build_rooms(world: MDSWorld) -> void:
	var tiles := load(TILES) as TileSet
	var styles := {"Hollow_01": {"shape": "s", "style": "cave"}, "Ridge_Arena": {"style": "arena"}}
	var k := 0
	for id in world.get_room_ids():
		var path := "%s/%s.tscn" % [ROOMS_DIR, id.to_lower()]
		var root := Node2D.new()
		root.name = id
		MDSWorldSceneTools.apply_gate_nodes(world, id, root, true)
		_own(root, root)
		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, path)
		root.free()
		var p := MDSRoomPainter.open(path, tiles)
		var cave: Dictionary = styles.get(id, {"style": "outdoor"})
		p.generate_cave(world, id, SEED + k, 0, 0, {}, {"cave": cave})
		if not p.paths_joined:
			push_warning("Open world demo: %s's gates aren't all joined." % id)
		if id == "Ridge_Arena":
			var walker_scene := load("res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/mds_walker.tscn") as PackedScene
			if walker_scene:
				var walker := walker_scene.instantiate() as Node2D
				walker.name = "Walker"
				walker.position = Vector2(1100, 700)
				p.root.add_child(walker)
				walker.owner = p.root
		p.save()
		p.free_instance()
		k += 1

## The game scene, as Scenes > Create game scene makes it (with the Gameplay Kit), streaming the
## rooms around the player.
static func _build_game_scene(world: MDSWorld) -> void:
	var err := MDSWorldSceneTools.create_game_scene(world, GAME_PATH, true)
	if err != OK:
		push_error("Failed to create the game scene: %s" % error_string(err))
		return
	var game := (load(GAME_PATH) as PackedScene).instantiate() as MDSWorldGame
	game.stream_rooms = true
	game.save_file = "user://open_world_demo_save.json"
	game.exploration_file = "user://open_world_demo_exploration.json"
	var packed := PackedScene.new()
	packed.pack(game)
	ResourceSaver.save(packed, GAME_PATH)
	game.free()

static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		if not c.owner and c != root:
			c.owner = root
		_own(c, root)
