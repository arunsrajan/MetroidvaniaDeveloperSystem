@tool
class_name IDPRoomPainter
extends RefCounted
## Paints the actual contents of a room scene: its "Background", "Terrain" and "Decor"
## TileMapLayers, with Godot's terrain autotiling. Used by the panel's Room view.
##
## The scene is opened as an editable instance kept outside the tree. Painting happens on
## copies of its TileMapLayers (so they can be displayed), and [method save] writes their
## tile data back into the scene's own layers (creating missing ones) and saves the scene.
## Nothing else in the scene is touched.

const LAYER_Z := {"Background": -10, "Terrain": 0, "Decor": 5}
const LAYER_ORDER: PackedStringArray = ["Background", "Terrain", "Decor"]

var scene_path := ""
var root: Node
var layers: Dictionary = {} ## name -> TileMapLayer copy being edited
var tile_set: TileSet
var dirty := false
var _source_paths: Dictionary = {} ## name -> NodePath inside root

static func open(path: String, default_tile_set: TileSet = null) -> IDPRoomPainter:
	var packed := load(path) as PackedScene
	if not packed:
		return null
	var p := IDPRoomPainter.new()
	p.scene_path = path
	p.root = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var found: Dictionary = {}
	var all_layers: Array = p.root.find_children("*", "TileMapLayer", true, false)
	for layer in all_layers:
		if layer.name in LAYER_Z and not found.has(String(layer.name)):
			found[String(layer.name)] = layer
	if not found.has("Terrain") and not all_layers.is_empty():
		found["Terrain"] = all_layers[0] # a scene with one unnamed tile layer: paint on it
	for layer in found.values():
		if layer.tile_set and not p.tile_set:
			p.tile_set = layer.tile_set
	if not p.tile_set:
		p.tile_set = default_tile_set if default_tile_set else IDPTilesetFactory.get_or_create()
	for n in LAYER_ORDER:
		var copy: TileMapLayer
		if found.has(n):
			var src: TileMapLayer = found[n]
			copy = src.duplicate()
			copy.transform = _local_transform(src, p.root)
			p._source_paths[n] = p.root.get_path_to(src)
		else:
			copy = TileMapLayer.new()
			copy.z_index = LAYER_Z[n]
		copy.name = n
		if not copy.tile_set:
			copy.tile_set = p.tile_set
		p.layers[n] = copy
	return p

static func _local_transform(node: Node, top: Node) -> Transform2D:
	var xform := Transform2D.IDENTITY
	var n := node
	while n and n != top:
		if n is Node2D:
			xform = (n as Node2D).transform * xform
		n = n.get_parent()
	return xform

func free_instance() -> void:
	if is_instance_valid(root):
		root.free()
	for l in layers.values():
		if is_instance_valid(l) and not l.is_inside_tree():
			l.free()

## Writes the painted tiles into the scene and saves it.
func save() -> Error:
	for n in LAYER_ORDER:
		var copy: TileMapLayer = layers[n]
		var target: TileMapLayer = root.get_node_or_null(_source_paths[n]) if _source_paths.has(n) else null
		if not target:
			if copy.get_used_cells().is_empty():
				continue
			target = TileMapLayer.new()
			target.name = n
			target.z_index = LAYER_Z[n]
			root.add_child(target)
			target.owner = root
			# Background behind everything else in the scene, Decor in front of Terrain.
			if n == "Background":
				root.move_child(target, 0)
			_source_paths[n] = root.get_path_to(target)
		target.tile_set = copy.tile_set
		target.tile_map_data = copy.tile_map_data
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = IDPWorldSceneTools.save_keeping_uid(packed, scene_path)
	if err == OK:
		dirty = false
	return err

# --- Coordinates --------------------------------------------------------------------------

func layer(n: String) -> TileMapLayer:
	return layers.get(n)

func tile_size() -> Vector2:
	return Vector2(tile_set.tile_size)

## Tile cell under a scene-local position on [param layer_name].
func cell_at(layer_name: String, local_pos: Vector2) -> Vector2i:
	var l: TileMapLayer = layers[layer_name]
	return l.local_to_map(l.transform.affine_inverse() * local_pos)

## Scene-local rect of a cell.
func cell_rect(layer_name: String, cell: Vector2i) -> Rect2:
	var l: TileMapLayer = layers[layer_name]
	var center := l.transform * l.map_to_local(cell)
	return Rect2(center - tile_size() / 2.0, tile_size())

## Cells (of the Terrain grid) inside the room's shape on the world map.
func room_cells(world: IDPWorld, id: String) -> Dictionary:
	var out: Dictionary = {}
	var ts := tile_size()
	for r in world.get_local_rects(id):
		var c0 := Vector2i((r.position / ts - Vector2(0.5, 0.5)).ceil())
		var c1 := Vector2i((r.end / ts - Vector2(0.5, 0.5)).ceil()) - Vector2i.ONE
		for y in range(c0.y, c1.y + 1):
			for x in range(c0.x, c1.x + 1):
				out[cell_at("Terrain", (Vector2(x, y) + Vector2(0.5, 0.5)) * ts)] = true
	return out

# --- Tileset introspection ----------------------------------------------------------------------

func has_terrains() -> bool:
	return not get_terrains().is_empty()

## [[terrain_set, terrain, name], ...] available in the tileset.
func get_terrains() -> Array:
	var out: Array = []
	for s in tile_set.get_terrain_sets_count():
		for t in tile_set.get_terrains_count(s):
			out.append([s, t, tile_set.get_terrain_name(s, t)])
	return out

## Decoration tiles by "idp_kind" custom data: kind -> Array of [source_id, atlas_coords].
func get_decor_tiles() -> Dictionary:
	var out: Dictionary = {}
	var layer_index := -1
	for i in tile_set.get_custom_data_layers_count():
		if tile_set.get_custom_data_layer_name(i) == "idp_kind":
			layer_index = i
	for si in tile_set.get_source_count():
		var sid := tile_set.get_source_id(si)
		var src := tile_set.get_source(sid) as TileSetAtlasSource
		if not src:
			continue
		for ti in src.get_tiles_count():
			var coords := src.get_tile_id(ti)
			var td := src.get_tile_data(coords, 0)
			var kind := ""
			if layer_index >= 0:
				kind = str(td.get_custom_data_by_layer_id(layer_index))
			if kind.is_empty() and td.terrain_set < 0:
				kind = "tile"
			if kind.is_empty() or kind in ["rock", "wall"]:
				continue
			if not out.has(kind):
				out[kind] = []
			out[kind].append([sid, coords])
	return out

# --- Painting ------------------------------------------------------------------------------

func paint_terrain(layer_name: String, cells: Array, terrain_set: int, terrain: int) -> void:
	if terrain_set >= tile_set.get_terrain_sets_count():
		return
	var typed: Array[Vector2i] = []
	typed.assign(cells)
	layers[layer_name].set_cells_terrain_connect(typed, terrain_set, terrain)
	dirty = true

## Erases cells and re-connects the terrain around them.
func erase(layer_name: String, cells: Array) -> void:
	var l: TileMapLayer = layers[layer_name]
	var by_set: Dictionary = {}
	for c in cells:
		var td := l.get_cell_tile_data(c)
		if td and td.terrain_set >= 0:
			if not by_set.has(td.terrain_set):
				by_set[td.terrain_set] = []
			by_set[td.terrain_set].append(c)
		else:
			l.erase_cell(c)
	for s in by_set:
		var typed: Array[Vector2i] = []
		typed.assign(by_set[s])
		l.set_cells_terrain_connect(typed, s, -1)
		for c in typed:
			l.erase_cell(c)
		# Neighbors re-pick their tiles now that these cells are gone.
		var around: Array[Vector2i] = []
		for c in typed:
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				var nd := l.get_cell_tile_data(n)
				if nd and nd.terrain_set == s and not n in around:
					around.append(n)
		if not around.is_empty():
			var t := l.get_cell_tile_data(around[0]).terrain
			l.set_cells_terrain_connect(around, s, t)
	dirty = true

func place_tile(layer_name: String, cell: Vector2i, source_id: int, atlas: Vector2i) -> void:
	layers[layer_name].set_cell(cell, source_id, atlas)
	dirty = true

## Random picks from a decor kind (e.g. "foliage") across cells.
func place_kind(layer_name: String, cells: Array, kind: String, rng: RandomNumberGenerator = null) -> void:
	var tiles: Array = get_decor_tiles().get(kind, [])
	if tiles.is_empty():
		return
	if not rng:
		rng = RandomNumberGenerator.new()
	for c in cells:
		var t: Array = tiles[rng.randi_range(0, tiles.size() - 1)]
		layers[layer_name].set_cell(c, t[0], t[1])
	dirty = true

func clear_layer(layer_name: String) -> void:
	layers[layer_name].clear()
	dirty = true

# --- Generation ------------------------------------------------------------------------------

## Builds a starting cave from the room's shape on the map: solid walls along the room's
## outline (rough, cellular-automata edges), openings where its gates are, a floor, a few
## ledges, background foliage, then decorations. Rock outside the painted shape fills the
## notches of irregular rooms.
func generate_cave(world: IDPWorld, id: String, seed_value := 0, terrain_set := 0, terrain := 0) -> void:
	if not has_terrains():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else hash(id)
	var inside := room_cells(world, id)
	if inside.is_empty():
		return
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in inside:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	# Distance of each inside cell to the room outline (4-neighborhood BFS).
	var dist: Dictionary = {}
	var queue: Array = []
	for c in inside:
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not inside.has(c + d):
				dist[c] = 1
				queue.append(c)
				break
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if inside.has(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	# Openings for gates.
	var open: Dictionary = {}
	var ts := tile_size()
	for g in world.get_gates(id):
		var gp := world.get_gate_local_pos(id, g)
		var gc := cell_at("Terrain", gp + {"left": Vector2(ts.x, 0), "right": Vector2(-ts.x, 0), "top": Vector2(0, ts.y), "bot": Vector2(0, -ts.y)}.get(world.get_gate_side(id, g), Vector2.ZERO) * 0.5)
		var side := world.get_gate_side(id, g)
		for a in range(-2, 2):
			for depth in 7:
				var c: Vector2i
				match side:
					"left":
						c = gc + Vector2i(depth, a)
					"right":
						c = gc + Vector2i(-depth, a)
					"top":
						c = gc + Vector2i(a, depth)
					"bot":
						c = gc + Vector2i(a, -depth)
					_:
						c = gc + Vector2i(a, depth - 3)
				open[c] = true
	# Initial rock: outline band thick, thinning inwards with noise.
	var solid: Dictionary = {}
	var chance := {1: 1.0, 2: 0.8, 3: 0.42, 4: 0.18, 5: 0.06}
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not inside.has(c):
				solid[c] = true
			elif rng.randf() < chance.get(dist[c], 0.0):
				solid[c] = true
	# Smooth into cave-like shapes.
	for it in 3:
		var next := solid.duplicate()
		for c in inside:
			if dist[c] <= 1:
				continue
			var count := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if (dx != 0 or dy != 0) and (solid.has(c + Vector2i(dx, dy)) or not inside.has(c + Vector2i(dx, dy))):
						count += 1
			if count >= 5:
				next[c] = true
			elif count <= 2:
				next.erase(c)
		solid = next
	# A walkable floor: the two lowest inside cells of every column.
	for x in range(lo.x, hi.x + 1):
		var bottom := -(1 << 30)
		for y in range(lo.y, hi.y + 1):
			if inside.has(Vector2i(x, y)):
				bottom = y
		if bottom > -(1 << 30):
			solid[Vector2i(x, bottom)] = true
			solid[Vector2i(x, bottom - 1)] = true
	# Ledges jutting out of the side walls, like jungle cave platforms, with room above.
	var ledges := maxi(1, inside.size() / 240)
	var keys: Array = inside.keys()
	for i in ledges * 12:
		if ledges <= 0:
			break
		var c: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
		if solid.has(c) or c.y > hi.y - 5 or c.y < lo.y + 4:
			continue
		# Find the closest wall on the left or right within a few tiles.
		var dir := 0
		for k in range(1, 5):
			if solid.has(c + Vector2i(-k, 0)):
				dir = -1
				break
			if solid.has(c + Vector2i(k, 0)):
				dir = 1
				break
		if dir == 0:
			continue
		var clear := true
		for k in range(0, 8):
			for up in range(1, 4):
				if solid.has(c + Vector2i(-dir * k, -up)):
					clear = false
		if not clear:
			continue
		var length := rng.randi_range(3, 7)
		var thick := rng.randi_range(1, 2)
		var x := c.x
		while not solid.has(Vector2i(x, c.y)) and absi(x - c.x) < 5:
			x += dir
		for k in length + absi(x - c.x):
			for t in thick:
				solid[Vector2i(x - dir * k, c.y + t)] = true
		ledges -= 1
	for c in open:
		solid.erase(c)
	# Keep the ground under side gates so players can walk in.
	for g in world.get_gates(id):
		var side := world.get_gate_side(id, g)
		if side == "left" or side == "right":
			var gc := cell_at("Terrain", world.get_gate_local_pos(id, g))
			for depth in 7:
				var c := gc + Vector2i(depth if side == "left" else -depth, 2)
				if inside.has(c):
					solid[c] = true
	clear_layer("Terrain")
	paint_terrain("Terrain", solid.keys(), terrain_set, terrain)
	clear_layer("Background")
	var back: Array = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			back.append(Vector2i(x, y))
	place_kind("Background", back, "foliage", rng)
	auto_decorate(rng.randi(), true, inside)

## Grass and plants on floors, stalactites, vines and moss under ceilings. With
## [param allowed] (cells), decorations stay inside those cells (the room's shape).
func auto_decorate(seed_value := 0, clear := true, allowed: Dictionary = {}) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kinds := get_decor_tiles()
	var terrain: TileMapLayer = layers.Terrain
	var decor: TileMapLayer = layers.Decor
	if clear:
		decor.clear()
	var placed := 0
	var pick := func(kind: String) -> Array:
		var list: Array = kinds.get(kind, [])
		return list[rng.randi_range(0, list.size() - 1)] if not list.is_empty() else []
	var is_solid := func(c: Vector2i) -> bool: return terrain.get_cell_source_id(c) != -1
	var ok := func(c: Vector2i) -> bool: return allowed.is_empty() or allowed.has(c)
	for c: Vector2i in terrain.get_used_cells():
		var above := c + Vector2i.UP
		var below := c + Vector2i.DOWN
		if not is_solid.call(above) and decor.get_cell_source_id(above) == -1 and ok.call(above):
			var roll := rng.randf()
			var kind := ""
			if roll < 0.32:
				kind = "grass"
			elif roll < 0.42:
				kind = "fern"
			elif roll < 0.46:
				kind = "flower"
			elif roll < 0.49:
				kind = "mushroom"
			var t: Array = pick.call(kind) if not kind.is_empty() else []
			if not t.is_empty():
				decor.set_cell(above, t[0], t[1])
				placed += 1
		if not is_solid.call(below) and decor.get_cell_source_id(below) == -1 and ok.call(below):
			var roll := rng.randf()
			if roll < 0.12:
				var length := rng.randi_range(1, 5)
				var parts: Array = [pick.call("vine_top")]
				for k in length - 1:
					parts.append(pick.call("vine_mid"))
				parts.append(pick.call("vine_end"))
				for k in parts.size():
					var cell := below + Vector2i(0, k)
					if parts[k].is_empty() or not ok.call(cell) or is_solid.call(cell) or is_solid.call(cell + Vector2i.DOWN) and k < parts.size() - 1:
						break
					decor.set_cell(cell, parts[k][0], parts[k][1])
					placed += 1
			else:
				var kind := ""
				if roll < 0.24:
					kind = "stalactite_small"
				elif roll < 0.3:
					kind = "stalactite_large"
				elif roll < 0.48:
					kind = "hanging_moss"
				var t: Array = pick.call(kind) if not kind.is_empty() else []
				if not t.is_empty():
					decor.set_cell(below, t[0], t[1])
					placed += 1
	dirty = true
	return placed
