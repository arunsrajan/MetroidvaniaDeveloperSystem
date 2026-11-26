@tool
class_name MDSCaveMask
extends RefCounted
## The open air of a cave room: the cells of its Terrain grid that are inside the room's shape on
## the world map and hold no Terrain tile. Environment effects ([MDSEnvironmentEffect]) draw only
## there, so weather, backgrounds and placed effects never show over rock or outside the room
## (see [method MDSEnvironmentEffect.set_cave_mask]).
##
## The mask is a texture with one pixel per cell, white where the cave is open, drawn with linear
## filtering: an effect fades out over one tile at the rock's edge. A room with no Terrain tiles
## yet is open everywhere inside its shape.
##
## The Room view gives every effect it shows the edited room's mask, and makes it again as the
## Terrain is painted. [MDSWorldGame] gives one to every room it loads.

## The mask: one pixel per Terrain cell (L8), white where the cave is open.
var texture: ImageTexture
## The rectangle [member texture] covers, in the room's coordinates.
var rect := Rect2()
## The open cells (Terrain grid). Vector2i -> true.
var open: Dictionary = {}
## The cells inside the room's shape (Terrain grid). Vector2i -> true.
var shape: Dictionary = {}
## The Terrain grid's cell size (px).
var tile_size := Vector2(16, 16)
## The Terrain layer's transform in the room (cells to room coordinates).
var grid_transform := Transform2D.IDENTITY

## The mask of room [param id] of [param world], its solid cells those of [param terrain] (the
## room's Terrain TileMapLayer, its transform relative to the room; null: no rock). Null when the
## room has no shape on the map.
static func build(world: MDSWorld, id: String, terrain: TileMapLayer, cell_size := Vector2.ZERO) -> MDSCaveMask:
	if not world or not world.has_room(id):
		return null
	var ts := cell_size
	if ts == Vector2.ZERO:
		ts = Vector2(terrain.tile_set.tile_size) if terrain and terrain.tile_set else Vector2(16, 16)
	var xform := terrain.transform if terrain else Transform2D.IDENTITY
	var cells := shape_cells(world, id, ts, xform)
	if cells.is_empty():
		return null
	return from_cells(open_cells(cells, terrain), cells, ts, xform)

## The cells (of a grid of [param cell_size] cells placed by [param grid]) inside room
## [param id]'s shape on the map: inside its outline when it has curved or slanted sides
## ([param follow_outline]), else its rectangles. A cell is in when its centre is.
static func shape_cells(world: MDSWorld, id: String, cell_size: Vector2, grid := Transform2D.IDENTITY, follow_outline := true) -> Dictionary:
	var out: Dictionary = {}
	var outline: Array[PackedVector2Array] = []
	if follow_outline:
		outline = world.get_local_shape(id)
	var inv := grid.affine_inverse()
	for r in world.get_local_rects(id):
		var c0 := Vector2i((r.position / cell_size - Vector2(0.5, 0.5)).ceil())
		var c1 := Vector2i((r.end / cell_size - Vector2(0.5, 0.5)).ceil()) - Vector2i.ONE
		for y in range(c0.y, c1.y + 1):
			for x in range(c0.x, c1.x + 1):
				var at := (Vector2(x, y) + Vector2(0.5, 0.5)) * cell_size
				if outline.is_empty() or MDSGeometry.point_in_any(outline, at):
					out[Vector2i(((inv * at) / cell_size).floor())] = true
	return out

## The cells of [param cells] where [param terrain] has no tile (all of them without one).
static func open_cells(cells: Dictionary, terrain: TileMapLayer) -> Dictionary:
	if not terrain:
		return cells.duplicate()
	var out: Dictionary = {}
	for c in cells:
		if terrain.get_cell_source_id(c) == -1:
			out[c] = true
	return out

## A mask of the [param open_set] cells, covering the [param shape_set] cells (and one cell
## more around them, closed, so the effect fades out at the room's edge).
static func from_cells(open_set: Dictionary, shape_set: Dictionary, cell_size: Vector2, grid := Transform2D.IDENTITY) -> MDSCaveMask:
	var m := MDSCaveMask.new()
	m.open = open_set
	m.shape = shape_set
	m.tile_size = cell_size
	m.grid_transform = grid
	var lo := Vector2i(2147483647, 2147483647)
	var hi := -lo
	for c: Vector2i in shape_set:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	for c: Vector2i in open_set:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	if lo.x > hi.x:
		lo = Vector2i.ZERO
		hi = Vector2i.ZERO
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var n := hi - lo + Vector2i.ONE
	var img := Image.create_empty(n.x, n.y, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	for c: Vector2i in open_set:
		img.set_pixelv(c - lo, Color.WHITE)
	m.texture = ImageTexture.create_from_image(img)
	var a := grid * (Vector2(lo) * cell_size)
	var b := grid * (Vector2(hi + Vector2i.ONE) * cell_size)
	m.rect = Rect2(a, b - a).abs()
	return m

## Whether the cave is open at [param pos] (room coordinates).
func is_open(pos: Vector2) -> bool:
	return open.has(Vector2i(((grid_transform.affine_inverse() * pos) / tile_size).floor()))

## Gives every effect under [param node] (itself included) this mask. [param space] is the node
## whose coordinates are the room's (an ancestor of [param node]; null: [param node]'s parent).
func apply(node: Node, space: Node = null) -> void:
	var s := space if space else node.get_parent()
	for fx in MDSEnvironment.effects_in(node):
		fx.set_cave_mask(texture, rect, s)

## Takes the masks away from the effects under [param node].
static func clear(node: Node) -> void:
	for fx in MDSEnvironment.effects_in(node):
		fx.clear_cave_mask()

## The Terrain TileMapLayer of a room scene [param room] (not a free tile piece or a hidden-tile
## layer), or null.
static func terrain_of(room: Node) -> TileMapLayer:
	if not room:
		return null
	var first: TileMapLayer = null
	for l in room.find_children("*", "TileMapLayer", true, false):
		if MDSRoomPainter.is_tile_piece(l) or MDSLegacy.has_meta_key(l, &"mds_blockout"):
			continue
		if l.name == &"Terrain":
			return l
		if not first:
			first = l
	return first
