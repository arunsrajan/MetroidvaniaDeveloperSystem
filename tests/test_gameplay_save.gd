extends "res://tests/test_case.gd"
## Gameplay Kit, phase 1: the kit's save data in ext.gameplay (a round trip through
## get_save_data / set_save_data and through the save file), a 3.3.0 save without ext loading with
## the kit's defaults, migrations from older versions, new_game resetting it, and save files
## written through a .tmp file so an interrupted write leaves the old save whole.

const Fixture := preload("res://tests/game_fixture.gd")
const SAVE := "user://mds_test_gameplay_save.json"

func _run() -> void:
	_clean()
	Fixture.build()
	var game := _game()
	add_child(game)
	await game.room_loaded
	var kit := MDSGameplay.find(game)
	kit.add_item("red_key")
	kit.add_item("health_fragment", 3)
	kit.add_currency(240)
	kit.set_flag("met_elder")
	kit.raise_max_health(1)
	kit.set_health(4)
	kit.set_mana(30)
	kit.deaths = 4
	kit.play_time = 12.5
	kit.defeat_until_rest("Garden_01/Guard")
	kit.corpse = {"room": "Garden_02", "position": [412, 500], "currency": 120}
	var data := game.get_save_data()
	check(data.has("ext") and data.ext.has("gameplay"), "the save has ext.gameplay")
	var g: Dictionary = data.ext.gameplay
	check(int(g.version) == MDSGameplay.VERSION and int(g.items.red_key) == 1 and int(g.items.health_fragment) == 3, "items and version")
	check(int(g.currency) == 240 and MDSGameplay.truthy(g.flags.met_elder) and int(g.max_health) == 6 and int(g.health) == 4 and int(g.mana) == 30, "currency, flags, health, mana")
	check(g.corpse.room == "Garden_02" and (g.rest_defeated as Array).has("Garden_01/Guard") and int(g.deaths) == 4, "corpse, rest_defeated, deaths")
	# Through JSON, into another game.
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(data))
	game.queue_free()
	await get_tree().process_frame
	var other := _game()
	add_child(other)
	await other.room_loaded
	var kit2 := MDSGameplay.find(other)
	other.set_save_data(round_trip)
	await other.room_loaded
	check(kit2.get_item_count("red_key") == 1 and kit2.get_item_count("health_fragment") == 3 and kit2.currency == 240, "loaded: items and currency")
	check(kit2.get_flag("met_elder") == true and kit2.max_health == 6 and kit2.health == 4 and kit2.mana == 30 and kit2.deaths == 4, "flags, health, mana, deaths")
	check(kit2.corpse.get("currency") == 120 and kit2.rest_defeated.has("Garden_01/Guard") and absf(kit2.play_time - 12.5) < 1.0, "corpse, rest_defeated, play time (%.2f)" % kit2.play_time)
	# A 3.3.0 save: no ext.
	var old := round_trip.duplicate(true)
	old.erase("ext")
	other.set_save_data(old)
	await other.room_loaded
	check(kit2.items.is_empty() and kit2.currency == 0 and kit2.flags.is_empty() and kit2.max_health == 5, "a save without ext loads with the kit's defaults")
	check(other.current_room == round_trip.room, "and the rest of it as before")
	# Migrations.
	var v0 := {"items": {"red_key": 2}, "currency": 9}
	var migrated := MDSGameplay.migrate(v0.duplicate(true))
	check(int(migrated.version) == MDSGameplay.VERSION and int(migrated.items.red_key) == 2, "data without a version is migrated to %d" % MDSGameplay.VERSION)
	other.set_save_data({"room": "Garden_01", "ext": {"gameplay": v0}})
	await other.room_loaded
	check(kit2.get_item_count("red_key") == 2 and kit2.currency == 9, "and loads")
	# Save file.
	kit2.add_item("lantern")
	check(other.save_game() == OK and FileAccess.file_exists(SAVE) and not FileAccess.file_exists(SAVE + ".tmp"), "save_game writes the file, no .tmp left")
	var on_disk := other.read_save_game()
	check(on_disk.has("ext") and int(on_disk.ext.gameplay.items.lantern) == 1, "with ext.gameplay")
	kit2.remove_item("lantern")
	check(other.load_game(), "load_game")
	await other.room_loaded
	check(kit2.get_item_count("lantern") == 1, "brings the kit's data back")
	# new_game resets the kit.
	other.new_game()
	await other.room_loaded
	check(kit2.items.is_empty() and kit2.currency == 0, "new_game starts the kit over")
	other.queue_free()
	await get_tree().process_frame
	_atomic()
	_clean()

func _game() -> MDSWorldGame:
	var game := Fixture.make_game("", SAVE)
	var kit := MDSGameplay.new()
	kit.name = "Gameplay"
	game.add_child(kit)
	return game

func _atomic() -> void:
	var path := "user://mds_test_atomic.json"
	check(MDSWorldGame._write_json(path, {"n": 1}) == OK and MDSWorldGame._write_json(path, {"n": 2}) == OK, "writing over an existing file works")
	check(JSON.parse_string(FileAccess.get_file_as_string(path)).n == 2.0 and not FileAccess.file_exists(path + ".tmp"), "the new data, no .tmp")
	# A write that dies half-way leaves its .tmp half written: the save itself is untouched.
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	f.store_string("{\"n\": 3, \"broken")
	f.close()
	check(JSON.parse_string(FileAccess.get_file_as_string(path)).n == 2.0, "an interrupted write leaves the old file whole")
	check(MDSWorldGame._write_json(path, {"n": 4}) == OK and JSON.parse_string(FileAccess.get_file_as_string(path)).n == 4.0, "and the next save replaces the stale .tmp")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _clean() -> void:
	for p in [SAVE, SAVE + ".tmp", "user://mds_test_atomic.json.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
