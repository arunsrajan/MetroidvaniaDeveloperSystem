@tool
class_name MDSMcpToolsFight
extends MDSMcpToolsObjects
## Fights made of moves, through the same document the Fight editor edits: a boss's or an enemy's
## in a scene, or a phase or move in a .tres file.

const OPS: PackedStringArray = ["make_editable", "from_recipe", "add", "remove", "move", "reorder", "copy", "make_unique", "set", "add_condition", "remove_condition", "add_phase", "remove_phase"]
const SLOT_HELP := "Which of the parent's lists or places the move goes in, such as moves or riposte. mds_fight_get says what each holds."

func _register() -> void:
	var target := _where_schema()
	target.merge({"node": S.text("The fighter in the scene"), "file": S.text("Or a phase or move in a .tres file"), "phase": S.integer("Which of a boss's phases, default 0", 0)})
	_add("mds_fight_get", "A fight as a tree: each move's path, class, parent and values, whether it can be changed yet, and the Fight editor's checks.", READ, target, [], _fight_get)
	_add("mds_fight_edit", "Changes a fight, as the Fight editor does. Moves are named by their paths from mds_fight_get; the phase or fighter itself is the path \"\". A recipe or a fight built in code is read-only until make_editable. op says which arguments each takes.", AUTHOR,
		target.merged({
			"op": S.choice(Array(OPS), "make_editable; from_recipe (recipe); add (parent, slot, index, move); remove (path); move (path, parent, slot, index); reorder (parent, slot, order); copy (path); make_unique (path); set (path, set); add_condition (path, list, condition_kind); remove_condition (path, list, index); add_phase; remove_phase (index)"), "path": S.text(), "parent": S.text(), "slot": S.text(SLOT_HELP), "index": S.integer("", 0), "order": S.array(S.integer("", 0), "The new order, as the old indexes"),
			"recipe": S.choice(Array(MDSMoveRecipes.RECIPES)), "move": S.any_object("{class, set}, or {path} of a .tres"), "set": S.any_object(SET_HELP),
			"list": S.choice(["when", "cancel_when"]), "condition_kind": S.choice(Array(MDSMoveCondition.Kind.keys())), "on_unsaved": _unsaved_schema(),
		}), ["op"], _fight_edit)
	_add("mds_fight_live", "What fighters in a game running from the editor are doing now: their running moves, phase, health, cooldowns and flags. Editor only.", READ, {}, [], _fight_live, {"editor_only": true})

## The document on what [param args] names, for [param opened] when it is in a scene. Null: see
## [member MDSMcpContext.error].
func _document(args: Dictionary, opened: Dictionary) -> MDSFightDocument:
	var doc := MDSFightDocument.new()
	var target: Object
	if opened.is_empty():
		target = _open_resource(str(args.get("file", "")))
		if not target:
			return null
		if not (target is MDSBossPhase or target is MDSMove):
			ctx.error = ctx.fail("bad_arguments", "%s is a %s: give a phase or a move." % [args.file, MDSMcpValues.class_of(target)])
			return null
	else:
		target = (opened.root as Node).get_node_or_null(NodePath(str(args.get("node", "."))))
		if not (target is MDSMoveBoss or target is MDSMoveEnemy):
			ctx.error = ctx.fail("not_a_fighter", "%s isn't an MDSMoveBoss or an MDSMoveEnemy." % args.get("node", "."), "mds_scene_tree shows the scene's nodes.")
			return null
	doc.open(target)
	if args.has("phase"):
		doc.set_phase(int(args.phase))
	return doc

func _fight_get(args: Dictionary, _report: Callable) -> Dictionary:
	var opened := {}
	if not args.has("file"):
		var path := _scene_path(args)
		if path.is_empty():
			return ctx.error
		opened = _open_scene(path)
		if opened.is_empty():
			return ctx.error
	var doc := _document(args, opened)
	if not doc:
		if not opened.is_empty():
			opened.root.free()
		return ctx.error
	var values := MDSMcpValues.new()
	var out := {"target": MDSMcpValues.class_of(doc.target), "read_only": doc.read_only, "phase": doc.phase_index}
	if doc.read_only:
		out.read_only_reason = doc.read_only_reason
	if doc.has_phases():
		var phases := []
		for p in doc.phases():
			phases.append(MDSFightDocument.short_name(p))
		out.phases = phases
	var moves := []
	for e: Dictionary in doc.entries():
		var res: Object = e.res
		var entry := {"path": e.path, "class": MDSMcpValues.class_of(res), "name": MDSFightDocument.short_name(res), "depth": e.depth, "slots": _slots(res), "values": values.changed_values(res)}
		if not str(e.path).is_empty():
			entry.parent = e.parent
			entry.slot = e.slot
		if res is Resource and not (res as Resource).resource_path.is_empty() and not (res as Resource).resource_path.contains("::"):
			entry.file = (res as Resource).resource_path
		moves.append(entry)
	out.moves = moves
	var checks := []
	for f: Dictionary in MDSFightCheck.check(doc.phases(), doc.root()):
		checks.append({"phase": f.phase, "path": f.path, "level": ["info", "warning", "error"][f.level], "text": f.text})
	out.checks = checks
	if not opened.is_empty():
		opened.root.free()
	return out

static func _slots(res: Object) -> Dictionary:
	var out := {}
	for s: Dictionary in MDSMoveTree.slots_of(res):
		out[String(s["name"])] = "list" if s["array"] else "one"
	return out

## Remembers the files a change to the fight can write. Returns whether it may.
func _touch_files(doc: MDSFightDocument) -> bool:
	var seen := {}
	var lists: Array = []
	lists.append_array(doc.phases())
	if not doc.has_phases():
		lists.append(doc.root())
	for root: Object in lists:
		if not root:
			continue
		for e: Dictionary in MDSMoveTree.walk(root):
			var res := e.res as Resource
			if not res:
				continue
			var file := res.resource_path.get_slice("::", 0)
			if not file.is_empty() and not seen.has(file):
				seen[file] = true
				if not ctx.touch(file):
					return false
	return true

func _fight_edit(args: Dictionary, _report: Callable) -> Dictionary:
	var opened := {}
	if not args.has("file"):
		opened = _edit_scene(args)
		if opened.is_empty():
			return ctx.error
	var doc := _document(args, opened)
	if not doc or not _touch_files(doc):
		if not opened.is_empty():
			opened.root.free()
		return ctx.error
	if opened.is_empty() and not ctx.touch(args.file):
		return ctx.error
	var problem := _apply_op(doc, args)
	if not problem.is_empty():
		if not opened.is_empty():
			opened.root.free()
		return ctx.fail("fight_not_changed", problem, "mds_fight_get shows the fight.")
	var entries := doc.entries().size()
	var out := {"op": args.op, "moves": entries, "read_only": doc.read_only}
	if opened.is_empty():
		var file: Resource = doc.target
		var err := ResourceSaver.save(file, file.resource_path)
		if err != OK:
			return ctx.fail("save_failed", "Could not save %s: %s." % [file.resource_path, error_string(err)])
		ctx.host.resource_written(file.resource_path)
		return out
	var bad := _save_scene(opened)
	return bad if not bad.is_empty() else out

## Does one edit. Returns why it couldn't be done, or "".
func _apply_op(doc: MDSFightDocument, args: Dictionary) -> String:
	var op: String = args.op
	var path := str(args.get("path", ""))
	var parent := str(args.get("parent", ""))
	var slot := StringName(str(args.get("slot", "")))
	if doc.read_only and not op in ["make_editable", "from_recipe"]:
		return doc.read_only_reason
	if op in ["remove", "move", "copy", "make_unique"] and (path.is_empty() or doc.entry(path).is_empty()):
		return "No move at path %s." % path
	if op in ["set", "add_condition", "remove_condition"] and doc.entry(path).is_empty():
		return "No move at path %s." % path
	if op in ["add", "move", "reorder"] and (doc.entry(parent).is_empty() or not _has_slot(doc.entry(parent).res, slot)):
		return "%s has no slot %s." % [parent if not parent.is_empty() else "The root", slot]
	var done := false
	match op:
		"make_editable":
			done = doc.make_editable()
		"from_recipe":
			if not args.has("recipe"):
				return "from_recipe needs recipe."
			done = doc.start_from_recipe(args.recipe)
		"add":
			var values := MDSMcpValues.new()
			var move: Variant = values.decode(args.get("move"), {"name": "move", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "MDSMove"})
			if not values.error.is_empty():
				return values.error
			if not move:
				return "add needs move."
			if not doc.has_room(parent, slot):
				return "%s of %s is already filled." % [slot, parent]
			done = doc.add_move(move, parent, slot, int(args.get("index", -1)))
		"remove":
			done = doc.remove(path)
		"move":
			done = doc.move_to(path, parent, slot, int(args.get("index", -1)))
		"reorder":
			if not args.has("order"):
				return "reorder needs order."
			var held: Variant = doc.entry(parent).res.get(slot)
			var order: Array = args.order.duplicate()
			var sorted := order.duplicate()
			sorted.sort()
			if not held is Array or sorted != range(held.size()):
				return "order must have each index of %s once." % slot
			done = doc.reorder(parent, slot, order)
		"copy":
			done = doc.duplicate_at(path)
		"make_unique":
			done = doc.make_unique(path)
		"set":
			return _set_values(doc, path, args.get("set", {}))
		"add_condition":
			if not doc.entry(path).res is MDSMove or not args.has("list"):
				return "add_condition needs a move's path, and list."
			var kind: int = MDSMoveCondition.Kind.get(str(args.get("condition_kind", "PLAYER_NEAR")), 0)
			done = doc.add_condition(doc.entry(path).res, StringName(args.list), kind as MDSMoveCondition.Kind)
		"remove_condition":
			if not doc.entry(path).res is MDSMove or not args.has("list") or not args.has("index"):
				return "remove_condition needs a move's path, list and index."
			done = doc.remove_condition(doc.entry(path).res, StringName(args.list), int(args.index))
		"add_phase":
			done = doc.add_phase()
		"remove_phase":
			if not args.has("index"):
				return "remove_phase needs index."
			done = doc.remove_phase(int(args.index))
	return "" if done else "%s couldn't be done here." % op

## Sets values of a move through the document, so files it lives in are saved.
static func _set_values(doc: MDSFightDocument, path: String, values: Dictionary) -> String:
	var obj: Object = doc.entry(path).res
	var reader := MDSMcpValues.new()
	var holder: Object = obj.duplicate() if obj is Resource else obj
	if not reader.set_all(holder, values):
		return reader.error
	var edits := []
	for key: String in values:
		edits.append([obj, StringName(key), holder.get(key)])
	return "" if edits.is_empty() or doc.commit("Set values", edits) else "These values couldn't be set."

static func _has_slot(res: Object, slot: StringName) -> bool:
	for s: Dictionary in MDSMoveTree.slots_of(res):
		if s["name"] == slot:
			return true
	return false

func _fight_live(_args: Dictionary, _report: Callable) -> Dictionary:
	return {"fighters": ctx.host.live_fights()}
