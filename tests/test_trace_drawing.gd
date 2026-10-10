extends "res://tests/test_case.gd"
## Trace drawing (MDSDrawingTracer): a drawing's colors become layers, its shapes become
## freeform shapes in the Room view's painter, holes stay open, and tracing again replaces the
## last trace.
##
## The drawing (240 x 120 px, traced over a 2400 x 1200 room, so 1 px = 10 px):
## black rock all round a white cave (20..220 x 20..100), a black island floating in the cave
## (100..140 x 40..60), an orange ledge (40..90 x 70..74), a green bush (a circle at 180, 50),
## a blue foreground blob (150..170 x 80..95), and a grey band along the cave's left wall (the
## soft edge a paint program leaves).

const ROOM := TMP + "/trace_room.tscn"
const DRAWING := TMP + "/trace_drawing.png"
const ORANGE := Color("#e8842a")
const GREEN := Color("#3fae4a")
const BLUE := Color("#3f62d8")

func _run() -> void:
	var img := _drawing()
	check(img.save_png(DRAWING) == OK, "saved the drawing")
	_colors()
	var shapes := _trace()
	_mapping(shapes)
	_crop_and_paper()
	_fast_on_busy_pictures()
	_painter()
	await _room_view()

func _drawing() -> Image:
	var img := Image.create(240, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	img.fill_rect(Rect2i(20, 20, 200, 80), Color.WHITE)
	img.fill_rect(Rect2i(20, 20, 3, 80), Color(0.5, 0.5, 0.5))
	img.fill_rect(Rect2i(100, 40, 40, 20), Color.BLACK)
	img.fill_rect(Rect2i(40, 70, 50, 4), ORANGE)
	for y in range(36, 65):
		for x in range(166, 195):
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(180, 50)) <= 12.0:
				img.set_pixel(x, y, GREEN)
	img.fill_rect(Rect2i(150, 80, 20, 15), BLUE)
	return img

func _tracer() -> MDSDrawingTracer:
	var t := MDSDrawingTracer.new()
	check(t.load_image(DRAWING) == OK, "the drawing loads from a file")
	t.target = Rect2(0, 0, 2400, 1200)
	return t

func _layer_of(t: MDSDrawingTracer, c: Color) -> int:
	for e in t.colors:
		if MDSDrawingTracer._distance(e.color, c) < 0.15:
			return e.layer
	return -1

func _colors() -> void:
	var t := _tracer()
	check(t.colors.size() == 5, "five colors: the grey band is a soft edge, not a color (%s)" % [t.colors.map(func(c: Dictionary) -> String: return c.color.to_html(false))])
	check(_layer_of(t, Color.BLACK) == MDSDrawingTracer.Layer.TERRAIN, "black is terrain")
	check(_layer_of(t, Color.WHITE) == MDSDrawingTracer.Layer.IGNORE, "white is paper")
	check(_layer_of(t, ORANGE) == MDSDrawingTracer.Layer.PLATFORM, "orange is a platform")
	check(_layer_of(t, GREEN) == MDSDrawingTracer.Layer.BACKGROUND, "green is background")
	check(_layer_of(t, BLUE) == MDSDrawingTracer.Layer.FOREGROUND, "blue is foreground")
	check(t.colors[0].share >= t.colors[1].share and absf(t.colors.reduce(func(a: float, c: Dictionary) -> float: return a + c.share, 0.0) - 1.0) < 0.001, "most used first, shares adding up to 1")
	check(MDSDrawingTracer.default_layer(Color("#6b4a2b")) == MDSDrawingTracer.Layer.TERRAIN and MDSDrawingTracer.default_layer(Color("#f2d33a")) == MDSDrawingTracer.Layer.PLATFORM and MDSDrawingTracer.default_layer(Color("#9b59d0")) == MDSDrawingTracer.Layer.FOREGROUND, "brown is terrain, yellow a platform, purple foreground")
	var preview := t.layer_preview()
	check(preview.get_size() == Vector2i(240, 120) and preview.get_pixel(60, 60).a == 0.0 and preview.get_pixel(5, 5).is_equal_approx(MDSDrawingTracer.LAYER_COLORS[MDSDrawingTracer.Layer.TERRAIN]), "the layer preview shows paper clear and rock in the terrain color")
	var big := MDSDrawingTracer.new()
	big.set_image(Image.create(2048, 1024, false, Image.FORMAT_RGBA8))
	check(big.image.get_size() == Vector2i(512, 256), "big drawings are traced at the resolution (%s)" % big.image.get_size())

func _inside(shapes: Array, layer: int, p: Vector2) -> bool:
	for s in shapes:
		if s.layer == layer and Geometry2D.is_point_in_polygon(p, MDSFreeform.outline_of(s.points, s.smooth)):
			return true
	return false

func _trace() -> Array:
	var t := _tracer()
	var shapes := t.trace()
	var T := MDSDrawingTracer.Layer.TERRAIN
	check(_inside(shapes, T, Vector2(100, 600)) and _inside(shapes, T, Vector2(1000, 100)) and _inside(shapes, T, Vector2(2300, 600)), "the rock round the cave is terrain")
	check(not _inside(shapes, T, Vector2(600, 400)) and not _inside(shapes, T, Vector2(1800, 900)), "the cave stays open: a hole in the rock")
	check(_inside(shapes, T, Vector2(1200, 500)), "the island floating in the cave is terrain too")
	check(_inside(shapes, MDSDrawingTracer.Layer.PLATFORM, Vector2(650, 720)), "the orange ledge is a platform")
	check(_inside(shapes, MDSDrawingTracer.Layer.BACKGROUND, Vector2(1800, 500)), "the bush is background")
	check(_inside(shapes, MDSDrawingTracer.Layer.FOREGROUND, Vector2(1600, 875)), "the blob is foreground")
	check(not _inside(shapes, T, Vector2(650, 720)) and not _inside(shapes, T, Vector2(1800, 500)), "other colors are not rock")
	var simple := shapes.all(func(s: Dictionary) -> bool: return MDSGeometry.is_simple(MDSFreeform.outline_of(s.points, s.smooth)))
	check(simple, "every outline can be filled and collided with")
	# The rock is cut in two around the cave: the halves meet along the cut without a notch.
	var cut: Array = shapes.filter(func(s: Dictionary) -> bool: return s.layer == T and not (s.seams as PackedFloat32Array).is_empty())
	check(cut.size() == 2 and cut[0].seams == cut[1].seams and cut[0].seams.size() == 1, "the rock's two halves share one seam (%s)" % [cut.map(func(s: Dictionary) -> PackedFloat32Array: return s.seams)])
	if cut.size() == 2:
		var x: float = cut[0].seams[0]
		check(x > 1150.0 and x < 1250.0, "down the middle of the cave (%.0f)" % x)
		var seamless := true
		for p in [Vector2(x - 2, 195), Vector2(x + 2, 195), Vector2(x - 2, 1005), Vector2(x + 2, 1005), Vector2(x - 1, 100), Vector2(x + 1, 100)]:
			seamless = seamless and _inside(shapes, T, p)
		check(seamless, "right up to the cave's ceiling and floor")
	check(shapes.filter(func(s: Dictionary) -> bool: return s.layer == T and (s.seams as PackedFloat32Array).is_empty()).size() == 1, "the island has no seam")
	var runs := MDSFreeform.outline_runs(rect_points(Rect2(0, 0, 100, 50)), PackedFloat32Array([100.0]))
	check(runs.size() == 1 and not runs[0][1] and (runs[0][0] as PackedVector2Array).size() == 4, "an outline leaves out its seam (%s)" % [runs])
	check(MDSFreeform.outline_runs(rect_points(Rect2(0, 0, 100, 50)), PackedFloat32Array())[0][1], "and is closed without one")
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for s in shapes:
		var b := MDSGeometry.bounds(s.points)
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	check(lo.x <= -t.bleed + 1.0 and lo.y <= -t.bleed + 1.0 and hi.x >= 2400 + t.bleed - 1.0 and hi.y >= 1200 + t.bleed - 1.0, "rock at the drawing's edge runs on past the room (%s, %s)" % [lo, hi])
	# Specks are dropped; turning a color off drops its shapes.
	t.min_size = 300.0
	check(not t.trace().any(func(s: Dictionary) -> bool: return s.layer == MDSDrawingTracer.Layer.BACKGROUND), "a smallest shape bigger than the bush drops it")
	t.min_size = 24.0
	for c in t.colors:
		if c.layer == MDSDrawingTracer.Layer.FOREGROUND:
			c.layer = MDSDrawingTracer.Layer.IGNORE
	check(not t.trace().any(func(s: Dictionary) -> bool: return s.layer == MDSDrawingTracer.Layer.FOREGROUND), "a color set to Nothing makes no shapes")
	return shapes

func _mapping(_shapes: Array) -> void:
	var t := _tracer()
	t.target = Rect2(0, 0, 2400, 2400)
	t.keep_aspect = true
	check(t.image_to_target() == Transform2D(Vector2(10, 0), Vector2(0, 10), Vector2(0, 600)), "keeping proportions centres the drawing (%s)" % t.image_to_target())
	t.bleed = 0.0
	var ys: Array = []
	for s in t.trace():
		var b := MDSGeometry.bounds(s.points)
		ys.append(b.position.y)
		ys.append(b.end.y)
	check(ys.min() >= 599.0 and ys.max() <= 1801.0, "its shapes stay in the drawing's band (%.0f..%.0f)" % [ys.min(), ys.max()])

## Paper around the drawing is cut off, so what is drawn fills the room; without white or
## transparent paper, the color filling the border is the paper.
func _crop_and_paper() -> void:
	var img := Image.create(240, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.fill_rect(Rect2i(60, 30, 120, 60), Color.BLACK)
	var t := MDSDrawingTracer.new()
	t.set_image(img)
	t.target = Rect2(0, 0, 2400, 1200)
	t.bleed = 0.0
	check(t.content_rect() == Rect2i(60, 30, 120, 60), "the drawn part is found (%s)" % t.content_rect())
	var b := _bounds_of(t.trace())
	check(b.position.distance_to(Vector2.ZERO) < 30.0 and b.end.distance_to(Vector2(2400, 1200)) < 30.0, "cropped, it fills the room's width and height (%s)" % b)
	t.crop = false
	b = _bounds_of(t.trace())
	check(b.position.distance_to(Vector2(600, 300)) < 30.0 and b.end.distance_to(Vector2(1800, 900)) < 30.0, "uncropped, the paper around it stays (%s)" % b)
	# A drawing on a dark background, no white anywhere.
	var dark := Image.create(240, 120, false, Image.FORMAT_RGBA8)
	dark.fill(Color("#10141c"))
	dark.fill_rect(Rect2i(30, 70, 100, 12), ORANGE)
	dark.fill_rect(Rect2i(150, 20, 60, 60), GREEN)
	var d := MDSDrawingTracer.new()
	d.set_image(dark)
	check(_layer_of(d, Color("#10141c")) == MDSDrawingTracer.Layer.IGNORE, "a dark background filling the border is the paper")
	check(_layer_of(d, ORANGE) == MDSDrawingTracer.Layer.PLATFORM and _layer_of(d, GREEN) == MDSDrawingTracer.Layer.BACKGROUND, "and the shapes on it keep their layers")

func _bounds_of(shapes: Array) -> Rect2:
	var b := Rect2()
	for i in shapes.size():
		var r := MDSGeometry.bounds(shapes[i].points)
		b = r if i == 0 else b.merge(r)
	return b

## A busy picture (hundreds of specks) traces quickly: specks are dropped before anything
## compares outlines.
func _fast_on_busy_pictures() -> void:
	var img := Image.create(512, 288, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.fill_rect(Rect2i(40, 40, 432, 208), Color.BLACK)
	img.fill_rect(Rect2i(80, 80, 352, 128), Color.WHITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 3000:
		img.set_pixel(rng.randi_range(0, 511), rng.randi_range(0, 287), Color.BLACK if rng.randf() < 0.5 else Color.WHITE)
	var t := MDSDrawingTracer.new()
	t.set_image(img)
	t.target = Rect2(0, 0, 3456, 1944)
	var t0 := Time.get_ticks_msec()
	var shapes := t.trace()
	var took := Time.get_ticks_msec() - t0
	check(took < 1500, "a picture with 3000 specks traces in %d ms" % took)
	check(shapes.all(func(s: Dictionary) -> bool: var bb := MDSGeometry.bounds(s.points); return maxf(bb.size.x, bb.size.y) >= t.min_size), "nothing smaller than the smallest shape is kept (%d shapes)" % shapes.size())
	t.min_size = 60.0
	var big := shapes.size()
	shapes = t.trace()
	check(shapes.filter(func(s: Dictionary) -> bool: return s.layer == MDSDrawingTracer.Layer.TERRAIN).size() <= 4 and shapes.size() < big, "a bigger smallest shape drops the specks, the rock ring stays (%d shapes)" % shapes.size())
	check(_inside(shapes, MDSDrawingTracer.Layer.TERRAIN, Vector2(400, 900)) and not _inside(shapes, MDSDrawingTracer.Layer.TERRAIN, Vector2(1728, 972)), "with its cave open")

func _painter() -> void:
	var root := Node2D.new()
	root.name = "TraceRoom"
	save_scene(root, ROOM)
	root.free()
	var painter := MDSRoomPainter.open(ROOM)
	var t := _tracer()
	var rock := MDSFreeformStyle.new()
	rock.display_name = "Test rock"
	var bush := MDSFreeformStyle.new()
	bush.display_name = "Test bush"
	t.styles[MDSDrawingTracer.Layer.TERRAIN] = rock
	for c in t.colors:
		if c.layer == MDSDrawingTracer.Layer.BACKGROUND:
			c.style = bush
	painter.checkpoint()
	var r := t.apply(painter)
	check(r.terrain >= 3 and r.platform == 1 and r.background == 1 and r.foreground == 1 and r.removed == 0, "the trace makes rock, a ledge, a bush and a blob (%s)" % r)
	var terrain := painter.items("Freeform").filter(func(f: MDSFreeform) -> bool: return f.is_terrain())
	var ledges := painter.items("Freeform").filter(func(f: MDSFreeform) -> bool: return f.is_platform())
	check(terrain.size() == r.terrain and terrain.all(func(f: MDSFreeform) -> bool: return f.style == rock and f.solid), "rock is solid, in the layer's style")
	check(ledges.size() == 1 and ledges[0].is_one_way() and ledges[0].style == rock, "the ledge is a one-way platform (rock style: no platform style given)")
	var back: Array = painter.items("FreeformBack")
	check(back.size() == 1 and back[0].style == bush and not back[0].is_collider(), "the bush is a background shape of its color's style, not solid")
	check(painter.items("FreeformFront").size() == 1 and not painter.items("FreeformFront")[0].is_collider(), "the blob is a foreground shape")
	var all: Array = painter.items("Freeform") + back + painter.items("FreeformFront")
	check(all.all(func(f: Node) -> bool: return f.has_meta(MDSDrawingTracer.META)), "traced shapes are marked")
	check(String(terrain[0].name).begins_with("TracedTerrain"), "and named for their layer (%s)" % terrain[0].name)
	var halves := terrain.filter(func(f: MDSFreeform) -> bool: return f.has_meta(&"mds_seams"))
	check(halves.size() == 2, "the rock's halves know their seam")
	if halves.size() == 2:
		halves[0].rebuild()
		var open_lines: Array = halves[0].get_children(true).filter(func(c: Node) -> bool: return c is Line2D and not c.closed and c.width == rock.outline_width)
		check(open_lines.size() >= 1, "so their outline stops at it")
	# A shape of the room's own is kept when tracing again.
	var own := painter.add_freeform(rect_points(Rect2(10, 10, 50, 50)), rock)
	var count := painter.items("Freeform").size()
	painter.checkpoint()
	var again := t.apply(painter)
	check(again.removed == r.terrain + r.platform + r.background + r.foreground, "tracing again replaces the last trace (%d removed)" % again.removed)
	check(painter.items("Freeform").size() == count and is_instance_valid(own) and own.get_parent() != null, "and keeps the room's own shapes")
	painter.undo()
	painter.undo()
	check(painter.items("Freeform").is_empty() and painter.items("FreeformBack").is_empty(), "undo takes the trace back out")
	painter.redo()
	painter.redo()
	check(painter.save() == OK, "saved")
	painter.free_instance()
	load_fresh(ROOM)
	var saved := MDSRoomPainter.open(ROOM)
	check(saved.items("Freeform").size() == count and saved.items("Freeform")[1].has_meta(MDSDrawingTracer.META), "the traced shapes are in the scene, marked")
	saved.free_instance()

# --- The Room view ----------------------------------------------------------------------------------

func _room_view() -> void:
	var root := Node2D.new()
	root.name = "TraceRoom"
	save_scene(root, ROOM)
	root.free()
	load_fresh(ROOM)
	var world := MDSWorld.new()
	world.path = TMP + "/trace.idpworld.json"
	world.add_room("Cave", Rect2(0, 0, 2400, 1200))
	world.set_room_scene("Cave", ROOM)
	var view := MDSRoomView.new()
	view.size = Vector2(900, 600)
	add_child(view)
	await get_tree().process_frame
	check(view.open_room(world, "Cave").is_empty(), "the Room view opens the room")
	var messages: Array = []
	view.status_message.connect(func(t: String) -> void: messages.append(t))
	# The Effects tool: its list instead of the brush controls.
	view.set_tool(MDSRoomCanvas.Tool.EFFECT)
	for i in 3:
		await get_tree().process_frame
	check(view._effect_box.visible and not view.fill_opt.get_parent().visible and not view.brush_spin.visible, "the Effects tool shows its list, not the brushes")
	check(view.effect_list.item_count == MDSEnvironment.EFFECTS.size() + 1 and view.effect_list.get_item_icon(1) != null, "every effect is listed with its icon, after No effect")
	check(str(view.effect_list.get_item_metadata(0)).is_empty() and view.effect_list._get_drag_data(view.effect_list.get_item_rect(0).get_center()) == null, "No effect places nothing and can't be dragged")
	var drag: Variant = view.effect_list._get_drag_data(view.effect_list.get_item_rect(2).get_center())
	check(drag is Dictionary and drag.type == MDSRoomCanvas.DRAG_EFFECT and drag.effect == MDSEnvironment.EFFECTS.keys()[1], "dragging an entry carries its effect (%s)" % [drag])
	view.set_tool(MDSRoomCanvas.Tool.TERRAIN)
	view.canvas._drop_data(Vector2(300, 300), drag)
	check(view.canvas.tool == MDSRoomCanvas.Tool.EFFECT and view.painter.effects().size() == 1, "dropping it switches to the Effects tool and places it")
	view.set_tool(MDSRoomCanvas.Tool.FREEFORM)
	check(not view._effect_box.visible and view.fill_opt.get_parent().visible, "other tools hide the list")
	# Trace drawing.
	view.open_trace_dialog(DRAWING)
	var dialog := view._trace_dialog
	check(dialog.tracer.colors.size() == 5, "the dialog reads the drawing's colors")
	var styled := dialog.tracer.colors.all(func(c: Dictionary) -> bool: return (c.layer == MDSDrawingTracer.Layer.IGNORE) == (c.get("style") == null))
	check(styled and dialog._rows.get_child_count() == 4 * 5, "each color has a layer and a style picker")
	dialog.preview()
	var traced := func() -> int: return view.painter.items("Freeform").filter(func(f: Node) -> bool: return f.has_meta(MDSDrawingTracer.META)).size()
	check(traced.call() >= 4, "Preview traces it into the room (%d)" % traced.call())
	dialog._take_back()
	check(traced.call() == 0, "Cancel takes it back out")
	dialog._on_confirmed()
	check(traced.call() >= 4 and str(world.get_room_value("Cave", "drawing", "")) == DRAWING, "Trace keeps it and remembers the drawing for the room")
	check(messages.any(func(m: String) -> bool: return m.begins_with("Traced the drawing into Cave")), "and says what it made (%s)" % [messages.back()])
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame
