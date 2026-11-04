# Boss moves: what is built, what isn't, and the Fight editor

The move system (`addons/MetroidvaniaDeveloperSystem/gameplay/moves/`) lets a fight be put together from small, reusable actions instead of a state script for each boss. This page records how the fights it was designed against map onto it, what it can't do yet, and how the Fight editor came out against its plan.

## The fights it was designed against

The research came from the community wiki at hollowknight.wiki, whose attack names are not official. The recipes in `MDSMoveRecipes` are original patterns with original names and placeholder looks. They don't use Team Cherry's names or art, and they aren't copies: timings and numbers are starting points.

"Sister of the Void" isn't a boss. According to the wiki it is the achievement for defeating Lost Lace, so it has no recipe of its own.

| Reference fight | Recipe | How its attacks are made |
|---|---|---|
| Moss Mother | `swooper` | Swoop: `Fly` above the player, `Dash` at the player with `skid`. Ceiling slam: `Fly` up, `Cue` shake, `Shoot` from the ceiling with `marker_time`, or `Summon` grubs. The slam and the grubs are gained through `when: HEALTH_BELOW`. |
| Moss Mother pair | `twin_swooper` | As above, plus `Summon` with `partner` once, gated by a `FLAG`. `on_death` brings the second if the first dies before calling it. |
| Trobbio | `showman` | Whirlwind: `Dash` with `bounces`, then `Shoot` in an arc. Fireworks: `Zones` at random. Glitter bombs: `Shoot` with `bounces`, `fuse`, `knockable`. Flutter: `Leap` to `APEX`, `Fly`. Floorboard shuffle: `Vanish` with a marker. Pyrotechnics (phase 2): `Vanish HIDE`, floor `Zones`, `Vanish SHOW`. Dodge: a reaction. |
| Lace | `duelist` | Lunge: `Dash`. Triple cut: three `Strike`s, the last with `cancel_when: PLAYER_BEHIND`. Balestra: `Leap` to `APEX`, `Strike`, angled `Dash`. Parry: `Guard` with a `riposte`. Moulinet: `Zones` at the player, then `Leap`. Too close, or just hit: reactions. Three phases. |
| Lost Lace | `possessed_duelist` | Dive between attacks: `Vanish` next to the player. Long lash: a long `Strike`. Projectiles: `Shoot` from a ring at where the player was. Blobs: `Shoot` all around. Columns and waves: floor `Zones`. Lost moulinet: `Zones` at the player, a slam `Leap`. Four phases. |
| Sister Splinter | `hanging_matriarch` | Triple swipe: `Fly` over the player and a `Strike` with `reach_floor`, three times. Vine walls: ceiling `Zones` with `span_room` and `hits_to_break`, cleared by a stagger. Adds: `Summon`. Six walls once: `Zones` even, gated by a `FLAG`. Falls when staggered: `falls_when_staggered`. |

## What it can't do yet

These parts of the reference fights aren't covered. A subclass of `MDSMove` can add any of them.

- **Grabbing or trapping the player.** No move takes control of the player.
- **Changing the arena.** Floors that collapse, rising lava and similar changes aren't moves. A `Cue` can emit `move_cue` for your own scene to react to.
- **Chasing the player onto a wall.** `PLAYER_ON_WALL` can be tested, but no move clings to a wall.
- **A hit that only lands on some sides.** Trobbio's whirlwind is immune from the sides. `Guard` blocks every direction.
- **Silksong's own systems.** Needolin, tools deflecting off an attack and similar interactions depend on player abilities MDS doesn't have. The player's pogo in MDS is straight down only.
- **Game feel and art.** Recipes use placeholder looks and starting numbers. They have only been run by headless tests, so nobody has judged whether they feel good. Play `examples/boss_moves_demo/` to judge them.

## The Fight editor

The Fight editor is a mode of the MDS panel (**Fight editor** in its first drop-down). It is a second layer over the same resources: a fight is a tree of resources (`MDSMovePhase` → `MDSMovePick` → `MDSMoveSequence` → actions), and the graph shows that tree. It adds no runtime and no file format, so a fight stays editable by hand, in code or in the graph. How to use it is in the README, under "The Fight editor".

The two open questions in the plan were settled by asking for it: the graph lives in the MDS panel, and it covers `MDSMoveEnemy` as well as bosses.

### What differs from the plan

- **Layout positions aren't stored.** The graph lays itself out left to right each time, so there is no editor metadata to keep in step with a fight. You can't arrange nodes by hand: dragging one up or down changes its order among its siblings, then it settles back.
- **Conditions are edited in the side panel,** as rows for the selected move. A node lists them as lines of text, not as chips.
- **Reactions have no separate lane.** They are a slot of the phase, so they appear as its children in the same graph.
- **Checks are listed under the graph,** not in the panel's Issues tab, because they belong to the fight on show.

### What isn't built

- **MCP tools to build fights.** The MCP server still only reaches enemies through `mds_enemy_configure`.
- **A full preview of fights built in code.** A boss whose `_make_phases()` is overridden shows them read-only if its script is `@tool`, and otherwise a message asking for `@tool`. An enemy built in `_make_moves()` shows no preview either way. The game still reports these fights while it runs, but the graph has no nodes to light up for them.

### What has been checked, and what hasn't

`tests/test_fight_editor.gd` covers the model, every edit and its undo, conditions, recipes, the checks, the panel and the live view, on Godot 4.6.1 and 4.7.2. A real editor, run headless, was driven through opening scenes, editing with its undo history, and a running game reporting through the debugger.

**Nobody has looked at it yet.** Rendering can't run headless, so its appearance and how usable it feels are unknown, and mouse dragging has only been tested by sending `GraphEdit`'s signals directly. A move used twice under one running parent lights up in both places on the live view.

### Alternatives considered

- **LimboAI**, a mature behaviour tree and state machine plugin with its own visual editor. It remains the better choice for a team that wants general AI authoring. It's a compiled dependency, and it wouldn't know about phases, arenas, zones or recipes, so those would still need writing as its tasks. It has not been installed or tested with MDS.
- **Orchestrator**, a visual scripting plugin. It is general purpose, so a fight would be a large script graph rather than a list of moves. It has not been installed or tested with MDS either.
