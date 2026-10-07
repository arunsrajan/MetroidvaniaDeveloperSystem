extends "res://tests/test_case.gd"
## Brief 3: saving room scenes without silent data loss.

const WEATHER := TMP + "/brief3_weather.tscn"
const ROOM := TMP + "/brief3_room.tscn"
const BROKEN_SCRIPT := TMP + "/brief3_broken.gd"
const BROKEN_ROOM := TMP + "/brief3_broken_room.tscn"

func _run() -> void:
	var with_editable := _build_rooms()
	_overrides_survive(with_editable)
	_gate_writes_keep_overrides()
	_broken_script_refused()

## Writes the weather scene and a room that sets properties inside it, then takes the
## [editable] marker out, like rooms written by hand or by other tools. Returns the text
## Godot wrote (with the marker).
func _build_rooms() -> String:
	var weather := Node2D.new()
	weather.name = "Weather"
	var thunder := AudioStreamPlayer.new()
	thunder.name = "Thunder"
	weather.add_child(thunder)
	var rain := CPUParticles2D.new()
	rain.name = "Rain"
	weather.add_child(rain)
	check(save_scene(weather, WEATHER) == OK, "the weather scene saves")
	weather.free()
	var room := Node2D.new()
	room.name = "Room"
	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	terrain.tile_set = ts
	room.add_child(terrain)
	var obj := (load_fresh(WEATHER) as PackedScene).instantiate()
	obj.name = "Obj_Weather"
	room.add_child(obj)
	obj.owner = room
	room.set_editable_instance(obj, true)
	(obj.get_node("Thunder") as AudioStreamPlayer).volume_db = -12.0
	(obj.get_node("Rain") as CPUParticles2D).amount = 40
	var group := Node2D.new()
	group.name = "Freeform"
	group.z_index = 1
	room.add_child(group)
	var f := MDSFreeform.new()
	f.name = "Rock"
	f.points = rect_points(Rect2(0, 500, 600, 148))
	f.seed_value = 7
	group.add_child(f)
	check(save_scene(room, ROOM) == OK, "the room saves")
	room.free()
	# Saved from a running game, a scene gets no UID: give it one, as the editor would.
	ResourceSaver.set_uid(ROOM, ResourceUID.create_id())
	var text := FileAccess.get_file_as_string(ROOM)
	check(text.contains("[editable path=\"Obj_Weather\"]") and text.contains("volume_db = -12.0") and text.contains("amount = 40"), "sanity: Godot wrote the overrides with an [editable] marker")
	var stripped := text.replace("\n\n[editable path=\"Obj_Weather\"]", "")
	check(stripped != text, "sanity: the marker was taken out")
	_write(ROOM, stripped)
	var loaded := (load_fresh(ROOM) as PackedScene).instantiate()
	check(is_equal_approx((loaded.get_node("Obj_Weather/Thunder") as AudioStreamPlayer).volume_db, -12.0), "sanity: without the marker, the room still applies its overrides")
	# What used to happen: packing it again drops them.
	var plain := PackedScene.new()
	plain.pack(loaded)
	loaded.free()
	ResourceSaver.save(plain, TMP + "/brief3_plain.tscn")
	check(not FileAccess.get_file_as_string(TMP + "/brief3_plain.tscn").contains("volume_db = -12.0"), "sanity: a plain pack loses the override (the bug this guards against)")
	load_fresh(ROOM)
	return text

func _overrides_survive(with_editable: String) -> void:
	var uid := MDSWorldSceneTools.file_uid(ROOM)
	var ts := TileSet.new()
	var painter := MDSRoomPainter.open(ROOM, ts)
	check(painter.save() == OK, "the Room view saves the room (%s)" % MDSWorldSceneTools.last_error)
	painter.free_instance()
	var after := FileAccess.get_file_as_string(ROOM)
	check(after == with_editable, "an unchanged room saves byte for byte, plus the [editable] marker")
	if after != with_editable:
		_print_diff(with_editable, after)
	check(MDSWorldSceneTools.file_uid(ROOM) == uid and uid != ResourceUID.INVALID_ID, "the UID is unchanged")
	# An edit saves the edit and nothing else.
	load_fresh(ROOM)
	painter = MDSRoomPainter.open(ROOM, ts)
	var rock: MDSFreeform = painter.items("Freeform")[0]
	var pts := rock.points.duplicate()
	pts[0] = Vector2(-10, 500)
	rock.points = pts
	check(painter.save() == OK, "the edited room saves")
	painter.free_instance()
	var edited := FileAccess.get_file_as_string(ROOM)
	check(edited.contains("volume_db = -12.0") and edited.contains("amount = 40"), "the overrides survive an edit")
	check(_changed_lines(with_editable, edited) == 1, "only the shape's points line changed (%d lines)" % _changed_lines(with_editable, edited))
	check(MDSWorldSceneTools.file_uid(ROOM) == uid, "the UID is still unchanged")

func _gate_writes_keep_overrides() -> void:
	load_fresh(ROOM)
	var world := MDSWorld.new()
	var id := world.add_room("Brief3", Rect2(0, 0, 1152, 648), 0, "", ROOM)
	world.add_gate(id, Vector2(0, 300), "left", "", false)
	var added := MDSWorldSceneTools.ensure_gate_nodes(world, id)
	check(added == PackedStringArray(["left1"]), "a gate node is added (%s, %s)" % [added, MDSWorldSceneTools.last_error])
	var text := FileAccess.get_file_as_string(ROOM)
	check(text.contains("volume_db = -12.0") and text.contains("amount = 40") and text.contains("left1"), "adding gate nodes keeps the overrides")
	load_fresh(ROOM)
	check(MDSWorldSceneTools.write_gates(world, id) == 1, "Write to scene works")
	text = FileAccess.get_file_as_string(ROOM)
	check(text.contains("volume_db = -12.0"), "Write to scene keeps the overrides")

func _broken_script_refused() -> void:
	_write(BROKEN_SCRIPT, "extends Node2D\n\nfunc _ready() -> void:\n\tthis_function_does_not_exist()\n")
	_write(BROKEN_ROOM, "[gd_scene format=3]\n\n[ext_resource type=\"Script\" path=\"%s\" id=\"1_broken\"]\n\n[node name=\"Room\" type=\"Node2D\"]\n\n[node name=\"RoomInstance\" type=\"Node2D\" parent=\".\"]\nscript = ExtResource(\"1_broken\")\n" % BROKEN_SCRIPT)
	var before := FileAccess.get_file_as_string(BROKEN_ROOM)
	print("  (the script errors below are expected)")
	var painter := MDSRoomPainter.open(BROKEN_ROOM, TileSet.new())
	check(painter != null, "the room opens")
	if not painter:
		return
	var lost := painter.root.get_node("RoomInstance").get_script() == null
	check(lost, "sanity: the node loaded without its script")
	painter.dirty = true
	var err := painter.save()
	check(err != OK, "a room whose script cannot compile is not saved")
	check(MDSWorldSceneTools.last_error.contains("RoomInstance"), "the error names the node (%s)" % MDSWorldSceneTools.last_error)
	check(FileAccess.get_file_as_string(BROKEN_ROOM) == before, "the file is untouched")
	painter.free_instance()
	# Left behind, the broken script would log a parse error at every import.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BROKEN_SCRIPT))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BROKEN_ROOM))

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _changed_lines(a: String, b: String) -> int:
	var la := a.split("\n")
	var lb := b.split("\n")
	var n := absi(la.size() - lb.size())
	for i in mini(la.size(), lb.size()):
		if la[i] != lb[i]:
			n += 1
	return n

func _print_diff(a: String, b: String) -> void:
	var la := a.split("\n")
	var lb := b.split("\n")
	for i in maxi(la.size(), lb.size()):
		var x := la[i] if i < la.size() else "<none>"
		var y := lb[i] if i < lb.size() else "<none>"
		if x != y:
			print("    line %d:\n      want %s\n      got  %s" % [i + 1, x.left(160), y.left(160)])
