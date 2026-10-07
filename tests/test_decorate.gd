extends "res://tests/test_case.gd"
## Brief 5: freeform auto-decorate and scenery generators.

const STAMPS := "res://asset_packs/mossgrove/freeform/mossgrove.stamps.tres"
## The doorway of left1 and the save point: nothing may cover them.
const DOOR := Rect2(0, 456, 260, 120)

func _run() -> void:
	_generators()
	_decorate()
	_freeform_tool()

func _generators() -> void:
	var rng := RandomNumberGenerator.new()
	var bad: PackedStringArray = []
	for kind in MDSShapeGenerators.NAMES.size():
		for i in 40:
			rng.seed = i * 31 + kind
			var w := rng.randf_range(60.0, 500.0)
			var h := rng.randf_range(40.0, 420.0)
			var box := Rect2(rng.randf_range(-200, 200), rng.randf_range(-200, 200), w, h)
			var d := MDSShapeGenerators.make(kind, box, rng)
			if d.points.size() < 3 or not MDSGeometry.is_simple(MDSFreeform.outline_of(d.points, d.smooth)):
				bad.append("%s %s" % [MDSShapeGenerators.NAMES[kind], box])
	check(bad.is_empty(), "every generated outline is simple (%d bad: %s)" % [bad.size(), bad.slice(0, 3)])
	var r2 := RandomNumberGenerator.new()
	r2.seed = 9
	var col := MDSShapeGenerators.make(MDSShapeGenerators.Kind.COLUMN, Rect2(100, 300, 110, 300), r2)
	var b := MDSGeometry.bounds(col.points)
	check(b.end.y > 600.0 and b.position.y >= 290.0 and b.position.y < 360.0, "a column stands on its box's bottom and reaches its top, give or take its jagged break (%s)" % b)
	r2.seed = 9
	var st := MDSShapeGenerators.make(MDSShapeGenerators.Kind.STALACTITES, Rect2(100, 300, 300, 120), r2)
	b = MDSGeometry.bounds(st.points)
	check(b.position.y < 300.0 and b.end.y <= 421.0, "stalactites hang from their box's top (%s)" % b)

func _rock(parent: Node, r: Rect2, nm: String) -> void:
	var f := MDSFreeform.new()
	f.name = nm
	f.points = rect_points(r)
	f.smooth = false
	parent.add_child(f)

## Two screens wide: floor, ceiling, walls (left1 open), a save point.
func _room() -> MDSRoomPainter:
	var path := TMP + "/brief5_room.tscn"
	var root := Node2D.new()
	root.name = "Garden"
	var g := Node2D.new()
	g.name = "Freeform"
	root.add_child(g)
	_rock(g, Rect2(-96, 576, 2496, 168), "Floor")
	_rock(g, Rect2(-96, -96, 2496, 160), "Ceiling")
	_rock(g, Rect2(-96, 0, 160, 456), "LeftWall")
	_rock(g, Rect2(2240, 0, 160, 700), "RightWall")
	var save := Node2D.new()
	save.name = "SavePoint"
	save.position = Vector2(1500, 576)
	save.add_to_group(&"save_point", true)
	root.add_child(save)
	check(save_scene(root, path) == OK, "the garden room saves")
	root.free()
	return MDSRoomPainter.open(path, TileSet.new())

func _decorator() -> MDSFreeformDecorator:
	var d := MDSFreeformDecorator.new()
	d.stamp_set = load(STAMPS)
	d.hanging_category = "hanging"
	d.floor_categories = PackedStringArray(["moss", "fern"])
	d.leaf_category = "leaf"
	d.structure_kinds.append(MDSShapeGenerators.Kind.STALACTITES)
	d.structure_kinds.append(MDSShapeGenerators.Kind.MOUND)
	d.room_rects = [Rect2(0, 0, 2304, 648)]
	d.gates = [{"name": "left1", "pos": Vector2(0, 520), "side": "left"}]
	d.seed_value = 5
	d.density = 1.5
	return d

func _snapshot(painter: MDSRoomPainter) -> Array:
	var out: Array = []
	for g in MDSRoomPainter.ITEM_GROUPS:
		for item in painter.items(g):
			if item.has_meta(MDSFreeformDecorator.META):
				var d := MDSRoomPainter._item_data(item)
				d.erase("seed")
				out.append([g, String(item.name), var_to_str(d.get("points", d.get("transform")))])
	return out

func _decorate() -> void:
	var painter := _room()
	var d := _decorator()
	painter.checkpoint()
	var r := d.decorate(painter)
	check(r.hanging > 0 and r.plants > 0 and r.structures > 0 and r.foreground > 0, "every category is placed: %s" % r)
	var save_rect := MDSRoomObjects.visual_rect(painter.root.get_node("SavePoint"), painter.root)
	for p in d.placed:
		check(not p.rect.intersects(DOOR), "%s %s stays out of the doorway" % [p.kind, p.node.name])
		check(not p.rect.intersects(save_rect), "%s %s stays off the save point" % [p.kind, p.node.name])
		if p.node is MDSFreeform:
			check(MDSGeometry.is_simple(p.node.get_outline()), "%s is simple" % p.node.name)
			check(not p.node.is_collider(), "%s doesn't collide" % p.node.name)
	var first := _snapshot(painter)
	# Again, same seed: the same room (the earlier decoration is replaced, not doubled).
	painter.checkpoint()
	var again := _decorator().decorate(painter)
	check(again.removed == first.size(), "running it again replaces what it placed (%d of %d)" % [again.removed, first.size()])
	check(_snapshot(painter) == first, "the same seed gives the same decoration")
	# Saved and undone.
	painter.undo()
	painter.undo()
	check(_snapshot(painter).is_empty(), "undo takes the decoration out")
	painter.redo()
	check(painter.save() == OK, "the decorated room saves")
	painter.free_instance()
	var scene := (load_fresh(TMP + "/brief5_room.tscn") as PackedScene).instantiate()
	var tagged := scene.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.has_meta(MDSFreeformDecorator.META))
	check(tagged.size() == first.size(), "the saved scene keeps the decoration and its tags (%d)" % tagged.size())
	scene.free()

## The Freeform tool draws a generator's shape from a dragged box.
func _freeform_tool() -> void:
	var painter := _room()
	var world := MDSWorld.new()
	var id := world.add_room("Garden", Rect2(0, 0, 2304, 648), 0)
	var canvas := MDSRoomCanvas.new()
	canvas.size = Vector2(800, 400)
	add_child(canvas)
	canvas.open(world, id, painter)
	canvas.tool = MDSRoomCanvas.Tool.FREEFORM
	canvas.freeform_group = "FreeformBack"
	canvas.freeform_solid = false
	canvas.shape = MDSRoomCanvas.GENERATOR_BASE + MDSShapeGenerators.Kind.ARCH
	var before := painter.items("FreeformBack").size()
	canvas.paint_shape(Vector2i(10, 8), Vector2i(21, 17))
	var after := painter.items("FreeformBack")
	check(after.size() == before + 1, "dragging a box with Arch (broken) adds a shape")
	if after.size() == before + 1:
		var f: MDSFreeform = after[after.size() - 1]
		check(MDSGeometry.is_simple(f.get_outline()) and String(f.name).begins_with("Arch"), "it is a simple arch (%s)" % f.name)
		var b := MDSGeometry.bounds(f.get_outline())
		var ts := painter.tile_size().x
		check(b.position.x >= 10 * ts - 8.0 and b.end.x <= 22 * ts + 8.0 and b.size.x > 10 * ts, "it fills the dragged box (%s, tiles of %d px)" % [b, ts])
	canvas.close()
	canvas.queue_free()
	painter.free_instance()
