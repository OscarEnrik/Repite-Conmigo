# AGENTS.md

Godot **4.8 (dev build `4.8-dev6`)** 2D game for "Repite Conmigo". Renderer is
**GL Compatibility** with the `d3d12` driver — *not* `forward_plus`. Don't reach for
Forward+ / 3D-only features.

Visual style for this prototype: focus on core mechanics, UI of choices, and state management, leaving complex style variations for later.

Structure and usage recipes live in `README.md`; design/art/credit docs in `docs/`.

**The step-by-step build order for the prototype is `docs/IMPLEMENTATION_PLAN.md` — follow its
steps in order and don't skip ahead.**

## Verifying changes

There is **no test suite** (`tests/` is empty). Running the game is the only real check:

1. `project_run` — must come back `status: "live"`, `ready: true`.
2. `editor_manage op="game_eval"` to inspect or drive the running game.
3. `logs_read` with `source: "game"` (editor logs are a persistent store that keeps
   stale errors forever — `logs_clear` does not wipe them, so don't read them as current).

`game_eval` executes inside the game process, so it's how you assert gameplay — e.g. inspect
`/root/Main/DialogueBox` (the choices panel hangs off `Main`, not off the day scene) and read
its state. **It requires an explicit `return`**, otherwise you get `null` and think it failed.
Inside a day, the day scene is `/root/Main/LevelHost`'s first child.

**`game_eval` has a hard ~8 s budget.** Exceed it and you get `EVAL_HUNG`; the abort can leave
the game frozen, and the next call fails with `EVAL_GAME_NOT_READY` — recover with
`project_manage op="stop"` then `project_run`. Budget it at ~60 fps of
`await get_tree().process_frame`, so a full 7-day week does **not** fit in one eval: split it
per ending or per batch of days.

## godot-ai MCP gotchas

The MCP stack is `godot-ai.exe` (a thin wrapper) → a **Python FastMCP server**. That server
is what listens on **8001** (HTTP/MCP, the transport the agent talks to) and **8002**
(WebSocket, where the *editor's addon* connects as a client). Its log is
`%LOCALAPPDATA%\godot-ai\runtime\backend-8001.log`. These cost real debugging time:

- **When the MCP server dies mid-call the editor wedges.** Its addon blocks, the window goes
  **"Not Responding"** with the CPU counter nearly frozen, and it never recovers on its own:
  force-close it (`taskkill /PID <pid> /F`) and relaunch
  (`Godot_v4.8-dev6_win64.exe --path <project> --editor`). Sanity check afterwards:
  `netstat -ano | findstr 8002` must show an `ESTABLISHED` pair between the editor and the
  MCP server.
- **`Port 8001 is occupied by a process the bridge cannot adopt`** and
  `Timed out waiting for backend startup lock …attach-http-8001.lock` mean orphaned backends
  are fighting over the port, each with its own nonce. Retrying while it is down makes it
  worse (every attempt spawns another backend). Kill whatever holds 8001/8002, wait, then
  make exactly **one** call.
- Killing that chain also drops the agent's own MCP connection: the `godot-ai` tools vanish
  from the catalog and nothing brings them back except reconnecting/restarting the MCP client
  in OpenCode. Prefer fixing the editor before shooting the server.
- **Serialize MCP calls.** Parallel bursts cause `Port 8001 is occupied…` and
  `Timed out waiting for backend startup lock`. Await each call in turn.
- **`script_create` emits false `Identifier not found: <Autoload>`.** The addon validates
  in an isolated compile with no autoload globals. The same file runs fine in game. Trust
  this diagnostic only for syntax errors and `class_name` resolution — do **not** rewrite
  working code to "fix" it.
- **Autoloads register only at editor startup.** Adding/changing autoloads while the editor
  is open leaves stale "Identifier not found" errors. Tell the user to restart the editor;
  don't chase it in code.
- **`autoload_manage add` appends**, and order is load order (`Audio`/`Game` depend on
  earlier ones). To reorder, remove *all* of them and re-add in sequence.
- **`game_manage next_frame` requires `suspend` first**, and a suspend that errors mid-way
  wedges the bridge (game keeps running but appears frozen). Always `resume` after.
- While the game is playing, scene/script writes fail with `EDITOR_NOT_READY`. Stop it first.

## Architecture

Six autoloads — order matters:

| Autoload | Script | Role |
|---|---|---|
| `Events` | `scripts/autoload/event_bus.gd` | signals only, **no game logic** |
| `Settings` | `settings_manager.gd` | volumes/fullscreen → `user://settings.cfg` |
| `Save` | `save_manager.gd` | `user://savegame.json` |
| `Audio` | `audio_manager.gd` | SFX pool + music; creates `Music`/`SFX` buses at runtime |
| `SceneLoader` | `scene_loader.gd` | fade + `change_scene` |
| `Game` | `game_manager.gd` | `State` enum, mood bar, day/turn progression, pause |

**Cross-system communication goes through `Events`**, never direct node references — the HUD
and dialogue menus must survive scene reloads. `Game` tracks the global mood bar and the 7-day progression (Monday to Sunday). `main.tscn` is the persistent host: `LevelHost` (days swap inside it) + `HUD` + `DialogueBox` + `PauseMenu`. Days resolve as `res://scenes/levels/day_%02d.tscn`.

### Naming traps

- **Never add a global `class_name` that collides with an autoload name or with a
  `Game.State` member.** A `class_name State` used to collide with the `Game.State` enum and
  broke startup; that is why nothing in the project is called `State`, `Events`, `Game`,
  `Audio`, `Save`, `Settings` or `SceneLoader` at global scope.
- Nodes the code needs are marked `unique_name_in_owner` and read via `%Name`, not `$Path`.
- `class_name` PascalCase; files/folders snake_case English; no spaces or uppercase in
  `res://` paths. Each `.tscn` lives beside its `.gd` (there is no `scripts/actors/` etc.).

### Game design

The design (loop, dialogue system, mood bar, endings) lives in `docs/GDD.md`. Input actions:
`ui_accept` / mouse click for dialogue choices, `pause` (Esc/P).

## Repo facts

- `project.godot` must keep the `_mcp_game_helper` autoload and the `[editor_plugins]`
  entry, or the MCP bridge dies. Preserve Jolt / `d3d12` / `gl_compatibility` too.
- There is no `stretch/scale_mode` key because `fractional` is the default — it is not
  missing, don't "fix" it.
- This folder is **not** a git repo: there is no `.git`, no Anchorpoint `.ap/` and no
  `*.approj`. `git` is also not on PATH in this shell, so don't reach for it.
- `addons/` is third-party — leave it untouched.

