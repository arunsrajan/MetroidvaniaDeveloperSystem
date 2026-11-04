@tool
class_name MDSFightDebugger
extends EditorDebuggerPlugin
## Brings news of running fights from the game to the Fight editor.

signal fight_reported(snapshot: Dictionary)
signal game_stopped

func _has_capture(capture: String) -> bool:
	return capture == MDSMoveTree.CAPTURE

func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message == MDSMoveTree.MESSAGE and not data.is_empty() and data[0] is Dictionary:
		fight_reported.emit(data[0])
		return true
	return false

func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.stopped.connect(func() -> void: game_stopped.emit())
