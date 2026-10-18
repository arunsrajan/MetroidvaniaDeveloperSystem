extends "res://tests/test_case.gd"
## Gameplay Kit, phase 8: Create game scene with the kit (MDSPlayer, MDSGameplay, the kit's UI,
## enforce_requirements) and without it (the placeholder body), both run; a gate the player can't
## pass yet shows "Requires Dash" in the toast; the Room view's enemy entries are the template
## scenes; the debug keys' overlay and ability list; the title screen's slots go through the game's
## save API.

const Fixture := preload("res://tests/game_fixture.gd")
const DIR := TMP + "/scene_tools"
const SLOT_GAME := "user://mds_test_scene_tools_own.json"

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	DirAccess.make_dir_recursive_absolute(DIR)
	var world := Fixture.build()
	await _placeholder_mode(world)
	await _kit_mode(world)
	_enemy_templates()
	_release_all()
	MDSWorld._cache.erase(Fixture.WORLD)

func _release_all() -> void:
	for a in MDSGameplaySetup.ACTIONS:
		Input.action_release(a)

## The generated game, ready to run here: no fades, no gate cooldown, nothing loaded or saved.
func _instance(path: String) -> MDSWorldGame:
	var game := (load_fresh(path) as PackedScene).instantiate() as MDSWorldGame
	game.fade_time = 0.0
	game.gate_cooldown = 0.0
	game.load_on_start = false
	game.save_file = SLOT_GAME
	game.exploration_file = ""
	return game

func _placeholder_mode(world: MDSWorld) -> void:
	var path := DIR + "/game_placeholder.tscn"
	check(MDSWorldSceneTools.create_game_scene(world, path, false) == OK, "a game scene without the kit is created")
	var game := _instance(path)
	var body := game.get_node_or_null(^"Player")
	check(body is CharacterBody2D and not body is MDSPlayer and body.is_in_group(&"player"), "its player is the placeholder body")
	check(body.get_node_or_null(^"Shape") is CollisionShape2D and body.get_node_or_null(^"Camera2D") is Camera2D, "with its capsule and camera")
	check(MDSGameplay.find(game) == null and game.get_node_or_null(^"UI/Hud") == null and not game.enforce_requirements, "and no kit, kit UI or enforced requirements")
	add_child(game)
	await game.room_loaded
	await physics_frames(10)
	check(game.current_room == world.get_start_room() and game.player == body, "it runs: the start room loads with the placeholder player")
	game.load_room("Garden_02", "left1")
	await game.room_loaded
	await physics_frames(5)
	check(game.current_room == "Garden_02", "and goes from room to room")
	game.queue_free()
	await get_tree().process_frame

func _kit_mode(world: MDSWorld) -> void:
	var path := DIR + "/game_kit.tscn"
	check(MDSWorldSceneTools.create_game_scene(world, path) == OK, "a game scene with the kit is created")
	var game := _instance(path)
	var player := game.get_node_or_null(^"Player") as MDSPlayer
	check(player != null and player.is_in_group(&"player") and player.get_node_or_null(^"Camera2D") is Camera2D, "its player is MDSPlayer, with the camera")
	check(MDSGameplay.find(game) != null and game.enforce_requirements, "with MDSGameplay and requirements enforced")
	var missing: PackedStringArray = []
	for n in ["Hud", "Toast", "AbilityPopup", "PauseMenu", "DialogueBox"]:
		if not game.get_node_or_null(NodePath("UI/" + n)):
			missing.append(n)
	check(missing.is_empty(), "and the kit's UI under UI (missing: %s)" % ", ".join(missing))
	add_child(game)
	await game.room_loaded
	await physics_frames(30)
	check(game.current_room == world.get_start_room() and player.is_on_floor(), "it runs: the kit player stands in the start room")
	await _requires_toast(game, player)
	_debug_tools(game)
	_title_slots(game)
	game.queue_free()
	await get_tree().process_frame
	if FileAccess.file_exists(SLOT_GAME):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SLOT_GAME))

## A gate that needs dash stops the player, and the toast names what is missing.
func _requires_toast(game: MDSWorldGame, player: MDSPlayer) -> void:
	game.world.get_gate("Garden_01", "right1")["requires"] = ["dash"]
	var toast := game.get_node(^"UI/Toast") as MDSToast
	player.global_position = game.world.get_origin("Garden_01") + Vector2(850, 540)
	player.velocity = Vector2.ZERO
	await physics_frames(20)
	Input.action_press(&"move_right")
	var shown := false
	for i in 200:
		await get_tree().physics_frame
		if toast.get_current_text().contains("Requires Dash") or Array(toast.get_queue()).any(func(t: String) -> bool: return t.contains("Requires Dash")):
			shown = true
			break
	Input.action_release(&"move_right")
	check(shown, "a gate the player can't pass yet shows \"Requires Dash\" (%s)" % toast.get_current_text())
	check(game.current_room == "Garden_01", "and the player stays in the room")
	game.world.get_gate("Garden_01", "right1")["requires"] = []
	await physics_frames(10)

## F1's overlay text and F2's abilities (those the world file names, not its items or flags).
func _debug_tools(game: MDSWorldGame) -> void:
	game.world.get_gate("Garden_02", "right1")["requires"] = ["dash", "item:red_key", "ability:wall_jump", "flag:gate_open"]
	var all := MDSGameplayDebug.world_abilities(game)
	check(all.has("dash") and all.has("wall_jump") and not all.has("red_key") and not all.has("item:red_key") and not all.has("gate_open"), "F2 grants the world file's abilities only (%s)" % ", ".join(all))
	game.world.get_gate("Garden_02", "right1")["requires"] = []
	var dbg := MDSGameplayDebug.new()
	game.add_child(dbg)
	var text := "\n".join(dbg.overlay_lines())
	check(text.contains("State: ") and not text.contains("State: None") and text.contains("HP: ") and text.contains("Room: Garden_01"), "F1's overlay shows the player's state, health and room")
	check(not get_tree().get_nodes_in_group(MDSHitbox.GROUP).is_empty() and not get_tree().get_nodes_in_group(MDSHurtbox.GROUP).is_empty(), "and finds the hitboxes and hurtboxes to outline")
	dbg.free()

## The title screen reads and deletes its slots through the game's save API, keeping the game's
## own save file.
func _title_slots(game: MDSWorldGame) -> void:
	var title := MDSTitleScreen.new()
	game.get_node(^"UI").add_child(title)
	var slot := title.get_slot_path(2)
	var f := FileAccess.open(slot, FileAccess.WRITE)
	f.store_string(JSON.stringify({"room": "Garden_01", "ext": {"gameplay": {"health": 3, "max_health": 5}}}))
	f.close()
	check(title.has_slot_save(2) and not title.has_slot_save(1), "slot 2 has a save, slot 1 none")
	check(str(title.read_slot(2).get("room", "")) == "Garden_01", "the slot's save is read")
	check(game.save_file == SLOT_GAME, "and the game's own save file is kept")
	title.delete_slot(2)
	check(not title.has_slot_save(2) and not FileAccess.file_exists(slot), "deleting the slot removes its save")
	title.free()

## The Room view's Enemy entries make the template scenes, not bare enemies.
func _enemy_templates() -> void:
	var want := {"walker": "MDSWalker", "flyer": "MDSFlyer", "turret": "MDSTurret", "charger": "MDSCharger", "ambusher": "MDSAmbusher"}
	for kind: String in want:
		var n := MDSRoomCanvas.enemy_template(kind)
		var script := n.get_script() as Script
		check(script != null and script.get_global_name() == want[kind] and n.name == kind.capitalize(), "Room view Enemy (%s) places the %s template (%s)" % [kind.capitalize(), want[kind], script.get_global_name() if script else "none"])
		n.free()
