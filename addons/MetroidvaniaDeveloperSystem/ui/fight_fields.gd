@tool
class_name MDSFightFields
extends RefCounted
## The fields the Fight editor shows for a selected move, made from its exports, so a move of your
## own gets them without further code. Each control is named after its property ("Field_speed").

const CONDITION_LISTS: Array[StringName] = [&"when", &"cancel_when"]
const HIDDEN: Array[StringName] = [&"attack_states", &"enter_animation"]

## Adds the fields of [param obj] to [param box]. [param only]: just these properties.
static func build(box: Container, doc: MDSFightDocument, obj: Object, only: Array[StringName] = []) -> void:
	var slots := MDSMoveTree.slots_of(obj).map(func(s: Dictionary) -> StringName: return s["name"])
	var grid := _grid(box)
	for p: Dictionary in obj.get_property_list():
		var usage := int(p["usage"])
		var name := StringName(p["name"])
		if usage & PROPERTY_USAGE_GROUP and only.is_empty():
			var head := MDSUi.label(String(name))
			head.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
			box.add_child(head)
			grid = _grid(box)
			continue
		if not usage & PROPERTY_USAGE_SCRIPT_VARIABLE or not usage & PROPERTY_USAGE_EDITOR:
			continue
		if name in slots or name in HIDDEN or name in CONDITION_LISTS or (not only.is_empty() and not name in only):
			continue
		var label := Label.new()
		label.text = String(name).capitalize()
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var field := _field(doc, obj, p)
		field.name = "Field_%s" % name
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.tooltip_text = String(name)
		grid.add_child(field)

static func _grid(box: Container) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	return grid

static func _field(doc: MDSFightDocument, obj: Object, p: Dictionary) -> Control:
	var name := StringName(p["name"])
	var value: Variant = obj.get(name)
	var hint := int(p["hint"])
	var hints := String(p["hint_string"])
	match int(p["type"]):
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(func(on: bool) -> void: doc.set_value(obj, name, on))
			return check
		TYPE_INT:
			if hint == PROPERTY_HINT_ENUM:
				return _enum(doc, obj, name, hints, value)
			return _spin(doc, obj, name, float(value), hint, hints, true)
		TYPE_FLOAT:
			return _spin(doc, obj, name, float(value), hint, hints, false)
		TYPE_STRING, TYPE_STRING_NAME:
			var line := LineEdit.new()
			line.text = String(value)
			var is_name: bool = int(p["type"]) == TYPE_STRING_NAME
			MDSUi.commit_line(line, func(_text: String) -> void:
				if line.text != String(obj.get(name)):
					doc.set_value(obj, name, StringName(line.text) if is_name else line.text))
			return line
		TYPE_VECTOR2:
			var pair := HBoxContainer.new()
			var v := value as Vector2
			var x := _number(v.x, -100000.0, 100000.0, 1.0)
			var y := _number(v.y, -100000.0, 100000.0, 1.0)
			x.name = "X"
			y.name = "Y"
			var send := func(_n: float) -> void: doc.set_value(obj, name, Vector2(x.value, y.value))
			x.value_changed.connect(send)
			y.value_changed.connect(send)
			pair.add_child(x)
			pair.add_child(y)
			return pair
		TYPE_COLOR:
			var color := ColorPickerButton.new()
			color.color = value
			color.custom_minimum_size.y = 24.0
			color.popup_closed.connect(func() -> void: doc.set_value(obj, name, color.color))
			return color
	# Scenes, scripts, dictionaries, arrays: the inspector does them better.
	var open := Button.new()
	open.text = "%s…" % (_shown_thing(value))
	open.clip_text = true
	open.disabled = not Engine.is_editor_hint()
	open.pressed.connect(func() -> void: inspect(obj))
	return open

static func _shown_thing(value: Variant) -> String:
	if value is Object and is_instance_valid(value):
		var res := value as Resource
		return res.resource_path.get_file() if res and not res.resource_path.is_empty() and not res.resource_path.contains("::") else (value as Object).get_class()
	if value is Array or value is Dictionary:
		return "%d in inspector" % value.size()
	return "Set in inspector"

## Shows [param obj] in the editor's own inspector.
static func inspect(obj: Object) -> void:
	if Engine.is_editor_hint() and is_instance_valid(obj):
		EditorInterface.inspect_object(obj)

static func _enum(doc: MDSFightDocument, obj: Object, name: StringName, hints: String, value: int) -> OptionButton:
	var option := OptionButton.new()
	option.clip_text = true
	var next := 0
	for item in hints.split(","):
		var id := next
		if item.contains(":"):
			id = item.get_slice(":", 1).to_int()
		option.add_item(item.get_slice(":", 0).capitalize(), id)
		next = id + 1
	option.select(option.get_item_index(value))
	option.item_selected.connect(func(i: int) -> void: doc.set_value(obj, name, option.get_item_id(i)))
	return option

static func _number(value: float, low: float, high: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.step = step
	spin.min_value = low
	spin.max_value = high
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.set_value_no_signal(value)
	spin.custom_minimum_size.x = 60.0
	return spin

static func _spin(doc: MDSFightDocument, obj: Object, name: StringName, value: float, hint: int, hints: String, whole: bool) -> SpinBox:
	var low := -100000.0
	var high := 100000.0
	var step := 1.0 if whole else 0.01
	var open_high := true
	if hint == PROPERTY_HINT_RANGE:
		var parts := hints.split(",")
		low = parts[0].to_float()
		high = parts[1].to_float() if parts.size() > 1 else high
		if parts.size() > 2 and parts[2].is_valid_float():
			step = parts[2].to_float()
		open_high = "or_greater" in parts
	var spin := _number(value, low, high, step)
	spin.allow_lesser = false if hint == PROPERTY_HINT_RANGE else spin.allow_lesser
	spin.allow_greater = open_high
	spin.value_changed.connect(func(n: float) -> void: doc.set_value(obj, name, int(n) if whole else n))
	return spin

## The conditions of [param move]: a row each, with what to test and its value.
static func build_conditions(box: Container, doc: MDSFightDocument, move: MDSMove) -> void:
	var titles := {&"when": "Starts only when", &"cancel_when": "Stops when"}
	for list in CONDITION_LISTS:
		var head := HBoxContainer.new()
		head.name = "Conditions_%s" % list
		var label := MDSUi.label(titles[list])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(label)
		var add := MDSUi.button("+", "Add a condition")
		add.name = "Add"
		add.disabled = doc.read_only
		add.pressed.connect(func() -> void: doc.add_condition(move, list))
		head.add_child(add)
		box.add_child(head)
		var conditions: Array = move.get(list)
		for i in conditions.size():
			var c := conditions[i] as MDSMoveCondition
			if c:
				box.add_child(_condition_row(doc, move, list, i, c))

static func _condition_row(doc: MDSFightDocument, move: MDSMove, list: StringName, index: int, c: MDSMoveCondition) -> Control:
	var row := HBoxContainer.new()
	row.name = "Condition_%s_%d" % [list, index]
	var kinds := OptionButton.new()
	kinds.name = "Kind"
	kinds.clip_text = true
	kinds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k: String in MDSMoveCondition.Kind.keys():
		kinds.add_item(k.capitalize())
	kinds.select(c.kind)
	kinds.item_selected.connect(func(i: int) -> void:
		doc.commit("Set a condition", [[c, &"kind", i]]))
	row.add_child(kinds)
	if c.kind == MDSMoveCondition.Kind.FLAG:
		var flag := LineEdit.new()
		flag.name = "Flag"
		flag.text = String(c.flag)
		flag.placeholder_text = "flag"
		flag.custom_minimum_size.x = 60.0
		MDSUi.commit_line(flag, func(_text: String) -> void:
			if StringName(flag.text) != c.flag:
				doc.commit("Set a condition", [[c, &"flag", StringName(flag.text)]], false))
		row.add_child(flag)
	else:
		var value := _number(c.value, -100000.0, 100000.0, 0.01)
		value.name = "Value"
		value.value_changed.connect(func(n: float) -> void:
			doc.commit("Set a condition", [[c, &"value", n]], false))
		row.add_child(value)
	var invert := CheckBox.new()
	invert.name = "Invert"
	invert.text = "not"
	invert.tooltip_text = "Holds when the test fails"
	invert.button_pressed = c.invert
	invert.toggled.connect(func(on: bool) -> void:
		doc.commit("Set a condition", [[c, &"invert", on]], false))
	row.add_child(invert)
	var cut := MDSUi.button("×", "Remove this condition")
	cut.name = "Remove"
	cut.pressed.connect(func() -> void: doc.remove_condition(move, list, index))
	row.add_child(cut)
	return row
