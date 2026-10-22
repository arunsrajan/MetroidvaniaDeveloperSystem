@tool
class_name MDSRoomPainter
extends RefCounted
## Paints the actual contents of a room scene: its "Background", "Terrain", "Decor" and
## "Foreground" TileMapLayers (with Godot's terrain autotiling), its freeform shapes
## ([MDSFreeform]), its stamps (sprites from an [MDSStampSet]) and the environment effects in
## its "Effects" node ([MDSEnvironmentEffect]: rain, steam vents, lava...). Used by the Room
## view.
##
## The scene is opened as an editable instance kept outside the tree. Painting happens on
## copies (so they can be displayed), and [method save] writes them back into the scene
## (creating missing layers and item groups) and saves it.
##
## Tools that change the scene's other nodes (Convert to freeform hides old terrain, Fit
## props moves objects) record [member scene_edits] instead of touching the scene, so undo
## covers them; [method save] applies them. Tiles hidden rather than deleted go to a
## disabled "<Layer>Blockout" layer ([method hide_cells]).
##
## Tiles can also leave the grid: a free tile piece is a small TileMapLayer of its own in the
## "Tiles" group, at any position and angle, drawn and colliding like the layer it belongs to
## (see [method add_tile_piece], [method lift_cells] and [method merge_piece]). Pictures kept as
## they are drawn ([MDSDrawing]) are in the "Pictures" group.

const LAYER_Z := {"Background": -10, "Terrain": 0, "Decor": 5, "Foreground": 20}
const LAYER_ORDER: PackedStringArray = ["Background", "Terrain", "Decor", "Foreground"]
## Groups of freeform shapes, stamps, effects, free tile pieces and pictures (nodes of that name
## in the scene) and their z. Effects, pieces and pictures draw at their own z_index.
const ITEM_GROUPS := {
	"FreeformBack": -8, "StampsBack": -6, "Freeform": 1, "StampsFront": 6,
	"FreeformFront": 22, "StampsForeground": 24, "Effects": 0, "Tiles": 0, "Pictures": 0,
}
## The group environment effects are kept in. Effects elsewhere in the scene are left alone.
const EFFECTS_GROUP := "Effects"
## The group of free tile pieces. Each draws at the z of its layer ([constant LAYER_Z]).
const TILES_GROUP := "Tiles"
## The group of pictures ([MDSDrawing]).
const PICTURES_GROUP := "Pictures"
## Metadata of a free tile piece: the name of the tile layer it belongs to ("Terrain"...).
const PIECE_META := &"mds_tiles"
## z of a picture of each layer: just above that layer's tiles.
const PICTURE_Z := {"Background": -9, "Terrain": 0, "Decor": 5, "Foreground": 21}
## Metadata of a picture: the name of the layer whose depth it is drawn at.
const DRAWING_LAYER_META := &"mds_layer"
## Metadata of a tile layer: the cells the last Trace drawing painted on it (Replace the last
## trace erases them).
const TRACED_CELLS := &"mds_traced_cells"
## The alternative-tile bits that flip and turn a cell's tile.
const TRANSFORM_FLAGS := TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE
## Metadata of the stamps Generate cave scattered (New variation replaces them).
const GENERATED_META := &"mds_generated"

var scene_path := ""
var root: Node
## The scene as loaded, for saving it back safely (see [method MDSWorldSceneTools.repack_safely]).
var packed_scene: PackedScene
var layers: Dictionary = {} ## name -> TileMapLayer copy being edited
var tile_set: TileSet
var dirty := false
var tile_set_dirty := false
var _source_paths: Dictionary = {} ## name -> NodePath inside root
## Display copies of freeform shapes and stamps: one child per item group.
var items_root: Node2D
var _undo: Array = [] ## snapshots: layer name -> tile_map_data
var _redo: Array = []
## Hidden tiles: layer name -> disabled TileMapLayer copy ("<Layer>Blockout").
var blockout: Dictionary = {}
## Changes to the scene's other nodes: path from the root -> {hidden, removed, position}.
var scene_edits: Dictionary = {}
var _scene_originals: Dictionary = {} ## path -> {visible, process_mode, position, blockout}
var _detached: Dictionary = {} ## path -> [node, parent path, index]: removed by a save
var _created: Dictionary = {} ## paths of layers and groups a save added (removed again when empty)
var _base: Dictionary = {} ## the room as its scene had it last (see [method base_state])
## The doorways the last Generate cave carved: gate name -> its box (scene-local), on the room's
## edge across the opening, where the gate nodes were put (see [method fit_gate_nodes]).
var gate_openings: Dictionary = {}

const COLOR_SOURCE_NAME := "MDS colors"
const MAX_UNDO := 60
## Godot's editor warns that a text scene or resource is large on disk when it saves one
## bigger than this.
const LARGE_TEXT_FILE := 512 * 1024
## Bytes a tile takes in a .tscn or .tres: 12 of tile_map_data, written out in base64.
const TILE_FILE_BYTES := 16
## Images embedded in a tileset at least this big (pixels) become PNG files next to it (see
## [method externalize_sheets]); smaller ones are packed into it.
const SHEET_FILE_PIXELS := 64 * 64

static func open(path: String, default_tile_set: TileSet = null) -> MDSRoomPainter:
	var packed := load(path) as PackedScene
	if not packed:
		return null
	return open_packed(packed, path, default_tile_set)

## A painter of [param tiles] alone, with no room: what the tile palette and the brushes' fills
## need while no room is edited (the Full view's). Only its tileset methods work.
static func for_tile_set(tiles: TileSet) -> MDSRoomPainter:
	var p := MDSRoomPainter.new()
	p.tile_set = tiles
	return p

## Opens the room scene [param path] as [param packed] has it: the scene open in the editor, with
## the changes made there and not saved yet, packed (see [method rebase_onto]).
static func open_packed(packed: PackedScene, path: String, default_tile_set: TileSet = null) -> MDSRoomPainter:
	var p := MDSRoomPainter.new()
	p.scene_path = path
	p.packed_scene = packed
	p.root = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if not p.root:
		return null
	# Tiles erased before it was saved and kept as empty entries are no tiles.
	MDSWorldSceneTools.drop_erased_cells(p.root)
	# Metadata and groups with their names from before 3.1 get the new ones (saved with the scene).
	MDSLegacy.upgrade_nodes(p.root)
	var found: Dictionary = {}
	var all_layers: Array = p.root.find_children("*", "TileMapLayer", true, false).filter(func(l: Node) -> bool: return not MDSLegacy.has_meta_key(l, &"mds_blockout") and not is_tile_piece(l))
	for layer in all_layers:
		if layer.name in LAYER_Z and not found.has(String(layer.name)):
			found[String(layer.name)] = layer
	for layer in p.root.find_children("*Blockout", "TileMapLayer", true, false):
		var base := String(layer.name).trim_suffix("Blockout")
		if base in LAYER_Z and MDSLegacy.has_meta_key(layer, &"mds_blockout") and not p.blockout.has(base):
			var copy: TileMapLayer = layer.duplicate()
			copy.transform = _local_transform(layer, p.root)
			p.blockout[base] = copy
			p._source_paths[base + "Blockout"] = p.root.get_path_to(layer)
	if not found.has("Terrain") and not all_layers.is_empty():
		found["Terrain"] = all_layers[0] # a scene with one unnamed tile layer: paint on it
	for layer in found.values():
		if layer.tile_set and not p.tile_set:
			p.tile_set = layer.tile_set
	if not p.tile_set:
		p.tile_set = default_tile_set if default_tile_set else MDSTilesetFactory.get_or_create()
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
	p.items_root = Node2D.new()
	p.items_root.name = "MDSItems"
	for g in ITEM_GROUPS:
		var c := Node2D.new()
		c.name = g
		c.z_index = ITEM_GROUPS[g]
		p.items_root.add_child(c)
	for node in p.root.find_children("*", "", true, false):
		if node.owner != p.root or not is_item(node, p.root):
			continue
		var parent_name := String(node.get_parent().name)
		var group := parent_name if ITEM_GROUPS.has(parent_name) else ("Freeform" if node is MDSFreeform else "StampsFront")
		if node is MDSEnvironmentEffect:
			group = EFFECTS_GROUP
		elif is_tile_piece(node):
			group = TILES_GROUP
		elif node is MDSDrawing:
			group = PICTURES_GROUP
		var copy: Node2D = node.duplicate()
		copy.transform = _local_transform(node, p.root)
		if copy is TileMapLayer and not copy.tile_set:
			copy.tile_set = p.tile_set
		p.items_root.get_node(group).add_child(copy)
	p._base = p._snapshot()
	return p

static func is_stamp(node: Node) -> bool:
	return node is Sprite2D and MDSLegacy.has_meta_key(node, &"mds_stamp")

## A free tile piece: tiles off the grid, at any position and angle (see [method add_tile_piece]).
static func is_tile_piece(node: Node) -> bool:
	return node is TileMapLayer and node.has_meta(PIECE_META)

## Something the Room view keeps as an item of the room: a freeform shape, stamp, effect, free
## tile piece or picture.
static func is_item(node: Node, scene_root: Node) -> bool:
	return node is MDSFreeform or is_stamp(node) or is_room_effect(node, scene_root) or is_tile_piece(node) or node is MDSDrawing

## Whether [param cell] of [param layer] holds a tile its tileset can draw. A painted cell can
## point at a tile that is gone: its sheet was removed, or the sheet's tile size was made bigger
## so fewer tiles fit. Godot then keeps the tiles past the sheet's edge "outside the texture"
## (they draw nothing, and loading the tileset logs "The TileSetAtlasSource atlas has no tile at
## ..." for each of them), or drops them, and then [method TileMapLayer.get_cell_tile_data]
## logs that for every cell painted with them. Such a cell draws nothing and collides with
## nothing. Empty cells are not valid either.
static func is_cell_valid(layer: TileMapLayer, cell: Vector2i) -> bool:
	var ts := layer.tile_set
	var sid := layer.get_cell_source_id(cell)
	if not ts or sid < 0 or not ts.has_source(sid):
		return false
	var src := ts.get_source(sid)
	var at := layer.get_cell_atlas_coords(cell)
	if not src.has_tile(at) or not src.has_alternative_tile(at, layer.get_cell_alternative_tile(cell)):
		return false
	# A tile outside its sheet has no place in the atlas.
	return not src is TileSetAtlasSource or (src as TileSetAtlasSource).get_tile_at_coords(at) == at

## The tile data of [param cell], or null when it is empty or broken (see [method is_cell_valid]).
static func cell_tile_data(layer: TileMapLayer, cell: Vector2i) -> TileData:
	return layer.get_cell_tile_data(cell) if is_cell_valid(layer, cell) else null

## The painted cells of [param layer] that point at a tile its tileset doesn't have.
static func broken_cells_of(layer: TileMapLayer) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not layer.tile_set:
		return out
	for c in layer.get_used_cells():
		if not is_cell_valid(layer, c):
			out.append(c)
	return out

## An effect the Room view edits: one in the scene's "Effects" node (a child of
## [param scene_root]).
static func is_room_effect(node: Node, scene_root: Node) -> bool:
	if not node is MDSEnvironmentEffect:
		return false
	var parent := node.get_parent()
	return parent != null and String(parent.name) == EFFECTS_GROUP and parent.get_parent() == scene_root

## "freeform", "stamp", "effect", "tiles" (a free tile piece) or "drawing".
static func item_kind(node: Node) -> String:
	if node is MDSFreeform:
		return "freeform"
	if node is MDSEnvironmentEffect:
		return "effect"
	if is_tile_piece(node):
		return "tiles"
	if node is MDSDrawing:
		return "drawing"
	return "stamp"

static func _local_transform(node: Node, top: Node) -> Transform2D:
	var xform := Transform2D.IDENTITY
	var n := node
	while n and n != top:
		if n is Node2D:
			xform = (n as Node2D).transform * xform
		n = n.get_parent()
	return xform

## Snapshot of all layers for [method undo]. Call before each edit.
func checkpoint() -> void:
	_undo.append(_snapshot())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(_snapshot())
	_restore(_undo.pop_back())
	return true

func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(_snapshot())
	_restore(_redo.pop_back())
	return true

func _snapshot() -> Dictionary:
	var out: Dictionary = {}
	var traced: Dictionary = {}
	for n in LAYER_ORDER:
		out[n] = layers[n].tile_map_data
		if layers[n].has_meta(TRACED_CELLS):
			traced[n] = (layers[n].get_meta(TRACED_CELLS) as Array).duplicate()
	out[&"_traced"] = traced
	var items: Dictionary = {}
	for g in ITEM_GROUPS:
		var list: Array = []
		for node in items_root.get_node(g).get_children():
			list.append(_item_data(node))
		items[g] = list
	out[&"_items"] = items
	var hidden: Dictionary = {}
	for n in blockout:
		hidden[n] = blockout[n].tile_map_data
	out[&"_blockout"] = hidden
	out[&"_scene"] = scene_edits.duplicate(true)
	return out

func _restore(snap: Dictionary) -> void:
	for n in snap:
		if n is String and layers.has(n):
			layers[n].tile_map_data = snap[n]
	for n in LAYER_ORDER:
		var traced: Dictionary = snap.get(&"_traced", {})
		if traced.has(n):
			layers[n].set_meta(TRACED_CELLS, (traced[n] as Array).duplicate())
		elif layers[n].has_meta(TRACED_CELLS):
			layers[n].remove_meta(TRACED_CELLS)
	if snap.has(&"_items"):
		for g in snap[&"_items"]:
			var container := items_root.get_node(String(g))
			for c in container.get_children():
				container.remove_child(c)
				c.queue_free()
			for d in snap[&"_items"][g]:
				container.add_child(_item_from(d))
	for n in blockout:
		blockout[n].tile_map_data = snap.get(&"_blockout", {}).get(n, PackedByteArray())
	for n in snap.get(&"_blockout", {}):
		blockout_layer(n).tile_map_data = snap[&"_blockout"][n]
	scene_edits = snap.get(&"_scene", {}).duplicate(true)
	dirty = true

static func _item_data(node: Node) -> Dictionary:
	if node is MDSFreeform or node is MDSEnvironmentEffect or node is MDSDrawing:
		var d: Dictionary = node.to_data()
		d.kind = item_kind(node)
		return d
	if is_tile_piece(node):
		var piece := node as TileMapLayer
		var meta: Dictionary = {}
		for k in piece.get_meta_list():
			meta[k] = piece.get_meta(k)
		return {"kind": "tiles", "tile_set": piece.tile_set, "cells": piece.tile_map_data, "transform": piece.transform,
			"z": piece.z_index, "name": String(piece.name), "meta": meta}
	var s := node as Sprite2D
	var meta: Dictionary = {}
	for k in s.get_meta_list():
		if k != &"mds_stamp":
			meta[k] = s.get_meta(k)
	return {"kind": "stamp", "texture": s.texture, "region": s.region_rect, "offset": s.offset,
		"transform": s.transform, "index": MDSLegacy.get_meta_key(s, &"mds_stamp", 0), "meta": meta, "name": String(s.name)}

static func _item_from(d: Dictionary) -> Node2D:
	if d.kind == "freeform":
		return MDSFreeform.from_data(d)
	if d.kind == "effect":
		return MDSEnvironmentEffect.from_data(d)
	if d.kind == "drawing":
		return MDSDrawing.from_data(d)
	if d.kind == "tiles":
		var piece := TileMapLayer.new()
		piece.tile_set = d.tile_set
		piece.tile_map_data = d.cells
		piece.transform = d.transform
		piece.z_index = d.z
		if not str(d.get("name", "")).is_empty():
			piece.name = d.name
		for k in d.get("meta", {}):
			piece.set_meta(k, d.meta[k])
		return piece
	var s := Sprite2D.new()
	s.texture = d.texture
	s.region_enabled = true
	s.region_rect = d.region
	s.centered = false
	s.offset = d.offset
	s.transform = d.transform
	# Its name kept, so an undone stamp is still the scene's (not re-made as "@Sprite2D@...").
	if not str(d.get("name", "")).is_empty():
		s.name = d.name
	s.set_meta(&"mds_stamp", d.index)
	for k in d.get("meta", {}):
		s.set_meta(k, d.meta[k])
	return s

# --- Freeform shapes and stamps --------------------------------------------------------------

## Items of a group ("Freeform", "StampsFront"...).
func items(group: String) -> Array:
	return items_root.get_node(group).get_children()

func add_freeform(points: PackedVector2Array, style: MDSFreeformStyle, group := "Freeform", solid := true) -> MDSFreeform:
	var f := MDSFreeform.new()
	f.name = "Shape%d" % (items_root.get_node(group).get_child_count() + 1)
	f.style = style
	f.solid = solid
	f.seed_value = randi() % 100000
	f.points = points
	items_root.get_node(group).add_child(f, true)
	dirty = true
	return f

## Adds a freeform shape, stamp or effect made elsewhere to [param group] (it keeps its name,
## made unique in the group).
func add_item(node: Node2D, group: String) -> Node2D:
	if str(node.name).is_empty() or node.name.begins_with("@"):
		node.name = "Shape%d" % (items_root.get_node(group).get_child_count() + 1)
	items_root.get_node(group).add_child(node, true)
	dirty = true
	return node

func add_stamp(stamp_set: MDSStampSet, index: int, pos: Vector2, scale_value: Vector2, rotation_value := 0.0, group := "StampsFront") -> Sprite2D:
	var s := stamp_set.make_sprite(index)
	s.name = "Stamp%d" % (items_root.get_node(group).get_child_count() + 1)
	s.position = pos
	s.scale = scale_value
	s.rotation = rotation_value
	items_root.get_node(group).add_child(s, true)
	dirty = true
	return s

## Adds an environment effect ([method MDSEnvironment.create]) centred on [param pos]
## (scene-local; one that stands on its position, like a steam vent, stands on it). Returns
## it, or null for an unknown id.
func add_effect(id: String, pos: Vector2, settings: Dictionary = {}) -> MDSEnvironmentEffect:
	var e := MDSEnvironment.create(id, settings)
	if not e:
		return null
	var r := e.get_effect_rect()
	e.position = pos if r.position != Vector2.ZERO else pos - r.size * 0.5
	items_root.get_node(EFFECTS_GROUP).add_child(e, true)
	dirty = true
	return e

## The effects and gameplay items the Room view edits.
func effects() -> Array:
	var list := items(EFFECTS_GROUP)
	if root:
		for c in root.get_children():
			if is_instance_valid(c) and c is Node2D and c.is_in_group(&"mds_gameplay_placed"):
				list.append(c)
	return list

static func node_effect_rect(node: Node2D) -> Rect2:
	if node is MDSEnvironmentEffect:
		return (node as MDSEnvironmentEffect).get_effect_rect()
	if node.has_method("get_effect_rect"):
		return node.get_effect_rect()
	if "size" in node:
		var s: Vector2 = node.size
		return Rect2(-s.x * 0.5, -s.y, s.x, s.y)
	return Rect2(-24, -48, 48, 48)

## Every effect whose area holds [param p] (scene-local), the top-most first.
func effects_at(p: Vector2) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var list := effects()
	for i in range(list.size() - 1, -1, -1):
		var e: Node2D = list[i]
		if node_effect_rect(e).has_point(e.transform.affine_inverse() * p):
			out.append(e)
	return out

## The top-most effect whose area holds [param p] (scene-local), or null.
func effect_at(p: Vector2) -> Node2D:
	var list := effects()
	for i in range(list.size() - 1, -1, -1):
		var e: Node2D = list[i]
		if node_effect_rect(e).has_point(e.transform.affine_inverse() * p):
			return e
	return null

func remove_item(node: Node) -> void:
	if node and node.get_parent():
		node.get_parent().remove_child(node)
		node.queue_free()
		dirty = true

## The top-most freeform shape containing [param p] (scene-local), or null.
func freeform_at(p: Vector2) -> MDSFreeform:
	for g in ["FreeformFront", "Freeform", "FreeformBack"]:
		var list := items(g)
		for i in range(list.size() - 1, -1, -1):
			if list[i].has_point(p):
				return list[i]
	return null

## Stamps whose position is within [param radius] of [param p] (scene-local).
func stamps_near(p: Vector2, radius: float) -> Array:
	var out: Array = []
	for g in ["StampsForeground", "StampsFront", "StampsBack"]:
		for s in items(g):
			if s.position.distance_to(p) <= radius:
				out.append(s)
	return out

func clear_items() -> void:
	for g in ITEM_GROUPS:
		for c in items(g):
			remove_item(c)

# --- Free tile pieces, pictures and picking ----------------------------------------------------

## Adds a free tile piece to [param layer_name]'s depth: [param tiles] (cell -> [source id,
## atlas coords, alternative]) on a grid of its own, placed by [param xform] (any position and
## angle) in the room. It draws and collides like the layer's tiles. Returns it.
func add_tile_piece(layer_name: String, tiles: Dictionary, xform := Transform2D.IDENTITY) -> TileMapLayer:
	var piece := TileMapLayer.new()
	piece.tile_set = tile_set
	piece.z_index = LAYER_Z.get(layer_name, 0)
	piece.transform = xform
	piece.set_meta(PIECE_META, layer_name)
	var group := items_root.get_node(TILES_GROUP)
	var n := group.get_child_count() + 1
	while group.has_node("%sTiles%d" % [layer_name, n]):
		n += 1
	piece.name = "%sTiles%d" % [layer_name, n]
	for c: Vector2i in tiles:
		var t: Array = tiles[c]
		piece.set_cell(c, t[0], t[1], t[2] if t.size() > 2 else 0)
	group.add_child(piece, true)
	dirty = true
	return piece

## Free tile pieces (of [param layer_name], or all of them).
func tile_pieces(layer_name := "") -> Array:
	return items(TILES_GROUP).filter(func(p: Node) -> bool: return layer_name.is_empty() or piece_layer(p) == layer_name)

## The tile layer a free tile piece belongs to.
static func piece_layer(piece: Node) -> String:
	return str(piece.get_meta(PIECE_META, "Terrain"))

## [source id, atlas coords, alternative] of a cell of [param layer] ([] when it is empty).
static func cell_tile(layer: TileMapLayer, cell: Vector2i) -> Array:
	var sid := layer.get_cell_source_id(cell)
	if sid < 0:
		return []
	return [sid, layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]

## Takes [param cells] of [param layer_name] off the grid into a new free tile piece, in the same
## place (the tiles keep their look: neighbours are not re-connected). Returns it, or null when
## none of the cells has a tile.
func lift_cells(layer_name: String, cells: Array) -> TileMapLayer:
	var l: TileMapLayer = layers[layer_name]
	var tiles: Dictionary = {}
	for c: Vector2i in cells:
		var t := cell_tile(l, c)
		if not t.is_empty():
			tiles[c] = t
			l.erase_cell(c)
	if tiles.is_empty():
		return null
	return add_tile_piece(layer_name, tiles, l.transform)

## Puts a free tile piece back on its layer's grid: each tile goes to the cell under its center,
## turned in right angles (the piece's angle is rounded to the nearest one) and mirrored as the
## piece is. Tiles already there are replaced. The piece is removed. Returns the cells written.
func merge_piece(piece: TileMapLayer) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var layer_name := piece_layer(piece)
	var l: TileMapLayer = layers.get(layer_name, layers["Terrain"])
	var basis := right_angle_basis(piece.transform)
	for c in piece.get_used_cells():
		var t := cell_tile(piece, c)
		var at := cell_at(layer_name, piece.transform * piece.map_to_local(c))
		# The piece's turn on top of the tile's own.
		var flags := basis_flags(basis * flags_basis(int(t[2])))
		l.set_cell(at, t[0], t[1], (int(t[2]) & ~TRANSFORM_FLAGS) | flags)
		out.append(at)
	remove_item(piece)
	dirty = true
	return out

## Whether a free tile piece lines up with its layer's grid: not turned (or turned in right
## angles), not scaled, its tiles on the layer's cells.
func is_piece_on_grid(piece: TileMapLayer) -> bool:
	var xf := piece.transform
	var basis := right_angle_basis(xf)
	if not (xf.x.is_equal_approx(basis.x) and xf.y.is_equal_approx(basis.y)):
		return false
	var cells := piece.get_used_cells()
	if cells.is_empty():
		return true
	var l: TileMapLayer = layers.get(piece_layer(piece), layers["Terrain"])
	var p := piece.transform * piece.map_to_local(cells[0])
	return p.is_equal_approx(l.transform * l.map_to_local(cell_at(piece_layer(piece), p)))

## [param xform]'s axes turned to the nearest right angle (a mirror stays one), without its
## position or scale.
static func right_angle_basis(xform: Transform2D) -> Transform2D:
	if xform.x.is_zero_approx() or xform.y.is_zero_approx():
		return Transform2D.IDENTITY
	var x := Vector2(signf(xform.x.x), 0.0) if absf(xform.x.x) >= absf(xform.x.y) else Vector2(0.0, signf(xform.x.y))
	# y is x turned a quarter clockwise (on screen), or the other way when mirrored.
	var y := Vector2(-x.y, x.x) * (1.0 if xform.x.cross(xform.y) >= 0.0 else -1.0)
	return Transform2D(x, y, Vector2.ZERO)

## How the alternative-tile flags of a cell ([param alt]) turn and flip its tile, around the
## tile's center (Godot transposes first, then flips).
static func flags_basis(alt: int) -> Transform2D:
	var x := Vector2(1, 0)
	var y := Vector2(0, 1)
	if alt & TileSetAtlasSource.TRANSFORM_TRANSPOSE:
		x = Vector2(0, 1)
		y = Vector2(1, 0)
	if alt & TileSetAtlasSource.TRANSFORM_FLIP_H:
		x.x = -x.x
		y.x = -y.x
	if alt & TileSetAtlasSource.TRANSFORM_FLIP_V:
		x.y = -x.y
		y.y = -y.y
	return Transform2D(x, y, Vector2.ZERO)

## The alternative-tile flags that turn and flip a tile by [param basis] (right angles and
## mirrors only; others give 0).
static func basis_flags(basis: Transform2D) -> int:
	var b := right_angle_basis(basis)
	var f_h := TileSetAtlasSource.TRANSFORM_FLIP_H
	var f_v := TileSetAtlasSource.TRANSFORM_FLIP_V
	var tr := TileSetAtlasSource.TRANSFORM_TRANSPOSE
	for flags in [0, f_h, f_v, f_h | f_v, tr, tr | f_h, tr | f_v, tr | f_h | f_v]:
		var fb := flags_basis(flags)
		if fb.x.is_equal_approx(b.x) and fb.y.is_equal_approx(b.y):
			return flags
	return 0

## Whether [param p] (scene-local) is on [param node], an item Select picks: a freeform shape,
## stamp, free tile piece (one of its tiles) or picture.
static func item_contains(node: Node, p: Vector2) -> bool:
	if node is MDSFreeform:
		return (node as MDSFreeform).has_point(p)
	if node is MDSDrawing:
		return (node as MDSDrawing).has_point(p)
	if is_tile_piece(node):
		var piece := node as TileMapLayer
		return piece.get_cell_source_id(piece.local_to_map(piece.transform.affine_inverse() * p)) != -1
	if node is Sprite2D:
		var s := node as Sprite2D
		return s.get_rect().has_point(s.transform.affine_inverse() * p)
	return false

## The outline of an item Select picks, scene-local: the freeform shape's outline, or the box of
## a stamp, piece or picture (turned with it).
static func item_outline(node: Node) -> PackedVector2Array:
	if node is MDSFreeform:
		var f := node as MDSFreeform
		return Transform2D(0.0, f.position) * f.get_outline()
	var r := Rect2()
	if node is MDSDrawing:
		r = (node as MDSDrawing).get_rect()
	elif is_tile_piece(node):
		var piece := node as TileMapLayer
		var used := piece.get_used_rect()
		var ts := Vector2(piece.tile_set.tile_size) if piece.tile_set else Vector2(16, 16)
		r = Rect2(piece.map_to_local(used.position) - ts / 2.0, Vector2(used.size) * ts)
	elif node is Sprite2D:
		r = (node as Sprite2D).get_rect()
	return (node as Node2D).transform * MDSGeometry.rect_polygon(r)

## Every item Select can pick: freeform shapes, stamps, free tile pieces and pictures (not effects).
func pickable_items() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for g in ITEM_GROUPS:
		if g == EFFECTS_GROUP:
			continue
		for node in items(g):
			out.append(node)
	return out

## The top-most item Select picks at [param p] (scene-local), or null. Items draw by z, then in
## tree order.
func item_at(p: Vector2) -> Node2D:
	var best: Node2D = null
	var best_z := 0
	for node in pickable_items():
		if not item_contains(node, p):
			continue
		var z: int = (node.get_parent() as Node2D).z_index + node.z_index
		if best == null or z >= best_z:
			best = node
			best_z = z
	return best

## The pictures ([MDSDrawing]).
func drawings() -> Array:
	return items(PICTURES_GROUP)

## Adds a picture at [param layer_name]'s depth ([constant PICTURE_Z]). Returns it.
func add_drawing(texture: Texture2D, region: Rect2, xform: Transform2D, layer_name := "Terrain", keep := PackedColorArray(), cut := PackedColorArray()) -> MDSDrawing:
	var d := MDSDrawing.new()
	d.texture = texture
	d.region = region
	d.transform = xform
	d.keep_colors = keep
	d.cut_colors = cut
	d.z_index = PICTURE_Z.get(layer_name, 0)
	d.set_meta(DRAWING_LAYER_META, layer_name)
	var group := items_root.get_node(PICTURES_GROUP)
	var n := group.get_child_count() + 1
	while group.has_node("%sPicture%d" % [layer_name, n]):
		n += 1
	d.name = "%sPicture%d" % [layer_name, n]
	items_root.get_node(PICTURES_GROUP).add_child(d, true)
	dirty = true
	return d

# --- Hidden tiles and the scene's other nodes ----------------------------------------------------

## The disabled layer that keeps [param layer_name]'s hidden tiles (made on demand).
func blockout_layer(layer_name: String) -> TileMapLayer:
	if not blockout.has(layer_name):
		var src: TileMapLayer = layers[layer_name]
		var l := TileMapLayer.new()
		l.name = layer_name + "Blockout"
		l.tile_set = src.tile_set
		l.transform = src.transform
		l.z_index = src.z_index
		l.enabled = false
		l.set_meta(&"mds_blockout", true)
		blockout[layer_name] = l
	return blockout[layer_name]

## Takes [param cells] out of a layer and keeps them, hidden and without collision, in its
## blockout layer (saved in the scene, so they can be brought back).
func hide_cells(layer_name: String, cells: Array) -> void:
	var src: TileMapLayer = layers[layer_name]
	var dst := blockout_layer(layer_name)
	for c: Vector2i in cells:
		var sid := src.get_cell_source_id(c)
		if sid == -1:
			continue
		dst.set_cell(c, sid, src.get_cell_atlas_coords(c), src.get_cell_alternative_tile(c))
		src.erase_cell(c)
	dirty = true

func _scene_path_of(node: Node) -> String:
	return String(root.get_path_to(node))

func _remember(node: Node) -> String:
	var p := _scene_path_of(node)
	if not _scene_originals.has(p):
		_scene_originals[p] = {"visible": node.visible if node is CanvasItem else true, "process_mode": node.process_mode,
			"position": node.position if node is Node2D else Vector2.ZERO, "blockout": MDSLegacy.has_meta_key(node, &"mds_blockout")}
		var box := _gate_box_shape(node)
		if box:
			_scene_originals[p].gate_size = (box.shape as RectangleShape2D).size
	if not scene_edits.has(p):
		scene_edits[p] = {}
	return p

## Hides a node of the scene and takes it out of physics (it stays in the scene, marked as
## old terrain: the scanner and the checks skip it). Call [method checkpoint] first.
func hide_scene_node(node: Node) -> void:
	scene_edits[_remember(node)].hidden = true
	dirty = true

## Removes a node of the scene when it is saved. Call [method checkpoint] first.
func remove_scene_node(node: Node) -> void:
	scene_edits[_remember(node)].removed = true
	dirty = true

## Moves a node of the scene ([param pos] in its parent's space). Call [method checkpoint] first.
func move_scene_node(node: Node2D, pos: Vector2) -> void:
	scene_edits[_remember(node)].position = pos
	dirty = true

## The node's position with the Room view's moves applied.
func scene_position(node: Node2D) -> Vector2:
	return scene_edits.get(_scene_path_of(node), {}).get("position", node.position)

## How far the Room view moved [param node] (and its parents), in the scene's space.
func scene_offset(node: Node) -> Vector2:
	var off := Vector2.ZERO
	var n := node
	while n and n != root:
		var e: Dictionary = scene_edits.get(_scene_path_of(n), {})
		if e.has("position") and n is Node2D:
			off += Vector2(e.position) - (n as Node2D).position
		n = n.get_parent()
	return off

## Whether the Room view hid or removed [param node] or a parent of it.
func is_scene_node_hidden(node: Node) -> bool:
	var n := node
	while n and n != root:
		var e: Dictionary = scene_edits.get(_scene_path_of(n), {})
		if e.get("hidden", false) or e.get("removed", false):
			return true
		n = n.get_parent()
	return false

## Every scene node the Room view changed (now, or before an undo), with how it was:
## path -> {visible, process_mode, position}. For showing the edits.
func scene_originals() -> Dictionary:
	return _scene_originals

## The scene's gate nodes: gate name -> node (MDSGates, nodes in the mds_gate group, nodes named
## like a gate).
func gate_nodes() -> Dictionary:
	var out: Dictionary = {}
	MDSWorldSceneTools._collect_gate_nodes(root, root, out)
	return out

## [param node]'s collision box (its first CollisionShape2D with a rectangle), or null.
static func _gate_box_shape(node: Node) -> CollisionShape2D:
	if not node is Area2D:
		return null
	for c in node.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			return c
	return null

static func _set_gate_size(node: Node, size: Vector2) -> void:
	var box := _gate_box_shape(node)
	if box and (box.shape as RectangleShape2D).size != size:
		(box.shape as RectangleShape2D).size = size

## Moves gate node [param node] and sizes its collision box so the box is [param box]
## (scene-local), as an edit of the scene: undo takes it back, saving writes it.
func fit_gate_node(node: Node2D, box: Rect2) -> void:
	var p := _remember(node)
	var shape := _gate_box_shape(node)
	var parent := _local_transform(node.get_parent(), root)
	var k := node.scale.abs()
	var offset := node.transform.basis_xform(shape.position) if shape else Vector2.ZERO
	scene_edits[p].position = (parent.affine_inverse() * box.get_center() - offset).round()
	if shape:
		scene_edits[p].gate_size = (box.size / Vector2(maxf(k.x, 0.001), maxf(k.y, 0.001))).round()
	dirty = true

## Puts the scene's gate nodes on the doorways [param openings] (gate name -> box, scene-local),
## the ones Generate cave carved ([member gate_openings]): each node at its opening's middle on
## the room's edge, its collision box across the opening. Returns how many it moved.
func fit_gate_nodes(openings: Dictionary) -> int:
	var nodes := gate_nodes()
	var n := 0
	for g in openings:
		if nodes.has(g) and nodes[g] is Node2D and nodes[g].owner == root:
			fit_gate_node(nodes[g], openings[g])
			n += 1
	return n

## The gate nodes' collision boxes as they are now (Room view edits included): gate name -> box
## (scene-local). For showing them.
func gate_boxes() -> Dictionary:
	var out: Dictionary = {}
	var nodes := gate_nodes()
	for g in nodes:
		var node: Node2D = nodes[g]
		var shape := _gate_box_shape(node)
		if not shape:
			continue
		var path := _scene_path_of(node)
		var e: Dictionary = scene_edits.get(path, {})
		# A save applied the edits to the node: undone since, it is as it was before them.
		var o: Dictionary = _scene_originals.get(path, {})
		var size: Vector2 = e.get("gate_size", o.get("gate_size", (shape.shape as RectangleShape2D).size))
		var xf := _local_transform(node.get_parent(), root) * Transform2D(node.rotation, node.scale, node.skew, e.get("position", o.get("position", node.position)))
		var k := xf.get_scale().abs()
		out[g] = Rect2(xf * shape.position - size * k * 0.5, size * k)
	return out

## Applies [member scene_edits] to the scene, after putting back what earlier saves changed.
func _apply_scene_edits() -> void:
	for p in _detached.keys():
		if not scene_edits.get(p, {}).get("removed", false):
			var d: Array = _detached[p]
			var parent := root.get_node_or_null(d[1])
			if parent:
				parent.add_child(d[0])
				parent.move_child(d[0], mini(d[2], parent.get_child_count() - 1))
				d[0].owner = root
				_own(d[0], root)
			_detached.erase(p)
	for p in _scene_originals:
		var n := root.get_node_or_null(NodePath(p))
		if not n:
			continue
		var o: Dictionary = _scene_originals[p]
		if n is CanvasItem:
			n.visible = o.visible
		n.process_mode = o.process_mode
		if n is Node2D:
			n.position = o.position
		if not o.blockout and MDSLegacy.has_meta_key(n, &"mds_blockout"):
			MDSLegacy.remove_meta_key(n, &"mds_blockout")
		if o.has("gate_size"):
			_set_gate_size(n, o.gate_size)
	for p in scene_edits:
		var n := root.get_node_or_null(NodePath(p))
		if not n:
			continue
		var e: Dictionary = scene_edits[p]
		if e.has("position") and n is Node2D:
			n.position = e.position
		if e.has("gate_size"):
			_set_gate_size(n, e.gate_size)
		if e.get("removed", false):
			_detached[p] = [n, root.get_path_to(n.get_parent()), n.get_index()]
			n.get_parent().remove_child(n)
		elif e.get("hidden", false):
			if n is CanvasItem:
				n.visible = false
			n.process_mode = Node.PROCESS_MODE_DISABLED
			n.set_meta(&"mds_blockout", true)

## Layers and groups an earlier save added that are empty again (after undo) go, so the
## scene is as it was.
func _drop_empty_created() -> void:
	for p in _created.keys():
		var n := root.get_node_or_null(NodePath(p))
		if not n:
			_created.erase(p)
			continue
		var empty: bool = n.get_child_count() == 0 if not n is TileMapLayer else (n as TileMapLayer).get_used_cells().is_empty()
		if empty:
			for key in _source_paths.keys():
				if String(_source_paths[key]) == p:
					_source_paths.erase(key)
			n.get_parent().remove_child(n)
			n.free()
			_created.erase(p)

## Owner of the nodes of a re-attached subtree that came from this scene (not from scenes it
## instances).
static func _own(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		if c.owner == null:
			c.owner = owner_node
		if c.scene_file_path.is_empty():
			_own(c, owner_node)

func _save_blockout() -> void:
	for n in blockout:
		var copy: TileMapLayer = blockout[n]
		var key: String = n + "Blockout"
		var target: TileMapLayer = root.get_node_or_null(_source_paths[key]) if _source_paths.has(key) else null
		if not target:
			if copy.get_used_cells().is_empty():
				continue
			target = TileMapLayer.new()
			target.name = key
			target.z_index = copy.z_index
			target.enabled = false
			target.set_meta(&"mds_blockout", true)
			var src: Node = root.get_node_or_null(_source_paths[n]) if _source_paths.has(n) else null
			if src and src.get_parent():
				src.get_parent().add_child(target)
				src.get_parent().move_child(target, src.get_index() + 1)
			else:
				root.add_child(target)
			target.owner = root
			_source_paths[key] = root.get_path_to(target)
			_created[String(_source_paths[key])] = true
		target.tile_set = copy.tile_set
		target.tile_map_data = copy.tile_map_data

## Makes a twisted freeform shape simple (see [method MDSFreeform.repair_points]). The
## largest part stays in [param f]; other parts become new shapes beside it with the same
## settings; slivers are dropped. Returns the shapes it became (empty: removed, all slivers).
## Call [method checkpoint] first.
func repair_freeform(f: MDSFreeform) -> Array[MDSFreeform]:
	var out: Array[MDSFreeform] = []
	var parts := MDSFreeform.repair_points(f.points, f.smooth)
	if parts.is_empty():
		remove_item(f)
		return out
	var data := f.to_data()
	f.points = parts[0].points
	f.smooth = parts[0].smooth
	out.append(f)
	for i in range(1, parts.size()):
		var d := data.duplicate()
		d.points = parts[i].points
		d.smooth = parts[i].smooth
		d.name = "%s_%d" % [f.name, i + 1]
		var copy := MDSFreeform.from_data(d)
		f.get_parent().add_child(copy, true)
		out.append(copy)
	dirty = true
	return out

## Every freeform shape of the room whose outline crosses itself.
func twisted_freeforms() -> Array[MDSFreeform]:
	var out: Array[MDSFreeform] = []
	for f in MDSFreeform.shapes_in(items_root):
		if f.points.size() >= 3 and not f.is_outline_simple():
			out.append(f)
	return out

## Repairs every twisted shape. Returns {repaired, shapes (they became), removed}.
func repair_all() -> Dictionary:
	var result := {"repaired": 0, "shapes": 0, "removed": 0}
	for f in twisted_freeforms():
		var parts := repair_freeform(f)
		result.repaired += 1
		result.shapes += parts.size()
		if parts.is_empty():
			result.removed += 1
	return result

func free_instance() -> void:
	if is_instance_valid(root):
		root.free()
	for l in layers.values():
		if is_instance_valid(l) and not l.is_inside_tree():
			l.free()
	if is_instance_valid(items_root) and not items_root.is_inside_tree():
		items_root.free()
	for l in blockout.values():
		if is_instance_valid(l) and not l.is_inside_tree():
			l.free()
	for d in _detached.values():
		if is_instance_valid(d[0]):
			d[0].free()
	_detached.clear()

## Writes the painted tiles into the scene and saves it, keeping its UID and anything the
## scene sets inside instanced scenes. A scene with a node whose script failed to load is not
## saved: [member MDSWorldSceneTools.last_error] says which.
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
			_created[String(_source_paths[n])] = true
		target.tile_set = copy.tile_set
		target.tile_map_data = copy.tile_map_data
		if copy.has_meta(TRACED_CELLS) and not (copy.get_meta(TRACED_CELLS) as Array).is_empty():
			target.set_meta(TRACED_CELLS, (copy.get_meta(TRACED_CELLS) as Array).duplicate())
		elif target.has_meta(TRACED_CELLS):
			target.remove_meta(TRACED_CELLS)
	_save_items()
	_save_blockout()
	_apply_scene_edits()
	_drop_empty_created()
	save_tile_set()
	var err := MDSWorldSceneTools.repack_safely(root, packed_scene, scene_path)
	if err == OK:
		dirty = false
		_base = _snapshot()
	return err

# --- Changes made elsewhere ----------------------------------------------------------------------

## The room as its scene had it when this painter opened, saved or took in the scene last (a
## [method _snapshot]): what the changes on either side are measured from.
func base_state() -> Dictionary:
	return _base

## Whether two states ([method _snapshot]s) hold the same tiles, hidden tiles and items. The Room
## view's own changes to the scene's other nodes are left out.
static func same_state(a: Dictionary, b: Dictionary) -> bool:
	for n in LAYER_ORDER:
		if not _same_cells(a.get(n, PackedByteArray()), b.get(n, PackedByteArray())):
			return false
	var ha: Dictionary = a.get(&"_blockout", {})
	var hb: Dictionary = b.get(&"_blockout", {})
	for n in ha.keys() + hb.keys():
		if not _same_cells(ha.get(n, PackedByteArray()), hb.get(n, PackedByteArray())):
			return false
	return a.get(&"_items", {}) == b.get(&"_items", {}) and a.get(&"_traced", {}) == b.get(&"_traced", {})

## The scene's other nodes, which the Room view shows around the tiles and items it edits (an
## enemy, a spawn point, a gate...): their paths, classes, scripts, places and visibility. Two
## the same: none of them moved, came or went.
static func scene_fingerprint(scene_root: Node) -> Array:
	var out: Array = []
	for n in scene_root.find_children("*", "", true, false):
		if n.owner != scene_root or n is TileMapLayer or is_item(n, scene_root):
			continue
		var d: Array = [String(scene_root.get_path_to(n)), n.get_class(), n.get_script()]
		if n is Node2D:
			d.append_array([(n as Node2D).transform, (n as Node2D).visible])
		elif n is Control:
			d.append_array([(n as Control).position, (n as Control).size, (n as Control).visible])
		out.append(d)
	return out

## Goes on from [param theirs]: the same room, opened from its scene as it is now, changed
## elsewhere (in the 2D editor). The changes made here and not saved yet are kept, merged with
## the scene's tile by tile and item by item (by name); where both changed the same tile or
## item, the scene's change wins. Undo and redo steps get the scene's changes too. Returns
## [param theirs], holding it all; free this painter after.
func rebase_onto(theirs: MDSRoomPainter) -> MDSRoomPainter:
	var th := theirs._snapshot()
	var mine := _snapshot()
	theirs._restore(merge_states(_base, mine, th))
	for step in _undo:
		theirs._undo.append(merge_states(_base, step, th))
	for step in _redo:
		theirs._redo.append(merge_states(_base, step, th))
	theirs._scene_originals = _scene_originals
	theirs._detached = _detached
	theirs._created.merge(_created)
	theirs.tile_set_dirty = tile_set_dirty
	theirs._base = th
	theirs.dirty = dirty and not same_state(theirs._snapshot(), th)
	return theirs

## Goes on with the items of [param old] (the painter this one goes on from, see
## [method rebase_onto]): its [member items_root] and the item nodes in it become this one's,
## changed in place to this one's settings; this one's items with no node there join them, and
## the nodes this one has no item for go. The same objects go on and never leave the tree, so
## what holds them stays valid: the Inspector showing an effect (it lets go of a node taken out
## of the tree, even for a moment), the Room view's selection. Only what changed changes. Call
## it before freeing [param old].
func keep_items_of(old: MDSRoomPainter) -> void:
	var kept := old.items_root
	for g in ITEM_GROUPS:
		var src := items_root.get_node(g)
		var dst := kept.get_node(g)
		var before: Dictionary = {}
		for o in dst.get_children():
			before[String(o.name)] = o
		var order: Array[Node] = []
		var gone: Dictionary = before.duplicate()
		for n: Node2D in src.get_children():
			var o: Node2D = before.get(String(n.name))
			if is_instance_valid(o) and item_kind(o) == item_kind(n) and o.get_script() == n.get_script():
				_apply_item(o, _item_data(n))
				gone.erase(String(n.name))
				order.append(o)
			else:
				order.append(n)
		# The nodes no item is left for go first, so the new ones keep their names.
		for o: Node in gone.values():
			dst.remove_child(o)
			o.queue_free()
		for n in order:
			if n.get_parent() == src:
				src.remove_child(n)
				dst.add_child(n)
		for i in order.size():
			if order[i].get_index() != i:
				dst.move_child(order[i], i)
	# The two swap: the old painter frees what is left of this one's.
	old.items_root = items_root
	items_root = kept

## Three states ([method _snapshot]s) merged: what [param mine] changed from [param base] put on
## [param theirs], except where [param theirs] changed the same tile or item.
static func merge_states(base: Dictionary, mine: Dictionary, theirs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var traced: Dictionary = {}
	var bt: Dictionary = base.get(&"_traced", {})
	var mt: Dictionary = mine.get(&"_traced", {})
	var tt: Dictionary = theirs.get(&"_traced", {})
	for n in LAYER_ORDER:
		var b: PackedByteArray = base.get(n, PackedByteArray())
		var m: PackedByteArray = mine.get(n, PackedByteArray())
		out[n] = merge_cells(b, m, theirs.get(n, PackedByteArray()))
		# The traced cells go with the tiles of the side that changed them.
		var from: Dictionary = mt if not _same_cells(m, b) else tt
		if from.has(n):
			traced[n] = from[n]
	out[&"_traced"] = traced
	var hidden: Dictionary = {}
	var hb: Dictionary = base.get(&"_blockout", {})
	var hm: Dictionary = mine.get(&"_blockout", {})
	var ht: Dictionary = theirs.get(&"_blockout", {})
	for n in hb.keys() + hm.keys() + ht.keys():
		if not hidden.has(n):
			hidden[n] = merge_cells(hb.get(n, PackedByteArray()), hm.get(n, PackedByteArray()), ht.get(n, PackedByteArray()))
	out[&"_blockout"] = hidden
	var items: Dictionary = {}
	var ib: Dictionary = base.get(&"_items", {})
	var im: Dictionary = mine.get(&"_items", {})
	var it: Dictionary = theirs.get(&"_items", {})
	for g in ITEM_GROUPS:
		items[g] = merge_items(ib.get(g, []), im.get(g, []), it.get(g, []))
	out[&"_items"] = items
	# The scene knows nothing of the Room view's changes to its other nodes: they stay.
	out[&"_scene"] = mine.get(&"_scene", {}).duplicate(true)
	return out

## Three versions of a layer's tile_map_data merged, tile by tile: [param mine]'s changes from
## [param base] put on [param theirs], but for the tiles [param theirs] changed too.
static func merge_cells(base: PackedByteArray, mine: PackedByteArray, theirs: PackedByteArray) -> PackedByteArray:
	if mine == base or mine == theirs:
		return theirs
	if theirs == base:
		return mine
	var bc := cells_of(base)
	var mc := cells_of(mine)
	var tc := cells_of(theirs)
	if mc == bc:
		return theirs
	if tc == bc:
		return mine
	var out := tc.duplicate()
	for c in mc.keys() + bc.keys():
		if mc.get(c) != bc.get(c) and tc.get(c) == bc.get(c):
			if mc.has(c):
				out[c] = mc[c]
			else:
				out.erase(c)
	return data_of(out, theirs if theirs.size() >= 2 else mine)

## The tiles of tile_map_data [param data]: cell -> Vector4i(source id, atlas x, atlas y,
## alternative). Erased cells (kept as empty entries until the layer updates) are left out.
static func cells_of(data: PackedByteArray) -> Dictionary:
	var out: Dictionary = {}
	for i in maxi(0, (data.size() - 2) / 12):
		var at := 2 + i * 12
		var sid := data.decode_s16(at + 4)
		if sid != -1:
			out[Vector2i(data.decode_s16(at), data.decode_s16(at + 2))] = Vector4i(sid, data.decode_u16(at + 6), data.decode_u16(at + 8), data.decode_u16(at + 10))
	return out

## tile_map_data for [param cells] (as [method cells_of] gives them), in the format of
## [param like].
static func data_of(cells: Dictionary, like: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	if cells.is_empty():
		return out
	out.resize(2 + cells.size() * 12)
	out.encode_u16(0, like.decode_u16(0) if like.size() >= 2 else 0)
	var at := 2
	for c: Vector2i in cells:
		var v: Vector4i = cells[c]
		out.encode_s16(at, c.x)
		out.encode_s16(at + 2, c.y)
		out.encode_s16(at + 4, v.x)
		out.encode_u16(at + 6, v.y)
		out.encode_u16(at + 8, v.z)
		out.encode_u16(at + 10, v.w)
		at += 12
	return out

static func _same_cells(a: PackedByteArray, b: PackedByteArray) -> bool:
	return a == b or cells_of(a) == cells_of(b)

## Three versions of an item group ([method _item_data]s) merged, item by item, by name: those
## [param mine] changed, added or removed (from [param base]) and [param theirs] left alone, as
## [param mine] has them; all the others as [param theirs] has them. In [param theirs]' order,
## the ones added here after.
static func merge_items(base: Array, mine: Array, theirs: Array) -> Array:
	var bn := _items_by_name(base)
	var mn := _items_by_name(mine)
	var tn := _items_by_name(theirs)
	var out: Array = []
	for d in theirs:
		var n := str(d.get("name", ""))
		var unchanged_there: bool = bn.has(n) and d == bn[n]
		if unchanged_there and mn.has(n):
			out.append(mn[n])
		elif unchanged_there:
			continue # removed here
		else:
			out.append(d)
	var taken: Dictionary = {}
	for d in out:
		taken[str(d.get("name", ""))] = true
	for d in mine:
		var n := str(d.get("name", ""))
		if bn.has(n) or (tn.has(n) and tn[n] == d):
			continue # it was in the scene (kept or removed above), or both added it
		var added: Dictionary = d
		if taken.has(n):
			# Added on both sides with the same name: this one gets another.
			added = d.duplicate()
			var k := 2
			while taken.has("%s%d" % [n, k]):
				k += 1
			added.name = "%s%d" % [n, k]
		taken[str(added.get("name", ""))] = true
		out.append(added)
	return out

static func _items_by_name(list: Array) -> Dictionary:
	var out: Dictionary = {}
	for d in list:
		out[str(d.get("name", ""))] = d
	return out

## Why the room's scene file is big, when it is bigger than [constant LARGE_TEXT_FILE] (Godot's
## editor then warns that it is large on disk as it saves it); "" when it is not. Its tile
## layers, the biggest first, are the usual reason: each tile takes [constant TILE_FILE_BYTES]
## bytes, a hidden layer's tiles too. Images embedded in it are the other one.
func size_note() -> String:
	var f := FileAccess.open(scene_path, FileAccess.READ)
	if not f or f.get_length() <= LARGE_TEXT_FILE:
		return ""
	var size := f.get_length()
	var images := _embedded_image_bytes(f.get_as_text())
	var heavy: Array = [] # [bytes, what, hidden]
	var free_cells := 0
	for l in root.find_children("*", "TileMapLayer", true, false):
		if l.owner != root:
			continue
		var cells := (l as TileMapLayer).get_used_cells().size()
		if l.has_meta(PIECE_META):
			free_cells += cells
		elif cells > 0:
			heavy.append([cells * TILE_FILE_BYTES, "%s %d tiles" % [l.name, cells], _hidden_in_scene(l)])
	if free_cells > 0:
		heavy.append([free_cells * TILE_FILE_BYTES, "free tiles %d" % free_cells, false])
	if images > 0:
		heavy.append([images, "embedded images", false])
	heavy.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var parts: PackedStringArray = []
	var hidden := false
	for h in heavy.slice(0, 3):
		parts.append("%s (%d KiB%s)" % [h[1], ceili(h[0] / 1024.0), ", hidden" if h[2] else ""])
		hidden = hidden or h[2]
	var advice := "Erase tiles nothing shows, or split a very big room."
	if hidden:
		advice = "A hidden layer's tiles never show but are saved all the same: Clear hidden tiles (Room view) removes them."
	elif images >= LARGE_TEXT_FILE / 4:
		advice = "Save embedded images as PNG files and use those."
	return "%s is %d KiB, so Godot warns that it is large when it saves it. Most of it: %s. %s" % [scene_path.get_file(), ceili(size / 1024.0), ", ".join(parts), advice]

## The tile layers that hold tiles yet are hidden in the scene (a Background hidden in the
## Inspector, say): their tiles never show, and every one of them is saved. Layer name -> tiles.
func hidden_tiles() -> Dictionary:
	var out: Dictionary = {}
	for n in LAYER_ORDER:
		var src: Node = root.get_node_or_null(_source_paths[n]) if _source_paths.has(n) else null
		var cells := (layers[n] as TileMapLayer).get_used_cells().size()
		if src and cells > 0 and _hidden_in_scene(src):
			out[n] = cells
	return out

## Whether [param node] or a parent of it (below the root) is hidden in the scene.
func _hidden_in_scene(node: Node) -> bool:
	var n := node
	while n and n != root:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return true
		n = n.get_parent()
	return false

## Bytes of a .tscn or .tres [param text] that are images embedded in it.
static func _embedded_image_bytes(text: String) -> int:
	var total := 0
	var inside := false
	for line in text.split("\n"):
		if line.begins_with("["):
			inside = line.begins_with("[sub_resource type=\"Image\"") or line.begins_with("[sub_resource type=\"PortableCompressedTexture2D\"")
		if inside:
			total += line.length() + 1
	return total

## Writes the edited freeform shapes and stamps into the scene. Nodes that are still there
## (same group, same name) are updated in place, so an unchanged room saves unchanged; the
## others are added or removed.
func _save_items() -> void:
	var existing: Dictionary = {} # "group/name" -> node
	for node in root.find_children("*", "", true, false):
		if is_instance_valid(node) and node.owner == root and is_item(node, root):
			var parent := node.get_parent()
			var g := String(parent.name) if ITEM_GROUPS.has(String(parent.name)) and parent.get_parent() == root else ""
			existing["%s/%s" % [g, node.name]] = node
	var kept: Dictionary = {}
	for g in ITEM_GROUPS:
		var list := items(g)
		var container: Node2D = root.get_node_or_null(NodePath(g))
		if list.is_empty():
			continue
		if not container:
			container = Node2D.new()
			container.name = g
			container.z_index = ITEM_GROUPS[g]
			root.add_child(container)
			container.owner = root
			_created[g] = true
		var order: Array[Node] = []
		for item in list:
			var node: Node2D = existing.get("%s/%s" % [g, item.name])
			if node and item_kind(node) == item_kind(item) and node.get_script() == item.get_script() and not kept.has(node):
				_apply_item(node, _item_data(item))
			else:
				node = _item_from(_item_data(item))
				node.name = item.name
				container.add_child(node, true)
				node.owner = root
			kept[node] = true
			order.append(node)
		# Same order as in the Room view (only moved when it differs).
		var current: Array[Node] = []
		for c in container.get_children():
			if kept.has(c):
				current.append(c)
		if current != order:
			for node in order:
				container.move_child(node, -1)
	for node: Node in existing.values():
		if not kept.has(node) and is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()

## Sets a scene node's properties from item data, leaving equal values alone.
static func _apply_item(node: Node2D, d: Dictionary) -> void:
	if node is MDSEnvironmentEffect:
		MDSEnvironmentEffect.apply_data(node, d)
		return
	if node is MDSDrawing:
		MDSDrawing.apply_data(node, d)
		return
	if is_tile_piece(node):
		var piece := node as TileMapLayer
		if piece.tile_set != d.tile_set:
			piece.tile_set = d.tile_set
		if piece.tile_map_data != d.cells:
			piece.tile_map_data = d.cells
		if piece.transform != d.transform:
			piece.transform = d.transform
		if piece.z_index != d.z:
			piece.z_index = d.z
		for k in d.meta:
			if not piece.has_meta(k) or piece.get_meta(k) != d.meta[k]:
				piece.set_meta(k, d.meta[k])
		for k in piece.get_meta_list():
			if not d.meta.has(k):
				piece.remove_meta(k)
		return
	if node is MDSFreeform:
		var f := node as MDSFreeform
		var c: Dictionary = d.get("collision", {})
		var values := {"points": d.points, "style": d.style, "solid": d.solid, "smooth": d.smooth, "edge_clumps": d.edge_clumps,
			"seed_value": d.seed, "position": d.position, "override_collision": not c.is_empty()}
		if not c.is_empty():
			values.merge({"role": c.role, "collision_layer": c.layer, "collision_mask": c.mask, "one_way": c.one_way, "one_way_margin": c.margin}, true)
		for k in values:
			if f.get(k) != values[k]:
				f.set(k, values[k])
		var meta: Dictionary = d.get("meta", {})
		for k in meta:
			if not f.has_meta(k) or f.get_meta(k) != meta[k]:
				f.set_meta(k, meta[k])
		for k in f.get_meta_list():
			if not meta.has(k):
				f.remove_meta(k)
		return
	var s := node as Sprite2D
	var values := {"texture": d.texture, "region_rect": d.region, "offset": d.offset, "transform": d.transform}
	for k in values:
		if s.get(k) != values[k]:
			s.set(k, values[k])
	s.region_enabled = true
	s.centered = false
	s.set_meta(&"mds_stamp", d.index)
	var meta: Dictionary = d.get("meta", {})
	for k in meta:
		if not s.has_meta(k) or s.get_meta(k) != meta[k]:
			s.set_meta(k, meta[k])
	for k in s.get_meta_list():
		if k != &"mds_stamp" and not meta.has(k):
			s.remove_meta(k)

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

## Cells (of the Terrain grid) inside the room's shape on the world map: inside its outline
## when it has curved or slanted sides ([param follow_outline]), else its rectangles.
func room_cells(world: MDSWorld, id: String, follow_outline := true) -> Dictionary:
	var out: Dictionary = {}
	var ts := tile_size()
	# A room with curved or slanted sides on the map: only the tiles inside that outline.
	var outline: Array[PackedVector2Array] = []
	if follow_outline:
		outline = world.get_local_shape(id)
	for r in world.get_local_rects(id):
		var c0 := Vector2i((r.position / ts - Vector2(0.5, 0.5)).ceil())
		var c1 := Vector2i((r.end / ts - Vector2(0.5, 0.5)).ceil()) - Vector2i.ONE
		for y in range(c0.y, c1.y + 1):
			for x in range(c0.x, c1.x + 1):
				var at := (Vector2(x, y) + Vector2(0.5, 0.5)) * ts
				if outline.is_empty() or MDSGeometry.point_in_any(outline, at):
					out[cell_at("Terrain", at)] = true
	return out

# --- Tileset introspection ----------------------------------------------------------------------

## Atlas sources a palette can show: [[source_id, name, source], ...] (colors excluded).
func get_atlas_sources() -> Array:
	var out: Array = []
	for i in tile_set.get_source_count():
		var sid := tile_set.get_source_id(i)
		var src := tile_set.get_source(sid) as TileSetAtlasSource
		if not src or not src.texture or src.resource_name in [COLOR_SOURCE_NAME, MDSLegacy.OLD_COLOR_SOURCE_NAME]:
			continue
		var n := src.resource_name
		if n.is_empty():
			var tp := src.texture.resource_path
			n = tp.get_file() if not tp.is_empty() and not "::" in tp else "Tiles #%d" % sid
		out.append([sid, n, src])
	return out

func has_terrains() -> bool:
	return not get_terrains().is_empty()

## [[terrain_set, terrain, name], ...] available in the tileset.
func get_terrains() -> Array:
	var out: Array = []
	for s in tile_set.get_terrain_sets_count():
		for t in tile_set.get_terrains_count(s):
			out.append([s, t, tile_set.get_terrain_name(s, t)])
	return out

## Decoration tiles by "mds_kind" custom data: kind -> Array of [source_id, atlas_coords].
func get_decor_tiles() -> Dictionary:
	var out: Dictionary = {}
	var layer_index := -1
	for i in tile_set.get_custom_data_layers_count():
		if MDSLegacy.is_kind_layer(tile_set.get_custom_data_layer_name(i)):
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

## The room's painted cells that point at tiles its tileset doesn't have (see
## [method is_cell_valid]): layer name -> cells.
func broken_cells() -> Dictionary:
	var out: Dictionary = {}
	for n in LAYER_ORDER:
		var cells := broken_cells_of(layers[n])
		if not cells.is_empty():
			out[n] = cells
	return out

## Whether the tileset has tiles that no longer fit their sheet (see [method is_cell_valid]).
## Godot logs "The TileSetAtlasSource atlas has no tile at ..." for each of them every time it
## loads the tileset.
func has_dropped_tiles() -> bool:
	for i in tile_set.get_source_count():
		var src := tile_set.get_source(tile_set.get_source_id(i)) as TileSetAtlasSource
		if src and src.has_tiles_outside_texture():
			return true
	return false

## Erases the broken cells, and takes the tiles that no longer fit their sheet out of the
## tileset; [method save] then writes the tileset again, so it loads without errors. Cells other
## rooms painted with those tiles draw nothing either way (their scans report them). Call
## [method checkpoint] first to make the cells undoable. Returns how many cells were erased.
func remove_broken_cells() -> int:
	var n := 0
	for layer_name in LAYER_ORDER:
		for c in broken_cells_of(layers[layer_name]):
			layers[layer_name].erase_cell(c)
			n += 1
	for i in tile_set.get_source_count():
		var src := tile_set.get_source(tile_set.get_source_id(i)) as TileSetAtlasSource
		if src and src.has_tiles_outside_texture():
			src.clear_tiles_outside_texture()
			tile_set_dirty = true
	if n > 0:
		# Written again on save, so a tileset already cleaned up in memory reaches its file too.
		dirty = true
		tile_set_dirty = true
	return n

## Erases cells and re-connects the terrain around them.
func erase(layer_name: String, cells: Array) -> void:
	var l: TileMapLayer = layers[layer_name]
	var by_set: Dictionary = {}
	for c in cells:
		var td := cell_tile_data(l, c)
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
				var nd := cell_tile_data(l, n)
				if nd and nd.terrain_set == s and not n in around:
					around.append(n)
		if not around.is_empty():
			var t := cell_tile_data(l, around[0]).terrain
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

## Paints [param cells] of a layer with a fill:
## [code]{type = "terrain", set, terrain}[/code] (autotiled),
## [code]{type = "kind", kind}[/code] (random tiles tagged with that mds_kind),
## [code]{type = "stamp", source, region, random, rotation, flip}[/code] (tiles picked in the
## palette, turned [code]rotation[/code] degrees: on the grid, to the nearest right angle) or
## [code]{type = "color", color}[/code] (a solid color).
func paint_fill(layer_name: String, cells: Array, fill: Dictionary, rng: RandomNumberGenerator = null) -> void:
	match str(fill.get("type", "")):
		"terrain":
			paint_terrain(layer_name, cells, int(fill.get("set", 0)), int(fill.get("terrain", 0)))
		"kind":
			place_kind(layer_name, cells, str(fill.get("kind", "")), rng)
		"stamp":
			place_stamp(layer_name, cells, int(fill.get("source", -1)), fill.get("region", Rect2i()), bool(fill.get("random", false)), rng,
				quarter_turns(float(fill.get("rotation", 0.0))), bool(fill.get("flip", false)))
		"color":
			var t := color_tile(fill.get("color", Color.BLACK))
			for c in cells:
				layers[layer_name].set_cell(c, t[0], t[1], t[2])
			dirty = true

## Tiles picked in the palette. A multi-tile [param region] repeats as a pattern aligned
## to the grid (so large areas tile seamlessly); with [param random], each cell gets a
## random tile from the region instead. The pattern and its tiles are mirrored with
## [param mirror], then turned [param turn] quarter turns clockwise.
func place_stamp(layer_name: String, cells: Array, source_id: int, region: Rect2i, random := false, rng: RandomNumberGenerator = null, turn := 0, mirror := false) -> void:
	var tiles := tiles_in(source_id, region)
	if tiles.is_empty():
		return
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if not rng:
		rng = RandomNumberGenerator.new()
	var basis := Transform2D(posmod(turn, 4) * PI / 2.0, Vector2.ZERO) * (Transform2D.FLIP_X if mirror else Transform2D.IDENTITY)
	basis = right_angle_basis(basis)
	var flags := basis_flags(basis)
	var size := region.size if posmod(turn, 2) == 0 else Vector2i(region.size.y, region.size.x)
	var l: TileMapLayer = layers[layer_name]
	for c: Vector2i in cells:
		if random:
			l.set_cell(c, source_id, tiles[rng.randi_range(0, tiles.size() - 1)], flags)
			continue
		# The turned pattern's cell, back to where it is in the region.
		var u := Vector2(posmod(c.x, size.x), posmod(c.y, size.y)) + Vector2(0.5, 0.5) - Vector2(size) / 2.0
		var at := (basis.basis_xform_inv(u) + Vector2(region.size) / 2.0 - Vector2(0.5, 0.5)).round()
		var t := src.get_tile_at_coords(region.position + Vector2i(at))
		if t != Vector2i(-1, -1):
			l.set_cell(c, source_id, t, flags)
	dirty = true

## Quarter turns (0..3) nearest to [param degrees].
static func quarter_turns(degrees: float) -> int:
	return posmod(roundi(degrees / 90.0), 4)

## [source_id, atlas_coords, alternative] of a solid [param color] tile: one white tile in
## an "MDS colors" source, tinted per color by alternative tiles (created on demand).
func color_tile(color: Color) -> Array:
	var sid := -1
	for i in tile_set.get_source_count():
		var id := tile_set.get_source_id(i)
		if tile_set.get_source(id).resource_name in [COLOR_SOURCE_NAME, MDSLegacy.OLD_COLOR_SOURCE_NAME]:
			sid = id
	var src: TileSetAtlasSource
	if sid < 0:
		src = TileSetAtlasSource.new()
		src.resource_name = COLOR_SOURCE_NAME
		var img := Image.create(tile_set.tile_size.x, tile_set.tile_size.y, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		src.texture = _packed_texture(img)
		src.texture_region_size = tile_set.tile_size
		src.create_tile(Vector2i.ZERO)
		sid = tile_set.add_source(src)
	else:
		src = tile_set.get_source(sid)
	for i in src.get_alternative_tiles_count(Vector2i.ZERO):
		var alt := src.get_alternative_tile_id(Vector2i.ZERO, i)
		if alt != 0 and src.get_tile_data(Vector2i.ZERO, alt).modulate.is_equal_approx(color):
			return [sid, Vector2i.ZERO, alt]
	var new_alt := src.create_alternative_tile(Vector2i.ZERO)
	src.get_tile_data(Vector2i.ZERO, new_alt).modulate = color
	tile_set_dirty = true
	return [sid, Vector2i.ZERO, new_alt]

func clear_layer(layer_name: String) -> void:
	layers[layer_name].clear()
	if layers[layer_name].has_meta(TRACED_CELLS):
		layers[layer_name].remove_meta(TRACED_CELLS)
	dirty = true

# --- Generation ------------------------------------------------------------------------------

## Builds a starting cave from the room's shape on the map: solid walls along the room's
## outline (rough, cellular-automata edges), openings where its gates are, a floor, a few
## ledges, background foliage, then decorations. Rock outside the painted shape fills the
## notches of irregular rooms, and the parts of its rectangles outside a curved or slanted
## outline (see [method MDSWorld.get_local_shape]), so the cave follows the curve.
## [param background] is the fill for the background (default: random "foliage" tiles).
## [param fills] makes it with what is picked in the Room view:
## - "terrain", "background", "decor", "foreground": fills (see [method paint_fill]). Rock is
##   painted with the terrain fill (autotiled or not), the background behind the cave, the
##   decor fill among the floors' decorations, and the foreground in front: a color or a
##   terrain darkens the rock deep in the walls, tiles hang from ceilings and edge floors.
## - "stamps": {set (an [MDSStampSet]), category, group, scale}: stamps along the floors.
## - "paths" (default true): every gate reaches every other one and back, walking, jumping and
##   falling (see [method climb_reach]); where the cave doesn't allow it, tunnels and shafts
##   with ledges to climb are carved, so a player can always go back the way they came.
## - "parts" (default true): a merged room (see [method MDSWorld.merge_rooms]) keeps walls where
##   its old rooms met, with openings where their doors were, each old room reached through
##   them, instead of one big open cave.
func generate_cave(world: MDSWorld, id: String, seed_value := 0, terrain_set := 0, terrain := 0, background: Dictionary = {}, fills: Dictionary = {}) -> void:
	var rock: Dictionary = fills.get("terrain", {})
	if not has_terrains() and (rock.is_empty() or str(rock.get("type", "")) == "terrain"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else hash(id)
	var inside := room_cells(world, id)
	var box := room_cells(world, id, false)
	if inside.is_empty():
		inside = box
	if inside.is_empty():
		return
	# A merged room: walls where its old rooms met (see MDSWorld.merge_rooms).
	var part_of := part_cells(world, id, inside) if bool(fills.get("parts", true)) else {}
	# The whole box of its rectangles is filled: rock wherever the cave doesn't reach.
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in box:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	# Distance of each inside cell to the room outline (4-neighborhood BFS).
	var dist: Dictionary = {}
	var queue: Array = []
	for c in inside:
		var part: int = part_of.get(c, -1)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: int = part_of.get(c + d, -1)
			if not inside.has(c + d) or (part >= 0 and other >= 0 and other != part):
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
	gate_openings.clear()
	for g in world.get_gates(id):
		var gp := world.get_gate_local_pos(id, g)
		var gc := cell_at("Terrain", gp + {"left": Vector2(ts.x, 0), "right": Vector2(-ts.x, 0), "top": Vector2(0, ts.y), "bot": Vector2(0, -ts.y)}.get(world.get_gate_side(id, g), Vector2.ZERO) * 0.5)
		var side := world.get_gate_side(id, g)
		# The doorway: its mouth (the opening's cells at the edge), and the gate's box across it.
		var mouth := Rect2()
		for a in range(-2, 2):
			var m: Vector2i = gc + (Vector2i(0, a) if side == "left" or side == "right" else Vector2i(a, 0))
			mouth = cell_rect("Terrain", m) if a == -2 else mouth.merge(cell_rect("Terrain", m))
		match side:
			"left", "right":
				gate_openings[g] = Rect2(Vector2(gp.x - MDSWorldSceneTools.GATE_SIZE_ACROSS * 0.5, mouth.position.y), Vector2(MDSWorldSceneTools.GATE_SIZE_ACROSS, mouth.size.y))
			"top", "bot":
				gate_openings[g] = Rect2(Vector2(mouth.position.x, gp.y - MDSWorldSceneTools.GATE_SIZE_ACROSS * 0.5), Vector2(mouth.size.x, MDSWorldSceneTools.GATE_SIZE_ACROSS))
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
	# A merged room's old doors: openings through the walls between its parts, ground across
	# side ones, and a place on each side that paths reach.
	var part_ends: Array = []
	var part_ground: Dictionary = {}
	if not part_of.is_empty():
		for d: Dictionary in world.get_part_doors(id):
			var dc := cell_at("Terrain", d.pos)
			var across: bool = d.side == "left" or d.side == "right"
			if not across and d.side != "top" and d.side != "bot":
				continue
			for a in range(-2, 2):
				for depth in range(-6, 7):
					var c: Vector2i = dc + (Vector2i(depth, a) if across else Vector2i(a, depth))
					if inside.has(c):
						open[c] = true
			if across:
				for depth in range(-6, 7):
					if inside.has(dc + Vector2i(depth, 2)):
						part_ground[dc + Vector2i(depth, 2)] = true
			for k in [-8, 8]:
				var e: Vector2i = dc + (Vector2i(k, 1) if across else Vector2i(0, k))
				if inside.has(e):
					part_ends.append({"cell": e, "side": "part", "mouth": dc})
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
	# A walkable floor: the two lowest inside cells of every column (of each old room of a
	# merged one).
	for x in range(lo.x, hi.x + 1):
		var bottom: Dictionary = {}
		for y in range(lo.y, hi.y + 1):
			if inside.has(Vector2i(x, y)):
				bottom[part_of.get(Vector2i(x, y), -1)] = y
		for y: int in bottom.values():
			solid[Vector2i(x, y)] = true
			solid[Vector2i(x, y - 1)] = true
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
	for c in part_ground:
		solid[c] = true
	# Keep the ground under side gates so players can walk in.
	for g in world.get_gates(id):
		var side := world.get_gate_side(id, g)
		if side == "left" or side == "right":
			var gc := cell_at("Terrain", world.get_gate_local_pos(id, g))
			for depth in 7:
				var c := gc + Vector2i(depth if side == "left" else -depth, 2)
				if inside.has(c):
					solid[c] = true
	if bool(fills.get("paths", true)):
		connect_gates(world, id, inside, solid, open, part_ends)
	# The gate nodes go where their doorways now are, their collision across them.
	fit_gate_nodes(gate_openings)
	var terrain_fill: Dictionary = fills.get("terrain", {})
	clear_layer("Terrain")
	if terrain_fill.is_empty() or str(terrain_fill.get("type", "")) == "terrain":
		paint_terrain("Terrain", solid.keys(), int(terrain_fill.get("set", terrain_set)), int(terrain_fill.get("terrain", terrain)))
	else:
		paint_fill("Terrain", solid.keys(), terrain_fill, rng)
	clear_layer("Background")
	# Background behind the cave and just under its walls, not in the rock beyond its outline.
	var back: Dictionary = {}
	for c: Vector2i in inside:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var n := c + Vector2i(dx, dy)
				if n.x >= lo.x and n.x <= hi.x and n.y >= lo.y and n.y <= hi.y:
					back[n] = true
	var back_fill: Dictionary = fills.get("background", background)
	paint_fill("Background", back.keys(), back_fill if not back_fill.is_empty() else {"type": "kind", "kind": "foliage"}, rng)
	var fore_fill: Dictionary = fills.get("foreground", {})
	if not fore_fill.is_empty():
		clear_layer("Foreground")
		_generate_foreground(inside, solid, lo, hi, fore_fill, rng)
	auto_decorate(rng.randi(), true, inside, fills.get("decor", {}))
	var stamps: Dictionary = fills.get("stamps", {})
	if stamps.get("set") is MDSStampSet:
		_generate_stamps(inside, solid, stamps, rng)

## Foreground in front of a generated cave, of [param fill]: a solid color or a terrain fills
## the rock deep inside the walls (three tiles and more from the cave: the room's dark mass);
## tiles (a kind, palette tiles) hang in clusters from ceilings and tuft the floors' edges.
func _generate_foreground(inside: Dictionary, solid: Dictionary, lo: Vector2i, hi: Vector2i, fill: Dictionary, rng: RandomNumberGenerator) -> void:
	var cells: Array = []
	var type := str(fill.get("type", ""))
	if type == "color" or type == "terrain":
		var depth: Dictionary = {}
		var queue: Array[Vector2i] = []
		for c: Vector2i in inside:
			if not solid.has(c):
				depth[c] = 0
				queue.append(c)
		var head := 0
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if solid.has(n) and not depth.has(n) and n.x >= lo.x and n.x <= hi.x and n.y >= lo.y and n.y <= hi.y:
					depth[n] = int(depth[c]) + 1
					queue.append(n)
		for c: Vector2i in solid:
			if int(depth.get(c, 99)) >= 3:
				cells.append(c)
	else:
		var keys: Array = inside.keys()
		keys.sort()
		for c: Vector2i in keys:
			if solid.has(c):
				continue
			if solid.has(c + Vector2i.UP) and rng.randf() < 0.18:
				cells.append(c)
				if not solid.has(c + Vector2i.RIGHT) and inside.has(c + Vector2i.RIGHT):
					cells.append(c + Vector2i.RIGHT)
				if rng.randf() < 0.5 and not solid.has(c + Vector2i.DOWN):
					cells.append(c + Vector2i.DOWN)
			elif solid.has(c + Vector2i.DOWN) and rng.randf() < 0.06:
				cells.append(c)
	paint_fill("Foreground", cells, fill, rng)

## Stamps of [param stamps] ({set, category, group, scale}) along a generated cave's floors, about
## one every ten tiles. The ones an earlier generation scattered are taken out first.
func _generate_stamps(inside: Dictionary, solid: Dictionary, stamps: Dictionary, rng: RandomNumberGenerator) -> void:
	var set_res: MDSStampSet = stamps.set
	var picks := set_res.indices(str(stamps.get("category", "")))
	for g in ["StampsBack", "StampsFront", "StampsForeground"]:
		for st in items(g):
			if st.has_meta(GENERATED_META):
				remove_item(st)
	if picks.is_empty():
		return
	var floors: Array = []
	for c: Vector2i in inside:
		if not solid.has(c) and solid.has(c + Vector2i.DOWN) and not solid.has(c + Vector2i.UP):
			floors.append(c)
	floors.sort()
	for i in range(floors.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = floors[i]
		floors[i] = floors[j]
		floors[j] = t
	var group := str(stamps.get("group", "StampsFront"))
	var scale_value := float(stamps.get("scale", 1.0))
	for k in mini(floors.size() / 10, 40):
		var r := cell_rect("Terrain", floors[k])
		var size := scale_value * rng.randf_range(0.8, 1.2)
		var st := add_stamp(set_res, picks[rng.randi_range(0, picks.size() - 1)], Vector2(r.get_center().x, r.end.y), Vector2(size * (-1.0 if rng.randf() < 0.5 else 1.0), size), 0.0, group)
		st.set_meta(GENERATED_META, true)

# --- Paths through a room ------------------------------------------------------------------------

## Makes every gate of room [param id] reachable from every other one and back in a generated
## cave ([param inside]: the room's cells, [param solid]: its rock, changed in place, [param keep]:
## cells that must stay open). Where the cave doesn't allow it, a path is carved from the first
## gate through the room's own cells (off its edges, in long straight runs): tunnels as tall as
## the player, floored over drops too deep to climb out of, and shafts with ledges to climb.
## [param extra_ends] are more places to join ({cell, side, mouth}, like [method gate_end]'s),
## such as the doors between a merged room's parts.
func connect_gates(world: MDSWorld, id: String, inside: Dictionary, solid: Dictionary, keep: Dictionary = {}, extra_ends: Array = []) -> void:
	var ts := tile_size()
	var player := MDSRoomCheck.PLAYER_DEFAULTS.duplicate()
	player.merge(world.get_setting("player", {}), true)
	var tall := clampi(ceili(float(player.size[1]) / ts.y) + 1, 3, 8)
	var jump_px := MDSRoomCheck.max_jump_height(float(player.jump_velocity), float(player.gravity))
	var reach := clampi(floori(jump_px * 0.8 / ts.y), 2, 10)
	var step := clampi(floori(jump_px * 0.55 / ts.y), 2, mini(reach, 5))
	var ends: Array = []
	for g in world.get_gates(id):
		var e := gate_end(world, id, g, inside)
		if not e.is_empty():
			ends.append(e)
	ends.append_array(extra_ends)
	if ends.size() < 2:
		return
	var clearance := _clearance(inside)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, "paths"])
	# A carving can cut another way off (a tunnel's floor across a chamber): checked again.
	for attempt in 3:
		var all_ok := true
		# What the first end reaches, worked out again only after a carving.
		var reached: Dictionary = {}
		for i in range(1, ends.size()):
			if reached.is_empty():
				var open_cells := _open_cells(inside, solid)
				var land := land_map(open_cells)
				reached = {"open": open_cells, "land": land, "from": climb_reach(open_cells, ends[0].cell, reach, 3, land)}
			var from_i := climb_reach(reached.open, ends[i].cell, reach, 3, reached.land)
			if _arrives(reached.from, ends[i], reached.open, reached.land, reach) and _arrives(from_i, ends[0], reached.open, reached.land, reach):
				continue
			all_ok = false
			reached = {}
			var path := _inner_path(inside, clearance, ends[0].cell, ends[i].cell, rng, attempt)
			var k := 0
			while k < path.size() - 1:
				# One straight run at a time.
				var d: Vector2i = path[k + 1] - path[k]
				var e := k + 1
				while e + 1 < path.size() and path[e + 1] - path[e] == d:
					e += 1
				_carve_leg(path[k], path[e], inside, solid, keep, tall, step, reach)
				k = e
		if all_ok:
			break

## How far each of [param inside]'s cells is from the room's edge (1: on it), up to 4.
static func _clearance(inside: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var queue: Array[Vector2i] = []
	for c: Vector2i in inside:
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not inside.has(c + d):
				out[c] = 1
				queue.append(c)
				break
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if int(out[c]) >= 4:
			continue
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if inside.has(n) and not out.has(n):
				out[n] = int(out[c]) + 1
				queue.append(n)
	return out

## The cells from [param a] to [param b] through [param inside]: off the room's edges where it
## can be, and turning seldom (long straight runs). [param attempt] above 0 varies it.
static func _inner_path(inside: Dictionary, clearance: Dictionary, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator, attempt := 0) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var cost: Dictionary = {}
	var prev: Dictionary = {}
	var buckets: Array = [[]]
	for d in 4:
		var key := Vector3i(a.x, a.y, d)
		cost[key] = 0
		buckets[0].append(key)
	var found := Vector3i(-1, -1, -1)
	var at := 0
	while at < buckets.size():
		if buckets[at].is_empty():
			at += 1
			continue
		var key: Vector3i = buckets[at].pop_back()
		if int(cost[key]) != at:
			continue
		var c := Vector2i(key.x, key.y)
		if c == b:
			found = key
			break
		for nd in 4:
			var n: Vector2i = c + dirs[nd]
			if not inside.has(n):
				continue
			var step_cost := 1 + (4 - mini(int(clearance.get(n, 4)), 4)) * 2 + (4 if nd != key.z else 0)
			if attempt > 0:
				step_cost += rng.randi_range(0, 2 * attempt)
			var nk := Vector3i(n.x, n.y, nd)
			var nc := at + step_cost
			if not cost.has(nk) or nc < int(cost[nk]):
				cost[nk] = nc
				prev[nk] = key
				while buckets.size() <= nc:
					buckets.append([])
				buckets[nc].append(nk)
	var out: Array[Vector2i] = []
	if found.x == -1 and found.y == -1 and found.z == -1:
		return out
	var k: Variant = found
	while k != null:
		out.push_front(Vector2i(k.x, k.y))
		k = prev.get(k)
	return out

## A merged room's cells by the old room each is in (see [method MDSWorld.get_room_parts]):
## cell -> part index, for the cells of [param inside]. Empty when the room isn't merged.
func part_cells(world: MDSWorld, id: String, inside: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var parts := world.get_room_parts(id)
	if parts.size() < 2:
		return out
	var ts := tile_size()
	for i in parts.size():
		for r: Rect2 in parts[i]:
			var c0 := Vector2i((r.position / ts - Vector2(0.5, 0.5)).ceil())
			var c1 := Vector2i((r.end / ts - Vector2(0.5, 0.5)).ceil()) - Vector2i.ONE
			for y in range(c0.y, c1.y + 1):
				for x in range(c0.x, c1.x + 1):
					var c := cell_at("Terrain", (Vector2(x, y) + Vector2(0.5, 0.5)) * ts)
					if inside.has(c) and not out.has(c):
						out[c] = i
	return out

## Where gate [param gate_name] of room [param id] leads into the room: {cell (where the player
## stands or arrives, a few tiles in), side, mouth (the opening's cell at the room's edge)}, or
## {} when it is outside the room.
func gate_end(world: MDSWorld, id: String, gate_name: String, inside: Dictionary) -> Dictionary:
	var ts := tile_size()
	var side := world.get_gate_side(id, gate_name)
	var inward: Vector2i = {"left": Vector2i.RIGHT, "right": Vector2i.LEFT, "top": Vector2i.DOWN, "bot": Vector2i.UP}.get(side, Vector2i.ZERO)
	var gc := cell_at("Terrain", world.get_gate_local_pos(id, gate_name) + Vector2(inward) * ts * 0.5)
	var cell := gc + inward * 4
	if side == "left" or side == "right":
		cell.y += 1
	if not inside.has(cell):
		return {}
	return {"cell": cell, "side": side, "mouth": gc}

func _open_cells(inside: Dictionary, solid: Dictionary) -> Dictionary:
	var open: Dictionary = {}
	for c in inside:
		if not solid.has(c):
			open[c] = true
	return open

## Whether a player gets from gate end [param a] to [param b] and back.
func _both_ways(inside: Dictionary, solid: Dictionary, a: Dictionary, b: Dictionary, reach: int) -> bool:
	var open := _open_cells(inside, solid)
	var land := land_map(open)
	var from_a := climb_reach(open, a.cell, reach, 3, land)
	var from_b := climb_reach(open, b.cell, reach, 3, land)
	return _arrives(from_a, b, open, land, reach) and _arrives(from_b, a, open, land, reach)

## Whether standing cells [param reached] get the player out through gate end [param e]: to where
## it stands for a side or bottom gate, near enough under the mouth to jump out for a top one.
static func _arrives(reached: Dictionary, e: Dictionary, open: Dictionary, land: Dictionary, reach: int) -> bool:
	if e.side == "top":
		var mouth: Vector2i = e.mouth
		for s: Vector2i in reached:
			if absi(s.x - mouth.x) <= 2 and s.y - mouth.y <= reach:
				return true
		return false
	return reached.has(land.get(e.cell, e.cell))

## Carves a straight leg from [param p] to [param q]: across, a tunnel [param tall] tiles high,
## floored where it crosses a drop deeper than [param reach] rows (that a player falling in
## couldn't climb out of); up or down, a shaft four tiles wide with ledges every [param step]
## rows, on alternate sides, to climb back up.
func _carve_leg(p: Vector2i, q: Vector2i, inside: Dictionary, solid: Dictionary, keep: Dictionary, tall: int, step: int, reach := 6) -> void:
	var clear := func(c: Vector2i) -> void:
		if inside.has(c):
			solid.erase(c)
	var fill := func(c: Vector2i) -> void:
		if inside.has(c) and not keep.has(c):
			solid[c] = true
	if p.y == q.y:
		for x in range(mini(p.x, q.x) - 1, maxi(p.x, q.x) + 2):
			for dy in tall:
				clear.call(Vector2i(x, p.y - dy))
			var deep := true
			for dy in range(1, reach + 2):
				var below := Vector2i(x, p.y + dy)
				if not inside.has(below) or solid.has(below):
					deep = false
					break
			if deep:
				fill.call(Vector2i(x, p.y + 1))
		return
	var x0 := p.x - 1
	var top := mini(p.y, q.y)
	var bottom := maxi(p.y, q.y)
	for y in range(top - tall + 1, bottom + 1):
		for dx in 4:
			clear.call(Vector2i(x0 + dx, y))
	for dx in 4:
		fill.call(Vector2i(x0 + dx, bottom + 1))
	# Ledges half the shaft wide, so there is room to drop past them; they may stand in a gate's
	# opening (the top one is what a player jumps out of a top gate from).
	var left := true
	var y := bottom + 1 - step
	while y > top + 1:
		for dx in 2:
			var c := Vector2i(x0 + dx + (0 if left else 2), y)
			if inside.has(c):
				solid[c] = true
		left = not left
		y -= step

## The cell each of [param open]'s cells falls to: the open cell over solid ground under it.
static func land_map(open: Dictionary) -> Dictionary:
	var cells: Array = open.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	var land: Dictionary = {}
	for c: Vector2i in cells:
		var below: Vector2i = c + Vector2i.DOWN
		land[c] = land.get(below, below) if open.has(below) else c
	return land

## The cells a player standing at (or let go at) [param from] can stand on, moving through the
## [param open] tile cells: walking, jumping up to [param jump_h] tiles and across [param jump_w],
## and falling. A rough platformer reach, to check a room can be crossed (and backtracked).
static func climb_reach(open: Dictionary, from: Vector2i, jump_h := 4, jump_w := 3, land: Dictionary = {}) -> Dictionary:
	if land.is_empty():
		land = land_map(open)
	var seen: Dictionary = {}
	if not open.has(from):
		return seen
	var start: Vector2i = land[from]
	seen[start] = true
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var s: Vector2i = todo.pop_back()
		var rise := 0
		while rise < jump_h and open.has(s + Vector2i(0, -(rise + 1))):
			rise += 1
		for up in rise + 1:
			for dir in [-1, 1]:
				for dx in range(1, jump_w + 1):
					var c := Vector2i(s.x + dir * dx, s.y - up)
					if not open.has(c):
						break
					var n: Vector2i = land[c]
					if not seen.has(n):
						seen[n] = true
						todo.append(n)
	return seen

## Grass and plants on floors, stalactites, vines and moss under ceilings. With
## [param allowed] (cells), decorations stay inside those cells (the room's shape). With
## [param floor_fill] (a fill, see [method paint_fill]), most floor decorations are of it.
func auto_decorate(seed_value := 0, clear := true, allowed: Dictionary = {}, floor_fill: Dictionary = {}) -> int:
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
			if not kind.is_empty() and not floor_fill.is_empty() and rng.randf() < 0.6:
				paint_fill("Decor", [above], floor_fill, rng)
				placed += 1
				kind = ""
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

# --- Spritesheets --------------------------------------------------------------------------

## Adds a spritesheet (PNG...) to the tileset as a new atlas source and returns its id
## (-1 on failure). Fully transparent cells are skipped. A sheet whose tiles are not the
## tileset's tile size is scaled (nearest) to fit the grid. The tileset links to the image
## files (see [method _file_texture]), so it stays small. With [param collision], every
## tile gets a full-tile collision shape (for terrain).
func add_sheet(texture_path: String, sheet_tile: Vector2i, margin := Vector2i.ZERO, separation := Vector2i.ZERO, collision := false) -> int:
	if sheet_tile.x <= 0 or sheet_tile.y <= 0:
		return -1
	var tex := _sheet_texture(texture_path)
	if not tex:
		return -1
	var img := tex.get_image()
	if not img:
		return -1
	if img.is_compressed():
		img.decompress()
	var grid := tile_set.tile_size
	var src := TileSetAtlasSource.new()
	src.resource_name = texture_path.get_file().get_basename()
	if sheet_tile != grid:
		var factor := Vector2(grid) / Vector2(sheet_tile)
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(maxi(1, roundi(img.get_width() * factor.x)), maxi(1, roundi(img.get_height() * factor.y)), Image.INTERPOLATE_NEAREST)
		margin = Vector2i((Vector2(margin) * factor).round())
		separation = Vector2i((Vector2(separation) * factor).round())
		src.texture = _file_texture(img, scaled_sheet_path(texture_path, sheet_tile, grid, img))
	else:
		src.texture = tex
	src.texture_region_size = grid
	src.margins = margin
	src.separation = separation
	var cols := (img.get_width() - margin.x + separation.x) / (grid.x + separation.x)
	var rows := (img.get_height() - margin.y + separation.y) / (grid.y + separation.y)
	var sid := tile_set.add_source(src)
	var created: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			var r := Rect2i(margin + Vector2i(x, y) * (grid + separation), grid)
			if img.get_region(r).is_invisible():
				continue
			src.create_tile(Vector2i(x, y))
			created.append(Vector2i(x, y))
	if created.is_empty():
		tile_set.remove_source(sid)
		return -1
	if collision:
		set_collision(sid, created, true)
	tile_set_dirty = true
	save_tile_set()
	return sid

## Where a sheet scaled to the room grid is saved: named for both tile sizes
## ([code]fx_96x96_to_32x32.png[/code]), next to the sheet. The same sheet added again with
## another tile size gets a file of its own, and a file already there with other pixels is never
## overwritten: an atlas source still uses it, and a smaller image would shrink its atlas, losing
## the tiles past the new edge (and every cell painted with them).
static func scaled_sheet_path(texture_path: String, sheet_tile: Vector2i, grid: Vector2i, img: Image) -> String:
	var stem := "%s/%s_%dx%d_to_%dx%d" % [texture_path.get_base_dir(), texture_path.get_file().get_basename(), sheet_tile.x, sheet_tile.y, grid.x, grid.y]
	var path := stem + ".png"
	var n := 2
	while FileAccess.file_exists(path) and not _same_pixels(path, img):
		path = "%s_%d.png" % [stem, n]
		n += 1
	return path

static func _same_pixels(path: String, img: Image) -> bool:
	var other := Image.load_from_file(ProjectSettings.globalize_path(path))
	if not other or other.get_size() != img.get_size():
		return false
	other.convert(img.get_format())
	return other.get_data() == img.get_data()

## The sheet at [param path] as an imported texture. A file the editor has not imported
## yet (just copied into the project) is imported first: reading the raw file instead
## would end up embedding every pixel in the tileset.
static func _sheet_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var fs := _editor_files()
	if fs and path.begins_with("res://") and FileAccess.file_exists(path):
		fs.update_file(path)
		fs.reimport_files(PackedStringArray([path]))
		if ResourceLoader.exists(path):
			return ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	var raw := Image.load_from_file(path)
	return _packed_texture(raw) if raw else null

## A texture for [param img] that a tileset can reference cheaply. In the editor it is
## saved as a PNG at [param path] and imported, so the tileset only links to it; embedding
## the raw pixels makes the .tres huge (a 3232x2208 sheet is about 100 MB of text).
## Elsewhere it is embedded losslessly compressed.
static func _file_texture(img: Image, path: String) -> Texture2D:
	var fs := _editor_files()
	if fs and path.begins_with("res://") and img.save_png(path) == OK:
		fs.update_file(path)
		fs.reimport_files(PackedStringArray([path]))
		var tex := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
		if tex:
			return tex
	return _packed_texture(img)

static func _packed_texture(img: Image) -> Texture2D:
	var packed := PortableCompressedTexture2D.new()
	# Outside the editor it would let go of its data once made, and save without it.
	packed.keep_compressed_buffer = true
	packed.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	return packed

## Packs again the images packed into [param ts] that let go of their data, so saving it keeps
## them: outside the editor, one loaded from a file does (it is set to keep its data only
## after the data is read).
static func _keep_packed(ts: TileSet) -> void:
	for i in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(i)) as TileSetAtlasSource
		var tex := src.texture as PortableCompressedTexture2D if src else null
		if not tex or (not tex.resource_path.is_empty() and not "::" in tex.resource_path):
			continue
		if not (tex.get(&"_data") as PackedByteArray).is_empty():
			continue
		var img := tex.get_image()
		if img:
			tex.keep_compressed_buffer = true
			tex.create_from_image(img, tex.get_compression_mode())

static func _editor_files() -> Object:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		return Engine.get_singleton(&"EditorInterface").get_resource_filesystem()
	return null

## Takes the images embedded in [param ts] out of it: the starter atlas and the solid colors'
## tile of older versions, sheets from files that were not imported yet. Godot writes an
## embedded image out byte by byte, so even a small atlas makes a tileset of hundreds of KiB
## that is slow to save and load. In the editor, images of [constant SHEET_FILE_PIXELS] or
## more become PNG files next to the tileset, linked instead; the others, and all of them
## outside the editor, are packed into it, compressed without loss. The tiles look the same.
## Returns how many were taken out; the tileset is saved when any were.
static func externalize_sheets(ts: TileSet) -> int:
	var base := ts.resource_path
	if base.is_empty() or "::" in base:
		return 0
	var moved := 0
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if not src or not src.texture is ImageTexture:
			continue
		if not src.texture.resource_path.is_empty() and not "::" in src.texture.resource_path:
			continue
		var img: Image = src.texture.get_image()
		if not img:
			continue
		var tex: Texture2D = null
		if _editor_files() and img.get_width() * img.get_height() >= SHEET_FILE_PIXELS:
			tex = _file_texture(img, _sheet_file_path(ts, src, sid, img))
		src.texture = tex if tex else _packed_texture(img)
		moved += 1
	if moved > 0:
		_keep_packed(ts)
		ResourceSaver.save(ts, base)
	return moved

## Where [method externalize_sheets] saves [param src]'s image: the starter atlas's own PNG
## next to the tileset when it is still that image, else a new file named after the sheet.
static func _sheet_file_path(ts: TileSet, src: TileSetAtlasSource, sid: int, img: Image) -> String:
	var base := ts.resource_path
	var own := base.get_basename() + ".png"
	if src.resource_name.is_empty() and FileAccess.file_exists(own):
		var on_disk := Image.new()
		if on_disk.load_png_from_buffer(FileAccess.get_file_as_bytes(own)) == OK:
			on_disk.convert(img.get_format())
			if on_disk.get_size() == img.get_size() and on_disk.get_data() == img.get_data():
				return own
	var stem := "%s_%s" % [base.get_basename(), src.resource_name.validate_filename() if not src.resource_name.is_empty() else "sheet%d" % sid]
	var path := stem + ".png"
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s_%d.png" % [stem, n]
		n += 1
	return path

## Removes a sheet from the tileset (tiles painted from it disappear).
func remove_sheet(source_id: int) -> void:
	if tile_set.has_source(source_id):
		tile_set.remove_source(source_id)
		tile_set_dirty = true
		save_tile_set()

## Tiles of [param source_id] inside [param region] (atlas coords of existing tiles).
func tiles_in(source_id: int, region: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var src: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource if tile_set.has_source(source_id) else null
	if not src:
		return out
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var t := src.get_tile_at_coords(Vector2i(x, y))
			if t != Vector2i(-1, -1) and not t in out:
				out.append(t)
	return out

## Gives tiles a full-tile collision shape (solid ground) or removes it.
func set_collision(source_id: int, coords: Array, solid: bool) -> void:
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if not src:
		return
	if tile_set.get_physics_layers_count() == 0:
		tile_set.add_physics_layer()
	for c: Vector2i in coords:
		var half := Vector2(src.texture_region_size * src.get_tile_size_in_atlas(c)) / 2.0
		for ai in src.get_alternative_tiles_count(c):
			var td := src.get_tile_data(c, src.get_alternative_tile_id(c, ai))
			while td.get_collision_polygons_count(0) > 0:
				td.remove_collision_polygon(0, 0)
			if solid:
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]))
	tile_set_dirty = true

func is_solid(source_id: int, coords: Vector2i) -> bool:
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	return src != null and tile_set.get_physics_layers_count() > 0 and src.has_tile(coords) and src.get_tile_data(coords, 0).get_collision_polygons_count(0) > 0

## Tags tiles with an mds_kind ("grass", "foliage", "vine_top"...) so Auto-decorate,
## Generate cave and the kind fills use them. An empty kind removes the tag.
func tag_tiles(source_id: int, coords: Array, kind: String) -> void:
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if not src:
		return
	var layer_index := _kind_layer()
	for c: Vector2i in coords:
		src.get_tile_data(c, 0).set_custom_data_by_layer_id(layer_index, kind)
	tile_set_dirty = true

func get_tile_kind(source_id: int, coords: Vector2i) -> String:
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	for i in tile_set.get_custom_data_layers_count():
		if MDSLegacy.is_kind_layer(tile_set.get_custom_data_layer_name(i)) and src and src.has_tile(coords):
			return str(src.get_tile_data(coords, 0).get_custom_data_by_layer_id(i))
	return ""

func _kind_layer() -> int:
	for i in tile_set.get_custom_data_layers_count():
		if MDSLegacy.is_kind_layer(tile_set.get_custom_data_layer_name(i)):
			return i
	tile_set.add_custom_data_layer()
	var index := tile_set.get_custom_data_layers_count() - 1
	tile_set.set_custom_data_layer_name(index, MDSTilesetFactory.KIND_LAYER)
	tile_set.set_custom_data_layer_type(index, TYPE_STRING)
	return index

## Turns a block of palette tiles into an autotiling terrain, in a terrain set of its own.
## [param region] is either a 3x3 box (corners, edges and fill, the usual platformer
## layout) or 4x4 tiles ordered by connected sides (index = 1 right + 2 bottom + 4 left
## + 8 top, like MDS's starter tileset). Returns Vector2i(terrain set, terrain), or
## (-1, -1) when the region has another size.
func make_terrain(source_id: int, region: Rect2i, terrain_name: String, color: Color, collision := true) -> Vector2i:
	var src: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource if tile_set.has_source(source_id) else null
	if not src or not (region.size == Vector2i(3, 3) or region.size == Vector2i(4, 4)):
		return Vector2i(-1, -1)
	var set_index := tile_set.get_terrain_sets_count()
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(set_index, TileSet.TERRAIN_MODE_MATCH_SIDES)
	tile_set.add_terrain(set_index)
	tile_set.set_terrain_name(set_index, 0, terrain_name)
	tile_set.set_terrain_color(set_index, 0, color)
	var sides := [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE]
	var used: Array[Vector2i] = []
	for y in region.size.y:
		for x in region.size.x:
			var coords := region.position + Vector2i(x, y)
			if not src.has_tile(coords):
				continue
			var mask := 0
			if region.size.x == 3:
				mask = (1 if x < 2 else 0) | (2 if y < 2 else 0) | (4 if x > 0 else 0) | (8 if y > 0 else 0)
			else:
				mask = y * 4 + x
			var td := src.get_tile_data(coords, 0)
			td.terrain_set = set_index
			td.terrain = 0
			for i in 4:
				td.set_terrain_peering_bit(sides[i], 0 if mask & (1 << i) else -1)
			used.append(coords)
	if region.size.x == 3:
		# A 3x3 box has no tiles for 1-tile-wide pieces (columns, ledges, single blocks), so
		# the autotiler would leave them empty. Alternative tiles reuse the closest art.
		var fallbacks := {0: Vector2i(1, 0), 1: Vector2i(0, 0), 2: Vector2i(1, 0), 4: Vector2i(2, 0), 5: Vector2i(1, 0), 8: Vector2i(1, 2), 10: Vector2i(1, 1)}
		for mask in fallbacks:
			var coords: Vector2i = region.position + fallbacks[mask]
			if not src.has_tile(coords):
				continue
			var alt := src.create_alternative_tile(coords)
			var td := src.get_tile_data(coords, alt)
			td.terrain_set = set_index
			td.terrain = 0
			for i in 4:
				td.set_terrain_peering_bit(sides[i], 0 if mask & (1 << i) else -1)
	if collision:
		set_collision(source_id, used, true)
	tile_set_dirty = true
	save_tile_set()
	return Vector2i(set_index, 0)

## Saves the tileset when it is its own resource file (a tileset embedded in the scene is
## saved with the scene).
func save_tile_set() -> Error:
	# Saved here, or with the scene when it is embedded in it.
	_keep_packed(tile_set)
	if not tile_set_dirty:
		return OK
	var p := tile_set.resource_path
	if p.is_empty() or "::" in p:
		dirty = true
		return OK
	tile_set_dirty = false
	return ResourceSaver.save(tile_set, p)
