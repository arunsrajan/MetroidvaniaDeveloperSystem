@tool
class_name MDSRoomLayers
extends RefCounted
## The layers the Room view shows and hides (its Layers checkboxes), farthest first: the
## parallax background, the background effects, the four tile layers with the stamps between
## them, the foreground effects, the parallax foreground, the scene's other nodes and the guides
## drawn over the room. Each id says which nodes it covers ([method of_item]).
##
## Hiding a layer only changes what the view draws: nothing hidden is saved hidden (see
## [member MDSRoomPainter.view_hidden]).

## The layer ids, farthest first.
const IDS: PackedStringArray = [
	"parallax_back", "effects_back", "background", "stamps_back", "terrain", "decor", "stamps",
	"foreground", "stamps_fore", "effects_fore", "parallax_fore", "objects", "guides",
]
## The name of each layer in the Layers list.
# l10n: text
const LABELS := {
	"parallax_back": "Parallax background",
	"effects_back": "Background effects",
	"background": "Background",
	"stamps_back": "Stamps (back)",
	"terrain": "Terrain",
	"decor": "Decor",
	"stamps": "Stamps",
	"foreground": "Foreground",
	"stamps_fore": "Stamps (foreground)",
	"effects_fore": "Foreground effects",
	"parallax_fore": "Parallax foreground",
	"objects": "Objects",
	"guides": "Guides",
}
## What each layer holds (the checkbox's tooltip).
# l10n: text
const TIPS := {
	"parallax_back": "The room's parallax and animated backgrounds, behind everything.",
	"effects_back": "Effects behind the tiles: placed ones set to Background (or with a negative z) and the weather's.",
	"background": "Background tiles, back freeform shapes, and pictures and free tiles of the Background layer.",
	"stamps_back": "Stamps placed behind the terrain.",
	"terrain": "Terrain tiles, freeform shapes, and pictures and free tiles of the Terrain layer.",
	"decor": "Decor tiles, and pictures and free tiles of the Decor layer.",
	"stamps": "Stamps placed in front of the terrain.",
	"foreground": "Foreground tiles, front freeform shapes, and pictures and free tiles of the Foreground layer.",
	"stamps_fore": "Stamps placed in front of everything.",
	"effects_fore": "Effects in front of the tiles: placed ones set to Foreground (or with a z of 0 or more) and the weather's.",
	"parallax_fore": "The parallax background's foreground layers, passing in front of the room.",
	"objects": "The scene's other nodes: gameplay objects, enemies, gates, props.",
	"guides": "The tile grid, the room's outline, the gates' boxes and the reachability check.",
}
## The tile layer of each tile layer id.
const TILE_LAYERS := {"background": "Background", "terrain": "Terrain", "decor": "Decor", "foreground": "Foreground"}
## The layer of the item groups drawn whole (see [constant MDSRoomPainter.ITEM_GROUPS]).
const GROUPS := {
	"FreeformBack": "background", "StampsBack": "stamps_back", "Freeform": "terrain",
	"StampsFront": "stamps", "FreeformFront": "foreground", "StampsForeground": "stamps_fore",
}
## The stamp group of each stamps layer.
const STAMP_GROUPS := {"stamps_back": "StampsBack", "stamps": "StampsFront", "stamps_fore": "StampsForeground"}

## The layer id of the tile layer [param layer_name] ("Terrain"...).
static func of_tile_layer(layer_name: String) -> String:
	for id in TILE_LAYERS:
		if TILE_LAYERS[id] == layer_name:
			return id
	return "terrain"

## The layer of an item of the room (a child of one of the painter's item groups) or of a node
## of the scene.
static func of_item(node: Node) -> String:
	var parent := node.get_parent()
	var group := String(parent.name) if parent else ""
	if GROUPS.has(group):
		return GROUPS[group]
	if node.is_in_group(&"mds_gameplay_placed"):
		return "objects"
	if node is MDSEnvironmentEffect:
		return of_effect(node)
	if MDSRoomPainter.is_tile_piece(node):
		return of_tile_layer(str(node.get_meta(MDSRoomPainter.PIECE_META, "Terrain")))
	if node is MDSDrawing:
		return of_tile_layer(str(node.get_meta(MDSRoomPainter.DRAWING_LAYER_META, "Terrain")))
	return "objects"

## The layer of an item's data ([method MDSRoomPainter._snapshot]'s) in group [param group].
static func of_data(group: String, d: Dictionary) -> String:
	if GROUPS.has(group):
		return GROUPS[group]
	match group:
		MDSRoomPainter.EFFECTS_GROUP:
			return "effects_back" if int(d.get("z_index", 0)) < 0 else "effects_fore"
		MDSRoomPainter.TILES_GROUP:
			return of_tile_layer(str((d.get("meta", {}) as Dictionary).get(MDSRoomPainter.PIECE_META, "Terrain")))
		MDSRoomPainter.PICTURES_GROUP:
			return of_tile_layer(str((d.get("meta", {}) as Dictionary).get(MDSRoomPainter.DRAWING_LAYER_META, "Terrain")))
	return "objects"

## The layers [param visible] hides (id -> true): what Save leaves as the scene has it. The
## previews and guides are never saved, so they are left out.
static func unsaved(visible: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in visible:
		if not bool(visible[id]) and not id in ["parallax_back", "parallax_fore", "guides"]:
			out[id] = true
	return out

## "effects_back" or "effects_fore": whether [param fx] draws behind the tiles.
static func of_effect(fx: MDSEnvironmentEffect) -> String:
	return "effects_back" if fx.is_background() else "effects_fore"

## The ids of the tile layers.
static func is_tile_layer(id: String) -> bool:
	return TILE_LAYERS.has(id)

static func is_stamps(id: String) -> bool:
	return STAMP_GROUPS.has(id)

static func is_effects(id: String) -> bool:
	return id == "effects_back" or id == "effects_fore"

## The layers of [param visible] (id -> bool, a missing id is shown) with only [param id]
## shown.
static func solo(id: String) -> Dictionary:
	var out: Dictionary = {}
	for i in IDS:
		out[i] = i == id
	return out

## Every layer shown ([param on]) or hidden.
static func all(on := true) -> Dictionary:
	var out: Dictionary = {}
	for i in IDS:
		out[i] = on
	return out
