@tool
class_name MDSFreeformStyle
extends Resource
## Look of an [MDSFreeform] shape: a repeating fill texture, textured strips along its top
## edges (moss, grass...) and undersides (drips, roots), an outline, and clumps scattered
## along the edges from an [MDSStampSet]. Without textures the colors are used, so a style
## works with no art at all.
##
## Save styles as [code]*.freeform.tres[/code]: the Room view lists every such file in the
## project.

## What shapes of a style are for:
## - [code]TERRAIN[/code]: solid ground. It collides and forms the room's silhouette on the map.
## - [code]PLATFORM[/code]: a ledge to stand on. It collides (one-way with [member one_way])
##   and is reported as a platform, not as part of the room's silhouette.
## - [code]DECOR[/code]: drawn only. It never collides and never counts as terrain (deep
##   ground over the room's notches, scenery on the terrain layer).
enum Role { TERRAIN, PLATFORM, DECOR }
const ROLE_NAMES: PackedStringArray = ["Terrain", "Platform", "Decoration"]

@export var display_name := ""
@export_group("Fill")
@export var fill_texture: Texture2D
@export var fill_color := Color("#2a3442")
## World pixels per fill texture pixel (2 = texture drawn twice as big).
@export var fill_scale := 1.0
@export_group("Outline")
@export var outline_color := Color("#080b10")
@export var outline_width := 3.0
@export_group("Top edges")
## Strip along edges that face up (within top_angle of straight up). The texture's top
## row is the outside.
@export var top_texture: Texture2D
@export var top_color := Color("#58a83e")
@export var top_width := 0.0
## How far the strip's center sits inside the shape (px).
@export var top_inset := 6.0
@export_range(0, 89) var top_angle := 55.0
@export_group("Bottom edges")
## Strip along edges that face down. The texture's top row is the inside.
@export var bottom_texture: Texture2D
@export var bottom_color := Color("#0b0f15")
@export var bottom_width := 0.0
@export var bottom_inset := 4.0
@export_group("Clumps")
@export var stamp_set: MDSStampSet
## Stamp category scattered along top edges ("" = none).
@export var top_clumps := ""
## Stamp category hung under bottom edges ("" = none).
@export var bottom_clumps := ""
## Average distance between clumps (px).
@export var clump_spacing := 56.0
@export var clump_scale := Vector2(0.7, 1.1)
@export_group("Material")
## A material for the fill (a shader skin: lit stone, ice, lava...). The fill texture and
## color still reach it as TEXTURE and COLOR.
@export var fill_material: Material
## A material for a band along the edges: a mesh [member edge_inside] px into the shape and
## [member edge_outside] px out of it, with UV.x along the edge (px), UV.y across it (0 at
## the outline, 1 at the inner edge, negative outside) and COLOR.r/g telling which way it faces
## (see [MDSEdgeBand]). The addon's shaders/terrain_skin.gdshader is an example.
@export var edge_material: Material
@export var edge_inside := 34.0
@export var edge_outside := 30.0
## Edges lying on lines of this grid (x = k * grid.x, y = k * grid.y, in the room's
## coordinates) get no band: where rock meets the room's outer boundary and runs on into the
## next room. Zero: every edge has one.
@export var skip_edges_on_grid := Vector2.ZERO
@export_group("2.5D")
## Extruded by MDSDepth25D (solid terrain and platforms only).
@export var extrude := true
## Color of the extruded sides (alpha 0: the fill color, darkened).
@export var depth_side_color := Color(0, 0, 0, 0)
## Color of the receding top surfaces (alpha 0: the fill blended with the top color).
@export var depth_top_color := Color(0, 0, 0, 0)
@export_group("Collision")
## Terrain, platform or decoration (see [enum Role]).
@export var role: Role = Role.TERRAIN
## Physics layers the shape's body is on.
@export_flags_2d_physics var collision_layer := 1
## Physics layers the shape's body detects.
@export_flags_2d_physics var collision_mask := 1
## Collide only from above: bodies jump up through the shape and land on its top, like a
## ledge. Usually set with the Platform role.
@export var one_way := false
## How deep (px) a body may sink into a one-way shape and still be pushed up onto it.
@export var one_way_margin := 16.0
@export_group("Defaults")
## Collide by default (terrain) or not (backgrounds, foregrounds).
@export var solid := true
## Layer new shapes of this style go to: "terrain", "back" or "front".
@export var default_layer := "terrain"

func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return resource_path.get_file().get_basename().get_basename().capitalize() if not resource_path.is_empty() else "Style"

## The role, also honouring the [code]one_way_platform[/code] metadata older styles used for
## ledges.
func get_role() -> Role:
	if role == Role.TERRAIN and bool(get_meta(&"one_way_platform", false)):
		return Role.PLATFORM
	return role

func is_one_way() -> bool:
	return one_way or bool(get_meta(&"one_way_platform", false))

## "Mossy rock", "Garden ledge (platform, one-way)", "Deep ground (decoration)": the name with
## its role, for lists.
func get_list_name() -> String:
	var r := get_role()
	if r == Role.TERRAIN and not is_one_way():
		return get_display_name()
	var tags: PackedStringArray = [ROLE_NAMES[r].to_lower()]
	if is_one_way() and r != Role.DECOR:
		tags.append("one-way")
	return "%s (%s)" % [get_display_name(), ", ".join(tags)]

## Built-in color styles, available without any art.
static func builtins() -> Array[MDSFreeformStyle]:
	var out: Array[MDSFreeformStyle] = []
	var rock := MDSFreeformStyle.new()
	rock.display_name = "Plain rock (mossy)"
	rock.top_width = 10.0
	rock.bottom_width = 8.0
	out.append(rock)
	var back := MDSFreeformStyle.new()
	back.display_name = "Plain background"
	back.fill_color = Color("#13303a")
	back.outline_color = Color("#0b1c22")
	back.outline_width = 2.0
	back.solid = false
	back.default_layer = "back"
	out.append(back)
	var front := MDSFreeformStyle.new()
	front.display_name = "Plain foreground silhouette"
	front.fill_color = Color("#04080b")
	front.outline_color = Color("#04080b")
	front.outline_width = 0.0
	front.solid = false
	front.default_layer = "front"
	out.append(front)
	# A shader skin (shaders/terrain_skin.gdshader): lit stone with grass on top.
	var skin := MDSFreeformStyle.new()
	skin.display_name = "Shader stone (example)"
	skin.fill_color = Color("#8a8070")
	skin.outline_width = 0.0
	skin.fill_material = load(SKIN_FILL) as Material
	skin.edge_material = load(SKIN_EDGE) as Material
	out.append(skin)
	return out

const SKIN_FILL := "res://addons/MetroidvaniaDeveloperSystem/shaders/terrain_skin_fill.tres"
const SKIN_EDGE := "res://addons/MetroidvaniaDeveloperSystem/shaders/terrain_skin_edge.tres"

## How many [method builtins] there are.
const BUILTIN_COUNT := 4

## Every *.freeform.tres in the project (skipping .godot and hidden folders).
static func find_in_project(root := "res://", depth := 7) -> Array[MDSFreeformStyle]:
	var out: Array[MDSFreeformStyle] = []
	for p in _find_files(root, ".freeform.tres", depth):
		var s := load(p) as MDSFreeformStyle
		if s:
			out.append(s)
	return out

static func _find_files(dir: String, suffix: String, depth: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if depth < 0:
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(suffix):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_find_files(dir.path_join(d), suffix, depth - 1))
	return out
