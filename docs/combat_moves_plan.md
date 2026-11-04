# Boss moves: what is built, what isn't, and the visual editor plan

The move system (`addons/MetroidvaniaDeveloperSystem/gameplay/moves/`) lets a fight be put together from small, reusable actions instead of a state script for each boss. This page records how the fights it was designed against map onto it, what it can't do yet, and the plan for a visual editor. **The editor is a plan: none of it is built.**

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

## Visual editor plan

**Recommendation: build it, as a second layer over the same resources.** A fight is already a tree of resources (`MDSMovePhase` → `MDSMovePick` → `MDSMoveSequence` → actions), which maps directly onto nodes in a graph. The editor would add no new runtime and no new file format, so a fight stays editable by hand, in code or in the graph. The inspector can already edit these trees, but deep nesting is hard to read there, and that is the main thing a graph would fix.

### Scope

1. **Fight panel.** A bottom panel built on `GraphEdit`, opened by selecting an `MDSMoveBoss` or an `MDSMovePhase`. One tab per phase, with its thresholds and speed at the top.
2. **A node per move.** Generated from each class's exports, so a custom `MDSMove` subclass appears without extra code. Sequences show their children in order, picks show weights and parallels show branches.
3. **Conditions on the node.** `when` and `cancel_when` shown as chips, and `reactions` in a separate lane beside the main tree.
4. **Saving.** Editing the resources in place through `EditorUndoRedoManager`, saved as `.tres`. Layout positions stored in editor metadata, never read at runtime.
5. **Start from a recipe.** "New from recipe" turns an `MDSMoveRecipes` fight into resources to change.
6. **Live view while playing.** Highlight the running move, cooldowns and flags through `EngineDebugger` messages. This is the most useful part for tuning, so it comes straight after the first usable graph.
7. **Checks.** Warn about a move with no `when` that can never run, an empty pick, or a pick whose moves can all be gated off at once.

### Order

| Step | Delivers | Size |
|---|---|---|
| 1 | Read-only graph of a phase | Small |
| 2 | Editing, adding and reordering with undo | Medium |
| 3 | Conditions, reactions and recipe import | Small |
| 4 | Live highlighting while playing | Medium |
| 5 | Checks in the Issues tab, and MCP tools to build fights | Small |

### Alternatives considered

- **LimboAI**, a mature behaviour tree and state machine plugin with its own visual editor. It remains the better choice for a team that wants general AI authoring. It's a compiled dependency, and it wouldn't know about phases, arenas, zones or recipes, so those would still need writing as its tasks. It has not been installed or tested with MDS.
- **Orchestrator**, a visual scripting plugin. It is general purpose, so a fight would be a large script graph rather than a list of moves. It has not been installed or tested with MDS either.

### Open questions

- Should the graph live in the MDS panel or in its own bottom panel? Its own panel looks more likely, because the graph needs width.
- Should it cover `MDSMoveEnemy` from the first step? It should cost little, since an enemy is one tree without phases.
