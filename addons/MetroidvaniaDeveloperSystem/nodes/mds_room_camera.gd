@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSRoomCamera
extends Node2D
## Camera for [MDSWorldGame] rooms of any shape, driving a [Camera2D] or, when the
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
## [b]Backends.[/b] Camera2D: MDS sets the camera's limits (animated) itself. Phantom
## Camera: one PhantomCamera2D per zone, the active zone gets the highest priority and the
## PhantomCameraHost tweens between them. The Camera2D needs a PhantomCameraHost child,
## which is added when missing.
##
## Add it as a child of the MDSWorldGame (Create game scene does). Every setting can also
## come from the world file (World settings > Camera in the panel) when
## [member use_world_settings] is on.
##
## [b]Fights.[/b] An [MDSCameraDirector] child borrows the camera for a moment: framing a
## threat, revealing an arena, punching in, focusing on a node ([method get_director]).
##
## [b]Zoom between rooms.[/b] Like a PhantomCamera2D per room, each room (and each camera zone
## of an irregular room) can have a zoom of its own ([member auto_zoom]): set per room (Inspect
## tab > Camera zoom), or fitted to the zone so big rooms are seen whole and small ones closer
## ([member zoom_factor], [member min_zoom], [member max_zoom]). The zoom glides there with
## the room transition and zone changes ([member zoom_tween], [member zoom_time]), or snaps.

enum Backend { AUTO, CAMERA_2D, PHANTOM_CAMERA }
enum Confine { ROOM_SHAPE, ROOM_BOUNDS, NONE }
enum Transition { FADE, CUT, SLIDE, BLEND }
enum Motion { GLIDE, CUT }
enum AutoZoom { OFF, ROOM, FIT }

const BACKEND_NAMES: PackedStringArray = ["Auto (Phantom Camera if installed)", "Camera2D", "PhantomCamera2D"]
const CONFINE_NAMES: PackedStringArray = ["Room shape (zones)", "Room bounds", "None"]
const TRANSITION_NAMES: PackedStringArray = ["Fade", "Cut", "Slide", "Blend"]
const MOTION_NAMES: PackedStringArray = ["Glide", "Cut, never glide"]
const AUTO_ZOOM_NAMES: PackedStringArray = ["Off (always Zoom)", "Per room (a room's own zoom)", "Fit the room (out in big rooms, in in small ones)"]
## Settings read from the world file's settings.camera.
const SETTING_KEYS: PackedStringArray = ["backend", "confine", "room_transition", "transition_style", "transition_time", "zone_blend_time", "zone_hysteresis", "follow_smoothing", "zoom", "auto_zoom", "zoom_factor", "min_zoom", "max_zoom", "zoom_tween", "zoom_time", "zoom_tween_threshold"]
## The room value (Inspect tab) of a room's own zoom.
const ROOM_ZOOM_KEY := "camera_zoom"

signal zone_changed(zone: Rect2)

@export var backend: Backend = Backend.AUTO
## The Camera2D that renders the game. Empty: the MDSWorldGame's camera, else a new one.
@export var camera: Camera2D
## Node the camera follows. Empty: the MDSWorldGame's player.
@export var target: Node2D
## Values in the world file (settings.camera) override the ones set here.
@export var use_world_settings := true
@export var zoom := Vector2.ONE
## GLIDE: zones, slides, blends and the director's moves glide. CUT: the camera never glides:
## zone changes and room transitions cut, follow smoothing is off and the director cuts to its
## view and back (a camera that eases late makes the parallax and the backdrop late too).
@export var transition_style: Motion = Motion.GLIDE

@export_group("Zoom between rooms")
## OFF: always [member zoom]. ROOM: a room's own zoom (its [constant ROOM_ZOOM_KEY] room value,
## Inspect tab > Camera zoom), else [member zoom]. FIT: the zoom that fills the screen with the
## camera zone the player is in (out in big rooms and zones, in in small ones), times
## [member zoom_factor], between [member min_zoom] and [member max_zoom]; a room's own zoom
## still wins.
@export var auto_zoom: AutoZoom = AutoZoom.OFF
## FIT: scales the zoom that fills the zone (above 1 closer, below 1 farther out).
@export_range(0.1, 4.0, 0.05) var zoom_factor := 1.0
## FIT: the farthest out it zooms.
@export_range(0.05, 8.0, 0.05) var min_zoom := 0.5
## FIT: the closest in it zooms.
@export_range(0.05, 8.0, 0.05) var max_zoom := 2.0
## Zoom changes glide (on) or snap (off). They glide with the room transition (slide, blend) and
## zone changes, and over [member zoom_time] after a cut or a fade.
@export var zoom_tween := true
## Seconds the zoom glides after a cut or a fade into a room.
@export var zoom_time := 0.6
@export var zoom_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var zoom_ease: Tween.EaseType = Tween.EASE_IN_OUT
## Zoom changes smaller than this share (0.03: 3%) snap instead of gliding.
@export_range(0.0, 1.0, 0.01) var zoom_tween_threshold := 0.03

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

var game: MDSWorldGame
var zones: Array[Rect2] = []
var zone := Rect2()
var room_id := ""
var using_phantom := false

## The director borrowing the camera (see [method get_director]).
var director: MDSCameraDirector
## True while the director has the camera: the room camera keeps track of zones and limits but
## leaves the camera alone.
var directed := false

var _limits := Rect2() ## current (animated) Camera2D limits
var _limit_tween: Tween
var _zoom_tween: Tween
var _rest := Vector2.ONE ## the zoom the camera rests at in the current zone
var _pcams: Array[Node2D] = []
var _old_pcams: Array[Node2D] = []
var _busy := false

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	for c in get_children():
		if c is MDSCameraDirector:
			director = c

## The [MDSCameraDirector] of this camera (a child), added when there is none.
func get_director() -> MDSCameraDirector:
	if not is_instance_valid(director):
		director = MDSCameraDirector.new()
		director.name = "Director"
		add_child(director)
	return director

func is_cut() -> bool:
	return transition_style == Motion.CUT

## The room transition used: [member room_transition] (or [param style]), with a cut instead
## of a slide or blend when [member transition_style] is CUT.
func get_room_transition(style := -1) -> int:
	if style < 0:
		style = room_transition
	if is_cut() and (style == Transition.SLIDE or style == Transition.BLEND):
		return Transition.CUT
	return style

## Called by [MDSWorldGame] when it starts.
func setup(p_game: MDSWorldGame) -> void:
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
	_rest = zoom
	camera.offset = Vector2.ZERO
	using_phantom = backend != Backend.CAMERA_2D and phantom_available()
	if backend == Backend.PHANTOM_CAMERA and not using_phantom:
		push_warning("MDSRoomCamera: Phantom Camera is not installed or enabled; using Camera2D.")
	if using_phantom:
		_ensure_host()
	else:
		camera.position_smoothing_enabled = follow_smoothing > 0.0 and not is_cut()
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
	transition_style = int(s.get("transition_style", transition_style)) as Motion
	transition_time = float(s.get("transition_time", transition_time))
	zone_blend_time = float(s.get("zone_blend_time", zone_blend_time))
	zone_hysteresis = float(s.get("zone_hysteresis", zone_hysteresis))
	follow_smoothing = float(s.get("follow_smoothing", follow_smoothing))
	var z: Variant = s.get("zoom")
	if z is Array and z.size() == 2:
		zoom = Vector2(float(z[0]), float(z[1]))
	elif z is float or z is int:
		zoom = Vector2(float(z), float(z))
	auto_zoom = int(s.get("auto_zoom", auto_zoom)) as AutoZoom
	zoom_factor = float(s.get("zoom_factor", zoom_factor))
	min_zoom = float(s.get("min_zoom", min_zoom))
	max_zoom = float(s.get("max_zoom", max_zoom))
	zoom_tween = bool(s.get("zoom_tween", zoom_tween))
	zoom_time = float(s.get("zoom_time", zoom_time))
	zoom_tween_threshold = float(s.get("zoom_tween_threshold", zoom_tween_threshold))

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
	if not using_phantom and target and camera and (camera.get_parent() == self or camera.top_level) and not _busy and not directed:
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
		_set_zone(zones[best], 0.0 if is_cut() else zone_blend_time)

# --- Rooms ------------------------------------------------------------------------------------

## Visible world size of the camera.
func view_size() -> Vector2:
	return camera.get_viewport_rect().size / camera.zoom if camera else Vector2(1152, 648)

## Where the camera currently looks (world space).
func screen_center() -> Vector2:
	return camera.get_screen_center_position() if camera else Vector2.ZERO

## Called by [MDSWorldGame] after the new room is in place and the player is placed.
## Performs the transition (slide or blend; fades are done by the game).
func enter_room(id: String, style: int, previous_center: Vector2) -> void:
	if is_instance_valid(director):
		director.cancel()
	style = get_room_transition(style)
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
	var first := not _limits.has_area()
	var to_zoom := zoom_for(start)
	var new_limits := _limits_for(start)
	match style:
		Transition.SLIDE:
			await _slide_to(new_limits, to_zoom)
		Transition.BLEND:
			_busy = true
			zone = start
			await _tween_limits(new_limits, transition_time, transition_trans, transition_ease, to_zoom)
			_busy = false
		_:
			zone = start
			# A cut or a fade: the zoom glides from where it was (first room: it is just set).
			_glide_zoom(to_zoom, 0.0 if first else zoom_time)
			_apply_limits(new_limits)
			camera.reset_smoothing()
	zone_changed.emit(zone)

## The zoom the camera heads for in camera zone [param z] of the current room: see
## [member auto_zoom].
func zoom_for(z: Rect2) -> Vector2:
	if auto_zoom == AutoZoom.OFF:
		return zoom
	var own := room_zoom(room_id)
	if own > 0.0:
		return Vector2(own, own)
	if auto_zoom != AutoZoom.FIT or not z.has_area():
		return zoom
	var vp := camera.get_viewport_rect().size if camera else Vector2(1152, 648)
	var fill := maxf(vp.x / z.size.x, vp.y / z.size.y) * zoom_factor
	var v := clampf(fill, minf(min_zoom, max_zoom), maxf(min_zoom, max_zoom))
	return Vector2(v, v)

## Room [param id]'s own zoom (Inspect tab > Camera zoom), or 0 when it has none.
func room_zoom(id: String) -> float:
	if not game or not game.world or id.is_empty():
		return 0.0
	var v: Variant = game.world.get_room_value(id, ROOM_ZOOM_KEY, 0.0)
	var f := float(v) if v is float or v is int else str(v).to_float()
	return f if f > 0.0 else 0.0

## Whether going from zoom [param a] to [param b] is small enough to snap.
func _zoom_close(a: Vector2, b: Vector2) -> bool:
	return absf(a.x - b.x) <= maxf(absf(a.x), 0.0001) * zoom_tween_threshold and absf(a.y - b.y) <= maxf(absf(a.y), 0.0001) * zoom_tween_threshold

func _set_camera_zoom(z: Vector2) -> void:
	if directed or not camera:
		return
	camera.zoom = z
	# The limits keep up: never smaller than what the camera shows now.
	_apply_limits(_limits)

## Zooms to [param to] over [param time] (gliding when [member zoom_tween] is on and the
## change is big enough), the limits staying as they are.
func _glide_zoom(to: Vector2, time: float) -> void:
	_rest = to
	if _zoom_tween:
		_zoom_tween.kill()
	if not camera:
		return
	if not zoom_tween or time <= 0.0 or is_cut() or _zoom_close(camera.zoom, to):
		_set_camera_zoom(to)
		return
	_zoom_tween = create_tween().set_trans(zoom_trans).set_ease(zoom_ease)
	_zoom_tween.tween_method(_set_camera_zoom, camera.zoom, to, time)

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

## Camera limits for a zone: grown to at least the view size (at the zone's zoom, see
## [method zoom_for]), staying inside the room.
func _limits_for(z: Rect2) -> Rect2:
	if not z.has_area():
		return Rect2(-1e7, -1e7, 2e7, 2e7)
	var view := (camera.get_viewport_rect().size if camera else Vector2(1152, 648)) / zoom_for(z)
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
		_rest = zoom_for(z)
		for p in _pcams:
			_prop(p.get("tween_resource"), "duration", blend)
		_activate_pcam(z)
		return
	_tween_limits(_limits_for(z), blend, zone_trans, zone_ease, zoom_for(z))

func _apply_limits(r: Rect2) -> void:
	_limits = r
	if directed:
		return
	# Never smaller than the view (while zooming out), so the camera stays centred in them.
	var shown := r
	if r.size.x < 1e6:
		var view := view_size()
		for axis in 2:
			if shown.size[axis] < view[axis]:
				shown.position[axis] -= (view[axis] - shown.size[axis]) / 2.0
				shown.size[axis] = view[axis]
	camera.limit_left = floori(shown.position.x)
	camera.limit_top = floori(shown.position.y)
	camera.limit_right = ceili(shown.end.x)
	camera.limit_bottom = ceili(shown.end.y)

## Animates the limits (and the zoom, to [param to_zoom]). The camera is clamped to the
## in-between limits every frame, so it glides instead of snapping.
func _tween_limits(to: Rect2, time: float, trans: int, ease_type: int, to_zoom := Vector2.ZERO) -> void:
	if _limit_tween:
		_limit_tween.kill()
	if to_zoom == Vector2.ZERO:
		to_zoom = camera.zoom
	_rest = to_zoom
	if _zoom_tween:
		_zoom_tween.kill()
	if not zoom_tween or is_cut() or _zoom_close(camera.zoom, to_zoom):
		_set_camera_zoom(to_zoom)
	if time <= 0.0 or not _limits.has_area() or _limits.size.x > 1e6:
		_set_camera_zoom(to_zoom)
		_apply_limits(to)
		return
	# Start from exactly what is on screen, so the glide starts where the view is.
	var from_zoom := camera.zoom
	var view := view_size()
	var from := Rect2(screen_center() - view / 2.0, view)
	_apply_limits(from)
	_limit_tween = create_tween().set_trans(trans).set_ease(ease_type)
	_limit_tween.tween_method(func(k: float) -> void:
		if not directed:
			camera.zoom = from_zoom.lerp(to_zoom, k)
		_apply_limits(Rect2(from.position.lerp(to.position, k), from.size.lerp(to.size, k))), 0.0, 1.0, time)
	await _limit_tween.finished

## Pans the view from the old room to the new one (zooming to [param to_zoom] on the way),
## then locks to the new limits.
func _slide_to(new_limits: Rect2, to_zoom := Vector2.ZERO) -> void:
	_busy = true
	if to_zoom != Vector2.ZERO:
		_glide_zoom(to_zoom, transition_time)
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

# --- What the director needs --------------------------------------------------------------------

## The zoom the room's camera rests at (in the current zone, see [member auto_zoom]).
func rest_zoom() -> float:
	return _rest.x

## The limits the room's camera keeps to now (the current zone's, grown to the view).
func rest_limits() -> Rect2:
	if using_phantom or not _limits.has_area():
		return _limits_for(zone)
	return _limits

## Where the room's own camera looks at zoom [param z] (default: its rest zoom) when nothing
## directs it: the target, kept inside [method rest_limits].
func rest_centre(z := -1.0) -> Vector2:
	if z <= 0.0:
		z = rest_zoom()
	var l := rest_limits()
	var p := (target.global_position + follow_offset) if target else l.get_center()
	if l.size.x > 1e6:
		return p
	var half := (camera.get_viewport_rect().size if camera else Vector2(1152, 648)) / 2.0 / z
	var c := p
	for axis in 2:
		if l.size[axis] >= half[axis] * 2.0:
			c[axis] = clampf(p[axis], l.position[axis] + half[axis], l.end[axis] - half[axis])
		else:
			c[axis] = l.get_center()[axis]
	return c

## Rectangles a view may show at the rest zoom or closer: each zone's limits. Empty when the
## camera isn't confined.
func legal_areas() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if confine == Confine.NONE or not game or room_id.is_empty():
		return out
	if zones.is_empty():
		out.append(_limits_for(game.world.get_room_bounds(room_id)))
	for z in zones:
		out.append(_limits_for(z))
	return out

## The room's shape (world rectangles): a pulled-out view must stay inside it.
func shape_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not game or room_id.is_empty():
		return out
	if confine == Confine.ROOM_BOUNDS:
		out.append(game.world.get_room_bounds(room_id))
	else:
		out.assign(game.world.get_world_rects(room_id))
	return out

## Puts the Camera2D's limits back to the room camera's (when the director lets go).
func restore_limits() -> void:
	_apply_limits(_limits)

# --- Phantom Camera ----------------------------------------------------------------------------

func _make_pcam(z: Rect2) -> Node2D:
	var pcam := _new_global("PhantomCamera2D") as Node2D
	pcam.name = "Zone%d" % _pcams.size()
	var l := _limits_for(z)
	_prop(pcam, "priority", 0)
	_prop(pcam, "follow_mode", phantom_follow_mode)
	_prop(pcam, "zoom", zoom_for(z))
	_prop(pcam, "follow_offset", follow_offset)
	if follow_smoothing > 0.0 and not is_cut():
		_prop(pcam, "follow_damping", true)
		var d := clampf(1.0 / follow_smoothing, 0.01, 1.0)
		_prop(pcam, "follow_damping_value", Vector2(d, d))
	_prop(pcam, "limit_left", floori(l.position.x))
	_prop(pcam, "limit_top", floori(l.position.y))
	_prop(pcam, "limit_right", ceili(l.end.x))
	_prop(pcam, "limit_bottom", ceili(l.end.y))
	var tween_res := _new_global("PhantomCameraTween") as Resource
	if tween_res:
		_prop(tween_res, "duration", 0.0 if is_cut() else zone_blend_time)
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
	_rest = zoom_for(start)
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
		_prop(p.get("tween_resource"), "duration", 0.0 if is_cut() else zone_blend_time)
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
