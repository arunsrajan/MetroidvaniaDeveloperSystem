@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/creatures.svg")
class_name MDSCreatures
extends MDSEnvironmentEffect
## A background of living things, made for boss rooms: one kind of creature at a time, many of
## them, each glowing and carrying its own light, which lights their habitat behind them as they
## move. Twenty kinds ([member creature]): bees and wasps around their hive, lumaflies, moths and
## butterflies, dragonflies, a flock of small birds, crows circling, bats, firebirds, spiders
## hanging on silk and crawling, beetles, centipedes, snails leaving glowing trails, crabs, jellyfish,
## glowfish, eels, owls watching from their perches, worms coming up out of the earth.
##
## Drawn soft and out of focus, the far ones smaller and blurrier. Being a background, nothing in
## it collides or hurts: the fight goes on in front of it. It watches the player (the nodes of
## [member MDSEnvironmentEffect.affect_groups]) all the same:
## - the faster the player moves, the more stirred up they get ([member activity]): flocks
##   scatter, spiders climb their threads, beetles run, snails stop, worms come up;
## - a sudden jolt (a jump, a dash, a hit) startles them; [method startle] does it from code;
## - those near the player on screen glow brighter ([member proximity_glow]);
## - the game can keep them stirred with [member excitement] (a boss's second phase).
##
## Used as the background of a room, an area's boss rooms or the world's (the "Animated bg"
## fields take a creature id, like [code]bats[/code], or a style and a creature:
## [code]blood_moon, bats[/code]), their light takes the area's color ([member area_tint]).

enum Creature { BEES, WASPS, LUMAFLIES, MOTHS, BUTTERFLIES, DRAGONFLIES, SONGBIRDS, CROWS, BATS, FIREBIRDS, SPIDERS, BEETLES, CENTIPEDES, SNAILS, CRABS, JELLYFISH, GLOWFISH, EELS, OWLS, WORMS }
## Ids of the creatures (as the background fields write them), in [enum Creature] order.
const CREATURE_IDS: PackedStringArray = ["bees", "wasps", "lumaflies", "moths", "butterflies", "dragonflies", "songbirds", "crows", "bats", "firebirds", "spiders", "beetles", "centipedes", "snails", "crabs", "jellyfish", "glowfish", "eels", "owls", "worms"]
const CREATURE_NAMES: PackedStringArray = ["Bees", "Wasps", "Lumaflies", "Moths", "Butterflies", "Dragonflies", "Small birds", "Crows", "Bats", "Firebirds", "Spiders", "Beetles", "Centipedes", "Snails", "Crabs", "Jellyfish", "Glowfish", "Eels", "Owls", "Worms"]
const CREATURE_INFO: PackedStringArray = [
	"Bees with glowing stripes swarming around their hive, the honeycomb lit amber where they pass",
	"Wasps darting about a dark nest, closing in on the player when it gets busy",
	"Lumaflies drifting through a night wood, their lanterns blinking on and off",
	"Moths fluttering in a forest; when the player stands still they come to it, like to a flame",
	"Butterflies with glowing wing edges wandering over a marsh, scattering from the player",
	"Dragonflies hovering over the reeds and darting off, glowing along their tails",
	"A flock of small birds wheeling across a dusk sky, warm light on their breasts",
	"Crows circling slowly against a grey sky, red eyes glinting",
	"Bats flitting about a cave, eyes glowing violet, scattering as the player moves",
	"Firebirds sweeping across a red sky, trailing tails of flame",
	"Spiders lowering themselves on silk and crawling over webbed rock; they climb away when the player is busy",
	"Beetles with glowing shells crawling over the cave wall, running when the player moves",
	"Centipedes winding through the earth, their segments glowing",
	"Snails gliding over damp rock, leaving glowing trails; they stop when the player is near",
	"Crabs scuttling sideways over the seabed, claws glowing",
	"Jellyfish pulsing up through deep water, lighting it blue",
	"A school of glowfish turning together in the deep, splitting around the player",
	"Eels winding slowly through dark water, spots glowing along them",
	"Owls watching from their perches, glowing eyes following the player, blinking",
	"Worms rising out of the earth in glowing arcs and diving back; more come up the more the player stomps about",
]
## The places they live in, drawn behind them and lit by them.
enum Habitat { HIVE, WEB_CAVE, FOREST, SKY, CAVE, DEEP_WATER, EARTH, MARSH }
const MAX_COUNT := 32

enum Motion { SWARM, FLUTTER, DART, FLOCK, CIRCLE, ERRATIC, CRAWL, SCUTTLE, SCHOOL, SINUOUS, PULSE, PERCH, BURROW }
## How each kind moves, in [enum Creature] order.
const MOTIONS: Array[int] = [Motion.SWARM, Motion.SWARM, Motion.SWARM, Motion.FLUTTER, Motion.FLUTTER, Motion.DART, Motion.FLOCK, Motion.CIRCLE, Motion.ERRATIC, Motion.FLOCK, Motion.CRAWL, Motion.CRAWL, Motion.CRAWL, Motion.CRAWL, Motion.SCUTTLE, Motion.PULSE, Motion.SCHOOL, Motion.SINUOUS, Motion.PERCH, Motion.BURROW]
## Seen from above, turning to where they go.
const TOP_VIEW: Array[int] = [Creature.MOTHS, Creature.BUTTERFLIES, Creature.DRAGONFLIES, Creature.SPIDERS, Creature.BEETLES, Creature.CENTIPEDES, Creature.SNAILS]
## Seen from the front, upright.
const FRONT_VIEW: Array[int] = [Creature.BATS, Creature.CRABS, Creature.JELLYFISH, Creature.OWLS, Creature.WORMS]

## The kind: picking one gives the background its colors, habitat, numbers and pace.
@export var creature: Creature = Creature.BEES:
	set(v):
		if v == creature:
			return
		creature = v
		apply_look(v)
		_spawned = false
		_changed()
## How many (up to 32).
@export_range(1, 32) var count := 26:
	set(v):
		count = clampi(v, 1, MAX_COUNT)
		_spawned = false
		_changed()
@export_group("Look")
## Their light, and the parts of them that glow.
@export var glow_color := Color("#ffb43a"):
	set(v):
		glow_color = v
		_changed()
## Their bodies (dark: silhouettes lit by their own glow).
@export var body_color := Color("#1e1408"):
	set(v):
		body_color = v
		_changed()
## Where they live, drawn behind them.
@export var habitat: Habitat = Habitat.HIVE:
	set(v):
		habitat = v
		_changed()
## The habitat's dark, and its features.
@export var back_color_a := Color("#170c03"):
	set(v):
		back_color_a = v
		_changed()
@export var back_color_b := Color("#6b3d0c"):
	set(v):
		back_color_b = v
		_changed()
## How much of the habitat is drawn behind them (0: only the creatures, over another background).
@export_range(0.0, 1.0) var backdrop := 1.0:
	set(v):
		backdrop = v
		_changed()
## Size of one (a share of the view's height).
@export_range(0.005, 0.25, 0.001) var creature_size := 0.028:
	set(v):
		creature_size = v
		_changed()
## How out of focus they are.
@export_range(0.0, 1.0) var blur := 0.5:
	set(v):
		blur = v
		_changed()
@export_group("Light")
## How far each one's light reaches (a share of the view's height).
@export_range(0.0, 0.8, 0.005) var light_radius := 0.14:
	set(v):
		light_radius = v
		_changed()
@export_range(0.0, 3.0) var light_strength := 1.0:
	set(v):
		light_strength = v
		_changed()
## Light on the habitat with no creature near.
@export_range(0.0, 1.0) var ambient := 0.3:
	set(v):
		ambient = v
		_changed()
## The color of the area this background is in ([MDSWorldGame] and the Room view set it).
## Transparent: none.
@export var area_color := Color(0, 0, 0, 0):
	set(v):
		area_color = v
		_changed()
## How much their light takes the area's color.
@export_range(0.0, 1.0) var area_tint := 0.35:
	set(v):
		area_tint = v
		_changed()
@export_group("Behavior")
## How fast they go.
@export_range(0.0, 4.0) var speed := 1.0
## How much the player's moving about stirs them up (0: they ignore it).
@export_range(0.0, 1.0) var reactivity := 0.8
## How much brighter those near the player glow.
@export_range(0.0, 2.0) var proximity_glow := 0.6
## Kept stirred up by the game (0..1), whatever the player does: a boss's second phase.
@export_range(0.0, 1.0) var excitement := 0.0
## How much it moves with the camera: 0 stays on the screen (far away), 1 moves with the room.
@export var scroll_scale := Vector2(0.04, 0.02)
## Cover the whole view and follow the camera (in the game). Off: only its rectangle.
@export var follow_camera := true

## Colors, habitat, numbers and pace of each kind: id -> {property: value}.
const LOOKS := {
	"bees": {"glow_color": Color("#ffb43a"), "body_color": Color("#1e1408"), "back_color_a": Color("#170c03"), "back_color_b": Color("#6b3d0c"), "habitat": Habitat.HIVE, "count": 26, "creature_size": 0.028, "light_radius": 0.14, "light_strength": 1.0, "ambient": 0.3},
	"wasps": {"glow_color": Color("#ff6a2a"), "body_color": Color("#1a0d06"), "back_color_a": Color("#140804"), "back_color_b": Color("#5a2a10"), "habitat": Habitat.HIVE, "count": 18, "creature_size": 0.032, "light_radius": 0.13, "light_strength": 1.0, "ambient": 0.25},
	"lumaflies": {"glow_color": Color("#d8ff7a"), "body_color": Color("#20261a"), "back_color_a": Color("#050c0a"), "back_color_b": Color("#1d3a2c"), "habitat": Habitat.FOREST, "count": 24, "creature_size": 0.022, "light_radius": 0.16, "light_strength": 1.1, "ambient": 0.25},
	"moths": {"glow_color": Color("#f2e6c8"), "body_color": Color("#3a3428"), "back_color_a": Color("#0a0a10"), "back_color_b": Color("#2e2c3c"), "habitat": Habitat.FOREST, "count": 14, "creature_size": 0.04, "light_radius": 0.15, "light_strength": 0.9, "ambient": 0.3},
	"butterflies": {"glow_color": Color("#7fd6ff"), "body_color": Color("#1a1a2a"), "back_color_a": Color("#0b1018"), "back_color_b": Color("#2c4a46"), "habitat": Habitat.MARSH, "count": 12, "creature_size": 0.045, "light_radius": 0.14, "light_strength": 0.9, "ambient": 0.35},
	"dragonflies": {"glow_color": Color("#6affe0"), "body_color": Color("#10241e"), "back_color_a": Color("#071016"), "back_color_b": Color("#284a52"), "habitat": Habitat.MARSH, "count": 8, "creature_size": 0.055, "light_radius": 0.12, "light_strength": 1.0, "ambient": 0.35},
	"songbirds": {"glow_color": Color("#ffd890"), "body_color": Color("#241c14"), "back_color_a": Color("#2a1a2e"), "back_color_b": Color("#8a5a6a"), "habitat": Habitat.SKY, "count": 16, "creature_size": 0.04, "light_radius": 0.12, "light_strength": 0.8, "ambient": 0.45},
	"crows": {"glow_color": Color("#ff3a2a"), "body_color": Color("#08080c"), "back_color_a": Color("#1a1820"), "back_color_b": Color("#4a4a5a"), "habitat": Habitat.SKY, "count": 7, "creature_size": 0.065, "light_radius": 0.1, "light_strength": 0.8, "ambient": 0.45},
	"bats": {"glow_color": Color("#b07aff"), "body_color": Color("#2e2440"), "back_color_a": Color("#07050c"), "back_color_b": Color("#2a2236"), "habitat": Habitat.CAVE, "count": 14, "creature_size": 0.055, "light_radius": 0.12, "light_strength": 1.0, "ambient": 0.3},
	"firebirds": {"glow_color": Color("#ff8a2a"), "body_color": Color("#3a1206"), "back_color_a": Color("#1a0606"), "back_color_b": Color("#6a1e0a"), "habitat": Habitat.SKY, "count": 6, "creature_size": 0.055, "light_radius": 0.2, "light_strength": 1.3, "ambient": 0.25},
	"spiders": {"glow_color": Color("#c06aff"), "body_color": Color("#3a2c48"), "back_color_a": Color("#08060c"), "back_color_b": Color("#2a2434"), "habitat": Habitat.WEB_CAVE, "count": 9, "creature_size": 0.06, "light_radius": 0.12, "light_strength": 0.9, "ambient": 0.25},
	"beetles": {"glow_color": Color("#5aff9a"), "body_color": Color("#1c3024"), "back_color_a": Color("#0a0a08"), "back_color_b": Color("#2c2a22"), "habitat": Habitat.CAVE, "count": 10, "creature_size": 0.035, "light_radius": 0.12, "light_strength": 0.9, "ambient": 0.25},
	"centipedes": {"glow_color": Color("#ff5ad8"), "body_color": Color("#2e1a2a"), "back_color_a": Color("#0c0806"), "back_color_b": Color("#3a2a1c"), "habitat": Habitat.EARTH, "count": 5, "creature_size": 0.05, "light_radius": 0.14, "light_strength": 1.0, "ambient": 0.25},
	"snails": {"glow_color": Color("#9affea"), "body_color": Color("#1a1e20"), "back_color_a": Color("#080c0c"), "back_color_b": Color("#24363a"), "habitat": Habitat.CAVE, "count": 7, "creature_size": 0.04, "light_radius": 0.13, "light_strength": 0.9, "ambient": 0.3},
	"crabs": {"glow_color": Color("#ff8a6a"), "body_color": Color("#6a2a1a"), "back_color_a": Color("#04101a"), "back_color_b": Color("#1a4050"), "habitat": Habitat.DEEP_WATER, "count": 8, "creature_size": 0.07, "light_radius": 0.15, "light_strength": 1.1, "ambient": 0.35},
	"jellyfish": {"glow_color": Color("#7ab8ff"), "body_color": Color("#1a2a4a"), "back_color_a": Color("#020812"), "back_color_b": Color("#0e3050"), "habitat": Habitat.DEEP_WATER, "count": 9, "creature_size": 0.075, "light_radius": 0.2, "light_strength": 1.2, "ambient": 0.3},
	"glowfish": {"glow_color": Color("#5affd0"), "body_color": Color("#0a2026"), "back_color_a": Color("#020a12"), "back_color_b": Color("#0c3a4a"), "habitat": Habitat.DEEP_WATER, "count": 24, "creature_size": 0.04, "light_radius": 0.11, "light_strength": 0.9, "ambient": 0.3},
	"eels": {"glow_color": Color("#a6ff5a"), "body_color": Color("#0a1408"), "back_color_a": Color("#020806"), "back_color_b": Color("#12302a"), "habitat": Habitat.DEEP_WATER, "count": 5, "creature_size": 0.085, "light_radius": 0.16, "light_strength": 1.0, "ambient": 0.25},
	"owls": {"glow_color": Color("#ffd23a"), "body_color": Color("#1a140e"), "back_color_a": Color("#060810"), "back_color_b": Color("#1e2a3a"), "habitat": Habitat.FOREST, "count": 5, "creature_size": 0.075, "light_radius": 0.12, "light_strength": 0.9, "ambient": 0.3},
	"worms": {"glow_color": Color("#ff9ad0"), "body_color": Color("#2a1418"), "back_color_a": Color("#0e0806"), "back_color_b": Color("#4a2e1e"), "habitat": Habitat.EARTH, "count": 5, "creature_size": 0.06, "light_radius": 0.16, "light_strength": 1.0, "ambient": 0.3},
}
## The settings a kind sets.
const LOOK_KEYS: PackedStringArray = ["glow_color", "body_color", "back_color_a", "back_color_b", "habitat", "count", "creature_size", "light_radius", "light_strength", "ambient"]

## How stirred up they are now (0..1), from the player's moving about, jolts and
## [member excitement].
var activity := 0.0

var _mat: ShaderMaterial
var _quad: Polygon2D
var _spawned := false
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _time := 0.0
var _half := Vector2(0.889, 0.5)
var _drift := Vector2.ZERO
# Per creature: position and velocity (view heights from the view's middle), animation phase,
# depth, heading, glow, extra (thread, trail, progress, blink), timer, rest, aim, mode, facing.
var _p := PackedVector2Array()
var _v := PackedVector2Array()
var _ph := PackedFloat32Array()
var _dep := PackedFloat32Array()
var _ang := PackedFloat32Array()
var _gl := PackedFloat32Array()
var _ex := PackedFloat32Array()
var _t := PackedFloat32Array()
var _rest := PackedFloat32Array()
var _aim := PackedVector2Array()
var _mode := PackedInt32Array()
var _face := PackedFloat32Array()
var _order := PackedInt32Array()
# The player.
var _has_player := false
var _player := Vector2.ZERO ## on the view, like the creatures
var _player_last := Vector2.ZERO
var _player_seen := false
var _player_vel := Vector2.ZERO
var _jolt := 0.0
var _scatter := Vector2.ZERO
var _scatter_left := 0.0

func _init() -> void:
	z_index = -105
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.02

# The kind and its settings are also saved together, as "look" (see MDSAnimatedBackground).
func _get_property_list() -> Array[Dictionary]:
	return [{"name": "look", "type": TYPE_DICTIONARY, "usage": PROPERTY_USAGE_STORAGE}]

func _get(property: StringName) -> Variant:
	if property == &"look":
		var d: Dictionary = {"creature": int(creature)}
		for k in LOOK_KEYS:
			d[k] = get(k)
		return d
	return null

func _set(property: StringName, value: Variant) -> bool:
	if property != &"look" or not value is Dictionary:
		return false
	if value.has("creature"):
		creature = int(value.creature) as Creature
	for k in value:
		if LOOK_KEYS.has(str(k)):
			set(str(k), value[k])
	return true

func get_effect_id() -> String:
	return "creatures"

## Makes them [param id] (see [constant CREATURE_IDS]). Returns false for an unknown one.
func use_creature(id: String) -> bool:
	var i := CREATURE_IDS.find(id.strip_edges().to_lower().replace(" ", "_"))
	if i < 0:
		return false
	creature = i as Creature
	return true

## Sets the colors, habitat, numbers and pace of [param c] (see [constant LOOKS]).
func apply_look(c: Creature) -> void:
	var look: Dictionary = LOOKS.get(CREATURE_IDS[c], {})
	for k in look:
		set(k, look[k])

## Startles them, as if something struck at [param at] (global; INF: nowhere in particular):
## they scatter from it and stay stirred up for a while.
func startle(at := Vector2.INF, strength := 1.0) -> void:
	_jolt = maxf(_jolt, clampf(strength, 0.0, 1.0))
	if at != Vector2.INF:
		_scatter = to_view(at)
		_scatter_left = clampf(strength, 0.0, 1.0)

## Where the creatures are on the view (its middle at (0, 0), its height 1), for tests and tools.
func creature_positions() -> PackedVector2Array:
	return _p.duplicate()

## The light color now: [member glow_color] taking the area's color.
func light_color() -> Color:
	return glow_color.lerp(Color(area_color.r, area_color.g, area_color.b, glow_color.a), area_tint) if area_color.a > 0.0 else glow_color

func _build() -> void:
	_mat = add_quad(shader("creatures"), get_effect_rect())
	_quad = _quads[_quads.size() - 1] as Polygon2D
	_tick(0.0)

func _update_params() -> void:
	if not _mat:
		return
	_mat.set_shader_parameter("creature", int(creature))
	_mat.set_shader_parameter("habitat", int(habitat))
	_mat.set_shader_parameter("glow_color", light_color())
	_mat.set_shader_parameter("body_color", body_color)
	_mat.set_shader_parameter("back_color_a", back_color_a)
	_mat.set_shader_parameter("back_color_b", back_color_b)
	_mat.set_shader_parameter("backdrop", backdrop)
	_mat.set_shader_parameter("blur", blur)
	_mat.set_shader_parameter("light_radius", light_radius)
	_mat.set_shader_parameter("light_strength", light_strength)
	_mat.set_shader_parameter("ambient", ambient)

# --- Where things are ---------------------------------------------------------------------------

## What the camera sees, in this node's coordinates (its rectangle when there is no viewport).
func view_rect() -> Rect2:
	var vp := get_viewport()
	if not vp or not is_inside_tree():
		return get_effect_rect()
	var inv := get_global_transform_with_canvas().affine_inverse()
	var seen := vp.get_visible_rect()
	var a := inv * seen.position
	var b := inv * seen.end
	return Rect2(a, b - a).abs()

## Where the global point [param at] is on the view, in the creatures' units.
func to_view(at: Vector2) -> Vector2:
	var view := view_rect()
	var local := global_transform.affine_inverse() * at if is_inside_tree() else at
	var uv := (local - view.position) / Vector2(maxf(view.size.x, 1.0), maxf(view.size.y, 1.0))
	return (uv - Vector2(0.5, 0.5)) * Vector2(view.size.x / maxf(view.size.y, 1.0), 1.0) + _drift

# --- Running ------------------------------------------------------------------------------------

func _tick(delta: float) -> void:
	if not _mat or not _quad:
		return
	var view := view_rect()
	var following := follow_camera and not Engine.is_editor_hint()
	var cover := view.grow(4.0) if following else get_effect_rect()
	var poly := PackedVector2Array([cover.position, Vector2(cover.end.x, cover.position.y), cover.end, Vector2(cover.position.x, cover.end.y)])
	if _quad.polygon != poly:
		_quad.polygon = poly
	_mat.set_shader_parameter("rect_origin", cover.position)
	_mat.set_shader_parameter("rect_size", cover.size)
	_mat.set_shader_parameter("edge_fade", 0.0 if following else 24.0)
	_mat.set_shader_parameter("view_rect", Vector4(view.position.x, view.position.y, view.size.x, view.size.y))
	_half = Vector2(view.size.x / maxf(view.size.y, 1.0) * 0.5, 0.5)
	_drift = (view.get_center() - get_effect_rect().get_center()) * scroll_scale / 648.0
	_mat.set_shader_parameter("drift", _drift)
	if not _spawned or _p.size() != count:
		_spawn()
	step(delta)
	_send()

## Moves them on by [param delta] seconds (the effect does it every frame).
func step(delta: float) -> void:
	_sense(delta)
	var dt := minf(delta, 0.05) * speed
	_time += dt
	match MOTIONS[creature]:
		Motion.SWARM:
			_move_swarm(dt)
		Motion.FLUTTER:
			_move_flutter(dt, false)
		Motion.ERRATIC:
			_move_flutter(dt, true)
		Motion.DART:
			_move_dart(dt)
		Motion.FLOCK:
			_move_flock(dt, 0.5 if creature == Creature.FIREBIRDS else 0.38, 0.16 if creature == Creature.FIREBIRDS else 0.12)
		Motion.SCHOOL:
			_move_flock(dt, 0.22, 0.08)
		Motion.CIRCLE:
			_move_circle(dt)
		Motion.CRAWL:
			_move_crawl(dt)
		Motion.SCUTTLE:
			_move_scuttle(dt)
		Motion.SINUOUS:
			_move_sinuous(dt)
		Motion.PULSE:
			_move_pulse(dt)
		Motion.PERCH:
			_move_perch(dt)
		Motion.BURROW:
			_move_burrow(dt)
	_glow(dt)

func _spawn() -> void:
	_spawned = true
	var n := clampi(count, 1, MAX_COUNT)
	_rng.seed = hash("mds_creatures_%d_%d" % [seed_value, int(creature)])
	_noise.seed = int(_rng.seed % 100000)
	_p.resize(n)
	_v.resize(n)
	_aim.resize(n)
	_ph.resize(n)
	_dep.resize(n)
	_ang.resize(n)
	_gl.resize(n)
	_ex.resize(n)
	_t.resize(n)
	_rest.resize(n)
	_face.resize(n)
	_mode.resize(n)
	for i in n:
		_dep[i] = _rng.randf_range(0.0, 0.85)
		_p[i] = Vector2(_rng.randf_range(-_half.x, _half.x) * 0.9, _rng.randf_range(-0.42, 0.42))
		_v[i] = Vector2.from_angle(_rng.randf() * TAU) * 0.05
		_ph[i] = _rng.randf() * TAU
		_ang[i] = _rng.randf() * TAU
		_gl[i] = 1.0
		_ex[i] = 0.0
		_t[i] = _rng.randf_range(0.2, 3.0)
		_rest[i] = 0.0
		_aim[i] = _p[i]
		_mode[i] = 0
		_face[i] = 1.0 if _rng.randf() < 0.5 else -1.0
		match MOTIONS[creature]:
			Motion.CRAWL:
				if creature == Creature.SPIDERS and i % 5 < 2:
					# Hanging on silk from the top.
					_mode[i] = 1
					_aim[i] = Vector2(_p[i].x, -_half.y - 0.05)
					_ex[i] = _rng.randf_range(0.1, 0.5)
			Motion.SCUTTLE:
				_p[i].y = _ground(i)
				# Its sideways speed.
				_aim[i] = Vector2(_rng.randf_range(-0.12, 0.12), 0.0)
			Motion.PERCH:
				var x := lerpf(-_half.x * 0.8, _half.x * 0.8, (i + 0.5) / n) + _rng.randf_range(-0.05, 0.05)
				_p[i] = Vector2(x, _rng.randf_range(-0.12, 0.25))
				_aim[i] = _p[i]
				_dep[i] = _rng.randf_range(0.0, 0.55)
			Motion.BURROW:
				_p[i].y = _ground(i)
				_ex[i] = -1.0
				_t[i] = _rng.randf_range(0.2, 3.5)
	var idx: Array = range(n)
	idx.sort_custom(func(a: int, b: int) -> bool: return _dep[a] > _dep[b])
	_order = PackedInt32Array(idx)

## A steady random 0..1 per creature.
func _h(i: int, salt := 0) -> float:
	return fposmod(sin(i * 12.9898 + salt * 78.233) * 43758.5453, 1.0)

## Smooth noise -1..1 per creature, changing over time.
func _n(i: int, axis: int) -> float:
	return _noise.get_noise_2d(i * 37.0 + axis * 101.0, _time * 40.0)

## Where the floor is for creature [param i] (the far ones a little higher).
func _ground(i: int) -> float:
	return 0.44 - 0.1 * _dep[i]

## How stirred they are, and how much they fear the player.
func _agitation() -> float:
	return 1.0 + activity * reactivity * 1.5

func _fear() -> float:
	return activity * reactivity

## Away from the player (and a startle), stronger the nearer it is, within [param radius].
func _flee(i: int, radius: float) -> Vector2:
	var out := Vector2.ZERO
	if _has_player:
		var d := _p[i] - _player
		var l := d.length()
		if l < radius and l > 0.0001:
			out += d / l * (1.0 - l / radius)
	if _scatter_left > 0.0:
		var d2 := _p[i] - _scatter
		var l2 := d2.length()
		if l2 > 0.0001:
			out += d2 / l2 * _scatter_left * 1.5
	return out

## Back toward the middle when one strays past the view's edges.
func _inward(i: int) -> Vector2:
	var lim := _half + Vector2(0.06, 0.06)
	var k := Vector2(_p[i].x / lim.x, _p[i].y / lim.y).length()
	return -_p[i] * maxf(0.0, k - 0.8) * 3.0

func _sense(delta: float) -> void:
	var bodies := bodies_inside(2000.0)
	_has_player = not bodies.is_empty()
	var want := 0.0
	if _has_player:
		var g := bodies[0].global_position
		if _player_seen and delta > 0.0:
			var vel := (g - _player_last) / delta
			var jolt := (vel - _player_vel).length() / delta
			_player_vel = vel
			want = clampf(vel.length() / 450.0, 0.0, 1.0) * 0.8
			if jolt > 4000.0:
				_jolt = maxf(_jolt, 0.7)
		_player_last = g
		_player_seen = true
		_player = to_view(g)
	else:
		_player_seen = false
	want = maxf(maxf(want, _jolt), excitement)
	activity = move_toward(activity, want, delta * (3.0 if want > activity else 0.4))
	_jolt = move_toward(_jolt, 0.0, delta * 0.8)
	_scatter_left = move_toward(_scatter_left, 0.0, delta * 0.7)

func _glow(dt: float) -> void:
	var stir := 1.0 + activity * reactivity * 0.5
	for i in _p.size():
		var g := 0.85 + 0.15 * sin(_time * (1.5 + _h(i, 3)) + i * 1.7)
		match creature:
			Creature.LUMAFLIES:
				g = 0.25 + 0.75 * clampf(sin(_time * (0.7 + 0.6 * _h(i, 3)) + i * 2.3) * 1.4, 0.0, 1.0)
			Creature.JELLYFISH:
				g = 0.65 + 0.35 * sin(_ph[i])
			Creature.FIREBIRDS:
				g = 0.85 + 0.15 * sin(_time * 13.0 + i)
			Creature.SNAILS:
				g = lerpf(g, 0.35, clampf(_fear() * 1.5, 0.0, 1.0))
			Creature.OWLS:
				g = 0.8 + 0.6 * _fear()
			Creature.WORMS:
				g = 0.9 if _ex[i] >= 0.0 else 0.0
		var near := 0.0
		if _has_player:
			near = exp(-_p[i].distance_squared_to(_player) / 0.02)
		_gl[i] = g * stir * (1.0 + proximity_glow * near)

func _move_swarm(dt: float) -> void:
	var n := _p.size()
	var nc := maxi(1, n / 9)
	var ag := _agitation()
	for i in n:
		var k := i % nc
		var c := Vector2(sin(_time * 0.11 * (k + 1) + k * 2.1) * _half.x * 0.6, sin(_time * 0.09 * (k + 1) + k * 1.3) * 0.22 - 0.05)
		if creature == Creature.WASPS and _has_player:
			c = c.lerp(_player + Vector2(0.0, -0.12), _fear() * 0.6)
		_ang[i] += dt * (0.9 + 0.8 * _h(i)) * ag * (1.0 if i % 2 == 0 else -1.0)
		var r := (0.06 + 0.14 * _h(i, 2)) * (1.0 + _fear() * 0.6)
		var target := c + Vector2(cos(_ang[i]), sin(_ang[i]) * 0.6) * r + Vector2(_n(i, 0), _n(i, 1)) * 0.05 * ag
		var want := (target - _p[i]) * 3.0
		if creature != Creature.WASPS:
			want += _flee(i, 0.3) * 0.8
		_v[i] = _v[i].lerp(want, 1.0 - exp(-4.0 * dt))
		_p[i] += _v[i] * dt
		_ph[i] += dt * 45.0
		_steer_face(i)

func _move_flutter(dt: float, erratic: bool) -> void:
	var ag := _agitation()
	var fear := _fear()
	for i in _p.size():
		_ang[i] += _n(i, 0) * (6.0 if erratic else 2.5) * dt * ag
		var steer := _inward(i) * 2.0
		if creature == Creature.MOTHS and _has_player:
			# To the player like to a flame while it is still; away when it isn't.
			steer += (_player + Vector2(0.0, -0.08) - _p[i]) * (1.0 - fear) * 0.8 + _flee(i, 0.35) * fear * 2.0
		else:
			steer += _flee(i, 0.35 if erratic else 0.25) * (0.3 + fear * 2.0)
		if steer.length() > 0.0001:
			_ang[i] = lerp_angle(_ang[i], steer.angle(), 1.0 - exp(-steer.length() * 3.0 * dt))
		var spd := ((0.18 if erratic else 0.08) + 0.05 * _h(i)) * ag
		_v[i] = Vector2.from_angle(_ang[i]) * spd
		_p[i] += _v[i] * dt
		_ph[i] += dt * (16.0 if erratic else (14.0 if creature == Creature.MOTHS else 7.0)) * ag
		_steer_face(i)

func _random_point() -> Vector2:
	return Vector2(_rng.randf_range(-_half.x, _half.x) * 0.85, _rng.randf_range(-0.4, 0.35))

func _move_dart(dt: float) -> void:
	var ag := _agitation()
	for i in _p.size():
		if _mode[i] == 0:
			_t[i] -= dt * ag
			var hover := _aim[i] + Vector2(_n(i, 0), _n(i, 1)) * 0.012
			_v[i] = _v[i].lerp((hover - _p[i]) * 6.0, 1.0 - exp(-8.0 * dt))
			if _t[i] <= 0.0:
				_mode[i] = 1
				var best := _random_point()
				if _has_player and _fear() > 0.3:
					for k in 3:
						var c := _random_point()
						if c.distance_to(_player) > best.distance_to(_player):
							best = c
				_aim[i] = best
		else:
			var to := _aim[i] - _p[i]
			_v[i] = _v[i].lerp(to.normalized() * 0.9 * ag, 1.0 - exp(-10.0 * dt))
			if to.length() < 0.03:
				_mode[i] = 0
				_t[i] = _rng.randf_range(0.6, 2.2)
		_p[i] += _v[i] * dt
		if _v[i].length() > 0.02:
			_ang[i] = lerp_angle(_ang[i], _v[i].angle(), 1.0 - exp(-12.0 * dt))
		_ph[i] += dt * 60.0

func _move_flock(dt: float, max_speed: float, sep_dist: float) -> void:
	var n := _p.size()
	var centre := Vector2.ZERO
	var avg := Vector2.ZERO
	for i in n:
		centre += _p[i]
		avg += _v[i]
	centre /= n
	avg /= n
	var fish := MOTIONS[creature] == Motion.SCHOOL
	var goal := Vector2(sin(_time * (0.05 if fish else 0.07)) * _half.x * 0.7, sin(_time * 0.11 + 1.3) * 0.25)
	var ag := _agitation()
	var fear := _fear()
	for i in n:
		var acc := (centre - _p[i]) * 0.45 + (avg - _v[i]) * 0.9 + (goal - _p[i]) * 0.4
		for j in n:
			if j != i:
				var d := _p[i] - _p[j]
				var l := d.length()
				if l < sep_dist:
					# Keep their distance: each its own place in the flock.
					acc += (d / l if l > 0.0001 else Vector2.from_angle(i * 2.4)) * (1.0 - l / sep_dist) * 3.0
		acc += _flee(i, 0.4) * (0.3 + fear * 3.0) + _inward(i) * 2.0
		_v[i] += acc * dt * (1.4 if fish else 2.0)
		var spd := _v[i].length()
		var top := max_speed * ag
		var low := top * 0.35
		if spd > top:
			_v[i] *= top / spd
		elif spd < low and spd > 0.0001:
			_v[i] *= low / spd
		_p[i] += _v[i] * dt
		_ph[i] += dt * ((6.0 + _v[i].length() * 15.0) if fish else (9.0 + _v[i].length() * 12.0))
		_steer_face(i)

func _move_circle(dt: float) -> void:
	var ag := _agitation()
	var c := Vector2(sin(_time * 0.05) * _half.x * 0.3, -0.12 + sin(_time * 0.07) * 0.06)
	for i in _p.size():
		_ang[i] += dt * (0.25 + 0.15 * _h(i)) * (1.0 if i % 2 == 0 else -1.0) * ag
		var r := (0.18 + 0.3 * _h(i, 1)) * (1.0 + _fear() * 0.5)
		var target := c + Vector2(cos(_ang[i]) * r * 1.6, sin(_ang[i]) * r * 0.55)
		_v[i] = _v[i].lerp((target - _p[i]) * 2.0 + _flee(i, 0.3) * _fear(), 1.0 - exp(-3.0 * dt))
		_p[i] += _v[i] * dt
		# Flapping, then gliding.
		var flapping := fmod(_time + _h(i) * 5.0, 4.0) < 1.6
		_ph[i] += dt * (6.0 if flapping else 0.4) * ag
		_steer_face(i)

func _move_crawl(dt: float) -> void:
	var fear := _fear()
	for i in _p.size():
		if creature == Creature.SPIDERS and _mode[i] == 1:
			_move_hang(i, dt)
			continue
		var base := 0.05
		match creature:
			Creature.BEETLES:
				base = 0.07
			Creature.CENTIPEDES:
				base = 0.09
			Creature.SNAILS:
				base = 0.012
		var spd := base * (1.0 - clampf(fear * 1.5, 0.0, 1.0)) if creature == Creature.SNAILS else base * (1.0 + fear * 3.0)
		if _rest[i] > 0.0:
			_rest[i] -= dt
			if fear < 0.4 or creature == Creature.SNAILS:
				spd = 0.0
		elif _rng.randf() < dt * 0.15:
			_rest[i] = _rng.randf_range(0.5, 2.5)
		_ang[i] += _n(i, 0) * 1.5 * dt
		var steer := _inward(i) * 2.0
		if creature != Creature.SNAILS:
			steer += _flee(i, 0.35) * fear * 2.0
		if steer.length() > 0.0001:
			_ang[i] = lerp_angle(_ang[i], steer.angle(), 1.0 - exp(-steer.length() * 4.0 * dt))
		_v[i] = Vector2.from_angle(_ang[i]) * spd
		_p[i] += _v[i] * dt
		_ph[i] += dt * spd * 120.0
		if creature == Creature.SNAILS:
			_ex[i] = clampf(_ex[i] + (spd * dt * 25.0 if spd > 0.0 else -dt * 0.05), 0.0, 1.6)

## A spider on its thread: lowering itself while all is calm, climbing back up when it isn't.
func _move_hang(i: int, dt: float) -> void:
	var rest := 0.25 + 0.45 * _h(i, 4)
	var near := 0.0
	if _has_player:
		near = clampf(1.0 - absf(_player.x - _aim[i].x) / 0.3, 0.0, 1.0)
	var want := lerpf(rest, 0.04, clampf(_fear() * 1.5 + near * _fear(), 0.0, 1.0))
	var before := _ex[i]
	_ex[i] = move_toward(_ex[i], want, (0.06 if want > _ex[i] else 0.35) * dt * _agitation())
	_p[i] = Vector2(_aim[i].x + sin(_time * 0.6 + i) * 0.01 * _ex[i], _aim[i].y + _ex[i])
	_v[i] = Vector2(0.0, (_ex[i] - before) / maxf(dt, 0.0001))
	_ang[i] = PI * 0.5
	_ph[i] += dt * (absf(_ex[i] - before) / maxf(dt, 0.0001) * 60.0 + 0.5)

func _move_scuttle(dt: float) -> void:
	var ag := _agitation()
	for i in _p.size():
		_t[i] -= dt
		if _t[i] <= 0.0:
			_t[i] = _rng.randf_range(0.6, 2.5)
			# A pause, or off sideways: toward the middle more often from near an edge.
			var inward := -signf(_p[i].x) if absf(_p[i].x) > _half.x * 0.45 and _rng.randf() < 0.75 else (1.0 if _rng.randf() < 0.5 else -1.0)
			_aim[i].x = 0.0 if _rng.randf() < 0.35 else _rng.randf_range(0.05, 0.18) * inward
		var vx := _aim[i].x
		if _has_player and _fear() > 0.3:
			vx = signf(_p[i].x - _player.x + 0.0001) * 0.35 * ag
		if absf(_p[i].x) > _half.x - 0.06:
			# Back from the edge of the view.
			vx = -signf(_p[i].x) * maxf(absf(vx), 0.1)
		_v[i].x = lerpf(_v[i].x, vx, 1.0 - exp(-6.0 * dt))
		_v[i].y = 0.0
		_p[i].x += _v[i].x * dt
		_p[i].y = _ground(i) + sin(_time * 9.0 + i) * 0.002 * absf(_v[i].x) * 10.0
		_ph[i] += dt * (absf(_v[i].x) * 60.0 + 2.0)

func _move_sinuous(dt: float) -> void:
	var ag := _agitation()
	for i in _p.size():
		_ang[i] += _n(i, 0) * 0.8 * dt
		var steer := _inward(i) * 2.0 + _flee(i, 0.35) * (0.3 + _fear() * 2.0)
		if steer.length() > 0.0001:
			_ang[i] = lerp_angle(_ang[i], steer.angle(), 1.0 - exp(-steer.length() * 2.0 * dt))
		_v[i] = Vector2.from_angle(_ang[i]) * (0.05 + 0.02 * _h(i)) * ag
		_p[i] += _v[i] * dt
		_ph[i] += dt * (3.0 + _v[i].length() * 30.0)
		_steer_face(i)

func _move_pulse(dt: float) -> void:
	var ag := _agitation()
	for i in _p.size():
		var before := _ph[i]
		_ph[i] += dt * (1.4 + 0.6 * _h(i)) * ag
		if floorf(before / TAU) != floorf(_ph[i] / TAU):
			_v[i].y -= 0.12 * (1.0 + _fear())
		_v[i].y += 0.02 * dt
		_v[i].x += (_n(i, 0) * 0.02 + _flee(i, 0.3).x * 0.2 * _fear()) * dt * 10.0
		_v[i] *= exp(-1.2 * dt)
		_p[i] += _v[i] * dt
		if _p[i].y < -_half.y - 0.15:
			_p[i] = Vector2(_rng.randf_range(-_half.x, _half.x) * 0.9, _half.y + 0.15)
		if absf(_p[i].x) > _half.x + 0.1:
			_p[i].x = -signf(_p[i].x) * _half.x

func _move_perch(dt: float) -> void:
	for i in _p.size():
		var look := clampf((_player.x - _p[i].x) * 3.0, -1.0, 1.0) if _has_player else sin(_time * 0.2 + i * 1.3) * 0.6
		_ph[i] = lerpf(_ph[i] if absf(_ph[i]) <= 1.0 else 0.0, look, 1.0 - exp(-3.0 * dt))
		_t[i] -= dt * (1.0 + _fear() * 2.0)
		if _t[i] <= 0.0:
			_ex[i] = 1.0
			_t[i] = _rng.randf_range(2.0, 6.0)
		_ex[i] = move_toward(_ex[i], 0.0, dt * 7.0)
		_p[i] = _aim[i] + Vector2(0.0, sin(_time * 0.8 + i) * 0.003)
		_v[i] = Vector2.ZERO

func _move_burrow(dt: float) -> void:
	for i in _p.size():
		if _ex[i] < 0.0:
			# Underground: more come up the busier the player is.
			_t[i] -= dt * (1.0 + 4.0 * _fear())
			if _t[i] <= 0.0:
				_ex[i] = 0.0
				_p[i].x = _rng.randf_range(-_half.x, _half.x) * 0.85
				_face[i] = 1.0 if _rng.randf() < 0.5 else -1.0
		else:
			_ex[i] += dt / (2.2 + _h(i))
			if _ex[i] > 1.0:
				_ex[i] = -1.0
				_t[i] = _rng.randf_range(1.0, 4.0)
		_p[i].y = _ground(i)
		_ph[i] += dt * 3.0

## Faces the way it goes (side view), keeping its facing when it barely moves.
func _steer_face(i: int) -> void:
	if absf(_v[i].x) > 0.005:
		_face[i] = 1.0 if _v[i].x > 0.0 else -1.0

func _send() -> void:
	var n := _p.size()
	var pos := PackedVector4Array()
	var st := PackedVector4Array()
	pos.resize(MAX_COUNT)
	st.resize(MAX_COUNT)
	for k in mini(n, _order.size()):
		var i := _order[k]
		var sz := creature_size * lerpf(1.0, 0.45, _dep[i])
		var ang := 0.0
		var facing := 1.0
		if TOP_VIEW.has(creature):
			ang = _ang[i]
		elif FRONT_VIEW.has(creature):
			ang = clampf(_v[i].x * 2.0, -0.3, 0.3) if creature == Creature.BATS or creature == Creature.JELLYFISH else 0.0
			if creature == Creature.WORMS:
				facing = _face[i]
		else:
			facing = _face[i]
			var v := _v[i]
			ang = clampf(atan2(v.y, v.x) if facing > 0.0 else atan2(-v.y, -v.x), -0.6, 0.6) if v.length() > 0.001 else 0.0
		var extra := 0.0
		match creature:
			Creature.SPIDERS:
				extra = _ex[i] if _mode[i] == 1 else 0.0
			Creature.SNAILS, Creature.OWLS, Creature.WORMS:
				extra = _ex[i]
		pos[k] = Vector4(_p[i].x, _p[i].y, ang, sz * facing)
		st[k] = Vector4(_ph[i], _gl[i], _dep[i], extra)
	_mat.set_shader_parameter("cpos", pos)
	_mat.set_shader_parameter("cstate", st)
	_mat.set_shader_parameter("count", n)
