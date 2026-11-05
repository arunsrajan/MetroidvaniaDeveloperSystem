extends "res://tests/mcp_test_case.gd"
## The MCP terrain tools: shapes, freeform, conversion, decoration, tracing, pieces, tilesets.

const STYLE := WORK + "/styles/rock.freeform.tres"
const LEDGE := WORK + "/styles/ledge.freeform.tres"
const FILLED := WORK + "/styles/fill.freeform.tres"
const SHEET := WORK + "/pics/sheet.png"
const DRAWING := WORK + "/pics/drawing.png"

func _run() -> void:
	start_server()
	await make_world()
	await _make_styles()
	_make_pictures()
	await ok("mds_room_scene_create", {"world": WORLD, "room": "R1"})
	await ok("mds_room_scene_create", {"world": WORLD, "room": "R2"})
	await _shapes()
	await _freeform()
	await _seeing_shapes()
	await _convert_and_decorate()
	await _trace()
	await _pieces()
	await _tidy()
	await _tileset()
	end_server()

func _make_styles() -> void:
	await ok("mds_resource_create", {"path": STYLE, "class": "MDSFreeformStyle", "set": {"fill_color": "#445566"}})
	await ok("mds_resource_create", {"path": LEDGE, "class": "MDSFreeformStyle", "set": {"fill_color": "#556677"}})
	await ok("mds_resource_create", {"path": FILLED, "class": "MDSFreeformStyle", "set": {"fill_color": "#112233"}})

func _make_pictures() -> void:
	DirAccess.make_dir_recursive_absolute(SHEET.get_base_dir())
	var sheet := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.GRAY)
	sheet.save_png(SHEET)
	var drawing := Image.create(200, 120, false, Image.FORMAT_RGBA8)
	drawing.fill(Color.WHITE)
	drawing.fill_rect(Rect2i(0, 80, 200, 40), Color.BLACK)
	drawing.save_png(DRAWING)

func _painter(room: String) -> MDSRoomPainter:
	var path := MDSWorld.load_world(WORLD).get_scene_path(room)
	return MDSRoomPainter.open_packed(MDSWorldSceneTools.load_fresh(path), path)

func _shapes() -> void:
	var box: Dictionary = await ok("mds_room_paint_shape", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "fill", "shape": "rect", "a": [2, 2], "b": [6, 4], "fill": {"type": "color", "color": "#ff0000"}})
	check(box.cells == 15, "a box is what it says: %s" % box)
	var hill: Dictionary = await ok("mds_room_paint_shape", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "fill", "shape": "top", "a": [10, 2], "b": [24, 10], "curve": "hill", "fill": {"type": "color", "color": "#00ff00"}})
	check(hill.cells > 0 and hill.cells < 15 * 9, "a curved face leaves some out: %s" % hill)
	var ragged: Dictionary = await ok("mds_room_paint_shape", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "erase", "shape": "irregular", "a": [2, 2], "b": [6, 4], "rough": 0.5, "seed": 2})
	check(ragged.cells > 0, "an uneven shape: %s" % ragged)
	await refused("mds_room_paint_shape", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "fill", "shape": "rect", "a": [0, 0], "b": [5000, 5000]}, "too_many_cells")
	await ok("mds_room_paint", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "clear"})

func _freeform() -> void:
	var one: Dictionary = await ok("mds_room_freeform_add", {"world": WORLD, "room": "R1", "points": [[100, 100], [300, 100], [300, 300], [100, 300]], "style_path": STYLE})
	check(one.points == 4, "a shape: %s" % one)
	var made: Dictionary = await ok("mds_node_get", {"world": WORLD, "room": "R1", "node": one.node})
	check(made["class"] == "MDSFreeform", "it is a freeform node: %s" % made)
	check(made.values.get("style") == STYLE, "with the style: %s" % made)
	await ok("mds_node_update", {"world": WORLD, "room": "R1", "node": one.node, "set": {"smooth": true}})
	var arch: Dictionary = await ok("mds_room_freeform_add", {"world": WORLD, "room": "R1", "structure": "arch", "box": {"x": 400, "y": 100, "w": 200, "h": 200}, "group": "FreeformBack", "solid": false, "style_path": LEDGE})
	check(arch.points >= 3, "a ready-made structure: %s" % arch)
	await refused("mds_room_freeform_add", {"world": WORLD, "room": "R1", "points": [[1, 1]]}, "bad_arguments")
	await refused("mds_room_freeform_add", {"world": WORLD, "room": "R1", "structure": "arch"}, "bad_arguments")
	await refused("mds_room_freeform_add", {"world": WORLD, "room": "R1", "points": [[1, 1], [2, 2], [3, 1]], "style_path": WORK + "/styles/none.tres"}, "bad_value")
	var twisted: Dictionary = await ok("mds_room_freeform_add", {"world": WORLD, "room": "R1", "points": [[700, 100], [900, 300], [900, 100], [700, 300]]})
	var repaired: Dictionary = await ok("mds_room_freeform_repair", {"world": WORLD, "room": "R1"})
	check(repaired.twisted >= 1, "a twisted shape is found: %s" % repaired)
	await ok("mds_room_freeform_repair", {"world": WORLD, "room": "R1", "node": twisted.node})
	await refused("mds_room_freeform_repair", {"world": WORLD, "room": "R1", "node": "Nobody"}, "node_not_found")
	var items: Dictionary = await ok("mds_room_items", {"world": WORLD, "room": "R1"})
	check(not items.is_empty(), "the room's items read")

func _seeing_shapes() -> void:
	await ok("mds_room_add", {"world": WORLD, "id": "R3", "rect": {"x": 0, "y": 4000, "w": 640, "h": 320}, "area": "A"})
	await ok("mds_room_scene_create", {"world": WORLD, "room": "R3"})
	var painter := _painter("R3")
	var tile := painter.tile_size()
	painter.free_instance()
	await ok("mds_room_freeform_add", {"world": WORLD, "room": "R3", "points": [[160, 96], [320, 96], [320, 224], [160, 224]], "style_path": STYLE})
	await ok("mds_room_freeform_add", {"world": WORLD, "room": "R3", "points": [[400, 96], [560, 96], [560, 224], [400, 224]], "group": "FreeformBack", "solid": false, "style_path": LEDGE})
	var solid := Vector2i((Vector2(240, 160) / tile).floor())
	var behind := Vector2i((Vector2(480, 160) / tile).floor())
	var open := Vector2i((Vector2(32, 32) / tile).floor())
	var terrain: Dictionary = await ok("mds_room_ascii", {"world": WORLD, "room": "R3", "scale": 1})
	check(terrain.rows[solid.y][solid.x] == "#", "text shows a shape: %s" % [terrain.rows])
	check(terrain.rows[behind.y][behind.x] == ".", "of the layer asked for")
	check(terrain.rows[open.y][open.x] == ".", "and not around it")
	var back: Dictionary = await ok("mds_room_ascii", {"world": WORLD, "room": "R3", "scale": 1, "layer": "Background"})
	check(back.rows[behind.y][behind.x] == "#" and back.rows[solid.y][solid.x] == ".", "the one behind is on the Background: %s" % [back.rows])
	var seen: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "mds_room_preview", "arguments": {"world": WORLD, "room": "R3", "scale": 2}}})
	var img := Image.new()
	check(img.load_png_from_buffer(Marshalls.base64_to_raw(str(seen.result.content[0].data))) == OK, "a picture")
	var near := func(cell: Vector2i, want: Color) -> bool:
		var got := img.get_pixelv(cell * 2)
		return absf(got.r - want.r) + absf(got.g - want.g) + absf(got.b - want.b) < 0.03
	check(near.call(solid, MDSMcpToolsRoom.LAYER_COLORS["Terrain"]), "it draws the shape")
	check(near.call(behind, MDSMcpToolsRoom.LAYER_COLORS["Background"]), "and the one behind")
	check(near.call(open, MDSMcpToolsRoom.PREVIEW_SKY), "and leaves the rest open")

func _convert_and_decorate() -> void:
	await ok("mds_room_generate", {"world": WORLD, "room": "R2", "style": "cave", "seed": 7})
	var conv: Dictionary = await ok("mds_room_convert", {"world": WORLD, "room": "R2", "rock_style": STYLE, "ledge_style": LEDGE, "seed": 4, "fill_outside": FILLED})
	check(int(conv.get("rock", 0)) > 0, "tiles become rock: %s" % conv)
	var again: Dictionary = await call_mcp("mds_room_convert", {"world": WORLD, "room": "R2", "rock_style": STYLE, "ledge_style": LEDGE, "seed": 4})
	check(not again.is_empty(), "again gives an answer: %s" % [again.keys()])
	var outside: Dictionary = await ok("mds_room_fill_outside", {"world": WORLD, "room": "R2", "style": FILLED})
	check(outside.has("shapes"), "fills outside: %s" % outside)
	await refused("mds_room_fill_outside", {"world": WORLD, "room": "R2", "style": WORK + "/styles/none.tres"}, "bad_value")
	await refused("mds_room_convert", {"world": WORLD, "room": "R2", "rock_style": SHEET}, "bad_value")

	var one: Dictionary = await ok("mds_room_decorate_freeform", {"world": WORLD, "room": "R2", "seed": 9, "structures": true, "structure_kinds": ["column", "mound"], "structure_style": LEDGE, "foreground": true, "foreground_style": LEDGE, "hanging": false, "floor_plants": false})
	check(one.has("structures"), "decorates: %s" % one)
	var second: Dictionary = await ok("mds_room_decorate_freeform", {"world": WORLD, "room": "R2", "seed": 9, "structures": true, "structure_kinds": ["column", "mound"], "structure_style": LEDGE, "foreground": true, "foreground_style": LEDGE, "hanging": false, "floor_plants": false})
	check(second.get("structures") == one.get("structures"), "the same seed gives the same: %s and %s" % [one, second])
	await refused("mds_room_decorate_freeform", {"world": WORLD, "room": "R2", "stamp_set": STYLE}, "bad_value")

func _trace() -> void:
	var seen: Dictionary = await ok("mds_room_trace", {"world": WORLD, "room": "R1", "image": DRAWING, "dry_run": true})
	check(seen.colors.size() >= 1 and seen.width == 200, "colors are listed: %s" % seen)
	await refused("mds_room_trace", {"world": WORLD, "room": "R1", "image": WORK + "/pics/none.png"}, "not_found")
	var made: Dictionary = await ok("mds_room_trace", {"world": WORLD, "room": "R1", "image": DRAWING, "styles": {"terrain": STYLE, "background": LEDGE}, "colors": [{"color": "#000000", "layer": "terrain"}, {"color": "#ffffff", "layer": "ignore"}]})
	check(not made.is_empty(), "traced: %s" % made)
	var painter := _painter("R1")
	check(painter.items("Freeform").size() > 3, "shapes are in the room: %d" % painter.items("Freeform").size())
	painter.free_instance()
	var layers := [{"color": "#000000", "layer": "terrain"}, {"color": "#ffffff", "layer": "ignore"}]
	var plain: Dictionary = await ok("mds_room_trace", {"world": WORLD, "room": "R1", "image": DRAWING, "output": "colors", "colors": layers})
	check(plain.terrain >= 1 and plain.removed >= 1, "solid colors take the last trace's place: %s" % plain)
	var tiles: Dictionary = await ok("mds_room_trace", {"world": WORLD, "room": "R1", "image": DRAWING, "output": "tiles", "colors": layers})
	check(tiles.tiles > 0 and tiles.removed >= 1, "tiles too: %s" % tiles)
	painter = _painter("R1")
	check(painter.layer("Terrain").get_used_cells().size() >= int(tiles.tiles), "on the Terrain layer")
	painter.free_instance()
	var drawn: Dictionary = await ok("mds_room_trace", {"world": WORLD, "room": "R1", "image": DRAWING, "output": "picture", "colors": layers})
	check(drawn.pictures == 1 and drawn.collision >= 1, "the drawing itself, with collision: %s" % drawn)
	check(int(drawn.removed_tiles) == int(tiles.tiles), "and the traced tiles go: %s" % drawn)
	painter = _painter("R1")
	var pictures := painter.items(MDSRoomPainter.PICTURES_GROUP)
	check(pictures.size() == 1 and (pictures[0] as MDSDrawing).texture != null, "the room holds it: %s" % [pictures])
	painter.free_instance()
	await refused("mds_room_trace", {"world": WORLD, "room": "R1", "image": DRAWING, "colors": [{"color": "nope"}]}, "bad_value")
	await refused("mds_room_trace", {"world": WORLD, "room": "R1", "image": DRAWING, "colors": [{"color": "#000000", "layer": "nope"}]}, "bad_value")

func _pieces() -> void:
	var piece: Dictionary = await ok("mds_room_tile_piece", {"world": WORLD, "room": "R1", "layer": "Decor", "tiles": [[0, 0, 0, 0, 0], [1, 0, 0, 1, 0]], "pos": {"x": 40, "y": 60}, "rotation": 30})
	check(piece.tiles == 2, "tiles off the grid: %s" % piece)
	var seen: Dictionary = await ok("mds_node_get", {"world": WORLD, "room": "R1", "node": piece.node})
	check(seen.pos == [40, 60], "where it was put: %s" % seen)
	await refused("mds_room_tile_piece", {"world": WORLD, "room": "R1", "layer": "Decor", "tiles": []}, "bad_arguments")
	await refused("mds_room_tile_piece", {"world": WORLD, "room": "R1", "layer": "Decor", "tiles": [[1, 2]]}, "bad_arguments")

func _tidy() -> void:
	var report: Dictionary = await ok("mds_room_tidy", {"world": WORLD, "room": "R1", "ops": ["hidden", "broken"]})
	check(report.has("hidden") and report.has("broken"), "both run: %s" % report)

func _tileset() -> void:
	var tiles := WORK + "/tiles/t.tres"
	var before: Dictionary = await ok("mds_tileset_get", {"tileset": tiles})
	check(before.has("sheets") and before.has("terrains"), "what it has: %s" % [before.keys()])
	var added: Dictionary = await ok("mds_tileset_edit", {"tileset": tiles, "op": "add_sheet", "texture": SHEET, "tile": [16, 16], "collision": false})
	check(added.source >= 0, "a sheet: %s" % added)
	var after: Dictionary = await ok("mds_tileset_get", {"tileset": tiles})
	check(after.sheets.size() == before.sheets.size() + 1, "it is there: %s" % [after.sheets])
	await ok("mds_tileset_edit", {"tileset": tiles, "op": "collision", "source": added.source, "coords": [[0, 0]], "solid": true})
	await ok("mds_tileset_edit", {"tileset": tiles, "op": "tag", "source": added.source, "coords": [[1, 0]], "kind": "spikes"})
	var terrain: Dictionary = await call_mcp("mds_tileset_edit", {"tileset": tiles, "op": "terrain", "source": added.source, "region": {"x": 0, "y": 0, "w": 3, "h": 3}, "name": "Moss", "color": "#00ff00"})
	check(terrain.has("terrain"), "a terrain from a block of tiles: %s" % terrain)
	await refused("mds_tileset_edit", {"tileset": tiles, "op": "terrain", "source": added.source, "region": {"x": 0, "y": 0, "w": 1, "h": 1}, "name": "Bad"}, "tileset_not_changed")
	await refused("mds_tileset_edit", {"tileset": tiles, "op": "collision", "source": 99, "coords": [[0, 0]]}, "tileset_not_changed")
	await refused("mds_tileset_edit", {"tileset": tiles, "op": "add_sheet", "texture": WORK + "/pics/none.png", "tile": [16, 16]}, "tileset_not_changed")
	await refused("mds_tileset_edit", {"tileset": WORK + "/tiles/none.tres", "op": "remove_sheet", "source": 0}, "not_found")
	var reloaded := ResourceLoader.load(tiles, "", ResourceLoader.CACHE_MODE_REPLACE) as TileSet
	check(reloaded.has_source(added.source), "the file has the sheet")
	await ok("mds_tileset_edit", {"tileset": tiles, "op": "remove_sheet", "source": added.source})
	var gone := ResourceLoader.load(tiles, "", ResourceLoader.CACHE_MODE_REPLACE) as TileSet
	check(not gone.has_source(added.source), "and it can go")
