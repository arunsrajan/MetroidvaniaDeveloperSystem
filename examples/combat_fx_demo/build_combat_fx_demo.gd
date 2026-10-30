@tool
extends SceneTree
## Generates the combat effects demo: a Metroidvania world where every hit and hurt throws colored
## particles and plays its effects.
##   examples/combat_fx_demo/combat_fx_demo.mdsworld.json
##   examples/combat_fx_demo/rooms/*.tscn
##   examples/combat_fx_demo/tiles/cave_tileset.tres (and its PNG)
##   examples/combat_fx_demo/game.tscn
##
## Two arenas (Generate cave's Arena style) side by side. Six enemies, each set up in its
## inspector ([MDSEnemy]'s Hits and hurts): what its attacks do (fire, shock, ice, poison...), the
## colors of their effects, and the particles flying off it when the player hits it, in a palette
## of its own, glowing as much as it says:
## - Prism Arena: an Ember Crawler (fire; embers), a Prism Moth (petals in every color), a Crystal
##   Golem (crystal shards, glowing strongly).
## - Storm Hall: a Storm Beetle (shock; sparks of white, blue and gold), an Ink Slime (poison; dark
##   ink, no glow), a Frost Eye (ice shots; snowflakes).
## The player's own colors (gold effects, the particles of its blows, the heart shards it loses when
## hurt) are set by [code]combat_colors.gd[/code], a node of the game scene. Fixed seeds.
##
##   godot --headless --path . --script res://examples/combat_fx_demo/build_combat_fx_demo.gd

const DEMO_DIR := "res://examples/combat_fx_demo"
const ROOMS_DIR := DEMO_DIR + "/rooms"
const TILES := DEMO_DIR + "/tiles/cave_tileset.tres"
const WORLD_PATH := DEMO_DIR + "/combat_fx_demo.mdsworld.json"
const GAME_PATH := DEMO_DIR + "/game.tscn"
const ROOM := Vector2(1728, 864)
## Where the arenas' floors are (px from the room's top): Generate cave's Arena puts it 3 tiles up.
const FLOOR_Y := 768.0
const SEED := 33
const TEMPLATES := "res://addons/MetroidvaniaDeveloperSystem/gameplay/enemies/templates/"

## Room -> its enemies: [name, template, x, y (0: on the floor), settings].
const ENEMIES := {
	"Prism_Arena": [
		["Ember_Crawler", "mds_walker", 520.0, 0.0, {"damage_type": "fire", "attack_color": Color("#fff1a8"), "attack_glow": Color("#ff6a1a"), "hurt_particles": "embers", "particle_palette": [Color("#fff1a8"), Color("#ffb03a"), Color("#ff5a1a"), Color("#e8261a")], "particle_glow": 1.5, "body_color": Color("#e0632a")}],
		["Prism_Moth", "mds_flyer", 900.0, 470.0, {"hurt_particles": "petals", "particle_palette": [Color("#ff5a7a"), Color("#ffd25a"), Color("#5affb0"), Color("#5ab8ff"), Color("#c77aff")], "particle_glow": 1.2, "particle_size": 0.8, "attack_glow": Color("#ff7ad8"), "body_color": Color("#c77aff")}],
		["Crystal_Golem", "mds_charger", 1320.0, 0.0, {"damage_type": "earth", "hurt_particles": "crystal_shards", "particle_palette": [Color("#8ff4ff"), Color("#b78cff"), Color("#ff9ae0")], "particle_glow": 2.0, "particle_size": 1.6, "attack_glow": Color("#8ff4ff"), "body_color": Color("#6fa8c8")}],
	],
	"Storm_Hall": [
		["Storm_Beetle", "mds_walker", 520.0, 0.0, {"damage_type": "shock", "hurt_particles": "electric_sparks", "particle_palette": [Color("#ffffff"), Color("#7fd2ff"), Color("#ffe14a")], "particle_glow": 2.0, "body_color": Color("#3a5aa8")}],
		["Ink_Slime", "mds_walker", 900.0, 0.0, {"damage_type": "poison", "hurt_particles": "ink_drops", "particle_palette": [Color("#3a1a5a"), Color("#1a8a8a"), Color("#5a2a8a")], "particle_glow": 0.0, "particle_size": 1.4, "body_color": Color("#2a6a5a")}],
		["Frost_Eye", "mds_turret", 1400.0, 0.0, {"damage_type": "ice", "hurt_particles": "snowflakes", "particle_palette": [Color("#ffffff"), Color("#a8dcff"), Color("#6fc8ff")], "particle_glow": 0.8, "body_color": Color("#8fd8ff")}],
	],
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
	print("Combat effects demo built at %s" % DEMO_DIR)
	return world

static func _build_world() -> MDSWorld:
	var w := MDSWorld.new()
	w.path = WORLD_PATH
	w.data.name = "Combat FX Demo"
	w.data.settings = {"default_room_size": [ROOM.x, ROOM.y], "grid": 32, "room_tileset": TILES}
	w.data.areas["Prism Arena"] = {"title": "Prism Arena", "subtitle": "Hit them and watch", "color": "#b07aff", "parallax": "deep_cavern"}
	w.data.areas["Storm Hall"] = {"title": "Storm Hall", "color": "#4a8aff", "parallax": "deep_cavern"}
	w.add_room("Prism_Arena", Rect2(Vector2.ZERO, ROOM), 0, "Prism Arena")
	w.add_room("Storm_Hall", Rect2(Vector2(ROOM.x, 0), ROOM), 0, "Storm Hall")
	w.add_gate("Prism_Arena", Vector2(ROOM.x, 704), "right", "right1", false)
	w.add_gate("Storm_Hall", Vector2(ROOM.x, 704), "left", "left1", false)
	w.connect_gates("Prism_Arena", "right1", "Storm_Hall", "left1")
	for id in w.get_room_ids():
		w.set_room_scene(id, "%s/%s.tscn" % [ROOMS_DIR, id.to_lower()])
	w.set_start_room("Prism_Arena")
	w.save()
	MDSWorld._cache.erase(WORLD_PATH)
	return w

## Each room: an arena generated as Generate cave does, then its enemies.
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
		var enemies := Node2D.new()
		enemies.name = "Enemies"
		p.root.add_child(enemies)
		enemies.owner = p.root
		for e: Array in ENEMIES.get(id, []):
			var scene := load(TEMPLATES + str(e[1]) + ".tscn") as PackedScene
			var enemy := scene.instantiate() as MDSEnemy
			enemy.name = str(e[0])
			for key: String in e[4]:
				var v: Variant = e[4][key]
				enemy.set(key, PackedColorArray(v) if key == "particle_palette" else v)
			var y: float = e[3] if float(e[3]) > 0.0 else FLOOR_Y - enemy.body_size.y * 0.5 - 2.0
			enemy.position = Vector2(float(e[2]), y)
			enemies.add_child(enemy)
			enemy.owner = p.root
		p.save()
		p.free_instance()
		k += 1

## The game scene, as Scenes > Create game scene makes it (with the Gameplay Kit), and the node
## setting the player's colors.
static func _build_game_scene(world: MDSWorld) -> void:
	var err := MDSWorldSceneTools.create_game_scene(world, GAME_PATH, true)
	if err != OK:
		push_error("Failed to create the game scene: %s" % error_string(err))
		return
	var game := (load(GAME_PATH) as PackedScene).instantiate() as MDSWorldGame
	game.save_file = "user://combat_fx_demo_save.json"
	game.exploration_file = "user://combat_fx_demo_exploration.json"
	var colors := Node.new()
	colors.name = "CombatColors"
	colors.set_script(load(DEMO_DIR + "/combat_colors.gd"))
	game.add_child(colors)
	colors.owner = game
	var packed := PackedScene.new()
	packed.pack(game)
	ResourceSaver.save(packed, GAME_PATH)
	game.free()

static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		if not c.owner and c != root:
			c.owner = root
		_own(c, root)
