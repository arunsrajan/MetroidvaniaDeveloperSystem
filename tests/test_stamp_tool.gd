extends "res://tests/test_case.gd"
## The Stamps tool: its Random box, and the preview of what a click places.
## - the preview: the stamp a click would place (its very sprite, size, flip and tilt) follows the
##   mouse and the click places that one; moving the mouse places nothing; it is not shown over a
##   resize handle, with Shift (a click removes), once the mouse has left, under another tool, or on
##   top of the stamp just placed until the mouse moves on;
## - Random on: any sprite of the category, 80% to 120% of the Size, flipped or not, tilted a little;
##   Random off: the one sprite picked, exactly at the Size, upright and not flipped (a pick that is
##   not in the category gives the category's first);
## - the Room view: the Random box and, with it off, the category's sprites to pick from; the box of
##   the cave shapes that turns them is called Random turn;
## - Generate cave's stamps follow Random and the sprite picked, sitting where they would have sat;
## - the Effects tool previews the area a click would cover.

const TILES := TMP + "/stamp_tiles.tres"
const ROOM := TMP + "/stamp_room.tscn"
const STAMPS := "res://asset_packs/mossgrove/freeform/mossgrove.stamps.tres"

var canvas: MDSRoomCanvas
var view: MDSRoomView
var stamps: MDSStampSet
var category := ""
var picks: Array[int] = []

func _run() -> void:
	stamps = load(STAMPS)
	check(stamps != null, "the Mossgrove stamps are in the project")
	if not stamps:
		return
	# The category with the most sprites, so there is something to pick from.
	for c in stamps.get_categories():
		if stamps.indices(c).size() > picks.size():
			category = c
			picks = stamps.indices(c)
	check(picks.size() >= 3, "a category of several sprites (%s: %d)" % [category, picks.size()])
	await _open()
	_preview()
	_random_off()
	_random_on()
	_controls()
	_generated()
	_effects()
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame

func _open() -> void:
	var ts := MDSTilesetFactory.get_or_create(TILES)
	var root := Node2D.new()
	root.name = "StampRoom"
	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = ts
	root.add_child(terrain)
	save_scene(root, ROOM)
	root.free()
	load_fresh(ROOM)
	var world := MDSWorld.new()
	world.path = TMP + "/stamp.mdsworld.json"
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

## Moves the mouse to [param p] (scene = screen, at zoom 1 with no pan), no button pressed.
func _move(p: Vector2, shift := false) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = canvas.local_to_screen(p)
	mm.shift_pressed = shift
	canvas._gui_input(mm)

func _click(p: Vector2, shift := false) -> void:
	for pressed: bool in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.shift_pressed = shift
		mb.position = canvas.local_to_screen(p)
		canvas._gui_input(mb)

func _count() -> int:
	return canvas.painter.items(canvas.stamp_group).size()

func _index(s: Node) -> int:
	return int(s.get_meta(&"mds_stamp"))

func _preview() -> void:
	view.set_tool(MDSRoomCanvas.Tool.STAMP)
	canvas.stamp_set = stamps
	canvas.stamp_category = category
	canvas.stamp_random = true
	canvas.stamp_scale = 1.0
	var before := _count()
	check(canvas.stamp_ghost().is_empty(), "no preview before the mouse is over the room")
	_move(Vector2(300, 200))
	var ghost := canvas.stamp_ghost().duplicate()
	check(not ghost.is_empty() and int(ghost.index) in picks, "the Stamps tool shows a stamp of the category at the mouse")
	_move(Vector2(340, 210))
	_move(Vector2(380, 220))
	check(canvas.stamp_ghost() == ghost, "it is the same stamp while the mouse moves")
	check(_count() == before, "moving the mouse places nothing")
	# The click places that very stamp.
	_click(Vector2(380, 220))
	check(_count() == before + 1, "a click places one")
	var s: Sprite2D = canvas.selection[0]
	check(_index(s) == int(ghost.index) and s.scale.is_equal_approx(ghost.scale) and is_equal_approx(s.rotation, ghost.rotation), "the click placed the stamp that was shown (sprite %d, scale %s, tilt %.3f; placed %d, %s, %.3f)" % [int(ghost.index), ghost.scale, ghost.rotation, _index(s), s.scale, s.rotation])
	check(canvas.stamp_ghost().is_empty(), "no preview on top of the stamp just placed")
	_move(Vector2(520, 260))
	check(not canvas.stamp_ghost().is_empty(), "it is back once the mouse moves on")
	# Over a handle of the stamp placed, a click resizes it: nothing to preview.
	var box := canvas._resize_screen_box()
	check(box.has_area(), "the stamp placed has its handles")
	_move(canvas.screen_to_local(MDSRoomCanvas.handle_point(box, 3)))
	check(canvas.stamp_ghost().is_empty(), "no preview over a resize handle")
	_move(Vector2(700, 300), true)
	check(canvas.stamp_ghost().is_empty(), "no preview with Shift held: a click removes stamps")
	_move(Vector2(700, 300))
	check(not canvas.stamp_ghost().is_empty(), "Shift let go, it is back")
	canvas.notification(Control.NOTIFICATION_MOUSE_EXIT)
	check(canvas.stamp_ghost().is_empty(), "no preview once the mouse has left the room")
	_move(Vector2(700, 300))
	check(not canvas.stamp_ghost().is_empty(), "it is back when the mouse returns")
	view.set_tool(MDSRoomCanvas.Tool.TERRAIN)
	check(canvas.stamp_ghost().is_empty(), "no stamp preview under another tool")
	view.set_tool(MDSRoomCanvas.Tool.STAMP)
	# Shift+click still removes the stamps near it.
	_click(Vector2(380, 220), true)
	check(_count() == before, "Shift+click removes the stamp (%d left)" % _count())

func _random_off() -> void:
	canvas.stamp_random = false
	canvas.stamp_scale = 1.5
	canvas.stamp_pick = picks[2]
	_move(Vector2(200, 400))
	var g := canvas.stamp_ghost()
	check(not g.is_empty() and int(g.index) == picks[2] and g.scale == Vector2(1.5, 1.5) and g.rotation == 0.0, "Random off: the preview is the sprite picked, exactly at the Size, upright (%s)" % [g])
	var placed: Array[Sprite2D] = []
	for i in 6:
		placed.append(canvas.place_stamp(Vector2(150 + i * 120, 500)))
	check(placed.all(func(s: Sprite2D) -> bool: return _index(s) == picks[2] and s.scale == Vector2(1.5, 1.5) and s.rotation == 0.0), "six stamps are all that sprite, at exactly the Size, not flipped or tilted")
	canvas.stamp_scale = 0.3
	check(canvas.place_stamp(Vector2(300, 600)).scale == Vector2(0.3, 0.3), "at any Size: 30%")
	canvas.stamp_pick = picks[0]
	check(int(canvas.stamp_ghost().index) == picks[0], "another sprite picked, the preview changes at once")
	canvas.stamp_pick = 99999
	check(int(canvas.stamp_ghost().index) == picks[0], "a sprite that is not of the category: the category's first")
	canvas.stamp_pick = -1
	check(int(canvas.stamp_ghost().index) == picks[0], "none picked: the category's first")

func _random_on() -> void:
	canvas.stamp_random = true
	canvas.stamp_scale = 1.0
	var placed: Array[Sprite2D] = []
	for i in 60:
		placed.append(canvas.place_stamp(Vector2(100 + (i % 20) * 50, 100 + (i / 20) * 40)))
	var used := {}
	var flipped := 0
	var tilted := 0
	var in_range := true
	for s in placed:
		used[_index(s)] = true
		var k := absf(s.scale.y)
		in_range = in_range and k >= 0.8 - 0.0001 and k <= 1.2 + 0.0001 and is_equal_approx(absf(s.scale.x), k) and absf(s.rotation) <= 0.12 + 0.0001
		flipped += 1 if s.scale.x < 0.0 else 0
		tilted += 1 if not is_zero_approx(s.rotation) else 0
	check(in_range, "Random on: 80% to 120% of the Size, tilted by 0.12 radians at most")
	check(used.size() >= 2 and used.keys().all(func(i: int) -> bool: return i in picks), "any sprite of the category (%d of %d used)" % [used.size(), picks.size()])
	check(flipped > 5 and flipped < 55, "flipped about half the time (%d of 60)" % flipped)
	check(tilted > 50, "tilted a little (%d of 60)" % tilted)

func _controls() -> void:
	view.set_tool(MDSRoomCanvas.Tool.STAMP)
	canvas.stamp_random = true
	view._update_stamp_controls()
	check(view.stamp_random_check.visible and view.stamp_random_check.button_pressed, "the Stamps tool has a Random box, ticked")
	check(not view.stamp_sprites.visible, "and no sprites to pick from while it is ticked")
	view.stamp_random_check.button_pressed = false
	check(not canvas.stamp_random and view.stamp_sprites.visible, "unticked: the canvas places one sprite, and the sprites are listed")
	check(view.stamp_sprites.item_count == picks.size(), "the list has the category's sprites (%d)" % view.stamp_sprites.item_count)
	var icon := view.stamp_sprites.get_item_icon(1) as AtlasTexture
	check(icon != null and icon.atlas == stamps.texture and icon.region == stamps.regions[picks[1]], "each is its picture")
	view.stamp_sprites.select(1)
	view.stamp_sprites.item_selected.emit(1)
	check(canvas.stamp_pick == picks[1], "picking one in the list sets the sprite placed")
	view.set_tool(MDSRoomCanvas.Tool.TERRAIN)
	check(not view.stamp_random_check.visible and not view.stamp_sprites.visible, "the other tools show neither")
	view.set_tool(MDSRoomCanvas.Tool.STAMP)
	check(view.stamp_sprites.is_selected(1), "back on the Stamps tool, the sprite picked is still picked")
	# Another category: the sprite picked is of the old one, so the new category's first is used.
	var other := ""
	for i in view.fill_opt.item_count:
		var meta: Variant = view.fill_opt.get_item_metadata(i)
		if meta is Array and view._stamp_sets[meta[0]] == stamps and meta[1] != category and stamps.indices(meta[1]).size() > 0:
			other = meta[1]
			view.fill_opt.select(i)
			view.fill_opt.item_selected.emit(i)
			break
	check(not other.is_empty() and canvas.stamp_category == other, "another category picked in the Fill list (%s)" % other)
	var others := stamps.indices(other)
	check(view.stamp_sprites.item_count == others.size() and canvas.stamp_pick in others, "its sprites are listed, one of them picked")
	# Generate cave takes both along.
	canvas.stamp_pick = others[others.size() - 1]
	var fills := view.generation_fills()
	check(fills.has("stamps") and fills.stamps.random == false and fills.stamps.pick == others[others.size() - 1], "Generate cave's stamps follow Random and the sprite")
	view.stamp_random_check.button_pressed = true
	check(view.generation_fills().stamps.random == true, "and Random ticked again")
	# The cave shapes' box that turns each its own way is not the stamps' Random.
	var row := view.cave_rotation_spin.get_parent()
	var turn_box := row.get_child(row.get_child_count() - 1) as CheckBox
	check(turn_box != null and turn_box.text == "Random turn", "the cave shapes' box is called Random turn (%s)" % [turn_box.text if turn_box else "none"])
	canvas.stamp_category = category
	canvas.stamp_pick = -1
	canvas.stamp_random = true

## Sites of the stamps Generate cave scattered, left to right.
func _sites(painter: MDSRoomPainter) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for g in ["StampsBack", "StampsFront", "StampsForeground"]:
		for st: Node2D in painter.items(g):
			if st.has_meta(MDSRoomPainter.GENERATED_META):
				out.append(st)
	out.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.x < b.position.x)
	return out

func _generated() -> void:
	var painter := canvas.painter
	# A flat floor, 60 tiles wide: open above row 20's rock.
	var inside := {}
	var solid := {}
	for x in 60:
		for y in range(5, 21):
			inside[Vector2i(x, y)] = true
			if y == 20:
				solid[Vector2i(x, y)] = true
	var opts := {"set": stamps, "category": category, "group": "StampsFront", "scale": 1.3}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	painter._generate_stamps(inside, solid, opts, rng)
	var random_sites := _sites(painter)
	var random_at: Array[Vector2] = []
	var random_flips := 0
	var random_sprites := {}
	for st in random_sites:
		random_at.append(st.position)
		random_sprites[_index(st)] = true
		random_flips += 1 if st.scale.x < 0.0 else 0
	check(random_sites.size() == 6, "a floor of 60 tiles gets six stamps (%d)" % random_sites.size())
	check(random_sprites.size() >= 2 or random_sites.size() < 2, "by default (Random) they are different sprites (%d)" % random_sprites.size())
	opts["random"] = false
	opts["pick"] = picks[1]
	rng.seed = 7
	painter._generate_stamps(inside, solid, opts, rng)
	var fixed_sites := _sites(painter)
	check(fixed_sites.size() == random_sites.size(), "Random off: a new generation replaces them (%d)" % fixed_sites.size())
	check(fixed_sites.all(func(st: Node2D) -> bool: return _index(st) == picks[1] and st.scale == Vector2(1.3, 1.3) and st.rotation == 0.0), "all the one sprite picked, exactly at the Size, not flipped")
	var fixed_at: Array[Vector2] = []
	for st in fixed_sites:
		fixed_at.append(st.position)
	check(fixed_at == random_at, "sitting where they sat with Random on")
	opts["pick"] = 99999
	rng.seed = 7
	painter._generate_stamps(inside, solid, opts, rng)
	check(_sites(painter).all(func(st: Node2D) -> bool: return _index(st) == picks[0]), "a sprite that is not of the category: the category's first")
	for st in _sites(painter):
		painter.remove_item(st)

func _area(e: MDSEnvironmentEffect) -> Rect2:
	var r := e.get_effect_rect()
	return Rect2(e.position + r.position, r.size)

func _effects() -> void:
	view.set_tool(MDSRoomCanvas.Tool.EFFECT)
	canvas.selected_effect = null
	canvas.notification(Control.NOTIFICATION_MOUSE_EXIT)
	canvas.set_effect_pick("rain")
	check(canvas.effect_ghost().has_area() == false, "no effect preview before the mouse is over the room")
	var painter := canvas.painter
	for id in ["rain", "steam_vent"]:
		canvas.set_effect_pick(id)
		var n: int = painter.effects().size()
		_move(Vector2(600, 400))
		_move(Vector2(640, 420))
		var area := canvas.effect_ghost()
		check(area.has_area(), "the Effects tool shows the area a %s covers at the mouse" % id)
		check(painter.effects().size() == n, "moving the mouse places no effect")
		_move(Vector2(640, 420), true)
		check(not canvas.effect_ghost().has_area(), "no preview with Shift held: a click selects")
		_move(Vector2(640, 420))
		_click(Vector2(640, 420))
		var made: Array = painter.effects()
		check(made.size() == n + 1 and _area(made[made.size() - 1]).is_equal_approx(area), "the click puts the effect where the preview was (%s, placed %s)" % [area, _area(made[made.size() - 1]) if not made.is_empty() else "none"])
		check(not canvas.effect_ghost().has_area(), "with none picked any more, nothing is previewed")
		canvas.selected_effect = null
	canvas.set_effect_pick("rain")
	_move(Vector2(300, 300))
	canvas.notification(Control.NOTIFICATION_MOUSE_EXIT)
	check(not canvas.effect_ghost().has_area(), "no preview once the mouse has left the room")
	canvas.set_effect_pick("")
