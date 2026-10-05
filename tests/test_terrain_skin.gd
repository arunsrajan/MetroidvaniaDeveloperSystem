extends "res://tests/test_case.gd"
## Brief 11: shader-driven freeform fills (terrain skins).

func _run() -> void:
	var st: IDPFreeformStyle = IDPFreeformStyle.builtins()[3]
	check(st.fill_material is ShaderMaterial and st.edge_material is ShaderMaterial, "the example style uses the addon's skin shader")
	check((st.edge_material as ShaderMaterial).get_shader_parameter("edge_pass") == true, "the edge material is the edge pass")
	# A room-sized block: its left and bottom edges lie on the room's boundary.
	var f := IDPFreeform.new()
	f.style = st
	f.smooth = false
	f.points = rect_points(Rect2(0, 400, 600, 248))
	add_child(f)
	var fill: Polygon2D = null
	var band: MeshInstance2D = null
	for c in f.get_children(true):
		if c is Polygon2D:
			fill = c
		elif c is MeshInstance2D:
			band = c
	check(fill != null and fill.material == st.fill_material, "the fill uses the fill material")
	check(band != null and band.material == st.edge_material, "a band mesh uses the edge material")
	if band:
		var arrays := band.mesh.surface_get_arrays(0)
		var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		check(verts.size() == 4 * 6, "the band runs along every edge (%d vertices)" % verts.size())
		var max_u := 0.0
		var min_v := 0.0
		for uv in uvs:
			max_u = maxf(max_u, uv.x)
			min_v = minf(min_v, uv.y)
		check_near(max_u, 2.0 * (600 + 248), 0.5, "UV.x runs along the outline in px")
		check_near(min_v, -st.edge_outside / st.edge_inside, 0.001, "UV.y is negative outside the shape")
		var top_faces := 0
		for i in verts.size():
			if verts[i].y < 400.0 and cols[i].r < 0.3:
				top_faces += 1
		check(top_faces > 0, "the top edge's vertices say they face up")
	f.free()
	# Edges on the room grid get no band.
	var skip := st.duplicate() as IDPFreeformStyle
	skip.skip_edges_on_grid = Vector2(1152, 648)
	var g := IDPFreeform.new()
	g.style = skip
	g.smooth = false
	g.points = rect_points(Rect2(0, 400, 600, 248))
	add_child(g)
	var mesh := IDPEdgeBand.edge_mesh(g.get_outline(), 34, 30, skip.skip_edges_on_grid)
	check(mesh != null and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 2 * 6, "edges on the room's boundary (x = 0, y = 648) are skipped")
	check(IDPEdgeBand.on_grid(Vector2(1152, 10), Vector2(1152, 300), Vector2(1152, 648)) and not IDPEdgeBand.on_grid(Vector2(1000, 10), Vector2(1000, 300), Vector2(1152, 648)), "on_grid knows the grid lines")
	g.free()
	# A curved outline: one closed band, mitred at its joints (no vertex flies off).
	var round := IDPFreeform.outline_of(PackedVector2Array([Vector2(0, 0), Vector2(200, -40), Vector2(400, 0), Vector2(300, 160), Vector2(100, 160)]))
	var m := IDPEdgeBand.edge_mesh(round, 34, 30)
	var far := 0.0
	for v in m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var d := 1e9
		for i in round.size():
			d = minf(d, Geometry2D.get_closest_point_to_segment(v, round[i], round[(i + 1) % round.size()]).distance_to(v))
		far = maxf(far, d)
	check(far <= 2.0 * 34.0 + 0.5, "the band's joints stay within twice its width (%.1f)" % far)
