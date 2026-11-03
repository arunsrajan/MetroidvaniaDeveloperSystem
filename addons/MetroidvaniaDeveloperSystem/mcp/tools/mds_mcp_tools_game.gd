@tool
class_name MDSMcpToolsGame
extends MDSMcpTools
## Gameplay and combat: enemies' looks, the game scene, the project's input and layers.

const RESPAWNS: PackedStringArray = ["on_room_load", "on_rest", "never"]

func _register() -> void:
	var world := _world_schema()
	_add("mds_enemy_configure", "Sets how an enemy in a room hits and hurts. Damage types and particles come from mds_catalog. Colors are #rrggbb or #rrggbbaa.", AUTHOR,
		{
			"world": world, "room": S.text(), "node": S.text("Node path from mds_room_items"),
			"damage_type": S.text(), "attack_color": S.text(), "attack_glow": S.text(), "hurt_particles": S.text(), "particle_palette": S.array(S.text()),
			"particle_glow": S.number("", -1, 3), "particle_size": S.number("", 0), "body_color": S.text(), "contact_damage": S.integer("-1: the enemy data's", -1),
			"facing": S.integer("-1 left, 1 right", -1, 1), "respawn": S.choice(Array(RESPAWNS)), "on_unsaved": _unsaved_schema(),
		}, ["room", "node"], _enemy_configure)
	_add("mds_game_scene_create", "Makes the scene that plays the world, with the Gameplay Kit unless told otherwise. stream_rooms keeps the rooms around the player loaded, for open worlds.", AUTHOR,
		{"world": world, "path": S.text("res://....tscn"), "include_gameplay_kit": S.boolean("Default true"), "stream_rooms": S.boolean(), "save_file": S.text("user://..."), "exploration_file": S.text("user://...")}, ["path"], _game_scene)
	_add("mds_gameplay_setup", "Adds the input actions, physics layer names and settings the Gameplay Kit needs to project.godot. Only adds what is missing.", FULL,
		{"actions": S.boolean("Default true"), "layers": S.boolean("Default true"), "settings": S.boolean("Default true")}, [], _gameplay_setup, {"project_file": true})

func _enemy_configure(args: Dictionary, _report: Callable) -> Dictionary:
	if args.has("damage_type") and not args.damage_type in MDSDamageInfo.TYPES.split(","):
		return ctx.fail("bad_id", "%s is not a damage type." % args.damage_type, "mds_catalog lists damage_types.")
	if args.has("hurt_particles") and not args.hurt_particles in MDSHitParticles.KINDS.split(","):
		return ctx.fail("bad_id", "%s is not a kind of particles." % args.hurt_particles, "mds_catalog lists hit_particles.")
	if args.has("facing") and args.facing == 0:
		return ctx.fail("bad_arguments", "facing is -1 or 1.")
	for key in ["attack_color", "attack_glow", "body_color"]:
		if args.has(key) and not Color.html_is_valid(args[key]):
			return ctx.fail("bad_arguments", "%s: %s is not a color." % [key, args[key]])
	for c: String in args.get("particle_palette", []):
		if not Color.html_is_valid(c):
			return ctx.fail("bad_arguments", "particle_palette: %s is not a color." % c)
	var world := ctx.read_world(args)
	if not world:
		return ctx.error
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	var enemy := painter.root.get_node_or_null(NodePath(args.node)) as MDSEnemy
	if not enemy:
		painter.free_instance()
		return ctx.fail("node_not_found", "%s is not an enemy in room %s." % [args.node, args.room], "mds_room_items lists them.")
	var changed := []
	for key in ["damage_type", "hurt_particles", "particle_glow", "particle_size", "contact_damage", "facing"]:
		if args.has(key):
			enemy.set(key, args[key])
			changed.append(key)
	for key in ["attack_color", "attack_glow", "body_color"]:
		if args.has(key):
			enemy.set(key, S.color(args[key]))
			changed.append(key)
	if args.has("particle_palette"):
		var palette := PackedColorArray()
		for c: String in args.particle_palette:
			palette.append(S.color(c))
		enemy.particle_palette = palette
		changed.append("particle_palette")
	if args.has("respawn"):
		enemy.respawn = RESPAWNS.find(args.respawn) as MDSEnemy.Respawn
		changed.append("respawn")
	painter.dirty = true
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "node": args.node, "set": changed}

func _game_scene(args: Dictionary, _report: Callable) -> Dictionary:
	var world := ctx.edit_world(args)
	if not world:
		return ctx.error
	var path := MDSMcpGuard.normalize(args.path)
	if path.is_empty() or path.get_extension() != "tscn":
		return ctx.fail("bad_arguments", "%s must be a .tscn path inside res://." % args.path)
	if not ctx.prepare_room_write(path, args):
		return ctx.error
	var err := MDSWorldSceneTools.create_game_scene(world, path, args.get("include_gameplay_kit", true))
	if err != OK:
		return ctx.fail("save_failed", "Could not create %s: %s" % [path, error_string(err)])
	var packed := MDSWorldSceneTools.load_fresh(path)
	var game := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as MDSWorldGame if packed else null
	if game:
		if args.has("stream_rooms"):
			game.stream_rooms = args.stream_rooms
		for key in ["save_file", "exploration_file"]:
			if args.has(key):
				if not str(args[key]).begins_with("user://"):
					game.free()
					return ctx.fail("bad_arguments", "%s must be a user:// path." % key)
				game.set(key, args[key])
		var again := PackedScene.new()
		again.pack(game)
		ResourceSaver.save(again, path)
		game.free()
		MDSWorldSceneTools.load_fresh(path)
	ctx.host.room_written(path)
	var bad := ctx.save_world(world)
	return bad if not bad.is_empty() else {"scene": path}

func _gameplay_setup(args: Dictionary, _report: Callable) -> Dictionary:
	if not ctx.touch(MDSMcpGuard.PROJECT_FILE):
		return ctx.error
	var added := {}
	if args.get("actions", true):
		added.actions = MDSGameplaySetup.ensure_input_actions(true)
	if args.get("layers", true):
		added.layers = MDSGameplaySetup.ensure_layer_names(true)
	if args.get("settings", true):
		added.settings = MDSGameplaySetup.ensure_settings(true)
	return {"added": added}
