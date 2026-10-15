extends "res://tests/test_case.gd"
## Scenes and tilesets Godot's editor calls large on disk (a text file over 512 KiB, "likely
## because it has embedded binary data"):
## - the starter tileset doesn't embed its atlas: it links or packs it, the same pixels;
## - the solid colors' tile is packed too;
## - a tileset of an older version, its atlas and colors' tile embedded (850 KiB of text for a
##   256x192 atlas), is mended when a room opens with it: the same tiles, a small file;
## - a tileset packed like that, loaded outside the editor (where a packed image lets go of
##   its data) and saved again, keeps its images;
## - erased tiles leave the scene's file when MDS saves it (a layer outside the tree keeps
##   them as empty entries until it updates);
## - a room whose scene is big says what makes it big: its layers, biggest first, the hidden
##   ones marked; Clear background empties the Background and the scene is small again;
## - the Room view shows it in sight, with Clear hidden tiles when hidden layers make it big:
##   it clears them and saves, and Ctrl+Z brings them back.

const DIR := TMP + "/file_size"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_starter()
	_old_tileset()
	_erased()
	_size_note()
	await _room_view()

func _starter() -> void:
	var path := DIR + "/starter.tres"
	for f in [path, DIR + "/starter.png"]:
		_remove(f)
	var ts := MDSTilesetFactory.get_or_create(path)
	var src := ts.get_source(0) as TileSetAtlasSource
	check(src != null and src.texture != null and not src.texture is ImageTexture, "the starter atlas is not an image embedded in the tileset (%s)" % [src.texture.get_class() if src and src.texture else "none"])
	check(src != null and src.texture != null and _same(src.texture.get_image(), MDSTilesetFactory.build_image()), "it is the atlas all the same, pixel for pixel")
	check(FileAccess.file_exists(DIR + "/starter.png"), "its PNG is next to it, for repainting")
	check(_kib(path) < 64, "the starter tileset is small: %d KiB" % _kib(path))
	var root := Node2D.new()
	var layer := TileMapLayer.new()
	layer.name = "Terrain"
	layer.tile_set = ts
	root.add_child(layer)
	save_scene(root, DIR + "/colors.tscn")
	root.free()
	var painter := MDSRoomPainter.open(DIR + "/colors.tscn", ts)
	var t := painter.color_tile(Color(0.2, 0.4, 0.6))
	var colors := ts.get_source(t[0]) as TileSetAtlasSource
	check(colors.resource_name == MDSRoomPainter.COLOR_SOURCE_NAME and not colors.texture is ImageTexture, "the solid colors' tile is not an embedded image either (%s)" % colors.texture.get_class())
	var img := colors.texture.get_image()
	check(img != null and img.get_size() == ts.tile_size and img.get_pixel(5, 5).is_equal_approx(Color.WHITE), "it is a white tile, tinted per color")
	painter.save_tile_set()
	painter.free_instance()
	check(_kib(path) < 64, "with it the tileset stays small: %d KiB" % _kib(path))

## A tileset as 3.3 and older made it: the atlas and the colors' tile embedded as images.
func _old_tileset() -> void:
	var path := DIR + "/old.tres"
	for f in [path, DIR + "/old_sheet0.png", DIR + "/old_MDS colors.png"]:
		_remove(f)
	var ts := MDSTilesetFactory.build_tileset()
	var white := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var colors := TileSetAtlasSource.new()
	colors.resource_name = MDSRoomPainter.COLOR_SOURCE_NAME
	colors.texture = ImageTexture.create_from_image(white)
	colors.texture_region_size = ts.tile_size
	colors.create_tile(Vector2i.ZERO)
	var alt := colors.create_alternative_tile(Vector2i.ZERO)
	colors.get_tile_data(Vector2i.ZERO, alt).modulate = Color.BLACK
	var cid := ts.add_source(colors)
	ResourceSaver.save(ts, path)
	var before := _kib(path)
	check(before > 512, "such a tileset is over the 512 KiB Godot warns about: %d KiB" % before)
	var loaded := ResourceLoader.load(path, "TileSet", ResourceLoader.CACHE_MODE_REPLACE) as TileSet
	var moved := MDSRoomPainter.externalize_sheets(loaded)
	check(moved == 2, "opening a room takes both images out of it (%d)" % moved)
	var after := _kib(path)
	check(after < 64, "and it is small: %d KiB, from %d" % [after, before])
	var again := ResourceLoader.load(path, "TileSet", ResourceLoader.CACHE_MODE_IGNORE) as TileSet
	var atlas := again.get_source(0) as TileSetAtlasSource
	check(not atlas.texture is ImageTexture and _same(atlas.texture.get_image(), MDSTilesetFactory.build_image()), "the atlas is the same, pixel for pixel")
	check(atlas.get_tiles_count() == (ts.get_source(0) as TileSetAtlasSource).get_tiles_count() and atlas.get_tile_data(Vector2i(5, 0), 0).get_collision_polygons_count(0) == 1, "with all its tiles and their collision")
	var c := again.get_source(cid) as TileSetAtlasSource
	check(not c.texture is ImageTexture and c.texture.get_image().get_pixel(3, 3).is_equal_approx(Color.WHITE) and c.get_tile_data(Vector2i.ZERO, alt).modulate == Color.BLACK, "the colors' tile too, its colors kept")
	check(MDSRoomPainter.externalize_sheets(again) == 0, "a mended tileset is left alone")
	# Loaded here (not in the editor), the packed images let go of their data: saving packs them again.
	MDSRoomPainter._keep_packed(again)
	ResourceSaver.save(again, path)
	var third := ResourceLoader.load(path, "TileSet", ResourceLoader.CACHE_MODE_IGNORE) as TileSet
	var atlas3 := third.get_source(0) as TileSetAtlasSource
	check(_kib(path) < 64 and _same(atlas3.texture.get_image(), MDSTilesetFactory.build_image()) and (third.get_source(cid) as TileSetAtlasSource).texture.get_image() != null, "saved again outside the editor, it keeps its images (%d KiB)" % _kib(path))

func _erased() -> void:
	var ts := MDSTilesetFactory.get_or_create(DIR + "/starter.tres")
	var path := DIR + "/erased.tscn"
	var root := Node2D.new()
	var layer := TileMapLayer.new()
	layer.name = "Terrain"
	layer.tile_set = ts
	root.add_child(layer)
	for x in 100:
		layer.set_cell(Vector2i(x, 0), 0, Vector2i(0, 0))
	save_scene(root, path)
	root.free()
	var painter := MDSRoomPainter.open(path, ts)
	painter.checkpoint()
	for x in 60:
		painter.layers["Terrain"].erase_cell(Vector2i(x, 0))
	painter.dirty = true
	check(painter.save() == OK, "a room with tiles erased saves")
	painter.free_instance()
	check(_saved_cells(path, "Terrain") == 40, "only its 40 tiles left are in the file, not the 60 erased (%d)" % _saved_cells(path, "Terrain"))
	painter = MDSRoomPainter.open(path, ts)
	painter.checkpoint()
	painter.layers["Terrain"].tile_map_data = PackedByteArray()
	painter.dirty = true
	painter.save()
	painter.free_instance()
	check(_saved_cells(path, "Terrain") == 0, "nor any once the layer is cleared (%d)" % _saved_cells(path, "Terrain"))

func _size_note() -> void:
	var ts := MDSTilesetFactory.get_or_create(DIR + "/starter.tres")
	var path := DIR + "/big_room.tscn"
	var root := Node2D.new()
	root.name = "BigRoom"
	var back := TileMapLayer.new()
	back.name = "Background"
	back.tile_set = ts
	back.visible = false
	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = ts
	root.add_child(back)
	root.add_child(terrain)
	# A tall room filled from edge to edge, as Fill background does: 36,000 tiles.
	for y in 400:
		for x in 90:
			back.set_cell(Vector2i(x, y), 0, Vector2i(0, 2))
			if x < 2 or x > 87:
				terrain.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	save_scene(root, path)
	root.free()
	check(_kib(path) > 512, "the room's scene is big: %d KiB" % _kib(path))
	var painter := MDSRoomPainter.open(path, ts)
	var note := painter.size_note()
	check(note.begins_with("big_room.tscn is %d KiB" % ceili(FileAccess.get_file_as_bytes(path).size() / 1024.0)), "a big room says how big it is: %s" % note)
	check("Background 36000 tiles (563 KiB, hidden)" in note and "Terrain 1600 tiles" in note and note.find("Background") < note.find("Terrain"), "and what makes it big, biggest first, the hidden layer marked")
	check("Clear hidden tiles" in note, "a hidden layer's tiles are saved too: it says to clear them")
	painter.checkpoint()
	painter.clear_layer("Background")
	check(painter.save() == OK, "clearing the background saves")
	check(_kib(path) < 64 and painter.size_note().is_empty(), "the scene is small again (%d KiB) and has nothing to say" % _kib(path))
	painter.free_instance()

## Cells in [param layer]'s tile_map_data in the scene file at [param path].
func _saved_cells(path: String, layer: String) -> int:
	var text := FileAccess.get_file_as_string(path)
	var at := text.find("[node name=\"%s\"" % layer)
	var data := text.find("tile_map_data = PackedByteArray(\"", at)
	var next := text.find("\n[", at + 1)
	if at < 0 or data < 0 or (next >= 0 and next < data):
		return 0
	var start := data + "tile_map_data = PackedByteArray(\"".length()
	var raw := Marshalls.base64_to_raw(text.substr(start, text.find("\"", start) - start))
	return (raw.size() - 2) / 12

func _room_view() -> void:
	var ts := MDSTilesetFactory.get_or_create(DIR + "/starter.tres")
	var path := DIR + "/hidden_room.tscn"
	var root := Node2D.new()
	root.name = "HiddenRoom"
	var back := TileMapLayer.new()
	back.name = "Background"
	back.tile_set = ts
	back.visible = false
	root.add_child(back)
	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = ts
	root.add_child(terrain)
	for y in 400:
		for x in 90:
			back.set_cell(Vector2i(x, y), 0, Vector2i(0, 2))
	for x in 90:
		terrain.set_cell(Vector2i(x, 399), 0, Vector2i(0, 0))
	save_scene(root, path)
	root.free()
	load_fresh(path)
	var world := MDSWorld.new()
	world.path = DIR + "/hidden.mdsworld.json"
	world.add_room("Tall", Rect2(0, 0, 2880, 12800))
	world.set_room_scene("Tall", path)
	var view := MDSRoomView.new()
	view.size = Vector2(1200, 800)
	add_child(view)
	await get_tree().process_frame
	check(view.open_room(world, "Tall").is_empty(), "the Room view opens the tall room")
	check(view.size_box.visible and view.size_label.text.contains("Background 36000 tiles"), "it shows in sight that the scene is big, and why (%s)" % view.size_label.text)
	check(view.clear_hidden_button.visible and view.clear_hidden_button.text == "Clear 36000 hidden tiles (Background)", "with a button to clear the hidden tiles (%s)" % view.clear_hidden_button.text)
	check(view.clear_hidden_tiles() == 36000, "it clears them")
	check(_kib(path) < 64 and not view.size_box.visible, "and saves: the scene is small (%d KiB) and the warning gone" % _kib(path))
	check(view.painter.layers["Terrain"].get_used_cells().size() == 90, "the tiles that show stay")
	check(view.painter.undo() and view.painter.layers["Background"].get_used_cells().size() == 36000, "Ctrl+Z brings them back")
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame

func _same(a: Image, b: Image) -> bool:
	if not a or not b:
		return false
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	return a.get_size() == b.get_size() and a.get_data() == b.get_data()

func _kib(path: String) -> int:
	return ceili(FileAccess.get_file_as_bytes(path).size() / 1024.0)

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
