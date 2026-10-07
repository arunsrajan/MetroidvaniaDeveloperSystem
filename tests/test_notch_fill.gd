extends "res://tests/test_case.gd"
## Brief 7: fill outside an irregular room's shape.

const L_SHAPE := [Rect2(0, 0, 1152, 648), Rect2(0, 648, 576, 648)] # missing: bottom right
const J_SHAPE := [Rect2(0, 0, 1152, 648), Rect2(576, 648, 576, 648)] # missing: bottom left
const DEEP := "res://asset_packs/mossgrove/freeform/styles/deep_crystal.freeform.tres"

var host: SubViewport

func _run() -> void:
	host = SubViewport.new()
	host.disable_3d = true
	add_child(host)
	_polygons()
	_fill_and_update()
	_create_scene()
	host.queue_free()

func _covers(poly: PackedVector2Array, r: Rect2) -> bool:
	for p in [r.position + Vector2(4, 4), r.end - Vector2(4, 4), r.get_center(), Vector2(r.end.x - 4, r.position.y + 4), Vector2(r.position.x + 4, r.end.y - 4)]:
		if not Geometry2D.is_point_in_polygon(p, poly):
			return false
	return true

func _polygons() -> void:
	var polys := MDSNotchFill.outside_polygons(L_SHAPE)
	check(polys.size() == 1, "an L-shaped room has one area outside its shape (%d)" % polys.size())
	if polys.size() == 1:
		check(_covers(polys[0], Rect2(576, 648, 576, 648)), "it covers the missing quarter")
		check(not Geometry2D.is_point_in_polygon(Vector2(300, 1000), polys[0]) and not Geometry2D.is_point_in_polygon(Vector2(800, 300), polys[0]), "it leaves the room alone")
		var b := MDSGeometry.bounds(polys[0])
		check(b.end.x == 1152 + MDSNotchFill.MARGIN and b.end.y == 1296 + MDSNotchFill.MARGIN, "it runs on past the box's edges (%s)" % b)
		check(b.position.x == 576 and b.position.y == 648, "its inner edges follow the room's shape")
	check(MDSNotchFill.outside_polygons([Rect2(0, 0, 1152, 648)]).is_empty(), "a rectangular room has nothing outside")
	var u := MDSNotchFill.outside_polygons([Rect2(0, 0, 400, 648), Rect2(400, 0, 352, 200), Rect2(752, 0, 400, 648)])
	check(u.size() == 1 and _covers(u[0], Rect2(400, 200, 352, 448)), "a U-shaped room's notch is filled")

func _room() -> String:
	var path := TMP + "/brief7_room.tscn"
	var root := Node2D.new()
	root.name = "LRoom"
	var floor_shape := MDSFreeform.new()
	floor_shape.name = "Floor"
	floor_shape.smooth = false
	floor_shape.points = rect_points(Rect2(-96, 1240, 768, 160))
	root.add_child(floor_shape)
	var top := MDSFreeform.new()
	top.name = "TopFloor"
	top.smooth = false
	top.points = rect_points(Rect2(576, 600, 672, 120))
	root.add_child(top)
	check(save_scene(root, path) == OK, "the L room saves")
	root.free()
	return path

func _fill_and_update() -> void:
	var path := _room()
	var painter := MDSRoomPainter.open(path, TileSet.new())
	var style := load(DEEP) as MDSFreeformStyle
	check(style.get_role() == MDSFreeformStyle.Role.TERRAIN and style.solid, "sanity: the deep style is a solid terrain style")
	painter.checkpoint()
	check(MDSNotchFill.fill(painter, L_SHAPE, style) == 1, "Fill outside shape adds one shape to the L room")
	var shapes := MDSNotchFill.shapes_of(painter)
	check(shapes.size() == 1, "the fill shape is found again")
	if shapes.size() == 1:
		var f := shapes[0]
		check(f.get_parent().name == "Freeform", "it is in the Freeform group, over the rock's edges")
		check(not f.is_collider() and f.get_role() == MDSFreeformStyle.Role.DECOR, "it never collides, whatever its style (a decoration)")
		check(_covers(f.get_outline(), Rect2(576, 648, 576, 648)), "it covers the missing quarter")
	check(not MDSNotchFill.is_stale(painter, L_SHAPE) and MDSNotchFill.is_stale(painter, J_SHAPE), "it knows the shape it was made for")
	# A passage from the room into the filled area still lets the player through.
	var c := MDSRoomCheck.new()
	c.room_rects.assign(L_SHAPE)
	c.passages = [{"name": "right2", "pos": Vector2(576, 1180), "side": "right"}]
	c.build_from_painter(painter, host)
	c.run()
	check(not c.issues.any(func(i: Dictionary) -> bool: return i.kind == "passage"), "a passage into the filled area is open: %s" % [c.issues.map(func(i: Dictionary) -> String: return i.message)])
	c.free_proxy()
	# The room changes shape on the map: running it again moves the fill.
	painter.checkpoint()
	check(MDSNotchFill.fill(painter, J_SHAPE, style) == 1, "running it again after a shape change makes one shape")
	shapes = MDSNotchFill.shapes_of(painter)
	check(shapes.size() == 1 and _covers(shapes[0].get_outline(), Rect2(0, 648, 576, 648)) and not Geometry2D.is_point_in_polygon(Vector2(800, 1000), shapes[0].get_outline()), "the fill follows the new shape")
	check(painter.save() == OK, "the room saves")
	painter.free_instance()
	var meta := MDSSceneScanner.new().analyze_scene(path, false)
	check(meta.content_rect.position.y >= 600.0 - 1.0, "the map silhouette ignores the fill (%s)" % meta.content_rect)
	var scene := (load_fresh(path) as PackedScene).instantiate()
	var saved := scene.get_node_or_null("Freeform/OutsideShape") as MDSFreeform
	check(saved != null and saved.has_meta(MDSNotchFill.META) and not saved.is_collider(), "the saved fill keeps its settings")
	scene.free()

func _create_scene() -> void:
	var world := MDSWorld.new()
	var id := world.add_room("Notched", Rect2(0, 0, 1152, 648), 0)
	world.add_rect(id, Rect2(0, 648, 576, 648))
	world.set_setting("notch_fill_style", DEEP)
	var path := TMP + "/brief7_created.tscn"
	check(MDSWorldSceneTools.create_scene_for_room(world, id, path) == OK, "Create scene works")
	var scene := (load_fresh(path) as PackedScene).instantiate()
	var f := scene.get_node_or_null("Freeform/OutsideShape") as MDSFreeform
	check(f != null and not f.is_collider() and _covers(f.get_outline(), Rect2(576, 648, 576, 648)), "Create scene fills the notch with the world's notch fill style")
	scene.free()
