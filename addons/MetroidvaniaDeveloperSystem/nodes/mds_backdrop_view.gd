@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSBackdropView
extends Node2D
## Draws an [MDSBackdrop] behind a room: the sky over the whole view and the planes behind the
## room are drawn off screen in a [SubViewport] at [member MDSBackdrop.resolution] of the
## screen, looking through the same camera, and shown scaled up on a [CanvasLayer] far below
## the room's. Being a world of its own, the distance is never drawn into the room's world, and
## a dark room's darkness (lights, CanvasModulate on the room's canvas) doesn't reach it.
## Foreground planes are drawn in the room's world, in front of it.
##
## Place it at the room's top-left corner with [member room_size] its size ([MDSWorldGame]
## does this, with the backdrop of the room, of its area, or of the world). A plane of depth d
## moves at d of the camera's speed, around the room's middle.

## The backdrop drawn (rebuilt when set).
@export var backdrop: MDSBackdrop:
	set(v):
		backdrop = v
		if is_inside_tree():
			rebuild()
## Size of the room the planes are laid out around (its middle is where they rest).
@export var room_size := Vector2(1152, 648)
## For [member MDSBackdrop.sample_palette]: the room whose terrain colors tint the haze.
@export var room: Node

const FOG_SHADER := """
shader_type canvas_item;
uniform vec4 haze_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float haze = 0.3;
uniform vec4 tint : source_color = vec4(1.0);
uniform float desaturate = 0.0;
uniform float alpha = 1.0;
uniform float sway = 0.0;
void vertex() {
	VERTEX.x += sin(TIME * 0.6 + VERTEX.x * 0.004) * sway * max(VERTEX.y, 0.0) * 0.035;
}
void fragment() {
	float grey = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	COLOR.rgb = mix(COLOR.rgb, vec3(grey), desaturate) * tint.rgb;
	COLOR.rgb = mix(COLOR.rgb, haze_color.rgb, haze);
	COLOR.a *= alpha;
}
"""
static var _fog: Shader

var _sub: SubViewport
var _back: Node2D
var _shown: CanvasLayer
var _rect: TextureRect
var _sky: _Sky
var _front: Node2D
## [[plane, depth]]
var planes: Array = []

func _ready() -> void:
	_sub = SubViewport.new()
	_sub.name = "Distance"
	_sub.disable_3d = true
	_sub.transparent_bg = false
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	_sub.world_2d = World2D.new()
	_sub.size = Vector2i(576, 324)
	add_child(_sub)
	_back = Node2D.new()
	_back.name = "Planes"
	_sub.add_child(_back)
	_shown = CanvasLayer.new()
	_shown.name = "DistanceShown"
	_shown.layer = -110
	add_child(_shown)
	_rect = TextureRect.new()
	_rect.texture = _sub.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shown.add_child(_rect)
	_front = Node2D.new()
	_front.name = "Foreground"
	_front.z_index = 30
	add_child(_front)
	rebuild()

## The node planes behind the room are added to (in the off-screen world).
func distance_layer() -> Node2D:
	return _back

func rebuild() -> void:
	if not _back:
		return
	for p in planes:
		if is_instance_valid(p[0]):
			p[0].queue_free()
	planes.clear()
	if is_instance_valid(_sky):
		_sky.queue_free()
	_sky = null
	_shown.visible = backdrop != null
	if not backdrop:
		return
	_sky = _Sky.new()
	_sky.backdrop = backdrop
	_sky.z_index = -100
	_back.add_child(_sky)
	var palette := _room_palette() if backdrop.sample_palette else Color(0, 0, 0, 0)
	var z := -90
	for layer in backdrop.layers:
		if layer:
			_add_plane(layer, z, palette)
			z += 1

## The average color of the room's terrain (its freeform styles), or transparent.
func _room_palette() -> Color:
	if not is_instance_valid(room):
		return Color(0, 0, 0, 0)
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for f in MDSFreeform.terrain_in(room):
		var st := f.get_style()
		var c := MDSDepth25D.average_color(st.fill_texture, st.fill_color) if st.fill_texture else st.fill_color
		sum += c
		n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n, 1.0) if n > 0 else Color(0, 0, 0, 0)

func _add_plane(layer: MDSBackdropLayer, z: int, palette: Color) -> void:
	var plane := Node2D.new()
	plane.name = "Plane%d" % planes.size()
	plane.scale = Vector2.ONE * maxf(layer.scale, 0.01)
	plane.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if not _fog:
		_fog = Shader.new()
		_fog.code = FOG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _fog
	var haze := layer.haze_color
	if palette.a > 0.0:
		haze = haze.lerp(palette, backdrop.palette_mix)
	mat.set_shader_parameter("haze_color", haze)
	mat.set_shader_parameter("haze", layer.haze)
	mat.set_shader_parameter("tint", layer.tint)
	mat.set_shader_parameter("desaturate", layer.desaturate)
	mat.set_shader_parameter("alpha", layer.alpha)
	mat.set_shader_parameter("sway", layer.sway)
	plane.material = mat
	if layer.foreground:
		plane.z_index = z
		_front.add_child(plane)
	else:
		plane.z_index = z
		_back.add_child(plane)
	_fill_plane(plane, layer)
	planes.append([plane, layer.depth])

## How far (plane px) the art must reach either side so the view never runs off its edge
## wherever the camera goes in the room.
func _reach(layer: MDSBackdropLayer) -> Vector2:
	var view := _view_size()
	var roam := room_size * 0.5
	return (roam * absf(1.0 - layer.depth) + view * 0.8) / maxf(layer.scale, 0.01)

func _fill_plane(plane: Node2D, layer: MDSBackdropLayer) -> void:
	var reach := _reach(layer)
	match layer.source:
		MDSBackdropLayer.Source.TEXTURE:
			if not layer.texture:
				return
			var w := layer.spacing if layer.spacing > 0.0 else float(layer.texture.get_width())
			var count := ceili(reach.x / w) + 1 if layer.repeat else 0
			for k in range(-count, count + 1):
				var s := Sprite2D.new()
				s.texture = layer.texture
				s.position = layer.offset + Vector2(k * w, 0)
				plane.add_child(s)
		MDSBackdropLayer.Source.STAMPS:
			var set := layer.stamp_set
			if not set:
				return
			var picks := set.indices(layer.stamp_category)
			if picks.is_empty():
				return
			var rng := RandomNumberGenerator.new()
			rng.seed = layer.seed_value
			var n := maxi(1, roundi(reach.x * 2.0 / 1000.0 * layer.stamp_density))
			for i in n:
				var s := set.make_sprite(picks[rng.randi_range(0, picks.size() - 1)])
				var k := rng.randf_range(layer.stamp_scale.x, layer.stamp_scale.y)
				s.scale = Vector2(k * (-1.0 if rng.randf() < 0.5 else 1.0), k)
				s.position = layer.offset + Vector2(lerpf(-reach.x, reach.x, (i + rng.randf()) / n), rng.randf_range(-layer.jitter, layer.jitter))
				plane.add_child(s)
		MDSBackdropLayer.Source.SCENE:
			if not layer.scene:
				return
			var first := layer.scene.instantiate()
			plane.add_child(first)
			if first is Node2D:
				(first as Node2D).position = layer.offset
			if layer.repeat and layer.spacing > 0.0:
				var count := ceili(reach.x / layer.spacing)
				for k in range(-count, count + 1):
					if k == 0:
						continue
					var copy := layer.scene.instantiate()
					plane.add_child(copy)
					if copy is Node2D:
						(copy as Node2D).position = layer.offset + Vector2(k * layer.spacing, 0)

# --- Following the camera ----------------------------------------------------------------------------

func _view_size() -> Vector2:
	var vp := get_viewport()
	if not vp:
		return Vector2(1152, 648)
	var k := vp.get_canvas_transform().get_scale().abs()
	return vp.get_visible_rect().size / Vector2(maxf(k.x, 0.001), maxf(k.y, 0.001))

## Where the camera looks, in this node's space.
func view_centre() -> Vector2:
	var vp := get_viewport()
	if not vp:
		return room_size * 0.5
	return to_local(vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size * 0.5))

func _process(_delta: float) -> void:
	if not backdrop or not _sub:
		return
	var vp := get_viewport()
	var logical := vp.get_visible_rect().size
	var pixels := Vector2(vp.get_texture().get_size()) if vp.get_texture() else logical
	var res := clampf(backdrop.resolution, 0.1, 1.0)
	var want := Vector2i(maxi(int(pixels.x * res), 16), maxi(int(pixels.y * res), 16))
	if _sub.size != want:
		_sub.size = want
	var k := pixels / Vector2(maxf(logical.x, 1.0), maxf(logical.y, 1.0)) * res
	_sub.canvas_transform = Transform2D().scaled(k) * vp.get_canvas_transform()
	_back.global_transform = global_transform
	_rect.position = vp.get_visible_rect().position
	_rect.size = logical
	var cam := view_centre()
	var centre := room_size * 0.5
	for p in planes:
		var depth: float = p[1]
		(p[0] as Node2D).position = centre + (cam - centre) * (1.0 - depth)
	if _sky:
		var seen := _view_size()
		_sky.cover(Rect2(cam - seen * 0.6, seen * 1.2), Rect2(cam - seen * 0.5, seen))

## The sky gradient over the view (it is infinitely far: laid out on the view, not the room).
class _Sky extends Node2D:
	var backdrop: MDSBackdrop
	var rect := Rect2()
	var view := Rect2()

	func cover(r: Rect2, seen: Rect2) -> void:
		if not r.is_equal_approx(rect) or not seen.is_equal_approx(view):
			rect = r
			view = seen
			queue_redraw()

	func _draw() -> void:
		if not rect.has_area():
			return
		var steps := 16
		for i in steps:
			var y0 := lerpf(rect.position.y, rect.end.y, float(i) / steps)
			var y1 := lerpf(rect.position.y, rect.end.y, float(i + 1) / steps)
			var c0 := backdrop.sky_color(inverse_lerp(view.position.y, view.end.y, y0))
			var c1 := backdrop.sky_color(inverse_lerp(view.position.y, view.end.y, y1))
			draw_polygon(PackedVector2Array([Vector2(rect.position.x, y0), Vector2(rect.end.x, y0), Vector2(rect.end.x, y1), Vector2(rect.position.x, y1)]), PackedColorArray([c0, c0, c1, c1]))
