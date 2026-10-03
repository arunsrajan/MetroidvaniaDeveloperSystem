@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_idp.png")
class_name IDPRoomCamera
extends Node2D
## Camera for [IDPWorldGame] rooms of any shape, driving a [Camera2D] or, when the
## Phantom Camera addon is installed, [code]PhantomCamera2D[/code] nodes.
##
## [b]Irregular rooms.[/b] An L-, T- or U-shaped room is split into camera zones: the
## largest rectangles that fit in its shape on the map. The camera is limited to the zone
## the player is in, so it never shows the solid rock in the room's notches, and it glides
## to the next zone when the player moves into it (like Hollow Knight's camera locks).
## Zones smaller than the screen grow to the screen size, staying inside the room.
##
## [b]Room transitions.[/b] Cut, fade to black, slide (the view pans from the old room to
## the new one while the player waits, like classic Metroid) or blend (the limits glide
## over and the player keeps moving).
##
## [b]Backends.[/b] Camera2D: IDP sets the camera's limits (animated) itself. Phantom
## Camera: one PhantomCamera2D per zone, the active zone gets the highest priority and the
## PhantomCameraHost tweens between them. The Camera2D needs a PhantomCameraHost child,
## which is added when missing.
##
## Add it as a child of the IDPWorldGame (Create game scene does). Every setting can also
## come from the world file (World settings > Camera in the panel) when
## [member use_world_settings] is on.

enum Backend { AUTO, CAMERA_2D, PHANTOM_CAMERA }
enum Confine { ROOM_SHAPE, ROOM_BOUNDS, NONE }
enum Transition { FADE, CUT, SLIDE, BLEND }

const BACKEND_NAMES: PackedStringArray = ["Auto (Phantom Camera if installed)", "Camera2D", "PhantomCamera2D"]
const CONFINE_NAMES: PackedStringArray = ["Room shape (zones)", "Room bounds", "None"]
const TRANSITION_NAMES: PackedStringArray = ["Fade", "Cut", "Slide", "Blend"]
## Settings read from the world file's settings.camera.
const SETTING_KEYS: PackedStringArray = ["backend", "confine", "room_transition", "transition_time", "zone_blend_time", "zone_hysteresis", "follow_smoothing", "zoom"]

signal zone_changed(zone: Rect2)

@export var backend: Backend = Backend.AUTO
## The Camera2D that renders the game. Empty: the IDPWorldGame's camera, else a new one.
@export var camera: Camera2D
## Node the camera follows. Empty: the IDPWorldGame's player.
@export var target: Node2D
## Values in the world file (settings.camera) override the ones set here.
@export var use_world_settings := true
@export var zoom := Vector2.ONE

@export_group("Irregular rooms")
## How the camera is kept inside a room: by its shape (zones), by its bounding box, or not.
@export var confine: Confine = Confine.ROOM_SHAPE
## Seconds the camera takes to glide between zones of a room.
@export var zone_blend_time := 0.5
@export var zone_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var zone_ease: Tween.EaseType = Tween.EASE_IN_OUT
## How far (px) the player must leave a zone before the camera switches zones. Stops
## flicker at zone edges.
@export var zone_hysteresis := 32.0

@export_group("Room transitions")
@export var room_transition: Transition = Transition.FADE
## Seconds for fade, slide and blend.
@export var transition_time := 0.35
@export var transition_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var transition_ease: Tween.EaseType = Tween.EASE_IN_OUT
## Freeze the player while a slide pans the view.
@export var freeze_player_on_slide := true

@export_group("Follow")
## Camera2D position smoothing speed (0 = off). With Phantom Camera: follow damping.
@export var follow_smoothing := 0.0
@export var follow_offset := Vector2.ZERO
## PhantomCamera2D follow mode (0 none, 1 glued, 2 simple, 5 framed).
@export var phantom_follow_mode := 2
## Priority given to the active zone's PhantomCamera2D (others get 0).
@export var phantom_priority := 20

var game: IDPWorldGame
var zones: Array[Rect2] = []
var zone := Rect2()
var room_id := ""
var using_phantom := false

var _limits := Rect2() ## current (animated) Camera2D limits
var _limit_tween: Tween
var _pcams: Array[Node2D] = []
var _old_pcams: Array[Node2D] = []
var _busy := false

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO

## Called by [IDPWorldGame] when it starts.
func setup(p_game: IDPWorldGame) -> void:
	game = p_game
	if use_world_settings and game.world:
		apply_settings(game.world.get_setting("camera", {}))
	if not camera:
		camera = game.camera
	if not camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		add_child(camera)
		camera.top_level = true
	if not target:
		target = game.player
	camera.zoom = zoom
	camera.offset = Vector2.ZERO
	using_phantom = backend != Backend.CAMERA_2D and phantom_available()
	if backend == Backend.PHANTOM_CAMERA and not using_phantom:
		push_warning("IDPRoomCamera: Phantom Camera is not installed or enabled; using Camera2D.")
	if using_phantom:
		_ensure_host()
	else:
		camera.position_smoothing_enabled = follow_smoothing > 0.0
		camera.position_smoothing_speed = maxf(follow_smoothing, 0.01)
		if camera.get_parent() == self or camera.top_level:
			# A free camera (not a child of the player) follows the target itself.
			set_process(true)
	camera.make_current()

## Applies a settings dictionary (as stored in the world file).
func apply_settings(s: Dictionary) -> void:
	if s.is_empty():
		return
	backend = int(s.get("backend", backend)) as Backend
	confine = int(s.get("confine", confine)) as Confine
	room_transition = int(s.get("room_transition", room_transition)) as Transition
	transition_time = float(s.get("transition_time", transition_time))
	zone_blend_time = float(s.get("zone_blend_time", zone_blend_time))
	zone_hysteresis = float(s.get("zone_hysteresis", zone_hysteresis))
	follow_smoothing = float(s.get("follow_smoothing", follow_smoothing))
	var z: Variant = s.get("zoom")
	if z is Array and z.size() == 2:
		zoom = Vector2(float(z[0]), float(z[1]))
	elif z is float or z is int:
		zoom = Vector2(float(z), float(z))

## True when the Phantom Camera addon's classes (and its manager autoload) exist.
static func phantom_available() -> bool:
	return not _global_class_path("PhantomCamera2D").is_empty() and not _global_class_path("PhantomCameraHost").is_empty() and Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root.has_node("PhantomCameraManager")

static func _global_class_path(class_name_: String) -> String:
	for c in ProjectSettings.get_global_class_list():
		if c.get("class") == class_name_:
			return c.get("path", "")
	return ""

static func _new_global(class_name_: String) -> Object:
	var p := _global_class_path(class_name_)
	return (load(p) as Script).new() if not p.is_empty() else null

static func _prop(obj: Object, prop: String, value: Variant) -> void:
	if obj and prop in obj:
		obj.set(prop, value)

func _ensure_host() -> void:
	for c in camera.get_children():
		if c.get_script() and c.get_script().get_global_name() == &"PhantomCameraHost":
			return
	var host := _new_global("PhantomCameraHost") as Node
	host.name = "PhantomCameraHost"
	camera.add_child(host)

func _process(_delta: float) -> void:
	if not using_phantom and target and camera and (camera.get_parent() == self or camera.top_level) and not _busy:
		camera.global_position = target.global_position + follow_offset

func _physics_process(_delta: float) -> void:
	if not game or not target or room_id.is_empty() or _busy or confine != Confine.ROOM_SHAPE or zones.size() < 2:
		return
	var p := target.global_position
	if zone.grow(zone_hysteresis).has_point(p):
		return
	var best := -1
	for i in zones.size():
		if zones[i].has_point(p) and (best < 0 or zones[i].get_area() > zones[best].get_area()):
			best = i
	if best >= 0 and zones[best] != zone:
		_set_zone(zones[best], zone_blend_time)

# --- Rooms ------------------------------------------------------------------------------------

## Visible world size of the camera.
func view_size() -> Vector2:
	return camera.get_viewport_rect().size / camera.zoom if camera else Vector2(1152, 648)

## Where the camera currently looks (world space).
func screen_center() -> Vector2:
	return camera.get_screen_center_position() if camera else Vector2.ZERO

## Called by [IDPWorldGame] after the new room is in place and the player is placed.
## Performs the transition (slide or blend; fades are done by the game).
func enter_room(id: String, style: int, previous_center: Vector2) -> void:
	room_id = id
	var rects := game.world.get_world_rects(id)
	match confine:
		Confine.ROOM_SHAPE:
			zones = camera_zones(rects)
		Confine.ROOM_BOUNDS:
			zones = [game.world.get_room_bounds(id)]
		_:
			zones = []
	var start := _zone_for(target.global_position if target else game.world.get_room_label_pos(id))
	if using_phantom:
		await _enter_room_phantom(start, style)
		return
	var new_limits := _limits_for(start)
	match style:
		Transition.SLIDE:
			await _slide_to(new_limits)
		Transition.BLEND:
			_busy = true
			zone = start
			await _tween_limits(new_limits, transition_time, transition_trans, transition_ease)
			_busy = false
		_:
			zone = start
			_apply_limits(new_limits)
			camera.reset_smoothing()
	zone_changed.emit(zone)

func _zone_for(p: Vector2) -> Rect2:
	var best := Rect2()
	for z in zones:
		if z.has_point(p) and z.get_area() > best.get_area():
			best = z
	if best.has_area() or zones.is_empty():
		return best
	# Outside every zone (e.g. just past a gate): the nearest one.
	var dist := INF
	for z in zones:
		var d := p.distance_to(p.clamp(z.position, z.end))
		if d < dist:
			dist = d
			best = z
	return best

## Camera limits for a zone: grown to at least the view size, staying inside the room.
func _limits_for(z: Rect2) -> Rect2:
	if not z.has_area():
		return Rect2(-1e7, -1e7, 2e7, 2e7)
	var view := view_size()
	var bounds := game.world.get_room_bounds(room_id)
	var r := z
	for axis in 2:
		if r.size[axis] < view[axis]:
			var grow := view[axis] - r.size[axis]
			var lo := r.position[axis] - grow / 2.0
			# Keep inside the room bounds when the room is big enough.
			if bounds.size[axis] >= view[axis]:
				lo = clampf(lo, bounds.position[axis], bounds.end[axis] - view[axis])
			r.position[axis] = lo
			r.size[axis] = view[axis]
	return r

func _set_zone(z: Rect2, blend: float) -> void:
	zone = z
	zone_changed.emit(z)
	if using_phantom:
		_activate_pcam(z)
		return
	_tween_limits(_limits_for(z), blend, zone_trans, zone_ease)

func _apply_limits(r: Rect2) -> void:
	_limits = r
	camera.limit_left = floori(r.position.x)
	camera.limit_top = floori(r.position.y)
	camera.limit_right = ceili(r.end.x)
	camera.limit_bottom = ceili(r.end.y)

## Animates the limits. The camera is clamped to the in-between limits every frame, so it
## glides instead of snapping.
func _tween_limits(to: Rect2, time: float, trans: int, ease_type: int) -> void:
	if _limit_tween:
		_limit_tween.kill()
	if time <= 0.0 or not _limits.has_area() or _limits.size.x > 1e6:
		_apply_limits(to)
		return
	# Start from exactly what is on screen, so the glide starts where the view is.
	var view := view_size()
	var from := Rect2(screen_center() - view / 2.0, view)
	_apply_limits(from)
	_limit_tween = create_tween().set_trans(trans).set_ease(ease_type)
	_limit_tween.tween_method(_apply_limits, from, to, time)
	await _limit_tween.finished

## Pans the view from the old room to the new one, then locks to the new limits.
func _slide_to(new_limits: Rect2) -> void:
	_busy = true
	var old_center := screen_center()
	var smoothing := camera.position_smoothing_enabled
	camera.position_smoothing_enabled = false
	var frozen: Node = target if freeze_player_on_slide else null
	var old_mode := frozen.process_mode if frozen else Node.PROCESS_MODE_INHERIT
	if frozen:
		frozen.process_mode = Node.PROCESS_MODE_DISABLED
	if camera.get_parent() == self or camera.top_level:
		camera.global_position = target.global_position + follow_offset if target else camera.global_position
	var base := camera.global_position
	var view := view_size()
	var goal := base.clamp(new_limits.position + view / 2.0, new_limits.end - view / 2.0) if new_limits.size.x >= view.x and new_limits.size.y >= view.y else new_limits.get_center()
	_apply_limits(Rect2(-1e7, -1e7, 2e7, 2e7))
	camera.offset = old_center - base
	camera.reset_smoothing()
	var tw := create_tween().set_trans(transition_trans).set_ease(transition_ease)
	tw.tween_property(camera, "offset", goal - base, maxf(transition_time, 0.01))
	await tw.finished
	camera.offset = Vector2.ZERO
	_apply_limits(new_limits)
	zone = _zone_for(target.global_position) if target else zone
	camera.reset_smoothing()
	camera.position_smoothing_enabled = smoothing
	if frozen:
		frozen.process_mode = old_mode
	_busy = false

# --- Phantom Camera ----------------------------------------------------------------------------

func _make_pcam(z: Rect2) -> Node2D:
	var pcam := _new_global("PhantomCamera2D") as Node2D
	pcam.name = "Zone%d" % _pcams.size()
	var l := _limits_for(z)
	_prop(pcam, "priority", 0)
	_prop(pcam, "follow_mode", phantom_follow_mode)
	_prop(pcam, "zoom", zoom)
	_prop(pcam, "follow_offset", follow_offset)
	if follow_smoothing > 0.0:
		_prop(pcam, "follow_damping", true)
		var d := clampf(1.0 / follow_smoothing, 0.01, 1.0)
		_prop(pcam, "follow_damping_value", Vector2(d, d))
	_prop(pcam, "limit_left", floori(l.position.x))
	_prop(pcam, "limit_top", floori(l.position.y))
	_prop(pcam, "limit_right", ceili(l.end.x))
	_prop(pcam, "limit_bottom", ceili(l.end.y))
	var tween_res := _new_global("PhantomCameraTween") as Resource
	if tween_res:
		_prop(tween_res, "duration", zone_blend_time)
		_prop(tween_res, "transition", 1) # sine
		_prop(tween_res, "ease", 2) # in-out
		_prop(pcam, "tween_resource", tween_res)
	pcam.set_meta(&"idp_zone", z)
	pcam.global_position = target.global_position if target else l.get_center()
	add_child(pcam)
	_prop(pcam, "follow_target", target)
	return pcam

func _enter_room_phantom(start: Rect2, style: int) -> void:
	_old_pcams = _pcams.duplicate()
	_pcams.clear()
	var list := zones if not zones.is_empty() else [Rect2()]
	for z in list:
		_pcams.append(_make_pcam(z))
	zone = start
	# How the host moves to the new room's camera: tweened for slide/blend, instant else.
	var time := transition_time if style == Transition.SLIDE or style == Transition.BLEND else 0.0
	var frozen: Node = target if style == Transition.SLIDE and freeze_player_on_slide else null
	var old_mode := frozen.process_mode if frozen else Node.PROCESS_MODE_INHERIT
	if frozen:
		frozen.process_mode = Node.PROCESS_MODE_DISABLED
	_busy = true
	for p in _pcams:
		_prop(p.get("tween_resource"), "duration", time)
	_activate_pcam(start)
	if time > 0.0:
		await get_tree().create_timer(time).timeout
	else:
		await get_tree().process_frame
	for p in _pcams:
		_prop(p.get("tween_resource"), "duration", zone_blend_time)
	for p in _old_pcams:
		if is_instance_valid(p):
			p.queue_free()
	_old_pcams.clear()
	if frozen:
		frozen.process_mode = old_mode
	_busy = false
	zone_changed.emit(zone)

func _activate_pcam(z: Rect2) -> void:
	for p in _pcams:
		_prop(p, "priority", phantom_priority if p.get_meta(&"idp_zone", Rect2()) == z else 0)
	for p in _old_pcams:
		if is_instance_valid(p):
			_prop(p, "priority", 0)

## The active PhantomCamera2D (null with the Camera2D backend).
func get_active_pcam() -> Node2D:
	for p in _pcams:
		if p.get("priority") == phantom_priority:
			return p
	return null

# --- Zones -------------------------------------------------------------------------------------

## Camera zones of a room made of [param rects]: its maximal rectangles (the largest
## rectangles that fit in the shape), with ones inside others dropped.
static func camera_zones(rects: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if rects.size() <= 1:
		out.assign(rects)
		return out
	# Coordinate compression: a grid on the rect edges, cells covered or not.
	var xs: Array = []
	var ys: Array = []
	for r in rects:
		for v in [r.position.x, r.end.x]:
			if not v in xs:
				xs.append(v)
		for v in [r.position.y, r.end.y]:
			if not v in ys:
				ys.append(v)
	xs.sort()
	ys.sort()
	var w := xs.size() - 1
	var h := ys.size() - 1
	var covered: Array = []
	for j in h:
		var row: Array = []
		for i in w:
			var c := Vector2((xs[i] + xs[i + 1]) / 2.0, (ys[j] + ys[j + 1]) / 2.0)
			var hit := false
			for r in rects:
				if r.has_point(c):
					hit = true
					break
			row.append(hit)
		covered.append(row)
	var full := func(i0: int, i1: int, j0: int, j1: int) -> bool:
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				if not covered[j][i]:
					return false
		return true
	var found: Array[Rect2] = []
	# Every horizontal run grown up and down, and every vertical run grown left and right.
	for j in h:
		var i := 0
		while i < w:
			if not covered[j][i]:
				i += 1
				continue
			var i1 := i
			while i1 + 1 < w and covered[j][i1 + 1]:
				i1 += 1
			var j0 := j
			var j1 := j
			while j0 > 0 and full.call(i, i1, j0 - 1, j0 - 1):
				j0 -= 1
			while j1 + 1 < h and full.call(i, i1, j1 + 1, j1 + 1):
				j1 += 1
			found.append(Rect2(xs[i], ys[j0], xs[i1 + 1] - xs[i], ys[j1 + 1] - ys[j0]))
			i = i1 + 1
	for i in w:
		var j := 0
		while j < h:
			if not covered[j][i]:
				j += 1
				continue
			var j1 := j
			while j1 + 1 < h and covered[j1 + 1][i]:
				j1 += 1
			var i0 := i
			var i1 := i
			while i0 > 0 and full.call(i0 - 1, i0 - 1, j, j1):
				i0 -= 1
			while i1 + 1 < w and full.call(i1 + 1, i1 + 1, j, j1):
				i1 += 1
			found.append(Rect2(xs[i0], ys[j], xs[i1 + 1] - xs[i0], ys[j1 + 1] - ys[j]))
			j = j1 + 1
	for r in found:
		var inside := false
		for o in found:
			if o != r and o.encloses(r):
				inside = true
				break
		if not inside and not r in out:
			out.append(r)
	return out
