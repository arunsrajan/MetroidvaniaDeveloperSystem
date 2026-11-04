@tool
class_name MDSMoveTree
extends RefCounted
## How a fight's moves hang together, for tools: which properties hold moves, every move in a fight
## by its path, and what a running enemy is doing. The Fight editor and the game use the same paths,
## so a running fight can be shown on its graph. It finds move properties from the exports, so a move
## of your own that holds other moves works without further code.

## The debugger capture and message a running fight reports through.
const CAPTURE := "mds_moves"
const MESSAGE := "mds_moves:fight"

static var _bases: Dictionary = {}

## Whether [param class_name_] is [MDSMove] or extends it.
static func is_move_class(class_name_: String) -> bool:
	if _bases.is_empty():
		for c: Dictionary in ProjectSettings.get_global_class_list():
			_bases[String(c["class"])] = String(c["base"])
	var at := class_name_
	while not at.is_empty():
		if at == "MDSMove":
			return true
		at = String(_bases.get(at, ""))
	return false

## Forgets the classes it knows (a script was added).
static func forget_classes() -> void:
	_bases.clear()

## The properties of [param owner] that hold moves: each [code]{name, array}[/code].
static func slots_of(owner: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(owner):
		return out
	for p: Dictionary in owner.get_property_list():
		if not int(p["usage"]) & PROPERTY_USAGE_EDITOR:
			continue
		var hint := String(p["hint_string"])
		if int(p["type"]) == TYPE_OBJECT and int(p["hint"]) == PROPERTY_HINT_RESOURCE_TYPE and is_move_class(hint):
			out.append({"name": StringName(p["name"]), "array": false})
		elif int(p["type"]) == TYPE_ARRAY and is_move_class(hint.get_slice(":", hint.get_slice_count(":") - 1)):
			out.append({"name": StringName(p["name"]), "array": true})
	# A boss's last-gasp summon is no part of its phases.
	if owner is MDSMoveBoss:
		return out.filter(func(s: Dictionary) -> bool: return s["name"] != &"on_death") as Array[Dictionary]
	return out

## The path of what [param slot] holds under [param parent] ([param index] in an array slot).
static func child_path(parent: String, slot: StringName, index := -1) -> String:
	var own := String(slot) if index < 0 else "%s.%d" % [slot, index]
	return own if parent.is_empty() else parent + "/" + own

## Everything in the fight under [param root], root first, each
## [code]{path, res, parent, slot, index, depth}[/code]. A move used twice appears twice.
static func walk(root: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_instance_valid(root):
		_walk(root, "", "", &"", -1, 0, [], out)
	return out

static func _walk(res: Object, path: String, parent: String, slot: StringName, index: int, depth: int, stack: Array, out: Array[Dictionary]) -> void:
	out.append({"path": path, "res": res, "parent": parent, "slot": slot, "index": index, "depth": depth})
	if res in stack:
		return # holds itself: don't go round forever
	stack.append(res)
	for s in slots_of(res):
		var name: StringName = s["name"]
		var held: Variant = res.get(name)
		if s["array"]:
			var list: Array = held
			for i in list.size():
				if list[i]:
					_walk(list[i], child_path(path, name, i), path, name, i, depth + 1, stack, out)
		elif held:
			_walk(held, child_path(path, name), path, name, -1, depth + 1, stack, out)
	stack.pop_back()

## The paths under [param root] an enemy with [param ctx] is running now.
static func active_paths(root: Object, ctx: MDSMoveContext) -> PackedStringArray:
	var out := PackedStringArray()
	if is_instance_valid(root) and ctx:
		_active(root, "", ctx, [], out)
	return out

static func _active(res: Object, path: String, ctx: MDSMoveContext, stack: Array, out: PackedStringArray) -> void:
	if res in stack:
		return
	stack.append(res)
	for s in slots_of(res):
		var name: StringName = s["name"]
		var held: Variant = res.get(name)
		var list: Array = held if s["array"] else [held]
		for i in list.size():
			var move := list[i] as MDSMove
			if move and ctx.memory(move).get(&"running", false):
				var at := child_path(path, name, i if s["array"] else -1)
				out.append(at)
				_active(move, at, ctx, stack, out)
	stack.pop_back()

## The root of the tree [param enemy] is running: its phase, or itself.
static func root_of(enemy: MDSEnemy) -> Object:
	if enemy is MDSBoss:
		return (enemy as MDSBoss).get_phase()
	return enemy

## What a running fight looks like now, as the Fight editor shows it. [param state_name] is the state
## it is going to, when it is leaving this one.
static func snapshot(state: MDSMoveState, state_name := &"") -> Dictionary:
	var enemy := state.enemy
	var ctx := state._context()
	var root := root_of(enemy)
	var cooling := {}
	for e in walk(root):
		if e["res"] is MDSMove and ctx.cooling(e["res"]):
			cooling[e["path"]] = ctx.cooldown_left(e["res"])
	var boss := enemy as MDSBoss
	return {
		"id": enemy.get_instance_id(),
		"name": String(enemy.name),
		"path": String(enemy.get_path()) if enemy.is_inside_tree() else "",
		"kind": "boss" if boss else "enemy",
		"state": String(state_name if state_name != &"" else state.name),
		"phase": boss.phase_index if boss else 0,
		"threshold": boss.get_phase().health_threshold if boss and boss.get_phase() else 1.0,
		"active": active_paths(root, ctx),
		"cooling": cooling,
		"flags": ctx.flags.duplicate(),
		"health": enemy.health.current if enemy.health else 0,
		"max_health": enemy.health.get_max() if enemy.health else 0,
	}
