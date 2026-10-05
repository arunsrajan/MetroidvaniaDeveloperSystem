@tool
class_name IDPRoomObjects
extends RefCounted
## The things in a room scene that are not its terrain or scenery: save points, shops,
## characters, enemies, props, mechanisms. The freeform tools keep rock and scenery clear of
## them, the room checks stand them on the ground, and the dressing tools fit and separate
## them. No editor dependencies.
##
## Designers can steer it with groups or metadata:
## - [code]idp_protected[/code] (group or metadata): an area nothing may grow into. A
##   [ReferenceRect] or [Control] protects its rectangle; any other node its visuals or its
##   collision shapes.
## - [code]idp_stands[/code] (group, or metadata true/false): the node stands on the floor (or,
##   with false, doesn't, though its group says so).
## - [code]idp_scenery[/code] (group or metadata): the node is scenery, not an object.

const STAND_GROUPS: PackedStringArray = ["save_point", "savepoint", "save", "checkpoint", "bench", "shop", "merchant", "vendor", "trader", "npc", "player_spawn", "idp_stands"]
const BIG_GROUPS: PackedStringArray = ["boss", "bosses", "mini_boss"]
## Item groups of the Room view (shapes and stamps), and other containers of scenery.
const SCENERY_NAMES: PackedStringArray = ["FreeformBack", "StampsBack", "Freeform", "StampsFront", "FreeformFront", "StampsForeground", "MapBounds", "Gates", "IDPItems"]
## Footprint of an object with nothing visible (a spawn marker, an empty Node2D): above its
## origin, as if it stood there.
const DEFAULT_SIZE := Vector2(64, 96)

## Whether [param node] is terrain or scenery (never an object): tile layers, freeform shapes
## and stamps, cameras, gates, parallax, audio...
static func is_scenery(node: Node) -> bool:
	if node.is_in_group(&"idp_scenery") or node.has_meta(&"idp_scenery") or node.has_meta(&"idp_blockout"):
		return true
	if node is TileMapLayer or node.is_class("TileMap") or node is IDPFreeform or IDPRoomPainter.is_stamp(node) or node is IDPGate:
		return true
	if node is Camera2D or node is CanvasLayer or node is Parallax2D or node is ParallaxBackground or node is CanvasModulate:
		return true
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is Timer or node is AnimationPlayer or node is Light2D or node is LightOccluder2D:
		return true
	var script := node.get_script() as Script
	if String(node.name) in SCENERY_NAMES or node.name == &"RoomInstance":
		return true
	if script and (script.get_global_name() in [&"IDPRoomCamera", &"IDPDepth25D", &"IDPBackdropView"] or script.resource_path.ends_with("RoomInstance.gd")):
		return true
	if node is StaticBody2D and not _has_visual(node):
		return true # an invisible wall or the terrain's body
	# Backdrops: named so, or big plain art drawn behind the room (props behind the player are
	# small).
	for word in ["background", "backdrop", "parallax", "sky"]:
		if String(node.name).to_lower().contains(word):
			return true
	if (node is Polygon2D or node is Sprite2D) and (node as CanvasItem).z_index < 0 and script == null \
			and node.scene_file_path.is_empty() and node.get_groups().filter(func(g: StringName) -> bool: return not String(g).begins_with("_")).is_empty():
		var size := visual_rect(node, node).size
		if size.x >= 512.0 and size.y >= 512.0:
			return true
	return false

static func _has_visual(node: Node) -> bool:
	for c in node.get_children():
		if c is Sprite2D or c is AnimatedSprite2D or c is Polygon2D or c is MeshInstance2D:
			return true
	return false

## The objects of a room: Node2Ds under [param root] that are not scenery and have something
## to show or collide with, or a group, script or metadata that makes them one. A node that
## counts is taken whole (its children belong to it).
static func objects(root: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for c in root.get_children():
		_collect(c, out)
	return out

static func _collect(node: Node, out: Array[Node2D]) -> void:
	if is_scenery(node):
		return
	if node is Node2D and _is_object(node):
		out.append(node)
		return
	for c in node.get_children():
		_collect(c, out)

static func _is_object(node: Node2D) -> bool:
	if not node.scene_file_path.is_empty() or node.get_script() != null:
		return true
	if is_protected(node) or stands(node):
		return true
	if not node.get_groups().filter(func(g: StringName) -> bool: return not String(g).begins_with("_")).is_empty():
		return true
	return node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D or node is CollisionObject2D or node is Path2D or node is GPUParticles2D or node is CPUParticles2D

static func is_protected(node: Node) -> bool:
	return node.is_in_group(&"idp_protected") or bool(node.get_meta(&"idp_protected", false))

## Whether [param node] stands on the floor (save points, shops, NPCs, spawn points...).
static func stands(node: Node) -> bool:
	if node.has_meta(&"idp_stands"):
		return bool(node.get_meta(&"idp_stands"))
	for g in STAND_GROUPS:
		if node.is_in_group(g):
			return true
	var n := String(node.name).to_lower()
	return n.contains("savepoint") or n.contains("bench") or n.contains("checkpoint") or n.contains("shop")

static func is_big(node: Node) -> bool:
	for g in BIG_GROUPS:
		if node.is_in_group(g):
			return true
	return false

## [param node]'s transform relative to [param root] (scenes may be outside the tree).
static func local_transform(node: Node, root: Node) -> Transform2D:
	var xform := Transform2D.IDENTITY
	var n := node
	while n and n != root:
		if n is Node2D:
			xform = (n as Node2D).transform * xform
		elif n is Control:
			xform = Transform2D(0.0, (n as Control).position) * xform
		n = n.get_parent()
	return xform

## The area [param node] covers, relative to [param root]: its sprites, polygons, controls and
## (for non-static bodies and areas) collision shapes, with its children. Without any, a
## [constant DEFAULT_SIZE] box standing on its origin. With [param trim], sprites count only
## their visible pixels (not the transparent margin around the art).
static func visual_rect(node: Node, root: Node, trim := false) -> Rect2:
	var acc := [Rect2(), false, trim] # bounds, found anything, trim
	_visual(node, root, acc)
	if acc[1]:
		return acc[0]
	var p := local_transform(node, root).origin
	return Rect2(p - Vector2(DEFAULT_SIZE.x / 2.0, DEFAULT_SIZE.y), DEFAULT_SIZE)

static func _add(rect: Rect2, acc: Array) -> void:
	if not rect.has_area():
		return
	acc[0] = rect if not acc[1] else (acc[0] as Rect2).merge(rect)
	acc[1] = true

static func _visual(node: Node, root: Node, acc: Array) -> void:
	if node != root and node is CanvasItem and not (node as CanvasItem).visible and not node is CollisionObject2D:
		return
	var xform := local_transform(node, root)
	if node is Sprite2D:
		_add(xform * (_trimmed_rect(node) if acc[2] else (node as Sprite2D).get_rect()), acc)
	elif node is AnimatedSprite2D:
		var a := node as AnimatedSprite2D
		if a.sprite_frames and a.sprite_frames.has_animation(a.animation) and a.sprite_frames.get_frame_count(a.animation) > 0:
			var tex := a.sprite_frames.get_frame_texture(a.animation, clampi(a.frame, 0, a.sprite_frames.get_frame_count(a.animation) - 1))
			if tex:
				var size := tex.get_size()
				var pos := a.offset - (size / 2.0 if a.centered else Vector2.ZERO)
				_add(xform * Rect2(pos, size), acc)
	elif node is Polygon2D and (node as Polygon2D).polygon.size() >= 3:
		_add(xform * IDPGeometry.bounds((node as Polygon2D).polygon), acc)
	elif node is Control and node != root:
		_add(Rect2(xform.origin, (node as Control).size), acc)
	elif node is CollisionShape2D and (node as CollisionShape2D).shape and not node.get_parent() is StaticBody2D:
		_add(xform * (node as CollisionShape2D).shape.get_rect(), acc)
	elif node is CollisionPolygon2D and not node.get_parent() is StaticBody2D and (node as CollisionPolygon2D).polygon.size() >= 3:
		_add(xform * IDPGeometry.bounds((node as CollisionPolygon2D).polygon), acc)
	for c in node.get_children():
		if not IDPRoomPainter.is_stamp(c):
			_visual(c, root, acc)

static var _used_rects: Dictionary = {}

## The visible (not transparent) part of [param tex], cached per texture.
static func used_rect(tex: Texture2D) -> Rect2:
	var key: Variant = tex.resource_path if not tex.resource_path.is_empty() else tex.get_instance_id()
	if _used_rects.has(key):
		return _used_rects[key]
	var r := Rect2(Vector2.ZERO, tex.get_size())
	# Big art isn't worth decoding just for its margin (scans stay quick).
	if tex.get_width() * tex.get_height() > 2048 * 2048:
		_used_rects[key] = r
		return r
	var img := tex.get_image()
	if img:
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		var used := img.get_used_rect()
		if used.has_area():
			r = Rect2(used)
	_used_rects[key] = r
	return r

static func _trimmed_rect(s: Sprite2D) -> Rect2:
	var r := s.get_rect()
	if not s.texture or s.region_enabled or s.hframes > 1 or s.vframes > 1:
		return r
	var used := used_rect(s.texture)
	if s.flip_h:
		used.position.x = s.texture.get_size().x - used.end.x
	if s.flip_v:
		used.position.y = s.texture.get_size().y - used.end.y
	return Rect2(r.position + used.position, used.size)

## Where [param node] stands: the bottom middle of its visual rect.
static func feet(node: Node, root: Node) -> Vector2:
	var r := visual_rect(node, root)
	return Vector2(r.get_center().x, r.end.y)

## Areas of a room that nothing may grow into or be placed over: every object's visual rect
## grown by [param margin] (more for objects that stand, which need room around them), and
## the areas designers marked [code]idp_protected[/code].
static func protected_rects(root: Node, margin := 40.0) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var objs := objects(root)
	for o in objs:
		var r := visual_rect(o, root)
		if stands(o):
			r = r.grow_individual(margin * 1.5, margin * 2.0, margin * 1.5, margin * 0.5)
		elif is_big(o):
			r = r.grow(margin * 3.0)
		else:
			r = r.grow(margin)
		out.append(r)
	for n in root.find_children("*", "", true, false):
		if is_protected(n) and not n in objs:
			out.append(visual_rect(n, root))
	return out
