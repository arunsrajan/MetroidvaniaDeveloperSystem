@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/trace.svg")
class_name MDSDrawing
extends Node2D
## A picture placed in a room as it is drawn: what the Room view's Trace drawing makes with
## "The drawing itself", or any image. The [member region] of [member texture] is drawn from this
## node's origin, scaled and turned by its transform.
##
## Colors can be cut out: each pixel goes with the nearest of [member keep_colors] and
## [member cut_colors], and is transparent when that is a cut one. Trace drawing cuts out the
## paper around a drawing, and splits it into pictures at three depths (behind the terrain, at
## the terrain's depth and in front of everything), each keeping the colors of its layer.
## The cut is a shader (shaders/drawing_cutout.gdshader) on an internal sprite, so the scene
## stores only these values.
##
## A drawing has no collision: Trace drawing gives the terrain in it invisible freeform shapes
## (see [MDSFreeform]).

const SHADER := preload("res://addons/MetroidvaniaDeveloperSystem/shaders/drawing_cutout.gdshader")
## The most colors kept and cut together.
const MAX_COLORS := 16

@export var texture: Texture2D:
	set(v):
		texture = v
		_queue_update()
## The part of [member texture] shown (px). Empty: all of it.
@export var region := Rect2():
	set(v):
		region = v
		_queue_update()
## Colors that stay.
@export var keep_colors := PackedColorArray():
	set(v):
		keep_colors = v
		_queue_update()
## Colors made transparent where they are nearer than every kept color.
@export var cut_colors := PackedColorArray():
	set(v):
		cut_colors = v
		_queue_update()
## 0: a hard cut halfway between a kept and a cut color; 1: soft across the blend between them.
@export_range(0.0, 1.0) var softness := 0.35:
	set(v):
		softness = v
		_queue_update()

var _sprite: Sprite2D

func _ready() -> void:
	_update()

func _queue_update() -> void:
	if is_node_ready():
		_update()

func _update() -> void:
	if not _sprite:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		add_child(_sprite, false, Node.INTERNAL_MODE_BACK)
	_sprite.texture = texture
	_sprite.region_enabled = region.has_area()
	_sprite.region_rect = region
	if cut_colors.is_empty():
		_sprite.material = null
		return
	var m := _sprite.material as ShaderMaterial
	if not m:
		m = ShaderMaterial.new()
		m.shader = SHADER
		_sprite.material = m
	var palette := PackedVector4Array()
	for c in keep_colors:
		if palette.size() < MAX_COLORS:
			palette.append(Vector4(c.r, c.g, c.b, 1.0))
	for c in cut_colors:
		if palette.size() < MAX_COLORS:
			palette.append(Vector4(c.r, c.g, c.b, 0.0))
	var n := palette.size()
	palette.resize(MAX_COLORS)
	m.set_shader_parameter(&"palette", palette)
	m.set_shader_parameter(&"palette_size", n)
	m.set_shader_parameter(&"softness", softness)

## The internal sprite that draws the picture (null before it entered the tree).
func get_sprite() -> Sprite2D:
	return _sprite

## The picture's rectangle in its own coordinates.
func get_rect() -> Rect2:
	if region.has_area():
		return Rect2(Vector2.ZERO, region.size)
	return Rect2(Vector2.ZERO, texture.get_size() if texture else Vector2.ZERO)

## Whether [param p] (in this node's parent space) is on the picture's rectangle.
func has_point(p: Vector2) -> bool:
	return get_rect().has_point(transform.affine_inverse() * p)

# --- Data (undo, copies) ---------------------------------------------------------------------

func to_data() -> Dictionary:
	var d := {"texture": texture, "region": region, "keep": keep_colors.duplicate(), "cut": cut_colors.duplicate(),
		"softness": softness, "transform": transform, "z": z_index, "name": String(name)}
	var meta: Dictionary = {}
	for k in get_meta_list():
		meta[k] = get_meta(k)
	if not meta.is_empty():
		d.meta = meta
	return d

static func from_data(d: Dictionary) -> MDSDrawing:
	var p := MDSDrawing.new()
	apply_data(p, d)
	if not str(d.get("name", "")).is_empty():
		p.name = d.name
	return p

## Sets [param p] from [param d] (see [method to_data]), leaving equal values alone.
static func apply_data(p: MDSDrawing, d: Dictionary) -> void:
	# Packed arrays are shared by reference: the node gets its own copy of the snapshot's.
	var values := {"texture": d.texture, "region": d.region, "keep_colors": (d.keep as PackedColorArray).duplicate(), "cut_colors": (d.cut as PackedColorArray).duplicate(), "softness": d.softness,
		"transform": d.transform, "z_index": d.z}
	for k in values:
		if p.get(k) != values[k]:
			p.set(k, values[k])
	var meta: Dictionary = d.get("meta", {})
	for k in meta:
		if not p.has_meta(k) or p.get_meta(k) != meta[k]:
			p.set_meta(k, meta[k])
	for k in p.get_meta_list():
		if not meta.has(k):
			p.remove_meta(k)
