extends "res://tests/test_case.gd"
## Brief 9: the 2.5D presentation module.

func _run() -> void:
	await _demos()
	await _what_is_extruded()
	await _cost()

func _depth(room: Node, view: Rect2) -> MDSDepth25D:
	var d := MDSDepth25D.new()
	d.view_override = view
	room.add_child(d)
	return d

func _face_points(d: MDSDepth25D) -> PackedVector2Array:
	return d._faces._pts.duplicate()

func _demos() -> void:
	for path in ["res://asset_packs/mossgrove/demo/freeform_cave.tscn", "res://asset_packs/mossgrove/demo/mossgrove_demo.tscn", "res://asset_packs/sunken_gardens/demo/sunken_garden_demo.tscn"]:
		var room := (load(path) as PackedScene).instantiate()
		room.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(room)
		var d := _depth(room, Rect2(0, 0, 1152, 648))
		d.process_mode = Node.PROCESS_MODE_ALWAYS
		await get_tree().process_frame
		await get_tree().process_frame
		check(not d.masses.is_empty(), "%s: terrain to extrude is found (%d masses)" % [path.get_file(), d.masses.size()])
		check(d.stats.side + d.stats.floor > 0, "%s renders extruded faces (%s)" % [path.get_file(), d.stats])
		var a := _face_points(d)
		d.view_override = Rect2(400, 300, 1152, 648)
		await get_tree().process_frame
		await get_tree().process_frame
		check(_face_points(d) != a, "%s: the faces swing as the camera moves" % path.get_file())
		room.queue_free()
		await get_tree().process_frame

func _shape(parent: Node, r: Rect2, role := -1, solid := true) -> MDSFreeform:
	var f := MDSFreeform.new()
	f.smooth = false
	f.points = rect_points(r)
	f.solid = solid
	if role >= 0:
		f.set_collision_override(role, role == MDSFreeformStyle.Role.PLATFORM)
	parent.add_child(f)
	return f

func _what_is_extruded() -> void:
	var room := Node2D.new()
	add_child(room)
	var back := Node2D.new()
	back.name = "FreeformBack"
	room.add_child(back)
	var front := Node2D.new()
	front.name = "FreeformFront"
	room.add_child(front)
	var g := Node2D.new()
	g.name = "Freeform"
	room.add_child(g)
	var ground := _shape(g, Rect2(0, 500, 1152, 148))
	var ledge := _shape(g, Rect2(400, 300, 200, 24), MDSFreeformStyle.Role.PLATFORM)
	var deep := _shape(g, Rect2(800, 0, 352, 300), MDSFreeformStyle.Role.DECOR, false)
	var ruin := _shape(back, Rect2(100, 300, 100, 200), -1, false)
	var leaves := _shape(front, Rect2(0, 0, 200, 100), -1, false)
	var flat_style := MDSFreeformStyle.new()
	flat_style.extrude = false
	var flat := _shape(g, Rect2(700, 400, 100, 40))
	flat.style = flat_style
	var tiles := TileMapLayer.new()
	tiles.tile_set = _tileset()
	for x in 4:
		tiles.set_cell(Vector2i(x, 2), 0, Vector2i.ZERO)
	room.add_child(tiles)
	var d := _depth(room, Rect2(0, 0, 1152, 648))
	await get_tree().process_frame
	await get_tree().process_frame
	var nodes := d.masses.map(func(m: Dictionary) -> Node: return m.node)
	check(ground in nodes and ledge in nodes, "solid terrain and platforms are extruded")
	check(not deep in nodes and not ruin in nodes and not leaves in nodes, "decorations, background and foreground shapes are not")
	check(not flat in nodes, "a style with extrude off is not")
	check(tiles in nodes, "tile collision is extruded")
	var tile_mass: Dictionary = d.masses[nodes.find(tiles)]
	check(tile_mass.edges.size() == 4, "a row of tiles is one block: 4 merged edges (%d)" % tile_mass.edges.size())
	# Moving a shape redraws its faces.
	var before := _face_points(d)
	ledge.position += Vector2(0, -40)
	await get_tree().process_frame
	await get_tree().process_frame
	check(_face_points(d) != before, "a moved platform's faces follow it")
	room.queue_free()
	await get_tree().process_frame

func _tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.add_physics_layer()
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.45, 0.4))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(32, 32)
	ts.add_source(src, 0)
	src.create_tile(Vector2i.ZERO)
	var td := src.get_tile_data(Vector2i.ZERO, 0)
	td.add_collision_polygon(0)
	td.set_collision_polygon_points(0, 0, MDSGeometry.rect_polygon(Rect2(-16, -16, 32, 32)))
	return ts

## A 2304 x 1296 room with 30 curved shapes: building the faces of a frame stays under 1 ms.
func _cost() -> void:
	var room := Node2D.new()
	add_child(room)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var st := load("res://asset_packs/mossgrove/freeform/styles/mossy_rock.freeform.tres") as MDSFreeformStyle
	for i in 30:
		var c := Vector2(rng.randf_range(100, 2200), rng.randf_range(100, 1200))
		var pts := PackedVector2Array()
		for k in 10:
			var a := TAU * k / 10.0
			pts.append(c + Vector2(cos(a), sin(a)) * rng.randf_range(80, 160))
		var f := MDSFreeform.new()
		f.style = st
		f.points = pts
		room.add_child(f)
	var d := _depth(room, Rect2(0, 0, 1152, 648))
	await get_tree().process_frame
	await get_tree().process_frame
	var total := 0
	var frames := 0
	for step in 40:
		d.view_override = Rect2(Vector2(step * 28.0, step * 16.0), Vector2(1152, 648))
		await get_tree().process_frame
		total += d.stats.usec
		frames += 1
	var avg := float(total) / frames
	print("  2.5D faces: %.0f us per frame on average (%d edges)" % [avg, d.stats.edges])
	check(avg < 1000.0, "building a frame's faces takes under 1 ms (%.0f us)" % avg)
	room.queue_free()
	await get_tree().process_frame
