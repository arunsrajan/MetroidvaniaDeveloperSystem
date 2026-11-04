@tool
class_name MDSFightCheck
extends RefCounted
## Finds what will go wrong in a fight before it is played. Each finding is
## [code]{phase, path, level, text}[/code]: [param path] is where it is in that phase's tree.

enum Level { INFO, WARNING, ERROR }

## All the findings of a fight: [param phases] of a boss, or a single [param root] (an enemy, a file).
static func check(phases: Array, root: Object = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var roots: Array = phases if not phases.is_empty() else ([root] if root else [])
	var set_flags := {}
	for r: Object in roots:
		for e in MDSMoveTree.walk(r):
			if e["res"] is MDSMoveCue and (e["res"] as MDSMoveCue).set_flag != &"":
				set_flags[(e["res"] as MDSMoveCue).set_flag] = true
	_check_phase_list(phases, out)
	for i in roots.size():
		var r: Object = roots[i]
		if r is MDSBossPhase and not r is MDSMovePhase:
			_add(out, i, "", Level.ERROR, "This phase has no moves of its own (MDSBossPhase). Use an MDSMovePhase.")
			continue
		if r is MDSMovePhase and not (r as MDSMovePhase).moves:
			_add(out, i, "", Level.ERROR, "Nothing to do in this phase: give it moves.")
		if r is MDSMoveEnemy and not (r as MDSMoveEnemy).moves:
			_add(out, i, "", Level.WARNING, "No moves: it only stands there, unless its script builds them.")
		for e in MDSMoveTree.walk(r):
			_check_move(e, i, set_flags, out)
	return out

static func _add(out: Array[Dictionary], phase: int, path: String, level: Level, text: String) -> void:
	out.append({"phase": phase, "path": path, "level": level, "text": text})

static func _check_phase_list(phases: Array, out: Array[Dictionary]) -> void:
	var seen := {}
	var highest := -1.0
	for i in phases.size():
		var p := phases[i] as MDSBossPhase
		if not p:
			continue
		highest = maxf(highest, p.health_threshold)
		if seen.has(p.health_threshold):
			_add(out, i, "", Level.WARNING, "Two phases start at the same health (%d%%): one of them never runs." % roundi(p.health_threshold * 100.0))
		seen[p.health_threshold] = true
	if highest >= 0.0 and highest < 1.0:
		_add(out, 0, "", Level.WARNING, "No phase starts at full health: it uses the first phase until it reaches its threshold.")

static func _check_move(e: Dictionary, phase: int, set_flags: Dictionary, out: Array[Dictionary]) -> void:
	var res: Object = e["res"]
	var path: String = e["path"]
	if not res is MDSMove:
		return
	var move := res as MDSMove
	var name := MDSFightDocument.short_name(move)
	if move is MDSMoveSequence and (move as MDSMoveSequence).moves.is_empty():
		_add(out, phase, path, Level.ERROR, "This sequence is empty.")
	if move is MDSMoveParallel and (move as MDSMoveParallel).moves.is_empty():
		_add(out, phase, path, Level.ERROR, "This parallel is empty.")
	if move is MDSMoveRepeat and not (move as MDSMoveRepeat).move:
		_add(out, phase, path, Level.ERROR, "Repeat what? It holds no move.")
	if move is MDSMoveRepeat and (move as MDSMoveRepeat).times == 0 and (move as MDSMoveRepeat).cancel_when.is_empty():
		_add(out, phase, path, Level.WARNING, "It repeats forever: give it a cancel condition, or a number of times.")
	if move is MDSMovePick:
		_check_pick(move as MDSMovePick, phase, path, out)
	if move is MDSMoveSequence and not (move as MDSMoveSequence).keep_going:
		for child: MDSMove in (move as MDSMoveSequence).moves:
			if child and (not child.when.is_empty() or child.cooldown > 0.0):
				_add(out, phase, path, Level.INFO, "When %s can't start, the rest of this sequence is skipped. Turn on keep going to skip only that move." % MDSFightDocument.short_name(child))
				break
	if move is MDSMoveSummon:
		var summon := move as MDSMoveSummon
		if summon.partner and summon.scene == null and summon.enemy_script == null:
			_add(out, phase, path, Level.ERROR, "A partner needs a scene or a script.")
		elif summon.scene == null and summon.enemy_script == null:
			_add(out, phase, path, Level.INFO, "It has no scene or script, so it calls an MDSFlyer.")
	if move is MDSMoveGuard and not (move as MDSMoveGuard).riposte:
		_add(out, phase, path, Level.INFO, "It blocks hits but doesn't answer them: it has no riposte.")
	for list: Array in [move.when, move.cancel_when]:
		for c: MDSMoveCondition in list:
			if not c:
				_add(out, phase, path, Level.ERROR, "%s has an empty condition." % name)
			elif c.kind == MDSMoveCondition.Kind.FLAG:
				if c.flag == &"":
					_add(out, phase, path, Level.ERROR, "%s tests a flag with no name." % name)
				elif not set_flags.has(c.flag):
					_add(out, phase, path, Level.WARNING, "%s tests the flag \"%s\", but no cue in this fight sets it." % [name, c.flag])

static func _check_pick(pick: MDSMovePick, phase: int, path: String, out: Array[Dictionary]) -> void:
	if pick.moves.is_empty():
		_add(out, phase, path, Level.ERROR, "This pick has nothing to pick from.")
		return
	var always_ready := false
	for child: MDSMove in pick.moves:
		if not child:
			_add(out, phase, path, Level.ERROR, "This pick has an empty place.")
		elif child.when.is_empty() and child.cooldown <= 0.0:
			always_ready = true
		if child and child.weight <= 0.0 and pick.mode == MDSMovePick.Mode.RANDOM:
			_add(out, phase, path, Level.WARNING, "%s has no weight, so it is hardly ever picked." % MDSFightDocument.short_name(child))
	if not always_ready:
		_add(out, phase, path, Level.WARNING, "Every move here has a condition or a cooldown. When none can start, the enemy stands still.")
