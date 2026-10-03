@tool
class_name IDPTilesetFactory
extends RefCounted
## Generates a starter pixel-art tileset ("mossy cave") so rooms can be painted before any
## art exists. Pixels are drawn at 16 px and scaled 2x (32 px tiles).
##
## Atlas layout (32 px tiles, 8 columns):
## - rows 0-1: "Rock" terrain (terrain set 0), 16 tiles indexed by connected sides
##   (1 = right, 2 = bottom, 4 = left, 8 = top). Exposed tops get moss. Solid collision.
## - rows 2-3: "Cave wall" terrain (terrain set 1) for the Background layer.
## - row 4: foliage x4 (background), grass, fern, flower, mushroom.
## - row 5: vine top, vine middle, vine end, small stalactite, large stalactite, hanging moss.
## Decoration tiles carry an "idp_kind" custom data string used by auto-decorate.

const PX := 16
const SCALE := 2
const TILE := PX * SCALE
const COLS := 8
const ROWS := 6

const TERRAIN_ROCK := Vector2i(0, 0) ## terrain set, terrain
const TERRAIN_WALL := Vector2i(1, 0)
const FOLIAGE: Array[Vector2i] = [Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)]
const DECOR := {
	"grass": Vector2i(4, 4), "fern": Vector2i(5, 4), "flower": Vector2i(6, 4), "mushroom": Vector2i(7, 4),
	"vine_top": Vector2i(0, 5), "vine_mid": Vector2i(1, 5), "vine_end": Vector2i(2, 5),
	"stalactite_small": Vector2i(3, 5), "stalactite_large": Vector2i(4, 5), "hanging_moss": Vector2i(5, 5),
}

# Palette (close to lush cave pixel art: gray-blue stone, bright moss, teal depths).
const ROCK_DARK := Color("#1b1d24")
const ROCK := Color("#2c3039")
const STONE := Color("#4d5361")
const STONE_LIGHT := Color("#7b8394")
const MOSS_DARK := Color("#1f4a16")
const MOSS := Color("#3f8a22")
const MOSS_LIGHT := Color("#79c43a")
const MOSS_TIP := Color("#c4ef62")
const WALL := Color("#0f2826")
const WALL_LIGHT := Color("#173a35")
const LEAF_DARK := Color("#0f2f2a")
const LEAF := Color("#1b4f43")
const LEAF_LIGHT := Color("#2c7560")

## Creates (or loads) the starter tileset at [param path] (.tres, texture embedded).
static func get_or_create(path := "res://idp_tiles/idp_cave_tileset.tres") -> TileSet:
	if ResourceLoader.exists(path):
		var existing := load(path) as TileSet
		if existing:
			return existing
	var ts := build_tileset()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(ts, path)
	# Also drop the atlas as a PNG next to it, for artists to repaint.
	build_image().save_png(path.get_basename() + ".png")
	return load(path) as TileSet if ResourceLoader.exists(path) else ts

static func build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "idp_kind")
	ts.set_custom_data_layer_type(0, TYPE_STRING)
	ts.add_terrain_set()
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_SIDES)
	ts.add_terrain(0)
	ts.set_terrain_name(0, 0, "Rock")
	ts.set_terrain_color(0, 0, MOSS)
	ts.add_terrain_set()
	ts.set_terrain_set_mode(1, TileSet.TERRAIN_MODE_MATCH_SIDES)
	ts.add_terrain(1)
	ts.set_terrain_name(1, 0, "Cave wall")
	ts.set_terrain_color(1, 0, WALL_LIGHT)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(build_image())
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var sides := [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE]
	var half := TILE / 2.0
	for m in 16:
		for terrain_set in 2:
			var coords := Vector2i(m % COLS, m / COLS + terrain_set * 2)
			src.create_tile(coords)
			var td := src.get_tile_data(coords, 0)
			td.terrain_set = terrain_set
			td.terrain = 0
			for i in 4:
				if m & (1 << i):
					td.set_terrain_peering_bit(sides[i], 0)
			td.set_custom_data("idp_kind", "rock" if terrain_set == 0 else "wall")
			if terrain_set == 0:
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]))
	for i in FOLIAGE.size():
		src.create_tile(FOLIAGE[i])
		src.get_tile_data(FOLIAGE[i], 0).set_custom_data("idp_kind", "foliage")
	for kind in DECOR:
		src.create_tile(DECOR[kind])
		src.get_tile_data(DECOR[kind], 0).set_custom_data("idp_kind", kind)
	return ts

# --- Pixel art ------------------------------------------------------------------------------

static func build_image() -> Image:
	var img := Image.create(COLS * PX, ROWS * PX, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for m in 16:
		_rock_tile(img, Vector2i(m % COLS, m / COLS) * PX, m, 100 + m)
		_wall_tile(img, Vector2i(m % COLS, m / COLS + 2) * PX, m, 200 + m)
	for i in 4:
		_foliage_tile(img, FOLIAGE[i] * PX, 300 + i)
	_grass(img, DECOR.grass * PX, 401)
	_fern(img, DECOR.fern * PX, 402)
	_flower(img, DECOR.flower * PX, 403)
	_mushroom(img, DECOR.mushroom * PX, 404)
	_vine(img, DECOR.vine_top * PX, 0, 405)
	_vine(img, DECOR.vine_mid * PX, 1, 406)
	_vine(img, DECOR.vine_end * PX, 2, 407)
	_stalactite(img, DECOR.stalactite_small * PX, 7, 408)
	_stalactite(img, DECOR.stalactite_large * PX, 14, 409)
	_hanging_moss(img, DECOR.hanging_moss * PX, 410)
	img.resize(COLS * TILE, ROWS * TILE, Image.INTERPOLATE_NEAREST)
	return img

static func _px(img: Image, o: Vector2i, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < PX and y < PX:
		img.set_pixel(o.x + x, o.y + y, c)

static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

## Stone-filled rock. [param m] bits: 1 right, 2 bottom, 4 left, 8 top = connected.
static func _rock_tile(img: Image, o: Vector2i, m: int, s: int) -> void:
	var r := _rng(s)
	for y in PX:
		for x in PX:
			_px(img, o, x, y, ROCK)
	# Stones.
	for i in 5:
		var cx := r.randi_range(1, PX - 2)
		var cy := r.randi_range(1, PX - 2)
		var rx := r.randi_range(2, 3)
		var ry := r.randi_range(1, 2)
		for y in range(-ry - 1, ry + 2):
			for x in range(-rx - 1, rx + 2):
				var d := pow(float(x) / (rx + 0.5), 2) + pow(float(y) / (ry + 0.5), 2)
				if d <= 1.0:
					_px(img, o, cx + x, cy + y, STONE if d > 0.35 or y > 0 else STONE_LIGHT)
				elif d <= 1.5:
					_px(img, o, cx + x, cy + y, ROCK_DARK)
	var top := m & 8 == 0
	var bottom := m & 2 == 0
	var left := m & 4 == 0
	var right := m & 1 == 0
	if left:
		for y in PX:
			_px(img, o, 0, y, ROCK_DARK)
			if r.randf() < 0.5:
				_px(img, o, 1, y, ROCK_DARK)
	if right:
		for y in PX:
			_px(img, o, PX - 1, y, ROCK_DARK)
			if r.randf() < 0.5:
				_px(img, o, PX - 2, y, ROCK_DARK)
	if bottom:
		for x in PX:
			_px(img, o, x, PX - 1, ROCK_DARK)
			if r.randf() < 0.35:
				# Small moss drips under ledges.
				_px(img, o, x, PX - 2, MOSS_DARK)
	if top:
		# Moss cap with a bumpy lower edge.
		for x in PX:
			var h := 3 + int(2.5 * (0.5 + 0.5 * sin(x * 1.3 + s))) + r.randi_range(0, 1)
			for y in h:
				var c := MOSS
				if y == 0:
					c = MOSS_LIGHT if r.randf() < 0.75 else MOSS_TIP
				elif y == h - 1:
					c = MOSS_DARK
				_px(img, o, x, y, c)
		for i in 3:
			_px(img, o, r.randi_range(1, PX - 2), r.randi_range(1, 2), MOSS_TIP)
		# Moss creeping down exposed sides from the top.
		if left:
			for y in r.randi_range(4, 8):
				_px(img, o, 0, y, MOSS if y % 3 else MOSS_LIGHT)
		if right:
			for y in r.randi_range(4, 8):
				_px(img, o, PX - 1, y, MOSS if y % 3 else MOSS_LIGHT)

static func _wall_tile(img: Image, o: Vector2i, m: int, s: int) -> void:
	var r := _rng(s)
	for y in PX:
		for x in PX:
			var c := WALL if r.randf() < 0.85 else WALL_LIGHT
			_px(img, o, x, y, c)
	var edge := Color(WALL, 0.0)
	if m & 8 == 0:
		for x in PX:
			_px(img, o, x, 0, edge)
			if r.randf() < 0.6:
				_px(img, o, x, 1, edge)
	if m & 2 == 0:
		for x in PX:
			_px(img, o, x, PX - 1, edge)
	if m & 4 == 0:
		for y in PX:
			_px(img, o, 0, y, edge)
	if m & 1 == 0:
		for y in PX:
			_px(img, o, PX - 1, y, edge)

## Soft overlapping leaf bubbles, like dense background jungle.
static func _foliage_tile(img: Image, o: Vector2i, s: int) -> void:
	var r := _rng(s)
	for y in PX:
		for x in PX:
			_px(img, o, x, y, LEAF_DARK)
	for i in 6:
		var cx := r.randi_range(-2, PX + 1)
		var cy := r.randi_range(-2, PX + 1)
		var rad := r.randf_range(3.0, 5.5)
		for y in range(-6, 7):
			for x in range(-6, 7):
				var d := Vector2(x, y).length()
				if d <= rad:
					var c := LEAF
					if d <= rad * 0.45 and y < 0:
						c = LEAF_LIGHT
					elif d > rad - 1.0:
						c = LEAF_DARK
					# Wrap so tiles repeat seamlessly.
					_px(img, o, posmod(cx + x, PX), posmod(cy + y, PX), c)

static func _grass(img: Image, o: Vector2i, s: int) -> void:
	var r := _rng(s)
	for x in range(1, PX - 1):
		var h := r.randi_range(2, 7)
		for y in h:
			_px(img, o, x, PX - 1 - y, MOSS_LIGHT if y < h - 1 else MOSS_TIP)
		if r.randf() < 0.3:
			_px(img, o, x, PX - 1 - h, MOSS)

static func _fern(img: Image, o: Vector2i, _s: int) -> void:
	for y in range(4, PX):
		_px(img, o, 8, y, MOSS_DARK)
	for i in 5:
		var y := 5 + i * 2
		for k in range(1, 6 - i / 2):
			_px(img, o, 8 - k, y - k / 2, MOSS if k % 2 else MOSS_LIGHT)
			_px(img, o, 8 + k, y - k / 2, MOSS if k % 2 else MOSS_LIGHT)

static func _flower(img: Image, o: Vector2i, s: int) -> void:
	_grass(img, o, s)
	for p in [Vector2i(5, 8), Vector2i(10, 6)]:
		_px(img, o, p.x, p.y, Color("#f2e36b"))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_px(img, o, p.x + d.x, p.y + d.y, Color("#e8f6ff"))

static func _mushroom(img: Image, o: Vector2i, _s: int) -> void:
	for y in range(10, PX):
		_px(img, o, 7, y, Color("#d8d2b8"))
		_px(img, o, 8, y, Color("#d8d2b8"))
	for y in range(6, 10):
		for x in range(3 + (9 - y), 13 - (9 - y)):
			_px(img, o, x, y, Color("#5fd6c0") if y > 6 else Color("#a8f5e6"))

## Vines: 0 = top (attaches to a ceiling), 1 = middle, 2 = end.
static func _vine(img: Image, o: Vector2i, part: int, s: int) -> void:
	var r := _rng(s)
	for y in PX:
		if part == 2 and y > 11:
			break
		var x := 7 + int(round(sin(y * 0.6) * 1.5))
		_px(img, o, x, y, MOSS_DARK)
		_px(img, o, x + 1, y, MOSS)
		if y % 4 == 1:
			_px(img, o, x - 1, y, MOSS_LIGHT)
			_px(img, o, x + 2, y + 1, MOSS_LIGHT)
	if part == 0:
		for x in range(4, 12):
			_px(img, o, x, 0, MOSS)
			if r.randf() < 0.5:
				_px(img, o, x, 1, MOSS_DARK)

static func _stalactite(img: Image, o: Vector2i, length: int, _s: int) -> void:
	for y in length:
		var w := int(round(4.0 * (1.0 - float(y) / length)))
		for x in range(8 - w, 8 + w + 1):
			var c := STONE if x < 8 else ROCK
			if x == 8 - w or x == 8 + w:
				c = ROCK_DARK
			_px(img, o, x, y, c)

static func _hanging_moss(img: Image, o: Vector2i, s: int) -> void:
	var r := _rng(s)
	for x in range(1, PX - 1):
		var h := r.randi_range(2, 9)
		for y in h:
			_px(img, o, x, y, MOSS if y < h - 1 else MOSS_LIGHT)
