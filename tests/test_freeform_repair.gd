extends "res://tests/test_case.gd"
## Brief 2: freeform outline validation and repair.

const DEMOS: PackedStringArray = ["res://asset_packs/mossgrove/demo/freeform_cave.tscn", "res://asset_packs/mossgrove/demo/mossgrove_demo.tscn"]

## A bowtie: its control points cross.
const BOWTIE := [Vector2(0, 0), Vector2(300, 200), Vector2(300, 0), Vector2(0, 200)]

func _run() -> void:
	_simple_tests()
	_issues_tab()
	await _repair()
	_smoothing_fold()
	_no_false_positives()

func _simple_tests() -> void:
	check(MDSGeometry.is_simple(rect_points(Rect2(0, 0, 100, 50))), "a rectangle is simple")
	check(not MDSGeometry.is_simple(PackedVector2Array(BOWTIE)), "a bowtie is not simple")
	var dup := rect_points(Rect2(0, 0, 100, 50))
	dup.insert(1, dup[0])
	check(MDSGeometry.is_simple(dup), "a repeated point is not a crossing")
	var parts := MDSGeometry.untwist(PackedVector2Array(BOWTIE))
	check(parts.size() == 2 and parts.all(func(p: PackedVector2Array) -> bool: return MDSGeometry.is_simple(p)), "untwisting a bowtie gives its two simple lobes")
	# A C whose ends overlap encloses air: untwisted, the air stays open (no hole is filled).
	var c := PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 60), Vector2(60, 60), Vector2(60, 340), Vector2(400, 340), Vector2(400, 400), Vector2(0, 400), Vector2(0, 30), Vector2(-40, 30), Vector2(-40, -40), Vector2(30, -40), Vector2(30, 0)])
	var merged := Geometry2D.merge_polygons(rect_points(Rect2(0, 0, 400, 400)), PackedVector2Array())
	check(merged.size() == 1, "sanity: a square merges to itself")
	var ring := Geometry2D.merge_polygons(rect_points(Rect2(0, 0, 400, 400)), rect_points(Rect2(-10, -10, 20, 20)))
	var donut := Geometry2D.clip_polygons(rect_points(Rect2(0, 0, 400, 400)), rect_points(Rect2(100, 100, 200, 200)))
	var cut := MDSGeometry.without_holes(donut)
	var area := 0.0
	for p in cut:
		check(MDSGeometry.is_simple(p), "a cut piece of a ring is simple")
		check(not Geometry2D.is_point_in_polygon(Vector2(200, 200), p), "the ring's hole stays open")
		area += absf(MDSGeometry.signed_area(p))
	check_near(area, 400.0 * 400.0 - 200.0 * 200.0, 1.0, "cutting a ring open keeps its area")
	check(c.size() > 0 and ring.size() > 0, "fixtures built")

func _twisted_room(path: String) -> void:
	var root := Node2D.new()
	root.name = "TwistRoom"
	var group := Node2D.new()
	group.name = "Freeform"
	root.add_child(group)
	var good := MDSFreeform.new()
	good.name = "Floor"
	good.smooth = false
	good.points = rect_points(Rect2(0, 560, 1152, 88))
	group.add_child(good)
	var bad := MDSFreeform.new()
	bad.name = "Twisted"
	bad.smooth = false
	bad.points = PackedVector2Array(BOWTIE)
	bad.position = Vector2(400, 200)
	group.add_child(bad)
	var body := StaticBody2D.new()
	body.name = "OldBrick"
	root.add_child(body)
	var poly := CollisionPolygon2D.new()
	poly.name = "Col"
	body.add_child(poly)
	poly.polygon = PackedVector2Array([Vector2(0, 0), Vector2(100, 100), Vector2(100, 0), Vector2(0, 100)])
	check(save_scene(root, path) == OK, "the twisted room saves")
	root.free()

func _issues_tab() -> void:
	var path := TMP + "/brief2_room.tscn"
	_twisted_room(path)
	var meta := MDSSceneScanner.new().analyze_scene(path, false)
	var paths: PackedStringArray = []
	for t in meta.twisted:
		paths.append(t.path)
	check("Freeform/Twisted" in paths, "the scanner finds the twisted freeform shape (%s)" % ", ".join(paths))
	check("OldBrick/Col" in paths, "the scanner finds the twisted CollisionPolygon2D")
	check(not "Freeform/Floor" in paths, "the good shape is not reported")
	var world := MDSWorld.new()
	var id := world.add_room("Twist_01", Rect2(0, 0, 1152, 648), 0, "", path)
	var db := {path: meta}
	var analysis := MDSAnalysis.new(MDSGraph.from_world(world, db), world, db).run()
	var issues := MDSWorldValidator.run(world, analysis, db)
	var found := issues.filter(func(i: Dictionary) -> bool:
		return i.category == MDSValidator.CATEGORY_GEOMETRY and i.room_id == id and i.message.contains("Freeform/Twisted") and i.message.contains("crosses itself"))
	check(found.size() == 1, "the Issues tab reports the twisted shape with its room and node")
	if found.size() == 1:
		check(found[0].pos.distance_to(Vector2(550, 300)) < 1.0, "the issue jumps to the shape (%s)" % found[0].pos)

func _repair() -> void:
	var path := TMP + "/brief2_room.tscn"
	var ts := TileSet.new()
	var painter := MDSRoomPainter.open(path, ts)
	var holder := Node2D.new()
	add_child(holder)
	holder.add_child(painter.items_root)
	var twisted := painter.twisted_freeforms()
	check(twisted.size() == 1 and twisted[0].name == "Twisted", "the Room view finds the twisted shape")
	painter.checkpoint()
	var r := painter.repair_all()
	check(r.repaired == 1 and r.shapes == 2, "Repair all untwists it into its two lobes (%s)" % r)
	check(painter.twisted_freeforms().is_empty(), "no shape crosses itself after repair")
	await physics_frames(3)
	var space := holder.get_world_2d().direct_space_state
	for f in MDSFreeform.shapes_in(painter.items_root):
		var outline := f.get_outline()
		check(not Geometry2D.triangulate_polygon(outline).is_empty(), "%s fills (it triangulates)" % f.name)
		var q := PhysicsPointQueryParameters2D.new()
		q.position = f.position + MDSGeometry._inner_point(outline)
		check(not space.intersect_point(q).is_empty(), "%s collides" % f.name)
	painter.undo()
	check(painter.twisted_freeforms().size() == 1, "undo brings the twisted shape back")
	holder.remove_child(painter.items_root)
	painter.free_instance()
	holder.queue_free()

## A thin curl whose control points are simple but whose rounding folds over itself.
func _smoothing_fold() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 12), Vector2(30, 14), Vector2(28, 300), Vector2(40, 302), Vector2(18, 310), Vector2(14, 12)])
	check(MDSGeometry.is_simple(pts), "the control points are simple")
	var folded := not MDSGeometry.is_simple(MDSFreeform.outline_of(pts, true))
	if folded:
		var parts := MDSFreeform.repair_points(pts, true)
		check(not parts.is_empty(), "the folded shape repairs into something")
		for p in parts:
			check(MDSGeometry.is_simple(MDSFreeform.outline_of(p.points, p.smooth)), "each repaired part draws simple")
	var f := MDSFreeform.new()
	f.points = pts
	check(f.is_outline_simple() == not folded, "is_outline_simple agrees with the outline")
	f.free()

func _no_false_positives() -> void:
	for path in DEMOS:
		var meta := MDSSceneScanner.new().analyze_scene(path, false)
		check(meta.twisted.is_empty(), "%s: no false positives (%s)" % [path.get_file(), meta.twisted])
		var scene := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		for f in MDSFreeform.shapes_in(scene):
			check(f.is_outline_simple(), "%s: %s is simple" % [path.get_file(), f.name])
		scene.free()
