@tool
class_name MDSMcpStdio
extends RefCounted
## The stdio side of MCP: one JSON message per line. Stdin is read on a thread, a byte at a time:
## [method OS.read_string_from_stdin] can't tell lines apart on a Windows pipe, nor an empty line
## from the end of the input. Everything else happens on the main thread.
##
## Nothing but MCP messages may reach stdout, and [method print] is GDScript's only way there. So
## printing stays off except while sending: what scripts in a loaded scene print is dropped. The
## engine's banner is kept out by Godot's --no-header.

const MAX_LINE_BYTES := 16 * 1024 * 1024

## Takes a line (a String): answers it through [method send].
var on_line: Callable
var eof := false

var _thread := Thread.new()
var _mutex := Mutex.new()
var _lines: PackedStringArray = []
var _ended := false

func start() -> void:
	_thread.start(_read)

func _read() -> void:
	var buf := PackedByteArray()
	while true:
		var b := OS.read_buffer_from_stdin(1)
		if b.is_empty():
			break
		if b[0] == 10:
			_push(buf)
			buf = PackedByteArray()
		elif buf.size() < MAX_LINE_BYTES:
			buf.append(b[0])
	_mutex.lock()
	_ended = true
	_mutex.unlock()

func _push(line: PackedByteArray) -> void:
	if line.is_empty():
		return
	_mutex.lock()
	_lines.append(line.get_string_from_utf8().strip_edges())
	_mutex.unlock()

## The lines read since the last call. When the input ended and they are taken, [member eof] is
## set: the reader has stopped by then, and this waits for it.
func take_lines() -> PackedStringArray:
	_mutex.lock()
	var out := _lines
	_lines = PackedStringArray()
	var ended := _ended
	_mutex.unlock()
	if ended and not eof:
		_thread.wait_to_finish()
		eof = true
	return out

static func send(message: String) -> void:
	Engine.print_to_stdout = true
	print(message)
	Engine.print_to_stdout = false
