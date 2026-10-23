extends "res://tests/test_case.gd"
## Pins on the map while playing. MDSWorldGame.add_map_pin puts one (kind, label, an id to move
## it by), remove_map_pin / clear_map_pins take them away, pin_player_position pins where the
## player is. The game keeps them like the explored map: in the exploration file at once, in the
## save, on its maps. The map draws them as flags and, with pins_editable (the pause menu's),
## asks for one where it is clicked and takes the player's own away when one is clicked; the
## pause menu's Pin where I am pins the player. The editor's World map shows the playtest's pins.
## With zoomable (the pause menu's map) the full map zooms (wheel, map_zoom_in / out) around the
## point under the mouse, moves (a drag, map_pan_*) without leaving the rooms, and opens on the
## player; a drag is no click, and clicks put pins where they point at any zoom.

const Fixture := preload("res://tests/game_fixture.gd")
const DIR := TMP + "/map_pins"
const EXPLORED := DIR + "/pins_exploration.json"
const SAVE := DIR + "/pins_save.json"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))
	MDSGameplaySetup.ensure_runtime_actions()
	Fixture.build()
	_map_alone()
	await _zoom()
	await _playing()
	await _kept()
	await _pause_menu()
	await _editor()
	get_tree().paused = false

func _map_alone() -> void:
	var map := MDSWorldMapView.new()
	map.set_pin("a", Vector2(100, 50), 0, "danger", "Spikes")
	map.set_pin("b", Vector2(300, 50), 0)
	check(map.pins.size() == 2 and MDSWorldMapView.pin_position(map.pins.a) == Vector2(100, 50) and map.pins.a.kind == "danger" and map.pins.b.kind == "pin", "a map takes pins of its own (set_pin)")
	map.set_pin("a", Vector2(120, 60), 0, "danger", "Spikes")
	check(map.pins.size() == 2 and MDSWorldMapView.pin_position(map.pins.a) == Vector2(120, 60), "the same id moves it")
	var saved := map.get_save_data()
	var other := MDSWorldMapView.new()
	other.set_save_data(saved)
	check(other.pins.size() == 2 and other.pins.a.label == "Spikes", "they are saved with the map")
	map.clear_pins("pin")
	check(map.pins.keys() == ["a"], "clear_pins(kind) takes that kind away")
	check(map.remove_pin("a") and map.pins.is_empty() and not map.remove_pin("a"), "remove_pin")
	var kinds := MDSWorldMapView.marker_kinds
	check(kinds.has("quest") and kinds.has("danger") and kinds.pin.color != kinds.quest.color, "each kind has its color")
	map.free()
	other.free()

func _wheel(map: MDSWorldMapView, at: Vector2, up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = at
	map._gui_input(e)

func _zoom() -> void:
	var map := MDSWorldMapView.new()
	map.world_file = Fixture.WORLD
	map.reveal_all = true
	map.zoomable = true
	map.size = Vector2(600, 300)
	add_child(map)
	await get_tree().process_frame
	var fit := map._fit_scale
	check(fit > 0.0 and is_equal_approx(map._scale, fit) and map.clip_contents, "a zoomable map starts showing every room revealed, clipped to itself")
	# On the middle line: along it the rooms fit, so the map stays centred up and down.
	var at := map.size / 2.0 + Vector2(40, 0)
	var under := map.screen_to_world(at)
	map.set_zoom(2.0, at)
	check(is_equal_approx(map._scale, fit * 2.0) and map.screen_to_world(at).distance_to(under) < 1.0, "zoomed, the point under the mouse stays put")
	_wheel(map, at, true)
	check(is_equal_approx(map.zoom, 2.0 * MDSWorldMapView.ZOOM_STEP), "the wheel zooms (%.2f)" % map.zoom)
	_wheel(map, at, false)
	check(is_equal_approx(map.zoom, 2.0), "and back")
	map.set_zoom(1000.0)
	check(is_equal_approx(map.zoom, map.max_zoom), "no further than max_zoom")
	map.set_zoom(3.0)
	await get_tree().process_frame
	# A drag moves it, and is no click.
	var asked: Array = []
	map.pins_editable = true
	map.pin_requested.connect(func(wp: Vector2, _l: int) -> void: asked.append(wp))
	var before := map.screen_to_world(map.size / 2.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = map.size / 2.0
	map._gui_input(press)
	var move := InputEventMouseMotion.new()
	move.position = map.size / 2.0 + Vector2(40, 0)
	move.relative = Vector2(40, 0)
	map._gui_input(move)
	var release := press.duplicate()
	release.pressed = false
	release.position = move.position
	map._gui_input(release)
	var after := map.screen_to_world(map.size / 2.0)
	check(asked.is_empty() and is_equal_approx(after.x, before.x - 40.0 / map._scale), "a drag moves the map with the mouse, and puts no pin")
	map.pan_by(Vector2(-100000, -100000))
	var b := map._bounds
	var mid := map.screen_to_world(map.size / 2.0)
	check(b.grow(1.0).has_point(mid), "it never moves off the rooms (%s in %s)" % [mid, b])
	_click(map, at)
	check(asked.size() == 1 and asked[0].distance_to(map.screen_to_world(at)) < 0.5, "zoomed in, a click asks for a pin where it points")
	# The gamepad's way: map_zoom_in / map_pan_right held.
	map.set_zoom(2.0)
	map.center_on(b.get_center())
	var z := map.zoom
	Input.action_press(&"map_zoom_in", 1.0)
	map._process(0.5)
	Input.action_release(&"map_zoom_in")
	check(map.zoom > z * 1.5, "map_zoom_in (RT) zooms in (%.2f)" % map.zoom)
	var x := map.screen_to_world(map.size / 2.0).x
	Input.action_press(&"map_pan_right", 1.0)
	map._process(0.1)
	Input.action_release(&"map_pan_right")
	check(map.screen_to_world(map.size / 2.0).x > x, "map_pan_right (the right stick) looks right")
	map.reset_view()
	await get_tree().process_frame
	check(map.zoom == 1.0 and is_equal_approx(map._scale, fit), "reset_view shows every room again")
	map.zoomable = false
	map.set_zoom(4.0)
	await get_tree().process_frame
	check(is_equal_approx(map._scale, fit), "a map that isn't zoomable stays fitted")
	map.queue_free()
	await get_tree().process_frame

func _game() -> MDSWorldGame:
	var game := Fixture.make_game(EXPLORED, SAVE)
	game.starting_room = "Garden_01"
	return game

func _playing() -> void:
	var game := _game()
	add_child(game)
	await game.room_loaded
	var added: Array = []
	var removed: Array = []
	game.map_pin_added.connect(func(id: String) -> void: added.append(id))
	game.map_pin_removed.connect(func(id: String) -> void: removed.append(id))
	var origin := game.world.get_origin("Garden_01")
	var a := game.add_map_pin(origin + Vector2(200, 300))
	var b := game.add_map_pin(origin + Vector2(400, 300), "danger", "Thorns")
	check(a == "pin_1" and b == "pin_2" and added == ["pin_1", "pin_2"], "add_map_pin makes ids and says so (%s)" % [added])
	check(game.map_pins[b].kind == "danger" and game.map_pins[b].label == "Thorns" and int(game.map_pins[b].layer) == game.world.get_room_layer("Garden_01"), "with its kind, label and the layer the player is on")
	check(game.map_view.pins.has(a) and game.map_view.pins.has(b), "the game's map shows them")
	var q := game.add_map_pin(origin + Vector2(600, 200), "quest", "The elder", "quest_elder")
	game.add_map_pin(origin + Vector2(700, 200), "quest", "The elder", "quest_elder")
	check(q == "quest_elder" and MDSWorldMapView.pin_position(game.map_pins.quest_elder) == origin + Vector2(700, 200) and game.map_pins.size() == 3, "an id of one's own moves that pin (a quest's)")
	var here := game.pin_player_position()
	check(MDSWorldMapView.pin_position(game.map_pins[here]).is_equal_approx(game.player.global_position), "pin_player_position pins where the player is")
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPLORED))
	check((file.get("pins", {}) as Dictionary).size() == 4, "the exploration file keeps them at once")
	check(game.remove_map_pin(a) and removed == [a] and not game.map_view.pins.has(a) and not game.remove_map_pin(a), "remove_map_pin takes one away, from the map too")
	game.clear_map_pins("pin")
	check(game.map_pins.keys() == ["pin_2", "quest_elder"], "clear_map_pins(kind) only that kind (%s)" % [game.map_pins.keys()])
	check(game.save_game() == OK, "saved")
	game.remove_map_pin("pin_2")
	game.queue_free()
	await get_tree().process_frame

func _kept() -> void:
	# Started again: the pins are as they were last, not as saved (pin_2 went after saving).
	var game := _game()
	add_child(game)
	await game.room_loaded
	check(game.map_pins.keys() == ["quest_elder"] and game.map_view.pins.keys() == ["quest_elder"], "a game started again has its pins as they were last (%s)" % [game.map_pins.keys()])
	game.queue_free()
	await get_tree().process_frame
	# Without an exploration file, the save's.
	var saved := _game()
	saved.exploration_file = ""
	add_child(saved)
	await saved.room_loaded
	check(saved.map_pins.has("pin_2") and saved.map_pins.has("quest_elder") and saved.map_view.pins.has("pin_2"), "without an exploration file, the save keeps them")
	saved.queue_free()
	await get_tree().process_frame
	# A new game starts with none.
	var fresh := _game()
	add_child(fresh)
	await fresh.room_loaded
	fresh.new_game()
	await fresh.room_loaded
	check(fresh.map_pins.is_empty() and fresh.map_view.pins.is_empty(), "a new game has no pins")
	fresh.add_map_pin(fresh.world.get_origin("Garden_01") + Vector2(300, 300), "quest", "Go", "quest_go")
	fresh.queue_free()
	await get_tree().process_frame

func _click(map: MDSWorldMapView, at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		map._gui_input(e)

func _pause_menu() -> void:
	var game := _game()
	var menu := MDSPauseMenu.new()
	menu.name = "PauseMenu"
	game.get_node("UI").add_child(menu)
	add_child(game)
	await game.room_loaded
	# A screen's size (the test's window is tiny).
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.size = Vector2(1152, 648)
	menu.open(MDSPauseMenu.Tab.MAP)
	await get_tree().process_frame
	await get_tree().process_frame
	var map := menu.map
	check(map.pins_editable and map.zoomable and map.pins.has("quest_go"), "the pause menu's map shows the game's pins, takes clicks and zooms")
	var at := map.size / 2.0 + Vector2(37, 11)
	var want := map.screen_to_world(at)
	_click(map, at)
	var mine: Array = game.map_pins.keys().filter(func(id: String) -> bool: return game.map_pins[id].kind == "pin")
	check(mine.size() == 1 and MDSWorldMapView.pin_position(game.map_pins[mine[0]]).is_equal_approx(want) and map.pins.has(mine[0]), "a click on the map puts a pin there")
	await get_tree().process_frame
	_click(map, map._offset + MDSWorldMapView.pin_position(game.map_pins.quest_go) * map._scale)
	check(game.map_pins.has("quest_go"), "a click on a quest's pin leaves it")
	_click(map, at)
	check(not game.map_pins.has(mine[0]) and not map.pins.has(mine[0]), "a click on the player's own pin takes it away")
	menu.pin_here.pressed.emit()
	var placed: Array = game.map_pins.keys().filter(func(id: String) -> bool: return game.map_pins[id].kind == "pin")
	check(placed.size() == 1 and MDSWorldMapView.pin_position(game.map_pins[placed[0]]).is_equal_approx(game.player.global_position), "Pin where I am pins the player")
	# Zoomed in, the map opens on the player.
	map.set_zoom(4.0)
	map.center_on(Vector2(-99999, -99999))
	menu.close()
	menu.open(MDSPauseMenu.Tab.MAP)
	await get_tree().process_frame
	var mid := map.screen_to_world(map.size / 2.0)
	var player_on_screen := map._offset + game.player.global_position * map._scale
	check(map.zoom == 4.0 and Rect2(Vector2.ZERO, map.size).has_point(player_on_screen), "opened again, it keeps its zoom and shows the player (%s)" % mid)
	menu.close()
	game.queue_free()
	await get_tree().process_frame

func _editor() -> void:
	var e := MDSWorldGame.read_exploration(MDSWorld.load_world(Fixture.WORLD), DIR)
	check(e.get("file", "") == EXPLORED and (e.get("pins", {}) as Dictionary).has("quest_go"), "the editor's World map reads the playtest's pins")
	var canvas := MDSWorldCanvas.new()
	canvas.size = Vector2(800, 400)
	canvas.exploration_dir = DIR
	add_child(canvas)
	canvas.set_data(MDSWorld.load_world(Fixture.WORLD), null, {})
	canvas.set_show("explored", true)
	canvas.fit_to_layer()
	canvas.redraw()
	check(canvas.explored.has("pins"), "and draws them with the rest explored")
	await get_tree().process_frame
	canvas.queue_free()
	await get_tree().process_frame
