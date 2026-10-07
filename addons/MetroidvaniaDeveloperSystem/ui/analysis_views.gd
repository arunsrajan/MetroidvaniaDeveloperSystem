@tool
class_name MDSAnalysisViews
extends RefCounted
## The Progress, Issues and Stats sidebar tabs, shared by the MetSys and non-linear panels.
##
## The host panel implements:
## [codeblock]
## func ui_select_room(id: String) -> void               # select + center
## func ui_focus_rooms(ids: Array, route: Array) -> void # highlight (route: [from, to] or [])
## func ui_jump_to_issue(issue: Dictionary) -> void
## func ui_set_start_from_selection() -> void
## func ui_stats_header() -> String                      # BBCode lines on top of Stats
## func ui_area_color(area: String) -> Color
## [/codeblock]

var host: Object
var analysis: MDSAnalysis
var issues: Array = []
var progression_header: Label
var progression_tree: Tree
var issues_summary: Label
var issues_tree: Tree
var stats_text: RichTextLabel
var _sidebar: TabContainer
var _issues_tab: Control

func _init(p_host: Object, sidebar: TabContainer) -> void:
	host = p_host
	_sidebar = sidebar
	_build_progression_tab()
	_build_issues_tab()
	_build_stats_tab()

func _build_progression_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Progress"
	_sidebar.add_child(box)
	progression_header = MDSUi.label("")
	progression_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(progression_header)
	var set_start := MDSUi.button("Use selected room as start", "Progression is computed from this room")
	set_start.pressed.connect(func() -> void: host.ui_set_start_from_selection())
	box.add_child(set_start)
	progression_tree = Tree.new()
	progression_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	progression_tree.hide_root = true
	progression_tree.item_selected.connect(_on_progression_item_selected)
	box.add_child(progression_tree)
	box.add_child(MDSUi.hint("Select a sphere, ability or group to highlight it on the map."))

func _build_issues_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Issues"
	_issues_tab = box
	_sidebar.add_child(box)
	issues_summary = MDSUi.label("")
	issues_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(issues_summary)
	issues_tree = Tree.new()
	issues_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	issues_tree.hide_root = true
	issues_tree.item_selected.connect(func() -> void:
		var meta: Dictionary = issues_tree.get_selected().get_metadata(0)
		if not meta.is_empty():
			host.ui_jump_to_issue(meta))
	box.add_child(issues_tree)

func _build_stats_tab() -> void:
	stats_text = RichTextLabel.new()
	stats_text.name = "Stats"
	stats_text.bbcode_enabled = true
	stats_text.selection_enabled = true
	stats_text.meta_clicked.connect(func(meta: Variant) -> void:
		var s := str(meta)
		if s.begins_with("room:"):
			host.ui_select_room(s.trim_prefix("room:")))
	_sidebar.add_child(stats_text)

func refresh(p_analysis: MDSAnalysis, p_issues: Array, scanned: bool) -> void:
	analysis = p_analysis
	issues = p_issues
	_refresh_progression()
	_refresh_issues(scanned)
	_refresh_stats()

# --- Progress --------------------------------------------------------------------------

func _refresh_progression() -> void:
	progression_tree.clear()
	if not analysis:
		return
	progression_header.text = "Start: %s" % (analysis.get_room_name(analysis.start_room_id) if not analysis.start_room_id.is_empty() else "(none)")
	var root := progression_tree.create_item()
	for s in analysis.spheres:
		var head := progression_tree.create_item(root)
		var text := "Sphere %d: %d room(s)" % [s.index, s.rooms.size()]
		if s.index > 0:
			text += ", opened by %s" % ", ".join(analysis.spheres[s.index - 1].gained)
		if not s.gained.is_empty():
			text += "; grants %s" % ", ".join(s.gained)
		head.set_text(0, text)
		head.set_tooltip_text(0, text)
		head.set_custom_color(0, MDSMapCanvas.sphere_color(s.index, analysis.spheres.size()).lightened(0.3))
		head.set_metadata(0, {"rooms": s.rooms})
		for e in s.entries:
			var entry := progression_tree.create_item(head)
			entry.set_text(0, "Backtrack: %s -> %s  [%s]" % [analysis.get_room_name(e.from), analysis.get_room_name(e.to), ", ".join(e.requires)])
			entry.set_tooltip_text(0, "With %s you can now go back to %s and enter %s" % [", ".join(e.requires), analysis.get_room_name(e.from), analysis.get_room_name(e.to)])
			entry.set_custom_color(0, Color(1, 0.85, 0.4))
			entry.set_metadata(0, {"rooms": [e.from, e.to], "route": [analysis.start_room_id, e.from]})
		for id in s.rooms:
			_add_room_item(head, id)
		head.collapsed = s.rooms.size() > 12
	_add_room_group(root, "Locked (%d): never unlocked" % analysis.locked.size(), analysis.locked, Color(1, 0.5, 0.5))
	var disconnected := analysis.disconnected.filter(func(id: String) -> bool: return analysis.graph.get_room(id).has_scene)
	_add_room_group(root, "Not connected to start (%d)" % disconnected.size(), disconnected, Color(0.7, 0.7, 0.7))

	var abilities := progression_tree.create_item(root)
	var all: PackedStringArray = analysis.all_granted.duplicate()
	for a in analysis.all_required:
		if not a in all:
			all.append(a)
	abilities.set_text(0, "Abilities & keys (%d)" % all.size())
	abilities.set_metadata(0, {})
	for a in all:
		var sources := analysis.get_ability_sources(a)
		var uses := analysis.get_ability_uses(a)
		var item := progression_tree.create_item(abilities)
		var where := ", ".join(sources.map(func(id: String) -> String: return "%s (sphere %s)" % [analysis.get_room_name(id), analysis.sphere_of.get(id, "?")])) if not sources.is_empty() else "NOT GRANTED ANYWHERE"
		item.set_text(0, "%s: found in %s; opens %d passage(s)" % [a, where, uses.size()])
		item.set_tooltip_text(0, item.get_text(0))
		item.set_custom_color(0, MDSMapCanvas.ability_color(a))
		var highlight: Array = sources.duplicate()
		for u in uses:
			highlight.append(u.a)
			if not u.b.is_empty():
				highlight.append(u.b)
			var use_item := progression_tree.create_item(item)
			use_item.set_text(0, "%s <-> %s" % [analysis.get_room_name(u.a), analysis.get_room_name(u.b) if not u.b.is_empty() else "?"])
			use_item.set_metadata(0, {"rooms": [u.a, u.b] if not u.b.is_empty() else [u.a]})
		item.set_metadata(0, {"rooms": highlight})

	var objectives := analysis.get_objectives()
	if not objectives.is_empty():
		var head := progression_tree.create_item(root)
		head.set_text(0, "Objectives (%d)" % objectives.size())
		head.set_metadata(0, {})
		for o in objectives:
			var item := progression_tree.create_item(head)
			item.set_text(0, "%s: %s" % [o.area, _objective_status(o)])
			item.set_tooltip_text(0, "%s\nDone when: %s" % [o.text, o.condition if not str(o.condition).is_empty() else "game code calls complete_objective()"])
			if not str(o.problem).is_empty():
				item.set_custom_color(0, Color(1, 0.5, 0.5))
			item.set_metadata(0, {"rooms": o.rooms})

	var topo := progression_tree.create_item(root)
	topo.set_text(0, "Map topology")
	topo.set_metadata(0, {})
	_add_room_group(topo, "Dead ends (%d)" % analysis.dead_ends.size(), analysis.dead_ends, Color.WHITE, true)
	_add_room_group(topo, "Chokepoints (%d): removing one splits the map" % analysis.chokepoints.size(), analysis.chokepoints, Color.WHITE, true)
	_add_room_group(topo, "Hubs (%d): 4+ neighbors" % analysis.hubs.size(), analysis.hubs, Color.WHITE, true)

## "text - how it completes" for a [method MDSAnalysis.get_objectives] entry.
func _objective_status(o: Dictionary) -> String:
	var text := str(o.text) if not str(o.text).is_empty() else "(no text)"
	if not str(o.problem).is_empty():
		return "%s - NEVER COMPLETES: %s" % [text, o.problem]
	if str(o.kind).is_empty():
		return "%s - completed by game code" % text
	var where := ", ".join(o.rooms.map(analysis.get_room_name)) if not o.rooms.is_empty() else "?"
	return "%s - %s %s in %s%s" % [text, o.kind, o.target, where, " (sphere %d)" % o.sphere if o.sphere >= 0 else ""]

func _add_room_item(parent: TreeItem, id: String) -> void:
	var item := progression_tree.create_item(parent)
	var info := analysis.get_info(id)
	item.set_text(0, info.get("name", id))
	item.set_icon(0, MDSUi.type_icon(info.get("type", "")))
	item.set_metadata(0, {"room": id})

func _add_room_group(parent: TreeItem, text: String, ids: Array, color: Color, collapsed := false) -> void:
	if ids.is_empty():
		return
	var head := progression_tree.create_item(parent)
	head.set_text(0, text)
	head.set_custom_color(0, color)
	head.set_metadata(0, {"rooms": ids})
	for id in ids:
		_add_room_item(head, id)
	head.collapsed = collapsed

func _on_progression_item_selected() -> void:
	var meta: Dictionary = progression_tree.get_selected().get_metadata(0)
	if meta.has("room"):
		host.ui_select_room(meta.room)
	else:
		host.ui_focus_rooms(meta.get("rooms", []), meta.get("route", []))

# --- Issues ----------------------------------------------------------------------------

func _refresh_issues(scanned: bool) -> void:
	issues_tree.clear()
	var root := issues_tree.create_item()
	var counts := [0, 0, 0]
	var by_category: Dictionary = {}
	for issue in issues:
		counts[issue.severity] += 1
		if not by_category.has(issue.category):
			var head := issues_tree.create_item(root)
			head.set_metadata(0, {})
			by_category[issue.category] = [head, 0]
		var item := issues_tree.create_item(by_category[issue.category][0])
		by_category[issue.category][1] += 1
		item.set_text(0, issue.message)
		item.set_tooltip_text(0, issue.message)
		item.set_custom_color(0, [Color(0.6, 0.8, 1.0), Color(1.0, 0.8, 0.35), Color(1.0, 0.45, 0.45)][issue.severity])
		item.set_metadata(0, issue)
	for category in by_category:
		by_category[category][0].set_text(0, "%s (%d)" % [category, by_category[category][1]])
	issues_summary.text = "%d error(s), %d warning(s), %d note(s)%s" % [counts[2], counts[1], counts[0], "" if scanned else ". Scan scenes for content checks."]
	var serious: int = counts[2] + counts[1]
	_sidebar.set_tab_title(_issues_tab.get_index(), "Issues (%d)" % serious if serious > 0 else "Issues")

# --- Stats -----------------------------------------------------------------------------

func _refresh_stats() -> void:
	if not analysis:
		stats_text.text = ""
		return
	var t: String = host.ui_stats_header()
	var totals := {"collectibles": 0, "enemies": 0, "save_points": 0}
	for meta in analysis.scene_db.values():
		for k in totals:
			totals[k] += meta.get(k, []).size()
	t += "%d collectibles, %d enemies, %d save points (scanned %d scenes)\n\n" % [totals.collectibles, totals.enemies, totals.save_points, analysis.scene_db.size()]

	var assigned: Array = analysis.graph.rooms.values().filter(func(r: MDSGraph.GRoom) -> bool: return r.has_scene)
	var areas: Dictionary = {}
	for room: MDSGraph.GRoom in assigned:
		var info := analysis.get_info(room.id)
		var a: String = info.area if not str(info.area).is_empty() else "(no area)"
		if not areas.has(a):
			areas[a] = {"rooms": 0, "collectibles": 0, "saves": 0, "bosses": 0}
		areas[a].rooms += 1
		areas[a].collectibles += info.collectibles
		areas[a].saves += 1 if info.is_save else 0
		areas[a].bosses += 1 if info.is_boss else 0
	t += "[b]Areas[/b]\n"
	for a in areas:
		var s: Dictionary = areas[a]
		var swatch: Color = host.ui_area_color(a if a != "(no area)" else "")
		t += "[color=#%s]%s[/color]: %d rooms, %d items, %d saves, %d bosses\n" % [swatch.lightened(0.35).to_html(false), a, s.rooms, s.collectibles, s.saves, s.bosses]
	t += "\n"

	t += "[b]Bosses[/b]\n"
	var any_boss := false
	for id in analysis.room_info:
		var info: Dictionary = analysis.room_info[id]
		if info.is_boss:
			any_boss = true
			var sd: int = analysis.save_distance.get(id, -1)
			t += "[url=room:%s]%s[/url]: %s (sphere %s, %s)\n" % [id, info.name, ", ".join(info.boss_names) if not info.boss_names.is_empty() else "unnamed", analysis.sphere_of.get(id, "-"), "save %d room(s) away" % sd if sd >= 0 else "no save reachable"]
	if not any_boss:
		t += "None found. Name a boss in the Inspector or add idp_boss_name metadata to a node.\n"

	var objectives := analysis.get_objectives()
	if not objectives.is_empty():
		t += "\n[b]Objectives[/b]\n"
		for o in objectives:
			var swatch: Color = host.ui_area_color(o.area)
			var status := _objective_status(o)
			if not str(o.problem).is_empty():
				status = "[color=#ff8080]%s[/color]" % status
			t += "[color=#%s]%s[/color]: %s\n" % [swatch.lightened(0.35).to_html(false), o.area, status]

	t += "\n[b]Build status[/b]\n"
	var status_counts: Dictionary = {}
	for room: MDSGraph.GRoom in assigned:
		var s: String = analysis.get_info(room.id).status
		status_counts[s] = status_counts.get(s, 0) + 1
	for s in MDSAnnotations.STATUSES:
		if status_counts.has(s):
			var pct: float = 100.0 * status_counts[s] / maxf(1.0, assigned.size())
			t += "[color=#%s]%s[/color]: %d (%d%%)\n" % [MDSMapCanvas.STATUS_COLORS[s].lightened(0.3).to_html(false), s.capitalize() if not s.is_empty() else "No status", status_counts[s], roundi(pct)]
	stats_text.text = t
