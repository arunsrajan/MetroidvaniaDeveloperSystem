extends "res://tests/test_case.gd"
## Tests for Section 14 & 16: the Gameplay Demo World.
## Loads the world; the Progress tab reaches every room in the intended order (spheres 0..5);
## without the dash pickup Gardens_01 onward is unreachable; the rooms are painted with the
## Mossgrove and Sunken Gardens packs; and the intended route is played from Grove_01 to the
## Gardens_05 ending with simulated input only: Input.action_press and the player's input buffer
## (and a jump press to close the ability popups). Gates are crossed by moving through them,
## pickups collected by touching them, the switch and the breakable wall struck, the Warden
## fought with the default attacks. No debug keys.

const DEMO_WORLD := "res://examples/gameplay_demo/gameplay_demo.mdsworld.json"
const GAME_SCENE := "res://examples/gameplay_demo/game.tscn"
const BUILDER := "res://examples/gameplay_demo/build_gameplay_demo.gd"
## The played run goes this many times faster than real time: physics ticks per second and the
## time scale are raised together, so every physics step is still 1/60 s of game time.
const SPEED := 4
## Game seconds the run may take before it counts as stuck.
const RUN_LIMIT := 480.0
## The route: the room each leg starts in, and the method that plays it (to the next room).
const ROUTE := [
	["Grove_01", "_grove_01"],
	["Grove_02", "_grove_02_climb"],
	["Grove_03", "_grove_03"],
	["Grove_02", "_grove_02_high_ledge"],
	["Grove_04", "_grove_04"],
	["Grove_05", "_grove_05"],
	["Grove_06", "_grove_06"],
	["Grove_07", "_grove_07"],
	["Gardens_01", "_gardens_01_down"],
	["Gardens_02", "_gardens_02"],
	["Gardens_01", "_gardens_01_door"],
	["Gardens_03", "_gardens_03"],
	["Gardens_04", "_gardens_04"],
	["Gardens_05", "_gardens_05"],
]

var game: MDSWorldGame
var player: MDSPlayer
var kit: MDSGameplay
var verbose := false
var _held: Dictionary = {}
var _frames := 0
var _failure := ""
var _popup_seen_at := -1
var _popups_closed := 0
var _ticks_before := 60

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	# Ensure demo world is built
	if not FileAccess.file_exists(DEMO_WORLD) or not FileAccess.file_exists(GAME_SCENE):
		load(BUILDER).build_all()

	var world := _test_world_load()
	var scanner := _test_scanner_and_spheres(world)
	_test_missing_dash_makes_gardens_unreachable(world, scanner)
	_test_rooms_use_packs(world)
	await _test_moves_need_abilities()
	await _test_played_route()

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

## Every room is freeform terrain in its area's pack style, with the pack's stamps, and no plain
## collision floors.
func _test_rooms_use_packs(world: MDSWorld) -> void:
	for id in world.get_room_ids():
		var gardens := world.get_room_area(id) == "Sunken Gardens"
		var pack := "res://asset_packs/sunken_gardens/" if gardens else "res://asset_packs/mossgrove/"
		var rock := pack + ("freeform/styles/garden_limestone.freeform.tres" if gardens else "freeform/styles/mossy_rock.freeform.tres")
		var room: Node = (load(world.get_scene_path(id)) as PackedScene).instantiate()
		var shapes := MDSFreeform.shapes_in(room)
		var solid := shapes.filter(func(f: MDSFreeform) -> bool: return f.is_collider() and f.smooth)
		var in_rock := solid.filter(func(f: MDSFreeform) -> bool: return f.style and f.style.resource_path == rock)
		var stamps := room.find_children("*", "Sprite2D", true, false).filter(func(s: Node) -> bool:
			return MDSRoomPainter.is_stamp(s) and (s as Sprite2D).texture and (s as Sprite2D).texture.resource_path.begins_with(pack))
		var bodies := room.find_children("*", "StaticBody2D", true, false).filter(func(b: Node) -> bool: return b.get_script() == null)
		check(not in_rock.is_empty() and shapes.all(func(f: MDSFreeform) -> bool: return f.smooth or not f.is_collider()),
			"%s is converted freeform terrain in %s (%d of %d solid shapes)" % [id, rock.get_file(), in_rock.size(), solid.size()])
		check(not stamps.is_empty(), "%s is decorated with the pack's stamps (%d)" % [id, stamps.size()])
		check(bodies.is_empty(), "%s has no plain collision floors (%d)" % [id, bodies.size()])
		room.free()

# --- The obstacles ------------------------------------------------------------------------------

## Without its ability each obstacle can't be passed, played as the route plays it: Grove_02's
## high ledge (double_jump), Grove_07's lava cavern (dash), Gardens_05's shaft (wall_jump).
## Each room is loaded directly here (this is not the played run).
func _test_moves_need_abilities() -> void:
	if not await _start_game():
		return
	kit.show_ability_popups = false
	# Grove_02: a single jump from the hanging ledge doesn't reach the high ledge.
	game.load_room("Grove_02", "top1")
	await game.room_loaded
	for i in 120:
		_steer_to(690.0)
		await _step()
		if player.is_on_floor():
			break
	await _run_to(768.0)
	var on_ledge := player.is_on_floor() and absf(_feet() - 420.0) < 8.0
	var top := _feet()
	_press(&"jump")
	for i in 90:
		_steer_to(940.0)
		await _step()
		top = minf(top, _feet())
		if i > 5 and player.is_on_floor():
			break
	_let_go(&"jump")
	var reached := player.is_on_floor() and _feet() < 320.0 and _pos().x > 860.0
	check(on_ledge and not reached and top > 300.0, "without double_jump the high ledge (y 300) is out of reach from the hanging ledge (y 420): the jump tops out at %.0f" % top)
	# Grove_07: running off the first stone falls short; a jump hits the low ceiling.
	game.load_room("Grove_07", "left1")
	await game.room_loaded
	await _wait_floor()
	var health := player.health.current
	await _run_to(294.0, 4.0)
	await _jump_to(420.0)
	await _step(60)
	var past_first := _pos().x > 370.0 and absf(_feet() - 560.0) < 8.0
	check(not past_first and player.health.current < health, "without dash the first stepping stone is out of reach: the player falls in the lava (at %s, health %d)" % [_pos().round(), player.health.current])
	# Gardens_05: with the double jump but no wall jump, the shaft can't be climbed.
	game.grant_ability("double_jump")
	game.load_room("Gardens_05", "left1")
	await game.room_loaded
	var climbed := await _gardens_05()
	check(not climbed, "without wall_jump the Gardens_05 shaft can't be climbed (%s)" % _failure)
	_failure = ""
	await _stop_game()

# --- The played run ---------------------------------------------------------------------------

func _test_played_route() -> void:
	if not await _start_game():
		return
	var ok := await _play_route(0)
	_end_speed()
	check(ok, "the route is played from Grove_01 to the ending (%s)" % (_failure if not ok else "%.0f s of game time" % (_frames / 60.0)))
	if ok:
		var end := game.room_node.get_node_or_null(^"EndingTrigger")
		check(end != null and end.get_meta(&"demo_completed", false) == true, "the player reached the EndingTrigger in Gardens_05")
		check(player.has_ability("double_jump") and player.has_ability("dash") and player.has_ability("wall_jump"), "double_jump, dash and wall_jump were collected on the way")
		check(game.is_boss_defeated("Warden"), "the Warden was fought and beaten")
		check(kit.get_flag("bridge_lowered") == true, "the bridge switch was struck")
		check(not kit.has_item("red_key") and game.is_object_stored("Gardens_02/RedKeyPickup"), "the red key was picked up and used on the locked door")
		check(kit.get_item_count("health_fragment") == 1, "the health fragment behind the breakable wall was picked up")
		check(_popups_closed == 3, "the three ability popups were closed with a jump press (%d)" % _popups_closed)
		check(game.visited_rooms.size() == 12, "every room was visited (%d)" % game.visited_rooms.size())
		check(_frames / 60.0 < RUN_LIMIT, "the run took %.0f s of game time" % (_frames / 60.0))
	await _stop_game()

## Starts the demo's game scene (no save or exploration file of its own, cut transitions) and
## runs it [constant SPEED] times faster than real time.
func _start_game() -> bool:
	var packed: PackedScene = load(GAME_SCENE) as PackedScene
	check(packed != null, "game.tscn exists and is loadable")
	if not packed:
		return false
	game = packed.instantiate()
	game.load_on_start = false
	game.save_file = TMP + "/gameplay_demo_run.json"
	game.exploration_file = ""
	game.fade_time = 0.0
	if game.room_camera:
		game.room_camera.transition_time = 0.0
		game.room_camera.room_transition = MDSRoomCamera.Transition.CUT
	if FileAccess.file_exists(game.save_file):
		DirAccess.remove_absolute(game.save_file)
	add_child(game)
	await game.room_loaded
	player = game.player as MDSPlayer
	kit = MDSGameplay.find(game)
	check(game.current_room == "Grove_01" and player != null and kit != null, "the game starts in Grove_01 with the kit's player")
	if not player or not kit:
		return false
	check(not player.has_ability("double_jump") and not player.has_ability("dash") and not player.has_ability("wall_jump"), "the player starts with no abilities")
	_ticks_before = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = _ticks_before * SPEED
	Engine.time_scale = SPEED
	_frames = 0
	_popups_closed = 0
	await _step(5)
	return true

func _end_speed() -> void:
	_let_go_all()
	Engine.physics_ticks_per_second = _ticks_before
	Engine.time_scale = 1.0

func _stop_game() -> void:
	_end_speed()
	if is_instance_valid(game):
		game.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	Engine.time_scale = 1.0

## Plays the route from leg [param from]. Returns whether it reached the ending.
func _play_route(from: int) -> bool:
	for i in range(from, ROUTE.size()):
		var room: String = ROUTE[i][0]
		if game.current_room != room:
			return _fail("the route expected %s" % room)
		var started := _frames
		var done: bool = await Callable(self, ROUTE[i][1]).call()
		if verbose:
			print("  %s %s: %s in %.1f s, health %d" % [room, ROUTE[i][1], "done" if done else "FAILED", (_frames - started) / 60.0, player.health.current])
		if not done:
			return false
		if _frames / 60.0 > RUN_LIMIT:
			return _fail("out of time")
	return true

## Notes why the run stopped (with where the player is) and returns false.
func _fail(why: String) -> bool:
	if _failure.is_empty():
		_failure = "%s; in %s at %s, %s, health %d" % [why, game.current_room, _pos().round(), player.machine.get_state(), player.health.current]
	_let_go_all()
	return false

# --- Input --------------------------------------------------------------------------------------

## One physics step of the game (steps while the tree is paused, an ability popup showing, don't
## count: the popup is closed with a jump press as a player would; a pause that lasts longer than
## a few seconds is left to the moves' own limits).
func _step(n := 1) -> void:
	for i in n:
		await get_tree().physics_frame
		_handle_popup()
		var paused_at := Time.get_ticks_msec()
		while get_tree().paused and Time.get_ticks_msec() - paused_at < 5000:
			await get_tree().physics_frame
			_handle_popup()
		_frames += 1

func _handle_popup() -> void:
	var popup: MDSAbilityPopup = null
	for n in get_tree().get_nodes_in_group(&"mds_ability_popup"):
		if n is MDSAbilityPopup and (n as MDSAbilityPopup).is_showing():
			popup = n
	if not popup:
		_popup_seen_at = -1
		return
	if _popup_seen_at < 0:
		_popup_seen_at = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - _popup_seen_at > int(popup.min_time * 1000.0) + 100:
		_input_event(&"jump", true)
		_input_event(&"jump", false)
		_popups_closed += 1
		_popup_seen_at = -1

## A press or release as an input event (what benches and popups listen for).
func _input_event(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _hold(action: StringName) -> void:
	Input.action_press(action)
	_held[action] = true

func _let_go(action: StringName) -> void:
	if _held.has(action):
		Input.action_release(action)
		_held.erase(action)

func _let_go_all() -> void:
	for a in _held.keys():
		Input.action_release(a)
	_held.clear()

## A press: the action held down and noted in the player's input buffer.
func _press(action: StringName) -> void:
	_hold(action)
	player.buffer.press(String(action))

## Presses [param action] for a frame.
func _tap(action: StringName) -> void:
	_press(action)
	await _step()
	_let_go(action)

## Left (-1), right (1) or neither (0).
func _steer(dir: int) -> void:
	if dir < 0:
		_hold(&"move_left")
	else:
		_let_go(&"move_left")
	if dir > 0:
		_hold(&"move_right")
	else:
		_let_go(&"move_right")

## Steers toward [param x] (room coordinates), braking on the way in. Returns how far it is.
func _steer_to(x: float) -> float:
	var dx := x - _pos().x
	var want := clampf(dx * 6.0, -260.0, 260.0)
	var v := player.velocity.x
	var slack := minf(25.0, absf(want) * 0.5)
	if absf(dx) < 2.0 and absf(v) < 30.0:
		_steer(0)
	elif want - v > slack:
		_steer(1)
	elif v - want > slack:
		_steer(-1)
	else:
		_steer(0)
	return dx

## The player in the current room's coordinates.
func _pos() -> Vector2:
	return player.global_position - game.world.get_origin(game.current_room)

func _feet() -> float:
	return _pos().y + player.body_size.y * 0.5

func _room_x(n: Node2D) -> float:
	return n.global_position.x - game.world.get_origin(game.current_room).x

# --- Moves --------------------------------------------------------------------------------------

## Runs to [param x] and stops there. False when it never got there (or left the room).
func _run_to(x: float, tol := 6.0, limit := 600) -> bool:
	var room := game.current_room
	for i in limit:
		var dx := _steer_to(x)
		if absf(dx) <= tol and absf(player.velocity.x) < 40.0 and player.is_on_floor():
			_steer(0)
			return true
		await _step()
		if game.current_room != room:
			return false
	_steer(0)
	return false

## Runs on (without stopping) until it is past [param x] in [param dir].
func _run_past(x: float, dir: int, limit := 400) -> bool:
	var room := game.current_room
	for i in limit:
		_steer(dir)
		if (_pos().x - x) * dir >= 0.0:
			return true
		await _step()
		if game.current_room != room:
			return false
	return false

## Waits until the player stands on something.
func _wait_floor(limit := 240) -> bool:
	for i in limit:
		if player.is_on_floor() and not game.changing_room:
			return true
		await _step()
	return false

## Jumps (a double jump with [param double]: the second at the top of the first) and steers to land
## at [param x]. True when it landed (or went through a gate into another room).
func _jump_to(x: float, double := false, limit := 180) -> bool:
	var room := game.current_room
	_press(&"jump")
	var second := not double
	var airborne := false
	for i in limit:
		_steer_to(x)
		await _step()
		if game.current_room != room:
			_let_go(&"jump")
			return true
		if not player.is_on_floor():
			airborne = true
		if not second and airborne and player.velocity.y > -60.0:
			_let_go(&"jump")
			await _step()
			_press(&"jump")
			second = true
		if airborne and player.is_on_floor():
			break
	_let_go(&"jump")
	return airborne and player.is_on_floor()

## Lands on a floor whose top is [param top] (room y) or fails.
func _check_landed(top: float, what: String) -> bool:
	if player.is_on_floor() and absf(_feet() - top) < 8.0:
		return true
	return _fail("missed %s (feet at %.0f, wanted %.0f)" % [what, _feet(), top])

## Moves in [param dir] until the game is in [param room] (through the gate there).
func _go_through(dir: int, room: String, limit := 900) -> bool:
	for i in limit:
		_steer(dir)
		await _step()
		if game.current_room == room and not game.changing_room:
			_steer(0)
			await _step(2)
			return true
	_steer(0)
	return _fail("never got through to %s" % room)

## Swings forward at what is in front (toward [param dir]) [param times] times.
func _strike(dir: int, times := 1) -> void:
	_steer(dir)
	await _step()
	_steer(0)
	for i in times:
		await _tap(&"attack")
		await _step(20)

## Sits on the room's bench (Interact), which heals and saves, and gets up again.
func _rest_at_bench(bench_x: float) -> bool:
	if not await _run_to(bench_x, 10.0):
		return _fail("could not reach the bench")
	_input_event(&"interact", true)
	_input_event(&"interact", false)
	await _step(30)
	if not player.machine.is_in(&"Rest"):
		return _fail("did not sit on the bench")
	_input_event(&"move_right", true)
	_input_event(&"move_right", false)
	await _step(10)
	return true

# --- The route ------------------------------------------------------------------------------------

func _grove_01() -> bool:
	return await _go_through(1, "Grove_02")

## Up the ledges to the canopy hole (single jumps: the double jump is up there).
func _grove_02_climb() -> bool:
	await _wait_floor()
	# [run to, jump to, ledge top]
	var climb := [[100.0, 200.0, 490.0], [278.0, 390.0, 420.0], [332.0, 220.0, 350.0], [278.0, 390.0, 280.0],
		[332.0, 220.0, 210.0], [278.0, 380.0, 140.0]]
	for c in climb:
		if not await _run_to(c[0]):
			return _fail("could not get to x %.0f" % c[0])
		await _jump_to(c[1])
		if not _check_landed(c[2], "the ledge at %.0f" % c[2]):
			return false
	# Under the hole, straight up.
	await _run_to(530.0, 3.0)
	await _jump_to(576.0)
	if game.current_room != "Grove_03":
		return _fail("did not jump up into Grove_03")
	return true

## Up through the floor: the double jump, then back down the hole.
func _grove_03() -> bool:
	# Set down beside the hole with a hop: stay on this side of it.
	for i in 20:
		_steer(-1)
		await _step()
	await _wait_floor()
	if _pos().x > 576.0:
		return _fail("landed on the far side of the hole")
	await _run_to(300.0, 10.0)
	if not player.has_ability("double_jump"):
		return _fail("did not pick up the double jump")
	for i in 400:
		_steer_to(576.0)
		await _step()
		if game.current_room == "Grove_02":
			break
	return await _arrived("Grove_02")

func _arrived(room: String) -> bool:
	for i in 30:
		if game.current_room == room and not game.changing_room:
			return true
		await _step()
	return _fail("never got to %s" % room)

## Dropped back into Grove_02: onto the hanging ledge, then double jumps up to the high ledge.
func _grove_02_high_ledge() -> bool:
	for i in 120:
		_steer_to(690.0)
		await _step()
		if player.is_on_floor():
			break
	if absf(_feet() - 560.0) < 8.0:
		# Missed the hanging ledge: double jump up to it from the floor.
		await _run_to(610.0)
		await _jump_to(700.0, true)
	if not _check_landed(420.0, "the hanging ledge"):
		return false
	await _run_to(768.0)
	await _jump_to(940.0, true)
	if not _check_landed(300.0, "the high ledge"):
		return false
	return await _go_through(1, "Grove_04")

## Spikes in a pit, a breakable wall, the health fragment behind it.
func _grove_04() -> bool:
	await _wait_floor()
	if not await _run_to(400.0):
		return _fail("could not get down to the pit")
	if not player.checkpoint_position.is_finite():
		return _fail("did not touch the checkpoint")
	await _run_past(425.0, 1)
	await _jump_to(700.0, true)
	if not _check_landed(560.0, "the floor past the spikes"):
		return false
	await _run_to(832.0)
	var wall := game.room_node.get_node_or_null(^"BreakableWall")
	for i in 3:
		if not is_instance_valid(wall) or wall.is_queued_for_deletion():
			break
		await _strike(1)
	if is_instance_valid(wall) and not wall.is_queued_for_deletion():
		return _fail("the breakable wall did not break")
	await _run_to(1010.0, 10.0)
	if kit.get_item_count("health_fragment") != 1:
		return _fail("did not pick up the health fragment")
	return await _go_through(1, "Grove_05")

## The Warden.
func _grove_05() -> bool:
	var boss := game.room_node.get_node_or_null(^"Warden") as MDSBoss
	var arena := game.room_node.get_node_or_null(^"BossArena") as MDSBossArena
	if not boss or not arena:
		return _fail("no Warden or arena")
	await _wait_floor()
	await _run_to(330.0)
	if not arena.fighting:
		return _fail("walking into the arena did not start the fight")
	if not await _fight(boss):
		return false
	await _step(30)
	return await _go_through(1, "Grove_06")

## Fights [param boss] until it falls, as a careful player would: strikes while it rests or
## recovers from a swipe, from the side with room to back off, and is out of its reach before
## the rest ends; keeps away from its swipes and slams, double jumps over its charges (and over
## it, out of a corner). Returns whether it won.
func _fight(boss: MDSBoss) -> bool:
	const LEFT := 190.0 ## where the arena's doors are (the player's middle stays between)
	const RIGHT := 962.0
	const REACH := 66.0 ## striking distance
	const CLEAR := 175.0 ## out of its swipe
	var origin := game.world.get_origin(game.current_room)
	var jump := 0 ## 0 none, 1 first jump, 2 second jump pressed
	var jump_frames := 0
	var jump_dir := 0
	var swipe_struck := false
	var last_state := &""
	for i in 60 * 180:
		if not is_instance_valid(boss) or boss.dying:
			_let_go_all()
			return true
		if player.health.is_dead():
			return _fail("the Warden won")
		var state := boss.machine.get_state()
		var t := boss.machine.time_in_state
		if state != last_state:
			swipe_struck = false
			last_state = state
		if state == &"Swipe" and boss.attack_box.active:
			swipe_struck = true
		var bx := boss.global_position.x - origin.x
		var px := _pos().x
		var to_boss := 1 if bx >= px else -1
		var dist := absf(bx - px)
		# Room behind the player (away from the boss), and on the boss's far side.
		var room_behind := (px - LEFT) if to_boss > 0 else (RIGHT - px)
		var room_beyond := (RIGHT - bx) if to_boss > 0 else (bx - LEFT)
		# A double jump in progress (the second press at the top of the first, as soon as the kit
		# allows an air jump), steering over the boss or staying put.
		if jump > 0:
			jump_frames += 1
			# Once a charge has gone by underneath, follow it to where it stops.
			if jump_dir == 0 and state == &"Charge" and jump_frames > 10 and signf(boss.velocity.x) == to_boss:
				jump_dir = to_boss
			_steer(jump_dir)
			if jump == 1 and jump_frames > 3 and player.velocity.y > -60.0:
				_let_go(&"jump")
				await _step()
				_press(&"jump")
				jump = 2
				continue
			if jump == 2 and jump_frames > 12 and player.is_on_floor():
				_let_go(&"jump")
				jump = 0
			await _step()
			continue
		var want := px
		var hit_it := false
		var go_over := false
		match state:
			&"Idle", &"Stagger", &"Dormant":
				var left := (boss.rest_time / boss.speed() - t) if state == &"Idle" else (0.8 - t + boss.rest_time / boss.speed())
				if room_behind < CLEAR - REACH + 20.0 and room_beyond > CLEAR + 40.0:
					# Cornered: over it while it rests, to strike from the open side.
					if left > 0.9 and dist < 190.0 and dist > 110.0:
						go_over = true
					elif left > 0.9:
						want = bx - to_boss * 150.0
					else:
						want = bx - to_boss * CLEAR
				elif left > 0.38:
					hit_it = true
				else:
					want = bx - to_boss * CLEAR
			&"Swipe":
				if swipe_struck and not boss.attack_box.active:
					hit_it = true
				else:
					want = bx - to_boss * CLEAR
					go_over = not boss.attack_box.active and room_behind < 60.0 and dist < 260.0 and dist > 140.0
			&"Charge":
				# Up when it will reach the player in a little over half a second: high (on the
				# second jump) when it passes under.
				var windup := 0.45 / boss.speed()
				var rush := boss.charge_speed * boss.speed()
				var arrives := maxf(0.0, windup - t) + maxf(0.0, dist - 35.0) / rush
				if t < windup or signf(boss.velocity.x) == -to_boss:
					go_over = arrives < 0.57
					want = bx - to_boss * (35.0 + 0.6 * rush)
				else:
					want = bx - to_boss * CLEAR
			&"Slam":
				if not boss.is_on_floor() and t < 0.6:
					# Away from where it will land, or under it when there is no room.
					want = px - to_boss * 220.0 if room_behind > 170.0 else px + to_boss * 260.0
				else:
					want = bx - to_boss * CLEAR
			&"Volley":
				want = bx - to_boss * CLEAR
				go_over = t > 0.25 and t < 0.35
			_:
				want = px
		if go_over:
			jump = 1
			jump_frames = 0
			jump_dir = to_boss if state in [&"Idle", &"Stagger", &"Swipe"] else (-to_boss if state == &"Volley" and room_behind > 120.0 else 0)
			_press(&"jump")
			_steer(jump_dir)
			await _step()
			continue
		if hit_it:
			want = bx - to_boss * REACH
		want = clampf(want, LEFT, RIGHT)
		if hit_it and absf(want - px) < 14.0:
			# In reach: face it and swing (no steering away mid-swing).
			_steer(to_boss if player.facing != to_boss else 0)
			if not player.attacks.is_attacking() or player.attacks.phase == MDSAttackController.Phase.RECOVERY:
				_press(&"attack")
			else:
				_let_go(&"attack")
		else:
			_let_go(&"attack")
			if hit_it and player.attacks.is_attacking() and signi(want - px) != player.facing:
				_steer(0)
			else:
				_steer_to(want)
		await _step()
	return _fail("the fight went on too long (Warden at %d)" % boss.health.current)

## The dash, then on to the lava.
func _grove_06() -> bool:
	await _wait_floor()
	await _run_to(620.0, 10.0)
	if not player.has_ability("dash"):
		return _fail("did not pick up the dash")
	if player.health.current < player.health.get_max():
		if not await _rest_at_bench(300.0):
			return false
		if player.health.current < player.health.get_max():
			return _fail("resting did not heal")
	return await _go_through(1, "Grove_07")

## Dashes from stone to stone under the low ceiling.
func _grove_07() -> bool:
	await _wait_floor()
	var edges := [300.0, 460.0, 620.0, 780.0]
	var tries := 0
	while _pos().x < 870.0:
		tries += 1
		if tries > 10:
			return _fail("could not dash across the lava")
		var edge := 0.0
		for e: float in edges:
			if e > _pos().x - 20.0:
				edge = e
				break
		await _run_to(edge - 6.0, 4.0)
		for i in 60:
			if player.dash_cooldown_left <= 0.0 and player.is_on_floor():
				break
			await _step()
		_hold(&"move_right")
		_press(&"dash")
		await _step()
		_let_go(&"dash")
		await _step(6)
		await _wait_floor()
		_steer(0)
		await _step(2)
	return await _go_through(1, "Gardens_01")

## Down the hole to Gardens_02.
func _gardens_01_down() -> bool:
	await _wait_floor()
	for i in 600:
		_steer_to(576.0)
		await _step()
		if game.current_room == "Gardens_02":
			break
	return await _arrived("Gardens_02")

## The red key past the Charger, then up the garden ledges.
func _gardens_02() -> bool:
	for i in 120:
		_steer_to(576.0)
		await _step()
		if player.is_on_floor():
			break
	var charger := game.room_node.get_node_or_null(^"Charger") as MDSEnemy
	if not await _run_avoiding(990.0, charger):
		return _fail("could not get to the red key")
	if not kit.has_item("red_key"):
		return _fail("did not pick up the red key")
	if not await _run_avoiding(300.0, charger):
		return _fail("could not get back to the ledges")
	var climb := [[300.0, 400.0, 430.0], [340.0, 215.0, 300.0], [280.0, 420.0, 170.0]]
	for c in climb:
		await _run_to(c[0])
		await _jump_to(c[1], true)
		if not _check_landed(c[2], "the garden ledge at %.0f" % c[2]):
			return false
	await _run_to(538.0, 3.0)
	await _jump_to(576.0, true)
	if game.current_room != "Gardens_01":
		return _fail("did not jump up into Gardens_01")
	return true

## Runs to [param x], jumping over [param enemy] when it rushes in.
func _run_avoiding(x: float, enemy: MDSEnemy, limit := 900) -> bool:
	for i in limit:
		var near := is_instance_valid(enemy) and not enemy.dying
		if near:
			var ex := _room_x(enemy)
			var coming := absf(enemy.velocity.x) > 200.0 and signf(enemy.velocity.x) == signf(_pos().x - ex)
			if coming and absf(ex - _pos().x) < 170.0 and player.is_on_floor():
				await _jump_to(_pos().x + signf(x - _pos().x) * 60.0, true)
				continue
		if absf(_steer_to(x)) < 8.0 and player.is_on_floor():
			_steer(0)
			return true
		await _step()
	return false

## Back up through the hole with the key: the locked door opens for it.
func _gardens_01_door() -> bool:
	for i in 30:
		_steer(-1)
		await _step()
	await _wait_floor()
	await _run_to(420.0)
	await _run_past(490.0, 1)
	await _jump_to(720.0, true)
	if not _check_landed(560.0, "the floor past the hole"):
		return false
	var door := game.room_node.get_node_or_null(^"RedKeyBarrier") as MDSGateBarrier
	if not door or not door.is_open:
		return _fail("the locked door did not open for the red key")
	return await _go_through(1, "Gardens_03")

## Strikes the bridge switch, then over the dip to the open way out.
func _gardens_03() -> bool:
	await _wait_floor()
	await _run_to(296.0)
	await _strike(1)
	if kit.get_flag("bridge_lowered") != true:
		return _fail("striking the switch did not lower the bridge")
	await _run_past(430.0, 1)
	await _jump_to(780.0, true)
	if not _check_landed(560.0, "the floor past the dip"):
		return false
	return await _go_through(1, "Gardens_04")

## The wall jump.
func _gardens_04() -> bool:
	await _wait_floor()
	if player.health.current < player.health.get_max():
		if not await _rest_at_bench(300.0):
			return false
	await _run_to(700.0, 10.0)
	if not player.has_ability("wall_jump"):
		return _fail("did not pick up the wall jump")
	return await _go_through(1, "Gardens_05")

## Up the shaft from wall to wall to the ending: a double jump straight up into it, then a
## wall jump off each wall in turn.
func _gardens_05() -> bool:
	await _wait_floor()
	await _run_to(576.0, 3.0)
	var end := game.room_node.get_node_or_null(^"EndingTrigger")
	_press(&"jump")
	var side := -1
	var second := false
	var airborne := false
	for i in 900:
		if end and end.get_meta(&"demo_completed", false):
			_let_go_all()
			return true
		if not player.is_on_floor():
			airborne = true
		if not second:
			_steer_to(576.0)
			if airborne and player.velocity.y > -60.0:
				_let_go(&"jump")
				await _step()
				_press(&"jump")
				second = true
		elif player.machine.is_in(&"WallSlide"):
			_let_go(&"jump")
			await _step()
			_press(&"jump")
			side = -side
		else:
			# Toward the next wall once inside the shaft.
			_steer(side if _feet() < 440.0 else 0)
		await _step()
		if airborne and player.is_on_floor():
			return _fail("fell back down the shaft")
	return _fail("never reached the EndingTrigger")
