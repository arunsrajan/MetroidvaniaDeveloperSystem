@tool
class_name MDSFightDebugger
extends EditorDebuggerPlugin
## Brings news of running fights from the game to the Fight editor.

signal fight_reported(snapshot: Dictionary)
signal game_stopped

## How long a fighter counts as running after its last report, ms.
const RECENT_MSEC := 2000

## Last report of each fighter while the game runs, for those without a panel open.
static var _latest := {}

## What the fighters of the running game last said.
static func recent() -> Array:
	var now := Time.get_ticks_msec()
	return _latest.values().filter(func(s: Dictionary) -> bool: return now - int(s["heard_at"]) < RECENT_MSEC).map(func(s: Dictionary) -> Dictionary:
		var told := s.duplicate()
		told.erase("heard_at")
		return told)

func _has_capture(capture: String) -> bool:
	return capture == MDSMoveTree.CAPTURE

func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message == MDSMoveTree.MESSAGE and not data.is_empty() and data[0] is Dictionary:
		var heard: Dictionary = data[0].duplicate()
		heard["heard_at"] = Time.get_ticks_msec()
		_latest[heard.get("id", 0)] = heard
		fight_reported.emit(data[0])
		return true
	return false

func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.stopped.connect(func() -> void:
		_latest.clear()
		game_stopped.emit())
