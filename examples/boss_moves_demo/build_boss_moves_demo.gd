@tool
extends SceneTree
## Generates the boss moves demo: a row of arenas, each with a fight from [MDSMoveRecipes], to play
## and judge by hand.
##   examples/boss_moves_demo/boss_moves_demo.mdsworld.json
##   examples/boss_moves_demo/rooms/*.tscn
##   examples/boss_moves_demo/tiles/cave_tileset.tres (and its PNG)
##   examples/boss_moves_demo/game.tscn
##
## Walking into a room starts its fight. Leave by the gate on the right for the next one. Fixed seeds.
##
##   godot --headless --path . --script res://examples/boss_moves_demo/build_boss_moves_demo.gd

const DEMO_DIR := "res://examples/boss_moves_demo"
const ROOMS_DIR := DEMO_DIR + "/rooms"
const TILES := DEMO_DIR + "/tiles/cave_tileset.tres"
const WORLD_PATH := DEMO_DIR + "/boss_moves_demo.mdsworld.json"
const GAME_PATH := DEMO_DIR + "/game.tscn"
const ROOM := Vector2(1728, 864)
const SEED := 57
## Room -> [its recipe, the boss's name, its height above the floor].
const FIGHTS := {
	"Swooper": ["swooper", "The Swooper", 300.0],
	"Twins": ["twin_swooper", "The Twins", 300.0],
	"Showman": ["showman", "The Showman", 60.0],
	"Duelist": ["duelist", "The Duelist", 60.0],
	"Possessed": ["possessed_duelist", "The Possessed", 60.0],
	"Matriarch": ["hanging_matriarch", "The Matriarch", 480.0],
}

func _init() -> void:
	build_all()
	quit(0)

static func build_all() -> MDSWorld:
	DirAccess.make_dir_recursive_absolute(ROOMS_DIR)
	DirAccess.make_dir_recursive_absolute(TILES.get_base_dir())
	MDSTilesetFactory.get_or_create(TILES, "cave")
	var world := _build_world()
	_build_rooms(world)
	_build_game_scene(world)
	print("Boss moves demo built at %s" % DEMO_DIR)
	return world

static func _build_world() -> MDSWorld:
	var w := MDSWorld.new()
	w.path = WORLD_PATH
	w.data.name = "Boss Moves Demo"
	w.data.settings = {"default_room_size": [ROOM.x, ROOM.y], "grid": 32, "room_tileset": TILES}
	w.data.areas["Arenas"] = {"title": "The Arenas", "subtitle": "One fight in each", "color": "#b07aff", "parallax": "deep_cavern"}
	var ids: Array = FIGHTS.keys()
	for i in ids.size():
		w.add_room(ids[i], Rect2(Vector2(ROOM.x * i, 0), ROOM), 0, "Arenas")
	for i in ids.size() - 1:
		w.add_gate(ids[i], Vector2(ROOM.x * (i + 1), 704), "right", "right1", false)
		w.add_gate(ids[i + 1], Vector2(ROOM.x * (i + 1), 704), "left", "left1", false)
		w.connect_gates(ids[i], "right1", ids[i + 1], "left1")
	for id in w.get_room_ids():
		w.set_room_scene(id, "%s/%s.tscn" % [ROOMS_DIR, id.to_lower()])
	w.set_start_room(ids[0])
	w.save()
	MDSWorld._cache.erase(WORLD_PATH)
	return w

## Each room: an arena as Generate cave makes it, its boss, and an MDSBossArena over all of it.
static func _build_rooms(world: MDSWorld) -> void:
	var tiles := load(TILES) as TileSet
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
		p.generate_cave(world, id, SEED + k, 0, 0, {}, {"cave": {"style": "arena"}})
		var fight: Array = FIGHTS[id]
		var boss := MDSMoveBoss.new()
		boss.name = "Boss"
		boss.recipe = fight[0]
		boss.boss_name = fight[1]
		boss.position = Vector2(ROOM.x * 0.7, 768.0 - float(fight[2]))
		p.root.add_child(boss)
		boss.owner = p.root
		var arena := MDSBossArena.new()
		arena.name = "Arena"
		arena.size = ROOM
		arena.position = ROOM * 0.5
		p.root.add_child(arena)
		arena.owner = p.root
		arena.boss = boss
		p.save()
		p.free_instance()
		k += 1

## The game scene, as Scenes > Create game scene makes it (with the Gameplay Kit).
static func _build_game_scene(world: MDSWorld) -> void:
	var err := MDSWorldSceneTools.create_game_scene(world, GAME_PATH, true)
	if err != OK:
		push_error("Failed to create the game scene: %s" % error_string(err))
		return
	var game := (load(GAME_PATH) as PackedScene).instantiate() as MDSWorldGame
	game.save_file = "user://boss_moves_demo_save.json"
	game.exploration_file = "user://boss_moves_demo_exploration.json"
	var packed := PackedScene.new()
	packed.pack(game)
	ResourceSaver.save(packed, GAME_PATH)
	game.free()

static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		if not c.owner and c != root:
			c.owner = root
		_own(c, root)
