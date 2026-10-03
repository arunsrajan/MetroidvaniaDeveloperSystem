@tool
class_name IDPExporters
extends RefCounted
## Text exports of the map: JSON (tools/pipelines), Graphviz DOT (room graph) and a
## Markdown design document (reviews, sharing with the team).

static func to_json(model: IDPMapModel, ann: IDPAnnotations, analysis: IDPAnalysis, scene_db: Dictionary, filter_categories: Array) -> String:
	var rooms: Array = []
	for room: IDPMapModel.Room in model.rooms.values():
		var info := analysis.get_info(room.id)
		rooms.append({
			"id": room.id,
			"scene_path": room.scene_path,
			"layer": room.layer,
			"cells": room.cells.map(func(c: Vector3i) -> Array: return [c.x, c.y]),
			"irregular": room.is_irregular(),
			"name": info.get("name", ""),
			"type": info.get("type", ""),
			"area": info.get("area", ""),
			"status": info.get("status", ""),
			"boss_names": Array(info.get("boss_names", PackedStringArray())),
			"grants": Array(info.get("grants", PackedStringArray())),
			"sphere": analysis.sphere_of.get(room.id, -1),
			"save_distance": analysis.save_distance.get(room.id, -1),
			"neighbors": room.get_neighbor_rooms().map(func(r: IDPMapModel.Room) -> String: return r.id),
		})
	var doors: Array = []
	for door: IDPMapModel.Door in model.doors.values():
		doors.append({
			"key": door.key,
			"a": door.a_room.id,
			"b": door.b_room.id if door.b_room else "",
			"direction": IDPMapModel.DIR_NAMES[door.a_dir],
			"border": door.get_border_type(),
			"one_sided": door.is_one_sided(),
			"one_way_from": analysis.get_one_way_from(door.key),
			"requires": Array(analysis.get_door_requires(door.key)),
		})
	# Legacy keys ("layers", "cells", "scene_database") kept for existing consumers.
	var cells: Dictionary = {}
	for coords: Vector3i in model.cells:
		var cell: IDPMapModel.Cell = model.cells[coords]
		cells["%d,%d,%d" % [coords.z, coords.x, coords.y]] = {
			"x": coords.x, "y": coords.y, "layer": coords.z,
			"connections": Array(cell.borders),
			"cell_color": "#" + cell.color.to_html(false) if cell.color.a > 0 else "",
			"symbol": cell.symbol,
			"scene_uid": cell.scene_uid,
			"scene_path": cell.room.scene_path,
			"room_id": cell.room.id,
		}
	var layers: Array = model.layers.map(func(l: int) -> Dictionary: return {"idx": l, "layer_name": model.get_layer_name(l)})
	return JSON.stringify({
		"version": "2.0",
		"source_file": model.source_path,
		"export_date": Time.get_datetime_string_from_system(),
		"layers": layers,
		"cells": cells,
		"rooms": rooms,
		"doors": doors,
		"annotations": ann.data,
		"progression": progression_to_dict(analysis),
		"scene_database": sanitize_scene_db(scene_db),
		"filter_categories": filter_categories,
	}, "\t")

## Drops images and converts vectors so the scan results serialize cleanly.
static func sanitize_scene_db(scene_db: Dictionary) -> Dictionary:
	var ret: Dictionary = {}
	for path in scene_db:
		ret[path] = _sanitize(scene_db[path])
	return ret

static func _sanitize(value: Variant) -> Variant:
	if value is Dictionary:
		var d: Dictionary = {}
		for k in value:
			if k in ["silhouette", "silhouette_rect"]:
				continue
			d[k] = _sanitize(value[k])
		return d
	if value is Array or value is PackedStringArray:
		var a: Array = []
		for item in value:
			a.append(_sanitize(item))
		return a
	if value is Vector2 or value is Vector2i:
		return [value.x, value.y]
	if value is Object:
		return null
	return value

## Room graph for Graphviz, clustered by area. Works for both modes.
static func to_dot(analysis: IDPAnalysis, area_colors := {}) -> String:
	var graph := analysis.graph
	var lines: PackedStringArray = ["graph MetroidvaniaMap {", "\tgraph [overlap=false, splines=true, fontname=\"Helvetica\"];", "\tnode [style=filled, fontname=\"Helvetica\", fontcolor=white];"]
	var by_area: Dictionary = {}
	for room: IDPGraph.GRoom in graph.rooms.values():
		if not room.has_scene:
			continue
		var area: String = analysis.get_info(room.id).get("area", "")
		if not by_area.has(area):
			by_area[area] = []
		by_area[area].append(room)
	var cluster := 0
	for area in by_area:
		var indent := "\t"
		if not area.is_empty():
			lines.append("\tsubgraph cluster_%d {" % cluster)
			var area_color: Color = area_colors.get(area, Color.GRAY)
			lines.append("\t\tlabel=%s; color=\"#%s\";" % [_q(area), area_color.to_html(false)])
			indent = "\t\t"
			cluster += 1
		for room: IDPGraph.GRoom in by_area[area]:
			var info := analysis.get_info(room.id)
			var color: Color = IDPMapCanvas.TYPE_COLORS.get(info.get("type", ""), IDPMapCanvas.TYPE_COLORS[""])
			var shape := "box"
			if info.get("is_boss", false):
				shape = "doubleoctagon"
			elif info.get("is_save", false):
				shape = "house"
			var label: String = info.get("name", room.name)
			if info.get("is_boss", false) and not info.boss_names.is_empty():
				label += "\n(" + ", ".join(info.boss_names) + ")"
			if not info.get("grants", PackedStringArray()).is_empty():
				label += "\n+" + ", ".join(info.grants)
			lines.append("%s%s [label=%s, shape=%s, fillcolor=\"#%s\"%s];" % [indent, _q(room.id), _q(label), shape, color.to_html(false), ", penwidth=3" if room.id == analysis.start_room_id else ""])
		if not area.is_empty():
			lines.append("\t}")
	for e: IDPGraph.GEdge in graph.edges:
		if e.b.is_empty() or not graph.rooms[e.a].has_scene or not graph.rooms[e.b].has_scene:
			continue
		var attrs: PackedStringArray = []
		var reqs := analysis.get_door_requires(e.key)
		if not reqs.is_empty():
			attrs.append("label=%s" % _q(", ".join(reqs)))
			attrs.append("color=\"#%s\"" % IDPMapCanvas.ability_color(reqs[0]).to_html(false))
			attrs.append("penwidth=2")
		var one_way := analysis.get_one_way_from(e.key)
		if not one_way.is_empty():
			# Directed edge drawn as an arrow from the side that can pass.
			attrs.append("dir=forward" if one_way == e.a else "dir=back")
			attrs.append("style=dashed")
		lines.append("\t%s -- %s%s;" % [_q(e.a), _q(e.b), " [%s]" % ", ".join(attrs) if not attrs.is_empty() else ""])
	for link in analysis.annotations.get_links():
		var reqs: Array = link.get("requires", [])
		var label: String = link.get("note", "")
		if not reqs.is_empty():
			label += (" " if not label.is_empty() else "") + "[" + ", ".join(reqs) + "]"
		lines.append("\t%s -- %s [style=dotted, penwidth=2, label=%s];" % [_q(link.a), _q(link.b), _q(label)])
	lines.append("}")
	return "\n".join(lines)

static func _q(s: String) -> String:
	# Real newlines become DOT line breaks.
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""

## Progression summary shared by the JSON exports.
static func progression_to_dict(analysis: IDPAnalysis) -> Dictionary:
	return {
		"start_room": analysis.start_room_id,
		"spheres": analysis.spheres.map(func(s: Dictionary) -> Dictionary: return {"index": s.index, "rooms": s.rooms, "gained": Array(s.gained)}),
		"locked": analysis.locked,
		"disconnected": analysis.disconnected,
		"dead_ends": analysis.dead_ends,
		"chokepoints": analysis.chokepoints,
		"hubs": analysis.hubs,
		"save_distance": analysis.save_distance,
	}

## Design document. [param summary] is an ordered Dictionary of headline numbers and
## [param size_of] an optional Callable(room_id) -> String for the size column.
static func to_markdown(title: String, summary: Dictionary, ann: IDPAnnotations, analysis: IDPAnalysis, issues: Array, size_of := Callable()) -> String:
	var md: PackedStringArray = []
	md.append("# Map design document: %s" % title)
	md.append("")
	md.append("Generated %s by Interactive Dev Panel." % Time.get_datetime_string_from_system(false, true))
	md.append("")
	md.append("| " + " | ".join(summary.keys()) + " |")
	md.append("|" + "---|".repeat(summary.size()))
	md.append("| " + " | ".join(summary.values().map(func(v: Variant) -> String: return str(v))) + " |")
	md.append("")

	md.append("## Progression")
	md.append("")
	for s in analysis.spheres:
		var names: Array = s.rooms.map(func(id: String) -> String: return analysis.get_room_name(id))
		names.sort()
		md.append("**Sphere %d**%s: %s" % [s.index, " (unlocked by %s)" % ", ".join(analysis.spheres[s.index - 1].gained) if s.index > 0 else " (start)", ", ".join(names)])
		for e in s.entries:
			md.append("- Backtrack: %s -> %s needs %s" % [analysis.get_room_name(e.from), analysis.get_room_name(e.to), ", ".join(e.requires)])
		if not s.gained.is_empty():
			md.append("- Grants: %s" % ", ".join(s.gained))
		md.append("")
	if not analysis.locked.is_empty():
		md.append("**Locked:** " + ", ".join(analysis.locked.map(func(id: String) -> String: return analysis.get_room_name(id))))
		md.append("")

	md.append("## Bosses")
	md.append("")
	md.append("| Boss | Room | Area | Sphere | Rooms to nearest save |")
	md.append("|---|---|---|---|---|")
	for id in analysis.room_info:
		var info: Dictionary = analysis.room_info[id]
		if info.is_boss:
			md.append("| %s | %s | %s | %s | %s |" % [", ".join(info.boss_names) if not info.boss_names.is_empty() else "?", info.name, info.area, analysis.sphere_of.get(id, "-"), analysis.save_distance.get(id, "-")])
	md.append("")

	md.append("## Rooms by area")
	var by_area: Dictionary = {}
	for room: IDPGraph.GRoom in analysis.graph.rooms.values():
		if not room.has_scene:
			continue
		var area: String = analysis.get_info(room.id).get("area", "")
		if not by_area.has(area):
			by_area[area] = []
		by_area[area].append(room.id)
	for area in by_area:
		md.append("")
		md.append("### %s" % (area if not area.is_empty() else "No area"))
		md.append("")
		md.append("| Room | Type | Status | Size | Grants | Notes |")
		md.append("|---|---|---|---|---|---|")
		for id in by_area[area]:
			var info := analysis.get_info(id)
			var notes: String = ann.get_room_value(id, "notes", "")
			md.append("| %s | %s | %s | %s | %s | %s |" % [info.name, str(info.type).capitalize(), str(info.status).capitalize(), size_of.call(id) if size_of.is_valid() else "", ", ".join(info.grants), notes.replace("\n", " ").replace("|", "/")])
	md.append("")

	if not issues.is_empty():
		md.append("## Open issues")
		md.append("")
		for i in issues:
			md.append("- **%s** (%s): %s" % [["Info", "Warning", "Error"][i.severity], i.category, i.message])
	return "\n".join(md) + "\n"
