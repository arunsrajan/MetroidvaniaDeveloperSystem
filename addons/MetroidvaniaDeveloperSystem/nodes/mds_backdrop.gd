@tool
class_name MDSBackdrop
extends Resource
## The distance behind the rooms: a sky gradient and planes of art at increasing depths
## ([MDSBackdropLayer]), drawn by an [MDSBackdropView]. Made only of resources, so asset packs
## and the world file (per area or per room) can supply them. Save as
## [code]*.backdrop.tres[/code].

@export var display_name := ""
## The sky over the whole view, top (offset 0) to bottom (offset 1).
@export var sky: Gradient
## Planes, farthest first.
@export var layers: Array[MDSBackdropLayer] = []
## The distance is drawn off screen at this share of the screen's resolution and scaled up:
## it is soft anyway, and many translucent layers cost much less at half size.
@export_range(0.25, 1.0) var resolution := 0.5
## Mix the room's terrain colors (its freeform styles) into the haze, so the distance takes
## the room's palette.
@export var sample_palette := false
@export_range(0.0, 1.0) var palette_mix := 0.3

func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return resource_path.get_file().get_basename().get_basename().capitalize() if not resource_path.is_empty() else "Backdrop"

## The sky color at [param y] (0 = top of the view, 1 = bottom).
func sky_color(y: float) -> Color:
	return sky.sample(clampf(y, 0.0, 1.0)) if sky else Color(0.12, 0.14, 0.12).lerp(Color(0.04, 0.05, 0.04), y)
