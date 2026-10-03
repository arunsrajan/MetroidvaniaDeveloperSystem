@tool
class_name IDPFreeformStyle
extends Resource
## Look of an [IDPFreeform] shape: a repeating fill texture, textured strips along its top
## edges (moss, grass...) and undersides (drips, roots), an outline, and clumps scattered
## along the edges from an [IDPStampSet]. Without textures the colors are used, so a style
## works with no art at all.
##
## Save styles as [code]*.freeform.tres[/code]: the Room view lists every such file in the
## project.

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
@export var stamp_set: IDPStampSet
## Stamp category scattered along top edges ("" = none).
@export var top_clumps := ""
## Stamp category hung under bottom edges ("" = none).
@export var bottom_clumps := ""
## Average distance between clumps (px).
@export var clump_spacing := 56.0
@export var clump_scale := Vector2(0.7, 1.1)
@export_group("Defaults")
## Collide by default (terrain) or not (backgrounds, foregrounds).
@export var solid := true
## Layer new shapes of this style go to: "terrain", "back" or "front".
@export var default_layer := "terrain"

func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return resource_path.get_file().get_basename().get_basename().capitalize() if not resource_path.is_empty() else "Style"

## Built-in color styles, available without any art.
static func builtins() -> Array[IDPFreeformStyle]:
	var out: Array[IDPFreeformStyle] = []
	var rock := IDPFreeformStyle.new()
	rock.display_name = "Plain rock (mossy)"
	rock.top_width = 10.0
	rock.bottom_width = 8.0
	out.append(rock)
	var back := IDPFreeformStyle.new()
	back.display_name = "Plain background"
	back.fill_color = Color("#13303a")
	back.outline_color = Color("#0b1c22")
	back.outline_width = 2.0
	back.solid = false
	back.default_layer = "back"
	out.append(back)
	var front := IDPFreeformStyle.new()
	front.display_name = "Plain foreground silhouette"
	front.fill_color = Color("#04080b")
	front.outline_color = Color("#04080b")
	front.outline_width = 0.0
	front.solid = false
	front.default_layer = "front"
	out.append(front)
	return out

## Every *.freeform.tres in the project (skipping .godot and hidden folders).
static func find_in_project(root := "res://", depth := 7) -> Array[IDPFreeformStyle]:
	var out: Array[IDPFreeformStyle] = []
	for p in _find_files(root, ".freeform.tres", depth):
		var s := load(p) as IDPFreeformStyle
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
