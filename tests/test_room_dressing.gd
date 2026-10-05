extends "res://tests/test_case.gd"
## Brief 19: Fit props to floor and Declutter (IDPRoomDressing), undoable in the Room view's
## painter and saved; the "objects overlap" scan issue; the runtime IDPRoomDresser.
##
## The room (1152 x 648): a floor at y 560, a one-way ledge, a save point floating at y 300
## (its sprite has a transparent margin under the art), a bench sunk into the floor, a crate
## and a barrel standing in each other, a vase in front of a door, a guard, a hanging lantern.

const ROOM := TMP + "/brief19_room.tscn"
const SMALL := TMP + "/brief19_small.tscn"
const RECTS: Array[Rect2] = [Rect2(0, 0, 1152, 648)]
const FLOOR_Y := 560.0

var host: SubViewport

func _run() -> void:
	host = SubViewport.new()
	host.disable_3d = true
	host.size = Vector2i(4, 4)
	add_child(host)
	_save_room()
	_save_small()
	_scan()
	await _in_the_room_view()
	await _runtime()
	_nowhere_to_go()

func node(painter: IDPRoomPainter, name: String) -> Node2D:
	return painter.root.get_node(name)

func rect(painter: IDPRoomPainter, name: String) -> Rect2:
	return IDPRoomDressing.rect_of(node(painter, name), painter.root, painter)

# --- The scan -------------------------------------------------------------------------------------

func _scan() -> void:
	var scanner := IDPSceneScanner.new()
	var meta := scanner.analyze_scene(ROOM, false)
	var pairs: Array = meta.overlaps.map(func(o: Dictionary) -> String: return "%s+%s" % [o.a, o.b])
	check(pairs.has("Crate+Barrel") or pairs.has("Barrel+Crate"), "the scan finds the crate and barrel standing in each other (%s)" % [pairs])
	check(pairs.any(func(p: String) -> bool: return p.contains("Vase") and p.contains("Door")), "and the vase in front of the door")
	check(not pairs.any(func(p: String) -> bool: return p.contains("Floor")), "terrain bodies are not objects")
	var issues: Array = []
	IDPValidator.add_overlap_issue(issues, "Hall", meta.overlaps[0], "Hall")
	check(issues[0].category == IDPValidator.CATEGORY_GEOMETRY and str(issues[0].message).contains("objects overlap"), "the Issues tab reports it (%s)" % issues[0].message)

# --- In the Room view's painter -------------------------------------------------------------------

func _in_the_room_view() -> void:
	var painter := IDPRoomPainter.open(ROOM)
	var save_before := painter.scene_position(node(painter, "SavePoint"))
	var guard_before := rect(painter, "Guard")
	var lantern_before := rect(painter, "Lantern")
	check(rect(painter, "SavePoint").end.y < 400.0, "sanity: the save point floats (%s)" % rect(painter, "SavePoint"))
	# Fit props to floor.
	var c := IDPRoomDressing.ground_check(host, painter.root, painter, RECTS)
	var fit := IDPRoomDressing.fit_to_floor(painter.root, c, painter)
	c.free_proxy()
	painter.checkpoint()
	IDPRoomDressing.apply(fit, painter)
	var names: Array = fit.map(func(e: Dictionary) -> String: return String(e.node.name))
	check(names.has("SavePoint") and names.has("Bench"), "Fit props to floor moves the save point and the bench (%s)" % [names])
	check_near(rect(painter, "SavePoint").end.y, FLOOR_Y, 1.0, "the save point's art (not its transparent margin) stands on the floor")
	check_near(rect(painter, "Bench").end.y, FLOOR_Y, 1.0, "the sunk bench is lifted onto it")
	check(rect(painter, "Lantern") == lantern_before and rect(painter, "Guard") == guard_before, "hanging things and enemies aren't dropped")
	check(node(painter, "SavePoint").position == save_before, "nothing in the scene changes before saving (scene edits)")
	# Declutter.
	c = IDPRoomDressing.ground_check(host, painter.root, painter, RECTS)
	var sep := IDPRoomDressing.declutter(painter.root, c, painter)
	c.free_proxy()
	painter.checkpoint()
	IDPRoomDressing.apply(sep, painter)
	var crate := rect(painter, "Crate")
	var barrel := rect(painter, "Barrel")
	check(not crate.grow(IDPRoomDressing.GAP - 0.5).intersects(barrel), "Declutter separates the crate and the barrel by at least the gap (%s, %s)" % [crate, barrel])
	check_near(crate.end.y, FLOOR_Y, 1.0, "both still stand on the floor")
	check_near(barrel.end.y, FLOOR_Y, 1.0, "both still stand on the floor (barrel)")
	check(not rect(painter, "Vase").intersects(rect(painter, "Door")), "the vase steps away from the door")
	check(painter.scene_position(node(painter, "Door")) == node(painter, "Door").position and rect(painter, "Guard") == guard_before, "doors and enemies never move")
	check(IDPRoomDressing.overlaps(painter.root, painter).is_empty(), "nothing overlaps any more (%s)" % [IDPRoomDressing.overlaps(painter.root, painter)])
	# Undo and redo.
	painter.undo()
	check(_hits(rect(painter, "Crate"), rect(painter, "Barrel")), "undo puts the crate and barrel back")
	painter.undo()
	check(rect(painter, "SavePoint").end.y < 400.0, "a second undo floats the save point again")
	painter.redo()
	painter.redo()
	check_near(rect(painter, "SavePoint").end.y, FLOOR_Y, 1.0, "redo stands it again")
	check(painter.save() == OK, "the room saves")
	var saved := (load_fresh(ROOM) as PackedScene).instantiate()
	check_near(IDPRoomObjects.visual_rect(saved.get_node("SavePoint"), saved, true).end.y, FLOOR_Y, 1.0, "the saved scene has the save point on the floor")
	check(not _hits(IDPRoomObjects.visual_rect(saved.get_node("Crate"), saved, true), IDPRoomObjects.visual_rect(saved.get_node("Barrel"), saved, true)), "and the props apart")
	saved.free()
	painter.free_instance()
	await get_tree().process_frame

static func _hits(a: Rect2, b: Rect2) -> bool:
	return a.intersection(b).get_area() > 1.0

# --- At runtime -----------------------------------------------------------------------------------

func _runtime() -> void:
	_save_room() # undressed again
	var room := (load_fresh(ROOM) as PackedScene).instantiate() as Node2D
	room.position = Vector2(2304, 648) # rooms sit at their world position
	var dresser := IDPRoomDresser.new()
	room.add_child(dresser)
	var done: Array = []
	dresser.dressed.connect(func(_r: Node, e: Array) -> void: done.append(e))
	add_child(room)
	await get_tree().process_frame
	await get_tree().process_frame
	check(done.size() == 1 and not done[0].is_empty(), "IDPRoomDresser dresses the room it is in")
	check_near(IDPRoomObjects.visual_rect(room.get_node("SavePoint"), room, true).end.y, FLOOR_Y, 1.0, "standing the save point on the floor")
	check(not _hits(IDPRoomObjects.visual_rect(room.get_node("Crate"), room, true), IDPRoomObjects.visual_rect(room.get_node("Barrel"), room, true)), "and separating the props")
	check(get_tree().root.find_children("*", "SubViewport", false, false).is_empty(), "leaving nothing behind")
	room.queue_free()
	await get_tree().process_frame

# --- Nowhere to go --------------------------------------------------------------------------------

func _nowhere_to_go() -> void:
	var painter := IDPRoomPainter.open(SMALL)
	var rects: Array[Rect2] = [Rect2(0, 0, 200, 648)]
	var c := IDPRoomDressing.ground_check(host, painter.root, painter, rects)
	var edits := IDPRoomDressing.declutter(painter.root, c, painter)
	c.free_proxy()
	var by_name: Dictionary = {}
	for e in edits:
		by_name[String(e.node.name)] = e.kind
	check(by_name.get("Pot") == "remove", "a decoration with nowhere clear to go is removed (%s)" % by_name)
	check(not by_name.has("Key"), "a pickup (in a group) is never removed")
	painter.free_instance()

# --- Rooms ----------------------------------------------------------------------------------------

func _poly(name: String, r: Rect2, color := Color(0.6, 0.5, 0.4)) -> Polygon2D:
	var p := Polygon2D.new()
	p.name = name
	p.color = color
	p.polygon = rect_points(r)
	return p

func _floor(root: Node2D, width: float) -> void:
	var body := StaticBody2D.new()
	body.name = "Floor"
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, 648 - FLOOR_Y)
	cs.shape = shape
	cs.position = Vector2(width / 2.0, (FLOOR_Y + 648) / 2.0)
	body.add_child(cs)
	body.add_child(_poly("Art", Rect2(0, FLOOR_Y, width, 648 - FLOOR_Y)))
	root.add_child(body)

func _save_room() -> void:
	var root := Node2D.new()
	root.name = "Hall"
	_floor(root, 1152)
	var ledge := StaticBody2D.new()
	ledge.name = "Ledge"
	var lc := CollisionShape2D.new()
	var ls := RectangleShape2D.new()
	ls.size = Vector2(200, 16)
	lc.shape = ls
	lc.position = Vector2(800, 408)
	lc.one_way_collision = true
	ledge.add_child(lc)
	root.add_child(ledge)
	# A save point floating, its sprite with 16 px of transparent margin under the art.
	var save := Node2D.new()
	save.name = "SavePoint"
	save.add_to_group(&"save_point", true)
	save.position = Vector2(150, 250)
	var img := Image.create(48, 80, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(4, 0, 40, 64), Color(0.9, 0.8, 0.3))
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = ImageTexture.create_from_image(img)
	save.add_child(spr)
	root.add_child(save)
	# A bench sunk 40 px into the floor.
	root.add_child(_poly("Bench", Rect2(450, 520, 80, 80), Color(0.5, 0.35, 0.2)))
	# A crate and a barrel standing in each other.
	root.add_child(_poly("Crate", Rect2(300, 500, 60, 60)))
	root.add_child(_poly("Barrel", Rect2(330, 510, 50, 50), Color(0.45, 0.3, 0.2)))
	# A door and a vase in front of it.
	root.add_child(_poly("Door", Rect2(1000, 440, 70, 120), Color(0.3, 0.25, 0.2)))
	root.add_child(_poly("Vase", Rect2(1010, 520, 30, 40), Color(0.7, 0.4, 0.3)))
	var guard := _poly("Guard", Rect2(640, 496, 32, 64), Color(0.8, 0.2, 0.2))
	guard.add_to_group(&"enemy", true)
	root.add_child(guard)
	root.add_child(_poly("Lantern", Rect2(900, 100, 24, 40), Color(1, 0.8, 0.4)))
	save_scene(root, ROOM)
	root.free()

func _save_small() -> void:
	var root := Node2D.new()
	root.name = "Closet"
	_floor(root, 200)
	root.add_child(_poly("Door", Rect2(0, 400, 200, 160)))
	root.add_child(_poly("Pot", Rect2(80, 520, 40, 40)))
	var key := _poly("Key", Rect2(60, 530, 30, 30))
	key.add_to_group(&"pickup", true)
	root.add_child(key)
	save_scene(root, SMALL)
	root.free()
