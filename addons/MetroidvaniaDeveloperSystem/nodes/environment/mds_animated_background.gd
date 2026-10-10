@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/animated_background.svg")
class_name MDSAnimatedBackground
extends MDSEnvironmentEffect
## An animated background drawn by a shader: soft, out of focus, as if far behind the room and
## seen through a lens. Twenty styles ([member style]): bokeh lights, an aurora, a nebula, molten
## blobs, deep water, ember glow, storm clouds, a forest canopy, a sunset haze, a crystal cave,
## a frozen night, drifting spores, a starfield, a toxic swamp, your own picture blurred, and
## ones made for boss rooms (a void pulse, a blood moon, an arcane vortex, the infection, holy
## light). Picking a style gives it its colors and pace; change them after.
##
## The other kind of background is the parallax one ([MDSParallaxBackground]). Both can be
## behind a room at once: this one is the farthest (z_index -110), the parallax layers are drawn
## over it (-100), so a parallax without a sky layer shows it between its silhouettes.
##
## In the game it covers the whole view and follows the camera, moving a little with it
## ([member scroll_scale]). In the editor (and the Room view) it covers its rectangle. Give an
## area, a room, the world or the boss rooms one in the Areas, Inspect and World settings tabs
## ("Animated bg" fields): [MDSWorldGame] adds it to the room as it loads (see
## [method MDSEnvironment.background_for_room]).

enum Style { BOKEH, AURORA, NEBULA, MOLTEN_BLOBS, DEEP_WATER, EMBER_GLOW, STORM_CLOUDS, FOREST_CANOPY, SUNSET_HAZE, CRYSTAL_CAVE, VOID_PULSE, BLOOD_MOON, ARCANE_VORTEX, FROZEN_NIGHT, SPORE_DRIFT, INFECTION, STARFIELD, HOLY_LIGHT, TOXIC_SWAMP, PICTURE }
## Ids of the styles (as the "Animated bg" fields write them), in [enum Style] order.
const STYLE_IDS: PackedStringArray = ["bokeh", "aurora", "nebula", "molten_blobs", "deep_water", "ember_glow", "storm_clouds", "forest_canopy", "sunset_haze", "crystal_cave", "void_pulse", "blood_moon", "arcane_vortex", "frozen_night", "spore_drift", "infection", "starfield", "holy_light", "toxic_swamp", "picture"]
const STYLE_NAMES: PackedStringArray = ["Bokeh lights", "Aurora", "Nebula", "Molten blobs", "Deep water", "Ember glow", "Storm clouds", "Forest canopy", "Sunset haze", "Crystal cave", "Void pulse", "Blood moon", "Arcane vortex", "Frozen night", "Spore drift", "Infection", "Starfield", "Holy light", "Toxic swamp", "Your picture, blurred"]
## What each style shows, in [enum Style] order.
const STYLE_INFO: PackedStringArray = [
	"Out-of-focus lights drifting at three depths, like a city or lanterns seen through a lens",
	"Curtains of green and violet light waving over a starry night",
	"Slowly turning clouds of cosmic gas, soft stars twinkling",
	"Big soft blobs of molten color merging and parting, like a lava lamp",
	"Deep water: soft caustics, light rays from the surface, bubbles rising",
	"A dark red heat glowing from below, smoke, blurred embers rising",
	"Dark clouds rolling, lightning flashing behind them, a veil of rain",
	"Light through leaves: swaying shadows, sun flecks, soft rays",
	"A warm sky, a big soft sun, bands of cloud drifting by",
	"Glowing crystal facets shimmering in the dark, sparkles",
	"Boss: a dark void throbbing, rings rippling out from a glowing core",
	"Boss: a huge blood-red moon, red mist drifting across it",
	"Boss: a spiral of arcane light turning around a bright eye",
	"A cold night, snowflakes falling out of focus, near ones large and soft",
	"A teal haze, bioluminescent spores wandering",
	"Boss: glowing orange veins pulsing through the dark, motes drifting up",
	"Stars at several depths drifting slowly, a faint haze",
	"Boss or shrine: golden rays falling from above, dust shining in them",
	"A green murk swirling, bubbles rising, a sickly glow",
	"Your own picture, blurred out of focus, drifting and breathing slowly",
]
## The styles made for boss rooms.
const BOSS_STYLES: PackedStringArray = ["void_pulse", "blood_moon", "arcane_vortex", "infection", "holy_light", "ember_glow", "storm_clouds"]

## The look: picking one gives the background its colors, pace and blur (change them after).
@export var style: Style = Style.BOKEH:
	set(v):
		if v == style:
			return
		style = v
		apply_look(v)
		_changed()
@export_group("Colors")
## The deep: the bottom of the sky, the dark between the lights.
@export var color_a := Color("#0b0f22"):
	set(v):
		color_a = v
		_changed()
## The top of the sky.
@export var color_b := Color("#241a3e"):
	set(v):
		color_b = v
		_changed()
## The lights: the main glow (style PICTURE: the picture's tint).
@export var color_c := Color("#ffbf73"):
	set(v):
		color_c = v
		_changed()
## The accent (style PICTURE: a haze over it, its alpha how much).
@export var color_d := Color("#8fa6ff"):
	set(v):
		color_d = v
		_changed()
@export_group("Motion")
## How fast it moves (0: still).
@export_range(0.0, 4.0, 0.01) var speed := 1.0:
	set(v):
		speed = v
		_changed()
## How out of focus it is: 0 sharp, 1 very soft.
@export_range(0.0, 1.0, 0.01) var blur := 0.6:
	set(v):
		blur = v
		_changed()
## Size of its features (2: twice as big).
@export_range(0.25, 4.0, 0.01) var feature_scale := 1.0:
	set(v):
		feature_scale = v
		_changed()
## How many lights, motes, stars or blobs.
@export_range(0.0, 1.0, 0.01) var density := 0.5:
	set(v):
		density = v
		_changed()
@export_range(0.0, 2.0, 0.01) var brightness := 1.0:
	set(v):
		brightness = v
		_changed()
## A throb like a heartbeat, for boss rooms (0: none).
@export_range(0.0, 1.0, 0.01) var pulse := 0.0:
	set(v):
		pulse = v
		_changed()
## Beats a second.
@export_range(0.1, 4.0, 0.01) var pulse_rate := 1.0:
	set(v):
		pulse_rate = v
		_changed()
## Darkens the corners.
@export_range(0.0, 1.0, 0.01) var vignette := 0.35:
	set(v):
		vignette = v
		_changed()
## Film grain (it also hides banding in the soft gradients).
@export_range(0.0, 1.0, 0.01) var grain := 0.3:
	set(v):
		grain = v
		_changed()
## How much it moves with the camera: 0 stays on the screen (infinitely far), 1 moves with the
## room.
@export var scroll_scale := Vector2(0.04, 0.02):
	set(v):
		scroll_scale = v
		_changed()
## Cover the whole view and follow the camera (in the game). Off: only its rectangle.
@export var follow_camera := true
@export_group("Picture")
## Style PICTURE: the image shown, blurred by [member blur].
@export var picture: Texture2D:
	set(v):
		picture = v
		_changed()

## Colors and settings of each style: id -> {property: value}.
const LOOKS := {
	"bokeh": {"color_a": Color("#0b0f22"), "color_b": Color("#241a3e"), "color_c": Color("#ffbf73"), "color_d": Color("#8fa6ff"), "speed": 1.0, "blur": 0.6, "density": 0.5, "pulse": 0.0, "vignette": 0.35},
	"aurora": {"color_a": Color("#0a1a24"), "color_b": Color("#03060f"), "color_c": Color("#4dffb0"), "color_d": Color("#a56bff"), "speed": 1.0, "blur": 0.55, "density": 0.5, "pulse": 0.0, "vignette": 0.3},
	"nebula": {"color_a": Color("#05040d"), "color_b": Color("#2c1450"), "color_c": Color("#ff6fa8"), "color_d": Color("#53c7ff"), "speed": 1.0, "blur": 0.5, "density": 0.5, "pulse": 0.0, "vignette": 0.4},
	"molten_blobs": {"color_a": Color("#1a0710"), "color_b": Color("#3a0d24"), "color_c": Color("#ff7a3d"), "color_d": Color("#ff2f7a"), "speed": 1.0, "blur": 0.6, "density": 0.5, "pulse": 0.0, "vignette": 0.35},
	"deep_water": {"color_a": Color("#02101e"), "color_b": Color("#0f4a6b"), "color_c": Color("#9cf2ff"), "color_d": Color("#d6fbff"), "speed": 1.0, "blur": 0.55, "density": 0.4, "pulse": 0.0, "vignette": 0.4},
	"ember_glow": {"color_a": Color("#0c0303"), "color_b": Color("#3d0b05"), "color_c": Color("#ffb347"), "color_d": Color("#ff4a1a"), "speed": 1.0, "blur": 0.55, "density": 0.55, "pulse": 0.0, "vignette": 0.45},
	"storm_clouds": {"color_a": Color("#0d1016"), "color_b": Color("#3b4252"), "color_c": Color("#d8e4ff"), "color_d": Color("#8a96aa"), "speed": 1.0, "blur": 0.5, "density": 0.6, "pulse": 0.0, "vignette": 0.45},
	"forest_canopy": {"color_a": Color("#0b2214"), "color_b": Color("#3c6b3a"), "color_c": Color("#f4f0a0"), "color_d": Color("#b8f08a"), "speed": 1.0, "blur": 0.6, "density": 0.5, "pulse": 0.0, "vignette": 0.35},
	"sunset_haze": {"color_a": Color("#f08a4b"), "color_b": Color("#3d2a5c"), "color_c": Color("#ffe3a3"), "color_d": Color("#c0587a"), "speed": 1.0, "blur": 0.6, "density": 0.5, "pulse": 0.0, "vignette": 0.25},
	"crystal_cave": {"color_a": Color("#05030f"), "color_b": Color("#1a1038"), "color_c": Color("#7fe8ff"), "color_d": Color("#d07bff"), "speed": 1.0, "blur": 0.5, "density": 0.5, "pulse": 0.0, "vignette": 0.45},
	"void_pulse": {"color_a": Color("#020104"), "color_b": Color("#150825"), "color_c": Color("#b06bff"), "color_d": Color("#3b1d6e"), "speed": 1.0, "blur": 0.55, "density": 0.5, "pulse": 0.5, "vignette": 0.55},
	"blood_moon": {"color_a": Color("#0e0204"), "color_b": Color("#3c0a10"), "color_c": Color("#ff3b2e"), "color_d": Color("#5c1018"), "speed": 1.0, "blur": 0.5, "density": 0.5, "pulse": 0.3, "vignette": 0.5},
	"arcane_vortex": {"color_a": Color("#04030c"), "color_b": Color("#1c1250"), "color_c": Color("#ffe48a"), "color_d": Color("#6f5bff"), "speed": 1.0, "blur": 0.55, "density": 0.5, "pulse": 0.35, "vignette": 0.5},
	"frozen_night": {"color_a": Color("#3e5878"), "color_b": Color("#0b1426"), "color_c": Color("#f2f8ff"), "color_d": Color("#9fc0e8"), "speed": 1.0, "blur": 0.6, "density": 0.55, "pulse": 0.0, "vignette": 0.35},
	"spore_drift": {"color_a": Color("#03120f"), "color_b": Color("#0d3a34"), "color_c": Color("#6fffe0"), "color_d": Color("#c3ff8a"), "speed": 1.0, "blur": 0.6, "density": 0.5, "pulse": 0.0, "vignette": 0.4},
	"infection": {"color_a": Color("#0a0503"), "color_b": Color("#2a1208"), "color_c": Color("#ff9a2a"), "color_d": Color("#ffcf6a"), "speed": 1.0, "blur": 0.5, "density": 0.5, "pulse": 0.4, "vignette": 0.5},
	"starfield": {"color_a": Color("#0a0d22"), "color_b": Color("#010208"), "color_c": Color("#e8eeff"), "color_d": Color("#4a5aa8"), "speed": 1.0, "blur": 0.45, "density": 0.55, "pulse": 0.0, "vignette": 0.35},
	"holy_light": {"color_a": Color("#3a2a14"), "color_b": Color("#c9a35a"), "color_c": Color("#fff2c4"), "color_d": Color("#ffd27a"), "speed": 1.0, "blur": 0.6, "density": 0.5, "pulse": 0.15, "vignette": 0.35},
	"toxic_swamp": {"color_a": Color("#071006"), "color_b": Color("#2c4a12"), "color_c": Color("#c6ff4a"), "color_d": Color("#7dff6a"), "speed": 1.0, "blur": 0.55, "density": 0.5, "pulse": 0.0, "vignette": 0.45},
	"picture": {"color_a": Color("#101418"), "color_b": Color("#303840"), "color_c": Color.WHITE, "color_d": Color(0.0, 0.0, 0.0, 0.3), "speed": 1.0, "blur": 0.6, "density": 0.3, "pulse": 0.0, "vignette": 0.35},
}

## The settings a style sets.
const LOOK_KEYS: PackedStringArray = ["color_a", "color_b", "color_c", "color_d", "speed", "blur", "density", "pulse", "vignette"]

var _mat: ShaderMaterial
var _quad: Polygon2D

func _init() -> void:
	z_index = -110

# The style and its settings are also saved together, as "look". Setting the style gives the
# background that style's settings, and a setting equal to its default isn't saved on its own:
# without "look", a scene would bring it back as the style's.
func _get_property_list() -> Array[Dictionary]:
	return [{"name": "look", "type": TYPE_DICTIONARY, "usage": PROPERTY_USAGE_STORAGE}]

func _get(property: StringName) -> Variant:
	if property == &"look":
		var d: Dictionary = {"style": int(style)}
		for k in LOOK_KEYS:
			d[k] = get(k)
		return d
	return null

func _set(property: StringName, value: Variant) -> bool:
	if property != &"look" or not value is Dictionary:
		return false
	if value.has("style"):
		style = int(value.style) as Style
	for k in value:
		if LOOK_KEYS.has(str(k)):
			set(str(k), value[k])
	return true

func get_effect_id() -> String:
	return "animated_background"

## Gives it the look of style [param id] (see [constant STYLE_IDS]). Returns false for an
## unknown one.
func use_style(id: String) -> bool:
	var i := STYLE_IDS.find(id.strip_edges().to_lower().replace(" ", "_"))
	if i < 0:
		return false
	style = i as Style
	return true

## Sets the colors and settings of [param s] (see [constant LOOKS]).
func apply_look(s: Style) -> void:
	var look: Dictionary = LOOKS.get(STYLE_IDS[s], {})
	for k in look:
		set(k, look[k])

## Whether [param id] names a style made for boss rooms.
static func is_boss_style(id: String) -> bool:
	return BOSS_STYLES.has(id.strip_edges().to_lower())

func _build() -> void:
	_mat = add_quad(shader("animated_background"), get_effect_rect())
	_quad = _quads[_quads.size() - 1] as Polygon2D
	_tick(0.0)

func _update_params() -> void:
	if not _mat:
		return
	_mat.set_shader_parameter("style", int(style))
	_mat.set_shader_parameter("color_a", color_a)
	_mat.set_shader_parameter("color_b", color_b)
	_mat.set_shader_parameter("color_c", color_c)
	_mat.set_shader_parameter("color_d", color_d)
	_mat.set_shader_parameter("speed", speed)
	_mat.set_shader_parameter("blur", blur)
	_mat.set_shader_parameter("feature_scale", feature_scale)
	_mat.set_shader_parameter("density", density)
	_mat.set_shader_parameter("brightness", brightness)
	_mat.set_shader_parameter("pulse", pulse)
	_mat.set_shader_parameter("pulse_rate", pulse_rate)
	_mat.set_shader_parameter("vignette", vignette)
	_mat.set_shader_parameter("grain", grain)
	_mat.set_shader_parameter("picture", picture)
	_mat.set_shader_parameter("has_picture", picture != null)
	_mat.set_shader_parameter("picture_size", Vector2(picture.get_size()) if picture else Vector2.ONE)

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

## How far the background moved with the camera at [param cam] (local), in view heights: its
## share ([member scroll_scale]) of the camera's way from the rectangle's middle.
func drift_for(cam: Vector2) -> Vector2:
	return (cam - get_effect_rect().get_center()) * scroll_scale / 648.0

func _tick(_delta: float) -> void:
	if not _quad:
		return
	var view := view_rect()
	var following := follow_camera and not Engine.is_editor_hint()
	# In the game it covers the view, wherever the camera goes; in the editor only the rectangle.
	var cover := view.grow(4.0) if following else get_effect_rect()
	var poly := PackedVector2Array([cover.position, Vector2(cover.end.x, cover.position.y), cover.end, Vector2(cover.position.x, cover.end.y)])
	if _quad.polygon != poly:
		_quad.polygon = poly
	_mat.set_shader_parameter("rect_origin", cover.position)
	_mat.set_shader_parameter("rect_size", cover.size)
	_mat.set_shader_parameter("edge_fade", 0.0 if following else 24.0)
	_mat.set_shader_parameter("view_rect", Vector4(view.position.x, view.position.y, view.size.x, view.size.y))
	_mat.set_shader_parameter("drift", drift_for(view.get_center()))
