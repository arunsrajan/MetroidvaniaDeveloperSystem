extends "res://tests/test_case.gd"
## Gameplay Kit, phase 1: the condition grammar (item:, item:x>=n, flag:, the old strings
## unchanged), MDSWorldGame.is_condition_met handing item and flag conditions to MDSGameplay, gate
## barriers opening on an item or a flag (and using up the key with consume_items), map gates
## refusing the player without the item, and equipment lending abilities.

const Fixture := preload("res://tests/game_fixture.gd")

var game: MDSWorldGame
var kit: MDSGameplay

func _run() -> void:
	_grammar()
	Fixture.build()
	game = Fixture.make_game()
	kit = MDSGameplay.new()
	kit.name = "Gameplay"
	game.add_child(kit)
	add_child(game)
	await game.room_loaded
	await get_tree().process_frame
	_delegation()
	await _barriers()
	await _map_gates()
	_equipment()
	game.queue_free()
	await get_tree().process_frame
	await _without_kit()

func _grammar() -> void:
	check(MDSAnnotations.parse_condition("item:red_key") == ["item", "red_key"], "item:red_key")
	check(MDSAnnotations.parse_condition("item:health_fragment>=4") == ["item", "health_fragment>=4"], "item:health_fragment>=4")
	check(MDSAnnotations.parse_item_requirement("health_fragment>=4") == ["health_fragment", 4], "its id and count")
	check(MDSAnnotations.parse_item_requirement("Red Key") == ["red_key", 1], "a plain id counts 1, lowercased")
	check(MDSAnnotations.parse_condition("flag:bridge_lowered") == ["flag", "bridge_lowered"], "flag:bridge_lowered")
	check(MDSAnnotations.parse_condition("dash") == ["ability", "dash"], "a bare name is still an ability")
	check(MDSAnnotations.parse_condition("ability:dash") == ["ability", "dash"], "ability:dash unchanged")
	check(MDSAnnotations.parse_condition("object:Crypt_01/Chest") == ["object", "Crypt_01/Chest"], "object: unchanged")
	check(MDSAnnotations.parse_condition("boss:Moss Mother") == ["boss", "Moss Mother"], "boss: unchanged")

func _delegation() -> void:
	check(MDSGameplay.find(game) == kit, "the game finds its MDSGameplay")
	check(not game.is_condition_met("item:red_key"), "no red key yet")
	kit.add_item("red_key")
	check(game.is_condition_met("item:red_key") and kit.get_item_count("red_key") == 1, "item:red_key after add_item")
	kit.add_item("health_fragment", 3)
	check(not game.is_condition_met("item:health_fragment>=4"), "3 fragments are not 4")
	kit.add_item("health_fragment")
	check(game.is_condition_met("item:health_fragment>=4"), "4 fragments are")
	check(not game.is_condition_met("flag:bridge_lowered"), "flag not set")
	kit.set_flag("bridge_lowered")
	check(game.is_condition_met("flag:bridge_lowered"), "flag:bridge_lowered after set_flag")
	kit.set_flag("bridge_lowered", false)
	check(not game.is_condition_met("flag:bridge_lowered"), "false is unset")
	kit.set_flag("Bridge Lowered", 1)
	check(game.is_condition_met("flag:bridge_lowered"), "flag names are lowercase with underscores; 1 is set")
	check(kit.remove_item("red_key") and not game.is_condition_met("item:red_key") and not kit.remove_item("red_key"), "remove_item takes it, and refuses when there is none")
	check(not game.is_condition_met("dash"), "abilities as before")
	game.grant_ability("dash")
	check(game.is_condition_met("dash") and game.is_condition_met("ability:dash"), "dash, ability:dash")

func _barrier(requires: PackedStringArray, consume := false) -> MDSGateBarrier:
	var b := MDSGateBarrier.new()
	b.requires = requires
	b.consume_items = consume
	b.open_time = 0.01
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(32, 128)
	cs.shape = r
	b.add_child(cs)
	game.room_node.add_child(b)
	return b

func _barriers() -> void:
	var key_door := _barrier(["item:red_key"], true)
	var bridge := _barrier(["flag:lever_pulled"])
	await get_tree().process_frame
	check(not key_door.is_open and not bridge.is_open, "the barriers start shut")
	kit.add_item("red_key")
	check(key_door.is_open, "an item:red_key barrier opens on add_item")
	check(kit.get_item_count("red_key") == 0, "consume_items uses the key up")
	kit.set_flag("lever_pulled")
	check(bridge.is_open, "a flag:lever_pulled barrier opens on set_flag")
	check(game.is_object_stored(game.object_id(bridge)), "and stays open (stored)")

func _map_gates() -> void:
	var gate := game.world.get_gate("Garden_01", "right1")
	gate["requires"] = ["item:gate_pass"]
	game.enforce_requirements = true
	var blocked: Array = []
	game.transition_blocked.connect(func(_t: Dictionary, missing: PackedStringArray) -> void: blocked.append(missing))
	game._on_gate_entered({"room": "Garden_02", "gate": "left1", "from_gate": "right1", "from_room": game.current_room})
	await get_tree().process_frame
	check(game.current_room == "Garden_01" and blocked.size() == 1 and blocked[0] == PackedStringArray(["item:gate_pass"]), "a map gate needing item:gate_pass refuses the player (%s)" % [blocked])
	kit.add_item("gate_pass")
	game._on_gate_entered({"room": "Garden_02", "gate": "left1", "from_gate": "right1", "from_room": game.current_room})
	await game.room_loaded
	check(game.current_room == "Garden_02", "and lets it through with one")
	gate.erase("requires")
	game.enforce_requirements = false

func _equipment() -> void:
	var charm := MDSEquipmentData.new()
	charm.id = "wall_charm"
	charm.grants = PackedStringArray(["wall_jump"])
	charm.stat_mods = {"max_run_speed": 40}
	kit.register_item(charm)
	ProjectSettings.set_setting(MDSGameplaySetup.PREFIX + "equip_at_bench_only", false)
	check(not kit.equip("wall_charm"), "equipment not owned can't be worn")
	kit.add_item("wall_charm")
	check(kit.equip("wall_charm") and kit.is_equipped("wall_charm"), "owned, it is worn")
	check(game.is_condition_met("wall_jump") and not game.has_ability("wall_jump"), "it lends wall_jump without granting it")
	check(kit.equipment_mods().get("max_run_speed", 0.0) == 40.0, "its stat mods add up")
	kit.unequip("wall_charm")
	check(not game.is_condition_met("wall_jump"), "taken off, it lends nothing")
	ProjectSettings.set_setting(MDSGameplaySetup.PREFIX + "equip_at_bench_only", true)
	kit.add_item("wall_charm")
	check(not kit.equip("wall_charm"), "with equip_at_bench_only, not away from a bench")

func _without_kit() -> void:
	var plain := Fixture.make_game()
	add_child(plain)
	await plain.room_loaded
	check(not plain.is_condition_met("item:red_key") and not plain.is_condition_met("flag:x"), "without the kit, item and flag conditions are simply unmet")
	plain.queue_free()
	await get_tree().process_frame
