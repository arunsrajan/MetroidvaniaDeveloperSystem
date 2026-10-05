@tool
class_name IDPDepthStyle
extends Resource
## How [IDPDepth25D] fakes depth: how far walls reach back, how faces are lit, how dark the
## view gets away from the player, shadows and floor paving. Save as a .tres to share it, or
## leave the node's style empty for these defaults.

@export_group("Extrusion")
## How far back walls reach, as a fraction of the way to the vanishing point (the middle of
## the view), sideways...
@export_range(0.0, 0.5) var depth_x := 0.10
## ...and up and down: deeper, so floors read as planes without side walls turning into
## tunnels.
@export_range(0.0, 0.5) var depth_y := 0.20
## Draw order of the faces and shadows: behind the terrain and the stamps on it (plants,
## ivy: the Room view's StampsBack group is at z -6), in front of background shapes
## (FreeformBack, z -8), which stand farther back than the floor planes.
@export var face_z := -7
@export_group("Lighting")
## Where the key light comes from (faces turned toward it are lit, the others shaded).
@export var light_dir := Vector2(0, -1)
## Faces this far (px) from the player are at their darkest.
@export var light_reach := 900.0
## The view darkens from this distance (px) around the player...
@export var light_inner := 260.0
## ...to [member light_dark] at [member light_reach].
@export var light_dark := Color(0.66, 0.66, 0.74)
## How much the view darkens toward its edges (0 = no vignette).
@export_range(0.0, 1.0) var vignette := 0.3
## Draw order of the light falloff and vignette (multiplied over everything below it).
@export var light_z := 25
@export_group("Shadows")
## Opacity of the soft shadow under a body standing on the ground (they spread and fade as it
## rises).
@export_range(0.0, 1.0) var shadow_strength := 0.7
## Physics layers the shadows fall on.
@export_flags_2d_physics var shadow_mask := 1
@export_group("Floors")
## Distance (px) between the paving joints of floor tops.
@export var paving := 44.0
## Courses of paving across a floor's depth.
@export_range(0, 8) var floor_courses := 3
## Strength of the joint lines (0 = plain faces).
@export_range(0.0, 1.0) var joints := 0.55
@export_group("Colors")
## Sides and tops of terrain that has no freeform style (tile layers, static bodies).
@export var plain_side := Color(0.32, 0.31, 0.3)
@export var plain_top := Color(0.42, 0.42, 0.36)
@export var plain_joint := Color(0.08, 0.08, 0.07)
