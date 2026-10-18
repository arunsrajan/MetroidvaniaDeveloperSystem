@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_movement_config.svg")
class_name MDSMovementConfig
extends Resource
## How the player moves ([MDSPlayer]): one feel profile, in px and seconds. MDS rooms are
## 1152 x 648 px by default. The Inspector previews the jump arc these values give (height
## and distance), next to that room size.

@export_group("Run")
@export var max_run_speed := 260.0
## px/s² while running, and while stopping.
@export var ground_accel := 2000.0
@export var ground_decel := 2400.0
@export var air_accel := 1400.0
@export var air_decel := 1000.0
@export_group("Gravity")
@export var gravity := 1500.0
## Falling (going down) is this much heavier, for a snappy arc.
@export var fall_gravity_multiplier := 1.6
@export var max_fall_speed := 700.0
## Near the top of a jump (slower than this, px/s, jump held) gravity is lighter.
@export var apex_threshold := 40.0
@export var apex_gravity_multiplier := 0.5
@export_group("Jump")
@export var jump_velocity := 520.0
## Velocity kept when jump is released early (a short hop).
@export var jump_cut_multiplier := 0.45
## A jump still works this long after running off a ledge.
@export var coyote_time := 0.10
## A jump pressed this long before landing still happens on landing.
@export var jump_buffer_time := 0.12
## Extra jumps in the air, with the double_jump ability.
@export var max_air_jumps := 1
## Nudges the player past a ceiling corner it would bump its head on, up to this many px.
@export var corner_correction_px := 6.0
@export_group("Walls")
@export var wall_slide_speed := 100.0
## Away from the wall (x) and up (y).
@export var wall_jump_velocity := Vector2(300, -500)
## Seconds after a wall jump before steering works again.
@export var wall_jump_lock := 0.15
@export_group("Dash and slide")
@export var dash_speed := 600.0
@export var dash_time := 0.16
@export var dash_cooldown := 0.35
## Dashes in the air before landing again, with air_dash.
@export var air_dashes := 1
@export var slide_speed := 400.0
@export var slide_time := 0.35
@export_group("Climb, swim, glide")
@export var climb_speed := 140.0
@export var swim_speed := 180.0
## Gravity in water: sinking without the swim ability, drifting with it.
@export var swim_gravity := 300.0
@export var glide_fall_speed := 80.0
@export_group("Grapple and pound")
@export var grapple_range := 260.0
@export var grapple_pull_speed := 700.0
@export var ground_pound_speed := 900.0
@export_group("Floors")
## Steepest floor walked on (degrees).
@export_range(0.0, 89.0) var max_floor_angle := 45.0
@export var floor_snap_length := 8.0

## How high a full jump goes (px): rising at [member jump_velocity] under [member gravity], the
## lighter gravity near the apex taken into account.
func jump_height() -> float:
	var v := jump_velocity
	var a := clampf(apex_threshold, 0.0, v)
	# Up to the apex band at full gravity, through it at the apex gravity.
	return (v * v - a * a) / (2.0 * gravity) + (a * a) / (2.0 * gravity * maxf(apex_gravity_multiplier, 0.01))

## Seconds from take-off to the apex of a full jump.
func rise_time() -> float:
	var a := clampf(apex_threshold, 0.0, jump_velocity)
	return (jump_velocity - a) / gravity + a / (gravity * maxf(apex_gravity_multiplier, 0.01))

## Seconds from the apex back down to the take-off height.
func fall_time() -> float:
	return sqrt(2.0 * jump_height() / (gravity * fall_gravity_multiplier))

## How far a full jump at full speed goes (px), landing at the take-off height.
func jump_distance() -> float:
	return max_run_speed * (rise_time() + fall_time())

## Points of a full jump at full speed from (0, 0), every [param step] seconds (up is negative y).
func jump_arc(step := 1.0 / 30.0) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	var p := Vector2.ZERO
	var v := Vector2(max_run_speed, -jump_velocity)
	for i in 400:
		var g := gravity
		if v.y > 0.0:
			g *= fall_gravity_multiplier
		elif absf(v.y) < apex_threshold:
			g *= apex_gravity_multiplier
		v.y = minf(v.y + g * step, max_fall_speed)
		p += v * step
		pts.append(p)
		if p.y >= 0.0 and v.y > 0.0:
			break
	return pts
