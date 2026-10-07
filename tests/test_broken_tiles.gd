extends "res://tests/test_case.gd"
## Tiles that no longer fit their sheet: a sheet painted with 32 px tiles whose tile size is then
## made 64 px, so only 3x3 of its 6x6 tiles fit. Loading that tileset logs "The
## TileSetAtlasSource atlas has no tile at ..." for every tile past the edge, and the cells
## painted with them draw nothing. Reading those cells must stay quiet, the scan and the Issues
## tab report them, and Remove broken tiles erases them and rewrites the tileset so it loads
## cleanly. A second room still painted with the removed tiles must read quietly too. Adding a
## sheet again with another tile size must not overwrite the scaled sheet an earlier source uses.

const TILES := TMP + "/broken_tiles.tres"
const ROOM := TMP + "/broken_room.tscn"
const OTHER_ROOM := TMP + "/broken_room_2.tscn"
const SHEET := TMP + "/broken_fx.png"

## Collects the engine errors logged while it is added (OS.add_logger).
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []
	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s: %s %s" % [function, code, rationale])

	func no_tile() -> Array:
		return Array(errors).filter(func(e: String) -> bool: return e.contains("no tile at"))

var host: SubViewport
## Held so the tileset and the rooms stay loaded: loading the grown tileset again would log its
## load errors in the middle of the checks.
var _keep: Array = []

func _run() -> void:
	host = SubViewport.new()
	host.disable_3d = true
	host.size = Vector2i(4, 4)
	add_child(host)
	_make_grown_tileset()
	await _reads_are_quiet(ROOM, "tiles past the sheet's edge")
	_reported()
	await _room_view()
	_loads_cleanly()
	_paint_room(OTHER_ROOM, load(TILES) as TileSet)
	_keep.append(load(OTHER_ROOM))
	await _reads_are_quiet(OTHER_ROOM, "tiles taken out of the tileset")
	_removed_in_painter()
	_scaled_sheet_names()

func _paint_room(path: String, ts: TileSet) -> void:
	var root := Node2D.new()
	root.name = "BrokenRoom"
	var layer := TileMapLayer.new()
	layer.name = "Terrain"
	layer.tile_set = ts
	for y in 6:
		for x in 6:
			layer.set_cell(Vector2i(x, y), 0, Vector2i(x, y))
	root.add_child(layer)
	check(save_scene(root, path) == OK, "saved %s, every tile painted" % path.get_file())
	root.free()

## A 6x6 sheet of solid 32 px tiles, every tile painted, then the tile size doubled.
func _make_grown_tileset() -> void:
	var img := Image.create(192, 192, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.3, 0.2))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.add_physics_layer()
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(32, 32)
	ts.add_source(src, 0)
	for y in 6:
		for x in 6:
			src.create_tile(Vector2i(x, y))
			src.get_tile_data(Vector2i(x, y), 0).add_collision_polygon(0)
			src.get_tile_data(Vector2i(x, y), 0).set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)]))
	check(ResourceSaver.save(ts, TILES) == OK, "saved the tileset")
	_paint_room(ROOM, load_fresh(TILES) as TileSet)
	var grown := load_fresh(TILES) as TileSet
	(grown.get_source(0) as TileSetAtlasSource).texture_region_size = Vector2i(64, 64)
	ResourceSaver.save(grown, TILES)
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var loaded := load_fresh(TILES) as TileSet
	_keep.append(loaded)
	_keep.append(load_fresh(ROOM))
	OS.remove_logger(catcher)
	var src_loaded := loaded.get_source(0) as TileSetAtlasSource
	check(src_loaded.get_atlas_grid_size() == Vector2i(3, 3) and src_loaded.has_tiles_outside_texture(), "the grown tileset has tiles past its sheet's edge")
	check(not catcher.no_tile().is_empty(), "and Godot logs \"no tile at\" while loading it (%d)" % catcher.no_tile().size())

func _reads_are_quiet(path: String, label: String) -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var meta := MDSSceneScanner.new().analyze_scene(path, false)
	var painter := MDSRoomPainter.open(path)
	var c := MDSRoomCheck.new({})
	c.room_rects.assign([Rect2(0, 0, 192, 192)])
	c.build_from_painter(painter, host)
	c.run()
	c.free_proxy()
	var depth := MDSDepth25D.new()
	depth.sources = [painter.layers["Terrain"]]
	add_child(depth)
	await get_tree().process_frame
	await get_tree().process_frame
	depth.free()
	painter.erase("Terrain", [Vector2i(5, 5), Vector2i(1, 1)])
	painter.checkpoint()
	var conv := MDSFreeformConverter.new()
	conv.set_room([Rect2(0, 0, 192, 192)], [])
	conv.convert(painter)
	painter.undo()
	var deco := MDSFreeformDecorator.new()
	deco.room_rects.assign([Rect2(0, 0, 192, 192)])
	deco.decorate(painter)
	painter.free_instance()
	OS.remove_logger(catcher)
	var no_tile := catcher.no_tile()
	check(no_tile.is_empty(), "%s: scanning, Check room, 2.5D, Erase, Convert and Decorate log nothing (%d: %s)" % [label, no_tile.size(), "; ".join(no_tile.slice(0, 2))])
	check(meta.content_rect.end.x <= 96.5 and meta.content_rect.end.y <= 96.5, "%s: they are not terrain on the map (%s)" % [label, meta.content_rect])
	check(meta.broken_tiles.size() == 1 and meta.broken_tiles[0].count == 27, "%s: the scan finds the 27 broken tiles" % label)

func _reported() -> void:
	var meta := MDSSceneScanner.new().analyze_scene(ROOM, false)
	var b: Array = meta.broken_tiles
	check(b.size() == 1 and b[0].path == "Terrain" and (b[0].sample as Array).all(func(a: Vector2i) -> bool: return a.x >= 3 or a.y >= 3), "the scan names the layer and tiles past the new edge (%s)" % [b])
	var world := MDSWorld.new()
	world.path = TMP + "/broken.idpworld.json"
	world.add_room("Broken", Rect2(0, 0, 192, 192))
	world.set_room_scene("Broken", ROOM)
	var db := {ROOM: meta}
	var analysis := MDSAnalysis.new(MDSGraph.from_world(world, db), world, db).run()
	var messages: Array = MDSWorldValidator.run(world, analysis, db).map(func(i: Dictionary) -> String: return i.message)
	check(messages.any(func(m: String) -> bool: return m.contains("27 tile(s) of Terrain point at tiles its tileset no longer has") and m.contains("Remove broken tiles")), "the Issues tab says so and how to fix it")

func _room_view() -> void:
	var world := MDSWorld.new()
	world.path = TMP + "/broken_view.idpworld.json"
	world.add_room("Broken", Rect2(0, 0, 192, 192))
	world.set_room_scene("Broken", ROOM)
	var view := MDSRoomView.new()
	add_child(view)
	var messages: Array = []
	view.status_message.connect(func(t: String) -> void: messages.append(t))
	check(view.open_room(world, "Broken").is_empty(), "the Room view opens the room")
	check(view.broken_button.visible and messages.any(func(m: String) -> bool: return m.contains("27 on Terrain")), "and offers Remove broken tiles (%s)" % [messages])
	check(view.painter.has_dropped_tiles(), "it sees the tiles past the sheet's edge")
	check(view.remove_broken_tiles() == 27 and not view.broken_button.visible, "Remove broken tiles erases the 27 cells")
	check(not view.painter.has_dropped_tiles() and view.painter.layers["Terrain"].get_used_cells().size() == 9, "takes the tiles past the edge out of the tileset and keeps the good cells")
	check(view.painter.can_undo(), "undoably")
	check(view.save() == OK, "saved")
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame

func _loads_cleanly() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var ts := load_fresh(TILES) as TileSet
	var room := (load_fresh(ROOM) as PackedScene).instantiate()
	OS.remove_logger(catcher)
	var src := ts.get_source(0) as TileSetAtlasSource
	check(catcher.errors.is_empty() and src.get_tiles_count() == 9 and not src.has_tiles_outside_texture(), "the tileset was rewritten: it loads without errors (%d)" % catcher.errors.size())
	check(MDSRoomPainter.broken_cells_of(room.get_node("Terrain")).is_empty(), "and the room has no broken tiles left")
	room.free()
	_keep.append(ts)

func _removed_in_painter() -> void:
	var painter := MDSRoomPainter.open(OTHER_ROOM)
	check(painter.broken_cells().size() == 1 and painter.broken_cells()["Terrain"].size() == 27 and not painter.has_dropped_tiles(), "another room painted with the removed tiles has 27 broken cells")
	check(painter.remove_broken_cells() == 27 and painter.broken_cells().is_empty() and painter.layers["Terrain"].get_used_cells().size() == 9, "which the painter removes, keeping the good ones")
	painter.free_instance()

func _scaled_sheet_names() -> void:
	var a := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	a.fill(Color.RED)
	var b := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	b.fill(Color.RED)
	var first := MDSRoomPainter.scaled_sheet_path(SHEET, Vector2i(96, 96), Vector2i(32, 32), a)
	check(first == TMP + "/broken_fx_96x96_to_32x32.png", "a scaled sheet is named for both tile sizes (%s)" % first)
	if FileAccess.file_exists(first):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(first))
	check(MDSRoomPainter.scaled_sheet_path(SHEET, Vector2i(192, 192), Vector2i(32, 32), b) != first, "the same sheet with another tile size gets another file")
	a.save_png(first)
	check(MDSRoomPainter.scaled_sheet_path(SHEET, Vector2i(96, 96), Vector2i(32, 32), a) == first, "the same pixels reuse the file")
	var other := MDSRoomPainter.scaled_sheet_path(SHEET, Vector2i(96, 96), Vector2i(32, 32), b)
	check(other == TMP + "/broken_fx_96x96_to_32x32_2.png", "other pixels never overwrite a file a source may use (%s)" % other)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(first))
