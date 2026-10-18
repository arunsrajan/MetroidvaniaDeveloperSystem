extends "res://tests/test_case.gd"
## Tests for Section 14 & 16: Gameplay Demo World integration.
## Verifies world loading, Progress tab reachability (spheres 0..5 in intended order),
## missing dash making Grove_07 onward (Gardens_01..) unreachable, and a scripted run
## from Grove_01 to the Gardens_05 ending trigger.

const DEMO_WORLD := "res://examples/gameplay_demo/gameplay_demo.mdsworld.json"
const GAME_SCENE := "res://examples/gameplay_demo/game.tscn"

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	# Ensure demo world is built
	if not FileAccess.file_exists(DEMO_WORLD) or not FileAccess.file_exists(GAME_SCENE):
		var builder := preload("res://examples/gameplay_demo/build_gameplay_demo.gd")
		builder.build_all()

	var world := _test_world_load()
	var scanner := _test_scanner_and_spheres(world)
	_test_missing_dash_makes_gardens_unreachable(world, scanner)
	await _test_scripted_run_to_ending()

func _test_world_load() -> MDSWorld:
	var w := MDSWorld.load_world(DEMO_WORLD)
	check(w != null and not w.data.rooms.is_empty(), "gameplay_demo.mdsworld.json loads without errors")
	check(w.get_room_ids().size() == 12, "demo world contains exactly 12 rooms (%d)" % w.get_room_ids().size())
	check(w.get_start_room() == "Grove_01", "demo starts in Grove_01")
	check(w.get_areas().has("Mossgrove") and w.get_areas().has("Sunken Gardens"), "demo contains Mossgrove and Sunken Gardens")
	return w

func _test_scanner_and_spheres(world: MDSWorld) -> MDSSceneScanner:
	var scanner := MDSSceneScanner.new()
	scanner.require_room_instance = false
	for id in world.get_room_ids():
		var path: String = world.data.rooms[id].get("scene", "")
		if not path.is_empty() and ResourceLoader.exists(path):
			var meta := scanner.analyze_scene_any(path)
			scanner.scene_database[path] = meta

	var analysis := MDSAnalysis.new(MDSGraph.from_world(world, {}), world, scanner.scene_database).run()

	check(analysis.disconnected.is_empty(), "no rooms disconnected from start (%s)" % [analysis.disconnected])
	check(analysis.locked.is_empty(), "no rooms locked in intended progression (%s)" % [analysis.locked])

	# Check progression order matches Section 14 spec:
	# Sphere 0: Grove_01, Grove_02, Grove_03
	check(analysis.sphere_of.get("Grove_01") == 0, "Grove_01 in sphere 0")
	check(analysis.sphere_of.get("Grove_02") == 0, "Grove_02 in sphere 0")
	check(analysis.sphere_of.get("Grove_03") == 0, "Grove_03 in sphere 0")

	# Sphere 1: Grove_04, Grove_05 (unlocked by double_jump from Grove_03)
	check(analysis.sphere_of.get("Grove_04") == 1, "Grove_04 in sphere 1 (after double_jump)")
	check(analysis.sphere_of.get("Grove_05") == 1, "Grove_05 in sphere 1 (boss arena)")

	# Sphere 2: Grove_06, Grove_07 (unlocked by boss:Warden defeat in Grove_05)
	check(analysis.sphere_of.get("Grove_06") == 2, "Grove_06 in sphere 2 (after Warden)")
	check(analysis.sphere_of.get("Grove_07") == 2, "Grove_07 in sphere 2 (lava hazard)")

	# Sphere 3: Gardens_01, Gardens_02 (unlocked by dash from Grove_06)
	check(analysis.sphere_of.get("Gardens_01") == 3, "Gardens_01 in sphere 3 (after dash)")
	check(analysis.sphere_of.get("Gardens_02") == 3, "Gardens_02 in sphere 3 (red key)")

	# Sphere 4: Gardens_03 (unlocked by item:red_key from Gardens_02)
	check(analysis.sphere_of.get("Gardens_03") == 4, "Gardens_03 in sphere 4 (after red_key)")

	# Sphere 5: Gardens_04, Gardens_05 (unlocked by flag:bridge_lowered from Gardens_03)
	check(analysis.sphere_of.get("Gardens_04") == 5, "Gardens_04 in sphere 5 (after bridge lowered)")
	check(analysis.sphere_of.get("Gardens_05") == 5, "Gardens_05 in sphere 5 (wall jump & ending)")

	return scanner

func _test_missing_dash_makes_gardens_unreachable(world: MDSWorld, scanner: MDSSceneScanner) -> void:
	var copy_db := scanner.scene_database.duplicate(true)
	var g6_path: String = world.data.rooms["Grove_06"].get("scene", "")
	if copy_db.has(g6_path):
		copy_db[g6_path].grants = []
		copy_db[g6_path].grant_counts = {}

	var a_no_dash := MDSAnalysis.new(MDSGraph.from_world(world, {}), world, copy_db).run()
	check(not a_no_dash.sphere_of.has("Gardens_01"), "without dash pickup, Gardens_01 is not reached in any sphere")
	check(a_no_dash.locked.has("Gardens_01"), "without dash pickup, Gardens_01 is reported locked")
	check(a_no_dash.locked.has("Gardens_03"), "without dash pickup, Gardens_03 is reported locked")

	var issues := MDSWorldValidator.run(world, a_no_dash, copy_db)
	var locked_issues := issues.filter(func(i: Dictionary) -> bool:
		return str(i.message).contains("can never be entered") and str(i.message).contains("Gardens_01"))
	check(not locked_issues.is_empty(), "Issues tab reports Gardens_01 unreachable without dash (%d issues)" % locked_issues.size())

func _test_scripted_run_to_ending() -> void:
	var packed: PackedScene = load(GAME_SCENE) as PackedScene
	check(packed != null, "game.tscn exists and is loadable")
	if not packed:
		return

	var game: MDSWorldGame = packed.instantiate()
	game.fade_time = 0.0
	game.gate_cooldown = 0.0
	if game.room_camera:
		game.room_camera.transition_time = 0.0
		game.room_camera.room_transition = MDSRoomCamera.Transition.CUT
	add_child(game)
	await game.room_loaded
	await physics_frames(5)

	check(game.current_room == "Grove_01", "game starts in Grove_01")
	var player: MDSPlayer = game.player as MDSPlayer
	check(player != null, "player is an MDSPlayer")
	var kit := MDSGameplay.find(game)
	check(kit != null, "MDSGameplay kit is present in game scene")
	if kit:
		kit.show_ability_popups = false

	# Initial state: no abilities
	check(not player.has_ability("double_jump"), "initially player lacks double_jump")
	check(not player.has_ability("dash"), "initially player lacks dash")
	check(not player.has_ability("wall_jump"), "initially player lacks wall_jump")

	# Step 1: Visit Grove_02, then Grove_03 and get double_jump
	game.load_room("Grove_02", "left1")
	await game.room_loaded
	await physics_frames(3)
	game.load_room("Grove_03", "bot1")
	await game.room_loaded
	await physics_frames(3)

	var dj_pickup := game.room_node.get_node_or_null("AbilityPickup_DoubleJump") as MDSAbilityPickup
	check(dj_pickup != null, "Grove_03 contains AbilityPickup_DoubleJump")
	if dj_pickup:
		dj_pickup.collect()
	check(player.has_ability("double_jump"), "player gained double_jump in Grove_03")

	# Step 2: Go through Grove_04 to Grove_05 (Boss fight)
	game.load_room("Grove_04", "left1")
	await game.room_loaded
	await physics_frames(3)
	game.load_room("Grove_05", "left1")
	await game.room_loaded
	await physics_frames(3)

	var boss := game.room_node.get_node_or_null("Warden") as MDSBoss
	check(boss != null, "Grove_05 contains Boss Warden")
	check(not game.is_boss_defeated("Warden"), "Warden is initially alive")
	game.defeat_boss("Warden")
	check(game.is_boss_defeated("Warden"), "Warden is defeated")

	# Step 3: Advance to Grove_06 and collect dash
	game.load_room("Grove_06", "left1")
	await game.room_loaded
	await physics_frames(3)

	var dash_pickup := game.room_node.get_node_or_null("AbilityPickup_Dash") as MDSAbilityPickup
	check(dash_pickup != null, "Grove_06 contains AbilityPickup_Dash")
	if dash_pickup:
		dash_pickup.collect()
	check(player.has_ability("dash"), "player gained dash in Grove_06")

	# Step 4: Advance through Grove_07 to Gardens_01
	game.load_room("Grove_07", "left1")
	await game.room_loaded
	await physics_frames(3)
	game.load_room("Gardens_01", "left1")
	await game.room_loaded
	await physics_frames(3)

	# Step 5: Enter Gardens_02 and collect red_key
	game.load_room("Gardens_02", "top1")
	await game.room_loaded
	await physics_frames(3)

	var key_pickup := game.room_node.get_node_or_null("RedKeyPickup") as MDSPickup
	check(key_pickup != null, "Gardens_02 contains RedKeyPickup")
	if key_pickup:
		key_pickup.collect()
	check(kit.has_item("red_key"), "player collected red_key in Gardens_02")

	# Step 6: Unlock door to Gardens_03 and hit switch
	game.load_room("Gardens_03", "left1")
	await game.room_loaded
	await physics_frames(3)

	var sw := game.room_node.get_node_or_null("BridgeSwitch") as MDSSwitch
	check(sw != null, "Gardens_03 contains BridgeSwitch")
	if sw:
		sw.activate()
	check(kit.get_flag("bridge_lowered") == true, "bridge_lowered flag set by switch")

	# Step 7: Enter Gardens_04 and collect wall_jump
	game.load_room("Gardens_04", "left1")
	await game.room_loaded
	await physics_frames(3)

	var wj_pickup := game.room_node.get_node_or_null("AbilityPickup_WallJump") as MDSAbilityPickup
	check(wj_pickup != null, "Gardens_04 contains AbilityPickup_WallJump")
	if wj_pickup:
		wj_pickup.collect()
	check(player.has_ability("wall_jump"), "player gained wall_jump in Gardens_04")

	# Step 8: Enter Gardens_05 and reach ending trigger
	game.load_room("Gardens_05", "left1")
	await game.room_loaded
	await physics_frames(3)

	var end_trig := game.room_node.get_node_or_null("EndingTrigger") as Area2D
	check(end_trig != null, "Gardens_05 contains EndingTrigger")
	if end_trig:
		end_trig.emit_signal(&"body_entered", player)
		check(end_trig.get_meta("demo_completed", false) == true, "demo completed signal/metadata emitted at ending trigger")

	game.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	Engine.time_scale = 1.0
