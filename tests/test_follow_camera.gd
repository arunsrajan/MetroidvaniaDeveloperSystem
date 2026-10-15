extends "res://tests/test_case.gd"
## follow_camera and scroll_scale, the same for every background that has them (animated
## backgrounds, creatures, parallax backgrounds, machinery):
## - scroll_scale is how much it moves with the room as the camera moves: at 1 a point of it stays
##   at the same place in the world, at 0 at the same place on the screen, at 0.5 halfway; for
##   any view size and zoom (the drift was in 648 px units, so at another view height or zoom it
##   moved at the wrong pace);
## - follow_camera on covers the whole view, wherever the camera goes; off, only its rectangle,
##   and then it is fixed in the world whatever scroll_scale says: the camera moves nothing
##   (creatures not following live in their rectangle, spread over it, not on the screen);
## - machinery, by default, stays fixed in the world and covers its rectangle.
## (A rendered check measured the pictures moving 0, 80 and 160 px for a 160 px camera move at
## scroll_scale 0, 0.5 and 1, and 240 px at zoom 1.5.)

const VIEW := Vector2i(480, 270)
const KINDS := ["animated", "creatures", "parallax", "machinery"]

var host: SubViewport
var cam: Camera2D

func _run() -> void:
	host = SubViewport.new()
	host.size = VIEW
	add_child(host)
	cam = Camera2D.new()
	host.add_child(cam)
	cam.make_current()
	for kind in KINDS:
		await _scrolls(kind)
		await _still(kind)
		await _covers(kind)
	await _machinery_defaults()
	host.queue_free()
	await get_tree().process_frame

func _make(kind: String, s: float, follow: bool) -> MDSEnvironmentEffect:
	var e: MDSEnvironmentEffect
	match kind:
		"animated":
			e = MDSAnimatedBackground.new()
		"creatures":
			e = MDSCreatures.new()
		"parallax":
			var p := MDSParallaxBackground.new()
			for l in p.layers:
				l.scroll_scale = Vector2(s, s)
			e = p
		"machinery":
			e = MDSMachineryBackground.new()
	if kind != "parallax":
		e.set("scroll_scale", Vector2(s, s))
	e.set("follow_camera", follow)
	e.size = Vector2(4000, 2000)
	return e

## Where the world point [param at] shows in the background's own pattern (its units), with the
## camera where it is: what the shader draws there. Two camera places giving the same value mean
## the point stays fixed in the world.
func _pattern_at(e: MDSEnvironmentEffect, at: Vector2) -> Vector2:
	var m: ShaderMaterial = e.get_materials()[0]
	if e is MDSParallaxBackground or e is MDSMachineryBackground:
		return at - (m.get_shader_parameter("offset") as Vector2)
	# Animated backgrounds and creatures: from the middle of what they lie on, in its units, plus
	# the drift.
	var v: Vector4 = m.get_shader_parameter("view_rect")
	var unit: float = m.get_shader_parameter("unit")
	var mid := Vector2(v.x, v.y) + Vector2(v.z, v.w) * 0.5
	return ((at - mid) / unit + (m.get_shader_parameter("drift") as Vector2)) * unit

## The world point's place in the pattern after the camera moved 160 px, minus where it was:
## how far the pattern moved against the world (px).
func _slip(e: MDSEnvironmentEffect, zoom: float) -> float:
	cam.zoom = Vector2(zoom, zoom)
	cam.position = Vector2(2000, 1000)
	await get_tree().process_frame
	await get_tree().process_frame
	var at := Vector2(2100, 1050)
	var before := _pattern_at(e, at)
	cam.position.x += 160.0
	await get_tree().process_frame
	await get_tree().process_frame
	return (_pattern_at(e, at) - before).x

func _scrolls(kind: String) -> void:
	for run in [[1.0, 1.0], [0.0, 1.0], [0.5, 1.0], [1.0, 1.5], [0.5, 2.0]]:
		var s: float = run[0]
		var zoom: float = run[1]
		var e := _make(kind, s, true)
		host.add_child(e)
		var slip: float = await _slip(e, zoom)
		# The pattern slips against the world, with the camera, by the share it stays behind: none
		# at scroll 1, all of the camera's move at 0 (a fixed point then shows 160 px further back
		# in the pattern).
		check_near(slip, -160.0 * (1.0 - s), 0.5, "%s at scroll_scale %.1f, zoom %.1f: a point of it moves %d%% with the room" % [kind, s, zoom, roundi(s * 100.0)])
		e.queue_free()
		await get_tree().process_frame

## Not following the camera: fixed in the world, whatever scroll_scale says.
func _still(kind: String) -> void:
	for run in [[0.0, 1.0], [0.5, 1.0], [0.0, 1.5]]:
		var s: float = run[0]
		var zoom: float = run[1]
		var e := _make(kind, s, false)
		host.add_child(e)
		var at := Vector2(2100, 1050)
		var seen: Vector2 = (e as MDSCreatures).to_view(at) if e is MDSCreatures else Vector2.ZERO
		var slip: float = await _slip(e, zoom)
		check_near(slip, 0.0, 0.5, "%s not following the camera, at scroll_scale %.1f and zoom %.1f: fixed in the world" % [kind, s, zoom])
		if e is MDSCreatures:
			var c := e as MDSCreatures
			check((c.to_view(at) - seen).length() < 0.0001, "a place in the room stays the same place among the creatures")
			var widest := 0.0
			for q in c.creature_positions():
				widest = maxf(widest, absf(q.x))
			check(widest > 1.0 and is_equal_approx(c.frame_unit(), MDSEnvironmentEffect.screen_height()), "they live all over their rectangle, a screen high a unit (%.2f)" % widest)
		e.queue_free()
		await get_tree().process_frame

func _covers(kind: String) -> void:
	cam.zoom = Vector2.ONE
	cam.position = Vector2(-3000, -2000)
	for follow in [true, false]:
		var e := _make(kind, 1.0, follow)
		host.add_child(e)
		await get_tree().process_frame
		await get_tree().process_frame
		var quad: Polygon2D = e._quads[0]
		var box := MDSGeometry.bounds(quad.polygon)
		var view := Rect2(cam.position - Vector2(VIEW) * 0.5, Vector2(VIEW))
		if follow:
			check(box.grow(1.0).encloses(view), "%s following the camera covers the view, far outside its rectangle (%s)" % [kind, box])
		else:
			check(box.is_equal_approx(e.get_effect_rect()), "%s not following covers only its rectangle" % kind)
		e.queue_free()
		await get_tree().process_frame

func _machinery_defaults() -> void:
	var m := MDSMachineryBackground.new()
	check(m.scroll_scale == Vector2.ONE and not m.follow_camera, "machinery is fixed in the world by default, over its rectangle")
	m.size = Vector2(2304, 1296)
	host.add_child(m)
	cam.zoom = Vector2.ONE
	var moved := false
	for step in 6:
		cam.position = Vector2(step * 300.0, step * 120.0)
		cam.zoom = Vector2.ONE * (1.0 + step * 0.2)
		await get_tree().process_frame
		if (m.get_materials()[0] as ShaderMaterial).get_shader_parameter("offset") != Vector2.ZERO:
			moved = true
	check(not moved, "however the camera moves and zooms, it isn't moved")
	m.queue_free()
	await get_tree().process_frame
