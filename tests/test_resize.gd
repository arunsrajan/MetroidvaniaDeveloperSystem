extends "res://tests/test_case.gd"
## Resizing in the Room view: eight handles, on the corners and the middles of the sides
## (left, top, right, bottom, top-left, top-right, bottom-left, bottom-right).
## - the box math: each handle moves its sides only, the opposite ones stay; Shift on a corner
##   keeps the shape; never smaller than the least size;
## - effects: every handle resizes the effect's area, also an effect standing on its position
##   (a steam vent: its feet stay put when its top is dragged);
## - the Select tool: stamps scale, freeform shapes scale their points, grid tiles leave the grid
##   as a scaled free tile piece; Ctrl+Z undoes it;
## - what the Stamps and Place tools just placed, and the Freeform tool's shape, have the same
##   handles; the cursor shows which way a handle resizes;
## - a resized stamp is saved resized.

const TILES := TMP + "/resize_tiles.tres"
const ROOM := TMP + "/resize_room.tscn"
const STAMPS := "res://asset_packs/mossgrove/freeform/mossgrove.stamps.tres"

var canvas: MDSRoomCanvas
var view: MDSRoomView

func _run() -> void:
	_boxes()
	await _open()
	_effects()
	_select()
	_placed()
	_saved()
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame

func _boxes() -> void:
	var b := Rect2(100, 100, 200, 100)
	var d := Vector2(30, 20)
	var want: Array[Rect2] = [Rect2(130, 120, 170, 80), Rect2(100, 120, 200, 80), Rect2(100, 120, 230, 80), Rect2(100, 100, 230, 100),
		Rect2(100, 100, 230, 120), Rect2(100, 100, 200, 120), Rect2(130, 100, 170, 120), Rect2(130, 100, 170, 100)]
	var names := ["top-left", "top", "top-right", "right", "bottom-right", "bottom", "bottom-left", "left"]
	for h in 8:
		var got := MDSRoomCanvas.resized_box(b, h, d)
		check(got.is_equal_approx(want[h]), "the %s handle moves only its sides (%s)" % [names[h], got])
		check(MDSRoomCanvas.handle_at(b, MDSRoomCanvas.handle_point(b, h) + Vector2(3, -2)) == h, "the %s handle is grabbed near it" % names[h])
	check(MDSRoomCanvas.handle_at(b, b.get_center()) == -1, "the middle of the box is no handle")
	var kept := MDSRoomCanvas.resized_box(b, 4, Vector2(100, 10), true)
	check(kept.is_equal_approx(Rect2(100, 100, 300, 150)), "Shift on a corner keeps the shape, the opposite corner staying (%s)" % kept)
	kept = MDSRoomCanvas.resized_box(b, 0, Vector2(-100, 0), true)
	check(kept.is_equal_approx(Rect2(0, 50, 300, 150)), "from the top-left corner too (%s)" % kept)
	check(is_equal_approx(MDSRoomCanvas.resized_box(b, 7, Vector2(500, 0)).size.x, 4.0), "never smaller than the least size")

func _open() -> void:
	var ts := MDSTilesetFactory.get_or_create(TILES)
	var root := Node2D.new()
	root.name = "ResizeRoom"
	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = ts
	root.add_child(terrain)
	save_scene(root, ROOM)
	root.free()
	load_fresh(ROOM)
	var world := MDSWorld.new()
	world.path = TMP + "/resize.mdsworld.json"
	world.add_room("Hall", Rect2(0, 0, 1152, 648))
	world.set_room_scene("Hall", ROOM)
	view = MDSRoomView.new()
	view.size = Vector2(1300, 800)
	add_child(view)
	await get_tree().process_frame
	check(view.open_room(world, "Hall").is_empty(), "the Room view opens the room")
	canvas = view.canvas
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO
	canvas._apply_view()

func _press(p: Vector2, pressed: bool, shift := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.shift_pressed = shift
	mb.position = canvas.local_to_screen(p)
	canvas._gui_input(mb)

## Drags from [param a] to [param b] (screen = scene, at zoom 1 with no pan).
func _drag(a: Vector2, b: Vector2, shift := false) -> void:
	_press(a, true)
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.shift_pressed = shift
	for t in [0.5, 1.0]:
		mm.position = canvas.local_to_screen(a.lerp(b, t))
		canvas._gui_input(mm)
	_press(b, false)

func _area(e: MDSEnvironmentEffect) -> Rect2:
	var r := e.get_effect_rect()
	return Rect2(e.position + r.position, r.size)

func _effects() -> void:
	view.set_tool(MDSRoomCanvas.Tool.EFFECT)
	var e := canvas.place_effect("rain", Vector2(500, 300))
	canvas.resize_effect(e, Rect2(400, 250, 200, 100))
	check(_area(e).is_equal_approx(Rect2(400, 250, 200, 100)), "an effect is resized to an area (%s)" % _area(e))
	var names := ["top-left", "top", "top-right", "right", "bottom-right", "bottom", "bottom-left", "left"]
	var d := Vector2(24, 16)
	for h in 8:
		var before := _area(e)
		_drag(MDSRoomCanvas.handle_point(before, h), MDSRoomCanvas.handle_point(before, h) + d)
		var want := MDSRoomCanvas.resized_box(before, h, d)
		check(_area(e).is_equal_approx(want), "dragging the effect's %s handle resizes it there (%s, want %s)" % [names[h], _area(e), want])
	var before := _area(e)
	_drag(before.end, before.end + Vector2(before.size.x, 0), true)
	check(_area(e).is_equal_approx(Rect2(before.position, before.size * 2.0)), "Shift keeps its shape (%s)" % _area(e))
	# A steam vent stands on its position: its jet rises from it.
	var vent := canvas.place_effect("steam_vent", Vector2(800, 500))
	var feet := vent.position
	var area := _area(vent)
	_drag(MDSRoomCanvas.handle_point(area, 1), MDSRoomCanvas.handle_point(area, 1) + Vector2(0, -40))
	check(is_equal_approx(vent.size.y, area.size.y + 40.0) and vent.position == feet, "a vent's top dragged up makes its jet longer, its feet staying (%s)" % vent.position)
	area = _area(vent)
	_drag(MDSRoomCanvas.handle_point(area, 7), MDSRoomCanvas.handle_point(area, 7) + Vector2(-20, 0))
	check(_area(vent).is_equal_approx(Rect2(area.position - Vector2(20, 0), area.size + Vector2(20, 0))), "its left side dragged, its right side stays (%s)" % _area(vent))
	canvas._update_cursor(canvas.local_to_screen(MDSRoomCanvas.handle_point(_area(vent), 3)))
	check(canvas.mouse_default_cursor_shape == Control.CURSOR_HSIZE, "over a side handle the cursor shows the way it resizes")
	canvas._update_cursor(canvas.local_to_screen(MDSRoomCanvas.handle_point(_area(vent), 2)))
	check(canvas.mouse_default_cursor_shape == Control.CURSOR_BDIAGSIZE, "and over a corner")
	canvas._update_cursor(canvas.local_to_screen(_area(vent).get_center()))
	check(canvas.mouse_default_cursor_shape == Control.CURSOR_ARROW, "elsewhere the arrow")

## The handles of the selection: around its bounds, standing out a little (scene = screen).
func _handle(h: int) -> Vector2:
	return MDSRoomCanvas.handle_point(canvas.selection_bounds().grow(MDSRoomCanvas.HANDLE_GAP), h)

func _select() -> void:
	var stamps: MDSStampSet = load(STAMPS)
	var painter := canvas.painter
	view.set_tool(MDSRoomCanvas.Tool.SELECT)
	# A stamp: dragging its right side makes it twice as wide, its left side staying.
	var s := painter.add_stamp(stamps, 0, Vector2(200, 300), Vector2.ONE)
	canvas.set_selection([s])
	var b := canvas.selection_bounds()
	_drag(_handle(3), _handle(3) + Vector2(b.size.x, 0))
	var now := canvas.selection_bounds()
	check(now.is_equal_approx(Rect2(b.position, Vector2(b.size.x * 2.0, b.size.y))), "a stamp's right handle makes it wider, its left side staying (%s from %s)" % [now, b])
	check(is_equal_approx(absf(s.scale.x), 2.0) and is_equal_approx(s.scale.y, 1.0), "it is scaled (%s)" % s.scale)
	# A freeform shape: its points scale, from the top.
	var f := canvas.add_freeform(PackedVector2Array([Vector2(600, 100), Vector2(700, 100), Vector2(700, 200), Vector2(600, 200)]))
	f.smooth = false
	canvas.set_selection([f])
	b = canvas.selection_bounds()
	_drag(_handle(5), _handle(5) + Vector2(0, b.size.y * 0.5))
	now = canvas.selection_bounds()
	check(now.is_equal_approx(Rect2(b.position, Vector2(b.size.x, b.size.y * 1.5))), "a shape's bottom handle makes it taller, its top staying (%s from %s)" % [now, b])
	# Grid tiles: they leave the grid as a free tile piece, scaled.
	var terrain: TileMapLayer = painter.layers["Terrain"]
	var cells := [Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 11), Vector2i(11, 11)]
	for c in cells:
		terrain.set_cell(c, 0, Vector2i(0, 0))
	canvas.set_selection([], {"Terrain": cells})
	b = canvas.selection_bounds()
	_drag(_handle(4), _handle(4) + b.size)
	var pieces := canvas.selection.filter(func(n: Node) -> bool: return MDSRoomPainter.is_tile_piece(n))
	check(pieces.size() == 1 and terrain.get_cell_source_id(Vector2i(10, 10)) == -1, "grid tiles resized leave the grid, as a free tile piece")
	check(not pieces.is_empty() and (pieces[0] as Node2D).scale.is_equal_approx(Vector2(2, 2)) and canvas.selection_bounds().is_equal_approx(Rect2(b.position, b.size * 2.0)), "twice as big, from their top-left corner (%s)" % canvas.selection_bounds())
	var k := InputEventKey.new()
	k.keycode = KEY_Z
	k.ctrl_pressed = true
	k.pressed = true
	canvas._gui_input(k)
	check(terrain.get_cell_source_id(Vector2i(10, 10)) == 0 and painter.tile_pieces().is_empty(), "Ctrl+Z puts them back on the grid")
	# Several at once: they scale together, about the selection's box (undo made them anew).
	s = painter.add_stamp(stamps, 0, Vector2(200, 300), Vector2.ONE)
	f = canvas.add_freeform(PackedVector2Array([Vector2(600, 100), Vector2(700, 100), Vector2(700, 200), Vector2(600, 200)]))
	f.smooth = false
	canvas.set_selection([s, f])
	b = canvas.selection_bounds()
	canvas.resize_selection(Rect2(b.position, b.size * 0.5))
	check(canvas.selection_bounds().is_equal_approx(Rect2(b.position, b.size * 0.5)), "a selection of several scales together (%s)" % canvas.selection_bounds())

func _placed() -> void:
	var painter := canvas.painter
	# Stamps: what a click placed is selected, and its handles resize it (placing none).
	view.set_tool(MDSRoomCanvas.Tool.STAMP)
	var stamps: MDSStampSet = load(STAMPS)
	canvas.stamp_set = stamps
	canvas.stamp_category = stamps.get_categories()[0]
	var count := painter.items(canvas.stamp_group).size()
	_press(Vector2(300, 500), true)
	_press(Vector2(300, 500), false)
	check(painter.items(canvas.stamp_group).size() == count + 1 and canvas.selection.size() == 1 and MDSRoomPainter.is_stamp(canvas.selection[0]), "a stamp placed is selected")
	var placed: Sprite2D = canvas.selection[0]
	var b := canvas.selection_bounds()
	_drag(_handle(7), _handle(7) - Vector2(b.size.x, 0))
	check(painter.items(canvas.stamp_group).size() == count + 1 and canvas.selection_bounds().is_equal_approx(Rect2(b.position - Vector2(b.size.x, 0), Vector2(b.size.x * 2.0, b.size.y))), "its left handle makes it wider, and places no stamp (%s)" % canvas.selection_bounds())
	check(is_instance_valid(placed), "it is the stamp placed")
	# Place: the free tiles placed are selected, with handles.
	view.set_tool(MDSRoomCanvas.Tool.PLACE)
	canvas.place_fill = {"source": 0, "region": Rect2i(0, 0, 2, 1), "random": false, "rotation": 0.0, "flip": false}
	var piece := canvas.place_tiles_at(Vector2(700, 450))
	b = canvas.selection_bounds()
	_drag(_handle(5), _handle(5) + Vector2(0, b.size.y))
	check(piece.scale.is_equal_approx(Vector2(1, 2)), "the Place tool's tiles are resized by their handles (%s)" % piece.scale)
	# Freeform: the shape picked has handles too.
	view.set_tool(MDSRoomCanvas.Tool.FREEFORM)
	canvas.freeform_mode = MDSRoomCanvas.FreeformMode.EDIT
	var f := canvas.add_freeform(PackedVector2Array([Vector2(900, 300), Vector2(1000, 300), Vector2(1000, 400), Vector2(900, 400)]))
	f.smooth = false
	canvas.selected = f
	b = MDSGeometry.bounds(MDSRoomPainter.item_outline(f))
	var right := MDSRoomCanvas.handle_point(b.grow(MDSRoomCanvas.HANDLE_GAP), 3)
	_drag(right, right + Vector2(50, 0))
	var now := MDSGeometry.bounds(MDSRoomPainter.item_outline(f))
	check(now.is_equal_approx(Rect2(b.position, b.size + Vector2(50, 0))), "the Freeform tool's shape is resized by its handles (%s)" % now)
	# A corner of the shape is still its point: dragging the point moves it, not the handle.
	_drag(Vector2(900, 300), Vector2(880, 290))
	check(f.points[0].is_equal_approx(Vector2(880, 290) - f.position), "its points are still dragged on their own")

func _saved() -> void:
	var painter := canvas.painter
	var s: Sprite2D = painter.add_stamp(load(STAMPS), 0, Vector2(400, 150), Vector2.ONE, 0.0, "StampsBack")
	s.name = "Resized"
	view.set_tool(MDSRoomCanvas.Tool.SELECT)
	canvas.set_selection([s])
	var b := canvas.selection_bounds()
	canvas.resize_selection(Rect2(b.position, b.size * Vector2(3, 1)))
	check(view.save() == OK, "the room saves")
	load_fresh(ROOM)
	var again := MDSRoomPainter.open(ROOM)
	var found: Array = again.items("StampsBack").filter(func(n: Node) -> bool: return String(n.name) == "Resized")
	check(found.size() == 1 and (found[0] as Sprite2D).scale.is_equal_approx(Vector2(3, 1)), "a stamp resized is saved resized (%s)" % [(found[0] as Sprite2D).scale if not found.is_empty() else "none"])
	again.free_instance()
