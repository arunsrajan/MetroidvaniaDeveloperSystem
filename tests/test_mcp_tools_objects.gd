extends "res://tests/mcp_test_case.gd"
## The generic MCP tools: any class, resource or node of the plugin, by its exports.

func _run() -> void:
	start_server()
	await _classes()
	_every_class_round_trips()
	await _resources()
	await _scenes()
	await _nodes_in_rooms()
	await _guards()
	end_server()

func _classes() -> void:
	var all: Dictionary = await ok("mds_class_list", {})
	var names: Array = all.classes.map(func(c: Dictionary) -> String: return c["class"])
	for wanted in ["MDSItemData", "MDSAbilityData", "MDSEnemyData", "MDSCheckpoint", "MDSMoveBoss", "MDSFreeformStyle"]:
		check(wanted in names, "%s can be made" % wanted)
	check(not "MDSMcpProtocol" in names and not "MDSMcpValues" in names, "the plugin's tools aren't things a game holds")
	check(not "MDSDock" in names and not "MDSRoomCanvas" in names, "nor is its panel")
	var resources: Dictionary = await ok("mds_class_list", {"kind": "resource", "contains": "ability"})
	check(not resources.classes.is_empty() and resources.classes.all(func(c: Dictionary) -> bool: return c.kind == "resource"), "kind and contains narrow it down")
	var moves: Dictionary = await ok("mds_class_list", {"base": "MDSMove"})
	check(moves.classes.size() > 5, "base finds what extends it: %s" % [moves.classes.size()])
	var info: Dictionary = await ok("mds_class_info", {"class": "MDSCheckpoint"})
	check(info.kind == "node" and not info.properties.is_empty(), "a class says what it has")
	var native: Dictionary = await ok("mds_class_info", {"class": "MDSCheckpoint", "native": true})
	check(native.properties.size() > info.properties.size(), "native adds Godot's own")
	await refused("mds_class_info", {"class": "OS"}, "bad_class")

## Every class can be made and described, and what it holds by default reads back in.
func _every_class_round_trips() -> void:
	var all := MDSMcpValues.classes()
	check(all.size() > 60, "the plugin has many classes: %d" % all.size())
	var project := {"MyFoe": {"base": "MyBase"}, "MyBase": {"base": "MDSBoss"}, "MDSBoss": {"base": "CharacterBody2D"}, "Other": {"base": "Node2D"}}
	check(MDSMcpValues._extends_mds("MyFoe", project), "a project's own class counts, however far down")
	check(not MDSMcpValues._extends_mds("Other", project), "and one that doesn't extend the plugin's doesn't")
	var total := 0
	for class_id: String in all:
		var made := MDSMcpValues.make(class_id)
		if not check(made != null, "%s can be made" % class_id):
			continue
		var values := MDSMcpValues.new()
		if made is Node:
			values.scene_root = made
		for p in MDSMcpValues.properties(made, false):
			total += 1
			var now: Variant = made.get(p["name"])
			values.error = ""
			var was: Variant = values.encode(now)
			check(not JSON.stringify(was).is_empty(), "%s.%s encodes" % [class_id, p["name"]])
			var back: Variant = values.decode(was, p, now)
			check(values.error.is_empty(), "%s.%s reads back: %s" % [class_id, p["name"], values.error])
			if values.error.is_empty() and not now is Object and not now is Array and not now is Dictionary:
				check(typeof(back) == typeof(now) and (back == now or _close(back, now)), "%s.%s is the same: %s and %s" % [class_id, p["name"], now, back])
		if made is Node:
			(made as Node).free()
		check(not MDSMcpValues.describe(class_id).is_empty(), "%s describes itself" % class_id)
	check(total > 1000, "and they have properties: %d" % total)

static func _close(a: Variant, b: Variant) -> bool:
	if a is float:
		return is_equal_approx(a, b)
	if a is Vector2:
		return (a as Vector2).is_equal_approx(b)
	if a is Color:
		# Colors go through #rrggbbaa: within one step of 255.
		var c: Color = a
		var d: Color = b
		return absf(c.r - d.r) < 0.005 and absf(c.g - d.g) < 0.005 and absf(c.b - d.b) < 0.005 and absf(c.a - d.a) < 0.005
	return false

func _resources() -> void:
	var path := WORK + "/data_files/key.tres"
	await refused("mds_resource_create", {"path": path, "class": "OS"}, "bad_class")
	var made: Dictionary = await ok("mds_resource_create", {"path": path, "class": "MDSItemData", "set": {"id": "key", "display_name": "Old key"}})
	check(made.path == path and FileAccess.file_exists(path), "the file is there")
	await refused("mds_resource_create", {"path": path, "class": "MDSItemData"}, "already_exists")
	var seen: Dictionary = await ok("mds_resource_get", {"path": path})
	check(seen["class"] == "MDSItemData" and seen.values.id == "key" and seen.values.display_name == "Old key", "only what was set shows: %s" % seen)
	await ok("mds_resource_update", {"path": path, "set": {"display_name": "New key"}})
	check((load(path) as MDSItemData).display_name == "New key", "the file changed, and what loads is it")
	var wrong: Dictionary = await call_mcp("mds_resource_update", {"path": path, "set": {"display_name": "Other", "no_such_thing": 1}})
	check(wrong.has("_error") and wrong._error.code == "bad_value", "a wrong name is refused: %s" % wrong)
	check(str(wrong.get("_error", {}).get("message", "")).contains("display_name"), "and says what there is: %s" % wrong)
	check((ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as MDSItemData).display_name == "New key", "and nothing was set")
	var copy: Dictionary = await ok("mds_resource_copy", {"from": path, "path": WORK + "/data_files/key2.tres"})
	check(FileAccess.file_exists(copy.path), "a copy")
	var found: Dictionary = await ok("mds_resource_find", {"class": "MDSItemData", "folder": WORK})
	check(found.resources.size() == 2, "both are found: %s" % found)
	await ok("mds_undo", {})
	check(not FileAccess.file_exists(copy.path), "undo takes back a new resource")
	await ok("mds_undo", {})
	check((ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as MDSItemData).display_name == "Old key", "and a change to one")

	# A resource inside a resource, in a typed array.
	var seq := WORK + "/data_files/seq.tres"
	await ok("mds_resource_create", {"path": seq, "class": "MDSMoveSequence", "set": {"moves": [{"class": "MDSMoveWait", "set": {"seconds": 0.5}}, {"class": "MDSMoveWait"}]}})
	var read: MDSMoveSequence = ResourceLoader.load(seq, "", ResourceLoader.CACHE_MODE_REPLACE)
	check(read.moves.size() == 2 and read.moves[0] is MDSMoveWait and is_equal_approx((read.moves[0] as MDSMoveWait).seconds, 0.5), "resources nest, in a typed array: %s" % [read.moves])
	var nested: Dictionary = await ok("mds_resource_get", {"path": seq})
	check(nested.values.moves[0]["class"] == "MDSMoveWait", "and read back: %s" % nested)
	await refused("mds_resource_create", {"path": WORK + "/data_files/bad.tres", "class": "MDSMoveSequence", "set": {"moves": [{"class": "MDSItemData"}]}}, "bad_value")

func _scenes() -> void:
	var path := WORK + "/s/thing.tscn"
	await refused("mds_scene_create", {"path": path}, "bad_arguments")
	await ok("mds_scene_create", {"path": path, "class": "Node2D", "name": "Thing"})
	await refused("mds_scene_create", {"path": path, "class": "Node2D"}, "already_exists")
	await refused("mds_node_add", {"scene": path, "class": "OS"}, "bad_class")
	var add: Dictionary = await ok("mds_node_add", {"scene": path, "class": "MDSCheckpoint", "name": "Save", "pos": {"x": 100, "y": 200}, "groups": ["mine"], "meta": {"mds_grants": ["dash"]}})
	check(add.node == "Save", "added: %s" % add)
	await ok("mds_node_add", {"scene": path, "class": "Marker2D", "name": "Holder", "pos": {"x": 5, "y": 5}})
	var got: Dictionary = await ok("mds_node_get", {"scene": path, "node": "Save"})
	check(got["class"] == "MDSCheckpoint" and got.pos == [100, 200] and "mine" in got.groups, "it comes back: %s" % got)
	check(got.meta.get("mds_grants") == ["dash"], "with its metadata: %s" % got)
	await ok("mds_node_update", {"scene": path, "node": "Save", "parent": "Holder", "pos": {"x": 1, "y": 2}, "name": "Saved", "groups_add": ["other"], "groups_remove": ["mine"], "meta": {"mds_grants": null}})
	var tree: Dictionary = await ok("mds_scene_tree", {"scene": path})
	var nodes: Array = tree.nodes.map(func(n: Dictionary) -> String: return n.node)
	check("Holder/Saved" in nodes and nodes.size() == 3, "it moved under its new parent: %s" % [nodes])
	var moved: Dictionary = await ok("mds_node_get", {"scene": path, "node": "Holder/Saved"})
	check(moved.pos == [1, 2] and "other" in moved.groups and not "mine" in moved.groups and not moved.has("meta"), "and everything else changed: %s" % moved)
	await refused("mds_node_update", {"scene": path, "node": "Holder", "parent": "Holder/Saved"}, "bad_arguments")
	await refused("mds_node_update", {"scene": path, "node": "Holder/Saved", "set": {"no_such_thing": 1}}, "bad_value")
	await refused("mds_node_update", {"scene": path, "node": "Nobody"}, "node_not_found")
	await ok("mds_node_remove", {"scene": path, "node": "Holder", "confirm": true})
	var empty: Dictionary = await ok("mds_scene_tree", {"scene": path})
	check(empty.nodes.size() == 1, "what was under it went too: %s" % empty)

	# An instance, and a scene made from another.
	var other := WORK + "/s/other.tscn"
	await ok("mds_scene_create", {"path": other, "inherits": path})
	await ok("mds_node_add", {"scene": other, "instance": path, "name": "Inner"})
	var both: Dictionary = await ok("mds_scene_tree", {"scene": other})
	check(both.nodes.any(func(n: Dictionary) -> bool: return n.get("instance", "") == path), "an instance is one: %s" % both)
	await refused("mds_node_add", {"scene": path, "instance": path}, "bad_arguments")
	var saved := FileAccess.get_file_as_string(other)
	check(saved.contains("instance=ExtResource"), "the new scene inherits rather than copies:\n%s" % saved)

	await ok("mds_node_add", {"scene": path, "class": "Camera2D", "name": "Cam"})
	var camera: Dictionary = await ok("mds_node_get", {"scene": path, "node": "Cam"})
	check(camera["class"] == "Camera2D", "Godot's own classes too")

func _nodes_in_rooms() -> void:
	await make_world()
	await ok("mds_room_scene_create", {"world": WORLD, "room": "R1"})
	var add: Dictionary = await ok("mds_node_add", {"world": WORLD, "room": "R1", "class": "MDSCheckpoint", "name": "Save2", "set": {}})
	check(add.node == "Save2", "a room's scene takes any node")
	var tree: Dictionary = await ok("mds_scene_tree", {"world": WORLD, "room": "R1", "depth": 1})
	check(tree.nodes.any(func(n: Dictionary) -> bool: return n.node == "Save2"), "and lists it: %s" % tree)
	await ok("mds_undo", {})
	var back: Dictionary = await ok("mds_scene_tree", {"world": WORLD, "room": "R1", "depth": 1})
	check(not back.nodes.any(func(n: Dictionary) -> bool: return n.node == "Save2"), "undo takes it back")

func _guards() -> void:
	await refused("mds_resource_create", {"path": "user://x.tres", "class": "MDSItemData"}, "bad_arguments")
	var addon: Dictionary = await call_mcp("mds_resource_create", {"path": "res://addons/x.tres", "class": "MDSItemData"})
	check(addon.has("_error"), "nothing is written in addons: %s" % addon)
	var hidden: Dictionary = await call_mcp("mds_scene_create", {"path": "res://.godot/x.tscn", "class": "Node2D"})
	check(hidden.has("_error"), "nor in .godot: %s" % hidden)
	await refused("mds_resource_get", {"path": "C:/Windows/win.tres"}, "not_found")
	var script_path := WORK + "/data_files/script.tres"
	await refused("mds_resource_create", {"path": script_path, "class": "MDSItemData", "set": {"script": "res://tests/mcp_child.gd"}}, "bad_value")
	await refused("mds_resource_create", {"path": script_path, "class": "MDSItemData", "set": {"resource_path": "res://other.tres"}}, "bad_value")
	await ok("mds_scene_create", {"path": WORK + "/s/guard.tscn", "class": "Node2D"})
	await refused("mds_node_update", {"scene": WORK + "/s/guard.tscn", "node": ".", "set": {"script": "res://tests/mcp_child.gd"}}, "bad_value")
	await refused("mds_node_add", {"scene": WORK + "/s/guard.tscn", "class": "MDSCheckpoint", "meta": {"bad name!": 1}}, "bad_value")
	var scripted: Dictionary = await call_mcp("mds_resource_create", {"path": script_path, "class": "MDSMoveSequence", "set": {"moves": [{"class": "GDScript"}]}})
	check(scripted.has("_error"), "a script can't be made as a value: %s" % scripted)
	var as_value: Dictionary = await call_mcp("mds_resource_create", {"path": script_path, "class": "MDSMoveSequence", "set": {"moves": ["res://tests/mcp_child.gd"]}})
	check(as_value.has("_error"), "nor passed as one: %s" % as_value)
	check(not FileAccess.file_exists(script_path), "and no file came of it")
