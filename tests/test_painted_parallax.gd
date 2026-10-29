extends "res://tests/test_case.gd"
## The Painted Parallax pack: ten MDSParallaxBackground scenes built from painted picture layers.
## Each loads as a background a Parallax field can name, starts with a sky, stacks its pictures
## farthest (slowest) first, and keeps its foreground strips along the room's edges.

const DIR := "res://asset_packs/painted_parallax/backgrounds"

func _run() -> void:
	var scenes := Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool: return f.ends_with(".tscn"))
	check(scenes.size() == 10, "ten backgrounds (%d)" % scenes.size())
	for f: String in scenes:
		var path := DIR + "/" + f
		check(MDSEnvironment.check_parallax(path).is_empty(), "%s is a valid Parallax value" % f)
		var bg := (load(path) as PackedScene).instantiate() as MDSParallaxBackground
		if not check(bg != null, "%s holds an MDSParallaxBackground" % f):
			continue
		check(bg.preset == MDSParallaxBackground.Preset.CUSTOM and bg.layers.size() >= 4, "%s keeps its own layers (%d)" % [f, bg.layers.size()])
		check(bg.layers[0].kind == MDSParallaxLayer.Kind.SKY and bg.layers[0].scroll_scale == Vector2.ZERO, "%s starts with a sky that stays put" % f)
		var pictures := true
		var slower_first := true
		for i in range(1, bg.layers.size()):
			var l := bg.layers[i]
			pictures = pictures and l.kind == MDSParallaxLayer.Kind.PICTURE and l.picture != null and l.color.a == 1.0
			if i > 1:
				slower_first = slower_first and l.scroll_scale.x > bg.layers[i - 1].scroll_scale.x
		check(pictures, "%s: every other layer is a loaded, opaque-tinted picture" % f)
		check(slower_first, "%s: nearer layers move more" % f)
		for l in bg.foreground_layers:
			check(l.picture != null and l.scroll_scale.x > 1.0 and (l.hang == (l.horizon < 0.5)), "%s: its foreground strips pass in front, the top one hanging" % f)
		bg.free()
	var built := MDSEnvironment.build_parallax(DIR + "/" + str(scenes[0]), Rect2(0, 0, 1152, 648))
	var inner := built.get_child(0) as MDSParallaxBackground if built and built.get_child_count() > 0 else null
	check(inner != null and inner.layers.size() >= 4 and inner.fit_room, "a room's Parallax field builds it with its layers, fitted to the room")
	if built:
		built.free()
