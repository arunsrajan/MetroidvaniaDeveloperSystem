extends RefCounted
## The MCP server as a client runs it, for the tests: a child process spoken to over its pipes.
## Stderr is drained: a child whose stderr pipe fills up stops.

const MAIN := "res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_main.gd"
const WRITE_PIECE := 1024

var pid := -1
var stderr_text := ""
var _stdio: FileAccess
var _stderr: FileAccess
var _buffer := PackedByteArray()
## Whatever stdout had that wasn't JSON.
var not_json := PackedStringArray()

func start(extra_args: PackedStringArray = []) -> bool:
	var args := PackedStringArray(["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://").trim_suffix("/"), "--script", MAIN])
	if not extra_args.is_empty():
		args.append("--")
		args.append_array(extra_args)
	var info := OS.execute_with_pipe(OS.get_executable_path(), args, false)
	if info.is_empty():
		return false
	pid = info.pid
	_stdio = info.stdio
	_stderr = info.stderr
	return true

## The pipe doesn't block, and a write bigger than its buffer would be cut short: sent in pieces
## slower than the child reads them.
func send(text: String) -> void:
	var bytes := (text + "\n").to_utf8_buffer()
	for at in range(0, bytes.size(), WRITE_PIECE):
		_stdio.store_buffer(bytes.slice(at, at + WRITE_PIECE))
		_stdio.flush()
		if at + WRITE_PIECE < bytes.size():
			OS.delay_usec(2000)

func _pump() -> void:
	var out := _stdio.get_buffer(1 << 20)
	if not out.is_empty():
		_buffer.append_array(out)
	var err := _stderr.get_buffer(1 << 16)
	if not err.is_empty():
		stderr_text += err.get_string_from_utf8()

## The next line of stdout, or "" if none comes in [param timeout_msec].
func read_line(tree: SceneTree, timeout_msec := 60000) -> String:
	var until := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < until:
		_pump()
		var at := _buffer.find(10)
		if at >= 0:
			var line := _buffer.slice(0, at).get_string_from_utf8().strip_edges()
			_buffer = _buffer.slice(at + 1)
			return line
		await tree.process_frame
	return ""

## Sends a request and returns its answer, parsed, skipping progress notifications. {} on time out.
func request(tree: SceneTree, message: Dictionary, timeout_msec := 120000) -> Dictionary:
	send(JSON.stringify(message))
	while true:
		var line: String = await read_line(tree, timeout_msec)
		if line.is_empty():
			return {}
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary:
			not_json.append(line)
			continue
		if parsed.has("id"):
			return MDSMcpSchema.clean(parsed)
	return {}

## Calls a tool. Its result, or its failure under _error.
func tool(tree: SceneTree, tool_name: String, args: Dictionary = {}, id := 1) -> Dictionary:
	var answer: Dictionary = await request(tree, {"jsonrpc": "2.0", "id": id, "method": "tools/call", "params": {"name": tool_name, "arguments": args}})
	if not answer.has("result"):
		return {"_error": answer.get("error", {"code": "no_answer"})}
	if answer.result.isError:
		return {"_error": answer.result.structuredContent}
	return answer.result.structuredContent

## Closes stdin and returns whether the process left within [param timeout_msec].
func close_and_wait(tree: SceneTree, timeout_msec := 5000) -> bool:
	_stdio = null
	var until := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < until:
		if not OS.is_process_running(pid):
			return true
		await tree.process_frame
	return false

func kill() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	_stdio = null
	_stderr = null
