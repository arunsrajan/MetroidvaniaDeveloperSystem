@tool
class_name MDSMapStyle
extends RefCounted
## How rooms are drawn on the non-linear map, in the editor and in-game (MDSWorldMapView).
##
## Rooms are drawn cell by cell on the world's paint grid, each cell picking the tile that
## matches which of its sides are room edges, tinted with the room's area color:
## - Built-in tilesets ("handdrawn", "blueprint", "chunky") are generated in code.
## - "tileset:res://path.png": your own tileset. 4 columns x 5 rows of square tiles:
##   tiles 0-15 are indexed by the edge mask (1 = top, 2 = right, 4 = bottom, 8 = left
##   are room edges), row 5 holds the inner corners (top-left, top-right, bottom-right,
##   bottom-left). Paint it in grayscale/white: it's multiplied by the area color.
##   [method save_template] writes a built-in tileset as a starting point.
## - "metsys:res://.../Theme.tres": a MetSys map theme (center texture, walls, passages
##   where gates are, corners), drawn the way MetSys draws it.
## - "glow": a hand-made atlas look: each area a translucent shape with a glowing rim in its
##   color, faint lines between its rooms ([method draw_glow]).
## - "flat": plain rectangles (fastest).

enum Kind { FLAT, ATLAS, METSYS, GLOW }
const BUILTIN: PackedStringArray = ["flat", "handdrawn", "blueprint", "chunky", "glow"]
const BUILTIN_NAMES: PackedStringArray = ["Flat", "Hand-drawn (double line)", "Blueprint", "Chunky pixel", "Glowing areas (atlas)"]
const TILE := 32
const TOP := 1
const RIGHT := 2
const BOTTOM := 4
const LEFT := 8

static var _cache: Dictionary = {}

var id := "flat"
var kind: int = Kind.FLAT
var atlas: Texture2D
var tile_size := Vector2(TILE, TILE)
var has_corners := true
var theme: Resource

static func get_style(style_id: String) -> MDSMapStyle:
	if style_id.is_empty():
		style_id = "handdrawn"
	if _cache.has(style_id):
		return _cache[style_id]
	var s := MDSMapStyle.new()
	s.id = style_id
	if style_id == "glow":
		s.kind = Kind.GLOW
	elif style_id in BUILTIN and style_id != "flat":
		s.kind = Kind.ATLAS
		s.atlas = ImageTexture.create_from_image(build_builtin_image(style_id))
	elif style_id.begins_with("tileset:"):
		var tex := load(style_id.trim_prefix("tileset:")) as Texture2D if ResourceLoader.exists(style_id.trim_prefix("tileset:")) else null
		if tex:
			s.kind = Kind.ATLAS
			s.atlas = tex
			var w := tex.get_width() / 4.0
			s.tile_size = Vector2(w, w)
			s.has_corners = tex.get_height() >= w * 5.0 - 0.5
	elif style_id.begins_with("metsys:"):
		var t: Resource = load(style_id.trim_prefix("metsys:")) if ResourceLoader.exists(style_id.trim_prefix("metsys:")) else null
		if t and t.get("center_texture"):
			s.kind = Kind.METSYS
			s.theme = t
	_cache[style_id] = s
	return s

## Drops cached styles (e.g. after a tileset PNG was edited).
static func clear_cache() -> void:
	_cache.clear()

## MetSys themes found in the project (MetSys ships a dozen).
static func find_metsys_themes() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := "res://addons/MetroidvaniaSystem/Themes"
	if DirAccess.dir_exists_absolute(dir):
		for d in DirAccess.get_directories_at(dir):
			var p := dir.path_join(d).path_join("Theme.tres")
			if FileAccess.file_exists(p):
				out.append(p)
	return out

static func style_display_name(style_id: String) -> String:
	var i := BUILTIN.find(style_id)
	if i >= 0:
		return BUILTIN_NAMES[i]
	if style_id.begins_with("metsys:"):
		return "MetSys: " + style_id.get_base_dir().get_file()
	if style_id.begins_with("tileset:"):
		return "Tileset: " + style_id.get_file()
	return style_id

# --- Drawing --------------------------------------------------------------------------------

static func edge_mask(cells: Dictionary, c: Vector2i) -> int:
	var m := 0
	if not cells.has(c + Vector2i.UP):
		m |= TOP
	if not cells.has(c + Vector2i.RIGHT):
		m |= RIGHT
	if not cells.has(c + Vector2i.DOWN):
		m |= BOTTOM
	if not cells.has(c + Vector2i.LEFT):
		m |= LEFT
	return m

## Draws one room. [param to_screen] maps a world position to the canvas, [param cell_size]
## is the paint cell in world pixels. [param passages] holds "x,y:side" keys of cell edges
## with a gate (MetSys themes draw a passage there).
func draw_room(ci: CanvasItem, cells: Dictionary, cell_size: Vector2, to_screen: Callable, scale: float, color: Color, border_color := Color.WHITE, passages := {}) -> void:
	if kind == Kind.GLOW:
		var owner: Dictionary = {}
		for c in cells:
			owner[c] = 0
		draw_glow(ci, owner, cell_size, to_screen, scale, {0: color}, color)
		return
	var px := cell_size * scale
	for c: Vector2i in cells:
		var pos: Vector2 = to_screen.call(Vector2(c) * cell_size)
		var rect := Rect2(pos, px)
		var m := edge_mask(cells, c)
		match kind:
			Kind.ATLAS:
				ci.draw_texture_rect_region(atlas, rect, Rect2(Vector2(m % 4, m / 4) * tile_size, tile_size), color)
				if has_corners:
					var corners := [[Vector2i(-1, -1), TOP | LEFT], [Vector2i(1, -1), TOP | RIGHT], [Vector2i(1, 1), BOTTOM | RIGHT], [Vector2i(-1, 1), BOTTOM | LEFT]]
					for k in 4:
						# Inner corner: both side neighbors present, the diagonal one missing.
						if m & corners[k][1] == 0 and not cells.has(c + corners[k][0]):
							ci.draw_texture_rect_region(atlas, rect, Rect2(Vector2(k, 4) * tile_size, tile_size), color)
			Kind.METSYS:
				_draw_metsys_cell(ci, c, cells, rect, color, border_color, passages)
			_:
				ci.draw_rect(rect, color)

## Draws rooms the glowing way, a whole area at once: [param owner] maps the area's paint cells
## to its rooms, [param fills] its rooms to their colors. Translucent rooms, faint lines
## between them, and a rim glowing in [param rim] around the area.
static func draw_glow(ci: CanvasItem, owner: Dictionary, cell_size: Vector2, to_screen: Callable, scale: float, fills: Dictionary, rim: Color) -> void:
	var px := cell_size * scale
	# Each room a shade apart, so they read as rooms.
	var shades: Dictionary = {}
	for c: Vector2i in owner:
		var room: Variant = owner[c]
		if not shades.has(room):
			var fill: Color = fills.get(room, rim)
			var v := float(hash(str(room)) % 5) / 4.0 - 0.5
			fill = fill.lightened(v * 0.16) if v > 0.0 else fill.darkened(-v * 0.16)
			shades[room] = Color(fill.darkened(0.42), 0.62)
		ci.draw_rect(Rect2(to_screen.call(Vector2(c) * cell_size), px), shades[room])
	var lw := clampf(scale * 30.0, 1.5, 3.0)
	var inner := _screen_segments(MDSAreaTools.inner_edges(owner, cell_size), to_screen, 0.0)
	if not inner.is_empty():
		ci.draw_multiline(inner, Color(rim.lightened(0.25), 0.38), maxf(1.0, lw * 0.5))
	var light := rim.lightened(0.45)
	var outline := MDSAreaTools.outline(owner, cell_size)
	for glow: Array in [[6.0, 0.06], [3.6, 0.12], [2.0, 0.28], [1.0, 1.0]]:
		var w: float = lw * glow[0]
		var edges := _screen_segments(outline, to_screen, w * 0.5)
		if not edges.is_empty():
			ci.draw_multiline(edges, Color(light, glow[1]), w)

# --- Rooms with an outline on the map (curves, slants) ---------------------------------------

## The fill a room drawn by its outline gets, matching this style's tiles tinted [param color].
func outline_fill(color: Color) -> Color:
	if kind == Kind.ATLAS and id in BUILTIN:
		var f: Color = _params(id).fill
		return Color(color.r * f.r, color.g * f.g, color.b * f.b, color.a * f.a)
	if kind == Kind.ATLAS:
		return color.darkened(0.25)
	return color

static var _polys: Dictionary = {}

## Room [param id]'s outline on the map in world px, ready to fill: its shape, else its
## rectangles. Cached until the room changes.
static func room_polygons(world: MDSWorld, id: String) -> Array[PackedVector2Array]:
	var room: Dictionary = world.data.rooms.get(id, {})
	var key := hash([id, room.get("rects", []), room.get("shape", []), room.get("origin", [])])
	if not _polys.has(key):
		if _polys.size() > 4096:
			_polys.clear()
		_polys[key] = drawable(world.get_room_outline(id))
	return _polys[key]

## The outline around rooms [param ids] (an area): their outlines joined. Cached.
static func area_outline(world: MDSWorld, ids: Array[String]) -> Array[PackedVector2Array]:
	var parts: Array = ["area"]
	for id in ids:
		var room: Dictionary = world.data.rooms.get(id, {})
		parts.append([room.get("rects", []), room.get("shape", []), room.get("origin", [])])
	var key := hash(parts)
	if not _polys.has(key):
		var pieces: Array[PackedVector2Array] = []
		for id in ids:
			pieces.append_array(room_polygons(world, id))
		_polys[key] = drawable(MDSGeometry.union_all(pieces, INF))
	return _polys[key]

## The polygons of [param polys] that can be filled (they triangulate).
static func drawable(polys: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for p: PackedVector2Array in polys:
		var clean := MDSGeometry.dedupe(p)
		if clean.size() >= 3 and Geometry2D.triangulate_polygon(clean).size() >= 3:
			out.append(clean)
	return out

static func _on_screen(poly: PackedVector2Array, to_screen: Callable, closed := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size() + (1 if closed else 0))
	for i in poly.size():
		out[i] = to_screen.call(poly[i])
	if closed:
		out[poly.size()] = out[0]
	return out

## Draws a room by its outline (world-px [param polys]): a dark border, the fill, and a light
## band inside the edge (none when [param band] is transparent).
static func draw_outlined(ci: CanvasItem, polys: Array, to_screen: Callable, fill: Color, border: Color, band: Color, width: float) -> void:
	for p: PackedVector2Array in polys:
		ci.draw_polyline(_on_screen(p, to_screen, true), border, width * 2.0 + 1.0)
	for p: PackedVector2Array in polys:
		ci.draw_colored_polygon(_on_screen(p, to_screen), fill)
	if band.a > 0.0:
		for p: PackedVector2Array in polys:
			ci.draw_polyline(_on_screen(p, to_screen, true), band, maxf(1.5, width))

## [method draw_glow] for rooms with outlines: [param rooms] maps room ids to their world-px
## polygons, [param outline] is the area's (see [method area_outline]).
static func draw_glow_polygons(ci: CanvasItem, rooms: Dictionary, to_screen: Callable, scale: float, fills: Dictionary, rim: Color, outline: Array) -> void:
	var lw := clampf(scale * 30.0, 1.5, 3.0)
	for room in rooms:
		var fill: Color = fills.get(room, rim)
		var v := float(hash(str(room)) % 5) / 4.0 - 0.5
		fill = fill.lightened(v * 0.16) if v > 0.0 else fill.darkened(-v * 0.16)
		for p: PackedVector2Array in rooms[room]:
			ci.draw_colored_polygon(_on_screen(p, to_screen), Color(fill.darkened(0.42), 0.62))
	var inner := Color(rim.lightened(0.25), 0.38)
	for room in rooms:
		for p: PackedVector2Array in rooms[room]:
			ci.draw_polyline(_on_screen(p, to_screen, true), inner, maxf(1.0, lw * 0.5))
	var light := rim.lightened(0.45)
	for glow: Array in [[6.0, 0.06], [3.6, 0.12], [2.0, 0.28], [1.0, 1.0]]:
		for p: PackedVector2Array in outline:
			ci.draw_polyline(_on_screen(p, to_screen, true), Color(light, glow[1]), lw * glow[0])

## Segments (pairs of world points) on the screen, each made [param grow] px longer at both
## ends so thick lines meet at corners.
static func _screen_segments(points: PackedVector2Array, to_screen: Callable, grow: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in range(0, points.size(), 2):
		var a: Vector2 = to_screen.call(points[i])
		var b: Vector2 = to_screen.call(points[i + 1])
		var d := (b - a).normalized() * grow
		out[i] = a - d
		out[i + 1] = b + d
	return out

# MetSys border directions: R, D, L, U (same order as MetroidvaniaSystem.R/D/L/U).
const _FWD: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const _SIDE_NAMES: PackedStringArray = ["right", "bot", "left", "top"]

func _draw_metsys_cell(ci: CanvasItem, c: Vector2i, cells: Dictionary, rect: Rect2, color: Color, border_color: Color, passages: Dictionary) -> void:
	var center: Texture2D = theme.center_texture
	var base := center.get_size()
	# Draw in the theme's own pixel space, scaled to the cell.
	ci.draw_set_transform(rect.position, 0.0, rect.size / base)
	ci.draw_texture_rect(center, Rect2(Vector2.ZERO, base), false, color)
	var rectangle: bool = theme.get("rectangle") == true
	var shared: bool = theme.get("use_shared_borders") == true
	var borders: Array[int] = [-1, -1, -1, -1]
	for i in 4:
		if not cells.has(c + _FWD[i]):
			borders[i] = 1 if passages.has("%d,%d:%s" % [c.x, c.y, _SIDE_NAMES[i]]) else 0
	for i in 4:
		if borders[i] < 0:
			continue
		var tex: Texture2D
		if rectangle:
			var vertical := i == 0 or i == 2
			tex = theme.get(("vertical_" if vertical else "horizontal_") + ("passage" if borders[i] == 1 else "wall"))
		else:
			tex = theme.get("passage" if borders[i] == 1 else "wall")
		if tex:
			_metsys_border(ci, i, tex, border_color, base, shared)
	var nocorner: bool = theme.call("is_nocorner") if theme.has_method("is_nocorner") else false
	if shared or nocorner:
		ci.draw_set_transform(Vector2.ZERO)
		return
	for i in 4:
		var j := (i + 1) % 4
		if borders[i] >= 0 and borders[j] >= 0 and theme.get("outer_corner"):
			_metsys_corner(ci, i, theme.outer_corner, border_color, base)
		elif borders[i] < 0 and borders[j] < 0 and theme.get("inner_corner") and not cells.has(c + _FWD[i] + _FWD[j]):
			_metsys_corner(ci, i, theme.inner_corner, border_color, base)
	ci.draw_set_transform(Vector2.ZERO)

# Ports of MetSys CellView._draw_texture / _draw_border / _draw_corner.
func _metsys_texture(ci: CanvasItem, texture: Texture2D, color: Color, offset: Vector2, direction: int) -> void:
	match direction:
		0:
			ci.draw_texture_rect(texture, Rect2(offset, texture.get_size()), false, color)
		1:
			ci.draw_texture_rect(texture, Rect2(offset, texture.get_size() * Vector2(-1, 1)), false, color, true)
		2:
			ci.draw_texture_rect(texture, Rect2(offset, texture.get_size() * Vector2(-1, -1)), false, color)
		3:
			ci.draw_texture_rect(texture, Rect2(offset, texture.get_size() * Vector2(1, -1)), false, color, true)

func _metsys_border(ci: CanvasItem, i: int, texture: Texture2D, color: Color, cell: Vector2, shared: bool) -> void:
	var pos := Vector2()
	match i:
		0:
			pos.x = cell.x - texture.get_width()
		1:
			pos.y = cell.y - texture.get_width()
	match i:
		0, 2:
			pos.y = cell.y * 0.5 - texture.get_height() * 0.5
		1, 3:
			pos.x = cell.x * 0.5 - texture.get_height() * 0.5
	if shared:
		match i:
			0:
				pos.x += texture.get_width() / 2.0
			1:
				pos.y += texture.get_width() / 2.0
			2:
				pos.x -= texture.get_width() / 2.0
			3:
				pos.y -= texture.get_width() / 2.0
	_metsys_texture(ci, texture, color, pos, i)

func _metsys_corner(ci: CanvasItem, i: int, texture: Texture2D, color: Color, cell: Vector2) -> void:
	match i:
		0:
			_metsys_texture(ci, texture, color, cell - texture.get_size(), i)
		1:
			_metsys_texture(ci, texture, color, Vector2.DOWN * (cell.y - texture.get_height()), i)
		2:
			_metsys_texture(ci, texture, color, Vector2(), i)
		3:
			_metsys_texture(ci, texture, color, Vector2.RIGHT * (cell.x - texture.get_width()), i)

# --- Built-in tilesets -------------------------------------------------------------------------

## A 4x5 tile atlas (see the class description) drawn in grayscale for tinting.
static func build_builtin_image(style_id: String) -> Image:
	var img := Image.create(TILE * 4, TILE * 5, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for m in 16:
		_draw_builtin_tile(img, Vector2i(m % 4, m / 4) * TILE, m, style_id)
	for k in 4:
		_draw_builtin_corner(img, Vector2i(k, 4) * TILE, k, style_id)
	return img

static func _params(style_id: String) -> Dictionary:
	match style_id:
		"blueprint":
			return {"fill": Color(1, 1, 1, 0.22), "band": 3, "band_color": Color.WHITE, "outline": 0, "inner": 0}
		"chunky":
			return {"fill": Color(0.55, 0.55, 0.55), "band": 6, "band_color": Color.WHITE, "outline": 2, "inner": 0, "dots": true}
	# handdrawn: thick light band, dark outline outside, thin dark line inside, darker fill.
	return {"fill": Color(0.72, 0.72, 0.72), "band": 5, "band_color": Color.WHITE, "outline": 1, "inner": 1}

static func _draw_builtin_tile(img: Image, o: Vector2i, m: int, style_id: String) -> void:
	var p := _params(style_id)
	var t := TILE
	img.fill_rect(Rect2i(o, Vector2i(t, t)), p.fill)
	if p.get("dots", false):
		for y in range(3, t, 8):
			for x in range(3, t, 8):
				img.fill_rect(Rect2i(o + Vector2i(x, y), Vector2i(2, 2)), Color(0.45, 0.45, 0.45))
	var b: int = p.band
	var ol: int = p.outline
	var dark := Color(0.08, 0.08, 0.08)
	# Band + outline for every room edge of this tile.
	var sides := {TOP: Rect2i(0, 0, t, b), BOTTOM: Rect2i(0, t - b, t, b), LEFT: Rect2i(0, 0, b, t), RIGHT: Rect2i(t - b, 0, b, t)}
	for side in sides:
		if m & side:
			var r: Rect2i = sides[side]
			img.fill_rect(Rect2i(o + r.position, r.size), p.band_color)
	for side in sides:
		if m & side and ol > 0:
			var r: Rect2i = sides[side]
			var edge: Rect2i = {TOP: Rect2i(r.position.x, 0, r.size.x, ol), BOTTOM: Rect2i(r.position.x, t - ol, r.size.x, ol), LEFT: Rect2i(0, r.position.y, ol, r.size.y), RIGHT: Rect2i(t - ol, r.position.y, ol, r.size.y)}[side]
			img.fill_rect(Rect2i(o + edge.position, edge.size), dark)
	if p.inner > 0:
		var inner: int = p.inner
		var x0 := b if m & LEFT else 0
		var x1 := t - b if m & RIGHT else t
		var y0 := b if m & TOP else 0
		var y1 := t - b if m & BOTTOM else t
		if m & TOP:
			img.fill_rect(Rect2i(o + Vector2i(x0, b), Vector2i(x1 - x0, inner)), dark)
		if m & BOTTOM:
			img.fill_rect(Rect2i(o + Vector2i(x0, t - b - inner), Vector2i(x1 - x0, inner)), dark)
		if m & LEFT:
			img.fill_rect(Rect2i(o + Vector2i(b, y0), Vector2i(inner, y1 - y0)), dark)
		if m & RIGHT:
			img.fill_rect(Rect2i(o + Vector2i(t - b - inner, y0), Vector2i(inner, y1 - y0)), dark)

static func _draw_builtin_corner(img: Image, o: Vector2i, k: int, style_id: String) -> void:
	# Small band square in the concave corner so L-shaped rooms keep a continuous border.
	var p := _params(style_id)
	var b: int = p.band
	var t := TILE
	var pos: Vector2i = [Vector2i(0, 0), Vector2i(t - b, 0), Vector2i(t - b, t - b), Vector2i(0, t - b)][k]
	img.fill_rect(Rect2i(o + pos, Vector2i(b, b)), p.band_color)
	if p.outline > 0:
		var ol: int = p.outline
		var dark := Color(0.08, 0.08, 0.08)
		var cx: int = [0, t - ol, t - ol, 0][k]
		var cy: int = [0, 0, t - ol, t - ol][k]
		img.fill_rect(Rect2i(o + Vector2i(cx, cy), Vector2i(ol, ol)), dark)

## Writes a built-in tileset as a PNG to start your own from.
static func save_template(style_id: String, png_path: String) -> Error:
	return build_builtin_image(style_id if style_id in BUILTIN and style_id != "flat" else "handdrawn").save_png(png_path)
