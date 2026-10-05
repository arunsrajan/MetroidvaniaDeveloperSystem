extends SceneTree
## Builds demo/sunken_garden_demo.tscn with the Metroidvania Developer System's own tools: an
## L-shaped room blocked out with straight-edged shapes goes through Convert to freeform
## (garden limestone, garden ledges), Decorate freeform (ivy, grass, flowers, ferns, ruined
## columns and arches, foreground leaves) and Fill outside shape (deep ground). It also writes
## backdrop/garden.backdrop.tres (the distance behind the room, made of the pack's stamps) and
## shows it behind the demo. Fixed seeds: a run always builds the same room.
##
##   godot --headless --path . --script res://asset_packs/sunken_gardens/tools/build_demo.gd

const PACK := "res://asset_packs/sunken_gardens"
## The room: two screens wide on top, one below on the left (the bottom right belongs to
## another room).
const RECTS: Array[Rect2] = [Rect2(0, 0, 2304, 648), Rect2(0, 648, 1152, 648)]

func _initialize() -> void:
	var backdrop := _backdrop()
	DirAccess.make_dir_recursive_absolute(PACK + "/backdrop")
	print("backdrop: ", error_string(ResourceSaver.save(backdrop, PACK + "/backdrop/garden.backdrop.tres")))
	var path := PACK + "/demo/sunken_garden_demo.tscn"
	var root := _blockout()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	var err := ResourceSaver.save(packed, path)
	if err != OK:
		push_error("Could not save %s (%d)" % [path, err])
		quit(1)
		return
	var painter := IDPRoomPainter.open(path, TileSet.new())
	var conv := IDPFreeformConverter.new()
	conv.rock_style = load(PACK + "/freeform/styles/garden_limestone.freeform.tres")
	conv.ledge_style = load(PACK + "/freeform/styles/garden_ledge.freeform.tres")
	conv.room_rects = RECTS
	conv.seed_value = 7
	conv.keep_old = false
	print("convert: ", conv.convert(painter))
	var deco := IDPFreeformDecorator.new()
	deco.stamp_set = load(PACK + "/freeform/sunken_gardens.stamps.tres")
	deco.hanging_category = "ivy"
	deco.floor_categories = PackedStringArray(["grass", "flower", "fern"])
	deco.structure_style = load(PACK + "/freeform/styles/sunken_ruin.freeform.tres")
	deco.leaf_category = "leaf_bg"
	deco.foreground_style = load(PACK + "/freeform/styles/garden_foreground.freeform.tres")
	deco.room_rects = RECTS
	deco.seed_value = 7
	print("decorate: ", deco.decorate(painter))
	print("outside: ", IDPNotchFill.fill(painter, RECTS, load(PACK + "/freeform/styles/sunken_deep.freeform.tres")))
	err = painter.save()
	painter.free_instance()
	print("saved %s: %s" % [path, error_string(err)])
	quit(0 if err == OK else 1)

func _shape(parent: Node, root: Node, shape_name: String, r: Rect2, ledge := false) -> void:
	var f := IDPFreeform.new()
	f.name = shape_name
	f.smooth = false
	f.points = IDPGeometry.rect_polygon(r)
	if ledge:
		f.set_collision_override(IDPFreeformStyle.Role.PLATFORM, true)
	parent.add_child(f)
	f.owner = root

## The garden's distance: a green-lit sky, a far canopy, hedges, ferns, and dark leaves passing
## in front.
func _backdrop() -> IDPBackdrop:
	var stamps := load(PACK + "/freeform/sunken_gardens.stamps.tres") as IDPStampSet
	var b := IDPBackdrop.new()
	b.display_name = "Sunken Gardens distance"
	b.sky = Gradient.new()
	b.sky.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	b.sky.colors = PackedColorArray([Color("#56703f"), Color("#2b3a22"), Color("#10170c")])
	var specs := [
		# category, depth, scale, offset, density, jitter, haze, haze color, desaturate, foreground
		["leaf_bg", 0.12, 2.4, Vector2(0, -120), 7.0, 320.0, 0.55, Color("#6e8a58"), 0.35, false],
		["silhouette", 0.3, 1.8, Vector2(0, 0), 9.0, 300.0, 0.4, Color("#4f6a3e"), 0.25, false],
		["fern", 0.55, 1.15, Vector2(0, 160), 12.0, 260.0, 0.5, Color("#3a4f2e"), 0.35, false],
		["silhouette", 1.35, 2.2, Vector2(0, 470), 1.2, 30.0, 0.0, Color.BLACK, 0.0, true],
	]
	var seed_value := 11
	for spec in specs:
		var l := IDPBackdropLayer.new()
		l.source = IDPBackdropLayer.Source.STAMPS
		l.stamp_set = stamps
		l.stamp_category = spec[0]
		l.depth = spec[1]
		l.scale = spec[2]
		l.offset = spec[3]
		l.stamp_density = spec[4]
		l.jitter = spec[5]
		l.haze = spec[6]
		l.haze_color = spec[7]
		l.desaturate = spec[8]
		l.foreground = spec[9]
		if l.foreground:
			l.tint = Color("#0c120a")
		l.seed_value = seed_value
		seed_value += 7
		b.layers.append(l)
	return b

## The blockout: rectangles of rock, three ledges climbing out of the lower part, the player.
func _blockout() -> Node2D:
	var root := Node2D.new()
	root.name = "SunkenGardenDemo"
	var distance := IDPBackdropView.new()
	distance.name = "Distance"
	distance.backdrop = load(PACK + "/backdrop/garden.backdrop.tres")
	distance.room_size = Vector2(2304, 1296)
	root.add_child(distance)
	distance.owner = root
	var g := Node2D.new()
	g.name = "Freeform"
	g.z_index = IDPRoomPainter.ITEM_GROUPS["Freeform"]
	root.add_child(g)
	g.owner = root
	_shape(g, root, "Ceiling", Rect2(0, 0, 2304, 96))
	_shape(g, root, "LeftWall", Rect2(0, 0, 96, 1296))
	_shape(g, root, "RightWall", Rect2(2208, 0, 96, 648))
	_shape(g, root, "UpperFloor", Rect2(1152, 552, 1152, 96))
	_shape(g, root, "UpperFloorLeft", Rect2(96, 552, 520, 96))
	_shape(g, root, "LowerFloor", Rect2(0, 1200, 1152, 96))
	_shape(g, root, "InnerWall", Rect2(1056, 648, 96, 648))
	_shape(g, root, "Step", Rect2(820, 1100, 236, 100))
	_shape(g, root, "LedgeLow", Rect2(520, 1010, 240, 24), true)
	_shape(g, root, "LedgeMid", Rect2(760, 860, 220, 24), true)
	_shape(g, root, "LedgeHigh", Rect2(640, 700, 240, 24), true)
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.position = Vector2(300, 1150)
	player.set_script(load(PACK + "/demo/demo_player.gd"))
	player.add_to_group(&"player", true)
	root.add_child(player)
	player.owner = root
	var body := Polygon2D.new()
	body.name = "Body"
	body.color = Color("#e8dcb4")
	body.polygon = PackedVector2Array([Vector2(-14, -32), Vector2(14, -32), Vector2(16, 30), Vector2(-16, 30)])
	player.add_child(body)
	body.owner = root
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 16
	capsule.height = 64
	cs.shape = capsule
	player.add_child(cs)
	cs.owner = root
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = 2304
	cam.limit_bottom = 1296
	cam.position_smoothing_enabled = true
	player.add_child(cam)
	cam.owner = root
	return root
