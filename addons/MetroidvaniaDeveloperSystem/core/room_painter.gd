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

const LAYER_Z := {"Background": -10, "Terrain": 0, "Decor": 5, "Foreground": 20}
const LAYER_ORDER: PackedStringArray = ["Background", "Terrain", "Decor", "Foreground"]
## Groups of freeform shapes, stamps and effects (nodes of that name in the scene) and their
## z. Effects draw at their own z_index.
const ITEM_GROUPS := {
	"FreeformBack": -8, "StampsBack": -6, "Freeform": 1, "StampsFront": 6,
	"FreeformFront": 22, "StampsForeground": 24, "Effects": 0,
}
## The group environment effects are kept in. Effects elsewhere in the scene are left alone.
const EFFECTS_GROUP := "Effects"

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

const COLOR_SOURCE_NAME := "MDS colors"
## The name the color source had before the IDP to MDS rename (still recognized).
const LEGACY_COLOR_SOURCE_NAME := "IDP colors"
const MAX_UNDO := 60

static func open(path: String, default_tile_set: TileSet = null) -> MDSRoomPainter:
	var packed := load(path) as PackedScene
	if not packed:
		return null
	var p := MDSRoomPainter.new()
	p.scene_path = path
	p.packed_scene = packed
	p.root = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var found: Dictionary = {}
	var all_layers: Array = p.root.find_children("*", "TileMapLayer", true, false).filter(func(l: Node) -> bool: return not l.has_meta(&"idp_blockout"))
	for layer in all_layers:
		if layer.name in LAYER_Z and not found.has(String(layer.name)):
			found[String(layer.name)] = layer
	for layer in p.root.find_children("*Blockout", "TileMapLayer", true, false):
		var base := String(layer.name).trim_suffix("Blockout")
		if base in LAYER_Z and layer.has_meta(&"idp_blockout") and not p.blockout.has(base):
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
		if node.owner != p.root or not (node is MDSFreeform or is_stamp(node) or is_room_effect(node, p.root)):
			continue
		var parent_name := String(node.get_parent().name)
		var group := parent_name if ITEM_GROUPS.has(parent_name) else ("Freeform" if node is MDSFreeform else "StampsFront")
		if node is MDSEnvironmentEffect:
			group = EFFECTS_GROUP
		var copy: Node2D = node.duplicate()
		copy.transform = _local_transform(node, p.root)
		p.items_root.get_node(group).add_child(copy)
	return p

static func is_stamp(node: Node) -> bool:
	return node is Sprite2D and node.has_meta(&"idp_stamp")

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

## "freeform", "stamp" or "effect".
static func item_kind(node: Node) -> String:
	if node is MDSFreeform:
		return "freeform"
	if node is MDSEnvironmentEffect:
		return "effect"
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
	for n in LAYER_ORDER:
		out[n] = layers[n].tile_map_data
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
	if node is MDSFreeform or node is MDSEnvironmentEffect:
		var d: Dictionary = node.to_data()
		d.kind = item_kind(node)
		return d
	var s := node as Sprite2D
	var meta: Dictionary = {}
	for k in s.get_meta_list():
		if k != &"idp_stamp":
			meta[k] = s.get_meta(k)
	return {"kind": "stamp", "texture": s.texture, "region": s.region_rect, "offset": s.offset,
		"transform": s.transform, "index": s.get_meta(&"idp_stamp", 0), "meta": meta}

static func _item_from(d: Dictionary) -> Node2D:
	if d.kind == "freeform":
		return MDSFreeform.from_data(d)
	if d.kind == "effect":
		return MDSEnvironmentEffect.from_data(d)
	var s := Sprite2D.new()
	s.texture = d.texture
	s.region_enabled = true
	s.region_rect = d.region
	s.centered = false
	s.offset = d.offset
	s.transform = d.transform
	s.set_meta(&"idp_stamp", d.index)
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

## The effects the Room view edits.
func effects() -> Array:
	return items(EFFECTS_GROUP)

## The top-most effect whose area holds [param p] (scene-local), or null.
func effect_at(p: Vector2) -> MDSEnvironmentEffect:
	var list := effects()
	for i in range(list.size() - 1, -1, -1):
		var e: MDSEnvironmentEffect = list[i]
		if e.get_effect_rect().has_point(e.transform.affine_inverse() * p):
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
		l.set_meta(&"idp_blockout", true)
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
			"position": node.position if node is Node2D else Vector2.ZERO, "blockout": node.has_meta(&"idp_blockout")}
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
		if not o.blockout and n.has_meta(&"idp_blockout"):
			n.remove_meta(&"idp_blockout")
	for p in scene_edits:
		var n := root.get_node_or_null(NodePath(p))
		if not n:
			continue
		var e: Dictionary = scene_edits[p]
		if e.has("position") and n is Node2D:
			n.position = e.position
		if e.get("removed", false):
			_detached[p] = [n, root.get_path_to(n.get_parent()), n.get_index()]
			n.get_parent().remove_child(n)
		elif e.get("hidden", false):
			if n is CanvasItem:
				n.visible = false
			n.process_mode = Node.PROCESS_MODE_DISABLED
			n.set_meta(&"idp_blockout", true)

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
			target.set_meta(&"idp_blockout", true)
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
	_save_items()
	_save_blockout()
	_apply_scene_edits()
	_drop_empty_created()
	save_tile_set()
	var err := MDSWorldSceneTools.repack_safely(root, packed_scene, scene_path)
	if err == OK:
		dirty = false
	return err

## Writes the edited freeform shapes and stamps into the scene. Nodes that are still there
## (same group, same name) are updated in place, so an unchanged room saves unchanged; the
## others are added or removed.
func _save_items() -> void:
	var existing: Dictionary = {} # "group/name" -> node
	for node in root.find_children("*", "", true, false):
		if is_instance_valid(node) and node.owner == root and (node is MDSFreeform or is_stamp(node) or is_room_effect(node, root)):
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
	s.set_meta(&"idp_stamp", d.index)
	var meta: Dictionary = d.get("meta", {})
	for k in meta:
		if not s.has_meta(k) or s.get_meta(k) != meta[k]:
			s.set_meta(k, meta[k])
	for k in s.get_meta_list():
		if k != &"idp_stamp" and not meta.has(k):
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

## Cells (of the Terrain grid) inside the room's shape on the world map.
func room_cells(world: MDSWorld, id: String) -> Dictionary:
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

## Atlas sources a palette can show: [[source_id, name, source], ...] (colors excluded).
func get_atlas_sources() -> Array:
	var out: Array = []
	for i in tile_set.get_source_count():
		var sid := tile_set.get_source_id(i)
		var src := tile_set.get_source(sid) as TileSetAtlasSource
		if not src or not src.texture or src.resource_name in [COLOR_SOURCE_NAME, LEGACY_COLOR_SOURCE_NAME]:
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
## [code]{type = "kind", kind}[/code] (random tiles tagged with that idp_kind),
## [code]{type = "stamp", source, region, random}[/code] (tiles picked in the palette) or
## [code]{type = "color", color}[/code] (a solid color).
func paint_fill(layer_name: String, cells: Array, fill: Dictionary, rng: RandomNumberGenerator = null) -> void:
	match str(fill.get("type", "")):
		"terrain":
			paint_terrain(layer_name, cells, int(fill.get("set", 0)), int(fill.get("terrain", 0)))
		"kind":
			place_kind(layer_name, cells, str(fill.get("kind", "")), rng)
		"stamp":
			place_stamp(layer_name, cells, int(fill.get("source", -1)), fill.get("region", Rect2i()), bool(fill.get("random", false)), rng)
		"color":
			var t := color_tile(fill.get("color", Color.BLACK))
			for c in cells:
				layers[layer_name].set_cell(c, t[0], t[1], t[2])
			dirty = true

## Tiles picked in the palette. A multi-tile [param region] repeats as a pattern aligned
## to the grid (so large areas tile seamlessly); with [param random], each cell gets a
## random tile from the region instead.
func place_stamp(layer_name: String, cells: Array, source_id: int, region: Rect2i, random := false, rng: RandomNumberGenerator = null) -> void:
	var tiles := tiles_in(source_id, region)
	if tiles.is_empty():
		return
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if not rng:
		rng = RandomNumberGenerator.new()
	var l: TileMapLayer = layers[layer_name]
	for c: Vector2i in cells:
		if random:
			l.set_cell(c, source_id, tiles[rng.randi_range(0, tiles.size() - 1)])
		else:
			var t := src.get_tile_at_coords(region.position + Vector2i(posmod(c.x, region.size.x), posmod(c.y, region.size.y)))
			if t != Vector2i(-1, -1):
				l.set_cell(c, source_id, t)
	dirty = true

## [source_id, atlas_coords, alternative] of a solid [param color] tile: one white tile in
## an "MDS colors" source, tinted per color by alternative tiles (created on demand).
func color_tile(color: Color) -> Array:
	var sid := -1
	for i in tile_set.get_source_count():
		var id := tile_set.get_source_id(i)
		if tile_set.get_source(id).resource_name in [COLOR_SOURCE_NAME, LEGACY_COLOR_SOURCE_NAME]:
			sid = id
	var src: TileSetAtlasSource
	if sid < 0:
		src = TileSetAtlasSource.new()
		src.resource_name = COLOR_SOURCE_NAME
		var img := Image.create(tile_set.tile_size.x, tile_set.tile_size.y, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		src.texture = ImageTexture.create_from_image(img)
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
	dirty = true

# --- Generation ------------------------------------------------------------------------------

## Builds a starting cave from the room's shape on the map: solid walls along the room's
## outline (rough, cellular-automata edges), openings where its gates are, a floor, a few
## ledges, background foliage, then decorations. Rock outside the painted shape fills the
## notches of irregular rooms.
## [param background] is the fill for the background (default: random "foliage" tiles).
func generate_cave(world: MDSWorld, id: String, seed_value := 0, terrain_set := 0, terrain := 0, background: Dictionary = {}) -> void:
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
	paint_fill("Background", back, background if not background.is_empty() else {"type": "kind", "kind": "foliage"}, rng)
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
	packed.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	return packed

static func _editor_files() -> Object:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		return Engine.get_singleton(&"EditorInterface").get_resource_filesystem()
	return null

## Moves big images embedded in [param ts] (sheets added by older versions, or from files
## that were not imported yet) out to PNG files next to it and links them instead. Returns
## how many were moved; the tileset is saved when any were. Only works in the editor.
static func externalize_sheets(ts: TileSet) -> int:
	var base := ts.resource_path
	if not _editor_files() or base.is_empty() or "::" in base:
		return 0
	var moved := 0
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid) as TileSetAtlasSource
		if not src or not src.texture is ImageTexture or src.texture.get_width() * src.texture.get_height() < 512 * 512:
			continue
		if not src.texture.resource_path.is_empty() and not "::" in src.texture.resource_path:
			continue
		var img: Image = src.texture.get_image()
		if not img:
			continue
		var stem := "%s_%s" % [base.get_basename(), src.resource_name.validate_filename() if not src.resource_name.is_empty() else "sheet%d" % sid]
		var path := stem + ".png"
		var n := 2
		while FileAccess.file_exists(path):
			path = "%s_%d.png" % [stem, n]
			n += 1
		var tex := _file_texture(img, path)
		if tex is PortableCompressedTexture2D:
			continue
		src.texture = tex
		moved += 1
	if moved > 0:
		ResourceSaver.save(ts, base)
	return moved

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

## Tags tiles with an idp_kind ("grass", "foliage", "vine_top"...) so Auto-decorate,
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
		if tile_set.get_custom_data_layer_name(i) == "idp_kind" and src and src.has_tile(coords):
			return str(src.get_tile_data(coords, 0).get_custom_data_by_layer_id(i))
	return ""

func _kind_layer() -> int:
	for i in tile_set.get_custom_data_layers_count():
		if tile_set.get_custom_data_layer_name(i) == "idp_kind":
			return i
	tile_set.add_custom_data_layer()
	var index := tile_set.get_custom_data_layers_count() - 1
	tile_set.set_custom_data_layer_name(index, "idp_kind")
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
	if not tile_set_dirty:
		return OK
	var p := tile_set.resource_path
	if p.is_empty() or "::" in p:
		dirty = true
		return OK
	tile_set_dirty = false
	return ResourceSaver.save(tile_set, p)
