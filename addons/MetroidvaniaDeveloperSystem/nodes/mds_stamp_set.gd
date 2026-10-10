@tool
class_name MDSStampSet
extends Resource
## Large sprites placed freely (not on the tile grid): moss clumps, leaf clusters, hanging
## moss, background bubbles, foreground silhouettes... One texture with regions, each with
## a category and an anchor (the point that sits on the spot you click, e.g. the bottom of
## a clump that grows up from an edge).
##
## Save sets as [code]*.stamps.tres[/code]: the Room view lists every such file.

@export var display_name := ""
@export var texture: Texture2D
@export var regions: Array[Rect2] = []
@export var categories: PackedStringArray = []
## Per region, 0..1 inside the region (0.5, 1 = bottom center).
@export var anchors: PackedVector2Array = []

func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return resource_path.get_file().get_basename().get_basename().capitalize() if not resource_path.is_empty() else "Stamps"

func get_categories() -> PackedStringArray:
	var out: PackedStringArray = []
	for c in categories:
		if not c in out:
			out.append(c)
	return out

## Region indices of a category ("" = all).
func indices(category: String) -> Array[int]:
	var out: Array[int] = []
	for i in regions.size():
		if category.is_empty() or (i < categories.size() and categories[i] == category):
			out.append(i)
	return out

func anchor(i: int) -> Vector2:
	return anchors[i] if i < anchors.size() else Vector2(0.5, 1.0)

## A sprite for region [param i], positioned by its anchor.
func make_sprite(i: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.region_enabled = true
	s.region_rect = regions[i]
	s.centered = false
	s.offset = -anchor(i) * regions[i].size
	s.set_meta(&"mds_stamp", i)
	return s

static func find_in_project(root := "res://", depth := 7) -> Array[MDSStampSet]:
	var out: Array[MDSStampSet] = []
	for p in MDSFreeformStyle._find_files(root, ".stamps.tres", depth):
		var s := load(p) as MDSStampSet
		if s:
			out.append(s)
	return out
