extends "res://tests/test_case.gd"
## Editing the world map (MDSWorldCanvas) with several rooms: Extend (E) with rooms selected
## shares the box drawn out among them, each extending with the part nearest it, in one undo
## step; Merge (Ctrl+M, the tool panel's Merge rooms) takes the rooms selected, or one room and
## the rooms it touches, and refuses rooms that touch none of the others. Underneath: rooms
## sliding against others to the pixel (MDSAreaTools.slide_rects), passages around what is in
## the way (MDSAreaTools.passage), the overlap check of the Issues tab on a big map, and a map
## of hundreds of rooms that pans without being drawn again.

var world: MDSWorld
var canvas: MDSWorldCanvas

func _run() -> void:
	_extend()
	_merge()
	_slide()
	_passage()
	_validator()
	await _panning()

func _canvas(w: MDSWorld) -> MDSWorldCanvas:
	if canvas:
		canvas.queue_free()
	world = w
	canvas = MDSWorldCanvas.new()
	canvas.size = Vector2(900, 600)
	add_child(canvas)
	canvas.set_data(world, null, {})
	canvas.zoom = 0.1
	canvas.pan = Vector2(20, 20)
	canvas._after_view_change()
	return canvas

func _press(at: Vector2, pressed: bool, ctrl := false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.ctrl_pressed = ctrl
	mb.position = at
	canvas._gui_input(mb)

func _move(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(mm)

func _drag(from: Vector2, to: Vector2) -> void:
	_press(from, true)
	for k in range(1, 5):
		_move(from.lerp(to, k / 4.0))
	_press(to, false)

func _key(code: Key, ctrl := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	canvas._gui_input(k)

func _extend() -> void:
	var w := MDSWorld.new()
	w.add_room("A", Rect2(0, 0, 576, 320))
	w.add_room("B", Rect2(576, 0, 576, 320))
	w.add_room("C", Rect2(1152, 0, 576, 320))
	w.add_room("Below", Rect2(1152, 320, 576, 320))
	# A box under A and B (and C, whose part Below has already): each takes the part under it.
	var parts := MDSAreaTools.split_extension(w, ["A", "B"] as Array[String], Rect2(0, 320, 1728, 320))
	check(parts.size() == 2 and parts.has("A") and parts.has("B"), "a box under two rooms is shared out between them (%s)" % [parts.keys()])
	var a_box := Rect2()
	for r: Rect2 in parts.get("A", []):
		a_box = r if not a_box.has_area() else a_box.merge(r)
	var b_box := Rect2()
	for r: Rect2 in parts.get("B", []):
		b_box = r if not b_box.has_area() else b_box.merge(r)
	check(a_box == Rect2(0, 320, 576, 320) and b_box == Rect2(576, 320, 576, 320), "each the part nearest it, under it (%s, %s)" % [a_box, b_box])
	check(b_box.end.x <= 1152.0, "and what another room covers is left out")
	# With the Extend tool on the map: one undo step.
	_canvas(w)
	canvas.select_rooms(["A", "B"], "A")
	canvas.set_tool(MDSWorldCanvas.Tool.RECT)
	var before_a := w.get_world_rects("A").size()
	_drag(canvas.world_to_screen(Vector2(16, 336)), canvas.world_to_screen(Vector2(1136, 600)))
	check(w.get_world_rects("A").size() == before_a + 1 and w.get_world_rects("B").size() == 2, "the Extend tool with two rooms selected extends both")
	check(w.get_room_bounds("A").end.y > 320.0 and w.get_room_bounds("B").end.y > 320.0, "downwards, each under itself")
	w.undo()
	check(w.get_world_rects("A").size() == before_a and w.get_world_rects("B").size() == 1, "one Ctrl+Z takes both back")
	# Ctrl+click in the Extend tool picks the rooms to extend.
	canvas.select_rooms(["A"], "A")
	var c_at := canvas.world_to_screen(Vector2(1400, 100))
	_press(c_at, true, true)
	_press(c_at, false, true)
	check(canvas.get_selected_rooms().size() == 2 and canvas.get_selected_rooms().has("C"), "Ctrl+click adds a room to extend (%s)" % [canvas.get_selected_rooms()])

func _merge() -> void:
	var w := MDSWorld.new()
	w.add_area("Halls", Color.RED)
	w.add_room("H1", Rect2(0, 0, 576, 320), 0, "Halls")
	w.add_room("H2", Rect2(576, 0, 576, 320), 0, "Halls")
	w.add_room("H3", Rect2(0, 320, 576, 320), 0, "Halls")
	w.add_room("Other", Rect2(576, 320, 576, 320))
	w.add_room("Away", Rect2(4000, 0, 576, 320), 0, "Halls")
	# Only a corner shared: not touching.
	w.add_room("Corner", Rect2(1152, 320 + 320, 288, 162))
	check(MDSAreaTools.rooms_touch(w, "H1", "H2") and MDSAreaTools.rooms_touch(w, "H1", "H3"), "rooms side by side touch")
	check(not MDSAreaTools.rooms_touch(w, "H1", "Other"), "rooms meeting at a corner don't")
	var around := MDSAreaTools.touching(w, "H1", 0)
	check(around.size() == 2 and around.has("H2") and around.has("H3"), "the rooms one touches (%s)" % [around])
	var apart := MDSAreaTools.apart_from(w, ["H1", "H2", "Away"] as Array[String])
	check(apart.size() == 1 and apart[0] == "Away", "a room touching none of the others is named (%s)" % [apart])
	_canvas(w)
	var asked: Array = []
	canvas.merge_requested.connect(func(ids: Array[String], keep: String) -> void: asked.append([ids, keep]))
	# One room: it and the rooms of its area it touches.
	canvas.select_rooms(["H1"], "H1")
	_key(KEY_M, true)
	check(asked.size() == 1 and (asked[0][0] as Array).size() == 3 and not (asked[0][0] as Array).has("Other") and asked[0][1] == "H1", "Ctrl+M with one room: it and the rooms of its area it touches (%s)" % [asked])
	# Several rooms selected: those.
	canvas.select_rooms(["H2", "Other"], "Other")
	canvas.merge_selection()
	check(asked.size() == 2 and asked[1][0] == ["H2", "Other"] and asked[1][1] == "Other", "with rooms selected, those, the one picked first kept")
	# A room alone touching nothing: nothing asked.
	canvas.select_rooms(["Away"], "Away")
	canvas.merge_selection()
	check(asked.size() == 2, "a room touching no other: nothing to merge")
	# Merged, they are one room.
	var r := w.merge_rooms(asked[0][0], "H1")
	check(r.get("id", "") == "H1" and w.get_room_ids().size() == 4 and w.get_room_bounds("H1") == Rect2(0, 0, 1152, 640), "merged: one room of the three (%s)" % w.get_room_bounds("H1"))

func _slide() -> void:
	var own: Array[Rect2] = [Rect2(0, 0, 100, 100)]
	var wall: Array[Rect2] = [Rect2(300, -500, 50, 1000)]
	var at := MDSAreaTools.slide_rects(own, wall, Vector2.ZERO, Vector2(500, 0))
	check(at == Vector2(200, 0), "moving into a room it stops flush against it (%s)" % at)
	at = MDSAreaTools.slide_rects(own, wall, Vector2.ZERO, Vector2(500, 137))
	check(at == Vector2(200, 137), "and slides along it, to the pixel (%s)" % at)
	check(MDSAreaTools.rects_fit(own, wall, Vector2(200, 0)) and not MDSAreaTools.rects_fit(own, wall, Vector2(201, 0)), "touching fits, over it doesn't")
	# Already over it: moving out isn't stopped.
	at = MDSAreaTools.slide_rects(own, wall, Vector2(260, 0), Vector2(400, 0))
	check(at == Vector2(400, 0), "a room over another isn't held by it")

func _passage() -> void:
	var w := MDSWorld.new()
	var s := w.get_paint_cell()
	w.add_room("L", Rect2(Vector2(0, 0), s * Vector2(2, 2)))
	w.add_room("R", Rect2(Vector2(s.x * 6, 0), s * Vector2(2, 2)))
	# A wall between them, open below.
	w.add_room("Wall", Rect2(Vector2(s.x * 3, -s.y * 3), s * Vector2(1, 5)))
	var own := MDSAreaTools.cells_of(w, ["L"] as Array[String])
	var others := MDSAreaTools.cells_of(w, ["R"] as Array[String])
	var path := MDSAreaTools.passage(w, own, others, 0, 12)
	var taken := MDSAreaTools.occupied(w, 0)
	var free := true
	for k in range(1, path.size() - 1):
		free = free and not taken.has(path[k])
	check(path.size() >= 3 and own.has(path[0]) and others.has(path[-1]) and free, "a passage goes round what is in the way (%s)" % [path])
	check(MDSAreaTools.passage(w, own, others, 0, 2).is_empty(), "no passage longer than allowed")

func _validator() -> void:
	var w := MDSWorld.new()
	for i in 300:
		w.add_room("R%03d" % i, Rect2(Vector2((i % 30) * 600, (i / 30) * 400), Vector2(576, 320)))
	w.add_room("Over", Rect2(Vector2(300, 100), Vector2(576, 320)))
	var an := MDSAnalysis.new(MDSGraph.from_world(w, {}), w, {}).run()
	var t := Time.get_ticks_msec()
	var issues := MDSWorldValidator.run(w, an, {})
	var ms := Time.get_ticks_msec() - t
	var overlaps := issues.filter(func(i: Variant) -> bool: return str(i.message).contains("overlaps"))
	var want := 0
	for id in w.get_room_ids():
		if id != "Over" and w.get_room_bounds(id).intersection(w.get_room_bounds("Over")).get_area() > 1.0:
			want += 1
	check(overlaps.size() == want and want == 4, "the rooms a room overlaps are found, every one (%d of %d)" % [overlaps.size(), want])
	check(ms < 1500, "on a map of 300 rooms, quickly (%d ms)" % ms)

func _panning() -> void:
	var w := MDSWorld.new()
	for i in 200:
		w.add_room("R%03d" % i, Rect2(Vector2((i % 20) * 600, (i / 20) * 400), Vector2(576, 320)))
	_canvas(w)
	canvas.redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	check(canvas._layers_zoom == canvas.zoom, "the rooms are drawn at the zoom")
	canvas.center_on(Vector2(3000, 1000))
	check(canvas._rooms_layer.position.is_equal_approx(canvas.pan - canvas._rooms_pan) and canvas._rooms_layer.position != Vector2.ZERO, "panned, the rooms drawn move with the view, not drawn again")
	check(canvas._marks_layer.position.is_equal_approx(canvas._rooms_layer.position), "and so do their gates and names")
	canvas.set_zoom(canvas.zoom * 1.5)
	await get_tree().process_frame
	await get_tree().process_frame
	check(canvas._rooms_layer.position == Vector2.ZERO and is_equal_approx(canvas._layers_zoom, canvas.zoom), "zoomed, they are drawn again")
	canvas.queue_free()
	canvas = null
	await get_tree().process_frame
