@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/lightning.svg")
class_name MDSLightning
extends MDSEnvironmentEffect
## Lightning: every few seconds a forked bolt cracks down through the sky (behind the
## terrain), the whole rectangle flashes and flickers, and the thunder follows. Strikes come
## at random within [member interval], or when you call [method strike].

## A bolt struck at [param at] (the effect's coordinates).
signal struck(at: Vector2)

## Seconds between strikes (random within the range). 0 and 0: only [method strike].
@export var interval := Vector2(3.0, 9.0)
## How bright the flash is.
@export_range(0.0, 1.0) var flash_strength := 0.75
@export var flash_color := Color(0.80, 0.86, 1.0):
	set(v):
		flash_color = v
		_changed()
## Share of the flash spread evenly over the sky, away from the bolt.
@export_range(0.0, 1.0) var flash_spread := 0.35:
	set(v):
		flash_spread = v
		_changed()
@export_group("Bolt")
## Draw a bolt (off: only the flash, as from a strike out of sight).
@export var bolts := true
@export var bolt_color := Color(0.85, 0.9, 1.0)
@export_range(0.5, 12.0) var bolt_width := 3.0
## Forks off the main bolt.
@export_range(0, 8) var forks := 3
## How far down the bolt reaches, as shares of the height (random between them).
@export var reach := Vector2(0.45, 1.0)
## z of the bolt: behind the terrain by default.
@export var bolt_z := -6:
	set(v):
		bolt_z = v
		_queue_rebuild()
@export_group("Thunder")
## Played after each strike (none: silent).
@export var thunder: AudioStream
## Seconds between the flash and the thunder (random between them).
@export var thunder_delay := Vector2(0.3, 1.6)
@export var thunder_volume_db := 0.0

var _flash_mat: ShaderMaterial
var _bolt_root: Node2D
var _player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _wait := 1.0
var _since := 100.0
var _thunder_in := -1.0

func _init() -> void:
	z_index = 29

func get_effect_id() -> String:
	return "lightning"

func _build() -> void:
	_flash_mat = add_quad(shader("lightning_flash"), get_effect_rect())
	_bolt_root = Node2D.new()
	_bolt_root.name = "Bolts"
	_bolt_root.z_index = bolt_z
	_bolt_root.z_as_relative = false
	add_part(_bolt_root)
	_player = AudioStreamPlayer.new()
	_player.name = "Thunder"
	add_part(_player)
	_rng.seed = hash(seed_value) ^ get_instance_id()
	_wait = _next_wait() * 0.5

func _update_params() -> void:
	set_param(&"color", flash_color)
	set_param(&"spread", flash_spread)
	set_param(&"flash", _flash_now())

func _next_wait() -> float:
	if interval.x <= 0.0 and interval.y <= 0.0:
		return INF
	return _rng.randf_range(minf(interval.x, interval.y), maxf(interval.x, interval.y))

## Strikes now, at [param x] across the rectangle (0..1; negative: anywhere).
func strike(x := -1.0) -> void:
	if not _flash_mat:
		return
	var r := get_effect_rect()
	var u := x if x >= 0.0 else _rng.randf_range(0.1, 0.9)
	_since = 0.0
	_flash_mat.set_shader_parameter("bolt_x", u)
	var top := Vector2(r.position.x + r.size.x * u, r.position.y)
	var depth := _rng.randf_range(minf(reach.x, reach.y), maxf(reach.x, reach.y))
	var bottom := top + Vector2(_rng.randf_range(-0.12, 0.12) * r.size.x, r.size.y * depth)
	if bolts and _bolt_root:
		for c in _bolt_root.get_children():
			c.queue_free()
		var main := bolt_points(top, bottom, _rng)
		_add_bolt(main, bolt_width)
		for i in forks:
			var from := main[_rng.randi_range(int(main.size() * 0.2), int(main.size() * 0.75))]
			var dir := (bottom - top).normalized().rotated(_rng.randf_range(0.35, 0.9) * (-1.0 if _rng.randf() < 0.5 else 1.0))
			var length := (bottom - top).length() * _rng.randf_range(0.15, 0.4)
			_add_bolt(bolt_points(from, from + dir * length, _rng, 4), bolt_width * 0.55)
	if thunder and not Engine.is_editor_hint():
		_thunder_in = _rng.randf_range(minf(thunder_delay.x, thunder_delay.y), maxf(thunder_delay.x, thunder_delay.y))
	struck.emit(bottom)

## A jagged line from [param a] to [param b] (midpoint displacement, [param levels] deep).
static func bolt_points(a: Vector2, b: Vector2, rng: RandomNumberGenerator, levels := 6) -> PackedVector2Array:
	var pts := PackedVector2Array([a, b])
	var jag := a.distance_to(b) * 0.22
	for l in levels:
		var next := PackedVector2Array()
		for i in pts.size() - 1:
			var p := pts[i]
			var q := pts[i + 1]
			var normal := (q - p).orthogonal().normalized()
			next.append(p)
			next.append((p + q) * 0.5 + normal * rng.randf_range(-jag, jag))
		next.append(pts[pts.size() - 1])
		pts = next
		jag *= 0.55
	return pts

func _add_bolt(pts: PackedVector2Array, width: float) -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.35))
	for pass_i in 2:
		var line := Line2D.new()
		line.points = pts
		line.width = width * (5.0 if pass_i == 0 else 1.0)
		line.width_curve = taper
		line.default_color = Color(bolt_color, 0.28) if pass_i == 0 else Color(1, 1, 1, 0.95)
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.material = add
		_bolt_root.add_child(line)

## The flash's brightness now: a double flicker, then a fading glow.
func _flash_now() -> float:
	var t := _since
	var f := 0.0
	if t < 0.06:
		f = 1.0
	elif t < 0.12:
		f = 0.25
	elif t < 0.2:
		f = 0.85
	else:
		f = 0.85 * exp(-(t - 0.2) * 6.0)
	return f * flash_strength

func _tick(delta: float) -> void:
	if not _flash_mat:
		return
	_since += delta
	_wait -= delta
	if _wait <= 0.0:
		_wait = _next_wait()
		if get_strength() > 0.0:
			strike()
	var f := _flash_now()
	_flash_mat.set_shader_parameter("flash", f)
	if _bolt_root:
		_bolt_root.visible = _since < 0.32
		_bolt_root.modulate.a = clampf(f / maxf(flash_strength, 0.01) * 1.2, 0.0, 1.0) * get_strength()
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0 and _player and thunder:
			_player.stream = thunder
			_player.volume_db = thunder_volume_db + linear_to_db(maxf(get_strength(), 0.001))
			_player.play()

func _strength_changed(value: float) -> void:
	if _bolt_root and value <= 0.0005:
		_bolt_root.visible = false
