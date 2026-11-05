extends "res://tests/mcp_test_case.gd"
## The MCP tools for a map painted in MetSys: its map file is never written, only the notes beside it.

const MAP := WORK + "/ms/MapData.txt"
const TEXT := "[0,0,0]\n1,0,0,0|||\n[1,0,0]\n0,0,1,0|||\n"
const FIRST := "unassigned:0,0,0"
const SECOND := "unassigned:1,0,0"

func _run() -> void:
	start_server()
	DirAccess.make_dir_recursive_absolute(MAP.get_base_dir())
	var f := FileAccess.open(MAP, FileAccess.WRITE)
	f.store_string(TEXT)
	f.close()

	var got: Dictionary = await ok("mds_metsys_get", {"map": MAP, "doors": true})
	check(got.rooms.size() == 2, "two rooms: %s" % got)
	check(got.doors.size() == 1, "a door between them: %s" % [got.doors])
	var door: String = got.doors[0].door
	await refused("mds_metsys_get", {"map": WORK + "/ms/none.txt"}, "not_found")

	await ok("mds_metsys_annotate", {"map": MAP, "room": FIRST, "values": {"name": "Hall", "type": "save", "grants": ["dash"], "status": "done"}, "door": door, "requires": ["dash"], "one_way_from": FIRST, "start_room": FIRST})
	var ann := MDSAnnotations.load_for_map(MAP)
	check(ann.get_room_value(FIRST, "name") == "Hall" and ann.get_room_value(FIRST, "type") == "save", "room notes are saved")
	check(ann.get_door_requires(door) == PackedStringArray(["dash"]), "a door needs it: %s" % [ann.get_door_requires(door)])
	check(ann.get_door_one_way_from(door) == FIRST, "one way")
	check(ann.get_start_room() == FIRST, "the start room")
	check(FileAccess.get_file_as_string(MAP) == TEXT, "and the map file stays as it was")
	check(FileAccess.file_exists(WORK + "/ms/MapData.mds.json"), "they go beside it")
	await refused("mds_metsys_annotate", {"map": MAP, "room": "nobody", "values": {"name": "X"}}, "room_not_found")
	await refused("mds_metsys_annotate", {"map": MAP, "room": FIRST, "values": {"nothing": 1}}, "bad_arguments")
	await refused("mds_metsys_annotate", {"map": MAP, "room": FIRST, "values": {"type": "nope"}}, "bad_arguments")
	await refused("mds_metsys_annotate", {"map": MAP, "room": FIRST, "values": {"status": "nope"}}, "bad_arguments")
	await refused("mds_metsys_annotate", {"map": MAP, "door": "0,0,0:D", "requires": []}, "door_not_found")
	await refused("mds_metsys_annotate", {"map": MAP, "start_room": "nobody"}, "room_not_found")
	await ok("mds_undo", {})
	check(MDSAnnotations.load_for_map(MAP).get_start_room() == "", "undo takes the notes back")
	await ok("mds_metsys_annotate", {"map": MAP, "room": FIRST, "values": {"grants": ["dash"]}, "start_room": FIRST})

	var issues: Dictionary = await ok("mds_metsys_check", {"map": MAP, "kind": "issues"})
	check(issues.has("issues"), "issues: %s" % issues)
	var progress: Dictionary = await ok("mds_metsys_check", {"map": MAP, "kind": "progression"})
	check(not progress.is_empty(), "progression: %s" % [progress.keys()])
	var back: Dictionary = await ok("mds_metsys_check", {"map": MAP, "kind": "backtracking"})
	check(back.has("dead_ends"), "backtracking: %s" % [back.keys()])
	var way: Dictionary = await ok("mds_metsys_check", {"map": MAP, "kind": "path", "from": FIRST, "to": SECOND})
	check(way.has("path"), "a path: %s" % way)
	await refused("mds_metsys_check", {"map": MAP, "kind": "path"}, "bad_arguments")
	var uses: Dictionary = await ok("mds_metsys_check", {"map": MAP, "kind": "ability_uses", "ability": "dash"})
	check(uses.has("uses"), "ability uses: %s" % uses)
	await ok("mds_metsys_check", {"map": MAP, "kind": "objectives"})
	await ok("mds_metsys_annotate", {"map": MAP, "settings": {"player": {"jump_height": 200}, "geometry_checks": false}})
	check(MDSAnnotations.load_for_map(MAP).get_setting("player", {}).get("jump_height") == 200, "the player for the checks")
	var physics: Dictionary = await ok("mds_metsys_check", {"map": MAP, "kind": "geometry"})
	check(physics.no_scene.size() == 2, "the room checks say what has no scene: %s" % physics)

	var data: Dictionary = await ok("mds_metsys_export", {"map": MAP, "format": "json"})
	check(JSON.parse_string(data.text) is Dictionary, "json")
	var dot: Dictionary = await ok("mds_metsys_export", {"map": MAP, "format": "dot"})
	check(dot.text.contains("graph"), "a graph: %s" % dot.text.left(40))
	var written: Dictionary = await ok("mds_metsys_export", {"map": MAP, "format": "markdown", "path": WORK + "/ms/notes.md"})
	check(FileAccess.file_exists(written.written), "a document: %s" % written)
	await refused("mds_metsys_export", {"map": MAP, "format": "dot", "path": "res://addons/x.dot"}, "path_not_allowed")
	await _with_scenes()
	end_server()

## The room checks play the room, so they need a map whose rooms have scenes.
func _with_scenes() -> void:
	await make_world()
	await ok("mds_room_scene_create", {"world": WORLD, "room": "R1"})
	await ok("mds_room_generate", {"world": WORLD, "room": "R1", "seed": 1})
	var scene := MDSWorld.load_world(WORLD).get_scene_path("R1")
	var map := WORK + "/ms/WithScene.txt"
	var f := FileAccess.open(map, FileAccess.WRITE)
	f.store_string("[0,0,0]\n1,0,0,0|||%s\n[3,0,0]\n0,0,1,0|||\n" % scene)
	f.close()
	var physics: Dictionary = await ok("mds_metsys_check", {"map": map, "kind": "geometry"})
	check(physics.rooms.has(scene), "the room with a scene is checked: %s" % physics)
	check(physics.no_scene.size() == 1, "and the other is named: %s" % [physics.no_scene])
	var only: Dictionary = await ok("mds_metsys_check", {"map": map, "kind": "geometry", "rooms": [scene]})
	check(only.rooms.has(scene) and only.no_scene.is_empty(), "rooms picks which: %s" % only)
