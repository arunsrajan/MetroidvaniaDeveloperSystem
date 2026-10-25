extends "res://tests/test_case.gd"
## Caves a player can cross and backtrack, and scenes dropped in the Full view.
## Generate all and New variation for all (the Full view) on areas side by side, areas apart,
## freeform caves (the Moss Grotto kind) and an outline split into rooms: in every room each gate
## reaches every other one and back, one dropped in through a ceiling climbs back out, and every
## room is reached from every other through doors (areas that touch get one, areas apart a
## passage). Doors in a floor or a ceiling get ledges on rows fixed on the world grid, so the room
## above's and the room below's make one climb. A scene's footprint on the map: its MapBounds,
## else the cells its terrain covers and closes in (an L stays an L), else its pictures. Scenes
## dragged over the Full view show where they go, against their neighbours, never over them.
## Generate cave works on the rooms selected there; the 2.5D preview shows every room.

const DIR := TMP + "/backtracking"

var view: MDSRoomView

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	await _walkable("areas side by side", _areas(4))
	await _walkable("areas apart", _areas(1))
	await _walkable("freeform caves", _freeform(0))
	await _walkable("an outline split into rooms", _sketch())
	_door_ladders()
	_footprints()
	await _drops()
	await _selected_and_depth()

func _world(name: String) -> MDSWorld:
	var world := MDSWorld.new()
	world.path = DIR + "/%s.mdsworld.json" % name.to_snake_case()
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	return world

func _areas(seed_value: int) -> MDSWorld:
	var world := _world("areas_%d" % seed_value)
	var gen := MDSAreaGenerator.new()
	gen.shape = MDSAreaGenerator.Shape.HYBRID
	gen.seed_value = 4 + seed_value
	gen.generate(world, Rect2i(0, 0, 10, 7), 0, "West")
	gen.seed_value = 5 + seed_value
	gen.generate(world, Rect2i(10, 0, 10, 7), 0, "East")
	return world

func _freeform(seed_value: int) -> MDSWorld:
	var world := _world("freeform_%d" % seed_value)
	var gen := MDSAreaGenerator.new()
	gen.shape = MDSAreaGenerator.Shape.FREEFORM
	gen.seed_value = 11 + seed_value
	gen.generate(world, Rect2i(0, 0, 12, 8), 0, "Moss Grotto")
	return world

func _sketch() -> MDSWorld:
	var world := _world("sketch")
	var pts := PackedVector2Array()
	for i in 48:
		var t := TAU * i / 48.0
		var r := 1.0 + 0.25 * sin(3.0 * t) + 0.12 * cos(5.0 * t)
		pts.append(Vector2(3000, 1400) + Vector2(cos(t) * 2600.0 * r, sin(t) * 1200.0 * r))
	MDSRoomSketches.add(world, 0, pts, MDSRoomSketches.ROOMS, MDSRoomSketches.NEW_AREA, "curvy")
	MDSRoomSketches.new().generate(world, 0)
	return world

func _open(world: MDSWorld, prefix: String) -> void:
	if view:
		view.close_room(false)
		view.queue_free()
		await get_tree().process_frame
	view = MDSRoomView.new()
	view.size = Vector2(1400, 900)
	view.scene_path_for = func(id: String) -> String: return DIR.path_join(prefix + "_" + id.to_snake_case() + ".tscn")
	add_child(view)
	await get_tree().process_frame
	view.open_full(world, 0)
	await get_tree().process_frame

func _walkable(what: String, world: MDSWorld) -> void:
	await _open(world, what.to_snake_case())
	var before := MDSAreaTools.pieces(world, world.get_room_ids())
	var made := view.generate_all(false)
	check(made == world.get_room_ids().size(), "%s: Generate all makes a cave in each room (%d of %d)" % [what, made, world.get_room_ids().size()])
	var bad := _faults(world)
	check(bad.is_empty() and MDSAreaTools.pieces(world, world.get_room_ids()) == 1, "%s: every gate reaches every other one and back, every room reached through doors (%d piece(s) before) %s" % [what, before, bad])
	var first := _terrain(world)
	view.generate_all(true)
	bad = _faults(world)
	var changed := 0
	var now := _terrain(world)
	for id in now:
		if now[id] != first.get(id):
			changed += 1
	check(bad.is_empty() and changed * 2 >= now.size(), "%s: New variation for all is another layout (%d of %d rooms changed), as walkable %s" % [what, changed, now.size(), bad])

func _terrain(world: MDSWorld) -> Dictionary:
	var out: Dictionary = {}
	for id in world.get_room_ids():
		var p: MDSRoomPainter = view._session_painter(id)
		out[id] = hash(p.layers.Terrain.get_used_cells()) if p else 0
	return out

## What a player can't do in the rooms as generated: [room's gates that don't reach each other].
func _faults(world: MDSWorld) -> Array:
	var bad: Array = []
	for id in world.get_room_ids():
		var p: MDSRoomPainter = view._session_painter(id)
		if not p:
			bad.append(id + ": no scene")
			continue
		var reach: int = p.climb_params(world).reach
		var solid: Dictionary = {}
		for c in p.layers.Terrain.get_used_cells():
			solid[c] = true
		# Where a player can be: the room's box but its tiles.
		var open: Dictionary = {}
		for c in p.room_cells(world, id, false):
			if not solid.has(c):
				open[c] = true
		var ends: Array = []
		for g in world.get_gates(id):
			var e := p.gate_end(world, id, g, open)
			if e.is_empty():
				bad.append("%s.%s: no way in" % [id, g])
			else:
				ends.append(e)
		if not p.gates_joined(open, {}, ends, reach):
			bad.append(id)
	return bad

func _door_ladders() -> void:
	# A room above another (on whole tiles), a door between them in the floor of the one above.
	var world := _world("ladders")
	world.add_room("Above", Rect2(0, 0, 1152, 640), 0)
	world.add_room("Below", Rect2(0, 640, 1152, 640), 0)
	var a := world.add_gate("Above", Vector2(576, 640), "bot", "", false)
	var b := world.add_gate("Below", Vector2(576, 640), "top", "", false)
	world.connect_gates("Above", a, "Below", b)
	var steps: Array = []
	var rows: Dictionary = {}
	for id in ["Above", "Below"]:
		var root := Node2D.new()
		root.name = id
		save_scene(root, DIR + "/%s.tscn" % id.to_lower())
		root.free()
		world.set_room_scene(id, DIR + "/%s.tscn" % id.to_lower())
		var p := MDSRoomPainter.open(DIR + "/%s.tscn" % id.to_lower(), load(DIR + "/tiles.tres"))
		var step: int = p.climb_params(world).step
		steps.append(step)
		var ladder := p.door_ledges(world, id, p.room_cells(world, id))
		var off := int(world.get_origin(id).y / 32.0)
		for c in ladder:
			rows[c.y + off] = (c.x >= 18) # the right half of the doorway (it is at x 16..19)
		# On rows of the world's grid, but the one on the room's edge a row in (the gate's box).
		check(not ladder.is_empty() and ladder.all(func(c: Vector2i) -> bool: return posmod(c.y + off, step) == 0 or c.y + off == 21), "%s: ledges up its doorway, on rows of the world's grid (%s)" % [id, ladder])
		p.generate_cave(world, id, 3)
		var solid: Dictionary = {}
		for c in p.layers.Terrain.get_used_cells():
			solid[c] = true
		check(ladder.all(func(c: Vector2i) -> bool: return solid.has(c)) and p.paths_joined, "%s: Generate cave keeps them" % id)
		p.free_instance()
	var keys := rows.keys()
	keys.sort()
	var alternate := true
	for i in range(1, keys.size()):
		alternate = alternate and keys[i] - keys[i - 1] <= steps[0] + 1 and rows[keys[i]] != rows[keys[i - 1]]
	check(keys.size() >= 3 and alternate, "the two rooms' ledges make one climb through the door, a jump apart, on alternate sides (%s)" % [rows])

## A scene of [param cells] (paint cells of 256 x 160, 8 x 5 tiles) filled with terrain tiles.
func _terrain_scene(name: String, cells: Array, extra: Callable = Callable()) -> String:
	var root := Node2D.new()
	root.name = name
	var layer := TileMapLayer.new()
	layer.name = "Terrain"
	layer.tile_set = load(DIR + "/tiles.tres")
	root.add_child(layer)
	for c: Vector2i in cells:
		for y in 5:
			for x in 8:
				layer.set_cell(Vector2i(c.x * 8 + x, c.y * 5 + y), 0, Vector2i.ZERO)
	if extra.is_valid():
		extra.call(root)
	var path := DIR + "/%s.tscn" % name
	save_scene(root, path)
	root.free()
	load_fresh(path)
	return path

func _footprint_of(world: MDSWorld, path: String) -> Dictionary:
	return MDSWorldSceneTools.footprint(world, MDSSceneScanner.new(world.get_default_room_size()).analyze_scene_any(path))

func _footprints() -> void:
	var world := _world("footprints")
	world.set_setting("paint_cell", [256, 160])
	var l_cells: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(0, 2)]
	var fp := _footprint_of(world, _terrain_scene("ell", l_cells))
	check(fp.size() == 5 and l_cells.all(func(c: Vector2i) -> bool: return fp.has(c)), "an L of terrain is an L on the map, not its box (%s)" % [fp.keys()])
	# A ring of rock round a hollow: the hollow is the room's too.
	var ring: Array = []
	for y in 3:
		for x in 3:
			if x != 1 or y != 1:
				ring.append(Vector2i(x, y))
	fp = _footprint_of(world, _terrain_scene("hollow", ring))
	check(fp.size() == 9 and fp.has(Vector2i(1, 1)), "a cave's hollow is in it (%d)" % fp.size())
	# Made by MetDevSys: the rectangles it was made with.
	world.add_room("Made", Rect2(0, 0, 512, 160), 0)
	world.add_rect("Made", Rect2(0, 160, 256, 320))
	MDSWorldSceneTools.create_scene_for_room(world, "Made", DIR + "/made.tscn")
	load_fresh(DIR + "/made.tscn")
	fp = _footprint_of(world, DIR + "/made.tscn")
	check(fp.size() == 4 and fp.has(Vector2i(1, 0)) and fp.has(Vector2i(0, 2)) and not fp.has(Vector2i(1, 1)), "a scene's MapBounds are its shape (%s)" % [fp.keys()])
	# Pictures only: what they cover.
	var img := Image.create(600, 300, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var art := Node2D.new()
	art.name = "Art"
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	art.add_child(sprite)
	save_scene(art, DIR + "/art.tscn")
	art.free()
	load_fresh(DIR + "/art.tscn")
	fp = _footprint_of(world, DIR + "/art.tscn")
	check(fp.size() == 6 and fp.has(Vector2i(2, 1)) and not fp.has(Vector2i(0, 2)), "a scene of pictures alone: the cells they cover (%s)" % [fp.keys()])
	# Placed where a room is: the nearest place free, joined by its gates to the room it touches.
	world.add_room("Here", Rect2(0, 600, 768, 480), 0)
	var meta := MDSSceneScanner.new(world.get_default_room_size()).analyze_scene_any(DIR + "/ell.tscn")
	var id := MDSWorldSceneTools.place_scene(world, DIR + "/ell.tscn", meta, Vector2(256, 640), 0, "", true)
	var mine := world.get_room_cells(id)
	var overlap := mine.keys().filter(func(c: Vector2i) -> bool: return world.get_room_cells("Here").has(c))
	check(mine.size() == 5 and overlap.is_empty(), "a scene dropped on a room goes to the nearest place free, as its L (%s)" % [mine.keys()])

func _drops() -> void:
	var world := _world("drops")
	world.set_setting("paint_cell", [256, 160])
	world.add_room("Left", Rect2(0, 0, 768, 480), 0)
	world.add_room("Empty", Rect2(3072, 0, 512, 320), 0)
	world.set_room_scene("Left", _terrain_scene("left", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]))
	await _open(world, "drops")
	var tools := view.full_tools
	var ell := DIR + "/ell.tscn"
	var files := PackedStringArray([ell])
	var left := world.get_world_rects("Left")
	var hits := 0
	var last := Vector2.ZERO
	var xs: Array[float] = []
	# Dragged from the right into the room on the left: it follows the mouse to the pixel, then
	# stays against the room, never over it.
	for k in 12:
		last = tools.drop_preview(files, Vector2(1800 - k * 117, 240))
		var d: Dictionary = tools._drop
		xs.append(d.at.x)
		for r: Rect2 in d.rects:
			for l in left:
				if Rect2(r.position + d.at, r.size).grow(-0.5).intersects(l):
					hits += 1
	check(hits == 0 and tools._drop.touch, "dragged into a room, the scene's shape stays against it, never over it (%s)" % [tools._drop.get("at")])
	check(is_equal_approx(xs[1] - xs[0], -117.0) and not is_zero_approx(fmod(xs[1], 256.0)), "smoothly, with the mouse, not by paint cells (%s)" % [xs.slice(0, 3)])
	check(is_equal_approx(tools._drop.at.x + 0.0, 768.0), "flush against it (%s)" % tools._drop.at)
	check(not tools._drop.is_empty(), "shown while dragged")
	tools.drop_end()
	check(tools._drop.is_empty(), "and no more once dropped or gone")
	# Dropped there: a room of its shape, where it was shown, to the pixel.
	var before := world.get_room_ids().size()
	view.scenes_dropped.connect(func(f: PackedStringArray, at: Vector2) -> void:
		var meta := MDSSceneScanner.new(world.get_default_room_size()).analyze_scene_any(f[0])
		MDSWorldSceneTools.place_scene(world, f[0], meta, at, 0, "", true, true), CONNECT_ONE_SHOT)
	view.scenes_dropped.emit(files, last)
	var placed := world.get_room_ids().filter(func(id: String) -> bool: return world.get_scene_path(id) == ell)
	check(world.get_room_ids().size() == before + 1 and placed.size() == 1 and world.get_local_rects(placed[0]).size() == 2 and world.get_room_bounds(placed[0]).position.is_equal_approx(last), "dropped, it is a room of its shape where it was shown (%s, %s)" % [world.get_room_bounds(placed[0]).position if placed.size() == 1 else Vector2.INF, last])
	# Over a room without a scene: that room is what it fills.
	tools.drop_preview(files, Vector2(3100, 100))
	check(tools._drop.get("fill") == "Empty", "over a room without a scene, it fills that room")
	tools.drop_end()

func _selected_and_depth() -> void:
	var world := _freeform(2)
	await _open(world, "selected")
	var ids := world.get_room_ids()
	view.full_tools.select([ids[0], ids[1]])
	view.generate(false)
	var made := ids.filter(func(id: String) -> bool:
		var p: MDSRoomPainter = view._painters.get(id)
		return p != null and not p.layers.Terrain.get_used_cells().is_empty())
	check(made.size() == 2 and made.has(ids[0]) and made.has(ids[1]), "Generate cave in the Full view makes caves in the rooms selected (%s)" % [made])
	view.generate(true)
	check(view._painters.size() == 2, "and New variation, in them alone")
	view.full_tools.clear_selection()
	view.canvas.set_depth_preview(true)
	await get_tree().process_frame
	var depth := view.canvas._depth
	check(is_instance_valid(depth) and depth.sources.size() >= view.canvas._context.size() and view.canvas._context.size() > 0, "the 2.5D preview in the Full view, of every room shown (%d)" % (depth.sources.size() if depth else 0))
	view.canvas.set_depth_preview(false)
	check(not is_instance_valid(view.canvas._depth), "and off")
	view.close_room(false)
	view.queue_free()
	view = null
	await get_tree().process_frame
