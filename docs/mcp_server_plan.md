# MCP server for MDS: implementation plan

Status: **implemented**, phases 1 to 4, with Phase 5 left out. Researched and built 2026-11-03. How to use it is in the [README](../README.md#mcp-server-letting-ai-tools-build-with-mds). The rest of this page is the plan as approved, so read it with these results.

## Results

Decisions taken from section 12's recommendations: `author` tier by default, refuse on unsaved scenes, no MetSys mode, `mcp/` ships in the addon, no running the game.

**Different from the plan:**

| Plan | Built | Why |
|---|---|---|
| A dead editor or lock holder is detected with `OS.is_process_running` | The endpoint file is rewritten every 3 s and counts as gone after 10 s. A lock left unrenewed for 60 s can be taken | On Windows that call only knows a process's own children. **A frozen editor with MCP off looks closed after 10 s** |
| On 4.6, compare scene fingerprints to find unsaved scenes | Every open scene counts as unsaved | Only the current tab can be looked at, and a fingerprint misses painted tiles |
| An unread stderr may need the isolated worker process | The server silences engine errors, and `-- --show-errors` brings them back | With stderr unread, 0 of 58 calls were answered with errors on and 58 of 58 with them off, on both engines |
| Nothing said about scripts that print | Printing is off except while the server sends | `Engine.print_to_stdout` gates `print()`. `test_mcp_stdio` checks it with a scene that prints |
| Writes go to a temp file and then rename | True for worlds. Scenes are saved through the plugin's own scene code and Godot's saver, not atomically | A process killed while saving a scene can leave it damaged. Its snapshot in `.godot/mds_mcp/history/pending/` isn't restored by itself |
| `resources/` and `prompts/` folders | One file each | Less to carry |
| About 45 tools | 43 | The two play tools are Phase 5 |

**Phase 0 gates, with Claude Code 2.1.310 on Windows:**

| Gate | Result |
|---|---|
| Connects over stdio and lists the tools | Yes, 43 tools, on 4.6.1 (console `.exe`) and 4.7.2 (GUI `.exe`) |
| `\r\n` line ends | Accepted |
| `${GODOT4:-godot}` and `${CLAUDE_PROJECT_DIR:-.}` in the config | Work, with `GODOT4` set and started from the project folder |
| Which protocol | It probes `server/discover`, and its log says the server speaks the new protocol. Connecting took about 4.6 s |
| Exits with the client | No process left behind |

**Not verified:**

- **A model calling tools through a real client.** The CLI on this machine isn't logged in, so that run stopped after connecting. Tool calls were run through a test client over the same pipes and HTTP (`test_mcp_stdio`, `test_mcp_editor`, `test_mcp_http`).
- **Ctrl+Z on the map after a tool call.** Tests cover undo through `mds_undo` in a headless editor. Nobody has pressed the key.
- **Room view release and restore** with a real room showing.
- **The panel's MCP section and Copy config**, by eye, and a windowed editor at all, including when unfocused. The headless editor covers the server, not the UI.
- **SSE progress** through a real client.
- Claude Desktop, Cursor, other clients, the Inspector and the conformance suite.
- Linux and macOS. CI runs the suites on Linux, where the pipe and socket behaviour hasn't been seen yet.

## 1. Summary

**Yes, MDS can have an MCP server written entirely in GDScript, with nothing else to install.** Both standard MCP transports work on Godot 4.6.1 and 4.7.2. I tested them on both engines (see [section 3](#3-what-gdscript-can-do-tested)).

The recommendation:

- **One GDScript core, two front ends, no Node or Python.** The protocol and tools live in `addons/MetroidvaniaDeveloperSystem/mcp/`.
- **Every client uses one stdio command.** It starts a headless Godot process. If an editor is open on the project with MCP on, that process forwards each request to the editor. If not, it does the work itself.
- **The editor also serves Streamable HTTP** on `127.0.0.1`, with a token, for the forwarding and for clients that prefer a URL.
- **Tools speak MDS, not Godot.** "Generate a cave in this room" and "validate this world", not "set a property on a node". Generic Godot MCP servers already cover generic editing, and they can run alongside this one.
- **Support both protocol generations.** The latest spec (2026-07-28) removed the handshake that every earlier version needs. Clients are in transition, so the server has to answer both.
- **Off by default, and limited.** Enabling the plugin opens no port. Paths stay inside `res://` and writes stay out of `addons/` and `project.godot`. There is no "run this code" tool. Every write can be undone.

Decisions needed from you are in [section 12](#12-open-questions-for-you).

## 2. What MCP requires now

### Spec version

The current revision is [2026-07-28](https://modelcontextprotocol.io/specification/versioning). It differs a lot from 2025-11-25, which most existing servers and examples target ([changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog)):

| Change in 2026-07-28 | What it means for MDS |
|---|---|
| `initialize` handshake removed. Each request carries its version and capabilities in `_meta` | The server keeps no connection state |
| `server/discover` added, and servers must implement it | One new method, with a cached result |
| `Mcp-Session-Id` and the HTTP GET stream removed | Simpler HTTP. Each request is its own POST |
| `resultType` required on all results | Every result gets `"resultType": "complete"` |
| `ttlMs` and `cacheScope` required on list and read results | Tool lists can be cached for a long time |
| `Mcp-Method` and `Mcp-Name` headers required, and must match the body | Check them and reject a mismatch with 400 |
| Server-to-client requests replaced by [multi round-trip results](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/mrtr) | Not needed in v1 |
| `subscriptions/listen` replaces `resources/subscribe` | Not needed in v1: the tool list never changes at runtime |
| [Roots, sampling and logging deprecated](https://modelcontextprotocol.io/specification/2026-07-28/deprecated) | Don't use them. Log to stderr or a file |

### Stay compatible with older clients

A modern-only server fails with legacy clients ([compatibility matrix](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning#compatibility-matrix)). So MDS will be what the spec calls a **dual-era** server:

- A request with modern `_meta` is served statelessly under 2026-07-28.
- An `initialize` request selects legacy behaviour: `initialize`, `notifications/initialized` and `ping`, negotiating 2025-11-25, 2025-06-18 or 2025-03-26.

Because the tools hold no state between calls, the extra work is small: the legacy path adds a handshake and leaves out the new result fields.

### Transports

- **[stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio):** one JSON-RPC message per line. Nothing but MCP messages may reach stdout. Closing stdin is the shutdown signal, and the server should exit promptly.
- **[Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http):** one POST endpoint, answered with JSON or a per-request SSE stream. Servers **must** check `Origin` (403 if invalid) and **should** bind to localhost and authenticate.
- HTTP+SSE, the old transport, is [deprecated](https://modelcontextprotocol.io/specification/2026-07-28/deprecated). Don't implement it.

### What clients support

| Client | stdio | Streamable HTTP | Notes | Source |
|---|---|---|---|---|
| Claude Code | Yes | Yes (`http`) | Also a non-standard `ws` type. Its v2 runtime speaks 2026-07-28 and probes for it; its v1 runtime is legacy. Warns at 10,000 tokens of tool output and limits it to 25,000 | [docs](https://code.claude.com/docs/en/mcp) |
| Claude Desktop | Yes | Not confirmed | The current page centres on desktop extensions, and I couldn't confirm the details from it. Treat stdio as the safe choice | [docs](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop) |
| Cursor | Yes | Yes | `mcp.json`, `url` plus `headers` | [docs](https://cursor.com/docs/context/mcp) |
| VS Code Copilot | Yes | Yes | Workspace-root `.mcp.json` is the newer location; `.vscode/mcp.json` is labelled deprecated in its guided flow | [docs](https://code.visualstudio.com/docs/copilot/customization/mcp-servers) |
| OpenAI Codex | Yes | Yes | `codex mcp add`, `config.toml` | [docs](https://developers.openai.com/codex/mcp) |
| Gemini CLI | Yes | Yes | `settings.json` | [docs](https://geminicli.com/docs/tools/mcp-server/) |
| Windsurf docs (now "Devin Local") | Yes | Yes | Also SSE | [docs](https://docs.windsurf.com/windsurf/cascade/mcp) |
| Zed | Yes | Yes | `context_servers` | [docs](https://zed.dev/docs/ai/mcp) |

**stdio is the only transport every client on this list is confirmed to support.** Only Claude Code documents which protocol revision it speaks, which is the other reason to stay dual-era.

## 3. What GDScript can do (tested)

I ran throwaway probes in the scratchpad on `Godot_v4.6.1-stable_win64_console.exe` and `Godot_v4.7.2-stable_win64_console.exe`, then deleted them. Both versions behaved the same unless noted. **All of this was on Windows, and no real MCP client was involved.**

### stdio works

| Claim | Result |
|---|---|
| `OS.read_buffer_from_stdin(1)` on a `Thread` doesn't stall the game loop | About 146 frames per second while the reader waited |
| Clean stdout with `--no-header` | Nothing on stdout before the first reply. **Without the flag, the engine banner goes to stdout and would break the protocol** |
| Small request to reply | 2 to 54 ms |
| Large messages, UTF-8 | 300 KB in: 324 ms. 400 KB out through `print()`: 12 ms. Both intact |
| Two messages in one write | Both answered |
| Stdin closed | Exit code 0 in 77 to 113 ms. Fast enough for Claude Code, which [ends the process 300 ms after closing stdin on Windows](https://code.claude.com/docs/en/mcp) |
| Both Windows executables | The console and the GUI `.exe` both work over pipes |
| Real MDS authoring over `--script` | Two caves, a world and a game scene built: stdout held only my own line. Total run 3.3 s (4.6.1) and 4.2 s (4.7.2), of which the work took about 0.5 s |

**Use `read_buffer_from_stdin(1)`, not `read_string_from_stdin()`.** The string version is unusable for this, for two reasons:

- On a Windows pipe it returned several lines glued together, split at the buffer size, not at line ends (tested).
- It can't tell a blank line from end of input, because both give an empty string (tested on Windows, and the same follows from [the Unix source](https://github.com/godotengine/godot/blob/4.6-stable/drivers/unix/os_unix.cpp)).

**Writing goes through `print()`.** There is no other way to reach stdout from GDScript. So `--quiet` can't be used, because it silences the replies as well. On Windows each line ends in `\r\n`, which the parser in my test accepted. Check this against real clients in Phase 0.

### HTTP works

There is no `HTTPServer` class in the engine ([class list](https://github.com/godotengine/godot/tree/4.6-stable/doc/classes): only `HTTPClient` and `HTTPRequest`). A small HTTP/1.1 server on `TCPServer` and `StreamPeerTCP` is enough:

| Claim | Result |
|---|---|
| POST through `TCPServer` polled each frame | 14 to 41 ms from a `--script` process |
| Large bodies | 5 MB in: about 550 ms. 2 MB out: about 40 ms |
| SSE | Events arrived separately, 297 ms apart as sent |
| A second process on the same port | `listen()` returned "Already in use", so port conflicts can be detected on Windows |
| Inside an `EditorPlugin`, `--headless --editor` | HTTP 200 in 2 to 8 ms with `EditorInterface` calls working. `get_editor_undo_redo()` was available |
| MDS plugin itself under `--headless --editor` | Loaded with no errors on either version |
| Editor stdout | 14 to 18 lines of output from the MDS project's editor run. **So the editor process can't speak stdio itself** |

Two details the HTTP layer must get right:

- `TCPServer.listen()` [defaults to all interfaces](https://github.com/godotengine/godot/blob/4.6-stable/doc/classes/TCPServer.xml). Always pass `"127.0.0.1"`.
- Read the request before replying, and don't close in the same frame as a blind write. My first probe did that and curl reported a failure even though the server had "answered".

### Limits and surprises

- **Tools run on the main thread.** Scene and editor APIs need it. A long tool call freezes the editor while it runs, so long tools must `await` a frame between rooms.
- **An undrained stderr pipe froze the process.** When the parent never read stderr, one `printerr()` was enough to stop the server responding. With no stderr output, the same setup worked. The spec lets clients ignore stderr, so this could happen with a real client. I reproduced it on both versions with the console `.exe` and didn't find the cause. It is a Phase 0 gate.
- **The editor polls less when it isn't focused.** The default unfocused sleep is [100 ms](https://github.com/godotengine/godot/blob/4.6-stable/editor/settings/editor_settings.cpp), so expect up to about 100 ms of added latency. A plugin can lower it: setting `OS.low_processor_usage_mode_sleep_usec` to 2000 raised polling from about 140 to about 478 calls a second (measured focused). [Beckett](https://github.com/beckettlab/beckett-godot-mcp/blob/main/addons/beckett/core/http_server.gd) does the same while clients are active. **My windowed test stayed focused, so I did not measure the unfocused rate itself.**
- **`EditorInterface.get_unsaved_scenes()` exists in 4.7 but not 4.6** (per each version's docs). The plan needs a fallback, see [section 6](#6-editor-open-versus-headless).
- **A fresh clone has no class cache.** `class_name` lookups fail until `--import` has run, which took 26 s here. The server must detect this and say so, see Phase 1.

### Not verified

- Linux and macOS. CI will cover Linux. The source differs (`fread` and `fgets` on Unix, `ReadFile` on Windows), so don't assume.
- Any real MCP client. Phase 0 exists for this.
- Dirty-scene detection through scene fingerprints.
- A windowed editor while unfocused or minimized.

## 4. Existing Godot MCP servers

| Project | Shape | Worth learning |
|---|---|---|
| [Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp) (6.5k stars) | Node, drives the Godot CLI | Headless authoring is useful with no editor open |
| [hi-godot/godot-ai](https://github.com/hi-godot/godot-ai) (3.4k stars) | Python server plus addon. Needs `uv`, Godot 4.7+ | Current clients attach over stdio; its README says a bare HTTP entry can't authenticate |
| [yurineko73/Godot-MCP-Native](https://github.com/yurineko73/Godot-MCP-Native) (868 stars) | GDScript, in the editor, HTTP. Also a headless mode | Proves native GDScript HTTP is practical |
| [tomyud1/godot-mcp](https://github.com/tomyud1/godot-mcp) (449 stars) | Node over stdio, WebSocket to addon | Common bridge design, with undo and batches |
| [NPGameDev/godot-mcp-toolkit](https://github.com/NPGameDev/godot-mcp-toolkit) (99 stars) | npm bridge, WebSocket, addon | Tool list grows on request, to save context. Lets projects add GDScript tools |
| [satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp) (183 stars) | Node, WebSocket, debugger | Splits tools into read and write, so reads can be auto-approved. Built around agents checking their own work |
| [beckettlab/beckett-godot-mcp](https://github.com/beckettlab/beckett-godot-mcp) (49 stars) | GDScript, in the editor, HTTP, no sidecar | **Closest to this plan.** See below |

**From Beckett:** [its security page](https://github.com/beckettlab/beckett-godot-mcp/blob/main/SECURITY.md) and code show exact Host and Origin checks, a per-project token, confined file reads, an audit log and an "unfocused editor" boost. Note it targets 2025-11-25 and documents only HTTP from inside the editor, so it can't work with no editor open.

**Reuse none as a dependency.** All of them are generic. Each would add an install step (several need Node or Python), none knows rooms, gates or generators, and MDS's tools would still have to be written. Beckett and the others above are MIT-licensed, so small pieces could be adapted with credit, but the HTTP layer is short enough to write to match this repo's style.

**About your `godot-ai` entry:** it points at `http://127.0.0.1:8000/mcp`, and the connection is refused, which means nothing is listening there. Its README now says such a bare entry can't authenticate, so it may also need updating to `godot-ai attach`. This is separate from MDS, and I changed nothing.

## 5. Architecture

### Recommended: one core, two front ends

```
Claude Code / Cursor / any client
        | stdio (one config entry for everyone)
        v
godot --headless --no-header --script .../mcp/mds_mcp_main.gd
        |
        +-- editor running? ----> HTTP + token ---> EditorPlugin: MDSMcpHttp
        |                                                  |
        |                                                  v
        +-- no editor ---------> in this process     MDSMcpEditorHost
                                       |                   |
                                       v                   |
                                MDSMcpHeadlessHost         |
                                       |                   |
                                       v                   v
                                 MDSMcpProtocol --> tools --> MDSWorld, MDSRoomPainter,
                                                              MDSWorldSceneTools, ...
```

Optionally, a client can skip the stdio process and connect directly to the editor's HTTP endpoint.

Why this shape:

- **One config for every client.** The agent doesn't care whether the editor is open.
- **The stateless protocol fits.** Each call loads, changes, saves. Forwarding per request means opening or closing the editor mid-session just works.
- **The editor stays the only writer while open.** That is what keeps unsaved work safe.
- **CI can test all of it** with no display.

### New files

All under `addons/MetroidvaniaDeveloperSystem/mcp/`, following the addon's `MDS` naming:

| File | Role |
|---|---|
| `mds_mcp_main.gd` | `extends SceneTree`, the stdio entry point. Avoids `class_name` references so it can report a missing class cache |
| `mds_mcp_stdio.gd` | Reader thread, line framing, output through `print()` |
| `mds_mcp_http.gd` | HTTP/1.1 on `TCPServer`: limits, Host, Origin and token checks, SSE |
| `mds_mcp_protocol.gd` | JSON-RPC, both eras, dispatch. No knowledge of transports, so tests call it directly |
| `mds_mcp_schema.gd` | Checks inputs against a JSON Schema subset. Converts JSON numbers: Godot parses every number as a float, so a request `id` of `1` would otherwise come back as `1.0` |
| `mds_mcp_host.gd` | Interface for world and scene access, undo, refresh |
| `mds_mcp_headless_host.gd`, `mds_mcp_editor_host.gd` | The two implementations |
| `mds_mcp_guard.gd` | Path rules, permission tiers, write lock, audit log |
| `mds_mcp_history.gd` | File snapshots for undo |
| `tools/mds_mcp_tools_*.gd` | Thin wrappers over existing MDS classes. No new game logic |
| `resources/`, `prompts/` | Resource readers and prompt text |

Changes to existing files stay small:

- `plugin.gd` starts and stops the HTTP server.
- `world_panel.gd` gains an MCP status row, and one public method wrapping what [`_on_room_saved`](../addons/MetroidvaniaDeveloperSystem/world_panel.gd#L1613) already does after a room is written.

Editor-only calls must not break headless loading. `MDSMcpEditorHost` is loaded only inside the plugin, and shared code uses the [`Engine.has_singleton(&"EditorInterface")`](../addons/MetroidvaniaDeveloperSystem/core/room_painter.gd#L2714) pattern already in `MDSRoomPainter`.

### Alternatives rejected

| Alternative | Why not |
|---|---|
| Node or Python bridge plus addon | Adds an install step to a plugin that has none, plus a second language to test and ship. Testing shows it isn't needed |
| In-editor HTTP only (Beckett's way) | Doesn't work with no editor open, so no CI or headless authoring, and clients that can't reach HTTP are left out |
| Headless only (Coding-Solo's way) | Writing files behind an open editor is how unsaved work gets lost. No editor undo |
| Editor process speaking stdio | Its stdout carries engine output (measured 14 to 18 lines), and clients expect to launch the server, not attach to your editor |
| WebSocket | Not a standard MCP transport. Only Claude Code documents `ws` |
| A GDExtension (C++ or Rust) | Binaries for each platform, for no gain |
| Extending a generic server | Depends on someone else's project and install, for tools MDS has to write anyway |
| Separate worker process per call, for clean stdout and crash isolation | More moving parts than v1 needs. **Kept as the fallback** if Phase 0 or tests show stdout or hangs are a real problem |

## 6. Editor open versus headless

MDS has three separate owners of state. The rules follow from how they work today:

- **The panel's `MDSWorld`.** It has `checkpoint()`, `undo()` and a `changed` signal, saves on a timer, and [reloads when the file changes on disk](../addons/MetroidvaniaDeveloperSystem/world_panel.gd#L1139).
- **The Room view's painter.** It has its own undo and merges changes from an open scene ([test_editor_sync](../tests/test_editor_sync.gd)).
- **Godot's scene tabs.** [`reload_scene_from_path`](../addons/MetroidvaniaDeveloperSystem/world_panel.gd#L1616) discards their unsaved changes.

| Situation | What happens |
|---|---|
| World edit, world open in the panel | Applied to the panel's live `MDSWorld`: `checkpoint()`, edit, `changed`. The map redraws, the panel saves, **and Ctrl+Z on the map undoes it**. One tool call or batch is one undo step |
| World edit, another world or none open | Load fresh, edit, save atomically. The panel notices through its file check if it later has the file open |
| Room edit, scene closed | `MDSRoomPainter` writes the file, a snapshot is kept, then `update_file` and a rescan |
| Room edit, scene open with no unsaved changes | Same, then `reload_scene_from_path`. Godot's undo history for that tab is lost, so the snapshot is the undo |
| Room edit, scene open **with unsaved changes**, or Room view unsaved | **Refused** with `scene_has_unsaved_changes`, listing them. The agent should ask you, then can retry with `on_unsaved: "save_first"` |
| Headless | Same tools. Load fresh, write, snapshot. No live undo, but `mds_undo` still works |

**Detecting unsaved scenes:** use `get_unsaved_scenes()` when `has_method` finds it (4.7), and on 4.6 compare [`MDSRoomPainter.scene_fingerprint`](../addons/MetroidvaniaDeveloperSystem/core/room_painter.gd#L1074) of the open scene with the file on disk. The fallback needs a spike in Phase 3. If it isn't reliable, 4.6 treats every open scene as unsaved, which is safe but stricter.

**Undo that works in both modes.** `MDSMcpHistory` copies the bytes of every file a tool will change into `.godot/mds_mcp/history/<n>/`, keeping the last 50 steps. `mds_undo` restores them only if the files haven't changed since, the same check the panel's [`_gate_log`](../addons/MetroidvaniaDeveloperSystem/world_panel.gd#L1282) makes. If you've edited the file since, it refuses and says why.

**Saving.**

- Tools save what they change. There is no "unsaved agent work" state.
- Your open scenes are saved only by `mds_editor_save_scenes` or `on_unsaved: "save_first"`, never as a side effect.
- Writes go to a temp file and then rename, because Claude Code can kill the process within 300 to 500 ms of disconnecting.

**Stale caches.** A long-lived stdio process must not trust caches. Use `MDSWorld.load_world` and [`MDSWorldSceneTools.load_fresh`](../addons/MetroidvaniaDeveloperSystem/core/world_scene_tools.gd#L396), never `MDSWorld.get_cached`.

**Several processes.** A lock file (`.godot/mds_mcp/lock`, with PID) serialises writers. Stale locks are detected with `OS.is_process_running`.

**How the stdio process finds the editor.** The editor listens on port 6590 by default, or the next free one of the following nine, and writes `.godot/mds_mcp/endpoint.json` with port, token and PID, removing it on exit. Before each request the stdio process checks it and that the PID is alive. `.godot/` is already git-ignored.

## 7. Tools, resources and prompts

Tool conventions:

- `world` is a `res://…mdsworld.json` path. It can be left out when exactly one world exists or one is open.
- Results have both `structuredContent` and JSON text.
- Edits return `{changed: [paths], undo_id, warnings}`.
- Failures use `isError: true` with `{code, message, hint}`.
- Long lists are paged, since Claude Code warns at 10,000 tokens.
- Annotations mark `readOnlyHint` and `destructiveHint`. They are hints, so the server enforces its own rules as well.

Tier: **R** read, **A** author, **D** author and destructive (needs `confirm: true`), **F** full.

### Status and catalog

| Tool | Inputs | Tier | Built on |
|---|---|---|---|
| `mds_status` | none | R | Mode, versions, tier, worlds, what is open and unsaved, class cache state |
| `mds_catalog` | `kind`: `cave_styles`, `cave_shapes`, `attack_fx`, `hit_particles`, `damage_types`, `effects`, `enemy_templates`, `tile_palettes`, `stamp_sets` | R | `MDSCaveShapes.STYLES` and `CHOICES`, `MDSAttackFX.EFFECTS`, `MDSHitParticles.KINDS`, `MDSDamageInfo.TYPES`, `effect_ids()`, `PALETTES` |

### Worlds and maps

| Tool | Inputs | Tier | Built on |
|---|---|---|---|
| `mds_world_list` | none | R | Finds `*.mdsworld.json` |
| `mds_world_get` | `world`, `include?`, `cursor?` | R | `MDSWorld` getters |
| `mds_world_create` | `path`, `name`, `settings?` | A | `MDSWorld.new`, `save` |
| `mds_world_update` | `world`, `settings?` (allowed keys only), `name?`, `start_room?` | A | `set_setting`, `set_start_room` |
| `mds_area_set` | `world`, `area`, `title?`, `subtitle?`, `color?`, `parallax?`, `darkness?`, `rename_to?` | A | `add_area`, `set_area_value`, `rename_area` |
| `mds_area_remove` | `world`, `area`, `confirm` | D | `remove_area` |
| `mds_area_generate` | `world`, `area`, `box`, `layer?`, `shape?`, `room_min?`, `room_max?`, `irregularity?`, `shafts?`, `loops?`, `roughness?`, `tendrils?`, `curves?`, `slants?`, `seed?`, `dry_run?` | A | `MDSAreaGenerator.preview`, `generate` |
| `mds_room_add` | `world`, `id`, `rect` or `cells`, `layer?`, `area?`, `type?`, `scene?` | A | `add_room`, `add_room_from_cells` |
| `mds_room_update` | `world`, `id`, `rename_to?`, `area?`, `type?`, `origin?`, `rects?`, `shape?`, `scene?` | A | `rename_room`, `set_room_shape`, `set_room_scene`, ... |
| `mds_room_merge` | `world`, `ids`, `keep_id?` | A | `merge_error`, `merge_rooms` |
| `mds_room_remove` | `world`, `id`, `delete_scene?` (default false), `confirm` | D | `remove_room` |
| `mds_gate_add` | `world`, `room`, `pos`, `side?`, `name?`, `snap_to_edge?` | A | `add_gate` |
| `mds_gate_update` | `world`, `room`, `gate`, `rename_to?`, `pos?`, `values?` | A | `rename_gate`, `set_gate_world_pos`, `set_gate_value` |
| `mds_gate_remove` | `world`, `room`, `gate`, `confirm` | D | `remove_gate` |
| `mds_gate_connect` | `world`, `a`, `a_gate`, `b`, `b_gate`, `two_way?`, `requires?` | A | `connect_gates`, `set_door_value` |
| `mds_gate_disconnect` | `world`, `room`, `gate` | A | `disconnect_gate` |
| `mds_gates_auto` | `world`, `mode`: `touching` or `nearest`, `max_distance?` | A | `auto_gates_between_touching`, `auto_connect_gates` |

### Rooms

| Tool | Inputs | Tier | Built on |
|---|---|---|---|
| `mds_tileset_create` | `path`, `palette`: `cave` or `daylight` | A | `MDSTilesetFactory.get_or_create` |
| `mds_room_scene_create` | `world`, `room`, `scene_path?` | A | `create_scene_for_room`, `apply_gate_nodes` |
| `mds_room_generate` | `world`, `room`, `style`, `shape?`, `shapes?`, `rotation?`, `count?`, `width?`, `seed?`, `terrain?`, `background?`, `fills?`, `overwrite?` (default false), `on_unsaved?` | A | `MDSRoomPainter.generate_cave`. Returns `paths_joined` |
| `mds_area_generate_caves` | `world`, `rooms` or `area`, `cave`, `fills?`, `tileset?`, `skip_painted?` (default true), `seed?`, `on_unsaved?` | A | `generate_area_caves`, with progress per room |
| `mds_room_paint` | `world`, `room`, `layer`, `op`: `terrain`, `kind`, `fill`, `tile`, `erase`, `clear`; `cells` or `rect`; op values; `on_unsaved?` | A | `paint_terrain`, `place_kind`, `paint_fill`, `place_tile`, `erase`, `clear_layer` |
| `mds_room_decorate` | `world`, `room`, `seed?`, `clear?`, `allowed?` | A | `auto_decorate` |
| `mds_room_place` | `world`, `room`, `kind`: `enemy`, `scene`, `stamp`, `effect`; `template`, `pos`, `name?`, `settings?`, `on_unsaved?` | A | `add_stamp`, `add_effect`, adding a template as the build scripts do |
| `mds_room_fit_objects` | `world`, `room`, `mode`: `floor`, `declutter` | A | `MDSRoomDressing` |
| `mds_room_remove_item` | `world`, `room`, `node`, `confirm` | D | `remove_item`, `remove_scene_node` |
| `mds_room_items` | `world`, `room`, `cursor?` | R | `pickable_items`, `effects`, `gate_nodes` |
| `mds_room_ascii` | `world`, `room`, `layer?`, `region?`, `scale?` | R | Tile layers as text. Cheap way for an agent to see a room |
| `mds_room_preview` | `world`, `room`, `scale?` | R | PNG from cell colors using `Image`, so **no GPU, and works headless**. Returns MCP image content |

### Gameplay and combat

| Tool | Inputs | Tier | Built on |
|---|---|---|---|
| `mds_enemy_configure` | `world`, `room`, `node`, `damage_type?`, `attack_color?`, `attack_glow?`, `hurt_particles?`, `particle_palette?`, `particle_glow?`, `particle_size?`, `body_color?`, `contact_damage?`, `facing?`, `respawn?`, `on_unsaved?` | A | `MDSEnemy` exported properties, allowlisted. Values checked against `MDSDamageInfo.TYPES` and `MDSHitParticles.KINDS` |
| `mds_game_scene_create` | `world`, `path`, `include_gameplay_kit?`, `stream_rooms?`, `save_file?`, `exploration_file?` | A | `create_game_scene` plus the steps in [`build_open_world_demo.gd`](../examples/open_world_demo/build_open_world_demo.gd) |
| `mds_gameplay_setup` | `actions?`, `layers?`, `settings?` | F | `MDSGameplaySetup.ensure_*`. **The only tool that writes `project.godot`.** It only adds entries |

### Checks

| Tool | Inputs | Tier | Built on |
|---|---|---|---|
| `mds_validate` | `world`, `min_severity?`, `cursor?` | R | `MDSSceneScanner`, `MDSAnalysis`, `MDSWorldValidator.run` |
| `mds_analysis` | `world`, `kind`: `progression`, `backtracking`, `path`, `ability_uses`, `objectives`; `from?`, `to?`, `ability?` | R | `MDSAnalysis` |
| `mds_room_check` | `world`, `rooms` | R | `MDSRoomCheck`: gates passable, platforms landable, climbs reachable |
| `mds_export` | `world`, `format`: `json`, `dot`, `markdown`; `path?` | R, or A with `path` | `MDSExporters` |

### Undo, batches and the editor

| Tool | Inputs | Tier | Notes |
|---|---|---|---|
| `mds_batch` | `ops: [{tool, args}]`, `atomic?` (default true), `on_unsaved?` | A | One undo step. Restores snapshots if an op fails. Needed since a whole area takes dozens of calls |
| `mds_history` | `limit?` | R | Recent changes |
| `mds_undo` | `undo_id?` | A | See [section 6](#6-editor-open-versus-headless) |
| `mds_editor_open` | `world`, `room?` | A | Editor only: shows it in the panel |
| `mds_editor_save_scenes` | `paths?`, `all?` | A | Editor only |
| `mds_play_room` | `world`, `room` | F | Editor only: `play_custom_scene`. Phase 5 |
| `mds_play_stop` | none | F | Editor only. Phase 5 |

Editor-only tools stay listed in headless mode, because the list must be stable and shouldn't vary per connection. There they return `requires_editor`.

**Left out on purpose:** running GDScript or shell commands, writing scripts, setting any property on any node, reading files outside `res://`, editing `addons/`. Agents already have file tools from their client, under that client's own approval. MetSys mode is also left out of v1 (see open questions).

### Resources

Clients vary in how well they handle resources, so everything here is also reachable through tools.

| URI | Content |
|---|---|
| `mds://worlds` | World list |
| `mds://world/{path}` | World summary |
| `mds://world/{path}/room/{id}` | Room data with gates |
| `mds://world/{path}/issues` | Validator output |
| `mds://catalog/{kind}` | Same as `mds_catalog` |
| `mds://guide/objects` | Object guide. It sits in `docs/`, which an addon-only install may not have, so the resource must handle its absence |
| `mds://audit` | Recent tool calls |

### Prompts

| Prompt | Arguments | Walks the agent through |
|---|---|---|
| `build_area` | `theme`, `rooms`, `style?`, `world?` | Tileset, area, rooms, gates, caves, validate, game scene |
| `add_encounter` | `room`, `difficulty?`, `element?` | Place enemies, set hits and hurts, check the floor |
| `gated_progression` | `ability`, `area?` | Door requirements, then check progression and backtracking |
| `audit_world` | `world?` | Validate, room check, propose fixes without applying them |
| `combat_fx_pass` | `area`, `palette?` | Consistent attack and hurt looks |

The `instructions` field of `server/discover` and `initialize` gets a short workflow: check `mds_status`, use `mds_catalog` rather than guessing ids, keep seeds fixed, batch related edits, validate at the end.

## 8. Security

**Threats:** a web page reaching the local port (DNS rebinding), another local process, a confused or prompt-injected agent, and a cloned project switching things on by itself.

| Layer | Rule |
|---|---|
| Off by default | Stored with [`set_project_metadata`](../addons/MetroidvaniaDeveloperSystem/plugin.gd), as the window position is: per user and machine, not in `project.godot`. A cloned repo can't turn on a listener |
| Network | Bind `127.0.0.1` only. No setting to widen it in v1 |
| HTTP checks | `Origin`, if present, must be a loopback origin on this port, else 403 ([required](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http#security-%26-endpoint)). `Host` must match exactly, also against rebinding |
| Auth | Random 256-bit bearer token from `Crypto`, compared in constant time, 401 otherwise. It lives in `.godot/mds_mcp/`. OAuth isn't worth it on loopback |
| Limits | 8 MB body, 16 KB headers, 8 connections, idle timeout, cell-array and batch caps |
| Paths | Must be `res://`, normalised, no `..`. Writes refused in `addons/`, `.godot/`, `.git/`, and to `project.godot` (except `mds_gameplay_setup`) |
| Tiers | `read`, `author` (default), `full`. Set in the panel, or `-- --tier=read` in stdio args. Lower tiers refuse the call and say which tier is needed |
| Destructive | Needs `confirm: true`. Generators skip painted rooms unless told otherwise |
| Injection | Room names and other project strings are returned as data in JSON, length-limited. No tool result asks an agent to do anything |
| Audit | `.godot/mds_mcp/audit.log`: time, client, tool, changed files |
| Shipped games | Nothing autoloads. `mds_mcp_main.gd` refuses to run without `OS.has_feature("editor")`, and the docs suggest excluding `mcp/` from exports |

**What this does not protect against:**

- Local processes running as you can read the token, and stdio servers [run with your full account rights](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/local-server-security).
- Loading a room runs any `@tool` scripts in it, as opening it in the editor does. Only use it on projects you trust.

## 9. Setup

The panel gets an **MCP** row: on/off, tier, status (port and last call), and **Copy config** for each client, filled in with the real paths from `OS.get_executable_path()`. Writing `.mcp.json` happens only when you click it. It is never automatic.

Without the panel, run `godot --headless --path . --import` once on a fresh clone.

The command is the same everywhere (`<GODOT>` and `<PROJECT>` are absolute paths):

```
<GODOT> --headless --no-header --path <PROJECT> --script res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_main.gd
```

**Claude Code:**

```bash
claude mcp add --transport stdio mds -- <GODOT> --headless --no-header --path <PROJECT> --script res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_main.gd
```

To share with a team, use `.mcp.json` at the project root, with an environment variable for the engine path. Teammates [approve it on first use](https://code.claude.com/docs/en/mcp). The `${VAR:-default}` expansion is documented, but I haven't run it with this command yet:

```json
{
  "mcpServers": {
    "mds": {
      "command": "${GODOT4:-godot}",
      "args": ["--headless", "--no-header", "--path", "${CLAUDE_PROJECT_DIR:-.}",
               "--script", "res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_main.gd"]
    }
  }
}
```

Connecting straight to an open editor, which never belongs in a committed file because of the token:

```bash
claude mcp add --transport http mds http://127.0.0.1:6590/mcp --header "Authorization: Bearer <token>"
```

**Other clients** use the same command and args:

| Client | Where |
|---|---|
| Claude Desktop | `claude_desktop_config.json`, `mcpServers.mds`. A packaged desktop extension is a possible later step |
| Cursor | `.cursor/mcp.json`, `mcpServers.mds` |
| VS Code | Workspace `.mcp.json` |
| Codex | `codex mcp add mds -- <command>`, or `[mcp_servers.mds]` in `config.toml` |
| Gemini CLI | `settings.json`, `mcpServers.mds` |
| Zed | `context_servers.mds` |

A sensible client setup allows reads freely and keeps writes on approval: every `R` tool has `readOnlyHint`, and Claude Code permissions can allow tools by name.

## 10. Testing

The suites fit the existing setup. New `tests/test_mcp_*.tscn` scenes extend [`test_case.gd`](../tests/test_case.gd), so [`run_all.tscn`](../tests/run_all.gd) picks them up and [CI](../.github/workflows/tests.yml) runs them on 4.6.1 and 4.7.2 with no workflow change. Temp files go in `tests/tmp/`.

| Suite | Covers | How |
|---|---|---|
| `test_mcp_protocol` | Both eras, `server/discover`, version errors (-32022), `resultType`, `ttlMs`, stable `tools/list` order, `id` round trip (`1` stays `1`), malformed JSON | Direct calls, no sockets |
| `test_mcp_schema` | Input checks, unknown fields, enums, every tool's schema is valid | Direct calls |
| `test_mcp_tools_world` | World, area, room and gate tools | Compares with direct `MDSWorld` use |
| `test_mcp_tools_room` | Generate, paint, place, enemy settings. Same seed, same result | Reopens the scene and checks |
| `test_mcp_tools_analysis` | Validate, analysis, room check, exports, ASCII, preview PNG | Fixture world with known issues |
| `test_mcp_end_to_end` | Rebuilds a small demo through `mds_batch` and compares with the build script's world. `test_mcp_editor` repeats a short version in the editor | Guards against tools drifting from the authoring flow |
| `test_mcp_guard` | Path escapes, `addons/` writes, tier refusals, `confirm`, limits, lock file | Direct calls |
| `test_mcp_history` | Undo restores bytes, refuses after a later edit, atomic batch rollback | Direct calls |
| `test_mcp_http` | Real sockets on an ephemeral port: headers, 202, 403 on bad Origin, 400 on header mismatch, 401, split packets, oversized body, SSE | `StreamPeerTCP` client polled with `await` |
| `test_mcp_stdio` | **Every stdout line parses as JSON**, across all tools. UTF-8, large messages, exit on EOF | Child process through `OS.execute_with_pipe`, so no Python in CI |
| `test_mcp_editor` | Child `--headless --editor`: forwarding, panel world edit plus undo, refusal on unsaved, reload after write | Child process. Allow a long timeout |

Notes:

- `run_all` has a 300 s limit per test scene and CI 1800 s overall. `test_mcp_editor` must kill its child in every path.
- Keep the 4.7.2 rule: `project.godot` must be restored after import, and tests must not save it. The guard test asserts its bytes are unchanged after all non-`full` tools.
- Rendering can't run headless, which is why `mds_room_preview` uses `Image`. A screenshot tool (Phase 5) gets a manual check.

**Beyond the suites:**

- Optional CI job with the official [conformance tests](https://github.com/modelcontextprotocol/conformance) and manual runs with the [Inspector](https://github.com/modelcontextprotocol/inspector). Both need Node, so keep them out of the main job. I haven't checked how far the conformance suite covers 2026-07-28.
- A manual client matrix in the release checklist: Claude Code on v1 and v2 runtimes, Claude Desktop, Cursor, on Windows, plus at least Linux.

Project rules still apply: LF endings, `graphify-gdscript scan .` after editing `.gd` files, and a changelog entry and README section with the release.

## 11. Phases

Each phase ends with `run_all` green on both versions and a checkpoint with you. Sizes are relative.

### Phase 0: prove it against real clients (small)

A throwaway server with only `mds_status`, on a branch that doesn't merge. **Stop and rethink if a gate fails.**

- Works in Claude Code, on both runtimes if they can be selected, plus Claude Desktop and Cursor.
- `\r\n` line endings accepted.
- **Windows stderr:** do these clients drain it? If one doesn't, the server must never write to stderr, which engine errors can't promise, and the isolated worker comes back into scope.
- What happens when a stray `print()` reaches stdout.
- `${GODOT4:-godot}` in `.mcp.json`. Which `.exe` to recommend.
- The same smoke test on Linux, by CI or WSL.

### Phase 1: protocol, stdio, read tools (medium)

- `mds_mcp_protocol`, `schema`, `stdio`, `main`, `guard`, headless host.
- Read tools: `mds_status`, `mds_catalog`, `mds_world_list`, `mds_world_get`, `mds_room_items`, `mds_room_ascii`, `mds_validate`, `mds_analysis`.
- Missing class cache: every call returns "run `--import`" instead of a parse error.
- **Result: a client can inspect a world with no editor.**

### Phase 2: authoring (large)

- All world, room, combat and game tools, `mds_batch`, `mds_undo`, lock file, audit log.
- `test_mcp_end_to_end`.
- **Result: an agent builds a playable area headless, equivalent to the demo build scripts.**

### Phase 3: editor (large, the riskiest)

- HTTP server, editor host, `endpoint.json`, forwarding, panel row, Copy config.
- The rules in [section 6](#6-editor-open-versus-headless), starting with a spike on the 4.6 dirty-scene fallback.
- Unfocused-editor latency: measure, then apply the boost.
- **Result: the same tools work with the editor open, map edits undo with Ctrl+Z, and unsaved work is never lost.**

### Phase 4: polish (medium)

- Resources, prompts, `mds_room_preview`, `mds_room_check`, progress over SSE, paging.
- README section, changelog, troubleshooting. Client matrix run.
- Trial: can an agent with only the prompts build a good area? Fix the tool descriptions where it stumbles.

### Phase 5: optional, only if wanted

Room view live edits with its own undo, scene edits through `EditorUndoRedoManager` (the panel [already does this for gates](../addons/MetroidvaniaDeveloperSystem/world_panel.gd#L1228)), editor screenshots, play and stop, a bridge into the running game, a packaged desktop extension, and listing in the MCP registry.

### Risks

| Risk | Likelihood | Impact | Handling |
|---|---|---|---|
| A client doesn't drain stderr on Windows and the server freezes | Unknown | High | Phase 0 gate, isolated worker as fallback |
| Stray `print()` from a user's `@tool` script breaks stdout | Medium | Medium | MDS's own 9 `print` calls are in runtime and debug paths, not authoring. Test stdout purity. Document it. Worker as fallback |
| Unsaved work lost | Low with these rules | High | Refuse by default, snapshots, editor tests |
| Spec keeps moving, and client support for 2026-07-28 varies | High | Low | Protocol layer is separate, dual-era, version list in one place |
| Tool surface grows and costs agents context | Medium | Medium | About 45 tools with short descriptions, batches. Claude Code [loads tools on demand](https://code.claude.com/docs/en/mcp); consider toolsets if others struggle |
| Long tools freeze the editor | Medium | Low | `await` between rooms, progress, measured caps |
| Editor and headless behave differently | Medium | Medium | One tool code path behind the host interface. End-to-end checks run in both modes |
| Fingerprint fallback unreliable on 4.6 | Medium | Low | Treat every open scene as unsaved on 4.6 |
| `world_panel.gd` (2,980 lines) needs more hooks than expected | Medium | Medium | Add public methods only, and stop at Phase 3 review if it spreads |

## 12. Open questions for you

1. **Default tier?** I recommend `author`, with `mds_gameplay_setup` and play tools in `full`.
2. **When an agent hits your unsaved scene,** refuse (my recommendation), or auto-save first?
3. **MetSys mode:** leave out of v1? I recommend yes. The tools target `MDSWorld`, and MetSys mode has its own map model.
4. **Ship `mcp/` in the addon?** I recommend yes, since it is inert until turned on. The alternative is a separate optional addon, which is cleaner to exclude but harder to install.
5. **Scope of v1:** stop after Phase 4, or include running the game (Phase 5)? Agents checking gameplay by playing is a strong feature, but it is a large project of its own.
6. **Which clients must work on day one?** I'd test Claude Code, Claude Desktop and Cursor. Tell me if others matter.
7. **Phase 0 needs you, or your go-ahead,** for Claude Desktop and Cursor if I can't drive them from here.

## 13. Sources

**MCP:** [versioning](https://modelcontextprotocol.io/specification/versioning) · [2026-07-28 changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog) · [deprecated features](https://modelcontextprotocol.io/specification/2026-07-28/deprecated) · [compatibility](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning) · [stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio) · [Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) · [discovery](https://modelcontextprotocol.io/specification/2026-07-28/server/discover) · [tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools) · [2025-11-25 transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) · [security best practices](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices) · [local server security](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/local-server-security)

**Clients:** [Claude Code](https://code.claude.com/docs/en/mcp) · [Claude Desktop](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop) · [Cursor](https://cursor.com/docs/context/mcp) · [VS Code](https://code.visualstudio.com/docs/copilot/customization/mcp-servers) · [Codex](https://developers.openai.com/codex/mcp) · [Gemini CLI](https://geminicli.com/docs/tools/mcp-server/) · [Windsurf](https://docs.windsurf.com/windsurf/cascade/mcp) · [Zed](https://zed.dev/docs/ai/mcp)

**Godot 4.6 source and docs:** [OS](https://github.com/godotengine/godot/blob/4.6-stable/doc/classes/OS.xml) · [Windows stdin](https://github.com/godotengine/godot/blob/4.6-stable/platform/windows/os_windows.cpp) · [Unix stdin](https://github.com/godotengine/godot/blob/4.6-stable/drivers/unix/os_unix.cpp) · [TCPServer](https://github.com/godotengine/godot/blob/4.6-stable/doc/classes/TCPServer.xml) · [EditorInterface 4.6](https://github.com/godotengine/godot/blob/4.6-stable/doc/classes/EditorInterface.xml) · [EditorInterface 4.7](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/EditorInterface.xml) · [editor settings](https://github.com/godotengine/godot/blob/4.6-stable/editor/settings/editor_settings.cpp) · [command line flags](https://github.com/godotengine/godot/blob/4.6-stable/main/main.cpp)

**Godot MCP projects:** listed in [section 4](#4-existing-godot-mcp-servers). Stars and activity are from GitHub on 2026-11-03.

Web search was unavailable in this session, so projects were found through GitHub search and pages were read directly. A project that GitHub search didn't rank highly could be missing from the survey.
