extends "res://tests/test_case.gd"
## Rooms that aren't caves (MDSOpenLayouts), Generate cave's Outdoor and Arena styles, and the
## light: the daylight tileset, the bright 2.5D style and the game's brightness.
##
## Outdoor: an open sky over rolling ground with ledges; the sides another room goes on beyond
## are open, so three rooms in a row (the middle one lower and taller) are walked across from the
## first one's gate to the last one's, their grounds meeting at their edges. Arena: a flat floor,
## walls and a ceiling, platforms the same on both sides, its gates joined.

const DIR := TMP + "/open_layouts"
const TS := 32

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	_outdoor()
	_arena()
	_room_view()
	_light()

func _painter(world: MDSWorld, id: String) -> MDSRoomPainter:
	var root := Node2D.new()
	root.name = id
	var path := DIR + "/%s.tscn" % id.to_lower()
	save_scene(root, path)
	root.free()
	world.set_room_scene(id, path)
	return MDSRoomPainter.open(path, load(DIR + "/tiles.tres"))

## The room's solid cells, in world cells.
func _solid(p: MDSRoomPainter, world: MDSWorld, id: String) -> Dictionary:
	var out: Dictionary = {}
	var o := Vector2i((world.get_origin(id) / TS).round())
	for c in p.layers.Terrain.get_used_cells():
		out[c + o] = true
	return out

func _outdoor() -> void:
	var world := MDSWorld.new()
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	world.data.areas["Meadows"] = {"color": "#81b853"}
	world.add_room("Plains_A", Rect2(0, 0, 2304, 864), 0, "Meadows")
	world.add_room("Plains_B", Rect2(2304, 192, 2304, 1056), 0, "Meadows")
	world.add_room("Plains_C", Rect2(4608, 0, 2304, 864), 0, "Meadows")
	world.add_gate("Plains_A", Vector2(0, 560), "left", "left1", false)
	world.add_gate("Plains_C", Vector2(6912, 560), "right", "right1", false)
	var solid: Dictionary = {}
	var open: Dictionary = {}
	var surfaces: Dictionary = {}
	var ledges := 0
	for id in ["Plains_A", "Plains_B", "Plains_C"]:
		var p := _painter(world, id)
		p.generate_cave(world, id, 5, 0, 0, {}, {"cave": {"style": "outdoor"}})
		check(p.paths_joined, "%s: its gates joined" % id)
		var s := _solid(p, world, id)
		solid.merge(s)
		var b := Rect2i(Vector2i((world.get_room_bounds(id).position / TS).round()), Vector2i((world.get_room_bounds(id).size / TS).round()))
		var sky := 0
		for y in range(b.position.y, b.end.y):
			for x in range(b.position.x, b.end.x):
				var c := Vector2i(x, y)
				if not s.has(c):
					open[c] = true
					if y < b.position.y + b.size.y / 2:
						sky += 1
				elif not s.has(c + Vector2i.DOWN) and not s.has(c + Vector2i.UP) and y < b.end.y - 3:
					ledges += 1
		check(sky > b.size.x * b.size.y / 2 * 0.85, "%s: open sky over its upper half (%d cells)" % [id, sky])
		var roof := 0
		for x in range(b.position.x + 2, b.end.x - 2):
			if s.has(Vector2i(x, b.position.y)):
				roof += 1
		check(roof == 0, "%s: no ceiling" % id)
		# Where its ground is, column by column: the top of the rock up from the room's bottom.
		for x in range(b.position.x, b.end.x):
			var y := b.end.y - 1
			while y > b.position.y and s.has(Vector2i(x, y - 1)):
				y -= 1
			surfaces[x] = y
		p.free_instance()
	if OS.get_environment("LAYOUT_DEBUG") == "1":
		_dump(solid, Rect2i(0, 0, 216, 40))
	check(ledges > 0, "floating ledges to climb (%d cells)" % ledges)
	var steps: Array = []
	for edge in [72, 144]:
		steps.append(absi(int(surfaces.get(edge, 0)) - int(surfaces.get(edge - 1, 0))))
	check(steps[0] <= 3 and steps[1] <= 3, "the grounds meet at the rooms' edges, the middle one lower (steps %s)" % [steps])
	var walls := 0
	# From Plains_B's top (6 rows lower than Plains_A's: above it, Plains_A has its wall).
	for y in range(6, mini(int(surfaces.get(71, 27)), int(surfaces.get(72, 27)))):
		if solid.has(Vector2i(71, y)) or solid.has(Vector2i(72, y)):
			walls += 1
	check(walls == 0, "no wall between rooms side by side")
	var above := 0
	for y in range(0, 6):
		if solid.has(Vector2i(70, y)) and solid.has(Vector2i(71, y)):
			above += 1
	check(above == 6, "but one where no room is beyond")
	var cliff := 0
	for y in range(0, int(surfaces.get(215, 27)) - 6):
		if solid.has(Vector2i(215, y)):
			cliff += 1
	check(cliff > 0, "a wall at the world's end, beside its gate")
	# Walked across: from Plains_A's gate to Plains_C's.
	var start := Vector2i(3, 16)
	while start.y < 40 and not solid.has(start + Vector2i.DOWN):
		start.y += 1
	var reached := MDSRoomPainter.climb_reach(open, start, 6, 3)
	var far := 0
	for c: Vector2i in reached:
		far = maxi(far, c.x)
	check(far >= 212, "walked across the three rooms, from the first gate to the last (as far as column %d of 215)" % far)

func _arena() -> void:
	var world := MDSWorld.new()
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	world.add_room("Arena", Rect2(0, 0, 1728, 972))
	world.add_gate("Arena", Vector2(0, 800), "left", "left1", false)
	world.add_gate("Arena", Vector2(1728, 800), "right", "right1", false)
	world.add_gate("Arena", Vector2(864, 0), "top", "top1", false)
	var p := _painter(world, "Arena")
	p.generate_cave(world, "Arena", 3, 0, 0, {}, {"cave": {"style": "arena", "shape": "t"}})
	var s := _solid(p, world, "Arena")
	var w := 54
	var h := 30
	if OS.get_environment("LAYOUT_DEBUG") == "1":
		_dump(s, Rect2i(0, 0, w, h + 2))
	var flat := true
	for x in range(4, w - 4):
		for y in range(h - 3, h):
			flat = flat and s.has(Vector2i(x, y))
		flat = flat and not s.has(Vector2i(x, h - 4))
	check(flat, "a flat floor, three tiles thick, clear above")
	var roof := 0
	for x in w:
		if s.has(Vector2i(x, 0)):
			roof += 1
	check(roof > w - 8 and roof < w, "a ceiling, open at its top gate (%d of %d)" % [roof, w])
	var left := 0
	var right := 0
	for c: Vector2i in s:
		if c.y > 2 and c.y < h - 4 and c.x > 2 and c.x < w - 3:
			if c.x < w / 2:
				left += 1
			else:
				right += 1
	check(left > 0 and absi(left - right) <= maxi(4, left / 4), "platforms, the same on both sides (%d, %d)" % [left, right])
	var open: Dictionary = {}
	for c in p.room_cells(world, "Arena", false):
		if not p.layers.Terrain.get_cell_source_id(c) >= 0:
			open[c] = true
	var ends: Array = []
	for g in world.get_gates("Arena"):
		var e := p.gate_end(world, "Arena", g, open)
		if not e.is_empty():
			ends.append(e)
	check(ends.size() == 3 and p.gates_joined(open, {}, ends, int(p.climb_params(world).reach)) and p.paths_joined, "its gates reach each other and back")
	p.free_instance()

func _room_view() -> void:
	check(MDSCaveShapes.wanted({"style": "outdoor"}) and MDSCaveShapes.is_open({"shape": "natural", "style": "arena"}) and not MDSCaveShapes.wall_climb({"style": "outdoor"}), "Outdoor and Arena: no shape needed, no wall climb")
	var world := MDSWorld.new()
	world.path = DIR + "/rv.mdsworld.json"
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	world.add_room("A", Rect2(0, 0, 1728, 972))
	var view := MDSRoomView.new()
	add_child(view)
	view.world = world
	var style := view.cave_style_picker
	var outdoor := MDSCaveShapes.STYLES.map(func(c: Array) -> String: return c[0]).find("outdoor")
	check(style != null and outdoor >= 0 and style.item_count == MDSCaveShapes.STYLES.size(), "the Style list has Outdoor and Arena")
	if style:
		style.select(outdoor)
		style.item_selected.emit(outdoor)
		check(str(view.generation_fills().get("cave", {}).get("style", "")) == "outdoor" and view.cave_shape_picker.disabled, "Outdoor picked: Generate cave makes it, with no shape to pick")
	view.queue_free()
	await get_tree().process_frame

func _light() -> void:
	var avg := func(img: Image) -> float:
		var sum := 0.0
		var n := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					sum += c.get_luminance()
					n += 1
		return sum / maxf(n, 1)
	var cave: float = avg.call(MDSTilesetFactory.build_image("cave"))
	var day: float = avg.call(MDSTilesetFactory.build_image("daylight"))
	check(day > cave * 1.6, "the daylight tileset is much brighter than the cave one (%.2f, %.2f)" % [day, cave])
	check(is_equal_approx(avg.call(MDSTilesetFactory.build_image()), cave), "and the cave one is drawn as before")
	var ts := MDSTilesetFactory.get_or_create(DIR + "/day_tiles.tres", "daylight")
	check(ts and ts.get_terrain_color(0, 0).is_equal_approx(MDSTilesetFactory.PALETTES.daylight.moss), "made as a tileset")
	var style := load(MDSDepthStyle.DAYLIGHT) as MDSDepthStyle
	var moody := MDSDepthStyle.new()
	check(style and style.light_dark.get_luminance() > moody.light_dark.get_luminance() and style.vignette < moody.vignette, "the daylight 2.5D style barely darkens the view")
	# The game's brightness.
	var world := MDSWorld.new()
	world.path = DIR + "/bright.mdsworld.json"
	world.add_room("A", Rect2(0, 0, 1152, 648))
	var root := Node2D.new()
	root.name = "A"
	save_scene(root, DIR + "/bright_a.tscn")
	root.free()
	world.set_room_scene("A", DIR + "/bright_a.tscn")
	world.set_setting("brightness", 1.3)
	world.save()
	MDSWorld._cache.erase(world.path)
	var game := MDSWorldGame.new()
	game.world_file = world.path
	game.save_file = ""
	game.exploration_file = ""
	game.load_on_start = false
	add_child(game)
	await get_tree().process_frame
	var cm := game.get_node_or_null(^"Brightness") as CanvasModulate
	check(cm and cm.color.is_equal_approx(Color(1.3, 1.3, 1.3)), "World settings > Brightness brightens the rooms")
	game.brightness = 1.0
	game.apply_brightness()
	await get_tree().process_frame
	check(game.get_node_or_null(^"Brightness") == null, "the game's own brightness wins (1: as they are)")
	game.queue_free()
	await get_tree().process_frame

func _dump(s: Dictionary, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		var line := ""
		for x in range(r.position.x, r.end.x):
			line += "#" if s.has(Vector2i(x, y)) else "."
		print("%3d %s" % [y, line])
