extends "res://tests/test_case.gd"
## Brief 1: collision settings and roles on freeform styles.

const PLATFORM_LAYER := 4

func _run() -> void:
	_defaults()
	await _one_way_jump()
	_survives_edit_undo_save()
	_scanner_roles()

func _defaults() -> void:
	var st := IDPFreeformStyle.new()
	check(st.get_role() == IDPFreeformStyle.Role.TERRAIN and st.collision_layer == 1 and st.collision_mask == 1 and not st.is_one_way(), "a new style is terrain on layer 1, mask 1, two-way")
	var old := load("res://asset_packs/mossgrove/freeform/styles/mossy_rock.freeform.tres") as IDPFreeformStyle
	check(old != null and old.get_role() == IDPFreeformStyle.Role.TERRAIN and old.collision_layer == 1 and not old.is_one_way(), "an older .freeform.tres loads with today's behaviour")
	var legacy := IDPFreeformStyle.new()
	legacy.set_meta(&"one_way_platform", true)
	check(legacy.get_role() == IDPFreeformStyle.Role.PLATFORM and legacy.is_one_way(), "the one_way_platform metadata of older ledge styles still makes a one-way platform")
	check(legacy.get_list_name().contains("platform") and legacy.get_list_name().contains("one-way"), "the style list shows the role (%s)" % legacy.get_list_name())

func _ledge_style() -> IDPFreeformStyle:
	var st := IDPFreeformStyle.new()
	st.display_name = "Ledge"
	st.role = IDPFreeformStyle.Role.PLATFORM
	st.one_way = true
	st.collision_layer = PLATFORM_LAYER
	st.collision_mask = 2
	return st

func _shape(points: PackedVector2Array, st: IDPFreeformStyle) -> IDPFreeform:
	var f := IDPFreeform.new()
	f.style = st
	f.smooth = false
	f.points = points
	return f

## A body standing under a one-way ledge jumps up through it and lands on its top; under a
## two-way slab it bumps its head and falls back.
func _one_way_jump() -> void:
	var world := Node2D.new()
	add_child(world)
	var ground := _shape(rect_points(Rect2(-400, 200, 800, 100)), IDPFreeformStyle.new())
	world.add_child(ground)
	var ledge := _shape(rect_points(Rect2(-150, 0, 300, 24)), _ledge_style())
	world.add_child(ledge)
	var bodies := ledge.get_children(true).filter(func(n: Node) -> bool: return n is StaticBody2D)
	check(bodies.size() == 1, "the ledge has one body")
	if bodies.size() == 1:
		var body: StaticBody2D = bodies[0]
		check(body.collision_layer == PLATFORM_LAYER and body.collision_mask == 2, "the body is on the style's layer and mask")
		var poly := body.get_child(0) as CollisionPolygon2D
		check(poly.one_way_collision and is_equal_approx(poly.one_way_collision_margin, 16.0), "the collision polygon is one-way")
	var plats := IDPFreeform.platforms_in(world)
	check(plats.size() == 1 and plats[0] == ledge, "platforms_in finds the ledge")
	var terr := IDPFreeform.terrain_in(world)
	check(terr.size() == 1 and terr[0] == ground, "terrain_in finds the ground")
	await physics_frames(2)
	var landed := await _jump(world, 1 | PLATFORM_LAYER)
	check_near(landed.y, -30.0, 2.0, "the body jumped up through the ledge and stands on its top")
	# The same slab as two-way terrain: the jump is stopped by it.
	ledge.override_collision = true
	ledge.role = IDPFreeformStyle.Role.TERRAIN
	ledge.collision_layer = PLATFORM_LAYER
	ledge.one_way = false
	ledge.rebuild()
	await physics_frames(2)
	var blocked := await _jump(world, 1 | PLATFORM_LAYER)
	check_near(blocked.y, 170.0, 2.0, "a two-way override blocks the jump (the body ends on the ground)")
	world.queue_free()

## Jumps from the ground under the ledge; returns where the body comes to rest.
func _jump(world: Node2D, mask: int) -> Vector2:
	var body := CharacterBody2D.new()
	body.collision_layer = 2
	body.collision_mask = mask
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 60)
	cs.shape = rect
	body.add_child(cs)
	world.add_child(body)
	body.global_position = Vector2(0, 168)
	for i in 10:
		body.velocity.y += 15.0
		body.move_and_slide()
		await get_tree().physics_frame
	body.velocity.y = -700.0
	for i in 150:
		body.velocity.y += 15.0
		body.move_and_slide()
		await get_tree().physics_frame
	var p := body.global_position
	body.queue_free()
	return p

## The override and the style's settings survive Room view edits, undo and save.
func _survives_edit_undo_save() -> void:
	var path := TMP + "/brief1_room.tscn"
	var root := Node2D.new()
	root.name = "Room"
	var group := Node2D.new()
	group.name = "Freeform"
	root.add_child(group)
	var f := _shape(rect_points(Rect2(0, 0, 200, 30)), IDPFreeformStyle.new())
	f.name = "Ledge"
	f.set_collision_override(IDPFreeformStyle.Role.PLATFORM, true, PLATFORM_LAYER)
	group.add_child(f)
	check(save_scene(root, path) == OK, "the test room saves")
	root.free()
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	var painter := IDPRoomPainter.open(path, ts)
	var item: IDPFreeform = painter.items("Freeform")[0]
	check(item.is_platform() and item.is_one_way() and item.get_body_layer() == PLATFORM_LAYER, "the Room view's copy keeps the override")
	painter.checkpoint()
	var pts := item.points
	pts[0] += Vector2(-20, 0)
	item.points = pts
	painter.undo()
	item = painter.items("Freeform")[0]
	check(item.is_platform() and item.is_one_way() and item.get_body_layer() == PLATFORM_LAYER, "the override survives undo")
	check(item.points[0] == Vector2(0, 0), "undo restored the points (%s)" % item.points)
	painter.redo()
	check(painter.save() == OK, "the room saves")
	painter.free_instance()
	var again := (load_fresh(path) as PackedScene).instantiate()
	var saved := again.get_node("Freeform/Ledge") as IDPFreeform
	check(saved and saved.is_platform() and saved.is_one_way() and saved.get_body_layer() == PLATFORM_LAYER, "the override survives saving")
	check(saved and saved.points[0] == Vector2(-20, 0), "the edit was saved")
	again.free()

## The map silhouette is terrain only; platforms are listed; decorations are ignored.
func _scanner_roles() -> void:
	var path := TMP + "/brief1_scan.tscn"
	var root := Node2D.new()
	root.name = "Room"
	var ground := _shape(rect_points(Rect2(0, 600, 1152, 48)), IDPFreeformStyle.new())
	ground.name = "Ground"
	root.add_child(ground)
	var ledge := _shape(rect_points(Rect2(400, 300, 200, 24)), _ledge_style())
	ledge.name = "Ledge"
	root.add_child(ledge)
	var deco := _shape(rect_points(Rect2(0, 0, 100, 100)), IDPFreeformStyle.new())
	deco.name = "Deep"
	deco.set_collision_override(IDPFreeformStyle.Role.DECOR, false)
	root.add_child(deco)
	check(not deco.is_collider(), "a decoration has no body")
	check(save_scene(root, path) == OK, "the scan test room saves")
	root.free()
	var meta := IDPSceneScanner.new().analyze_scene(path, false)
	check(meta.content_rect == Rect2(0, 600, 1152, 48), "only terrain counts toward the silhouette (%s)" % meta.content_rect)
	check(meta.platforms.size() == 1 and meta.platforms[0].name == "Ledge" and meta.platforms[0].one_way, "the ledge is reported as a one-way platform")
