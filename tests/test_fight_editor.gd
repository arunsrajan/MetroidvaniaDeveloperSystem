extends "res://tests/test_case.gd"
## The Fight editor: finding moves in a fight, every edit with its undo, the checks, and the panel
## itself: its graph, what dragging does, its fields, and a running fight lit up on it.

const WORK := TMP + "/fight_editor"

## A move of a game's own holding others: it needs no code to show up in the editor.
class Combo extends MDSMove:
	@export var first: MDSMove
	@export var rest: Array[MDSMove] = []

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	DirAccess.make_dir_recursive_absolute(WORK)
	_tree()
	_edits()
	_undo()
	_conditions_and_copies()
	_recipes_and_phases()
	await _saved_fight_runs()
	_files()
	_checks()
	await _panel()
	await _panel_enemy()
	await _panel_scenes()
	await _live()

# --- Helpers -------------------------------------------------------------------------------------

func _phase() -> MDSMovePhase:
	var a := MDSMoveWait.of(0.1)
	a.title = "a"
	var b := MDSMoveWait.of(0.2)
	b.title = "b"
	var c := MDSMoveWait.of(0.3)
	c.title = "c"
	var pick := MDSMovePick.of([a, b] as Array[MDSMove])
	var seq := MDSMoveSequence.of([pick, c])
	return MDSMovePhase.of(1.0, seq)

func _doc(phases: Array[MDSBossPhase]) -> Array:
	var boss := MDSMoveBoss.new()
	boss.name = "Boss"
	boss.phases = phases
	var doc := MDSFightDocument.new()
	doc.open(boss)
	return [doc, boss]

func _titles(list: Array) -> String:
	return ",".join(list.map(func(m: MDSMove) -> String: return m.title))

# --- The tree ------------------------------------------------------------------------------------

func _tree() -> void:
	var names := func(o: Object) -> Array:
		return MDSMoveTree.slots_of(o).map(func(s: Dictionary) -> StringName: return s["name"])
	check(names.call(MDSMovePhase.new()) == [&"moves", &"opening", &"reactions"], "a phase holds moves, an opening and reactions (%s)" % [names.call(MDSMovePhase.new())])
	check(names.call(MDSMoveSequence.new()) == [&"moves"], "a sequence holds moves")
	check(names.call(MDSMoveRepeat.new()) == [&"move"], "a repeat holds one")
	check(names.call(MDSMoveGuard.new()) == [&"riposte"], "a guard holds its riposte")
	check(names.call(MDSMoveWait.new()) == [], "a wait holds nothing")
	var enemy := MDSMoveEnemy.new()
	check(names.call(enemy) == [&"moves"], "an enemy holds its moves")
	enemy.free()
	var boss := MDSMoveBoss.new()
	check(names.call(boss) == [], "a boss's moves are in its phases")
	boss.free()
	var combo := Combo.new()
	check(names.call(combo) == [&"first", &"rest"], "a move of your own holding moves needs no code (%s)" % [names.call(combo)])

	var entries := MDSMoveTree.walk(_phase())
	var paths: Array = entries.map(func(e: Dictionary) -> String: return e["path"])
	check(paths == ["", "moves", "moves/moves.0", "moves/moves.0/moves.0", "moves/moves.0/moves.1", "moves/moves.1"], "every move has its path (%s)" % [paths])
	check(entries[3]["depth"] == 3 and entries[3]["index"] == 0 and entries[3]["slot"] == &"moves", "and knows its place")

	var round_and_round := MDSMoveSequence.new()
	round_and_round.moves = [round_and_round]
	check(MDSMoveTree.walk(round_and_round).size() == 2, "a move holding itself doesn't hang the walk")

	check(MDSMoveTree.is_move_class("MDSMoveDash") and not MDSMoveTree.is_move_class("MDSBoss"), "it knows a move class")

# --- Edits ---------------------------------------------------------------------------------------

func _edits() -> void:
	var got := _doc([_phase()] as Array[MDSBossPhase])
	var doc: MDSFightDocument = got[0]
	var boss: MDSMoveBoss = got[1]
	var phase := boss.phases[0] as MDSMovePhase
	var seq := phase.moves as MDSMoveSequence
	var pick := seq.moves[0] as MDSMovePick
	var fired := [0]
	doc.changed.connect(func() -> void: fired[0] += 1)

	var d := MDSMoveWait.of(0.4)
	d.title = "d"
	check(doc.add_move(d, "moves", &"moves"), "a move goes at the end")
	check(seq.moves.size() == 3 and seq.moves[2] == d, "of what it was put in")
	check(fired[0] == 1, "and it says so")
	check(seq.moves.is_typed(), "the list stays typed")
	var e := MDSMoveWait.of(0.5)
	e.title = "e"
	check(doc.add_move(e, "moves", &"moves", 0) and seq.moves[0] == e, "or where it is told")
	check(not doc.add_move(MDSMoveWait.new(), "", &"moves"), "a place holding a move has no room")
	check(not doc.has_room("", &"moves") and doc.has_room("", &"opening") and doc.has_room("", &"reactions"), "it knows where there is room")
	check(doc.add_move(MDSMoveCue.new(), "", &"opening") and phase.opening is MDSMoveCue, "the empty opening does")

	check(doc.remove("moves/moves.0") and seq.moves[0] == pick, "a move comes out")
	check(not doc.remove(""), "the root stays")
	check(not doc.remove("nowhere"), "nothing is taken from nowhere")
	check(doc.remove("opening") and phase.opening == null, "a single place is emptied")

	# seq: [pick(a, b), c, d]
	check(doc.move_to("moves/moves.1", "moves/moves.0", &"moves"), "a move goes into another")
	check(_titles(pick.moves) == "a,b,c" and _titles(seq.moves.slice(1)) == "d", "out of where it was (%s)" % _titles(pick.moves))
	check(doc.move_to("moves/moves.0/moves.2", "moves/moves.0", &"moves", 0), "and to another place among its siblings")
	check(_titles(pick.moves) == "c,a,b", "keeping the rest in order (%s)" % _titles(pick.moves))
	check(not doc.move_to("moves", "moves/moves.0", &"moves"), "not inside itself")
	check(not doc.move_to("moves/moves.0", "moves/moves.0", &"moves"), "not into itself")
	check(not doc.move_to("moves/moves.1", "", &"moves"), "not where there's no room")
	check(doc.reorder("moves/moves.0", &"moves", [2, 0, 1]) and _titles(pick.moves) == "b,c,a", "reordered (%s)" % _titles(pick.moves))
	check(not doc.reorder("moves/moves.0", &"moves", [0, 1, 2]), "the same order isn't an edit")
	check(not doc.reorder("moves/moves.0", &"moves", [0]), "nor is a wrong one")
	check(doc.set_value(pick, &"no_repeat", false) and not pick.no_repeat, "a value is set")

	var again: MDSMove = pick.moves[0]
	pick.moves = [again, again]
	doc.open(boss)
	check(doc.uses_of(again) == 2, "a move used twice shows as twice")
	boss.free()

func _undo() -> void:
	var got := _doc([_phase()] as Array[MDSBossPhase])
	var doc: MDSFightDocument = got[0]
	var boss: MDSMoveBoss = got[1]
	var seq := (boss.phases[0] as MDSMovePhase).moves as MDSMoveSequence
	var undo := doc.undo as UndoRedo
	var before := seq.moves.duplicate()
	check(doc.remove("moves/moves.1") and seq.moves.size() == 1, "removed")
	check(doc.entry("moves/moves.1").is_empty(), "and gone from the graph")
	undo.undo()
	check(seq.moves == before, "undo brings it back")
	check(not doc.entry("moves/moves.1").is_empty(), "to the graph too")
	undo.redo()
	check(seq.moves.size() == 1, "redo takes it out")
	undo.undo()
	var wait := seq.moves[1] as MDSMoveWait
	doc.set_value(wait, &"seconds", 9.0)
	var values := [0]
	var shapes := [0]
	doc.values_changed.connect(func() -> void: values[0] += 1)
	doc.changed.connect(func() -> void: shapes[0] += 1)
	doc.set_value(wait, &"seconds", 8.0)
	check(values[0] == 1 and shapes[0] == 0, "setting a value leaves the fields alone")
	undo.undo()
	check(is_equal_approx(wait.seconds, 9.0) and shapes[0] == 1, "undoing it shows the old value")
	var v := undo.get_version()
	check(not doc.commit("Nothing", []) and undo.get_version() == v, "no edits, no undo step")
	boss.free()

func _conditions_and_copies() -> void:
	var got := _doc([_phase()] as Array[MDSBossPhase])
	var doc: MDSFightDocument = got[0]
	var boss: MDSMoveBoss = got[1]
	var seq := (boss.phases[0] as MDSMovePhase).moves as MDSMoveSequence
	var c := seq.moves[1] as MDSMove
	check(doc.add_condition(c, &"when") and c.when.size() == 1, "a condition is added")
	check(MDSFightDocument.describe(c.when[0]) == "player near 200", "and described (%s)" % MDSFightDocument.describe(c.when[0]))
	check(MDSFightDocument.describe(MDSMoveCondition.make(MDSMoveCondition.Kind.HEALTH_BELOW, 0.5, true)) == "not health below 50%", "health reads as a share")
	check(MDSFightDocument.describe(MDSMoveCondition.make(MDSMoveCondition.Kind.FLAG, 0.0, false, &"seen")) == "flag seen", "a flag by name")
	check(doc.remove_condition(c, &"when", 0) and c.when.is_empty(), "and removed")

	var shared := MDSMoveStrike.new()
	shared.when = [MDSMoveCondition.make(MDSMoveCondition.Kind.PLAYER_NEAR, 100.0)]
	var inner := MDSMoveSequence.of([shared, shared])
	var copy := MDSFightDocument.copy_tree(inner) as MDSMoveSequence
	check(copy != inner and copy.moves[0] != shared, "a copy shares nothing with what it was copied from")
	check(copy.moves[0] == copy.moves[1], "a move used twice inside it stays one move")
	check(copy.moves[0].when[0] != shared.when[0] and copy.moves[0].when.is_typed(), "its conditions are its own")
	var size := seq.moves.size()
	check(doc.duplicate_at("moves/moves.0") and seq.moves.size() == size + 1, "a duplicate goes right after")
	check(seq.moves[1] != seq.moves[0] and seq.moves[1] is MDSMovePick, "and is a copy")
	check(not doc.duplicate_at("moves"), "a place holding one has no room for a duplicate")

	seq.moves[1] = seq.moves[0]
	doc.open(boss)
	var was: MDSMove = seq.moves[0]
	check(doc.uses_of(was) == 2, "used twice")
	check(doc.make_unique("moves/moves.1") and seq.moves[1] != was and seq.moves[0] == was, "made unique, only that place changes")
	var parts := MDSFightDocument.summary(MDSMoveDash.of(MDSMoveDash.Aim.AWAY_FROM_PLAYER, 123.0, 0.5))
	check("aim Away From Player" in parts and "speed 123" in parts, "a node says what differs from a new one (%s)" % parts)
	boss.free()

func _recipes_and_phases() -> void:
	var boss := MDSMoveBoss.new()
	boss.name = "Boss"
	boss.recipe = "duelist"
	boss.boss_name = "Lady"
	var doc := MDSFightDocument.new()
	doc.open(boss)
	check(doc.read_only and doc.read_only_reason.contains("duelist"), "a recipe shows read-only")
	check(doc.phases().size() == 3 and doc.entries().size() > 5, "with its phases")
	check(boss.phases.is_empty() and boss.recipe == "duelist", "without changing the boss")
	check(not doc.remove("moves"), "nothing can be edited")
	check(not doc.add_phase(), "not even a phase")
	check(doc.make_editable(), "until it is made editable")
	check(not doc.read_only and boss.phases.size() == 3 and boss.recipe.is_empty(), "then the boss has the phases")
	check(boss.stagger_hits == 16, "and the rest of the recipe")
	(doc.undo as UndoRedo).undo()
	check(doc.read_only and boss.phases.is_empty() and boss.recipe == "duelist" and boss.stagger_hits == 0, "undo puts it all back")
	check(doc.start_from_recipe("twin_swooper") and boss.phases.size() == 1 and boss.on_death != null, "any recipe can start a fight")
	check(not boss.uses_gravity, "and its body")

	check(doc.add_phase() and boss.phases.size() == 2 and doc.phase_index == 1, "a phase is added and opened")
	check(is_equal_approx(boss.phases[1].health_threshold, 0.5), "at half the last")
	check(doc.root() == boss.phases[1], "and shown")
	check(doc.remove_phase(1) and boss.phases.size() == 1 and doc.phase_index == 0, "and removed")
	boss.phases[0].health_threshold = 0.5
	check(doc.tab_of_live_phase(0, 0.5) == 0, "a running phase finds its tab by health")
	boss.free()

func _saved_fight_runs() -> void:
	var boss := MDSMoveBoss.new()
	boss.name = "Boss"
	boss.boss_name = "Saved"
	var doc := MDSFightDocument.new()
	doc.open(boss)
	doc.start_from_recipe("twin_swooper")
	var path := WORK + "/fight.tscn"
	var root := Node2D.new()
	root.name = "Root"
	root.add_child(boss)
	check(save_scene(root, path) == OK, "a fight made in the editor saves in its scene")
	root.free()
	var loaded := (load_fresh(path) as PackedScene).instantiate() as Node2D
	var back := loaded.get_node("Boss") as MDSMoveBoss
	check(back.phases.size() == 1 and back.phases[0] is MDSMovePhase, "and comes back")
	check(back.on_death != null and back.on_death.partner, "with what it does when it dies")
	var phase := back.phases[0] as MDSMovePhase
	var entries := MDSMoveTree.walk(phase)
	check(entries.size() > 10, "all of it (%d moves)" % entries.size())
	var uses := 0
	var seen_ceiling: MDSMove = null
	var one_move := true
	for e in entries:
		if e["res"] is MDSMoveFly and (e["res"] as MDSMoveFly).target == MDSMove.Anchor.CEILING_ABOVE_SELF:
			uses += 1
			one_move = one_move and (seen_ceiling == null or seen_ceiling == e["res"])
			seen_ceiling = e["res"]
	check(uses >= 2 and one_move, "a shared move stays shared when saved")
	add_child(loaded)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = MDSGameplaySetup.bit("world")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(3000, 100)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.position = Vector2(0, 700)
	loaded.add_child(floor_body)
	var player := CharacterBody2D.new()
	player.add_to_group(&"player")
	player.collision_layer = 0
	loaded.add_child(player)
	player.position = Vector2(-200, 600)
	back.position = Vector2(200, 300)
	await physics_frames(2)
	back.start_fight()
	await physics_frames(20)
	check(back.fight._current != null, "it runs in the game")
	loaded.queue_free()
	await get_tree().process_frame

func _files() -> void:
	var path := WORK + "/phase.tres"
	check(ResourceSaver.save(_phase(), path) == OK, "a phase saved in a file")
	var phase := load_fresh(path) as MDSMovePhase
	var doc := MDSFightDocument.new()
	doc.open(phase)
	check(doc.root() == phase and not doc.has_phases(), "opens by itself")
	var seq := phase.moves as MDSMoveSequence
	check(doc.remove("moves/moves.1") and seq.moves.size() == 1, "edited")
	var again := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MDSMovePhase
	check((again.moves as MDSMoveSequence).moves.size() == 1, "and saved at once")
	var move := MDSMoveSequence.of([MDSMoveWait.of(1.0)])
	doc.open(move)
	check(doc.entries().size() == 2 and doc.root() == move, "a single move opens too")

func _has(findings: Array[Dictionary], level: int, text: String) -> bool:
	for f in findings:
		if f["level"] == level and String(f["text"]).contains(text):
			return true
	return false

func _checks() -> void:
	var L := MDSFightCheck.Level
	check(MDSFightCheck.check([_phase()]).is_empty(), "a sound fight has nothing to report (%s)" % [MDSFightCheck.check([_phase()])])
	check(_has(MDSFightCheck.check([MDSMovePhase.new()]), L.ERROR, "give it moves"), "a phase with no moves")
	check(_has(MDSFightCheck.check([MDSBossPhase.new()]), L.ERROR, "MDSMovePhase"), "a phase of the wrong kind")
	var dup := [MDSMovePhase.of(1.0, MDSMoveWait.new()), MDSMovePhase.of(1.0, MDSMoveWait.new())]
	check(_has(MDSFightCheck.check(dup), L.WARNING, "same health"), "two phases at the same health")
	check(_has(MDSFightCheck.check([MDSMovePhase.of(0.5, MDSMoveWait.new())]), L.WARNING, "full health"), "no phase at full health")
	check(_has(MDSFightCheck.check([], MDSMoveSequence.new()), L.ERROR, "empty"), "an empty sequence")
	check(_has(MDSFightCheck.check([], MDSMovePick.new()), L.ERROR, "nothing to pick"), "an empty pick")
	check(_has(MDSFightCheck.check([], MDSMoveRepeat.new()), L.ERROR, "holds no move"), "an empty repeat")
	var forever := MDSMoveRepeat.of(MDSMoveWait.new(), 0)
	check(_has(MDSFightCheck.check([], forever), L.WARNING, "forever"), "a repeat with no end")
	var gated := MDSMoveWait.new()
	gated.cooldown = 3.0
	check(_has(MDSFightCheck.check([], MDSMovePick.of([gated] as Array[MDSMove])), L.WARNING, "stands still"), "a pick that can stall")
	var part := MDSMoveSummon.new()
	part.partner = true
	check(_has(MDSFightCheck.check([], part), L.ERROR, "partner"), "a partner of nothing")
	var flagged := MDSMoveWait.new()
	flagged.when = [MDSMoveCondition.make(MDSMoveCondition.Kind.FLAG, 0.0, false, &"seen")]
	check(_has(MDSFightCheck.check([], flagged), L.WARNING, "no cue"), "a flag nothing sets")
	var seq := MDSMoveSequence.of([MDSMoveCue.of(0.0, 0.0, &"seen"), flagged])
	check(not _has(MDSFightCheck.check([], seq), L.WARNING, "no cue"), "a flag a cue sets")
	check(_has(MDSFightCheck.check([], seq), L.INFO, "keep going"), "a condition that cuts a sequence short")
	var enemy := MDSMoveEnemy.new()
	check(_has(MDSFightCheck.check([], enemy), L.WARNING, "No moves"), "an enemy with no moves")
	enemy.free()
	for recipe: String in MDSMoveRecipes.RECIPES:
		var boss := MDSMoveBoss.new()
		MDSMoveRecipes.setup(boss, recipe)
		var findings := MDSFightCheck.check(boss.phases)
		check(not findings.any(func(f: Dictionary) -> bool: return f["level"] == L.ERROR), "%s has no errors (%s)" % [recipe, findings])
		boss.free()

# --- The panel -----------------------------------------------------------------------------------

func _make_panel() -> MDSFightPanel:
	var panel := MDSFightPanel.new()
	panel.size = Vector2(1400, 800)
	add_child(panel)
	await get_tree().process_frame
	return panel

func _node_of(panel: MDSFightPanel, path: String) -> GraphNode:
	return panel.nodes_by_path.get(path)

func _field(panel: MDSFightPanel, prop: String) -> Control:
	return panel.fields.find_child("Field_" + prop, true, false) as Control

func _panel() -> void:
	var panel := await _make_panel()
	check(panel.banner.visible and panel.nodes_by_path.is_empty(), "nothing open: it says what to do")
	check(panel.toolbar != null and panel.side_panel.header != null, "the host's switches have a place")
	check(panel.add_box.find_child("Add_MDSMoveDash", true, false) != null, "every kind of move can be added")
	check(panel.add_box.find_child("Add_MDSMoveZones", true, false) != null, "zones too")

	var boss := MDSMoveBoss.new()
	boss.name = "Boss"
	boss.phases = [_phase(), MDSMovePhase.of(0.5, MDSMoveGuard.of(0.5, MDSMoveWait.of(1.0)))] as Array[MDSBossPhase]
	panel.set_target(boss)
	var doc := panel.doc
	check(not panel.banner.visible, "opened")
	check(panel.phase_tabs.tab_count == 2 and panel.phase_tabs.get_tab_title(1) == "Phase 2 (50%)", "a tab for each phase")
	check(panel.nodes_by_path.size() == doc.entries().size(), "a node for each move (%d)" % panel.nodes_by_path.size())
	check(panel.graph.get_connection_list().size() == doc.entries().size() - 1, "a line for each")
	check(_node_of(panel, "moves/moves.0/moves.0").title == "a", "a move shows its title")
	var root := _node_of(panel, "")
	check(root.get_node_or_null("Slot_reactions") != null, "a phase shows where moves go")
	check(_node_of(panel, "moves/moves.0").position_offset.y < _node_of(panel, "moves/moves.1").position_offset.y, "siblings stand in their order")
	check(_node_of(panel, "moves").position_offset.x > root.position_offset.x, "children to the right")

	# Dragging a line: c into the pick.
	var seq := (boss.phases[0] as MDSMovePhase).moves as MDSMoveSequence
	var pick := seq.moves[0] as MDSMovePick
	panel.graph.connection_request.emit(_node_of(panel, "moves/moves.0").name, 0, _node_of(panel, "moves/moves.1").name, 0)
	check(pick.moves.size() == 3 and seq.moves.size() == 1, "a line dragged puts a move there")
	check(panel.nodes_by_path.has("moves/moves.0/moves.2"), "the graph follows")
	panel.graph.connection_request.emit(_node_of(panel, "moves/moves.0").name, 0, _node_of(panel, "moves").name, 0)
	check(pick.moves.size() == 3 and panel.status.text.contains("inside itself"), "it can't go inside itself, and says so")
	(doc.undo as UndoRedo).undo()
	check(seq.moves.size() == 2, "undo")

	# Pulling a line off.
	panel.graph.disconnection_request.emit(_node_of(panel, "moves").name, 0, _node_of(panel, "moves/moves.1").name, 0)
	check(seq.moves.size() == 1, "a line pulled off takes the move out")
	(doc.undo as UndoRedo).undo()

	# Delete key.
	panel.graph.delete_nodes_request.emit([_node_of(panel, "moves/moves.0/moves.0").name, _node_of(panel, "moves/moves.0/moves.1").name, _node_of(panel, "").name] as Array[StringName])
	check(pick.moves.is_empty(), "several deleted, the root stays")
	check(panel.issues.visible and panel.issues.item_count > 0, "an empty pick is reported under the graph")
	check(_node_of(panel, "moves/moves.0").get_node_or_null("Problem") != null, "and marked on its node")
	(doc.undo as UndoRedo).undo()
	(doc.undo as UndoRedo).undo()
	check(_titles(pick.moves) == "a,b" and not panel.issues.visible, "both back, nothing to report")

	# Dragging a move below its sibling.
	var a_node := _node_of(panel, "moves/moves.0/moves.0")
	var b_node := _node_of(panel, "moves/moves.0/moves.1")
	a_node.selected = true
	a_node.position_offset.y = b_node.position_offset.y + 50.0
	panel.graph.end_node_move.emit()
	check(_titles(pick.moves) == "b,a", "dragged below its sibling, it goes after (%s)" % _titles(pick.moves))
	var nudged := _node_of(panel, "moves/moves.0/moves.1")
	var settled := nudged.position_offset
	nudged.selected = true
	nudged.position_offset.x += 300.0
	panel.graph.end_node_move.emit()
	check(_node_of(panel, "moves/moves.0/moves.1").position_offset == settled, "dragged anywhere else, it settles back")
	(doc.undo as UndoRedo).undo()

	# Selecting shows its fields.
	panel.graph.node_selected.emit(_node_of(panel, "moves/moves.1"))
	check(panel.selected_path == "moves/moves.1", "selected")
	var seconds := _field(panel, "seconds") as SpinBox
	check(seconds != null, "its fields come from its exports")
	var c := seq.moves[1] as MDSMoveWait
	seconds.value = 2.5
	check(is_equal_approx(c.seconds, 2.5), "a number field sets its value")
	check(_field(panel, "seconds") == seconds, "and stays while you type")
	var check_box := _field(panel, "face_player") as CheckBox
	check_box.button_pressed = false
	check(not c.face_player, "a check field")
	var line := _field(panel, "title") as LineEdit
	line.text = "Renamed"
	line.text_submitted.emit("Renamed")
	check(c.title == "Renamed", "a text field")
	check(_node_of(panel, "moves/moves.1").title == "Renamed", "the graph says so")
	check(_field(panel, "boss_name") != null and _field(panel, "stagger_hits") != null, "and the boss's own")

	var add := panel.fields.find_child("Conditions_when", true, false).get_node("Add") as Button
	add.pressed.emit()
	check(c.when.size() == 1, "a condition is added")
	var row := panel.fields.find_child("Condition_when_0", true, false)
	check(row != null, "and shown")
	(row.get_node("Value") as SpinBox).value = 333.0
	check(is_equal_approx(c.when[0].value, 333.0), "its value is set")
	(row.get_node("Kind") as OptionButton).item_selected.emit(MDSMoveCondition.Kind.FLAG)
	check(c.when[0].kind == MDSMoveCondition.Kind.FLAG, "its kind is set")
	row = panel.fields.find_child("Condition_when_0", true, false)
	check(row.get_node_or_null("Flag") != null, "a flag asks for a name")
	(row.get_node("Remove") as Button).pressed.emit()
	check(c.when.is_empty(), "and it goes")

	# Adding: after the selected, or in it.
	check(panel.add_where.item_count == 1 and panel.add_where.get_item_text(0) == "After this move", "a plain move can only be followed")
	check(panel.add_new((MDSMoveDash as Script).resource_path), "a new move goes after it")
	check(seq.moves.size() == 3 and seq.moves[2] is MDSMoveDash, "there")
	check(panel.selected_path == "moves/moves.2", "and is selected")
	panel.graph.node_selected.emit(_node_of(panel, "moves"))
	check(panel.add_where.get_item_text(0) == "In moves", "a pattern holds it")
	check(panel.add_new((MDSMoveCue as Script).resource_path) and seq.moves[3] is MDSMoveCue, "at its end")
	panel.graph.node_selected.emit(_node_of(panel, ""))
	var offered: Array = []
	for i in panel.add_where.item_count:
		offered.append(panel.add_where.get_item_text(i))
	check(offered == ["In opening", "In reactions"], "a full place isn't offered (%s)" % [offered])
	panel.selected_path = "moves/moves.3"
	panel._refresh()
	panel._shift(-1)
	check(seq.moves[2] is MDSMoveCue and panel.selected_path == "moves/moves.2", "up, and it stays selected")
	panel._shift(-100)
	check(seq.moves[2] is MDSMoveCue, "nowhere to go, it stays")

	# Phases.
	panel.phase_tabs.current_tab = 1
	check(doc.phase_index == 1 and panel.selected_path == "", "a tab opens its phase")
	check(panel.nodes_by_path.has("moves/riposte"), "a guard shows its riposte")
	panel.graph.connection_request.emit(_node_of(panel, "moves").name, 0, _node_of(panel, "moves/riposte").name, 0)
	check(panel.status.text.contains("already holds"), "a full place refuses a line")

	# A recipe shows read-only, and comes in by one click.
	var other := MDSMoveBoss.new()
	other.name = "Other"
	other.recipe = "showman"
	panel.set_target(other)
	check(panel.banner.visible and panel.banner.get_node("MakeEditable").visible, "a recipe offers to be made editable")
	check(panel.nodes_by_path.size() > 3, "and shows")
	panel.graph.node_selected.emit(_node_of(panel, "moves"))
	check(panel.add_new((MDSMoveCue as Script).resource_path) == false, "adding is refused")
	panel.graph.delete_nodes_request.emit([_node_of(panel, "moves").name] as Array[StringName])
	check(other.phases.is_empty(), "so is deleting")
	var inner := panel.fields.find_child("Add", true, false) as Button
	check(inner != null and inner.disabled, "its fields are off")
	(panel.banner.get_node("MakeEditable") as Button).pressed.emit()
	check(other.phases.size() == 2 and not panel.banner.visible, "one click and it is the boss's own")
	panel.recipe_picker.item_selected.emit(1)
	check(other.phases.size() == 1, "and a recipe comes in by its menu")
	other.free()
	boss.free()
	panel._refresh()
	check(not panel.doc.is_open() and panel.nodes_by_path.is_empty(), "when what it shows is gone, it empties")
	panel.queue_free()
	await get_tree().process_frame

func _panel_enemy() -> void:
	var panel := await _make_panel()
	var enemy := MDSMoveEnemy.new()
	enemy.name = "Grub"
	panel.set_target(enemy)
	check(not panel.phase_tabs.visible, "an enemy has no phase tabs")
	check(panel.nodes_by_path.size() == 1 and _node_of(panel, "").title == "Grub", "it shows itself")
	check(panel.issues.item_count == 1, "with nothing to do, it says so")
	check(not panel.doc.add_phase(), "it can't have phases")
	panel._refresh()
	check(panel.add_where.get_item_text(0) == "In moves", "moves go in it")
	check(_field(panel, "wait_to_see") != null, "and its own field")
	check(panel.add_new((MDSMoveSequence as Script).resource_path) and enemy.moves is MDSMoveSequence, "its first move")
	check(panel.selected_path == "moves", "selected")
	check(panel.add_new((MDSMoveWait as Script).resource_path), "and more in it")
	check((enemy.moves as MDSMoveSequence).moves.size() == 1, "there")
	check(panel.graph.get_connection_list().size() == 2, "joined up")
	enemy.free()
	panel.queue_free()
	await get_tree().process_frame

func _panel_scenes() -> void:
	var panel := await _make_panel()
	var first := Node2D.new()
	var boss := MDSMoveBoss.new()
	boss.name = "FirstBoss"
	boss.recipe = "swooper"
	first.add_child(boss)
	var second := Node2D.new()
	var enemy := MDSMoveEnemy.new()
	enemy.name = "SecondEnemy"
	second.add_child(enemy)
	var plain := Node2D.new()
	panel.on_scene_changed(first)
	check(panel.fighter_picker.get_item_text(0) == "FirstBoss", "the fighters of the scene are listed")
	check(panel.doc.target == boss, "a scene opens on its first fighter")
	check(panel.fighter_picker.selected == 0, "the list shows which")
	panel.on_scene_changed(second)
	check(panel.fighter_picker.get_item_text(0) == "SecondEnemy", "another scene: the list follows")
	check(panel.doc.target == enemy, "and so does the graph")
	panel.on_scene_changed(plain)
	check(not panel.doc.is_open(), "a scene with no fighters shows none")
	check(panel.fighter_picker.is_item_disabled(0), "and says so")
	check(panel.fighter_picker.selected == -1, "with nothing picked")
	panel.on_scene_changed(first)
	boss.free()
	panel.on_scene_changed(first)
	check(not panel.doc.is_open(), "a fighter that is gone is let go of")
	check(panel.nodes_by_path.is_empty(), "and leaves the graph")
	var fight := MDSMovePhase.new()
	panel.set_target(fight)
	panel.on_scene_changed(second)
	check(panel.doc.target == fight, "a fight file stays open when the scene changes")
	check(panel.fighter_picker.selected == -1, "and is not one of the listed fighters")
	panel.queue_free()
	first.free()
	second.free()
	plain.free()
	await get_tree().process_frame

func _stage() -> Node2D:
	var stage := Node2D.new()
	add_child(stage)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = MDSGameplaySetup.bit("world")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(3000, 100)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.position = Vector2(0, 700)
	stage.add_child(floor_body)
	var player := CharacterBody2D.new()
	player.add_to_group(&"player")
	player.collision_layer = 0
	player.position = Vector2(-300, 600)
	stage.add_child(player)
	return stage

func _live() -> void:
	var panel := await _make_panel()
	var stage := _stage()
	var slow := MDSMoveWait.of(100.0)
	slow.title = "slow"
	var quick := MDSMoveCue.of(0.0)
	quick.cooldown = 50.0
	quick.set_flag = &"seen"
	var seq := MDSMoveSequence.of([quick, slow])
	seq.keep_going = true
	var boss := MDSMoveBoss.new()
	boss.name = "Boss"
	boss.phases = [MDSMovePhase.of(1.0, seq), MDSMovePhase.of(0.5, MDSMoveWait.of(100.0))] as Array[MDSBossPhase]
	stage.add_child(boss)
	boss.position = Vector2(300, 600)
	await physics_frames(2)
	boss.start_fight()
	await physics_frames(5)
	var s := MDSMoveTree.snapshot(boss.fight)
	check(s["kind"] == "boss" and s["name"] == "Boss" and s["state"] == "Idle", "a snapshot says who and what state")
	check(Array(s["active"]) == ["moves", "moves/moves.1"], "and what is running (%s)" % s["active"])
	check(s["cooling"].has("moves/moves.0") and float(s["cooling"]["moves/moves.0"]) > 40.0, "what is cooling down")
	check(s["flags"].get(&"seen", false), "its flags")
	check(s["health"] == boss.health.current, "its health")
	check(bytes_to_var(var_to_bytes(s)) is Dictionary, "and it travels")

	var editing := MDSMoveBoss.new()
	editing.name = "Boss"
	editing.phases = [MDSMovePhase.of(1.0, MDSFightDocument.copy_tree(seq)), MDSMovePhase.of(0.5, MDSMoveWait.of(100.0))] as Array[MDSBossPhase]
	panel.set_target(editing)
	panel.apply_live(s)
	check(_node_of(panel, "moves/moves.1").get_meta(&"live", false), "what is running lights up")
	check(_node_of(panel, "moves/moves.1").title.begins_with("▶"), "with a mark")
	check(not _node_of(panel, "moves/moves.0").get_meta(&"live", false), "what isn't stays dark")
	check(_node_of(panel, "moves/moves.0").title.contains("s)"), "a cooldown counts down on its node")
	check(panel.live_text.text.contains("Idle") and panel.live_text.text.contains("seen"), "the side says its state and flags")
	check(panel.live_picker.item_count == 1, "it is listed")

	boss.health.set_current(int(boss.health.get_max() * 0.4))
	await physics_frames(int(boss.phase_pause * 60.0) + 10)
	panel.apply_live(MDSMoveTree.snapshot(boss.fight))
	check(panel.doc.phase_index == 1, "a new phase in the game opens its tab")
	check(_node_of(panel, "moves").get_meta(&"live", false), "lit up too")

	var nobody := MDSMoveBoss.new()
	nobody.name = "Stranger"
	panel.set_target(nobody)
	check(panel.live_text.text.contains("Pick"), "a fighter who isn't running: pick one")
	panel.live_picker.select(0)
	panel.live_picker.item_selected.emit(0)
	check(not panel.live_follow, "a pick is kept")
	panel.clear_live()
	check(panel.live.is_empty() and panel.live_picker.item_count == 0, "the game stopping clears it")

	panel.apply_live(MDSMoveTree.snapshot(boss.fight))
	panel.live[boss.get_instance_id()]["at"] = 0
	panel._forget_stale_fighters()
	check(panel.live.is_empty(), "a fighter gone silent is forgotten")

	var enemy := MDSMoveEnemy.new()
	enemy.name = "Grub"
	enemy.moves = MDSMoveSequence.of([MDSMoveWait.of(100.0)])
	enemy.wait_to_see = false
	stage.add_child(enemy)
	enemy.position = Vector2(500, 600)
	await physics_frames(5)
	var snap := MDSMoveTree.snapshot(enemy.machine.current as MDSMoveState)
	check(snap["kind"] == "enemy", "an enemy reports too")
	check(Array(snap["active"]) == ["moves", "moves/moves.0"], "what it is running (%s)" % snap["active"])
	var same := MDSMoveEnemy.new()
	same.name = "Grub"
	same.moves = MDSMoveSequence.of([MDSMoveWait.of(1.0)])
	panel.set_target(same)
	panel.apply_live(snap)
	check(_node_of(panel, "moves/moves.0").get_meta(&"live", false), "and lights up on its own graph")
	same.free()
	nobody.free()
	editing.free()
	stage.queue_free()
	panel.queue_free()
	await get_tree().process_frame
