@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSCameraDirector
extends Node
## Borrows an [MDSRoomCamera]'s camera for a moment when a fight needs framing, then gives it
## back exactly where the room's own camera would be. Add it as a child of the MDSRoomCamera,
## or call [method MDSRoomCamera.get_director].
##
## - [method focus_on]: hold on a node (a death, a finishing blow), optionally in slow motion.
## - [method frame_threat]: pull out until the player and a threat off screen are both in view.
## - [method reveal]: pull out to show an area (a boss's whole arena).
## - [method punch_in]: a short push in.
## - [method frame_world]: show an area beyond the room (the whole level, for
##   [MDSLevelOverview]).
##
## A focus beats a threat or a reveal, which beat a punch. Every view stays inside the room: a
## pull-out never shows anything outside the room's shape (the notches of an L or T room), and
## views at the room's zoom or closer stay inside a camera zone. Zoom and position glide there
## and back (cut, with the room camera's [member MDSRoomCamera.transition_style] CUT). It works
## with both of the room camera's backends: with Camera2D it moves the camera itself, with Phantom
## Camera it takes over through a PhantomCamera2D of its own with the highest priority.
##
## With [member automatic] on it watches [member watch_group] and frames an enemy that is off
## screen and after the player.

enum Kind { NONE, PUNCH, THREAT, FOCUS }

## Emitted when it takes the camera (or a stronger request takes over).
signal started(kind: int)
## Emitted when the room's camera has the camera back.
signal released

## The camera it borrows. Empty: its parent.
@export var room_camera: MDSRoomCamera
## The farthest a pull-out goes, as a share of the room camera's zoom (0.6: the view grows to
## at most 1/0.6 of its size). Past it the player is too small to read.
@export_range(0.1, 1.0) var min_zoom := 0.6
## How quickly zoom and position close in on their target (per second, real time).
@export var glide := 5.0
## Space kept around the player and around a threat when framing both.
@export var player_margin := Vector2(140, 170)
@export var threat_margin := Vector2(110, 130)
## Nothing is framed for less than this (seconds), so the view doesn't flicker.
@export var min_hold := 1.0
## The camera is handed back after this long gliding back, even if the glide never arrives.
@export var max_release_time := 1.5
@export_group("Automatic")
## Watch [member watch_group] and frame an enemy off screen that is after the player.
@export var automatic := false
@export var watch_group: StringName = &"enemy"
## Enemies farther than this from the player are ignored.
@export var engage_range := 1500.0
## Seconds between looks.
@export var watch_interval := 0.25
## Closing in by this much (px) between two looks counts as chasing.
@export var approach_step := 18.0
## An enemy whose [code]state[/code] or [code]current_state[/code] enum is named with one of
## these is minding its own business; any other state (chase, attack...) is after the player.
@export var quiet_states: PackedStringArray = ["IDLE", "PATROL", "PASSIVE", "INTRO", "INACTIVE", "DEAD", "WANDER", "REST", "SLEEP"]

## A threat counts as on screen this far (px) inside the view's edge.
const ON_SCREEN_INSET := 48.0

var _kind := Kind.NONE
var _releasing := false
var _until_ms := 0
var _release_ms := 0
var _subject: Node2D
var _zoom := 1.0 ## the zoom an override heads for (relative to nothing: a Camera2D zoom)
var _reveal := Rect2()
var _centre := Vector2.ZERO ## where the borrowed view looks now
var _view_zoom := 1.0 ## the borrowed view's zoom now
var _time_scale_set := false
var _last_ms := 0
var _next_watch_ms := 0
var _last_distance: Dictionary = {}
var _pcam: Node2D ## Phantom Camera: the director's own PhantomCamera2D
var _smoothing := false
var _world := Rect2() ## frame_world: the area shown, beyond the room
var _ease_ms := 0 ## frame_world: a timed move, its length, start and where it started
var _ease_start_ms := 0
var _ease_from_zoom := 1.0
var _ease_from_centre := Vector2.ZERO
var _free_view := false ## the view isn't kept inside the room (a world frame, until handed back)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not room_camera and get_parent() is MDSRoomCamera:
		room_camera = get_parent()
	if room_camera and not is_instance_valid(room_camera.director):
		room_camera.director = self
	_last_ms = Time.get_ticks_msec()

func is_overriding() -> bool:
	return _kind != Kind.NONE

func current_kind() -> Kind:
	return _kind

## The view it shows now: {centre, zoom} (while overriding).
func current_view() -> Dictionary:
	return {"centre": _centre, "zoom": _view_zoom}

# --- Requests ---------------------------------------------------------------------------------

## Pulls out until [param threat] and the player are both in view, for at least
## [param seconds]. Ignored when the threat is on screen already, when the room has no space
## to pull out into, or during a focus.
func frame_threat(threat: Node2D, seconds := 1.6) -> void:
	if not _usable() or not is_instance_valid(threat) or _kind == Kind.FOCUS:
		return
	var player := _player()
	if not player:
		return
	if _kind == Kind.THREAT and _subject == threat and not _releasing:
		_until_ms = maxi(_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))
		return
	if on_screen(threat.global_position):
		return
	var plan := plan_threat_view(player.global_position, threat.global_position)
	if plan.is_empty():
		return
	_start(Kind.THREAT, threat, plan.zoom, maxf(seconds, min_hold))

## Pulls out to show all of [param area] (world rect), for at least [param seconds], as far as
## the room and [member min_zoom] allow. Ignored during a focus.
func reveal(area: Rect2, seconds := 1.6) -> void:
	if not _usable() or _kind == Kind.FOCUS or not area.has_area():
		return
	var plan := plan_reveal(area)
	if plan.is_empty():
		return
	_start(Kind.THREAT, null, plan.zoom, maxf(seconds, min_hold))
	_reveal = area

## A short push in, [param amount] times closer than the room's camera, centred between the
## player and [param around] (or on the player). Only when nothing stronger has the camera.
func punch_in(amount := 1.15, seconds := 0.55, around: Node2D = null) -> void:
	if not _usable() or _kind == Kind.FOCUS or _kind == Kind.THREAT:
		return
	_start(Kind.PUNCH, around, room_camera.rest_zoom() * amount, seconds)

## Holds on [param node] at [param zoom] times the room camera's zoom for [param seconds] of
## real time; with [param time_scale] below 1 the game runs slowed meanwhile. Beats everything.
func focus_on(node: Node2D, zoom := 1.5, seconds := 1.0, time_scale := 1.0) -> void:
	if not _usable() or not is_instance_valid(node):
		return
	_start(Kind.FOCUS, node, room_camera.rest_zoom() * zoom, seconds)
	if time_scale < 1.0:
		Engine.time_scale = time_scale
		_time_scale_set = true

## Shows all of [param area] (world rect, beyond the room: the rooms around it are on show) at
## the zoom that fits it, for [param seconds] of real time (INF: until [method release]). The
## move takes [param ease_seconds], easing in and out (0: a glide). Beats everything; the room's
## limits are set aside while it lasts.
func frame_world(area: Rect2, seconds := INF, ease_seconds := 2.4, fit := 0.94) -> void:
	if not _usable() or not area.has_area():
		return
	var vp := _viewport_size()
	var z := minf(vp.x / area.size.x, vp.y / area.size.y) * fit
	_start(Kind.FOCUS, null, z, seconds if is_finite(seconds) else 1e6, false)
	_world = area
	_free_view = true
	_ease_ms = 0 if room_camera.is_cut() else int(ease_seconds * 1000.0)
	_ease_start_ms = Time.get_ticks_msec()
	_ease_from_zoom = _view_zoom
	_ease_from_centre = _centre
	if room_camera.is_cut():
		_step(1.0)

## Lets go now, gliding back to the room's camera.
func release() -> void:
	if _kind != Kind.NONE:
		_until_ms = 0

## Gives the camera back at once, with no glide (a room change does this).
func cancel() -> void:
	if _kind != Kind.NONE:
		_finish()

# --- Planning ---------------------------------------------------------------------------------

## The view showing both the player and a threat: {zoom, centre}, or {} when the room can't
## show them better than the room's camera does.
func plan_threat_view(player_pos: Vector2, threat_pos: Vector2) -> Dictionary:
	var need := Rect2(player_pos - player_margin, player_margin * 2.0).merge(Rect2(threat_pos - threat_margin, threat_margin * 2.0))
	return _plan(need, player_pos)

## The view showing [param area]: {zoom, centre}, or {} when the view shows it already.
func plan_reveal(area: Rect2) -> Dictionary:
	var player := _player()
	return _plan(area, player.global_position if player else area.get_center())

func _plan(need: Rect2, anchor: Vector2) -> Dictionary:
	var rest := room_camera.rest_zoom()
	var vp := _viewport_size()
	var z := clampf(minf(vp.x / need.size.x, vp.y / need.size.y), rest * min_zoom, rest)
	if z >= rest - 0.02 * rest:
		return {}
	var legal := legal_view(need.get_center(), z, anchor)
	if legal.is_empty() or float(legal.zoom) >= rest - 0.02 * rest:
		return {}
	return legal

## [param centre] and [param zoom] made legal: the view kept inside the room's shape (or, at
## the room camera's zoom and closer, inside a camera zone) with [param anchor] (the player) in
## it. A pull-out that can't be made legal is brought back in step by step, recentring on the
## anchor, until it can. Returns {zoom, centre}, or {} when even the room camera's zoom can't.
func legal_view(centre: Vector2, zoom: float, anchor: Vector2) -> Dictionary:
	var rest := room_camera.rest_zoom()
	var z := zoom
	var top := maxf(rest, zoom)
	while z <= top + 0.001:
		var c := legal_centre(centre, z, anchor)
		if c.is_finite():
			return {"zoom": z, "centre": c}
		centre = centre.lerp(anchor, 0.35)
		z += 0.04 * rest
	return {}

## The legal view centre nearest [param centre] at zoom [param z] that keeps [param anchor]
## (when given) inside the view, or Vector2.INF when no view at that zoom does.
func legal_centre(centre: Vector2, z: float, anchor := Vector2.INF) -> Vector2:
	var half := _viewport_size() / 2.0 / z
	# Where the centre may be for the anchor to stay in view: a margin inside the edges, or
	# just inside where a wall is closer than the margin.
	var keep := Rect2(-1e9, -1e9, 2e9, 2e9)
	var loose := keep
	if anchor.is_finite():
		var m := Vector2(minf(player_margin.x, half.x * 0.8), minf(player_margin.y, half.y * 0.8))
		keep = Rect2(anchor - half + m, (half - m) * 2.0)
		loose = Rect2(anchor - half, half * 2.0)
	var areas := room_camera.legal_areas()
	if areas.is_empty():
		return centre.clamp(keep.position, keep.end)
	var best := Vector2.INF
	var best_d := INF
	# Inside one camera zone: always legal for the room's camera.
	for a in areas:
		var r := _centre_range(a, half, keep)
		if r.is_empty():
			r = _centre_range(a, half, loose)
		if r.is_empty():
			continue
		var c := centre.clamp(r[0], r[1])
		var d := c.distance_squared_to(centre)
		if d < best_d:
			best_d = d
			best = c
	# Across zones (a pull-out): inside the room's bounds and covered by its shape.
	var shape := room_camera.shape_rects()
	if not shape.is_empty():
		var bounds := shape[0]
		for s in shape:
			bounds = bounds.merge(s)
		var r := _centre_range(bounds, half, keep)
		if r.is_empty():
			r = _centre_range(bounds, half, loose)
		if not r.is_empty():
			var c := centre.clamp(r[0], r[1])
			if c.distance_squared_to(centre) < best_d and covered(Rect2(c - half, half * 2.0), shape):
				best = c
	return best

## The centres of views of half size [param half] that fit in [param area] with their centre in
## [param keep], as [min, max] (equal on an axis where the view only just fits), or [] when none.
static func _centre_range(area: Rect2, half: Vector2, keep: Rect2) -> Array:
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for axis in 2:
		var a_lo: float = area.position[axis] + half[axis]
		var a_hi: float = area.end[axis] - half[axis]
		if a_hi < a_lo - 0.5:
			return []
		a_hi = maxf(a_hi, a_lo)
		var l := maxf(a_lo, keep.position[axis])
		var h := minf(a_hi, keep.end[axis])
		if h < l - 0.5:
			return []
		lo[axis] = l
		hi[axis] = maxf(h, l)
	return [lo, hi]

## True when [param view] lies entirely inside the union of [param rects] (1 px tolerance).
static func covered(view: Rect2, rects: Array[Rect2]) -> bool:
	var left: Array[Rect2] = [view.grow(-1.0)]
	for r in rects:
		var next: Array[Rect2] = []
		for piece in left:
			next.append_array(_minus(piece, r))
		left = next
		if left.is_empty():
			return true
	return left.is_empty()

## [param a] minus [param b], as up to four rectangles.
static func _minus(a: Rect2, b: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var i := a.intersection(b)
	if not i.has_area():
		out.append(a)
		return out
	if i.position.y > a.position.y:
		out.append(Rect2(a.position.x, a.position.y, a.size.x, i.position.y - a.position.y))
	if i.end.y < a.end.y:
		out.append(Rect2(a.position.x, i.end.y, a.size.x, a.end.y - i.end.y))
	if i.position.x > a.position.x:
		out.append(Rect2(a.position.x, i.position.y, i.position.x - a.position.x, i.size.y))
	if i.end.x < a.end.x:
		out.append(Rect2(i.end.x, i.position.y, a.end.x - i.end.x, i.size.y))
	return out

## True when [param pos] is comfortably inside what the camera shows now.
func on_screen(pos: Vector2) -> bool:
	var cam := room_camera.camera
	var half := _viewport_size() / 2.0 / maxf(cam.zoom.x, 0.01)
	return Rect2(cam.get_screen_center_position() - half, half * 2.0).grow(-ON_SCREEN_INSET).has_point(pos)

# --- Running ----------------------------------------------------------------------------------

func _start(kind: Kind, subject: Node2D, zoom: float, seconds: float, cut_now := true) -> void:
	if _kind == Kind.NONE:
		_take()
	_kind = kind
	_subject = subject
	_reveal = Rect2()
	_world = Rect2()
	_ease_ms = 0
	_free_view = false
	_zoom = zoom
	_releasing = false
	_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	started.emit(kind)
	if room_camera.is_cut() and cut_now:
		_step(1.0)

## Takes the camera from wherever the room's camera has it, so the first frame doesn't move.
func _take() -> void:
	var cam := room_camera.camera
	_centre = cam.get_screen_center_position()
	_view_zoom = cam.zoom.x
	room_camera.directed = true
	if room_camera.using_phantom:
		if not is_instance_valid(_pcam):
			_pcam = MDSRoomCamera._new_global("PhantomCamera2D") as Node2D
			_pcam.name = "DirectorCamera"
			MDSRoomCamera._prop(_pcam, "follow_mode", 0)
			var tw := MDSRoomCamera._new_global("PhantomCameraTween") as Resource
			if tw:
				MDSRoomCamera._prop(tw, "duration", 0.0)
				MDSRoomCamera._prop(_pcam, "tween_resource", tw)
			MDSRoomCamera._prop(_pcam, "tween_on_load", false)
			_pcam.top_level = true
			room_camera.add_child(_pcam)
		_pcam.global_position = _centre
		MDSRoomCamera._prop(_pcam, "zoom", Vector2(_view_zoom, _view_zoom))
		MDSRoomCamera._prop(_pcam, "priority", room_camera.phantom_priority + 100)
	else:
		_smoothing = cam.position_smoothing_enabled
		cam.position_smoothing_enabled = false
		cam.limit_left = -10000000
		cam.limit_top = -10000000
		cam.limit_right = 10000000
		cam.limit_bottom = 10000000
		_show()

## Puts the borrowed view on the camera.
func _show() -> void:
	if room_camera.using_phantom:
		if is_instance_valid(_pcam):
			_pcam.global_position = _centre
			MDSRoomCamera._prop(_pcam, "zoom", Vector2(_view_zoom, _view_zoom))
		return
	var cam := room_camera.camera
	cam.zoom = Vector2(_view_zoom, _view_zoom)
	# The camera may follow the player by itself (a child of it): the offset carries the view.
	var at := _centre
	if cam.anchor_mode == Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT:
		at -= _viewport_size() / 2.0 / _view_zoom
	cam.offset = at - cam.global_position

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	# Real time: it also runs while the game is slowed down.
	var dt := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	if not _usable():
		return
	if get_tree().paused:
		_until_ms += int(dt * 1000.0)
		return
	if automatic and now >= _next_watch_ms:
		_next_watch_ms = now + int(watch_interval * 1000.0)
		_watch(now)
	if _kind == Kind.NONE:
		return
	if now >= _until_ms and not _releasing:
		_releasing = true
		_release_ms = now
		_ease_ms = 0
		_world = Rect2()
		_restore_time_scale()
	if _releasing and now - _release_ms > int(max_release_time * 1000.0) * (3 if _free_view else 1):
		_finish()
		return
	if _ease_ms > 0 and not _releasing:
		# A timed frame_world move: from rest, eased in and out, arriving on time.
		var t := smoothstep(0.0, 1.0, clampf(float(now - _ease_start_ms) / float(_ease_ms), 0.0, 1.0))
		_view_zoom = exp(lerpf(log(maxf(_ease_from_zoom, 0.001)), log(maxf(_zoom, 0.001)), t))
		_centre = _ease_from_centre.lerp(_world.get_center(), t)
		_show()
		return
	_step(1.0 if room_camera.is_cut() else 1.0 - exp(-glide * dt))

## Moves the view a share [param k] of the way to its target (1: there).
func _step(k: float) -> void:
	var rest := room_camera.rest_zoom()
	var target_zoom := rest if _releasing else _zoom
	var target_centre := room_camera.rest_centre(target_zoom) if _releasing else _override_centre(target_zoom)
	if not _releasing:
		target_zoom = _zoom
	# Zoom glides in log space, so a long pull-out feels even from start to end.
	var z := exp(lerpf(log(maxf(_view_zoom, 0.001)), log(maxf(target_zoom, 0.001)), k))
	var aim := _centre.lerp(target_centre, k)
	# Every frame of the way is a legal view: one that would show outside the room's shape is
	# brought back in.
	# The view always keeps the player in it, or for a focus, what it focuses on.
	var player := _player()
	var anchor := player.global_position if player else aim
	if _kind == Kind.FOCUS and not _releasing and is_instance_valid(_subject):
		anchor = _subject.global_position
	var legal := {} if _free_view and (not _releasing or z < room_camera.rest_zoom() * min_zoom) else legal_view(aim, z, anchor)
	_view_zoom = float(legal.zoom) if not legal.is_empty() else z
	_centre = legal.centre if not legal.is_empty() else aim
	_show()
	if _releasing and absf(_view_zoom - rest) < 0.004 * rest and _centre.distance_to(room_camera.rest_centre(rest)) < 2.0:
		_finish()

## Where an override looks now. A threat moves, so its view is planned again as it goes.
func _override_centre(z: float) -> Vector2:
	var player := _player()
	var p := player.global_position if player else _centre
	var s := _subject.global_position if is_instance_valid(_subject) else p
	match _kind:
		Kind.THREAT:
			var plan := plan_reveal(_reveal) if _reveal.has_area() else plan_threat_view(p, s)
			if plan.is_empty():
				_zoom = room_camera.rest_zoom()
				return room_camera.rest_centre(_zoom)
			_zoom = plan.zoom
			return plan.centre
		Kind.FOCUS:
			if _world.has_area():
				return _world.get_center()
			return s
	return (p + s) / 2.0

## Hands the camera back: the room's camera takes over where the view is (the rest view after
## a glide back, so nothing jumps).
func _finish() -> void:
	_kind = Kind.NONE
	_releasing = false
	_subject = null
	_reveal = Rect2()
	_world = Rect2()
	_ease_ms = 0
	_free_view = false
	_restore_time_scale()
	var cam := room_camera.camera
	room_camera.directed = false
	if room_camera.using_phantom:
		if is_instance_valid(_pcam):
			# The view is already the zone camera's (or must be at once, on cancel): the host cuts
			# back to it instead of tweening.
			var zone_pcam := room_camera.get_active_pcam()
			var tween: Object = zone_pcam.get("tween_resource") if zone_pcam else null
			var duration: Variant = tween.get("duration") if tween else null
			MDSRoomCamera._prop(tween, "duration", 0.0)
			MDSRoomCamera._prop(_pcam, "priority", 0)
			if tween:
				_restore_tween.call_deferred(tween, duration)
	else:
		cam.zoom = room_camera.zoom
		cam.offset = Vector2.ZERO
		room_camera.restore_limits()
		if room_camera.camera.get_parent() == room_camera or cam.top_level:
			if room_camera.target:
				cam.global_position = room_camera.target.global_position + room_camera.follow_offset
		cam.position_smoothing_enabled = _smoothing
		cam.reset_smoothing()
	released.emit()

func _restore_tween(tween: Object, duration: Variant) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(tween) and _kind == Kind.NONE:
		MDSRoomCamera._prop(tween, "duration", duration)

func _restore_time_scale() -> void:
	if _time_scale_set:
		Engine.time_scale = 1.0
		_time_scale_set = false

func _exit_tree() -> void:
	_restore_time_scale()

# --- Watching enemies ---------------------------------------------------------------------------

func _watch(_now: int) -> void:
	if _kind == Kind.FOCUS:
		return
	var player := _player()
	if not player or room_camera.rest_zoom() * min_zoom >= room_camera.rest_zoom() - 0.001:
		return
	var best: Node2D = null
	var best_d := INF
	var seen: Dictionary = {}
	for n in get_tree().get_nodes_in_group(watch_group):
		var e := n as Node2D
		if not e or e is Area2D or not e.is_inside_tree() or not e.is_visible_in_tree():
			continue
		var id := e.get_instance_id()
		var d := e.global_position.distance_to(player.global_position)
		var was: float = _last_distance.get(id, d)
		seen[id] = d
		if d > engage_range or on_screen(e.global_position) or not is_engaged(e, was - d):
			continue
		if d < best_d:
			best = e
			best_d = d
	_last_distance = seen
	if best:
		frame_threat(best, 1.4)

## True when [param e] is after the player: its [code]is_attacking[/code] is true, its state is
## not a quiet one, or it closed in by [member approach_step] since the last look.
func is_engaged(e: Node, approach: float) -> bool:
	if "health" in e:
		var h: Variant = e.get("health")
		if (h is int or h is float) and h <= 0:
			return false
	if "is_attacking" in e and e.get("is_attacking") == true:
		return true
	var state := state_name(e)
	if state.contains("DEAD"):
		return false
	if not state.is_empty():
		for q in quiet_states:
			if state.contains(q):
				return approach >= approach_step
		return true
	return approach >= approach_step

## The name of [param e]'s current state from its own enum ("CHASE"...), or "".
static func state_name(e: Node) -> String:
	for prop in ["current_state", "state"]:
		if not prop in e:
			continue
		var v: Variant = e.get(prop)
		if v is String or v is StringName:
			return str(v).to_upper()
		if not v is int:
			continue
		var s: Script = e.get_script()
		while s:
			var consts := s.get_script_constant_map()
			for key in consts:
				if consts[key] is Dictionary and String(key).to_lower().contains("state") and (consts[key] as Dictionary).values().has(v):
					return String((consts[key] as Dictionary).find_key(v)).to_upper()
			s = s.get_base_script()
	return ""

func _usable() -> bool:
	return room_camera != null and is_instance_valid(room_camera) and room_camera.camera != null and room_camera.game != null and not room_camera.room_id.is_empty()

func _player() -> Node2D:
	if room_camera.target and is_instance_valid(room_camera.target):
		return room_camera.target
	return room_camera.game.player if room_camera.game else null

func _viewport_size() -> Vector2:
	return room_camera.camera.get_viewport_rect().size
