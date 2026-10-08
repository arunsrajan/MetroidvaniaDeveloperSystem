@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/parallax.svg")
class_name MDSParallaxBackground
extends MDSEnvironmentEffect
## A parallax background: layers behind the room, each moving at its own share of the camera's
## speed ([member MDSParallaxLayer.scroll_scale]), the far ones slowest, so the distance has
## depth. Layers are drawn by a shader, so no art is needed (a sky, mountains, hills, forest,
## city, ruins, cave rock, dunes, clouds, fog, stars); a layer can also be your own picture,
## repeated sideways. Pick a [member preset] to start from, then change its layers.
##
## In the game it covers the whole view and follows the camera. In the editor (and the Room
## view) it covers its rectangle, and scrolls as you pan the view. Give an area (or a room, or
## the world) one in the Areas tab's Parallax field: [MDSWorldGame] adds it to every room of the
## area as the room loads.
##
## It draws at z_index -100: behind the room's background tiles (-10) and everything else.

## Starting points; CUSTOM keeps the layers as they are.
enum Preset { CUSTOM, DUSK_MOUNTAINS, MISTY_FOREST, RUINED_CITY, DESERT_DUNES, DEEP_CAVERN, SNOWY_PEAKS, VOLCANIC, NIGHT_SKY, SUNKEN_GARDEN, DUSTY_WASTES }
## Ids of the presets (as the Parallax fields write them), in [enum Preset] order.
const PRESET_IDS: PackedStringArray = ["custom", "dusk_mountains", "misty_forest", "ruined_city", "desert_dunes", "deep_cavern", "snowy_peaks", "volcanic", "night_sky", "sunken_garden", "dusty_wastes"]
const PRESET_NAMES: PackedStringArray = ["Custom", "Dusk mountains", "Misty forest", "Ruined city at night", "Desert dunes", "Deep cavern", "Snowy peaks", "Volcanic", "Night sky", "Sunken garden", "Dusty wastes"]

@export var preset: Preset = Preset.DUSK_MOUNTAINS:
	set(v):
		preset = v
		if v != Preset.CUSTOM:
			layers = layers_of(v)
## Farthest first.
@export var layers: Array[MDSParallaxLayer] = []:
	set(v):
		for l in layers:
			if l and l.changed.is_connected(_changed):
				l.changed.disconnect(_changed)
		layers = v
		for l in layers:
			if l and not l.changed.is_connected(_changed):
				l.changed.connect(_changed)
		_queue_rebuild()
## Cover the whole view and scroll with the camera (in the game). Off: only its rectangle.
@export var follow_camera := true

var _layer_mats: Array[ShaderMaterial] = []
var _layer_quads: Array[Polygon2D] = []

func _init() -> void:
	z_index = -100
	if layers.is_empty():
		layers = layers_of(preset)

func get_effect_id() -> String:
	return "parallax"

## Starts from [param p] (a preset id, see [constant PRESET_IDS]). Returns false for an
## unknown one.
func use_preset(id: String) -> bool:
	var i := PRESET_IDS.find(id.strip_edges().to_lower())
	if i <= 0:
		return false
	preset = i as Preset
	return true

## Adds [param texture] as the nearest layer, its bottom on the background's horizon.
func add_picture(texture: Texture2D, scroll := Vector2(0.4, 0.2)) -> MDSParallaxLayer:
	var l := MDSParallaxLayer.make(MDSParallaxLayer.Kind.PICTURE, {"picture": texture, "color": Color.WHITE, "scroll_scale": scroll, "horizon": 1.0, "haze": 0.0, "fill_below": false})
	var list := layers.duplicate()
	list.append(l)
	preset = Preset.CUSTOM
	layers = list
	return l

func _build() -> void:
	_layer_mats.clear()
	_layer_quads.clear()
	var sh := shader("parallax_layer")
	for i in layers.size():
		var m := add_quad(sh, get_effect_rect(), i, float(i) * 3.7)
		_layer_mats.append(m)
		_layer_quads.append(_quads[_quads.size() - 1] as Polygon2D)
	_tick(0.0)

func _update_params() -> void:
	var r := get_effect_rect()
	for i in mini(layers.size(), _layer_mats.size()):
		var l := layers[i]
		var m := _layer_mats[i]
		if not l:
			m.set_shader_parameter("alpha", 0.0)
			continue
		m.set_shader_parameter("kind", int(l.kind))
		m.set_shader_parameter("color", l.color)
		m.set_shader_parameter("color_top", l.color_top)
		m.set_shader_parameter("color_bottom", l.color_bottom)
		m.set_shader_parameter("base_y", r.position.y + l.horizon * r.size.y)
		m.set_shader_parameter("height", l.height)
		m.set_shader_parameter("feature_size", l.feature_size)
		m.set_shader_parameter("roughness", l.roughness)
		m.set_shader_parameter("fill_below", l.fill_below)
		m.set_shader_parameter("haze", l.haze)
		m.set_shader_parameter("alpha", l.alpha)
		m.set_shader_parameter("autoscroll", l.autoscroll)
		m.set_shader_parameter("seed", float(seed_value) * 1.37 + float(l.seed_value) + i * 3.7)
		m.set_shader_parameter("picture", l.picture)
		m.set_shader_parameter("picture_size", Vector2(l.picture.get_size()) if l.picture else Vector2.ONE)
		m.set_shader_parameter("picture_scale", l.picture_scale)
		m.set_shader_parameter("repeat_x", l.repeat_x)

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

## Each layer's offset for the camera at [param cam] (local): it moves by its share of the
## camera's movement from the background's middle.
func layer_offset(layer: MDSParallaxLayer, cam: Vector2) -> Vector2:
	return (cam - get_effect_rect().get_center()) * (Vector2.ONE - layer.scroll_scale)

func _tick(_delta: float) -> void:
	if _layer_quads.is_empty():
		return
	var view := view_rect()
	var cam := view.get_center()
	# In the game the layers cover the view, wherever the camera goes; in the editor only the
	# rectangle (they would cover the whole 2D view otherwise).
	var cover := view.grow(4.0) if follow_camera and not Engine.is_editor_hint() else get_effect_rect()
	var poly := PackedVector2Array([cover.position, Vector2(cover.end.x, cover.position.y), cover.end, Vector2(cover.position.x, cover.end.y)])
	for i in mini(layers.size(), _layer_quads.size()):
		var q := _layer_quads[i]
		if q.polygon != poly:
			q.polygon = poly
		var m := _layer_mats[i]
		m.set_shader_parameter("rect_origin", cover.position)
		m.set_shader_parameter("rect_size", cover.size)
		m.set_shader_parameter("view_rect", Vector4(view.position.x, view.position.y, view.size.x, view.size.y))
		if layers[i]:
			m.set_shader_parameter("offset", layer_offset(layers[i], cam))

## The layers of [param p], farthest first.
static func layers_of(p: Preset) -> Array[MDSParallaxLayer]:
	var K := MDSParallaxLayer.Kind
	var out: Array[MDSParallaxLayer] = []
	match p:
		Preset.DUSK_MOUNTAINS:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#1d2340"), "color_bottom": Color("#c9785a"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.CLOUDS, {"color": Color("#7a4a5a"), "color_top": Color("#f0a880"), "horizon": 0.3, "height": 70.0, "feature_size": 700.0, "alpha": 0.45, "autoscroll": 6.0, "scroll_scale": Vector2(0.02, 0.01)}))
			out.append(MDSParallaxLayer.make(K.MOUNTAINS, {"color": Color("#4a3a62"), "color_top": Color("#e8c8d8"), "color_bottom": Color("#b06a68"), "horizon": 0.66, "height": 280.0, "feature_size": 620.0, "haze": 0.55, "scroll_scale": Vector2(0.05, 0.03)}))
			out.append(MDSParallaxLayer.make(K.MOUNTAINS, {"color": Color("#2c2442"), "color_top": Color("#c8a8c8"), "color_bottom": Color("#7a4a58"), "horizon": 0.76, "height": 210.0, "feature_size": 420.0, "haze": 0.4, "roughness": 0.65, "scroll_scale": Vector2(0.15, 0.07), "seed_value": 3}))
			out.append(MDSParallaxLayer.make(K.HILLS, {"color": Color("#17121f"), "color_top": Color("#3a2a3a"), "color_bottom": Color("#2a1a26"), "horizon": 0.9, "height": 110.0, "feature_size": 380.0, "haze": 0.15, "scroll_scale": Vector2(0.3, 0.15)}))
		Preset.MISTY_FOREST:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#93b2ae"), "color_bottom": Color("#e2ebe2"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.FOREST, {"color": Color("#8aa59f"), "color_bottom": Color("#d0ddd6"), "horizon": 0.7, "height": 170.0, "feature_size": 900.0, "haze": 0.5, "scroll_scale": Vector2(0.06, 0.03)}))
			out.append(MDSParallaxLayer.make(K.FOG, {"color": Color("#e4ece6"), "horizon": 0.72, "height": 90.0, "feature_size": 500.0, "alpha": 0.6, "autoscroll": 4.0, "scroll_scale": Vector2(0.1, 0.05)}))
			out.append(MDSParallaxLayer.make(K.FOREST, {"color": Color("#557069"), "color_bottom": Color("#a8bfb6"), "horizon": 0.8, "height": 230.0, "feature_size": 1100.0, "haze": 0.35, "scroll_scale": Vector2(0.18, 0.09), "seed_value": 5}))
			out.append(MDSParallaxLayer.make(K.FOREST, {"color": Color("#22322d"), "color_bottom": Color("#4a5f57"), "horizon": 0.93, "height": 300.0, "feature_size": 1500.0, "haze": 0.1, "roughness": 0.7, "scroll_scale": Vector2(0.35, 0.18), "seed_value": 9}))
		Preset.RUINED_CITY:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#0b0e20"), "color_bottom": Color("#323657"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.STARS, {"color": Color("#d8dcff"), "horizon": 0.6, "height": 400.0, "roughness": 0.3, "scroll_scale": Vector2(0.01, 0.0)}))
			out.append(MDSParallaxLayer.make(K.CITY, {"color": Color("#262a48"), "color_top": Color("#f2d07a"), "color_bottom": Color("#3c4066"), "horizon": 0.74, "height": 260.0, "feature_size": 700.0, "roughness": 0.35, "haze": 0.45, "scroll_scale": Vector2(0.07, 0.04)}))
			out.append(MDSParallaxLayer.make(K.FOG, {"color": Color("#454a72"), "horizon": 0.76, "height": 70.0, "alpha": 0.5, "autoscroll": 5.0, "scroll_scale": Vector2(0.12, 0.06)}))
			out.append(MDSParallaxLayer.make(K.RUINS, {"color": Color("#13152a"), "color_top": Color("#f2d07a"), "color_bottom": Color("#22254a"), "horizon": 0.9, "height": 240.0, "feature_size": 900.0, "haze": 0.15, "scroll_scale": Vector2(0.25, 0.12), "seed_value": 4}))
		Preset.DESERT_DUNES:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#e2b178"), "color_bottom": Color("#f6e2b8"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.DUNES, {"color": Color("#d9a56c"), "color_top": Color("#f2cf98"), "color_bottom": Color("#efd3a6"), "horizon": 0.72, "height": 120.0, "feature_size": 900.0, "haze": 0.5, "scroll_scale": Vector2(0.05, 0.03)}))
			out.append(MDSParallaxLayer.make(K.DUNES, {"color": Color("#c48a52"), "color_top": Color("#e8b77a"), "color_bottom": Color("#d9ab78"), "horizon": 0.82, "height": 150.0, "feature_size": 700.0, "haze": 0.3, "scroll_scale": Vector2(0.15, 0.07), "seed_value": 6}))
			out.append(MDSParallaxLayer.make(K.DUNES, {"color": Color("#a46a38"), "color_top": Color("#d29858"), "color_bottom": Color("#b88050"), "horizon": 0.94, "height": 170.0, "feature_size": 560.0, "haze": 0.1, "scroll_scale": Vector2(0.3, 0.15), "seed_value": 11}))
		Preset.DEEP_CAVERN:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#05070b"), "color_bottom": Color("#121a20"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.CAVE, {"color": Color("#18222a"), "color_bottom": Color("#24323a"), "horizon": 0.85, "height": 230.0, "feature_size": 900.0, "haze": 0.5, "scroll_scale": Vector2(0.1, 0.08)}))
			out.append(MDSParallaxLayer.make(K.STARS, {"color": Color("#6fe0c0"), "horizon": 1.0, "height": 2000.0, "roughness": 0.1, "scroll_scale": Vector2(0.15, 0.1), "seed_value": 2}))
			out.append(MDSParallaxLayer.make(K.CAVE, {"color": Color("#0b1115"), "color_bottom": Color("#141e24"), "horizon": 0.95, "height": 300.0, "feature_size": 700.0, "haze": 0.25, "scroll_scale": Vector2(0.28, 0.2), "seed_value": 7}))
		Preset.SNOWY_PEAKS:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#567cab"), "color_bottom": Color("#d7e6f2"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.MOUNTAINS, {"color": Color("#8ea6c4"), "color_top": Color("#ffffff"), "color_bottom": Color("#c8d8e8"), "horizon": 0.68, "height": 320.0, "feature_size": 700.0, "haze": 0.45, "roughness": 0.7, "scroll_scale": Vector2(0.05, 0.03)}))
			out.append(MDSParallaxLayer.make(K.CLOUDS, {"color": Color("#c8d6e6"), "color_top": Color("#ffffff"), "horizon": 0.62, "height": 60.0, "feature_size": 600.0, "alpha": 0.55, "autoscroll": 8.0, "scroll_scale": Vector2(0.08, 0.04)}))
			out.append(MDSParallaxLayer.make(K.MOUNTAINS, {"color": Color("#5f7896"), "color_top": Color("#eef4ff"), "color_bottom": Color("#8ea6c0"), "horizon": 0.8, "height": 230.0, "feature_size": 480.0, "haze": 0.3, "scroll_scale": Vector2(0.15, 0.08), "seed_value": 4}))
			out.append(MDSParallaxLayer.make(K.FOREST, {"color": Color("#2c3a4c"), "color_bottom": Color("#4a5c70"), "horizon": 0.95, "height": 180.0, "feature_size": 1200.0, "haze": 0.1, "scroll_scale": Vector2(0.3, 0.15), "seed_value": 8}))
		Preset.VOLCANIC:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#160604"), "color_bottom": Color("#6a1e0c"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.CLOUDS, {"color": Color("#2a1410"), "color_top": Color("#a0482a"), "horizon": 0.35, "height": 110.0, "feature_size": 800.0, "alpha": 0.7, "autoscroll": -10.0, "scroll_scale": Vector2(0.03, 0.02)}))
			out.append(MDSParallaxLayer.make(K.MOUNTAINS, {"color": Color("#2a0e0a"), "color_top": Color("#ff6a2a"), "color_bottom": Color("#7a2410"), "horizon": 0.72, "height": 300.0, "feature_size": 520.0, "haze": 0.5, "roughness": 0.8, "scroll_scale": Vector2(0.07, 0.04)}))
			out.append(MDSParallaxLayer.make(K.HILLS, {"color": Color("#140806"), "color_top": Color("#c4401a"), "color_bottom": Color("#3a120a"), "horizon": 0.92, "height": 120.0, "feature_size": 360.0, "haze": 0.2, "roughness": 0.9, "scroll_scale": Vector2(0.3, 0.15), "seed_value": 5}))
		Preset.NIGHT_SKY:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#04050d"), "color_bottom": Color("#1a1f3d"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.STARS, {"color": Color("#e8ecff"), "horizon": 0.9, "height": 2000.0, "roughness": 0.5, "scroll_scale": Vector2(0.01, 0.0)}))
			out.append(MDSParallaxLayer.make(K.MOUNTAINS, {"color": Color("#151a33"), "color_top": Color("#3a4478"), "color_bottom": Color("#1c2244"), "horizon": 0.76, "height": 240.0, "feature_size": 560.0, "haze": 0.35, "roughness": 0.6, "scroll_scale": Vector2(0.05, 0.03), "seed_value": 6}))
			out.append(MDSParallaxLayer.make(K.HILLS, {"color": Color("#0b0e1d"), "color_top": Color("#2a3260"), "color_bottom": Color("#141936"), "horizon": 0.86, "height": 140.0, "feature_size": 600.0, "haze": 0.2, "scroll_scale": Vector2(0.15, 0.08)}))
		Preset.SUNKEN_GARDEN:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#2c463a"), "color_bottom": Color("#88aa90"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.RUINS, {"color": Color("#46645a"), "color_bottom": Color("#7c9c8a"), "horizon": 0.72, "height": 230.0, "feature_size": 800.0, "haze": 0.5, "scroll_scale": Vector2(0.06, 0.03)}))
			out.append(MDSParallaxLayer.make(K.FOG, {"color": Color("#a6c6ae"), "horizon": 0.75, "height": 80.0, "alpha": 0.55, "autoscroll": 3.0, "scroll_scale": Vector2(0.1, 0.05)}))
			out.append(MDSParallaxLayer.make(K.FOREST, {"color": Color("#26392f"), "color_bottom": Color("#3e5446"), "horizon": 0.92, "height": 220.0, "feature_size": 1300.0, "haze": 0.15, "roughness": 0.8, "scroll_scale": Vector2(0.3, 0.15), "seed_value": 3}))
		Preset.DUSTY_WASTES:
			out.append(MDSParallaxLayer.make(K.SKY, {"color_top": Color("#1b2128"), "color_bottom": Color("#525b62"), "scroll_scale": Vector2.ZERO}))
			out.append(MDSParallaxLayer.make(K.RUINS, {"color": Color("#363f47"), "color_bottom": Color("#4c565e"), "horizon": 0.74, "height": 190.0, "feature_size": 1000.0, "haze": 0.55, "roughness": 0.3, "scroll_scale": Vector2(0.05, 0.03)}))
			out.append(MDSParallaxLayer.make(K.FOG, {"color": Color("#6c757c"), "horizon": 0.78, "height": 110.0, "feature_size": 700.0, "alpha": 0.5, "autoscroll": 25.0, "scroll_scale": Vector2(0.1, 0.05)}))
			out.append(MDSParallaxLayer.make(K.DUNES, {"color": Color("#232a31"), "color_top": Color("#3c454c"), "color_bottom": Color("#323a41"), "horizon": 0.93, "height": 140.0, "feature_size": 800.0, "haze": 0.2, "scroll_scale": Vector2(0.28, 0.14), "seed_value": 4}))
	return out
