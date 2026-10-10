extends "res://tests/test_case.gd"
## Projects made before the IDP to MDS rename of the data (3.1) keep working (MDSLegacy): old
## metadata and groups are read and renamed when the Room view saves, old world files and MetSys
## map notes load, the old tile kind layer is used, and old project settings move.

const DIR := "res://tests/tmp/legacy"

func _run() -> void:
	_names()
	_nodes()
	_scene()
	_world()
	_notes()
	_tiles()
	_settings()

func _names() -> void:
	check(MDSLegacy.old_name(&"mds_blockout") == &"idp_blockout" and MDSLegacy.old_name(&"save_point") == &"save_point", "an mds_ name's old name; other names stay")
	var n := Node2D.new()
	n.set_meta(&"idp_stands", true)
	n.set_meta(&"idp_boss_name", "Warden")
	n.add_to_group(&"idp_protected")
	check(MDSLegacy.has_meta_key(n, &"mds_stands") and MDSLegacy.get_meta_key(n, &"mds_boss_name", "") == "Warden", "old metadata is read under the new name")
	check(MDSLegacy.in_group(n, &"mds_protected") and not MDSLegacy.in_group(n, &"mds_fixed"), "old groups too")
	n.set_meta(&"mds_boss_name", "Moss Mother")
	check(MDSLegacy.get_meta_key(n, &"mds_boss_name") == "Moss Mother", "the new name wins")
	MDSLegacy.remove_meta_key(n, &"mds_boss_name")
	check(not n.has_meta(&"mds_boss_name") and not n.has_meta(&"idp_boss_name"), "removing takes both")
	check(MDSRoomObjects.stands(n) and MDSRoomObjects.is_protected(n), "the room tools see them")
	var gate := Node2D.new()
	gate.add_to_group(&"idp_stands")
	check(MDSRoomObjects.stands(gate), "an old stand group counts")
	n.free()
	gate.free()

func _nodes() -> void:
	var root := Node2D.new()
	root.set_meta(&"idp_room_type", "boss")
	var stamp := Sprite2D.new()
	stamp.name = "Stamp"
	stamp.set_meta(&"idp_stamp", 4)
	stamp.set_meta(&"custom", 1)
	stamp.add_to_group(&"idp_scenery", true)
	root.add_child(stamp)
	stamp.owner = root
	var inner_root := Node2D.new()
	var inner := Node2D.new()
	inner.name = "Inner"
	inner.set_meta(&"idp_stands", true)
	inner_root.add_child(inner)
	inner.owner = inner_root
	inner_root.scene_file_path = "res://somewhere/prop.tscn"
	root.add_child(inner_root)
	inner_root.owner = root
	var count := MDSLegacy.upgrade_nodes(root)
	check(count == 3, "upgrade_nodes renamed the scene's own metadata and groups (%d)" % count)
	check(root.get_meta(&"mds_room_type") == "boss" and not root.has_meta(&"idp_room_type"), "on the root")
	check(stamp.get_meta(&"mds_stamp") == 4 and stamp.has_meta(&"custom") and not stamp.has_meta(&"idp_stamp"), "and its nodes, other metadata kept")
	check(stamp.is_in_group(&"mds_scenery") and not stamp.is_in_group(&"idp_scenery"), "groups too")
	check(inner.has_meta(&"idp_stands"), "nodes of an instanced scene keep theirs (their own scene has them)")
	check(MDSLegacy.upgrade_nodes(root) == 0, "nothing left the second time")
	root.free()

func _scene() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "/old_room.tscn"
	var root := Node2D.new()
	root.name = "OldRoom"
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	var s := Sprite2D.new()
	s.name = "Rock"
	s.texture = tex
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, 8, 8)
	s.set_meta(&"idp_stamp", 2)
	root.add_child(s)
	s.owner = root
	var bench := Node2D.new()
	bench.name = "Bench"
	bench.set_meta(&"idp_stands", true)
	root.add_child(bench)
	bench.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()
	var painter := MDSRoomPainter.open(path)
	check(painter != null and _any_stamp(painter), "the Room view opens a scene made before the rename: its stamps are stamps")
	check(painter.root.get_node("Bench").has_meta(&"mds_stands"), "its metadata has the new names")
	painter.dirty = true
	check(painter.save() == OK, "it saves")
	painter.free_instance()
	var text := FileAccess.get_file_as_string(path)
	check(text.contains("metadata/mds_stands") and text.contains("metadata/mds_stamp") and not text.contains("idp_"), "the saved scene has only the new names")

func _any_stamp(painter: MDSRoomPainter) -> bool:
	for g in MDSRoomPainter.ITEM_GROUPS:
		for n in painter.items(g):
			if MDSRoomPainter.is_stamp(n):
				return true
	return false

func _world() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "/old.idpworld.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": "idp_world", "version": 1, "name": "Old", "rooms": {"A": {"rects": [[0, 0, 1152, 648]], "origin": [0, 0], "layer": 0, "gates": {}}}, "areas": {}, "layers": ["Main"], "links": [], "pins": [], "start_room": "A", "settings": {}}))
	f.close()
	check(MDSWorld.is_world_file(path) and MDSWorld.is_world_file("res://new.mdsworld.json") and not MDSWorld.is_world_file("res://a.json"), "both world file names are world files")
	check(MDSWorld.base_name(path) == "old" and MDSWorld.base_name("res://x/pharloom.mdsworld.json") == "pharloom", "base_name of either")
	var w := MDSWorld.load_world(path)
	check(w.has_room("A") and w.get_world_name() == "Old", "a world of format idp_world loads")
	check(w.save() == OK, "and saves")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.get("format", "") == MDSWorld.FORMAT and MDSWorld.FORMAT == "mds_world", "as format mds_world, under its own file name")
	check(MDSWorld.EXTENSION == ".mdsworld.json", "new worlds are .mdsworld.json")

func _notes() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var map := DIR + "/MapData.txt"
	var old := DIR + "/MapData.idp.json"
	var new := DIR + "/MapData.mds.json"
	if FileAccess.file_exists(new):
		DirAccess.remove_absolute(new)
	var f := FileAccess.open(old, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "start_room": "uid://old", "rooms": {}, "doors": {}, "links": [], "pins": [], "settings": {}}))
	f.close()
	var ann := MDSAnnotations.load_for_map(map)
	check(ann.data.start_room == "uid://old", "MetSys notes in MapData.idp.json are read")
	check(ann.path == new, "and saved to MapData.mds.json")
	ann.save()
	check(FileAccess.file_exists(new) and MDSAnnotations.load_for_map(map).data.start_room == "uid://old", "from then on the new file is read")

func _tiles() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "idp_kind")
	ts.set_custom_data_layer_type(0, TYPE_STRING)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(Image.create(32, 16, false, Image.FORMAT_RGBA8))
	src.texture_region_size = Vector2i(16, 16)
	src.create_tile(Vector2i(0, 0))
	src.create_tile(Vector2i(1, 0))
	var sid := ts.add_source(src)
	src.get_tile_data(Vector2i(0, 0), 0).set_custom_data("idp_kind", "grass")
	check(MDSLegacy.is_kind_layer("idp_kind") and MDSLegacy.is_kind_layer(MDSTilesetFactory.KIND_LAYER) and MDSTilesetFactory.KIND_LAYER == "mds_kind", "the tile kind layer, old or new")
	var painter := MDSRoomPainter.new()
	painter.tile_set = ts
	check(painter.get_decor_tiles().has("grass") and painter.get_tile_kind(sid, Vector2i(0, 0)) == "grass", "a tileset tagged with idp_kind keeps its kinds")
	painter.tag_tiles(sid, [Vector2i(1, 0)], "fern")
	check(ts.get_custom_data_layers_count() == 1 and painter.get_tile_kind(sid, Vector2i(1, 0)) == "fern", "tagging uses its layer, without adding another")
	var fresh := MDSTilesetFactory.build_tileset()
	check(fresh.get_custom_data_layer_name(0) == "mds_kind", "the starter tileset uses the new name")
	check(MDSTilesetFactory.DEFAULT_PATH == "res://mds_tiles/mds_cave_tileset.tres", "in res://mds_tiles/")
	check(MDSLegacy.tileset_path("res://tests/tmp/legacy/none.tres") == "res://tests/tmp/legacy/none.tres" or ResourceLoader.exists(MDSLegacy.OLD_TILESET_PATH), "the old starter tileset is used only when it is there")

func _settings() -> void:
	var old := MDSLegacy.OLD_SETTINGS + "/legacy_test_value"
	var new := MDSLegacy.SETTINGS + "/legacy_test_value"
	ProjectSettings.set_setting(old, "res://old.idpworld.json")
	check(MDSLegacy.get_setting(new, "") == "res://old.idpworld.json", "a setting saved under interactive_dev_panel/ is read under its new name")
	var moved := MDSLegacy.upgrade_settings()
	check(moved >= 1 and ProjectSettings.get_setting(new, "") == "res://old.idpworld.json" and not ProjectSettings.has_setting(old), "upgrade_settings moves it (%d)" % moved)
	ProjectSettings.set_setting(old, "older")
	MDSLegacy.upgrade_settings()
	check(ProjectSettings.get_setting(new, "") == "res://old.idpworld.json" and not ProjectSettings.has_setting(old), "a setting already under the new name wins")
	ProjectSettings.set_setting(new, null)
	check(MDSLegacy.get_setting(new, "fallback") == "fallback", "neither: the default")
