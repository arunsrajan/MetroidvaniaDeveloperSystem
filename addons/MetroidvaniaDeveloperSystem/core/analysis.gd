@tool
class_name MDSAnalysis
extends RefCounted
## Metroidvania-oriented analysis of the room graph.
##
## - Progression "spheres": starting from the start room, everything reachable with the
##   abilities you have is sphere 0; abilities found there unlock sphere 1, and so on
##   (the same logic item randomizers use). Rooms never reached are locked or disconnected.
## - Backtracking payoff: which previously visited rooms each ability opens up.
## - Save coverage: how many rooms away the nearest save point is (bench before boss...).
## - Topology: dead ends, chokepoints (rooms whose removal splits the map) and hubs.
##
## Works on an [MDSGraph], so the MetSys and non-linear modes share it.

var graph: MDSGraph
var annotations: MDSAnnotations
var scene_db: Dictionary

## id -> {name, type, area, grants, is_save, is_boss, is_shop, is_teleporter, boss_names,
##        collectibles, status}
var room_info: Dictionary = {}
## door key -> PackedStringArray, merged from annotations and scanned gates.
var door_requires: Dictionary = {}
## door key -> Array of gate node names found by the scanner.
var door_gate_sources: Dictionary = {}
var start_room_id := ""
var sphere_of: Dictionary = {} ## id -> int
## [{index, rooms: Array[String], gained: PackedStringArray, entries: [{door, from, to, requires}]}]
var spheres: Array = []
var locked: Array[String] = [] ## reachable if requirements are ignored, but never unlocked.
var disconnected: Array[String] = [] ## not connected to the start at all.
var save_distance: Dictionary = {} ## id -> hops to the nearest save room (-1: none).
var start_distance: Dictionary = {} ## id -> hops from the start (ignoring requirements).
var dead_ends: Array[String] = []
var chokepoints: Array[String] = []
var hubs: Array[String] = []
var all_required: PackedStringArray = []
var all_granted: PackedStringArray = []

var _adjacency: Dictionary = {} ## id -> Array of {to: String, door: String, link: int}

func _init(p_graph: MDSGraph, p_annotations: MDSAnnotations, p_scene_db: Dictionary) -> void:
	graph = p_graph
	annotations = p_annotations
	scene_db = p_scene_db

func run() -> MDSAnalysis:
	_collect_room_info()
	_collect_door_requirements()
	_build_adjacency()
	_pick_start()
	_compute_spheres()
	start_distance = distances_from([start_room_id]) if not start_room_id.is_empty() else {}
	var saves: Array[String] = []
	for id in room_info:
		if room_info[id].is_save:
			saves.append(id)
	save_distance = distances_from(saves)
	_compute_topology()
	return self

# --- Room facts ----------------------------------------------------------------

func _collect_room_info() -> void:
	room_info.clear()
	for room: MDSGraph.GRoom in graph.rooms.values():
		var meta: Dictionary = scene_db.get(room.scene_path, {})
		var ann := annotations.get_room(room.id)
		var type: String = ann.get("type", "")
		if type.is_empty():
			type = meta.get("room_type_hint", "")
		if type.is_empty():
			if meta.get("has_boss", false):
				type = "boss"
			elif not meta.get("save_points", []).is_empty():
				type = "save"
			elif meta.get("has_shopkeeper", false):
				type = "shop"
			elif meta.get("has_teleporter", false):
				type = "fast_travel"
		var grants := PackedStringArray(ann.get("grants", []))
		for g in meta.get("grants", PackedStringArray()):
			if not g in grants:
				grants.append(g)
		var boss_names: PackedStringArray = []
		if not str(ann.get("boss", "")).is_empty():
			boss_names.append(ann.boss)
		else:
			for b in meta.get("bosses", []):
				boss_names.append(b.name)
		var groups := room.group_names
		var area: String = ann.get("area", "")
		if area.is_empty() and not groups.is_empty():
			area = groups[0]
		room_info[room.id] = {
			"name": ann.get("name", room.name) if not str(ann.get("name", "")).is_empty() else room.name,
			"type": type,
			"area": area,
			"status": ann.get("status", ""),
			"grants": grants,
			"is_save": type == "save" or not meta.get("save_points", []).is_empty(),
			"is_boss": type in ["boss", "mini_boss"] or meta.get("has_boss", false),
			"is_shop": type == "shop" or meta.get("has_shopkeeper", false),
			"is_teleporter": type == "fast_travel" or meta.get("has_teleporter", false),
			"boss_names": boss_names,
			"collectibles": meta.get("collectibles", []).size(),
			"scanned": not meta.is_empty(),
		}

func get_info(id: String) -> Dictionary:
	return room_info.get(id, {})

func get_room_name(id: String) -> String:
	return room_info.get(id, {}).get("name", id)

## Requirements typed in the panel plus the ones built into the graph (scanned gate
## nodes, world gate requirements).
func _collect_door_requirements() -> void:
	door_requires.clear()
	door_gate_sources.clear()
	for e: MDSGraph.GEdge in graph.edges:
		var reqs := annotations.get_door_requires(e.key)
		for r in e.requires:
			if not r in reqs:
				reqs.append(r)
		if not reqs.is_empty():
			door_requires[e.key] = reqs
		if not e.gate_sources.is_empty():
			door_gate_sources[e.key] = e.gate_sources.duplicate()

func get_door_requires(key: String) -> PackedStringArray:
	return door_requires.get(key, PackedStringArray())

# --- Graph ---------------------------------------------------------------------

func _build_adjacency() -> void:
	_adjacency.clear()
	for id in graph.rooms:
		_adjacency[id] = []
	for e: MDSGraph.GEdge in graph.edges:
		if e.b.is_empty() or e.a == e.b or not _adjacency.has(e.a) or not _adjacency.has(e.b):
			continue
		_adjacency[e.a].append({"to": e.b, "door": e.key, "link": -1})
		_adjacency[e.b].append({"to": e.a, "door": e.key, "link": -1})
	var links := annotations.get_links()
	for i in links.size():
		var link: Dictionary = links[i]
		if _adjacency.has(link.a) and _adjacency.has(link.b):
			_adjacency[link.a].append({"to": link.b, "door": "", "link": i})
			_adjacency[link.b].append({"to": link.a, "door": "", "link": i})

func get_neighbors(id: String) -> Array:
	return _adjacency.get(id, [])

func _edge_requires(edge: Dictionary) -> PackedStringArray:
	if edge.link >= 0:
		return PackedStringArray(annotations.get_links()[edge.link].get("requires", []))
	return get_door_requires(edge.door)

func _can_pass(from_id: String, edge: Dictionary, have: Dictionary) -> bool:
	if edge.link < 0:
		var one_way := get_one_way_from(edge.door)
		if not one_way.is_empty() and one_way != from_id:
			return false
	for r in _edge_requires(edge):
		if not have.has(r):
			return false
	return true

## Room id a door can only be passed from ("" when two-way): set in the panel, or built
## into the graph (world transitions that do not lead back).
func get_one_way_from(key: String) -> String:
	var one_way := annotations.get_door_one_way_from(key)
	if one_way.is_empty():
		var e := graph.get_edge(key)
		if e:
			one_way = e.one_way_from
	return one_way

func _pick_start() -> void:
	start_room_id = annotations.get_start_room()
	if graph.rooms.has(start_room_id):
		return
	start_room_id = ""
	# Default: the first save room on the lowest layer, else the first room.
	var candidates: Array = graph.rooms.values()
	candidates.sort_custom(func(a: MDSGraph.GRoom, b: MDSGraph.GRoom) -> bool:
		if a.layer != b.layer:
			return a.layer < b.layer
		if a.sort_pos.y != b.sort_pos.y:
			return a.sort_pos.y < b.sort_pos.y
		return a.sort_pos.x < b.sort_pos.x)
	for room: MDSGraph.GRoom in candidates:
		if room_info[room.id].is_save and room.has_scene:
			start_room_id = room.id
			return
	if not candidates.is_empty():
		start_room_id = candidates[0].id

func _compute_spheres() -> void:
	sphere_of.clear()
	spheres.clear()
	locked.clear()
	disconnected.clear()
	all_required = PackedStringArray()
	all_granted = PackedStringArray()
	for reqs in door_requires.values():
		for r in reqs:
			if not r in all_required:
				all_required.append(r)
	for link in annotations.get_links():
		for r in link.get("requires", []):
			if not r in all_required:
				all_required.append(r)
	for info in room_info.values():
		for g in info.grants:
			if not g in all_granted:
				all_granted.append(g)
	if start_room_id.is_empty():
		return

	var have: Dictionary = {}
	var sphere := 0
	sphere_of[start_room_id] = 0
	while true:
		var entries: Array = []
		# Expand from every reached room with the abilities currently held.
		var queue: Array = sphere_of.keys()
		while not queue.is_empty():
			var id: String = queue.pop_front()
			for edge in _adjacency[id]:
				if sphere_of.has(edge.to) or not _can_pass(id, edge, have):
					continue
				sphere_of[edge.to] = sphere
				queue.append(edge.to)
				if sphere > 0 and sphere_of[id] < sphere:
					entries.append({"door": edge.door, "link": edge.link, "from": id, "to": edge.to, "requires": _edge_requires(edge)})
		var rooms_here: Array[String] = []
		var gained: PackedStringArray = []
		for id in sphere_of:
			if sphere_of[id] == sphere:
				rooms_here.append(id)
		for id in sphere_of:
			for g in room_info[id].grants:
				if not have.has(g) and not g in gained:
					gained.append(g)
		spheres.append({"index": sphere, "rooms": rooms_here, "gained": gained, "entries": entries})
		if gained.is_empty():
			break
		for g in gained:
			have[g] = true
		sphere += 1

	var connected := distances_from([start_room_id])
	for id in graph.rooms:
		if sphere_of.has(id):
			continue
		if connected.has(id):
			locked.append(id)
		else:
			disconnected.append(id)

## Multi-source BFS ignoring requirements and one-way doors. Returns id -> hops.
func distances_from(sources: Array[String]) -> Dictionary:
	var dist: Dictionary = {}
	var queue: Array = []
	for s in sources:
		if _adjacency.has(s):
			dist[s] = 0
			queue.append(s)
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for edge in _adjacency[id]:
			if not dist.has(edge.to):
				dist[edge.to] = dist[id] + 1
				queue.append(edge.to)
	return dist

## Shortest room path from [param from_id] to [param to_id] (inclusive), ignoring
## requirements. Empty if no path exists.
func find_path(from_id: String, to_id: String) -> Array[String]:
	var ret: Array[String] = []
	if not _adjacency.has(from_id) or not _adjacency.has(to_id):
		return ret
	var parent: Dictionary = {from_id: ""}
	var queue: Array = [from_id]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if id == to_id:
			break
		for edge in _adjacency[id]:
			if not parent.has(edge.to):
				parent[edge.to] = id
				queue.append(edge.to)
	if not parent.has(to_id):
		return ret
	var cur := to_id
	while not cur.is_empty():
		ret.push_front(cur)
		cur = parent[cur]
	return ret

func _compute_topology() -> void:
	dead_ends.clear()
	chokepoints.clear()
	hubs.clear()
	for id in _adjacency:
		var unique: Dictionary = {}
		for edge in _adjacency[id]:
			unique[edge.to] = true
		if unique.size() == 1:
			dead_ends.append(id)
		elif unique.size() >= 4:
			hubs.append(id)
	chokepoints = _articulation_points()

## Iterative Tarjan: rooms whose removal disconnects part of the map.
func _articulation_points() -> Array[String]:
	var disc: Dictionary = {}
	var low: Dictionary = {}
	var result: Dictionary = {}
	var timer := 0
	for root in _adjacency:
		if disc.has(root):
			continue
		var root_children := 0
		disc[root] = timer
		low[root] = timer
		timer += 1
		var stack: Array = [[root, "", 0]] # node, parent, next edge index
		while not stack.is_empty():
			var frame: Array = stack.back()
			var node: String = frame[0]
			var edges: Array = _adjacency[node]
			if frame[2] < edges.size():
				var to: String = edges[frame[2]].to
				frame[2] += 1
				if to == frame[1]:
					continue
				if disc.has(to):
					low[node] = mini(low[node], disc[to])
				else:
					disc[to] = timer
					low[to] = timer
					timer += 1
					if node == root:
						root_children += 1
					stack.append([to, node, 0])
			else:
				stack.pop_back()
				var parent: String = frame[1]
				if not parent.is_empty():
					low[parent] = mini(low[parent], low[node])
					if parent != root and low[node] >= disc[parent]:
						result[parent] = true
		if root_children > 1:
			result[root] = true
	var ret: Array[String] = []
	ret.assign(result.keys())
	return ret

## Doors (and links) that need [param ability], with the rooms on each side.
func get_ability_uses(ability: String) -> Array:
	var ret: Array = []
	for key in door_requires:
		if ability in door_requires[key]:
			var e := graph.get_edge(key)
			if e:
				ret.append({"door": key, "a": e.a, "b": e.b})
	var links := annotations.get_links()
	for i in links.size():
		if ability in links[i].get("requires", []):
			ret.append({"door": "", "link": i, "a": links[i].a, "b": links[i].b})
	return ret

## Rooms granting [param ability].
func get_ability_sources(ability: String) -> Array[String]:
	var ret: Array[String] = []
	for id in room_info:
		if ability in room_info[id].grants:
			ret.append(id)
	return ret

## The areas' objectives ([code]areas[name].objective[/code] and
## [code]objective_done_when[/code]), each a
## Dictionary: [code]area, text, condition, kind[/code] ("ability", "object", "boss" or
## "" when game code completes it), [code]target, rooms[/code] (where the condition can be met),
## [code]sphere[/code] (earliest progression sphere it can complete in, -1 unknown) and
## [code]problem[/code] (why it can never complete, "" when it can).
func get_objectives() -> Array:
	var ret: Array = []
	var areas: Dictionary = annotations.data.get("areas", {})
	for area in areas:
		var text := str(areas[area].get("objective", ""))
		var condition := str(areas[area].get("objective_done_when", "")).strip_edges()
		if text.is_empty() and condition.is_empty():
			continue
		var o := {"area": area, "text": text, "condition": condition, "kind": "", "target": "", "rooms": [], "sphere": -1, "problem": ""}
		ret.append(o)
		if condition.is_empty():
			continue
		var c := MDSAnnotations.parse_condition(condition)
		o.kind = c[0]
		o.target = c[1]
		var rooms: Array[String] = []
		match o.kind:
			"ability":
				o.target = str(c[1]).to_lower().replace(" ", "_")
				rooms = get_ability_sources(o.target)
				if rooms.is_empty():
					o.problem = "no room grants '%s'" % o.target
			"boss":
				for id in room_info:
					for b in room_info[id].boss_names:
						if str(b).to_lower() == str(o.target).to_lower():
							rooms.append(id)
				if rooms.is_empty():
					o.problem = "no room has the boss '%s'" % o.target
			"object":
				# Object ids are "<room id>/<node path>" (MDSWorldGame.object_id) unless a node
				# sets idp_object_id: only the room part can be checked.
				var room_id := str(o.target).get_slice("/", 0)
				if str(o.target).contains("/"):
					if room_info.has(room_id):
						rooms.append(room_id)
					else:
						o.problem = "the object's room '%s' doesn't exist" % room_id
		o.rooms = rooms
		if o.problem.is_empty() and not rooms.is_empty() and not start_room_id.is_empty():
			var best := -1
			for id in rooms:
				if sphere_of.has(id) and (best < 0 or int(sphere_of[id]) < best):
					best = int(sphere_of[id])
			o.sphere = best
			if best < 0:
				o.problem = "it can only be met in %s, which the player can never reach" % ", ".join(rooms.map(get_room_name))
	return ret
