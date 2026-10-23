extends "res://tests/test_case.gd"
## Markers on the map with a title and a description while playing: a boss room (titled by its
## boss), a locked door (what it needs said for it), a key, a quest's target (one id, moved as the
## quest goes on), and markers of any kind with a color and an icon of their own. Each kind has
## its icon; kinds of one's own (a color, an icon or a texture) join every map. Pointed at (the
## mouse over it, or the middle of the map on a gamepad), a marker's description shows. The
## full map zooms out below its fit, as far as min_zoom.

const Fixture := preload("res://tests/game_fixture.gd")
const DIR := TMP + "/map_markers"
const EXPLORED := DIR + "/markers_exploration.json"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))
	MDSGameplaySetup.ensure_runtime_actions()
	Fixture.build()
	_kinds()
	await _game_markers()
	await _info_and_zoom()

func _kinds() -> void:
	var all := MDSWorldMapView.MARKER_KINDS
	check(all.keys().all(func(k: String) -> bool: return str(all[k].icon) in MDSWorldMapView.MARKER_ICONS and all[k].color is Color), "every kind has an icon of its own and a color")
	check(all.boss.icon == "skull" and all.locked_door.icon == "lock" and all.key.icon == "key" and all.quest.icon == "star", "a boss is a skull, a locked door a padlock, a key a key, a quest a star")
	MDSWorldMapView.define_marker_kind("shop", Color.GOLD, "gem")
	var st := MDSWorldMapView.marker_style({"kind": "shop"})
	check(st.color == Color.GOLD and st.icon == "gem" and st.name == "Shop", "a kind of one's own (define_marker_kind)")
	st = MDSWorldMapView.marker_style({"kind": "boss", "color": Color.GREEN.to_html(), "icon": "cross"})
	check(st.color.is_equal_approx(Color.GREEN) and st.icon == "cross", "a marker's own color and icon win over its kind's")
	st = MDSWorldMapView.marker_style({"kind": "no_such_kind"})
	check(st.icon == "flag" and st.color == MDSWorldMapView.MARKER_KINDS.pin.color, "an unknown kind looks like a pin")
	var tex := PlaceholderTexture2D.new()
	ResourceSaver.save(tex, DIR + "/icon.tres")
	st = MDSWorldMapView.marker_style({"kind": "pin", "icon": DIR + "/icon.tres"})
	check(st.icon is Texture2D, "an icon can be a texture, by its path")
	MDSWorldMapView.define_marker_kind("npc", Color.SKY_BLUE, tex, "Villager")
	check(MDSWorldMapView.marker_style({"kind": "npc"}).icon == tex, "or given to a kind")
	MDSWorldMapView.marker_kinds.erase("shop")
	MDSWorldMapView.marker_kinds.erase("npc")

func _game_markers() -> void:
	var game := Fixture.make_game(EXPLORED, "")
	game.starting_room = "Garden_01"
	add_child(game)
	await game.room_loaded
	var world := game.world
	world.data.rooms["Crypt_01"].boss = "Bone Warden"
	world.get_gate("Garden_02", "right1").requires = ["item:crypt_key", "dash"]
	var b := game.mark_boss_room("Crypt_01", "", "It guards the lift.")
	var m := game.get_map_marker(b)
	check(b == "boss_Crypt_01" and m.kind == "boss" and m.label == "Bone Warden" and m.description == "It guards the lift.", "a boss room, titled by its boss (%s)" % [m])
	check(MDSWorldMapView.pin_position(m) == world.get_room_label_pos("Crypt_01") and int(m.layer) == world.get_room_layer("Crypt_01"), "in the room's middle, on its layer")
	var d := game.mark_locked_door("Garden_02", "right1")
	m = game.get_map_marker(d)
	check(d == "door_Garden_02_right1" and m.kind == "locked_door" and MDSWorldMapView.pin_position(m) == world.get_gate_world_pos("Garden_02", "right1"), "a locked door, on its gate")
	check(m.description == "Needs Crypt Key and Dash", "saying what it needs ('%s')" % m.description)
	check(game.mark_locked_door("Garden_02", "no_such_gate").is_empty() and game.mark_boss_room("Nowhere").is_empty(), "no gate or room, no marker")
	var key_node := Node2D.new()
	game.room_node.add_child(key_node)
	key_node.position = Vector2(500, 400)
	var k := game.mark_key(key_node, "Crypt key", "Under the old roots.")
	check(game.get_map_marker(k).kind == "key" and MDSWorldMapView.pin_position(game.get_map_marker(k)).is_equal_approx(key_node.global_position), "a key, where its node is")
	var q := game.mark_quest_target("Garden_02", "The elder", "Talk to the elder.")
	game.mark_quest_target(world.get_origin("Crypt_01") + Vector2(300, 500), "The lift", "Ride the old lift down.")
	check(q == "quest" and game.get_map_marker("quest").label == "The lift" and game.map_pins.keys().count("quest") == 1, "a quest's target moves as the quest goes on")
	var own := game.add_map_marker(world.get_origin("Garden_01") + Vector2(700, 500), "danger", "Thorns", "Mind your step.", {"color": Color.ORANGE, "icon": "cross"})
	m = game.get_map_marker(own)
	check(Color.html(m.color).is_equal_approx(Color.ORANGE) and m.icon == "cross", "a marker of its own color and icon")
	check(game.add_map_marker("Nowhere", "note", "?").is_empty(), "nowhere: no marker")
	check(game.map_view.pins.size() == game.map_pins.size() and game.map_view.pins[b].description == "It guards the lift.", "the game's map shows them, descriptions and all")
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPLORED))
	check(file.pins[b].description == "It guards the lift." and file.pins[own].icon == "cross", "kept at once, descriptions and looks too")
	check(MDSWorldGame.describe_requires([]).is_empty() and MDSWorldGame.describe_requires(["dash"]) == "Needs Dash" and MDSWorldGame.describe_requires(["boss:Warden"]) == "Needs defeating Warden", "what a door needs, in words")
	game.queue_free()
	await get_tree().process_frame

func _info_and_zoom() -> void:
	var map := MDSWorldMapView.new()
	map.world_file = Fixture.WORLD
	map.reveal_all = true
	map.zoomable = true
	map.size = Vector2(700, 320)
	add_child(map)
	await get_tree().process_frame
	var fit := map._fit_scale
	var middle := map._bounds.get_center()
	var boss_at := map.world.get_room_label_pos("Crypt_01")
	map.set_pin("boss", boss_at, 0, "boss", "Bone Warden", "It guards the lift.")
	map.set_pin("key", middle, 0, "key", "Crypt key")
	await get_tree().process_frame
	var said: Array = []
	map.marker_focused.connect(func(id: String) -> void: said.append(id))
	var over := InputEventMouseMotion.new()
	over.position = map._offset + boss_at * map._scale + Vector2(0, -MDSWorldMapView.MARKER_LIFT)
	map._gui_input(over)
	check(map.focused_pin == "boss" and said == ["boss"], "the mouse over a marker points at it")
	map.queue_redraw()
	await get_tree().process_frame
	over.position = Vector2(5, 5)
	map._gui_input(over)
	check(map.focused_pin.is_empty(), "and away, at none")
	# A gamepad: the marker in the middle of the map, as the stick moves it.
	Input.action_press(&"map_pan_right", 0.5)
	map._process(0.016)
	Input.action_release(&"map_pan_right")
	check(map.focused_pin == "key", "on a gamepad, the marker in the middle (%s)" % map.focused_pin)
	map.remove_pin("key")
	check(map.focused_pin.is_empty(), "a marker taken away isn't pointed at")
	# Zoomed out below the fit: the rooms small in the middle.
	map.set_zoom(0.01)
	await get_tree().process_frame
	check(is_equal_approx(map.zoom, map.min_zoom) and is_equal_approx(map._scale, fit * map.min_zoom), "it zooms out as far as min_zoom (%.2f)" % map.zoom)
	check(map.screen_to_world(map.size / 2.0).distance_to(middle) < 1.0, "the rooms in the middle")
	map.reset_view()
	await get_tree().process_frame
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = map.size / 2.0
	map._gui_input(wheel)
	check(map.zoom < 1.0, "the wheel goes below the fit too (%.2f)" % map.zoom)
	map.min_zoom = 0.6
	map.set_zoom(0.1)
	check(is_equal_approx(map.zoom, 0.6), "min_zoom says how far")
	map.queue_free()
	await get_tree().process_frame
