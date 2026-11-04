@tool
class_name MDSFightDocument
extends RefCounted
## The fight open in the Fight editor, with every edit it can make: no UI, so it can be tested and
## driven by itself. It edits the resources themselves, so a fight stays editable by hand, in code or
## in the graph. Each edit is one undo step in [member undo].

signal changed
## An edit changed values only, not the shape of the fight (no need to rebuild what is being typed in).
signal values_changed

## The properties of a boss a recipe sets.
const RECIPE_PROPS: Array[StringName] = [&"uses_gravity", &"look", &"body_size", &"body_color", &"stagger_hits", &"stagger_time", &"falls_when_staggered", &"damage_type", &"on_death", &"phases"]
const BOSS_FIELDS: Array[StringName] = [&"boss_name", &"stagger_hits", &"stagger_time", &"phase_pause", &"falls_when_staggered", &"rest_time", &"wake_range"]
const ENEMY_FIELDS: Array[StringName] = [&"wait_to_see", &"uses_gravity"]

## An [MDSMoveBoss], an [MDSMoveEnemy], or a phase or move from a .tres file.
var target: Object
## An UndoRedo, or the editor's EditorUndoRedoManager.
var undo: Object
var phase_index := 0
## A fight you can look at but not change, until [method make_editable]: a recipe, or built in code.
var read_only := false
## Why it is read-only.
var read_only_reason := ""

var _preview: Array[MDSBossPhase] = []
var _entries: Array[Dictionary] = []

func _init() -> void:
	undo = UndoRedo.new()

## Opens [param new_target] (null: nothing).
func open(new_target: Object) -> void:
	target = new_target
	phase_index = 0
	_reload()
	changed.emit()

func is_open() -> bool:
	return is_instance_valid(target)

func _reload() -> void:
	read_only = false
	read_only_reason = ""
	_preview.clear()
	if not is_open():
		_entries = []
		return
	if target is MDSMoveBoss:
		var boss := target as MDSMoveBoss
		if boss.phases.is_empty():
			if not boss.recipe.is_empty():
				_preview = _recipe_phases(boss.recipe)
				read_only_reason = "This is the recipe \"%s\". Make it editable to change it." % boss.recipe
			elif _is_inherited(boss, MDSMoveBoss):
				if (boss.get_script() as Script).is_tool():
					_preview = boss._make_phases()
					read_only_reason = "These phases are built in code by %s. Make them editable to keep a copy in this scene." % _script_name(boss)
				else:
					read_only_reason = "%s builds its phases in code. Add @tool to its script to see them here." % _script_name(boss)
			read_only = not read_only_reason.is_empty()
	elif target is MDSMoveEnemy:
		var enemy := target as MDSMoveEnemy
		if not enemy.moves and _is_inherited(enemy, MDSMoveEnemy) and not (enemy.get_script() as Script).is_tool():
			read_only = true
			read_only_reason = "%s builds its moves in code. Add @tool to its script to see them here." % _script_name(enemy)
	phase_index = clampi(phase_index, 0, maxi(0, phases().size() - 1))
	_entries = MDSMoveTree.walk(root())

func _is_inherited(node: Object, base: Script) -> bool:
	return node.get_script() != base

func _script_name(node: Object) -> String:
	return (node.get_script() as Script).resource_path.get_file()

## Phases of [param recipe], built on a boss that is never shown.
func _recipe_phases(recipe: String) -> Array[MDSBossPhase]:
	var tmp := MDSMoveBoss.new()
	MDSMoveRecipes.setup(tmp, recipe)
	var out := tmp.phases
	tmp.free()
	return out

## The phases it has (a boss only).
func phases() -> Array[MDSBossPhase]:
	if has_phases():
		return _preview if read_only else (target as MDSMoveBoss).phases
	return []

func has_phases() -> bool:
	return is_instance_valid(target) and target is MDSMoveBoss

## What the graph shows: this phase, the enemy, or the file's phase or move.
func root() -> Object:
	if not is_open():
		return null
	if has_phases():
		var list := phases()
		return list[phase_index] if phase_index < list.size() else null
	return target

func entries() -> Array[Dictionary]:
	return _entries

## The entry at [param path] (empty: none).
func entry(path: String) -> Dictionary:
	for e in _entries:
		if e["path"] == path:
			return e
	return {}

func set_phase(index: int) -> void:
	phase_index = clampi(index, 0, maxi(0, phases().size() - 1))
	_entries = MDSMoveTree.walk(root())
	changed.emit()

## How many places in this fight use the same [param res].
func uses_of(res: Object) -> int:
	var n := 0
	for e in _entries:
		if e["res"] == res:
			n += 1
	return n

# --- Edits ---------------------------------------------------------------------------------------

## Applies [param edits], each [code][object, property, value][/code], as one undo step.
func commit(label: String, edits: Array, reshapes := true) -> bool:
	if read_only or not is_open() or edits.is_empty():
		return false
	var touched: Array = []
	if undo is UndoRedo:
		(undo as UndoRedo).create_action(label)
	else:
		var context: Object = target if target is Node else null
		undo.call(&"create_action", label, 0, context)
	for e: Array in edits:
		undo.call(&"add_do_property", e[0], e[1], e[2])
		undo.call(&"add_undo_property", e[0], e[1], e[0].get(e[1]))
		if not e[0] in touched:
			touched.append(e[0])
	# Undoing a change of values still rebuilds the fields: they show the old value again.
	if undo is UndoRedo:
		(undo as UndoRedo).add_do_method(_after.bind(touched, reshapes))
		(undo as UndoRedo).add_undo_method(_after.bind(touched, true))
	else:
		undo.call(&"add_do_method", self, &"_after", touched, reshapes)
		undo.call(&"add_undo_method", self, &"_after", touched, true)
	undo.call(&"commit_action")
	return true

func _after(touched: Array, reshapes: bool) -> void:
	_persist(touched)
	_reload()
	if reshapes:
		changed.emit()
	else:
		values_changed.emit()

## What lives in a .tres of its own is saved right away. What belongs to a scene is saved with it.
func _persist(touched: Array) -> void:
	var files := {}
	for o: Object in touched:
		if o is Resource:
			var file := (o as Resource).resource_path.get_slice("::", 0)
			if file.ends_with(".tres") or file.ends_with(".res"):
				files[file] = true
	for file: String in files:
		var res := ResourceLoader.load(file)
		if res:
			ResourceSaver.save(res, file)

## Sets a property of something in the fight.
func set_value(obj: Object, prop: StringName, value: Variant) -> bool:
	return commit("Set %s" % prop, [[obj, prop, value]], false)

func _owner_of(e: Dictionary) -> Object:
	return entry(e["parent"]).get("res")

## Puts [param move] in [param slot] of what is at [param parent_path], at [param index] (-1: the end).
func add_move(move: Resource, parent_path: String, slot: StringName, index := -1) -> bool:
	var parent: Object = entry(parent_path).get("res")
	if not parent or not move:
		return false
	var edit := _insert_edit(parent, slot, move, index)
	return not edit.is_empty() and commit("Add %s" % short_name(move), [edit])

func _insert_edit(parent: Object, slot: StringName, move: Resource, index: int) -> Array:
	var held: Variant = parent.get(slot)
	if held is Array:
		var list: Array = (held as Array).duplicate()
		list.insert(index if index >= 0 and index <= list.size() else list.size(), move)
		return [parent, slot, list]
	if held:
		return []
	return [parent, slot, move]

## Whether [param slot] of what is at [param path] has room for one more.
func has_room(path: String, slot: StringName) -> bool:
	var parent: Object = entry(path).get("res")
	if not parent:
		return false
	var held: Variant = parent.get(slot)
	return held is Array or not held

func remove(path: String) -> bool:
	var e := entry(path)
	if e.is_empty() or path.is_empty():
		return false
	return commit("Remove %s" % short_name(e["res"]), [_removal_edit(e)])

func _removal_edit(e: Dictionary) -> Array:
	var parent := _owner_of(e)
	var held: Variant = parent.get(e["slot"])
	if held is Array:
		var list: Array = (held as Array).duplicate()
		list.remove_at(e["index"])
		return [parent, e["slot"], list]
	return [parent, e["slot"], null]

## Moves what is at [param path] to [param slot] of what is at [param parent_path]. It can't go inside
## itself.
func move_to(path: String, parent_path: String, slot: StringName, index := -1) -> bool:
	var e := entry(path)
	var to := entry(parent_path)
	if e.is_empty() or to.is_empty() or path.is_empty():
		return false
	if _holds(e["res"], to["res"]):
		return false
	var from_parent := _owner_of(e)
	if from_parent == to["res"] and e["slot"] == slot:
		if e["index"] < 0:
			return false
		var list: Array = (from_parent.get(slot) as Array).duplicate()
		list.remove_at(e["index"])
		list.insert(clampi(index if index >= 0 else list.size(), 0, list.size()), e["res"])
		return commit("Move %s" % short_name(e["res"]), [[from_parent, slot, list]])
	var add := _insert_edit(to["res"], slot, e["res"], index)
	if add.is_empty():
		return false
	return commit("Move %s" % short_name(e["res"]), [_removal_edit(e), add])

## Whether [param outer] is [param inner], or holds it anywhere.
func _holds(outer: Object, inner: Object) -> bool:
	for e in MDSMoveTree.walk(outer):
		if e["res"] == inner:
			return true
	return false

## Puts what [param slot] of [param parent_path] holds in the order of [param order] (old indexes).
func reorder(parent_path: String, slot: StringName, order: Array) -> bool:
	var parent: Object = entry(parent_path).get("res")
	if not parent:
		return false
	var old: Array = parent.get(slot)
	if order.size() != old.size():
		return false
	var list: Array = old.duplicate()
	var same := true
	for i in order.size():
		list[i] = old[int(order[i])]
		same = same and int(order[i]) == i
	return not same and commit("Reorder %s" % slot, [[parent, slot, list]])

## A copy of [param res] sharing nothing with it, however deep. Moves used twice inside it stay the
## one move, used twice.
static func copy_tree(res: Resource, seen := {}) -> Resource:
	if seen.has(res):
		return seen[res]
	var copy := res.duplicate(false)
	seen[res] = copy
	for s in MDSMoveTree.slots_of(res):
		var name: StringName = s["name"]
		if s["array"]:
			var list: Array = (res.get(name) as Array).duplicate()
			for i in list.size():
				if list[i]:
					list[i] = copy_tree(list[i], seen)
			copy.set(name, list)
		elif res.get(name):
			copy.set(name, copy_tree(res.get(name), seen))
	if res is MDSMove:
		for prop: StringName in [&"when", &"cancel_when"]:
			var conditions: Array = (res.get(prop) as Array).duplicate()
			for i in conditions.size():
				if conditions[i]:
					conditions[i] = (conditions[i] as Resource).duplicate()
			copy.set(prop, conditions)
	return copy

## A copy of what is at [param path], right after it (where its place holds only one, nothing).
func duplicate_at(path: String) -> bool:
	var e := entry(path)
	if e.is_empty() or path.is_empty() or e["index"] < 0:
		return false
	return add_move(copy_tree(e["res"]), e["parent"], e["slot"], e["index"] + 1)

## What is at [param path] becomes a copy of its own, so editing it leaves its other uses alone.
func make_unique(path: String) -> bool:
	var e := entry(path)
	if e.is_empty() or path.is_empty():
		return false
	var parent := _owner_of(e)
	var copy := copy_tree(e["res"])
	if e["index"] >= 0:
		var list: Array = (parent.get(e["slot"]) as Array).duplicate()
		list[e["index"]] = copy
		return commit("Make %s unique" % short_name(e["res"]), [[parent, e["slot"], list]])
	return commit("Make %s unique" % short_name(e["res"]), [[parent, e["slot"], copy]])

## Adds a condition to [param move]'s [param list] (when, cancel_when).
func add_condition(move: Object, list: StringName, kind := MDSMoveCondition.Kind.PLAYER_NEAR) -> bool:
	var conditions: Array = (move.get(list) as Array).duplicate()
	conditions.append(MDSMoveCondition.make(kind, 200.0 if kind == MDSMoveCondition.Kind.PLAYER_NEAR else 0.0))
	return commit("Add a condition", [[move, list, conditions]])

func remove_condition(move: Object, list: StringName, index: int) -> bool:
	var conditions: Array = (move.get(list) as Array).duplicate()
	conditions.remove_at(index)
	return commit("Remove a condition", [[move, list, conditions]])

## A new phase for the boss: it starts at half the health of the last.
func add_phase() -> bool:
	if not has_phases() or read_only:
		return false
	var list: Array[MDSBossPhase] = phases().duplicate()
	var last := list[-1].health_threshold if not list.is_empty() else 2.0
	list.append(MDSMovePhase.of(last * 0.5, null))
	if not commit("Add a phase", [[target, &"phases", list]]):
		return false
	set_phase(list.size() - 1)
	return true

func remove_phase(index: int) -> bool:
	if not has_phases() or read_only or index < 0 or index >= phases().size():
		return false
	var list: Array[MDSBossPhase] = phases().duplicate()
	list.remove_at(index)
	return commit("Remove a phase", [[target, &"phases", list]])

## Gives the boss the fight of [param recipe], to change. One undo step brings back what it had.
func start_from_recipe(recipe: String) -> bool:
	if not has_phases():
		return false
	var tmp := MDSMoveBoss.new()
	MDSMoveRecipes.setup(tmp, recipe)
	var edits: Array = [[target, &"recipe", ""]]
	for prop in RECIPE_PROPS:
		edits.append([target, prop, tmp.get(prop)])
	tmp.free()
	var was := read_only
	read_only = false
	var ok := commit("Start from recipe %s" % recipe, edits)
	read_only = was and not ok
	return ok

## Copies a recipe or a fight built in code onto the boss, to change.
func make_editable() -> bool:
	if not read_only or not has_phases() or _preview.is_empty():
		return false
	var boss := target as MDSMoveBoss
	if not boss.recipe.is_empty():
		return start_from_recipe(boss.recipe)
	var list: Array[MDSBossPhase] = _preview.duplicate()
	read_only = false
	var ok := commit("Make the phases editable", [[target, &"phases", list]])
	read_only = not ok
	return ok

## The tab of the phase a running boss calls [param index], whose threshold is [param threshold]:
## the game sorts phases by health, the list here stays as written.
func tab_of_live_phase(index: int, threshold: float) -> int:
	var list := phases()
	for i in list.size():
		if is_equal_approx(list[i].health_threshold, threshold):
			return i
	return clampi(index, 0, maxi(0, list.size() - 1))

# --- What the graph says about a move ------------------------------------------------------------

## A move's class without the prefix ("Dash"), or a phase's or a node's.
static func short_name(res: Object) -> String:
	if res is Node:
		return String((res as Node).name)
	var script := res.get_script() as Script
	var global := script.get_global_name() if script else &""
	var text := String(global) if global != &"" else res.get_class()
	return text.trim_prefix("MDSMove").trim_prefix("MDS")

## What a condition says, in a few words.
static func describe(c: MDSMoveCondition) -> String:
	var kind := String(MDSMoveCondition.Kind.keys()[c.kind]).to_lower().replace("_", " ")
	var text := kind
	match c.kind:
		MDSMoveCondition.Kind.FLAG:
			text = "flag %s" % c.flag
		MDSMoveCondition.Kind.HEALTH_BELOW, MDSMoveCondition.Kind.CHANCE:
			text = "%s %d%%" % [kind, roundi(c.value * 100.0)]
		MDSMoveCondition.Kind.ALWAYS, MDSMoveCondition.Kind.PLAYER_BEHIND, MDSMoveCondition.Kind.PLAYER_IN_AIR, MDSMoveCondition.Kind.PLAYER_ON_WALL, MDSMoveCondition.Kind.PLAYER_OUTSIDE_ARENA, MDSMoveCondition.Kind.ON_FLOOR, MDSMoveCondition.Kind.AT_WALL:
			pass
		_:
			text = "%s %s" % [kind, _number(c.value)]
	return ("not " + text) if c.invert else text

static func _number(value: float) -> String:
	return String.num(snappedf(value, 0.01)).trim_suffix(".0")

static var _defaults: Dictionary = {}

## The values of [param res] that differ from a new one of its class, each "name value".
static func summary(res: Object, most := 4) -> PackedStringArray:
	var out := PackedStringArray()
	if not res is Resource:
		return out
	var script := res.get_script() as Script
	if not script or not script.can_instantiate():
		return out
	if not _defaults.has(script):
		_defaults[script] = script.new()
	var base: Object = _defaults[script]
	var skip := [&"title", &"when", &"cancel_when", &"attack", &"resource_name", &"moves", &"attack_states"]
	for s in MDSMoveTree.slots_of(res):
		skip.append(s["name"])
	for p: Dictionary in res.get_property_list():
		if not int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE or not int(p["usage"]) & PROPERTY_USAGE_EDITOR:
			continue
		var name := StringName(p["name"])
		if name in skip or res.get(name) == base.get(name) or int(p["type"]) in [TYPE_OBJECT, TYPE_DICTIONARY, TYPE_ARRAY]:
			continue
		out.append("%s %s" % [String(name).replace("_", " "), _shown(p, res.get(name))])
		if out.size() >= most:
			break
	return out

static func _shown(p: Dictionary, value: Variant) -> String:
	if int(p["type"]) == TYPE_INT and int(p["hint"]) == PROPERTY_HINT_ENUM:
		var names := String(p["hint_string"]).split(",")
		var at := int(value)
		if at >= 0 and at < names.size():
			return names[at].get_slice(":", 0).capitalize()
	if value is float:
		return _number(value)
	if value is Vector2:
		return "%d×%d" % [roundi(value.x), roundi(value.y)]
	if value is Color:
		return "#" + (value as Color).to_html(false)
	return str(value)
