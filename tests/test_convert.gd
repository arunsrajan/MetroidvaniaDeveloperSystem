extends "res://tests/test_case.gd"
## Brief 4: Convert to freeform.

const ROOM := TMP + "/brief4_blockout.tscn"
const GATES := [
	{"name": "left1", "pos": Vector2(0, 512), "side": "left"},
	{"name": "right1", "pos": Vector2(1152, 512), "side": "right"},
	{"name": "top1", "pos": Vector2(576, 0), "side": "top"},
]

var host: SubViewport

func _run() -> void:
	host = SubViewport.new()
	host.disable_3d = true
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(host)
	_build_room()
	_convert_blockout(true)
	_convert_blockout(false)
	_undo_restores()
	_convert_demo()
	host.queue_free()

## Tiles: 0 = solid block, 1 = one-way block.
func _tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.add_physics_layer()
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.4, 0.45))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(32, 32)
	ts.add_source(src, 0)
	for x in 2:
		src.create_tile(Vector2i(x, 0))
		var td := src.get_tile_data(Vector2i(x, 0), 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, MDSGeometry.rect_polygon(Rect2(-16, -16, 32, 32)))
		td.set_collision_polygon_one_way(0, 0, x == 1)
	return ts

## A 1152 x 648 room blocked out in tiles: floor, walls with a doorway each side, a ceiling
## with a hole, a one-way tile ledge, a one-way static body and a save point on the floor.
func _build_room() -> void:
	var room := Node2D.new()
	room.name = "Blockout"
	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = _tileset()
	room.add_child(terrain)
	var solid: Array[Vector2i] = []
	for x in 36:
		for y in range(18, 21):
			solid.append(Vector2i(x, y))
		if x < 16 or x > 19:
			for y in 2:
				solid.append(Vector2i(x, y))
	for y in range(2, 14):
		for x in [0, 1, 34, 35]:
			solid.append(Vector2i(x, y))
	for c in solid:
		terrain.set_cell(c, 0, Vector2i(0, 0))
	for x in range(14, 21):
		terrain.set_cell(Vector2i(x, 12), 0, Vector2i(1, 0))
	var step := StaticBody2D.new()
	step.name = "Step1"
	step.position = Vector2(300, 300)
	room.add_child(step)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(200, 24)
	cs.shape = rect
	cs.one_way_collision = true
	step.add_child(cs)
	var save := Sprite2D.new()
	save.name = "SavePoint"
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	save.texture = ImageTexture.create_from_image(img)
	save.centered = false
	save.offset = Vector2(-32, -64)
	save.position = Vector2(900, 576)
	save.add_to_group(&"save_point", true)
	room.add_child(save)
	check(save_scene(room, ROOM) == OK, "the blockout room saves")
	room.free()

func _converter() -> MDSFreeformConverter:
	var conv := MDSFreeformConverter.new()
	conv.room_rects = [Rect2(0, 0, 1152, 648)]
	conv.gates = GATES
	conv.seed_value = 3
	return conv

func _floor_under(shapes: Array[MDSFreeform], x: float, y0: float, y1: float) -> float:
	var best := y1
	for f in shapes:
		if not f.is_terrain():
			continue
		var outline := f.transform * f.get_outline()
		best = minf(best, MDSGeometry.solid_from(outline, x, y0, y1))
	return best

func _convert_blockout(keep_old: bool) -> void:
	var tag := " (keep old)" if keep_old else " (remove old)"
	load_fresh(ROOM)
	var painter := MDSRoomPainter.open(ROOM)
	var conv := _converter()
	conv.keep_old = keep_old
	painter.checkpoint()
	var r := conv.convert(painter)
	check(r.error.is_empty(), "the room converts%s: %s" % [tag, r])
	check(r.rock >= 1 and r.ledges == 2, "rock and two ledges are made%s (%d rock, %d ledges)" % [tag, r.rock, r.ledges])
	var shapes := MDSFreeform.shapes_in(painter.items_root)
	for f in shapes:
		check(MDSGeometry.is_simple(f.get_outline()), "%s is simple%s" % [f.name, tag])
	var names: PackedStringArray = []
	for o in conv.openings:
		names.append(o.name)
	for g in GATES:
		check(g.name in names, "%s is found as an opening%s (%s)" % [g.name, tag, names])
	# Every former platform's top is where it was.
	for want in [["Step1", Vector2(300, 288)], ["Ledge", Vector2(544, 384)]]:
		var ledge: MDSFreeform = null
		for f in shapes:
			if f.is_platform() and absf(f.position.x - want[1].x) < 20.0:
				ledge = f
		check(ledge != null and ledge.is_one_way(), "%s became a one-way ledge%s" % [want[0], tag])
		if ledge:
			var top := MDSRoomCheck._top_at(ledge.transform * ledge.get_outline(), want[1].x)
			check_near(top, want[1].y, 1.0, "%s's top stays at the same height%s" % [want[0], tag])
	# The floor under the save point stays put.
	for x in [872.0, 900.0, 928.0]:
		check_near(_floor_under(shapes, x, 500.0, 640.0), 576.0, 2.5, "the floor under the save point at x %d%s" % [x, tag])
	# The old terrain is hidden or gone.
	check(painter.layers.Terrain.get_used_cells().is_empty(), "no terrain tiles are left%s" % tag)
	check(painter.blockout.has("Terrain") == keep_old, "the old tiles are %s%s" % ["kept hidden" if keep_old else "removed", tag])
	# Played like a player: every gate open, the ledges landed on, the save point grounded.
	var c := MDSRoomCheck.new()
	c.room_rects = conv.room_rects
	c.passages = GATES
	c.build_from_painter(painter, host)
	c.run()
	var kinds := c.issues.map(func(i: Dictionary) -> String: return i.message)
	check(not c.issues.any(func(i: Dictionary) -> bool: return i.kind in ["passage", "landing", "floating", "buried"]), "every gate stays passable and everything grounded%s: %s" % [tag, kinds])
	c.free_proxy()
	# Saved, the scene has the shapes and keeps or drops the old terrain.
	var out := TMP + "/brief4_converted_%s.tscn" % ("keep" if keep_old else "remove")
	painter.scene_path = out
	check(painter.save() == OK, "the converted room saves%s" % tag)
	painter.free_instance()
	var scene := (load_fresh(out) as PackedScene).instantiate()
	var step := scene.get_node_or_null("Step1")
	if keep_old:
		check(step and not step.visible and step.process_mode == Node.PROCESS_MODE_DISABLED and step.has_meta(&"idp_blockout"), "the old step is kept, hidden and without collision")
		var bl := scene.get_node_or_null("TerrainBlockout") as TileMapLayer
		check(bl and not bl.enabled and bl.get_used_cells().size() > 100, "the old tiles are kept in a disabled TerrainBlockout layer")
	else:
		check(step == null, "the old step is removed")
		check(scene.get_node_or_null("TerrainBlockout") == null, "no blockout layer when removing")
	scene.free()
	var meta := MDSSceneScanner.new().analyze_scene(out, false)
	check(meta.twisted.is_empty(), "the scanner finds no twisted shape%s" % tag)
	check(meta.platforms.size() == 2, "the scanner lists the two ledges as platforms%s" % tag)

func _undo_restores() -> void:
	load_fresh(ROOM)
	var painter := MDSRoomPainter.open(ROOM)
	var copy := TMP + "/brief4_undo.tscn"
	painter.scene_path = copy
	painter.save()
	var before := FileAccess.get_file_as_string(copy)
	painter.checkpoint()
	_converter().convert(painter)
	check(MDSFreeform.shapes_in(painter.items_root).size() > 2, "sanity: the conversion made shapes")
	painter.undo()
	check(MDSFreeform.shapes_in(painter.items_root).is_empty(), "undo takes the shapes out")
	check(painter.layers.Terrain.get_used_cells().size() > 100, "undo brings the tiles back")
	check(painter.save() == OK, "the room saves after undo")
	check(FileAccess.get_file_as_string(copy) == before, "undo restores the room exactly")
	# And after a save in between: converted, saved, undone, saved again.
	painter.checkpoint()
	_converter().convert(painter)
	painter.save()
	painter.undo()
	painter.save()
	check(FileAccess.get_file_as_string(copy) == before, "undo restores the room exactly, even across a save")
	painter.free_instance()

func _convert_demo() -> void:
	var path := "res://asset_packs/mossgrove/demo/mossgrove_demo.tscn"
	var painter := MDSRoomPainter.open(path)
	var conv := MDSFreeformConverter.new()
	conv.rock_style = load("res://asset_packs/mossgrove/freeform/styles/mossy_rock.freeform.tres")
	painter.checkpoint()
	var r := conv.convert(painter)
	check(r.error.is_empty() and r.rock >= 1, "the Mossgrove demo converts: %s" % r)
	for f in MDSFreeform.shapes_in(painter.items_root):
		check(MDSGeometry.is_simple(f.get_outline()), "demo: %s is simple" % f.name)
	check(conv.standing.size() >= 3, "demo: the floors under its objects are pinned (%d)" % conv.standing.size())
	var shapes := MDSFreeform.shapes_in(painter.items_root)
	for s in conv.standing:
		check_near(_floor_under(shapes, s[0], s[1] - 40.0, s[1] + 40.0), s[1], 2.5, "demo: the floor under x %d stays" % s[0])
	# Openings passable before the conversion stay passable.
	var after := _blocked(painter, conv)
	painter.undo()
	var before := _blocked(painter, conv)
	painter.redo()
	var closed := Array(after).filter(func(o: String) -> bool: return not o in before)
	check(closed.is_empty(), "demo: no opening that was passable is closed (before %s, after %s)" % [before, after])
	painter.free_instance()

func _blocked(painter: MDSRoomPainter, conv: MDSFreeformConverter) -> PackedStringArray:
	var c := MDSRoomCheck.new()
	c.room_rects = conv.room_rects
	c.passages = conv.openings
	c.build_from_painter(painter, host)
	c.run()
	c.free_proxy()
	var out: PackedStringArray = []
	for i in c.issues:
		if i.kind == "passage":
			out.append(i.message.get_slice(" ", 1))
	return out
