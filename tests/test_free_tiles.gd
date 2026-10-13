extends "res://tests/test_case.gd"
## Tiles off the grid and the Room view's Place and Select tools:
## - the tile palette turns its tiles 0 to 360 degrees (and mirrors them); the brushes paint them
##   on the grid turned to the nearest right angle (alternative-tile flags), pattern and all;
## - free tile pieces (MDSRoomPainter.add_tile_piece) sit anywhere, at any angle, collide like
##   their layer, survive undo and saving, and go back on the grid (merge_piece);
## - the Select tool picks grid tiles, free tiles, stamps and freeform shapes (click, Shift+click,
##   box), moves them by pixels (tiles leave the grid) or by whole tiles (they stay on it),
##   turns them and deletes them.
##
## The tileset: 16 px tiles, a 4x2 sheet of colors, every tile solid; tile (1, 0) is a slope (the
## lower right half of its square).

const TILES := TMP + "/free_tiles.tres"
const ROOM := TMP + "/free_tiles_room.tscn"
const SLOPE := Vector2i(1, 0)
const TURN_90 := TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_H

var host: SubViewport

func _run() -> void:
	host = SubViewport.new()
	host.disable_3d = true
	host.size = Vector2i(4, 4)
	add_child(host)
	var ts := _tileset()
	_flags()
	_turned_brushes(ts)
	_pieces(ts)
	await _room_view()

func _tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_physics_layer()
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 2:
		for x in 4:
			img.fill_rect(Rect2i(x * 16, y * 16, 16, 16), Color.from_hsv((x + y * 4) / 8.0, 0.8, 0.9))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(16, 16)
	# In the tileset first, so its tiles get the physics layer.
	ts.add_source(src, 0)
	for y in 2:
		for x in 4:
			src.create_tile(Vector2i(x, y))
			var td := src.get_tile_data(Vector2i(x, y), 0)
			td.add_collision_polygon(0)
			var pts := PackedVector2Array([Vector2(-8, 8), Vector2(8, 8), Vector2(8, -8)]) if Vector2i(x, y) == SLOPE else rect_points(Rect2(-8, -8, 16, 16))
			td.set_collision_polygon_points(0, 0, pts)
	check(ResourceSaver.save(ts, TILES) == OK, "saved the tileset")
	return load_fresh(TILES) as TileSet

func _new_room() -> MDSRoomPainter:
	var root := Node2D.new()
	root.name = "FreeTilesRoom"
	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = load(TILES)
	root.add_child(terrain)
	save_scene(root, ROOM)
	root.free()
	load_fresh(ROOM)
	return MDSRoomPainter.open(ROOM)

## Alternative-tile flags and the transforms they stand for.
func _flags() -> void:
	var f_h := TileSetAtlasSource.TRANSFORM_FLIP_H
	var f_v := TileSetAtlasSource.TRANSFORM_FLIP_V
	var tr := TileSetAtlasSource.TRANSFORM_TRANSPOSE
	var all := true
	for flags in [0, f_h, f_v, f_h | f_v, tr, tr | f_h, tr | f_v, tr | f_h | f_v]:
		all = all and MDSRoomPainter.basis_flags(MDSRoomPainter.flags_basis(flags)) == flags
	check(all, "every flip and turn flag set stands for its own transform")
	check(MDSRoomPainter.basis_flags(Transform2D(PI / 2.0, Vector2.ZERO)) == TURN_90, "a quarter turn clockwise is transpose + flip H")
	check(MDSRoomPainter.flags_basis(TURN_90) * Vector2(-8, 8) == Vector2(-8, -8), "which turns the lower left corner to the upper left one")
	var near := MDSRoomPainter.right_angle_basis(Transform2D(deg_to_rad(100.0), Vector2(3, 4)))
	check(near.x.is_equal_approx(Vector2(0, 1)) and near.y.is_equal_approx(Vector2(-1, 0)) and near.origin == Vector2.ZERO, "100 degrees is nearest a quarter turn (%s)" % near)
	var mirrored := MDSRoomPainter.right_angle_basis(Transform2D(deg_to_rad(10.0), Vector2.ZERO) * Transform2D.FLIP_X)
	check(mirrored.x.is_equal_approx(Vector2(-1, 0)) and mirrored.y.is_equal_approx(Vector2(0, 1)), "a mirror stays a mirror (%s)" % mirrored)
	check(MDSRoomPainter.quarter_turns(37.0) == 0 and MDSRoomPainter.quarter_turns(100.0) == 1 and MDSRoomPainter.quarter_turns(-90.0) == 3 and MDSRoomPainter.quarter_turns(359.0) == 0, "angles round to the nearest quarter turn")

## Palette tiles turned and mirrored, painted on the grid.
func _turned_brushes(_ts: TileSet) -> void:
	var painter := _new_room()
	var l: TileMapLayer = painter.layers["Terrain"]
	var pair := {"type": "stamp", "source": 0, "region": Rect2i(0, 0, 2, 1), "random": false}
	painter.paint_fill("Terrain", [Vector2i(0, 0), Vector2i(1, 0)], pair)
	check(l.get_cell_atlas_coords(Vector2i(0, 0)) == Vector2i(0, 0) and l.get_cell_atlas_coords(Vector2i(1, 0)) == Vector2i(1, 0) and l.get_cell_alternative_tile(Vector2i(0, 0)) == 0, "unturned, the pair paints as picked")
	var turned := pair.duplicate()
	turned.rotation = 90.0
	painter.paint_fill("Terrain", [Vector2i(4, 0), Vector2i(4, 1), Vector2i(5, 0)], turned)
	check(l.get_cell_atlas_coords(Vector2i(4, 0)) == Vector2i(0, 0) and l.get_cell_atlas_coords(Vector2i(4, 1)) == Vector2i(1, 0), "turned a quarter, the pair stands up: left tile on top (%s, %s)" % [l.get_cell_atlas_coords(Vector2i(4, 0)), l.get_cell_atlas_coords(Vector2i(4, 1))])
	check(l.get_cell_alternative_tile(Vector2i(4, 0)) == TURN_90 and l.get_cell_atlas_coords(Vector2i(5, 0)) == Vector2i(0, 0), "each tile is turned too, and the pattern repeats a column wide")
	turned.rotation = 100.0
	painter.paint_fill("Terrain", [Vector2i(8, 0)], turned)
	check(l.get_cell_alternative_tile(Vector2i(8, 0)) == TURN_90, "100 degrees paints the grid at the nearest right angle")
	var mirrored := pair.duplicate()
	mirrored.flip = true
	painter.paint_fill("Terrain", [Vector2i(10, 0), Vector2i(11, 0)], mirrored)
	check(l.get_cell_atlas_coords(Vector2i(10, 0)) == Vector2i(1, 0) and l.get_cell_alternative_tile(Vector2i(10, 0)) == TileSetAtlasSource.TRANSFORM_FLIP_H, "mirrored, the pair swaps and each tile flips")
	check(MDSRoomPainter.is_cell_valid(l, Vector2i(4, 0)) and painter.broken_cells().is_empty(), "turned tiles are not broken tiles")
	# A turned slope collides turned: the lower left half of its cell, not the lower right.
	painter.paint_fill("Terrain", [Vector2i(20, 10)], {"type": "stamp", "source": 0, "region": Rect2i(SLOPE, Vector2i.ONE), "rotation": 90.0})
	var c := MDSRoomCheck.new()
	c.build_from_painter(painter, host)
	var center := l.map_to_local(Vector2i(20, 10))
	var lower_left := false
	var upper_right := false
	for poly in c._ground.get_children():
		if poly is CollisionPolygon2D:
			lower_left = lower_left or Geometry2D.is_point_in_polygon(center + Vector2(-5, 5), poly.polygon)
			upper_right = upper_right or Geometry2D.is_point_in_polygon(center + Vector2(5, -5), poly.polygon)
	check(lower_left and not upper_right, "a slope turned a quarter collides in its lower left half")
	c.free_proxy()
	painter.free_instance()

func _piece_at(painter: MDSRoomPainter, p: Vector2) -> bool:
	var hit := painter.item_at(p)
	return hit != null and MDSRoomPainter.is_tile_piece(hit)

## Free tile pieces in the painter: placing, lifting, merging, saving.
func _pieces(_ts: TileSet) -> void:
	var painter := _new_room()
	var l: TileMapLayer = painter.layers["Terrain"]
	painter.checkpoint()
	var tiles := {Vector2i(0, 0): [0, Vector2i(0, 0), 0], Vector2i(1, 0): [0, Vector2i(2, 0), 0]}
	var piece := painter.add_tile_piece("Terrain", tiles, Transform2D(deg_to_rad(30.0), Vector2(200, 100)))
	check(MDSRoomPainter.is_tile_piece(piece) and painter.tile_pieces().size() == 1 and piece.get_parent().name == "Tiles", "a free tile piece goes to the Tiles group")
	check(piece.z_index == MDSRoomPainter.LAYER_Z.Terrain and piece.tile_set == painter.tile_set and String(piece.name) == "TerrainTiles1", "at the Terrain layer's depth, with the room's tileset")
	var inside := piece.transform * Vector2(24, 8)
	check(_piece_at(painter, inside) and not _piece_at(painter, Vector2(200, 100) + Vector2(-4, -4)), "it is picked where its tiles are, turned with it")
	var outline := MDSRoomPainter.item_outline(piece)
	check(outline.size() == 4 and outline[0].is_equal_approx(Vector2(200, 100)) and outline[1].is_equal_approx(Vector2(200, 100) + Vector2(32, 0).rotated(deg_to_rad(30.0))), "its outline is its box, turned (%s)" % outline)
	check(not painter.is_piece_on_grid(piece), "a turned piece is off the grid")
	# Grid tiles lifted off the grid, moved by pixels, then put back by whole tiles.
	for x in range(4, 7):
		l.set_cell(Vector2i(x, 5), 0, Vector2i(3, 1))
	var lifted := painter.lift_cells("Terrain", [Vector2i(4, 5), Vector2i(5, 5), Vector2i(9, 9)])
	check(lifted != null and lifted.get_used_cells().size() == 2 and l.get_cell_source_id(Vector2i(4, 5)) == -1 and l.get_cell_source_id(Vector2i(6, 5)) == 0, "lifting takes the tiles off the grid (empty cells are skipped)")
	check(painter.is_piece_on_grid(lifted) and lifted.get_cell_atlas_coords(Vector2i(4, 5)) == Vector2i(3, 1), "in the same place, the same tiles")
	lifted.position += Vector2(5, 3)
	check(not painter.is_piece_on_grid(lifted), "moved by pixels, they are off the grid")
	lifted.position += Vector2(27, 13)
	check(painter.is_piece_on_grid(lifted), "moved by whole tiles in all, they line up again")
	var written := painter.merge_piece(lifted)
	check(written.size() == 2 and l.get_cell_atlas_coords(Vector2i(6, 6)) == Vector2i(3, 1) and l.get_cell_atlas_coords(Vector2i(7, 6)) == Vector2i(3, 1), "merged back two tiles right and one down (%s)" % [written])
	check(lifted.get_parent() == null and painter.tile_pieces().size() == 1, "and the piece is gone")
	# A piece turned a quarter merges with its tiles turned.
	var quarter := painter.add_tile_piece("Terrain", {Vector2i(0, 0): [0, Vector2i(0, 0), 0], Vector2i(1, 0): [0, Vector2i(1, 0), 0]}, Transform2D(PI / 2.0, Vector2(32 + 16, 160)))
	check(painter.is_piece_on_grid(quarter), "a piece turned a quarter, on a grid corner, is on the grid")
	painter.merge_piece(quarter)
	check(l.get_cell_atlas_coords(Vector2i(2, 10)) == Vector2i(0, 0) and l.get_cell_atlas_coords(Vector2i(2, 11)) == Vector2i(1, 0) and l.get_cell_alternative_tile(Vector2i(2, 11)) == TURN_90, "it merges standing up, its tiles turned (%s %s)" % [l.get_cell_atlas_coords(Vector2i(2, 11)), l.get_cell_alternative_tile(Vector2i(2, 11))])
	# Undo and redo.
	painter.undo()
	check(painter.tile_pieces().is_empty() and l.get_cell_source_id(Vector2i(4, 5)) == -1, "undo takes the pieces and moves back out")
	painter.redo()
	check(painter.tile_pieces().size() == 1 and is_equal_approx((painter.tile_pieces()[0] as TileMapLayer).rotation, deg_to_rad(30.0)), "redo brings the turned piece back")
	# The check collides with the piece where it was turned to.
	var c := MDSRoomCheck.new()
	c.build_from_painter(painter, host)
	var hit := false
	for poly in c._ground.get_children():
		if poly is CollisionPolygon2D and Geometry2D.is_point_in_polygon(inside, poly.polygon):
			hit = true
	check(hit, "Check room collides with the free tiles where they are")
	c.free_proxy()
	# Saved: a TileMapLayer in the Tiles group, not taken for one of the room's layers.
	check(painter.save() == OK, "saved")
	painter.free_instance()
	var packed := load_fresh(ROOM) as PackedScene
	var scene := packed.instantiate()
	var saved := scene.get_node_or_null("Tiles/TerrainTiles1") as TileMapLayer
	check(saved != null and saved.get_meta(MDSRoomPainter.PIECE_META) == "Terrain" and is_equal_approx(saved.rotation, deg_to_rad(30.0)) and saved.get_used_cells().size() == 2, "the scene has the piece, turned, marked with its layer")
	scene.free()
	var again := MDSRoomPainter.open(ROOM)
	check(again.tile_pieces().size() == 1 and String(again.layers["Terrain"].name) == "Terrain" and again.layers["Terrain"].get_cell_source_id(Vector2i(6, 6)) == 0, "opened again, the piece is a piece and the Terrain layer is the room's")
	again.free_instance()

func _press(canvas: MDSRoomCanvas, p: Vector2, pressed: bool, shift := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.shift_pressed = shift
	mb.position = canvas.local_to_screen(p)
	canvas._gui_input(mb)

func _drag(canvas: MDSRoomCanvas, a: Vector2, b: Vector2) -> void:
	_press(canvas, a, true)
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	for t in [0.5, 1.0]:
		mm.position = canvas.local_to_screen(a.lerp(b, t))
		canvas._gui_input(mm)
	_press(canvas, b, false)

func _key(canvas: MDSRoomCanvas, code: Key, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.shift_pressed = shift
	canvas._gui_input(k)

## The Room view: the palette's turn, the Place tool, the Select tool.
func _room_view() -> void:
	var painter := _new_room()
	painter.free_instance()
	var world := MDSWorld.new()
	world.path = TMP + "/free_tiles.mdsworld.json"
	world.add_room("Yard", Rect2(0, 0, 640, 320))
	world.set_room_scene("Yard", ROOM)
	var view := MDSRoomView.new()
	view.size = Vector2(900, 600)
	add_child(view)
	await get_tree().process_frame
	check(view.open_room(world, "Yard").is_empty(), "the Room view opens the room")
	var canvas := view.canvas
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO
	canvas._apply_view()
	var messages: Array = []
	view.status_message.connect(func(t: String) -> void: messages.append(t))
	check(view.tool_buttons.size() == 10 and view.tool_buttons[MDSRoomCanvas.Tool.PLACE].text == "Place" and view.tool_buttons[MDSRoomCanvas.Tool.SELECT].text == "Select", "the Place and Select tools have buttons")
	# The palette: tiles picked and turned.
	var palette := view.palette
	palette.select_region(Rect2i(0, 0, 2, 1))
	palette.set_turn(37.0)
	check(is_equal_approx(palette.turn_degrees, 37.0) and is_equal_approx(float(palette.get_fill().rotation), 37.0) and palette.describe_fill().contains("turned 37"), "the palette turns its tiles to any angle (%s)" % palette.describe_fill())
	palette.set_turn(-30.0)
	check(is_equal_approx(palette.turn_degrees, 330.0) and is_equal_approx(palette.turn_spin.value, 330.0), "angles stay within 0 to 360")
	palette.set_turn(37.0)
	check(is_equal_approx(float(canvas.fills[MDSRoomCanvas.Tool.TERRAIN].get("rotation", 0.0)), 37.0), "the brush painting palette tiles takes the angle")
	check(messages.back().contains("nearest right angle"), "and is told the grid paints them at the nearest right angle (%s)" % messages.back())
	# Place: the tiles at 37 degrees, centred on the click, at the picked layer's depth.
	view.set_tool(MDSRoomCanvas.Tool.PLACE)
	check(view._turn_row.visible and view.snap_check.visible and not view.fill_opt.get_parent().visible and view.layer_opt.item_count == 4, "Place shows its turn, snap and layer controls, not the fills")
	view.layer_opt.select(3)
	view._on_layer_selected(3)
	_press(canvas, Vector2(300, 150), true)
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.position = canvas.local_to_screen(Vector2(310, 154))
	canvas._gui_input(mm)
	_press(canvas, Vector2(310, 154), false)
	var placed: Array = view.painter.tile_pieces("Foreground")
	check(placed.size() == 1, "a click places the tiles as a free piece of the Foreground layer")
	if placed.size() == 1:
		var piece: TileMapLayer = placed[0]
		check(is_equal_approx(piece.rotation, deg_to_rad(37.0)) and piece.z_index == MDSRoomPainter.LAYER_Z.Foreground, "turned 37 degrees, at the Foreground's depth")
		check((piece.transform * Vector2(16, 8)).distance_to(Vector2(310, 154)) < 0.6, "centred where the drag after the click left it (%s)" % (piece.transform * Vector2(16, 8)))
		check(canvas.selection.size() == 1 and canvas.selection[0] == piece, "and selected")
	_key(canvas, KEY_R)
	check(is_equal_approx(palette.turn_degrees, 52.0), "R turns the palette's tiles by the turn step (%.0f)" % palette.turn_degrees)
	# With Snap to tiles and a right angle, placed tiles line up with the grid.
	view.snap_check.button_pressed = true
	palette.set_turn(90.0)
	view.layer_opt.select(1)
	view._on_layer_selected(1)
	var snapped := canvas.place_tiles_at(Vector2(101, 99))
	check(snapped != null and view.painter.is_piece_on_grid(snapped), "snapped, a quarter turn lines up with the grid")
	view.snap_check.button_pressed = false
	palette.set_turn(0.0)
	# Select: grid tiles, then items.
	view.set_tool(MDSRoomCanvas.Tool.SELECT)
	check(view._select_row.visible and view.layer_opt.item_count == MDSRoomCanvas.PICK_LAYER_NAMES.size(), "Select shows its pick list and buttons")
	var l: TileMapLayer = view.painter.layers["Terrain"]
	view.painter.checkpoint()
	for y in range(2, 4):
		for x in range(2, 5):
			l.set_cell(Vector2i(x, y), 0, Vector2i(x - 2, y - 2))
	_press(canvas, Vector2(40, 40), true)
	_press(canvas, Vector2(40, 40), false)
	check(canvas.selection.is_empty() and canvas.selected_cells.get("Terrain", {}).keys() == [Vector2i(2, 2)], "a click selects the grid tile under it (%s)" % [canvas.selected_cells])
	_press(canvas, Vector2(72, 56), true, true)
	_press(canvas, Vector2(72, 56), false, true)
	check(canvas.selection_counts() == Vector2i(0, 2), "Shift+click adds another")
	_press(canvas, Vector2(72, 56), true, true)
	_press(canvas, Vector2(72, 56), false, true)
	check(canvas.selection_counts() == Vector2i(0, 1), "and takes it out again")
	_drag(canvas, Vector2(20, 20), Vector2(90, 70))
	check(canvas.selection_counts() == Vector2i(0, 6), "a box selects the six tiles in it (%s)" % canvas.selection_counts())
	_press(canvas, Vector2(40, 40), true)
	_press(canvas, Vector2(40, 40), false)
	check(canvas.selection_counts() == Vector2i(0, 1), "a click on one of them, without dragging, selects only it")
	_drag(canvas, Vector2(20, 20), Vector2(90, 70))
	# Moved by pixels: the tiles leave the grid as one free piece.
	_drag(canvas, Vector2(56, 40), Vector2(61, 43))
	var off: Array = canvas.selection.filter(func(n: Node) -> bool: return MDSRoomPainter.is_tile_piece(n))
	check(off.size() == 1 and (off[0] as TileMapLayer).get_used_cells().size() == 6 and (off[0] as TileMapLayer).position == Vector2(5, 3), "moved 5, 3 px, the six tiles are a free piece (%s)" % [off.map(func(n: Node2D) -> Vector2: return n.position)])
	check(l.get_cell_source_id(Vector2i(2, 2)) == -1 and canvas.selected_cells.is_empty(), "their cells are empty")
	check(messages.back().contains("left the grid"), "and the status says they left the grid")
	view.painter.undo()
	canvas._clean_selection()
	check(l.get_cell_source_id(Vector2i(2, 2)) == 0 and view.painter.tile_pieces("Terrain").size() == 1, "undo puts them back on the grid")
	# Moved by whole tiles with Snap to tiles: they stay on the grid.
	canvas.set_selection([], {"Terrain": [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]})
	view.snap_check.button_pressed = true
	_drag(canvas, Vector2(40, 40), Vector2(75, 58))
	check(l.get_cell_source_id(Vector2i(2, 2)) == -1 and l.get_cell_atlas_coords(Vector2i(4, 3)) == Vector2i(0, 0) and l.get_cell_atlas_coords(Vector2i(6, 4)) == Vector2i(2, 1), "snapped, they move two tiles right and one down on the grid")
	check(canvas.selected_cells.get("Terrain", {}).size() == 6 and canvas.selection.is_empty(), "and stay selected as grid tiles")
	# Turned a quarter, snapped: still on the grid, turned.
	canvas.rotate_selection(90.0)
	var turned_cells: Array = canvas.selected_cells.get("Terrain", {}).keys()
	check(turned_cells.size() == 6 and turned_cells.all(func(c: Vector2i) -> bool: return l.get_cell_alternative_tile(c) == TURN_90), "a quarter turn keeps them on the grid, each tile turned (%s)" % [turned_cells])
	view.snap_check.button_pressed = false
	canvas.rotate_selection(30.0)
	var turned_piece: Array = canvas.selection.filter(func(n: Node) -> bool: return MDSRoomPainter.is_tile_piece(n))
	check(turned_piece.size() == 1 and is_equal_approx((turned_piece[0] as Node2D).rotation, deg_to_rad(30.0)) and canvas.selected_cells.is_empty(), "30 degrees takes them off the grid, turned")
	var merged := canvas.merge_selection_to_grid()
	var back: Array = canvas.selected_cells.get("Terrain", {}).keys()
	check(merged == 6 and not back.is_empty() and canvas.selection.is_empty() and back.all(func(c: Vector2i) -> bool: return l.get_cell_alternative_tile(c) == TURN_90), "To grid puts them back on the grid, each still turned its quarter (%d, %s)" % [merged, back])
	# Items: a stamp and a freeform shape, picked, moved by pixels, turned, deleted.
	var stamp := Sprite2D.new()
	var tex := ImageTexture.create_from_image(Image.create(20, 20, false, Image.FORMAT_RGBA8))
	stamp.texture = tex
	stamp.region_enabled = true
	stamp.region_rect = Rect2(0, 0, 20, 20)
	stamp.centered = false
	stamp.position = Vector2(400, 200)
	stamp.set_meta(&"mds_stamp", 0)
	view.painter.add_item(stamp, "StampsFront")
	var shape := view.painter.add_freeform(rect_points(Rect2(480, 160, 40, 20)), MDSFreeformStyle.builtins()[0])
	_press(canvas, Vector2(410, 210), true)
	_press(canvas, Vector2(410, 210), false)
	_press(canvas, Vector2(500, 170), true, true)
	_press(canvas, Vector2(500, 170), false, true)
	check(canvas.selection.size() == 2 and stamp in canvas.selection and shape in canvas.selection, "a stamp and a shape are selected together")
	_key(canvas, KEY_RIGHT)
	_key(canvas, KEY_DOWN, true)
	check(stamp.position == Vector2(401, 216) and shape.position == Vector2(1, 16), "the arrows nudge them a pixel, Shift a tile (%s, %s)" % [stamp.position, shape.position])
	canvas.rotate_selection(90.0)
	var b := MDSGeometry.bounds(Transform2D(0.0, shape.position) * shape.get_outline())
	check(b.size.x < b.size.y and is_equal_approx(shape.rotation, 0.0), "turning a shape turns its points, not the node (%s)" % b)
	check(not is_equal_approx(stamp.rotation, 0.0), "and turns the stamp")
	_key(canvas, KEY_DELETE)
	check(not is_instance_valid(stamp) or stamp.get_parent() == null, "Delete removes them")
	check(canvas.selection.is_empty(), "and empties the selection")
	view.painter.undo()
	canvas._clean_selection()
	check(view.painter.items("StampsFront").size() == 1 and view.painter.items("Freeform").size() == 1, "undo brings them back")
	# What a click picks follows the pick list.
	view.layer_opt.select(MDSRoomCanvas.PickLayer.ITEMS)
	view._on_layer_selected(MDSRoomCanvas.PickLayer.ITEMS)
	check(canvas.pick_at(Vector2(100, 56)).is_empty() or canvas.pick_at(Vector2(100, 56)).has("item"), "Items only never picks grid tiles")
	# Erase removes free tiles under the brush too.
	var free := view.painter.add_tile_piece("Terrain", {Vector2i(0, 0): [0, Vector2i(0, 0), 0]}, Transform2D(0.0, Vector2(608, 288)))
	canvas.erase_cells([view.painter.cell_at("Terrain", Vector2(608, 288))], MDSRoomCanvas.EraseMode.TOP)
	check(not is_instance_valid(free) or free.get_parent() == null, "Erase takes free tiles out (an empty piece goes)")
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame
