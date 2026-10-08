@tool
class_name MDSParallaxLayer
extends Resource
## One layer of an [MDSParallaxBackground]: a sky, a silhouette drawn by a shader (mountains,
## hills, a forest, a city, ruins, cave rock, dunes), clouds, a fog band, stars, or your own
## picture repeated sideways. Layers further back move less as the camera moves
## ([member scroll_scale]).

enum Kind { SKY, MOUNTAINS, HILLS, FOREST, CITY, RUINS, CAVE, DUNES, CLOUDS, FOG, STARS, PICTURE }

@export var kind: Kind = Kind.MOUNTAINS:
	set(v):
		kind = v
		emit_changed()
## The silhouette's color (the stars', the clouds' shadow; a picture is multiplied by it).
@export var color := Color(0.16, 0.14, 0.25):
	set(v):
		color = v
		emit_changed()
## Snow on peaks, lit windows, the crest's rim, the clouds' light; the sky's top.
@export var color_top := Color(0.9, 0.9, 1.0):
	set(v):
		color_top = v
		emit_changed()
## The haze at the silhouette's base; the sky's bottom.
@export var color_bottom := Color(0.5, 0.4, 0.5):
	set(v):
		color_bottom = v
		emit_changed()
## How much the layer moves with the room: 0 stays on the screen (infinitely far), 1 moves with
## the room. Usually smaller vertically.
@export var scroll_scale := Vector2(0.2, 0.1):
	set(v):
		scroll_scale = v
		emit_changed()
## Where its features stand, as a share of the background's height (0 top, 1 bottom).
@export_range(-1.0, 2.0) var horizon := 0.75:
	set(v):
		horizon = v
		emit_changed()
## How tall its features rise (px).
@export_range(0.0, 4000.0) var height := 220.0:
	set(v):
		height = v
		emit_changed()
## How wide its features are (px).
@export_range(10.0, 8000.0) var feature_size := 420.0:
	set(v):
		feature_size = v
		emit_changed()
## Jagged peaks, lit windows, star count...
@export_range(0.0, 1.0) var roughness := 0.5:
	set(v):
		roughness = v
		emit_changed()
## The silhouette runs on down to the bottom of the view.
@export var fill_below := true:
	set(v):
		fill_below = v
		emit_changed()
## The air between the layer and the viewer: toward [member color_bottom] near the base.
@export_range(0.0, 1.0) var haze := 0.3:
	set(v):
		haze = v
		emit_changed()
@export_range(0.0, 1.0) var alpha := 1.0:
	set(v):
		alpha = v
		emit_changed()
## Drift (px/s): clouds sailing by.
@export_range(-400.0, 400.0) var autoscroll := 0.0:
	set(v):
		autoscroll = v
		emit_changed()
@export var seed_value := 0:
	set(v):
		seed_value = v
		emit_changed()
@export_group("Picture")
## Kind PICTURE: your art, its bottom edge on the horizon, repeated sideways.
@export var picture: Texture2D:
	set(v):
		picture = v
		emit_changed()
@export_range(0.05, 20.0) var picture_scale := 1.0:
	set(v):
		picture_scale = v
		emit_changed()
@export var repeat_x := true:
	set(v):
		repeat_x = v
		emit_changed()

## A layer of [param p_kind] with [param settings] (property name -> value).
static func make(p_kind: Kind, settings: Dictionary = {}) -> MDSParallaxLayer:
	var l := MDSParallaxLayer.new()
	l.kind = p_kind
	for k in settings:
		l.set(k, settings[k])
	return l
