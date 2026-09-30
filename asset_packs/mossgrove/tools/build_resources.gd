extends SceneTree
## Builds the pack's Godot resources from pack.json and the PNGs, wherever the pack folder
## sits in the project:
##   mossgrove_tileset.tres   terrains (autotiling, collision) + decorations (idp_kind tags)
##   frames/*.tres            SpriteFrames for the player, enemies and effects
##   demo/mossgrove_demo.tscn a small level with parallax, the player, enemies and props
##   freeform/*.freeform.tres  styles for IDP's freeform terrain (needs the IDP addon)
##   freeform/mossgrove.stamps.tres  clumps for IDP's Stamps tool and the styles' edges
##
## Run from the project folder (after the editor has imported the PNGs):
##   godot --headless --script res://asset_packs/mossgrove/tools/build_resources.gd

var root_dir := ""
var pack: Dictionary

func _init() -> void:
	root_dir = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	pack = JSON.parse_string(FileAccess.get_file_as_string(root_dir.path_join("pack.json")))
	var tiles := build_tileset()
	ResourceSaver.save(tiles, root_dir.path_join("mossgrove_tileset.tres"))
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("frames"))
	for sprite_name in pack.sprites:
		ResourceSaver.save(build_frames(pack.sprites[sprite_name]), root_dir.path_join("frames/%s_frames.tres" % sprite_name))
	if pack.has("freeform") and _has_class("IDPFreeformStyle"):
		build_freeform()
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("demo"))
	var demo := build_demo(load(root_dir.path_join("mossgrove_tileset.tres")))
	var packed := PackedScene.new()
	packed.pack(demo)
	ResourceSaver.save(packed, root_dir.path_join("demo/mossgrove_demo.tscn"))
	demo.free()
	print("Mossgrove resources built in ", root_dir)
	quit()

func _has_class(n: String) -> bool:
	for c in ProjectSettings.get_global_class_list():
		if c.class == n:
			return true
	return false

# --- Freeform styles and stamps (IDP) ----------------------------------------------------------

func build_freeform() -> void:
	var ff: Dictionary = pack.freeform
	var stamps: Resource = load("res://addons/InteractiveDevPanel/nodes/idp_stamp_set.gd").new()
	stamps.display_name = "Mossgrove clumps"
	stamps.texture = tex(ff.clumps.texture)
	var regions: Array[Rect2] = []
	var cats := PackedStringArray()
	var anchors := PackedVector2Array()
	for it in ff.clumps.items:
		regions.append(Rect2(it.region[0], it.region[1], it.region[2], it.region[3]))
		cats.append(it.category)
		anchors.append(Vector2(it.anchor[0], it.anchor[1]))
	stamps.regions = regions
	stamps.categories = cats
	stamps.anchors = anchors
	ResourceSaver.save(stamps, root_dir.path_join("freeform/mossgrove.stamps.tres"))
	stamps = load(root_dir.path_join("freeform/mossgrove.stamps.tres"))
	var style_script: Script = load("res://addons/InteractiveDevPanel/nodes/idp_freeform_style.gd")
	var specs := {
		"mossy_rock": {"display_name": "Mossy rock", "fill": "rock", "outline_color": Color("#080b10"), "outline_width": 3.0,
			"top": "moss", "top_width": 58.0, "top_inset": 4.0, "top_angle": 78.0, "bottom": "under", "bottom_width": 40.0, "bottom_inset": 2.0,
			"top_clumps": "moss", "bottom_clumps": "hanging", "clump_spacing": 85.0, "clump_scale": Vector2(0.5, 0.95)},
		"pale_shell": {"display_name": "Pale shell", "fill": "shell", "outline_color": Color("#221e2a"), "outline_width": 3.0,
			"top": "shell", "top_width": 26.0, "top_inset": 3.0, "bottom": "under", "bottom_width": 34.0, "bottom_inset": 2.0},
		"deep_crystal": {"display_name": "Deep crystal rock", "fill": "deep", "outline_color": Color("#030409"), "outline_width": 3.0,
			"top": "crystal", "top_width": 40.0, "top_inset": 4.0, "bottom": "under", "bottom_width": 34.0, "bottom_inset": 2.0},
		"jungle_foliage": {"display_name": "Jungle foliage (background)", "fill": "foliage", "outline_width": 0.0,
			"top": "foliage", "top_width": 56.0, "top_inset": 8.0, "top_angle": 80.0, "solid": false, "default_layer": "back",
			"top_clumps": "bubble_bg", "clump_spacing": 150.0, "clump_scale": Vector2(0.7, 1.1)},
		"foreground_silhouette": {"display_name": "Foreground silhouette", "fill": "silhouette", "outline_width": 0.0,
			"top": "silhouette", "top_width": 48.0, "top_inset": 4.0, "top_angle": 89.0, "solid": false, "default_layer": "front",
			"top_clumps": "silhouette", "clump_spacing": 130.0, "clump_scale": Vector2(0.8, 1.3)},
	}
	DirAccess.make_dir_recursive_absolute(root_dir.path_join("freeform/styles"))
	for key in specs:
		var sp: Dictionary = specs[key]
		var st: Resource = style_script.new()
		st.display_name = sp.display_name
		st.fill_texture = tex(ff.fills[sp.fill])
		for k in ["outline_color", "outline_width", "top_width", "top_inset", "top_angle", "bottom_width", "bottom_inset", "top_clumps", "bottom_clumps", "clump_spacing", "clump_scale", "solid", "default_layer"]:
			if sp.has(k):
				st.set(k, sp[k])
		if sp.has("top"):
			st.top_texture = tex(ff.edges[sp.top])
		if sp.has("bottom"):
			st.bottom_texture = tex(ff.edges[sp.bottom])
		if sp.has("top_clumps") or sp.has("bottom_clumps"):
			st.stamp_set = stamps
		ResourceSaver.save(st, root_dir.path_join("freeform/styles/%s.freeform.tres" % key))

func tex(path: String) -> Texture2D:
	return load(root_dir.path_join(path))

# --- TileSet ------------------------------------------------------------------------------------

func build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.add_physics_layer()
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "idp_kind")
	ts.set_custom_data_layer_type(0, TYPE_STRING)
	var terrain_src := TileSetAtlasSource.new()
	terrain_src.resource_name = "Mossgrove terrain"
	terrain_src.texture = tex("tiles/terrain.png")
	terrain_src.texture_region_size = Vector2i(32, 32)
	ts.add_source(terrain_src, 0)
	var sides := [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE]
	var colors := [Color("#58a83e"), Color("#d8ccb8"), Color("#4fd6c8"), Color("#2c4555")]
	var solid_square := PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	for i in pack.terrains.size():
		var t: Dictionary = pack.terrains[i]
		ts.add_terrain_set()
		ts.set_terrain_set_mode(i, TileSet.TERRAIN_MODE_MATCH_SIDES)
		ts.add_terrain(i)
		ts.set_terrain_name(i, 0, t.name)
		ts.set_terrain_color(i, 0, colors[i % colors.size()])
		var col0 := int(t.column)
		var cells: Array = []
		for m in 16:
			cells.append([Vector2i(col0 + m % 4, m / 4), m, 1.0])
		for v in 4:
			cells.append([Vector2i(col0 + 4, v), 15, 0.3]) # fill variants, used now and then
		for c in cells:
			terrain_src.create_tile(c[0])
			var td := terrain_src.get_tile_data(c[0], 0)
			td.terrain_set = i
			td.terrain = 0
			for b in 4:
				td.set_terrain_peering_bit(sides[b], 0 if int(c[1]) & (1 << b) else -1)
			td.probability = c[2]
			td.set_custom_data("idp_kind", "rock" if t.solid else "wall")
			if t.solid:
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, solid_square)
	var decor_src := TileSetAtlasSource.new()
	decor_src.resource_name = "Mossgrove decor"
	decor_src.texture = tex("tiles/decor.png")
	decor_src.texture_region_size = Vector2i(32, 32)
	ts.add_source(decor_src, 1)
	for d in pack.decor:
		var coords := Vector2i(int(d.coords[0]), int(d.coords[1]))
		decor_src.create_tile(coords)
		decor_src.get_tile_data(coords, 0).set_custom_data("idp_kind", d.kind)
	return ts

# --- Sprites --------------------------------------------------------------------------------------

func build_frames(spec: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	var atlas := tex(spec.texture)
	for anim in spec.animations:
		var a: Dictionary = spec.animations[anim]
		sf.add_animation(anim)
		sf.set_animation_speed(anim, a.fps)
		sf.set_animation_loop(anim, a.loop)
		for r in a.frames:
			var at := AtlasTexture.new()
			at.atlas = atlas
			at.region = Rect2(r[0], r[1], r[2], r[3])
			sf.add_frame(anim, at)
	return sf

## An AnimatedSprite2D whose origin is the character's feet (or its center for effects).
func sprite(sprite_name: String, anim: String) -> AnimatedSprite2D:
	var spec: Dictionary = pack.sprites[sprite_name]
	var s := AnimatedSprite2D.new()
	s.name = sprite_name.capitalize().replace(" ", "")
	s.sprite_frames = load(root_dir.path_join("frames/%s_frames.tres" % sprite_name))
	s.animation = anim
	s.autoplay = anim
	s.centered = false
	s.offset = -Vector2(spec.origin[0], spec.origin[1])
	return s

# --- Demo scene -------------------------------------------------------------------------------------

const LEVEL := [
	"########################################",
	"##......####..........#####......#######",
	"#........##............###..........####",
	"#......................................#",
	"#......................................#",
	"#..........................ssss........#",
	"#..........######.......................",
	"#.........########.....................#",
	"#......................................#",
	"#.............................dddd.....#",
	"#....####..............................#",
	"#...######...........................###",
	"#..................#####............####",
	"##................#######.........######",
	"########################################",
	"########################################",
	"########################################",
]

func build_demo(ts: TileSet) -> Node2D:
	var root := Node2D.new()
	root.name = "MossgroveDemo"
	var bg := Node2D.new()
	bg.name = "Parallax"
	root.add_child(bg)
	bg.owner = root
	for p in pack.parallax:
		var layer := Parallax2D.new()
		layer.name = String(p.texture).get_file().get_basename().capitalize().replace(" ", "")
		layer.scroll_scale = Vector2(p.scroll_scale, p.scroll_scale)
		layer.repeat_size = Vector2(1920 * 0.7, 0)
		layer.repeat_times = 3
		# Behind the Background tile layer (z -10), except the foreground layer.
		layer.z_index = 20 if float(p.scroll_scale) > 1.0 else -30 + bg.get_child_count()
		var spr := Sprite2D.new()
		spr.texture = tex(p.texture)
		spr.centered = false
		spr.scale = Vector2(0.7, 0.7)
		spr.position = Vector2(0, -60)
		layer.add_child(spr)
		bg.add_child(layer)
		layer.owner = root
		spr.owner = root
	var layers := {}
	for n in ["Background", "Terrain", "Decor"]:
		var l := TileMapLayer.new()
		l.name = n
		l.tile_set = ts
		l.z_index = {"Background": -10, "Terrain": 0, "Decor": 5}[n]
		root.add_child(l)
		l.owner = root
		layers[n] = l
	var solid: Array[Vector2i] = []
	var shell: Array[Vector2i] = []
	var deep: Array[Vector2i] = []
	var wall: Array[Vector2i] = []
	for y in LEVEL.size():
		for x in LEVEL[y].length():
			var c := Vector2i(x, y)
			match LEVEL[y][x]:
				"#":
					solid.append(c)
				"s":
					shell.append(c)
				"d":
					deep.append(c)
			if y >= 8 and (x < 12 or x > 26):
				wall.append(c)
	layers.Background.set_cells_terrain_connect(wall, 3, 0)
	layers.Terrain.set_cells_terrain_connect(solid, 0, 0)
	layers.Terrain.set_cells_terrain_connect(shell, 1, 0)
	layers.Terrain.set_cells_terrain_connect(deep, 2, 0)
	# Decorations: plants on floors, moss, vines and stalactites under ceilings.
	var kinds := {}
	for d in pack.decor:
		if not kinds.has(d.kind):
			kinds[d.kind] = []
		kinds[d.kind].append(Vector2i(int(d.coords[0]), int(d.coords[1])))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var terrain: TileMapLayer = layers.Terrain
	for c in terrain.get_used_cells():
		var up := c + Vector2i.UP
		var down := c + Vector2i.DOWN
		if terrain.get_cell_source_id(up) == -1 and up.y >= 0:
			var roll := rng.randf()
			var kind := "grass" if roll < 0.45 else ("fern" if roll < 0.58 else ("flower" if roll < 0.66 else ("mushroom" if roll < 0.72 else "")))
			if kind != "":
				layers.Decor.set_cell(up, 1, kinds[kind][rng.randi_range(0, kinds[kind].size() - 1)])
		if terrain.get_cell_source_id(down) == -1 and down.y < LEVEL.size():
			var roll := rng.randf()
			if roll < 0.12:
				layers.Decor.set_cell(down, 1, kinds.vine_top[0])
				var vine_len := rng.randi_range(1, 3)
				for k in vine_len:
					if terrain.get_cell_source_id(down + Vector2i(0, k + 1)) != -1:
						break
					layers.Decor.set_cell(down + Vector2i(0, k + 1), 1, kinds.vine_mid[k % kinds.vine_mid.size()])
				layers.Decor.set_cell(down + Vector2i(0, vine_len + 1), 1, kinds.vine_end[0])
			elif roll < 0.3:
				var kind: String = ["stalactite_small", "stalactite_large", "hanging_moss", "hanging_moss"][rng.randi_range(0, 3)]
				layers.Decor.set_cell(down, 1, kinds[kind][rng.randi_range(0, kinds[kind].size() - 1)])
	# Characters, enemies, props and a camera.
	var things := [
		["player", "idle", Vector2(6 * 32, 14 * 32)],
		["crawler", "walk", Vector2(22 * 32, 12 * 32)],
		["moth", "fly", Vector2(30 * 32, 6 * 32)],
	]
	for t in things:
		var s := sprite(t[0], t[1])
		s.position = t[2]
		root.add_child(s)
		s.owner = root
	var props := [["bench", Vector2(10 * 32, 14 * 32)], ["lamp", Vector2(14 * 32, 14 * 32)], ["sign", Vector2(3 * 32, 14 * 32)], ["shell_pile", Vector2(33 * 32, 14 * 32)], ["breakable_wall", Vector2(38 * 32, 14 * 32)]]
	for p in props:
		var spr := Sprite2D.new()
		spr.name = String(p[0]).capitalize().replace(" ", "")
		spr.texture = tex(pack.props[p[0]].texture)
		spr.centered = false
		spr.offset = -Vector2(pack.props[p[0]].size[0] / 2.0, pack.props[p[0]].size[1] - 2)
		spr.position = p[1]
		spr.z_index = -1
		root.add_child(spr)
		spr.owner = root
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.position = Vector2(20 * 32, 8.5 * 32)
	root.add_child(cam)
	cam.owner = root
	return root
