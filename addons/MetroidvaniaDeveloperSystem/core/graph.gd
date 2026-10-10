@tool
class_name MDSGraph
extends RefCounted
## Mode-independent room graph consumed by [MDSAnalysis].
##
## Built from a MetSys map ([method from_metsys]) or a non-linear world
## ([method from_world]), so progression, save distance, routes and design checks work
## the same in both modes.

class GRoom:
	var id := ""
	var name := "" ## Default display name (annotations may override it).
	var scene_path := ""
	var has_scene := false
	var layer := 0
	var sort_pos := Vector2.ZERO ## Used to pick a default start room (top-left first).
	var group_names: PackedStringArray = [] ## Area fallbacks (MetSys groups / world area).

class GEdge:
	var key := ""
	var a := ""
	var b := "" ## Empty when the passage leads nowhere.
	var requires: PackedStringArray = [] ## Built-in requirements (scanned gates, world gates).
	var gate_sources: Array = [] ## Names of scene nodes that contributed requirements.
	var one_way_from := "" ## Built-in one-way (world: only one side has the transition).

var rooms: Dictionary = {} ## id -> GRoom
var edges: Array[GEdge] = []
var edge_by_key: Dictionary = {}

func add_room(id: String, name: String, scene_path: String, has_scene: bool, layer: int, sort_pos: Vector2, group_names := PackedStringArray()) -> GRoom:
	var r := GRoom.new()
	r.id = id
	r.name = name
	r.scene_path = scene_path
	r.has_scene = has_scene
	r.layer = layer
	r.sort_pos = sort_pos
	r.group_names = group_names
	rooms[id] = r
	return r

func add_edge(key: String, a: String, b: String) -> GEdge:
	var e := GEdge.new()
	e.key = key
	e.a = a
	e.b = b
	edges.append(e)
	edge_by_key[key] = e
	return e

func get_edge(key: String) -> GEdge:
	return edge_by_key.get(key)

func get_room(id: String) -> GRoom:
	return rooms.get(id)

## Graph of a MetSys map. Gates found in scenes ([code]mds_requires[/code] metadata) are
## attached to the passage closest to the gate node.
static func from_metsys(model: MDSMapModel, scene_db: Dictionary, cell_size: Vector2) -> MDSGraph:
	var g := MDSGraph.new()
	for room: MDSMapModel.Room in model.rooms.values():
		g.add_room(room.id, room.get_display_name(), room.scene_path, not room.scene_uid.is_empty(), room.layer, Vector2(room.min_cell), model.get_room_group_names(room))
	for door: MDSMapModel.Door in model.doors.values():
		g.add_edge(door.key, door.a_room.id, door.b_room.id if door.b_room else "")
	for room: MDSMapModel.Room in model.rooms.values():
		var meta: Dictionary = scene_db.get(room.scene_path, {})
		for gate in meta.get("gates", []):
			var door := _closest_metsys_door(room, gate.position, cell_size)
			if not door:
				continue
			var e := g.get_edge(door.key)
			for r in gate.requires:
				if not r in e.requires:
					e.requires.append(r)
			e.gate_sources.append(gate.name)
	return g

static func _closest_metsys_door(room: MDSMapModel.Room, local_pos: Vector2, cell_size: Vector2) -> MDSMapModel.Door:
	var best: MDSMapModel.Door = null
	var best_d := INF
	for door in room.doors:
		var c := door.cell_of(room)
		var d := door.dir_of(room)
		var local_cell := Vector2(c.x - room.min_cell.x, c.y - room.min_cell.y)
		var edge_mid := (local_cell + Vector2(0.5, 0.5) + Vector2(MDSMapModel.FWD[d]) * 0.5) * cell_size
		var dist := edge_mid.distance_squared_to(local_pos)
		if dist < best_d:
			best_d = dist
			best = door
	return best

## Graph of a non-linear world. Every gate is an edge; a transition whose target does not
## point back is one-way (like a Hollow Knight drop), as is a gate flagged "one_way".
static func from_world(world: MDSWorld, scene_db: Dictionary) -> MDSGraph:
	var g := MDSGraph.new()
	for id in world.get_room_ids():
		var area := world.get_room_area(id)
		var groups := PackedStringArray([area]) if not area.is_empty() else PackedStringArray()
		var path := world.get_scene_path(id)
		g.add_room(id, id, path, not path.is_empty(), world.get_room_layer(id), world.get_room_bounds(id).position, groups)
	for id in world.get_room_ids():
		var gates := world.get_gates(id)
		for gate_name in gates:
			var gate: Dictionary = gates[gate_name]
			var to: String = gate.get("to", "")
			var key := MDSWorld.edge_key(id, gate_name, to, gate.get("to_gate", ""))
			var e := g.get_edge(key)
			if not e:
				e = g.add_edge(key, id, to if world.has_room(to) else "")
				if not e.b.is_empty():
					var back := world.get_gate(to, gate.get("to_gate", ""))
					var points_back: bool = back.get("to", "") == id and back.get("to_gate", "") == gate_name
					if not points_back:
						e.one_way_from = id
			for r in gate.get("requires", []):
				if not r in e.requires:
					e.requires.append(r)
			if gate.get("one_way", false):
				e.one_way_from = id
		# Scanned gate nodes (mds_requires) attach to the closest transition.
		var meta: Dictionary = scene_db.get(world.get_scene_path(id), {})
		for scanned_gate in meta.get("gates", []):
			var best := ""
			var best_d := INF
			for gate_name in gates:
				var d := world.get_gate_local_pos(id, gate_name).distance_squared_to(scanned_gate.position)
				if d < best_d:
					best_d = d
					best = gate_name
			if best.is_empty():
				continue
			var gate: Dictionary = gates[best]
			var e := g.get_edge(MDSWorld.edge_key(id, best, gate.get("to", ""), gate.get("to_gate", "")))
			if e:
				for r in scanned_gate.requires:
					if not r in e.requires:
						e.requires.append(r)
				e.gate_sources.append(scanned_gate.name)
	return g
