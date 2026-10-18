# AGENTS.md

Godot **4.8 (official build `4.8-beta1`)** 2D game for "Repite Conmigo". Renderer is
**GL Compatibility** with the `d3d12` driver — *not* `forward_plus`. Don't reach for
Forward+ / 3D-only features.

Visual style for this prototype: pixel art narrative game focusing on core dialogue mechanics,
UI of choices, emotional animatics, and mood state management.

Structure and usage recipes live in `README.md`. **`docs/ARCHITECTURE.md` is the deep reference**:
how the boot → day → dialogue flow wires together, plus a "I want to change X → edit file:line"
recipe book. The design (loop, endings, constants) is in `docs/GDD.md`.

## Verifying changes

There is **no test suite** (`tests/` is empty). Running the game is the only real check:

1. `project_run` — must come back `status: "live"`, `ready: true`.
2. `editor_manage op="game_eval"` to inspect or drive the running game.
3. `logs_read` with `source: "game"` (editor logs are a persistent store that keeps
   stale errors forever — `logs_clear` does not wipe them, so don't read them as current).
4. `editor_screenshot` with `source: "game"` for anything visual — it returns the game framebuffer
   and is far more trustworthy than reading rects (`stale_frame: true` only means the game window
   is unfocused).

`game_eval` executes inside the game process, so it's how you assert gameplay — e.g. inspect
`/root/Main/DialogueBox` (the choices panel hangs off `Main`, not off the day scene) and read
its state. **It requires an explicit `return`**, otherwise you get `null` and think it failed.
Inside a day, the day scene is `/root/Main/LevelHost`'s first child.

**`game_eval` has a hard ~8 s budget.** Exceed it and you get `EVAL_HUNG`; the abort can leave
the game frozen, and the next call fails with `EVAL_GAME_NOT_READY` — recover with
`project_manage op="stop"` then `project_run`. Budget it at ~60 fps of
`await get_tree().process_frame`.

`logs_read source="editor"` permanently reports `GDScript::reload: The signal "…" is declared but
never explicitly used` once per `event_bus.gd` signal, plus an ANGLE/OpenGL driver warning. All
pre-existing noise — the **game** log is the one that matters.

## godot-ai MCP gotchas

The MCP stack is `godot-ai.exe` (a thin wrapper) → a **Python FastMCP server**. That server
is what listens on **8001** (HTTP/MCP, the transport the agent talks to) and **8002**
(WebSocket, where the *editor's addon* connects as a client). Its log is
`%LOCALAPPDATA%\godot-ai\runtime\backend-8001.log`. These cost real debugging time:

- **When the MCP server dies mid-call the editor wedges.** Its addon blocks, the window goes
  **"Not Responding"** with the CPU counter nearly frozen, and it never recovers on its own:
  force-close it (`taskkill /PID <pid> /F`) and relaunch
  (`Godot_v4.8-beta1_win64.exe --path <project> --editor`). Sanity check afterwards:
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
- After hand-editing a `.tscn`/`.gd` on disk, the editor's open copy goes stale. Use
  `scene_open path="..." force_reload=true` so the editor reloads the file from disk, avoiding
  overwriting changes on subsequent editor saves.

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
and dialogue menus must survive scene reloads. `Game` tracks the global mood and the 4-day
progression (`DAY_COUNT = 4`, Lunes a Jueves). `main.tscn` is the persistent host:
`LevelHost` (days swap inside it) + `HUD` + `DialogueBox` + `AnimaticPlayer` + `PauseMenu`.
Days resolve as `res://scenes/levels/day_%02d.tscn`.

### UI layout & styling

- The canvas is **1920×1080** and UI dimensions scale the original 640×360 design × **3**.
- `window/size/window_width/height_override` (1280×720) takes precedence over `size/mode=2`, so the
  window opens **windowed, not maximized**, while the canvas stays 1920×1080 → the game renders at
  ×0.667. Rects you measure in `game_eval` are **canvas units, not screen pixels**.
- **Every font size comes from `resources/themes/main_theme.tres` → `default_font_size` (`40`)**,
  with `Bitshow.otf` font and font color `#332017`. Node-specific overrides use
  `theme_override_font_sizes/font_size`.
- Layer order:
  - Day `UI`: `0`
  - `HUD`: `1`
  - `DialogueBox`: `5`
  - `AnimaticPlayer`: `8`
  - `PauseMenu`: `10`
  - `SettingsMenu`: `20`
- The layout is tight and the day card's height is **deliberately fixed**: HUD `0..262`, card
  `288..732`, dialogue panel `450..1080`. Card and dialogue panel overlap but are never shown
  together (the card hides on `dialogue_turn_started`).

### Core Systems & Flow

1. **Boot & Menus**: `boot.tscn` → `main_menu.tscn` → `main.tscn` → `ending.tscn`.
2. **Day Lifecycle**:
   - `AnimaticPlayer` plays intro vignettes (`1.png` .. `4.png`) or title card.
   - `DayStage` shows Richard wandering the green floor until clicked.
   - `IntroCard` reveals the day's narrative prompt; clicking "Continuar" triggers `Game.begin_dialog()`.
3. **Dialogue & Choice System**:
   - 3 dialogue options displayed side-by-side (`HBoxContainer`) with text auto-wrapping.
   - Options behave as mutually exclusive toggle buttons.
   - Dedicated "Confirmar" (`%ConfirmButton`) applies the choice with `Game.choose_option()` and advances turn.
4. **Mood & Progression**:
   - Mood value persists across day transitions (accumulates through the week, starting at 50 on Day 1).
   - In the HUD, `MoodValueLabel` updates immediately, and `DeltaLabel` (inside `MoodRow/DeltaAnchor`)
     animates via a Tween: pops in, drifts down for penalties (`-12` in red) or up for rewards (`+10` in green),
     pauses, and fades out.
   - Day ends when `TURNS_PER_DAY` (2 turns) finish; the week concludes after Day 4, directing to `ending.tscn`.

### Naming traps

- **Never add a global `class_name` that collides with an autoload name or with a
  `Game.State` member.** Nothing in the project is called `State`, `Events`, `Game`,
  `Audio`, `Save`, `Settings` or `SceneLoader` at global scope.
- Nodes the code needs are marked `unique_name_in_owner` and read via `%Name`, not `$Path`.
- `class_name` PascalCase; files/folders snake_case English; no spaces or uppercase in
  `res://` paths. Each `.tscn` lives beside its `.gd`.

### Game design

The design (loop, dialogue system, mood bar, endings) lives in `docs/GDD.md`. Input actions:
`ui_accept` / mouse click for dialogue choices and animatics, `pause` (Esc/P).

## Repo facts

- `project.godot` must keep the `_mcp_game_helper` autoload and the `[editor_plugins]`
  entry, or the MCP bridge dies. Preserve Jolt / `d3d12` / `gl_compatibility` too.
- There is no `stretch/scale_mode` key because `fractional` is the default — it is not
  missing, don't "fix" it.
- This folder is **not** a git repo: there is no `.git`, no Anchorpoint `.ap/` and no
  `*.approj`. `git` is also not on PATH in this shell, so don't reach for it.
- `addons/` is third-party — leave it untouched.
