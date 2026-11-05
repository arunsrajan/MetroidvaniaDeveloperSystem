extends "res://tests/mcp_test_case.gd"
## The MCP fight tools: the same document the Fight editor edits.

func _run() -> void:
	start_server()
	await _in_a_scene()
	await _in_a_file()
	await _in_a_boss()
	end_server()

func _in_a_scene() -> void:
	var path := WORK + "/e/enemy.tscn"
	await ok("mds_scene_create", {"path": path, "class": "MDSMoveEnemy"})
	var empty: Dictionary = await ok("mds_fight_get", {"scene": path})
	check(empty.target == "MDSMoveEnemy", "a fighter: %s" % empty)
	await refused("mds_fight_get", {"scene": path, "node": "Nobody"}, "not_a_fighter")
	await refused("mds_fight_edit", {"scene": path, "op": "from_recipe", "recipe": MDSMoveRecipes.RECIPES[0]}, "fight_not_changed")
	check(empty.moves[0].path == "", "the root's path is empty: %s" % empty.moves[0])
	var slots: Dictionary = empty.moves[0].slots
	check(not slots.is_empty(), "and it says what it holds: %s" % empty.moves[0])
	var slot: String = slots.keys()[0]
	var from: Dictionary = await ok("mds_fight_edit", {"scene": path, "op": "add", "parent": "", "slot": slot, "move": {"class": "MDSMoveWait", "set": {"seconds": 2.0}}})
	check(from.moves == 2, "a move goes in: %s" % from)
	var fight: Dictionary = await ok("mds_fight_get", {"scene": path})
	check(fight.moves.size() == 2 and fight.moves[1]["class"] == "MDSMoveWait", "and stays: %s" % fight)
	check(fight.moves[1].values.get("seconds") == 2, "with its values: %s" % fight.moves[1])
	check(fight.has("checks"), "the editor's checks come with it")

func _in_a_file() -> void:
	var path := WORK + "/f/move.tres"
	await ok("mds_resource_create", {"path": path, "class": "MDSMoveSequence", "set": {"moves": [{"class": "MDSMoveWait", "set": {"seconds": 1.0}}]}})
	var one: Dictionary = await ok("mds_fight_get", {"file": path})
	check(one.moves.size() == 2, "a sequence and its move: %s" % one)
	var added: Dictionary = await ok("mds_fight_edit", {"file": path, "op": "add", "parent": "", "slot": "moves", "index": 0, "move": {"class": "MDSMoveWait", "set": {"seconds": 2.0}}})
	check(added.moves == 3, "one more: %s" % added)
	var read: MDSMoveSequence = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	check(read.moves.size() == 2 and is_equal_approx((read.moves[0] as MDSMoveWait).seconds, 2.0), "the file has it, first")
	await refused("mds_fight_edit", {"file": path, "op": "add", "parent": "", "slot": "nothing", "move": {"class": "MDSMoveWait"}}, "fight_not_changed")
	await refused("mds_fight_edit", {"file": path, "op": "add", "parent": "", "slot": "moves", "move": {"class": "MDSItemData"}}, "fight_not_changed")
	var got: Dictionary = await ok("mds_fight_get", {"file": path})
	var second: String = got.moves[2].path
	await ok("mds_fight_edit", {"file": path, "op": "set", "path": second, "set": {"seconds": 3.0}})
	read = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	check(is_equal_approx((read.moves[1] as MDSMoveWait).seconds, 3.0), "set changes a move")
	await ok("mds_fight_edit", {"file": path, "op": "reorder", "parent": "", "slot": "moves", "order": [1, 0]})
	read = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	check(is_equal_approx((read.moves[0] as MDSMoveWait).seconds, 3.0), "reorder changes the order")
	await refused("mds_fight_edit", {"file": path, "op": "reorder", "parent": "", "slot": "moves", "order": [0, 0]}, "fight_not_changed")
	await ok("mds_fight_edit", {"file": path, "op": "copy", "path": second})
	read = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	check(read.moves.size() == 3, "copy adds one: %d" % read.moves.size())
	await ok("mds_fight_edit", {"file": path, "op": "add_condition", "path": second, "list": "when", "condition_kind": "PLAYER_NEAR"})
	read = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	check(read.moves.any(func(m: MDSMove) -> bool: return not m.when.is_empty()), "a condition went on")
	await ok("mds_fight_edit", {"file": path, "op": "remove_condition", "path": second, "list": "when", "index": 0})
	await ok("mds_fight_edit", {"file": path, "op": "remove", "path": second})
	read = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	check(read.moves.size() == 2, "remove takes one away: %d" % read.moves.size())
	await refused("mds_fight_edit", {"file": path, "op": "remove", "path": "nobody"}, "fight_not_changed")
	await ok("mds_undo", {})
	read = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	check(read.moves.size() == 3, "undo brings it back")

func _in_a_boss() -> void:
	var path := WORK + "/e/boss.tscn"
	await ok("mds_scene_create", {"path": path, "class": "MDSMoveBoss"})
	var one: Dictionary = await ok("mds_fight_get", {"scene": path})
	check(one.target == "MDSMoveBoss", "a boss: %s" % one)
	await ok("mds_fight_edit", {"scene": path, "op": "from_recipe", "recipe": MDSMoveRecipes.RECIPES[0]})
	var two: Dictionary = await ok("mds_fight_get", {"scene": path})
	check(two.get("phases", []).size() >= 1 and not two.read_only, "a recipe gives phases, to change: %s" % [two.get("phases")])
	await ok("mds_fight_edit", {"scene": path, "op": "add_phase"})
	var last: int = two.phases.size()
	var added: Dictionary = await ok("mds_fight_get", {"scene": path, "phase": last})
	check(added.phases.size() == last + 1 and added.phase == last, "another phase: %s" % [added.phases])
	check(two.moves.size() > 1, "a phase holds a fight: %d" % two.moves.size())
	await ok("mds_fight_edit", {"scene": path, "op": "remove_phase", "index": last})
	var left: Dictionary = await ok("mds_fight_get", {"scene": path})
	check(left.phases.size() == last, "one goes: %s" % [left.phases])
	var no_editor: Dictionary = await call_mcp("mds_fight_live", {})
	check(no_editor.has("_error"), "seeing a running game needs the editor: %s" % no_editor)
