@tool
class_name MDSBackdropLayer
extends Resource
## One plane of an [MDSBackdrop]: art at a depth, scrolling at a fraction of the camera's
## speed, drawn smaller, hazier and greyer the farther back it is.

enum Source { TEXTURE, STAMPS, SCENE }

@export var source: Source = Source.TEXTURE
## Source TEXTURE: an image repeated along the plane (every [member spacing] px).
@export var texture: Texture2D
## Source STAMPS: stamps of a category scattered along the plane.
@export var stamp_set: MDSStampSet
@export var stamp_category := ""
## Stamps per 1000 px of plane.
@export var stamp_density := 4.0
## Random size of each stamp (min, max).
@export var stamp_scale := Vector2(0.8, 1.2)
## Source SCENE: a scene placed on the plane (repeated with [member repeat]).
@export var scene: PackedScene
@export_group("Depth")
## How the plane moves: 0 stays on the screen (infinitely far, like the sky), 1 moves with
## the room, above 1 runs faster than the camera (in front of the room).
@export_range(0.0, 2.0) var depth := 0.3
## Size of the art (farther planes are usually drawn smaller).
@export var scale := 1.0
## Where the art sits on the plane, from the room's middle at rest (plane px). Positive y:
## lower.
@export var offset := Vector2.ZERO
## Repeat the art sideways so the view never runs off its edge.
@export var repeat := true
## Distance between repeats (0: the texture's width).
@export var spacing := 0.0
## Random vertical shift of each stamp (px).
@export var jitter := 0.0
## Drawn in front of the room (at full resolution, in its world) instead of behind it.
@export var foreground := false
@export var seed_value := 0
@export_group("Look")
## Color the plane is mixed toward (the air between it and the viewer).
@export var haze_color := Color(0.55, 0.6, 0.55)
@export_range(0.0, 1.0) var haze := 0.3
## Multiplies the art's colors after [member desaturate].
@export var tint := Color.WHITE
## Greys the art out (0 = its own colors), so borrowed art takes the scene's colors.
@export_range(0.0, 1.0) var desaturate := 0.0
@export_range(0.0, 1.0) var alpha := 1.0
## Sway in a slow draught (hanging things sway more the farther they hang).
@export_range(0.0, 1.0) var sway := 0.0
