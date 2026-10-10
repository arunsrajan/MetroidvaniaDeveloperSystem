@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/effect.svg")
class_name MDSEnvironmentEffect
extends Node2D
## Base of the environment effects: weather ([MDSDustStorm], [MDSRain], [MDSSnowfall],
## [MDSLightning], [MDSFog]), hazards ([MDSSteamVent], [MDSLava]) and scenery in motion
## ([MDSWaterfall], [MDSWater], [MDSLightShafts], [MDSEmbers], [MDSFireflies],
## [MDSFallingLeaves], [MDSHeatHaze]) and Silksong-style scenery ([MDSSilkThreads], [MDSWisps],
## [MDSGnatSwarm], [MDSDrips], [MDSHangingMoss], [MDSSwayingGrass], [MDSCobwebs],
## [MDSVoidTendrils], [MDSIncenseSmoke], [MDSForgeSparks]). Each one covers a rectangle ([method get_effect_rect],
## sized by [member size]) and draws it with a shader from [code]shaders/environment/[/code],
## in the editor too.
##
## Three ways to use them:
## - Add one like any node (Add Child Node, then search "MDS") and set it up in the inspector.
## - In the Room view, pick the Effects tool and drag an effect onto the room; select one to
##   move it, resize it from its corner and edit it in the inspector.
## - Give an area (or a room, or the whole world) weather: [MDSWorldGame] adds it to every room
##   of the area as the room loads, sized to the room (see [MDSEnvironment]).
##
## Effects that push or hurt (a dust storm's wind, steam vents, lava, waterfalls) act on the
## nodes of [member affect_groups] whose position is inside them. A CharacterBody2D is moved
## with [method CharacterBody2D.move_and_collide] (wind) or has its [code]velocity[/code] raised
## (a steam jet's launch), and [code]take_damage(amount)[/code] is called to hurt it. A body can
## handle these itself by implementing [code]mds_environment_push(velocity, delta, effect)[/code],
## [code]mds_environment_launch(velocity, effect)[/code] and
## [code]mds_environment_hurt(amount, effect)[/code]. Bodies held still (not processing, like
## the player while [MDSWorldGame] changes rooms) are left alone.

## A node of [member affect_groups] came into the effect.
signal body_entered_effect(body: Node2D)
## A node of [member affect_groups] left the effect.
signal body_exited_effect(body: Node2D)
## The effect hurt [param body] (see [method hurt_body]).
signal body_hurt(body: Node2D, amount: float)

## When the effect shows:
## - [code]ALWAYS[/code]: from the start.
## - [code]PLAYER_INSIDE[/code]: fades in while a node of [member affect_groups] is within
##   [member trigger_margin] px of it, and out once it leaves (a storm that only blows outside
##   the cave).
## - [code]MANUAL[/code]: off until [method start] is called.
enum Activation { ALWAYS, PLAYER_INSIDE, MANUAL }

const SHADER_DIR := "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/"

## Size of the area the effect covers (px), see [method get_effect_rect].
@export var size := Vector2(1152, 648):
	set(v):
		v = Vector2(maxf(v.x, 8.0), maxf(v.y, 8.0))
		if v != size:
			size = v
			_queue_rebuild()
## How strong it is (0: off).
@export_range(0.0, 1.0) var intensity := 1.0:
	set(v):
		intensity = clampf(v, 0.0, 1.0)
		_refresh_strength()
@export var activation: Activation = Activation.ALWAYS
## Seconds to fade in or out.
@export_range(0.0, 10.0, 0.05) var fade_time := 1.0
## How far (px) around the effect a body starts it, with PLAYER_INSIDE.
@export var trigger_margin := 0.0
## Cover the whole room. Effects of an area's or a room's weather that have it are moved and
## sized to the room as it loads (in the game and in the Room view's weather preview).
@export var fit_room := false
## Varies the pattern, so two effects side by side don't move in step.
@export var seed_value := 0:
	set(v):
		seed_value = v
		_changed()
@export_group("Bodies")
## Nodes in these groups are pushed or hurt by the effect and reported by
## [signal body_entered_effect].
@export var affect_groups: PackedStringArray = ["player"]
@export_group("Editor")
## Animate it in the editor (off: it is drawn only in the game).
@export var preview_in_editor := true:
	set(v):
		preview_in_editor = v
		_refresh_strength()

var _materials: Array[ShaderMaterial] = []
var _quads: Array[CanvasItem] = []
var _pending := false
var _on := true
var _fade := 1.0
var _fade_now := -1.0 ## the fade time start() or stop() asked for (negative: fade_time)
var _strength := -1.0
var _inside: Dictionary = {}
var _hurt_at: Dictionary = {}

func _ready() -> void:
	if not Engine.is_editor_hint():
		_on = activation == Activation.ALWAYS
		_fade = 1.0 if _on else 0.0
	rebuild()

# --- Settings -----------------------------------------------------------------------------------

## A short id of the effect ("rain", "dust_storm"...), as [MDSEnvironment] lists it.
func get_effect_id() -> String:
	return ""

## The area the effect covers, in its own coordinates: from its position by default; some
## effects stand on their position instead (a steam vent's jet rises from it).
func get_effect_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size)

## Where bodies are pushed or hurt (its own coordinates). Usually [method get_effect_rect].
func get_body_rect() -> Rect2:
	return get_effect_rect()

## Moves and sizes the effect to cover [param rect] (in its parent's coordinates).
func fit_to(rect: Rect2) -> void:
	size = rect.size
	position = rect.position - get_effect_rect().position

## How visible the effect is now: its [member intensity] times its fade in or out.
func get_strength() -> float:
	if Engine.is_editor_hint():
		return intensity if preview_in_editor else 0.0
	return intensity * _fade

## Fades the effect in, over [param seconds] (negative: [member fade_time]; 0: at once).
func start(seconds := -1.0) -> void:
	_on = true
	_fade_now = seconds
	if seconds == 0.0:
		_fade = 1.0
	_refresh_strength()

## Fades the effect out, over [param seconds] (negative: [member fade_time]; 0: at once).
func stop(seconds := -1.0) -> void:
	_on = false
	_fade_now = seconds
	if seconds == 0.0:
		_fade = 0.0
	_refresh_strength()

func is_active() -> bool:
	return get_strength() > 0.0

# --- Building -----------------------------------------------------------------------------------

func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_rebuild_deferred.call_deferred()

func _rebuild_deferred() -> void:
	_pending = false
	rebuild()

## Makes the effect's parts again (after its size or layout changed).
func rebuild() -> void:
	for c in get_children(true):
		if c.has_meta(&"mds_part"):
			remove_child(c)
			c.queue_free()
	_materials.clear()
	_quads.clear()
	_build()
	_strength = -1.0
	_changed()
	queue_redraw()

## Effect-specific: makes the parts (with [method add_quad], [method add_part]).
func _build() -> void:
	pass

## Effect-specific: sends the settings to the shaders (with [method set_param]).
func _update_params() -> void:
	pass

## Effect-specific: animates it (lightning strikes, a vent's cycle). Runs in the editor too
## while [member preview_in_editor] is on.
func _tick(_delta: float) -> void:
	pass

## Effect-specific: acts on a body inside it this physics frame, at [param strength].
func _affect(_body: Node2D, _delta: float, _strength_now: float) -> void:
	pass

## Effect-specific: the strength changed (0..1).
func _strength_changed(_value: float) -> void:
	pass

## Call when a setting changed: the shaders get it.
func _changed() -> void:
	if _materials.is_empty():
		return
	for m in _materials:
		m.set_shader_parameter("seed", float(seed_value) * 1.37 + float(m.get_meta(&"mds_seed", 0.0)))
	_update_params()
	_strength = -1.0
	_refresh_strength()

func _refresh_strength() -> void:
	var s := get_strength()
	if is_equal_approx(s, _strength):
		return
	_strength = s
	for m in _materials:
		m.set_shader_parameter("intensity", s)
	for q in _quads:
		q.visible = s > 0.0005
	_strength_changed(s)

static func shader(shader_name: String) -> Shader:
	return load(SHADER_DIR + shader_name + ".gdshader") as Shader

## A rectangle drawn with [param sh] ([param rect] in the effect's coordinates). With
## [param absolute_z] it is drawn at that z whatever the effect's own z_index (a far plane
## behind the terrain). [param seed_offset] varies its pattern from the effect's others.
func add_quad(sh: Shader, rect: Rect2, z := 0, seed_offset := 0.0, absolute_z := false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_meta(&"mds_seed", seed_offset)
	mat.set_shader_parameter("rect_origin", rect.position)
	mat.set_shader_parameter("rect_size", rect.size)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	poly.material = mat
	poly.z_index = z
	poly.z_as_relative = not absolute_z
	add_part(poly)
	_materials.append(mat)
	_quads.append(poly)
	return mat

## Adds a part of the effect (internal: not saved with the scene, remade by [method rebuild]).
func add_part(node: Node) -> void:
	node.set_meta(&"mds_part", true)
	add_child(node, false, Node.INTERNAL_MODE_BACK)

## Sets a shader parameter on every part.
func set_param(param: StringName, value: Variant) -> void:
	for m in _materials:
		m.set_shader_parameter(param, value)

func get_materials() -> Array[ShaderMaterial]:
	return _materials

# --- Running ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_refresh_strength()
		if preview_in_editor:
			_tick(delta)
		return
	if activation == Activation.PLAYER_INSIDE:
		var was := _on
		_on = not bodies_inside(trigger_margin, get_effect_rect()).is_empty()
		if _on != was:
			_fade_now = -1.0
	var want := 1.0 if _on else 0.0
	var seconds := _fade_now if _fade_now >= 0.0 else fade_time
	if _fade != want:
		_fade = move_toward(_fade, want, delta / seconds) if seconds > 0.0 else want
	_refresh_strength()
	_tick(delta)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or affect_groups.is_empty() or not is_inside_tree():
		return
	var now := bodies_inside()
	for b in now:
		if not _inside.has(b):
			_inside[b] = true
			body_entered_effect.emit(b)
	for b in _inside.keys():
		if not is_instance_valid(b):
			_inside.erase(b)
		elif not now.has(b):
			_inside.erase(b)
			body_exited_effect.emit(b)
	var s := get_strength()
	if s > 0.0:
		for b in now:
			if can_affect(b):
				_affect(b, delta, s)

## Whether effects can act on [param body] now: it is processing (not paused, and not held
## still the way [MDSWorldGame] holds the player during a room change) and, for a physics body,
## in a physics space. A body whose processing is disabled is taken out of its space, and
## moving it then is an error.
static func can_affect(body: Node2D) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree() or not body.can_process():
		return false
	return _in_physics_space(body)

static func _in_physics_space(body: Node2D) -> bool:
	if body is PhysicsBody2D:
		return PhysicsServer2D.body_get_space((body as PhysicsBody2D).get_rid()).is_valid()
	if body is Area2D:
		return PhysicsServer2D.area_get_space((body as Area2D).get_rid()).is_valid()
	return true

## The nodes of [member affect_groups] whose position is inside [param rect] (its own
## coordinates; empty: [method get_body_rect]), grown by [param margin] px.
func bodies_inside(margin := 0.0, rect := Rect2()) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if not is_inside_tree():
		return out
	var r := (rect if rect.has_area() else get_body_rect()).grow(margin)
	var inv := global_transform.affine_inverse()
	for g in affect_groups:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node2D and not out.has(n) and r.has_point(inv * (n as Node2D).global_position):
				out.append(n)
	return out

## Where up to [param count] nodes of [member affect_groups] within [param margin] px of the
## effect are, in its shaders' pixels (from the rectangle's top-left corner), the nearest to its
## middle first. For effects that bend away from bodies or reach for them (grass, moss, tendrils).
func body_points(count := 4, margin := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not is_inside_tree():
		return out
	var r := get_effect_rect()
	var inv := global_transform.affine_inverse()
	var mid := r.get_center()
	var near: Array[Vector2] = []
	for b in bodies_inside(margin, r):
		near.append(inv * b.global_position)
	near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(mid) < b.distance_squared_to(mid))
	for i in mini(count, near.size()):
		out.append(near[i] - r.position)
	return out

## Sends [method body_points] to the shaders: [code]bodies[/code] (vec2[4]) and
## [code]body_count[/code]. Returns how many there are.
func send_bodies(margin := 0.0) -> int:
	var pts := body_points(4, margin)
	var n := pts.size()
	pts.resize(4)
	set_param(&"bodies", pts)
	set_param(&"body_count", n)
	return n

## Pushes [param body] along [param velocity] (px/s, global) for this physics frame: wind,
## a current. Moves a CharacterBody2D with move_and_collide, so it never goes through walls.
## A physics body outside a physics space (held still, not yet added) isn't moved.
func push_body(body: Node2D, velocity: Vector2, delta: float) -> void:
	if body.has_method(&"mds_environment_push"):
		body.call(&"mds_environment_push", velocity, delta, self)
	elif body is PhysicsBody2D and not _in_physics_space(body):
		return
	elif body is CharacterBody2D:
		(body as CharacterBody2D).move_and_collide(velocity * delta)
	elif body is RigidBody2D:
		var rb := body as RigidBody2D
		rb.apply_central_force(velocity * rb.mass)
	else:
		body.global_position += velocity * delta

## Throws [param body] along [param velocity] (px/s, global): its speed that way becomes at
## least that much (a steam jet).
func launch_body(body: Node2D, velocity: Vector2) -> void:
	if body.has_method(&"mds_environment_launch"):
		body.call(&"mds_environment_launch", velocity, self)
		return
	var dir := velocity.normalized()
	var want := velocity.length()
	if body is RigidBody2D:
		var rb := body as RigidBody2D
		var along_rb := rb.linear_velocity.dot(dir)
		if along_rb < want:
			rb.linear_velocity += dir * (want - along_rb)
	elif "velocity" in body:
		var v: Vector2 = body.get("velocity")
		var along := v.dot(dir)
		if along < want:
			body.set("velocity", v + dir * (want - along))

## Hurts [param body] by [param amount], at most once every [param interval] seconds: calls
## its mds_environment_hurt(amount, effect) or take_damage(amount), and emits
## [signal body_hurt]. Returns whether it was hurt.
func hurt_body(body: Node2D, amount: float, interval := 0.5) -> bool:
	if amount <= 0.0:
		return false
	var id := body.get_instance_id()
	var now := Time.get_ticks_msec()
	if _hurt_at.get(id, 0) > now:
		return false
	_hurt_at[id] = now + int(interval * 1000.0)
	if body.has_method(&"mds_environment_hurt"):
		body.call(&"mds_environment_hurt", amount, self)
	elif body.has_method(&"take_damage"):
		body.call(&"take_damage", amount)
	body_hurt.emit(body, amount)
	return true

# --- Editor -------------------------------------------------------------------------------------

func _draw() -> void:
	# The covered area, as a faint outline in the editor (the game draws nothing here).
	if not Engine.is_editor_hint():
		return
	var r := get_effect_rect()
	draw_rect(r, Color(0.55, 0.85, 1.0, 0.35), false, 1.0)

# --- Data (undo, copies) ------------------------------------------------------------------------

## The effect's settings: {script, name, transform, z_index, visible, props, meta}.
func to_data() -> Dictionary:
	var props: Dictionary = {}
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE:
			props[p.name] = _copy(get(p.name))
	var meta: Dictionary = {}
	for k in get_meta_list():
		meta[k] = _copy(get_meta(k))
	return {"script": get_script(), "name": String(name), "transform": transform, "z_index": z_index,
		"visible": visible, "props": props, "meta": meta}

## An effect made from [method to_data].
static func from_data(d: Dictionary) -> MDSEnvironmentEffect:
	var e: MDSEnvironmentEffect = (d.script as Script).new()
	apply_data(e, d)
	return e

## Gives [param e] the settings of [param d], leaving equal values alone (so a scene saved
## unchanged stays unchanged).
static func apply_data(e: MDSEnvironmentEffect, d: Dictionary) -> void:
	var props: Dictionary = d.get("props", {})
	for k in props:
		if not _same(e.get(k), props[k]):
			e.set(k, _copy(props[k]))
	if e.transform != d.transform:
		e.transform = d.transform
	if e.z_index != int(d.z_index):
		e.z_index = int(d.z_index)
	if e.visible != bool(d.visible):
		e.visible = bool(d.visible)
	if not str(d.get("name", "")).is_empty() and e.name != StringName(d.name):
		e.name = d.name
	var meta: Dictionary = d.get("meta", {})
	for k in meta:
		if not e.has_meta(k) or e.get_meta(k) != meta[k]:
			e.set_meta(k, _copy(meta[k]))
	for k in e.get_meta_list():
		if not meta.has(k):
			e.remove_meta(k)

## Arrays (packed too), dictionaries and the resources kept in the scene (a parallax
## background's layers) are shared by reference: snapshots get a copy.
static func _copy(v: Variant) -> Variant:
	if v is Array:
		var out: Array = v.duplicate()
		for i in out.size():
			if _local(out[i]):
				out[i] = (out[i] as Resource).duplicate()
		return out
	if v is Dictionary or v is PackedStringArray or v is PackedVector2Array or v is PackedFloat32Array or v is PackedColorArray or v is PackedInt32Array:
		return v.duplicate()
	if _local(v):
		return (v as Resource).duplicate()
	return v

## A resource saved inside the scene (or not saved yet), not one of its own file.
static func _local(v: Variant) -> bool:
	return v is Resource and ((v as Resource).resource_path.is_empty() or (v as Resource).resource_path.contains("::"))

## Equal values, comparing resources kept in the scene by their settings (a copy of one is the
## same).
static func _same(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same(a[i], b[i]):
				return false
		return true
	if _local(a) and _local(b):
		if a == b:
			return true
		if (a as Resource).get_script() != (b as Resource).get_script():
			return false
		for p in (a as Resource).get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE and not _same(a.get(p.name), b.get(p.name)):
				return false
		return true
	return a == b
