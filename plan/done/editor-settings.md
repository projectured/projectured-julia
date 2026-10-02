# A person sets how an editor works, in a settings document

> **Status:** done on 2026-10-02. Written on 2026-10-01 at the owner's
> request. The owner decided the design on 2026-10-01; section 5 logs each
> decision. Step W1 of the appearance plan landed on `main` on 2026-10-01
> (`03e83ba36`), so the work can start (D10). Section 9 of the appearance plan
> and 3.8 here give what W1 changed. The kernel word "setting" of a wrapper
> becomes "argument" first (D12, step R1). The palette command "Show the
> settings" came on 2026-10-02, after the plan was done (S8).

## 1. The request

The owner asked on 2026-10-01:

> in projectured-julia, I'd like to have a projectured settings document and
> projections similar to how themes will be edited, the settings would control
> partial render, dirty render and other global options that you may find
> reasonable to control through normal widge editing and using operation
> produced by the wrapper projection transforming the normal editing operations
>
> let's design this, what settings make sense, how to store them, how to
> conifure them, how to apply them, how to save/load them, where, etc.

"How themes will be edited" is `plan/done/zoom-and-theme-controls.md`, the
appearance plan below. This plan follows its form: a collection of documents for
each editor, a wrapper of `build_editor` that handles a change, a tool tab, and a
TOML file. "Dirty render" is the red outline of the region that a frame repaints,
`debug_dirty` now.

## 2. The words

- A **setting** is one value that a person chooses about how an editor works, or
  about what it shows to find a fault. Example: whether a window repaints only
  the parts that changed.
- The **appearance** is how the content looks: the zoom, the scales and the
  themes. The appearance plan owns it. This plan does not change it.
- A **settings group** is a document that holds the settings of one part of the
  editor. Example: `RenderSettings` holds the settings of the repaint. The slice
  that owns the effect of a group declares it.
- `Settings` is the collection of the groups of one editor, found by the type of
  the group.
- To **apply** a group is to copy its values to the place outside the documents
  where they act. Example: the field `partial_render` of an `SdlBackend`.
- The **kind** of a setting says how it takes effect:

| Kind | What the code does | Example |
| --- | --- | --- |
| copied | `apply_settings!` copies the value into a field of the backend or of the editor. | partial render |
| read | The code that acts reads the cell of the setting each time that it acts. | the interval of a double click |
| start | The application reads the value once, when it starts. The tab says so. | the assistant |

An apply can also ask for a new print of the view, when a projection reads the
value while it prints. The fault policy is such a value (3.3).

## 3. What exists

### 3.1 Partial render and the repaint outline

- `SdlBackend` has two plain fields, `partial_render` and `debug_dirty`
  (`source/backend/sdl/SdlBackend.jl:200-201`). One value acts on every window of
  the backend.
- The constructor reads `PROJECTURED_PARTIAL_RENDER` and
  `PROJECTURED_DEBUG_DIRTY` once, when its keyword is `nothing` (`:228-233`).
  Both are off by default.
- `_render_window!` reads both fields in each frame (`:2862-2863`). With partial
  render off, it repaints the whole window. The walk of the change runs in both
  modes, so a switch between the modes is safe at any frame.
- With `debug_dirty` on, each frame copies the whole target to the window, so the
  outline of the frame before goes away (`:2915`). When `debug_dirty` goes off,
  the last outline stays on the back buffer until the next full copy.
- `VideoBackend` has `partial_render`, `debug_dirty` and `debug_dirty_hold`
  (`source/backend/video/VideoBackend.jl:122-124`), set by keyword only.
  `debug_dirty_hold` keeps each outline for a number of seconds. The SDL backend
  has no hold.
- The web backend has neither field. It always sends a patch of the changes.
- `_force_full_repaint!(editor)` (`SdlBackend.jl:4207`) makes the next frame
  repaint each window in full.

### 3.2 Supersample

- `_window_supersample()` (`SdlBackend.jl:628`) reads `PROJECTURED_SUPERSAMPLE`.
  The default is 2, and the value is clamped to 1 to 4. A value of 1 turns it off.
- The backend reads it once, when it makes a window, into
  `SdlWindowResources.ss`. The retained target of the window has the size of the
  window times `ss`. So a change at run time needs a new target for each window.

### 3.3 The fault policy

- `FaultPolicy` (`source/kernel/fault/FaultPolicy.jl`, ⬜) has three flags:
  `is_barrier_enabled`, `is_console_enabled` and `is_sound_enabled`. It is
  immutable, and `Editor.fault_policy` holds one.
- `run_editor!` replaces it, and calls `invalidate_projection!` when it changes
  (`source/kernel/editor/EditorLoop.jl:161`). The reason: `print!` puts the policy
  into the printer context, and the barriers read it there.
- The command line has `--strict-fault-policy`.

### 3.4 The pointer

- `ClickRecognition` (`source/kernel/gesture/ClickRecognition.jl`) holds four
  limits. A click moves less than 5 pixels and lasts less than 0.3 s. The next
  click of a double click comes within 5 pixels and 0.3 s. The limits are plain
  fields of an immutable struct.
- `DwellRecognition(; delay = 0.5)` gives a `MouseDwell`, which opens a tooltip.
- `make_standard_recognitions()` makes the chord, the click and the dwell
  recognition. `GestureTrackingProjection` and `WindowScene` take them as a
  keyword (`source/platform/screen/WindowScene.jl:93,125`). So the limits are
  fixed when the projection is built.
- `DraggingProjection(; threshold = 5)`: a press becomes a drag after 5 pixels.
- `ClickRecognition.jl` and `DwellRecognition.jl` are not in the inventory of
  `SEALING.md`. The other files of the gesture layer are ⬜.

### 3.5 The limits of the histories and the logs

| Limit | Default | Where |
| --- | --- | --- |
| undo steps | 100 | `UndoBuffer.capacity`, a plain `Int` (`source/platform/undo/UndoDocument.jl:77`) |
| message log lines | 200 | `MessageLog.capacity` (`source/platform/log/MessageLogDocument.jl:11`) |
| captured log lines | 1000 | `MessageLogStore.capacity`, one store for the process |
| gesture log entries | 20 | `GestureLog.capacity` (`source/platform/gesturelog/GestureLogDocument.jl:13`) |
| faults | 64 | `FaultStore.capacity` (`source/kernel/fault/FaultStore.jl`, 🔒) |
| frame measurements | 1000 | `FrameMeasurementStore.capacity` (`source/kernel/performance/FrameMeasurement.jl`, 🔒) |

### 3.6 The options of the application

`run_application` and its command line (`parse_application_arguments`,
`source/platform/application/Application.jl:450`) take `assistant` (`:ollama`,
`:anthropic` or `:none`), `model`, `context`, `mcp` with its host and port,
`root`, the size of the window and the fault policy. Each acts once, when the
application starts. The `Assistant` document holds its backend, its model and its
context as cells, so a person can change them in the assistant tab of an editor
that runs.

### 3.7 Values that are not settings for a person

The search of 2026-10-01 found these values. This plan leaves them out:

- `PROJECTURED_PERFORMANCE_COUNTERS` is a switch at compile time.
- `PROJECTURED_DISPLAY_SCALE` is a fact of the hardware. The appearance plan
  renames it to the density.
- `PROJECTURED_FONT_DIR` is a path for the process.
- `FRAME_INTERVAL` (10 ms), `MAX_OPERATIONS_PER_FRAME` (32), `INBOX_CAPACITY`
  (64), `_HOVER_MOTION_INTERVAL` (30 ms), `_DIRTY_RECT_LIMIT` (32),
  `_DAMAGE_HISTORY_CAP` (8) and the cap of the text textures (16384) tune the
  code. A person does not choose them, and a wrong value makes the editor slow or
  wrong.
- `ANTHROPIC_API_KEY` and `OPENROUTER_API_KEY` are secrets. A settings file is
  plain text, so a key stays in the environment.
- The host and the port of `WebBackend` and of `McpServer` are the address of a
  server. The person gives it when the server starts.

### 3.8 The appearance plan

`plan/done/zoom-and-theme-controls.md` landed its steps up to W2 on `main`
on 2026-10-01 (`03e83ba36`): `UntrackedCell`, `@theme`, `Appearance`,
`InvalidateProjectionOperation`, the slice `source/platform/appearance/` and the
seam of the build. The tab (W3) and the save and the load (W6) are not done.
What W1 gives this plan:

- **The seam of the build.** `make_wrapper_setting(::Val{keyword}, setting)`
  (`source/kernel/editor/EditorBuild.jl`) makes the value of each wrapper setting
  before anything is built. The `appearance` wrapper answers a new `Appearance`
  for `true`. `make_document_projection(document; settings...)` gets the value of
  each wrapper setting, by its keyword, on the path with no projection.
- **A wrapper sees the settings of the others** (its D32). `EditorParts.settings`
  holds the value of each wrapper setting, by keyword. The `tabs` wrapper takes
  the `Appearance` there: `get(parts.settings, :appearance, Appearance())`
  (`source/platform/pane/PaneTabsWrapper.jl:60`).
- **The form of the wrapper.** `AppearanceManagingProjection`
  (`source/platform/appearance/AppearanceManagingProjection.jl`) holds only its
  inner projection, and reads the `Appearance` from its input, the
  `AppearanceDocument`. Its reader gives a `CollectIntents` to the content and
  merges the bindings of the document; it gives a routed intent to the content;
  else it asks the content first and then the gesture table of the
  `AppearanceDocument` (`read_gesture`). It puts `InvalidateProjectionOperation`
  after an answer that changes the appearance. Its layer is `:screen => 0`.
- **The keys are in the gesture table of the document**: `@gestures
  AppearanceDocument` (`AppearanceDocument.jl`), so F1 and the palette list them.
- **A test that checks the root of a built editor** turns the wrapper off with
  `appearance = false` (its finding 16).
- **Its finding 15** says that the palette lists only a binding with a key. A
  command rule with no key exists (`nothing => "description" => rhs`,
  `source/kernel/binding/Gestures.jl:146`, used in
  `source/platform/conversation/Evaluator.jl:712`). Step S7 finds which one
  holds.

### 3.9 How an edit of a settings document reaches the root

- `ObjectToWidget` (`source/platform/widget/ObjectToWidget.jl`) shows the fields
  of an object as a form. It turns a control edit into
  `ReplaceReferencedValueOperation(root, path, value)`, the normal edit of a
  field.
- A `ReplaceReferencedValueOperation` that carries its own document passes each
  wrapper unchanged (`reroot_operation`,
  `source/kernel/operation/Rerooting.jl:38-44`). So a wrapper at the root sees
  the document that the write changes.
- A `WrappingOperation` is "an operation that holds one other operation and does
  something around it", for "a change [that] is another change plus an effect"
  (`source/kernel/operation/OperationInterface.jl:28-49`). `RecordUndoOperation`
  and `ReplaceViewStateOperation` are two of them.
- `make_inverse_operation(document, operation)` is the seam of the inverse. The
  editor takes the inverse before it evaluates the operation
  (`source/kernel/operation/Inversion.jl`).
- `evaluate_operation(editor, operation)` gets the editor. So an operation of a
  platform slice can reach `editor.backend` and `editor.fault_policy`.
- `SaveDocumentOperation` and `LoadDocumentOperation`
  (`source/platform/serialization/BinarySerialization.jl:73,95`) write and read a
  file.
- A history skips a write of view state (`_is_no_edit`,
  `source/platform/undo/UndoDocument.jl:167`).
- No settings document, settings tab or settings file exists.

## 4. The design

### 4.1 The settings of an editor

A `Settings` holds the settings groups of one editor, found by the type of the
group, as an `Appearance` holds the themes.

- The main builder, `run_application`, makes the `Settings`. It fills it from the
  file, the environment and the command line (4.9), builds the projection with
  it, and passes it to `build_editor` as `settings = collection`.
- The `settings` wrapper of `build_editor` is in the `:screen` layer and on by
  default. It wraps the root document in a `SettingsDocument` with the fields
  `settings` and `content`. It wraps the projection in a
  `SettingsManagingProjection` (4.5). Its start step applies each group once
  (4.7).
- `make_wrapper_argument(Val(:settings), true)` answers a new `Settings` (3.8,
  with the names of D12). On the path with no projection,
  `make_document_projection` gets it by its keyword, so the projection and the
  wrapper share it. Another wrapper reads it from `EditorParts.arguments` (4.8).
- With `settings = true`, the wrapper makes a `Settings` with the defaults and
  the environment. It never reads the file, so a test that calls `build_editor`
  does not depend on the file of the person.

**The editor knows nothing about settings.** It holds none, and the kernel reads
none. The editor evaluates the operations as now.

### 4.2 A settings group

A slice declares a group with the macro `@settings`. Each field has a docstring,
a type, a default and, when needed, the values that it can take:

```julia
@settings struct RenderSettings
    "Repaint only the parts of a window that changed."
    partial_render::Bool = false
    "Outline in red the parts of a window that each frame repaints."
    debug_dirty::Bool = false
    "Keep each outline for this number of seconds."
    debug_dirty_hold::Float64 = 0.0 in 0.0:0.5:5.0
    "Pixels in each direction for each pixel of a window. 1 turns it off."
    supersample::Int = 2 in 1:4
end
```

The macro generates:

- a `@document` struct `RenderSettings <: SettingsGroup`, with one cell for each
  field;
- `get_setting_descriptions(::Type{RenderSettings})`: one `SettingDescription`
  for each field, with the name, the label from the docstring, the type, the
  default, and the values that it can take;
- `get_settings_name(::Type{RenderSettings})`: `"render"`, the name of its table
  in the file.

The tab, the check of a value, the reset and the file use only the descriptions.
So a new setting is one line in one place. The types are `Bool`, `Int` and
`Float64` with a range, `Symbol` with a tuple of choices, and `String`.

### 4.3 The settings

The owner chose the set (D1): first the table without the start group, then
the start group.

| Group (slice) | Setting | Type, default, values | Kind | Where it acts |
| --- | --- | --- | --- | --- |
| `RenderSettings` (screen) | `partial_render` | `Bool`, off | copied | `SdlBackend`, `VideoBackend`; the next frame repaints in full once |
| | `debug_dirty` | `Bool`, off | copied | the same; when it goes off, the next frame repaints in full, so the last outline goes |
| | `debug_dirty_hold` | `Float64`, 0, 0 to 5 s | copied | `VideoBackend` now; the SDL backend gets the same hold |
| | `supersample` | `Int`, 2, 1 to 4 | copied | `ss` of each SDL window; the backend makes the target again |
| `FaultSettings` (fault) | `is_barrier_enabled` | `Bool`, on | copied | `editor.fault_policy`; a change also prints the view again, as `run_editor!` does |
| | `is_console_enabled` | `Bool`, on | copied | `editor.fault_policy` |
| | `is_sound_enabled` | `Bool`, on | copied | `editor.fault_policy` |
| `PointerSettings` (gesturetracking) | `multi_click_max_interval` | `Float64`, 0.3, 0.1 to 1 s | read | `ClickRecognition` |
| | `click_max_displacement` | `Int`, 5, 1 to 20 | read | `ClickRecognition`, for the click and for the next click |
| | `dwell_delay` | `Float64`, 0.5, 0.1 to 3 s | read | `DwellRecognition`, so the delay of a tooltip |
| | `drag_threshold` | `Int`, 5, 1 to 20 | read | `DraggingProjection` |
| `HistorySettings` (undo) | `undo_capacity` | `Int`, 100, 10 to 10000 | read | each `UndoBuffer` that the editor makes |
| `LogSettings` (log) | `message_log_capacity` | `Int`, 200, 50 to 10000 | read | `MessageLog` |
| `StartSettings` (application) | `assistant` | `Symbol`, `:ollama`, (`:ollama`, `:anthropic`, `:none`) | start | `run_application` |
| | `model` | `String`, empty | start | `run_application` |
| | `context` | `Int`, 0, 0 to 1048576 | start | `run_application` |
| | `mcp` | `Bool`, off | start | `run_application` |

Where a field exists now, the setting keeps its name: `partial_render`,
`debug_dirty`, `is_barrier_enabled`, `multi_click_max_interval` and the others.
So no code must change a name. A setting for a field with a short name gets a
longer one: `delay` becomes `dwell_delay`, `threshold` becomes `drag_threshold`,
and `capacity` becomes `undo_capacity`. The tab shows the label from the
docstring.

### 4.4 The settings tab

A tool tab, as the fault log is. Its projection is `SettingsToWidget`. It shows
the `Settings` of its own editor.

- One `WidgetCard` for each group, with the name of the group. One row for each
  setting: the label, the control, and a button that resets the setting. The
  docstring is the tooltip of the label.
- The type of the setting gives the control:
  - `Bool`: a `WidgetSwitch`;
  - `Int` or `Float64` with a range: a `WidgetSpinBox`, with the step of the
    range;
  - `Symbol`: a `WidgetSelect` of the choices;
  - `String`: a `WidgetText`.
- A row of the kind "start" shows "Takes effect at the next start".
- When no target of this editor applies a group (`is_settings_target`, 4.7), the
  card shows "This editor does not use these settings", and its controls are
  disabled. Example: `RenderSettings` in a web editor.
- Under the cards: "Reset all", "Save" and "Load".
- The tab opens from the toolbar, from the View menu and from the command palette
  ("Open settings").
- **The tab knows no effect.** Its reader turns a control edit into the normal
  edit of the group, `ReplaceReferencedValueOperation(group,
  FieldReference(name), value)`. The wrapper does the rest (4.5).

### 4.5 The wrapper turns a normal edit into an applied setting

`SettingsManagingProjection` wraps the whole view, in the `:screen` layer,
outside the `appearance` wrapper. It has the form of
`AppearanceManagingProjection` (3.8): it holds only its inner projection, and
reads the `Settings` from its input, the `SettingsDocument`. It holds no cell
and no edge.

```julia
function read_intent(p::SettingsManagingProjection, recursion, intent, iomap)
    # A CollectIntents and a routed intent go to the content, as in the
    # appearance wrapper.
    answer = <the answer of the content, rerooted under `content`>
    answer isa Operation ||
        (answer = read_gesture(iomap.input, <the event>))   # its gesture table
    Intent(intent.gesture, wrap_setting_writes(iomap.input.settings, answer))
end
```

`wrap_setting_writes` walks the answer, into each `CompoundOperation` and each
`WrappingOperation`. It replaces each `ReplaceReferencedValueOperation` whose
document is a group of the `Settings` with `ApplySettingOperation(write)`. A write
with no document, whose reference goes through `SettingsDocument.settings`, gets
the same. Every other operation stays as it is.

Why the wrapper, and not the tab:

- Each view of a settings group makes the same normal edit: the tab,
  `ObjectToWidget`, an inspector, a paste. The wrapper is the one place
  where each of them becomes an applied setting.
- The tab stays a plain view of a document. It knows no backend and no editor.
- The tab, the reset and a later view of the settings can not forget the apply.

The gesture table of the `SettingsDocument` acts only when the content declines
the input. It holds three commands of the palette, "Open settings", "Toggle
partial render" and "Toggle repaint outline". Each toggle answers the
`ApplySettingOperation` of the write that toggles the value. They have no key
(D8).

### 4.6 `ApplySettingOperation`

```julia
struct ApplySettingOperation <: WrappingOperation
    operation::ReplaceReferencedValueOperation   # a write into a settings group
end
```

- **The evaluation** has three parts:
  1. Check the value against the description. Convert it to the declared type,
     for example the text "3" to 3 for an `Int`, and check the range or the
     choices. If the value does not fit, change nothing and write one warning to
     the log.
  2. Evaluate the write, as the kernel does.
  3. Apply the group: `apply_settings!(editor, group)` and
     `apply_settings!(editor.backend, group)` (4.7).
- **The inverse** is the `ApplySettingOperation` of the inverse of the write. The
  write of the old value comes first and the apply after it, so the target gets
  the old value back.
- **The description** is "Set <label> to <value>", for the gesture log and the
  message log.
- **The other paths.** The effect is in the evaluation, not in the wrapper. So an
  `ApplySettingOperation` from the inbox, from the MCP server, from the assistant,
  from a load or from a reset applies its group. It does not need the reader
  chain.
- `ResetSettingsOperation(settings)` and `LoadSettingsOperation(settings, path)`
  evaluate one `ApplySettingOperation` for each value that changes.
  `SaveSettingsOperation(settings, path)` writes the file and changes no
  document, as `SaveDocumentOperation` does.

Why a wrapping operation, and not a second operation after the write, as the
appearance wrapper adds `InvalidateProjectionOperation`: the inverse of
`CompoundOperation([write, apply])` runs in the opposite order. It applies first
and writes the old value after it, so the target keeps the new value. A wrapping
operation keeps the apply after the write in both directions.

### 4.7 `apply_settings!`

`apply_settings!(target, group)` copies the values of a group to one target. The
settings slice declares it, with a default that does nothing. The slice or the
package that owns a target adds a method for each group that acts on it:

| Method | Package | What it does |
| --- | --- | --- |
| `apply_settings!(::SdlBackend, ::RenderSettings)` | the SDL backend | sets `partial_render`, `debug_dirty` and the hold; for a new `supersample`, sets `ss` of each window and drops its target; asks each window for a full repaint |
| `apply_settings!(::VideoBackend, ::RenderSettings)` | the video backend | sets its three fields |
| `apply_settings!(::Editor, ::FaultSettings)` | the platform fault slice | sets `editor.fault_policy`; calls `invalidate_projection!(editor)` when `is_barrier_enabled` changes |

- `is_settings_target(target, group)` answers whether such a method exists. The
  tab reads it (4.4).
- `ApplySettingOperation` calls it, and so do the reset and the load through it.
  The start step of the wrapper calls it once for each group, so the values from
  the file and from the environment reach the backend.
- A group of the kind "read" or "start" needs no method.

### 4.8 The settings that the code reads where it acts

- **The pointer.** Each limit of `ClickRecognition` and `DwellRecognition` takes
  a number or a cell (`Union{Real, AbstractCell}`), and the recognition reads the
  cell at each input. The default stays a number, so the tests do not change.
  `make_standard_recognitions(settings::PointerSettings)` gives the cells of the
  group. The `window` wrapper, which makes the recognitions in `WindowScene`,
  takes the `Settings` from `EditorParts.arguments` when its own argument names
  no recognitions, as the `tabs` wrapper takes the `Appearance` (3.8).
  `DraggingProjection` takes its threshold in the same way.
- **The history and the log.** The capacity of an `UndoBuffer` and of a
  `MessageLog` becomes a cell. The builder that makes one gives it the cell of
  the group. A smaller capacity drops the oldest entries at the next push.
- A reader or an evaluation reads these cells outside a computation, so the read
  records no edge.

### 4.9 Save and load

- **The file** is `settings.toml`, beside `appearance.toml` of the appearance
  plan, in the configuration folder of the platform. On Linux that is
  `$XDG_CONFIG_HOME/projectured/`, by default `~/.config/projectured/`. An
  application can name another file.
- **The form** is one table for each group, named by `get_settings_name`, and one
  key for each setting:

  ```toml
  [render]
  partial_render = true
  debug_dirty = false
  debug_dirty_hold = 0.0
  supersample = 2

  [fault]
  is_barrier_enabled = true
  is_console_enabled = true
  is_sound_enabled = true
  ```

- A key that is missing takes its default. A key or a table that is not known is
  ignored. A value that does not fit takes the default. Each of these writes one
  warning to the log, and none of them stops the load.
- **Save** writes the values of this editor. **Load** reads the file and applies
  each value that changes. The editor never saves on its own.
- **The order of the sources** when the application starts, from the weakest:
  the default, the file, the environment variables, the command line. A later
  source wins for this run. The tab shows the result, and a Save writes it.
- **The environment variables** stay, for one run: `PROJECTURED_PARTIAL_RENDER`,
  `PROJECTURED_DEBUG_DIRTY` and `PROJECTURED_SUPERSAMPLE`. The settings slice
  reads them, in one place. The `SdlBackend` constructor and
  `_window_supersample` stop their read (D6). `SdlBackend(;
  partial_render, debug_dirty)` keeps its keywords, with off as the default, for
  `make_editor`, which applies no wrapper.
- `--strict-fault-policy` sets `is_barrier_enabled` to off, as a source of the
  command line.
- Two editors can use one file. Each writes it when its person presses Save. The
  last save wins at the next start.
- The read and the write of the file share one helper with the appearance plan
  (its W6): the folder, the read of a TOML table into a document, and the write.
  The plan that lands second uses the helper of the first.

### 4.10 One editor, one `Settings`

- Each editor has its own `Settings` (PAR-PER-EDITOR-STATE). Two editors in one
  process have two, and a change in one leaves the other.
- An `SdlBackend` serves one editor, so `partial_render` acts on all the windows
  of one editor.

### 4.11 The slices

| Part | Slice |
| --- | --- |
| `SettingsGroup`, `@settings`, `SettingDescription`, `Settings`, `ApplySettingOperation` and the other operations of the settings, `apply_settings!`, `is_settings_target` | a new slice `source/platform/settings/`, before `gesturetracking` |
| `RenderSettings` | `screen` |
| `FaultSettings` and its apply | the platform `fault` slice |
| `PointerSettings` and `make_standard_recognitions(settings)` | `gesturetracking` |
| `HistorySettings` | `undo` |
| `LogSettings` | `log` |
| `StartSettings` | `application` |
| `SettingsDocument`, `SettingsManagingProjection`, the `settings` wrapper, `SettingsToWidget`, the commands of the palette, the save and the load | a new slice `source/platform/settingsmanaging/`, above `widget` |
| the toolbar item and the View menu item | `shell` (`WindowChrome.jl`) |
| `apply_settings!` for `SdlBackend` and for `VideoBackend` | the SDL backend and the video backend |

The tab and the wrapper find the groups by type in the `Settings` while the
editor runs. So the slice `settingsmanaging` does not depend on the slices of the
groups.

### 4.12 The new mechanisms

PAR-NO-NEW-SYNTHETIC-EVENT and the word of the owner of 2026-09-23 need each new
mechanism named and approved before it is added. The owner approved each of
these on 2026-10-01 (D11). This plan adds:

1. `Settings`, `SettingsGroup`, `SettingsDocument` and the `settings` wrapper of
   `build_editor`.
2. The macro `@settings` and `SettingDescription`.
3. `SettingsManagingProjection`, whose reader wraps each write into a settings
   group.
4. `ApplySettingOperation`, `ResetSettingsOperation`, `LoadSettingsOperation` and
   `SaveSettingsOperation`.
5. The seam `apply_settings!(target, group)`, and `is_settings_target`.
6. Limits of `ClickRecognition`, `DwellRecognition`, `DraggingProjection`,
   `UndoBuffer` and `MessageLog` that take a cell.
7. A change of the supersample of a window while the window is open.
8. The hold of the repaint outline in the SDL backend.
9. The file `settings.toml`.

The plan uses the seam of the build and `EditorParts.arguments`, which W1 of the
appearance plan added (3.8) and step R1 renames (D12). It adds no
`SyntheticEvent`, no reader payload and no `read_intent` method for a new type.

## 5. The decision log

All decisions are of 2026-10-01, by the owner. The owner agreed with each of my
recommendations, and chose two separate tabs for O8.

- **D1. The settings of this plan** (O1). First the table of 4.3 without the
  start group, then the start group as a later part (step S10). Rejected: the
  render group only; the render group and the fault group.
- **D2. The wrapper wraps the normal edit** (O2) in an `ApplySettingOperation`
  (4.5, 4.6). Rejected: an apply operation after the write, whose inverse runs in
  the wrong order; a tab that makes the settings operation itself, which leaves
  every other view of the document with no effect.
- **D3. The macro `@settings`** (O3) declares a group (4.2). Rejected: a plain
  `@document` and a list of descriptions by hand.
- **D4. The seam `apply_settings!(target, group)`** (O4) carries a copied value
  to the editor and to the backend (4.7). Rejected: a new `Device`, which holds a
  fact of the hardware and is sealed; a backend that reads the cells of a group
  in each frame.
- **D5. TOML, `settings.toml`** (O5), as the appearance plan chose (4.9).
  Rejected: a `.pred` file.
- **D6. The environment variables are overrides for one run** (O6), which the
  settings slice reads in one place; the backend stops its read (4.9). Rejected:
  the backend keeps its read; the variables go.
- **D7. No history records a change of a setting** (O7), as the appearance plan
  decided for a theme. The inverse exists for a later step. Rejected: a history
  that holds the tab records it. **Replaced by D14.**
- **D8. Two separate tabs** (O8): the settings tab and the appearance tab. The
  settings tab opens from the toolbar, the View menu and the palette, with no
  key. Rejected: a key of its own; one tab with the appearance.
- **D9. The names** (O9) of 4.3, 4.11 and 4.12.
- **D10. The work starts after the appearance plan lands its step W1 on
  `main`** (O10), so that the seam of the build has one form. Rejected: a copy of
  the seam on a branch of its own.
- **D11. The new mechanisms of 4.12** are approved, all nine.
- **D13. A `Settings` that the wrapper makes reads the targets first** (S7,
  2026-10-01). With `settings = true`, the start step reads each group from the
  editor and its backend with the seam `read_settings!(group, target)`, the
  reverse of `apply_settings!`, then the environment, and then applies. So a
  value that a caller gave a target directly stays, and the settings show what
  acts. A `Settings` from a main builder wins. Rejected: apply only the groups
  that the environment changed, where the tab can show a value that does not
  act; callers that move their values into `settings`, where a value given to a
  target is lost with no error.
- **D14. A history that holds the tab records a change of a setting**
  (2026-10-01, replaces D7). The facts that moved the view, found before S8:
  the window history of the application holds the pane tree, so it holds the
  tab; its reader answers a `RecordUndoOperation`, a wrapping operation, and the
  settings wrapper turns the write inside it into an `ApplySettingOperation`, so
  the history keeps an inverse that writes the old value and applies it. Ctrl+Z
  in the tab takes back the last change of a setting, with no code for it. The
  window history already keeps the steps of the window, such as a moved
  splitter. Accepted with it: a file with an empty history passes Ctrl+Z to the
  window history, which can take back a setting; a change from a palette
  command, the inbox or the assistant is not recorded. The theme tab of the
  appearance plan takes the same answer. Rejected: a write into a group that the
  undo slice treats as no edit; a write that the tab marks as view state; a tab
  outside the history.
- **D15. `drag_threshold` and `message_log_capacity` stay out** (2026-10-02,
  the owner confirms the findings of S5 and S6): nothing in the application reads
  a drag threshold, and the message log is one log for the process.
- **D16. The settings tab holds its selection the normal way** (2026-10-02). The
  owner: "The selection should just work the normal way, it's not a special case
  then. If needs to go into projection introduced document, then it should do
  that." The tab wires the paths of its output with
  `set_output_path_computations!`, carries them down its widgets with
  `set_output_tree_path_computations!`, and leaves a path operation to the
  default reader of the kernel, which introduces the path into the `Settings`.
  Rejected: sharing the private code of the appearance tab as a special
  mechanism; a read-only model text. The reason I gave first, that every change
  of a setting prints the view again, was wrong: only a change of the fault
  policy prints again.
- **D12. The kernel word "setting" of a wrapper becomes "argument"** (O11).
  The value of a keyword of `build_editor` is an argument of its wrapper:
  `make_wrapper_setting` becomes `make_wrapper_argument`, `EditorParts.settings`
  becomes `EditorParts.arguments`, `make_document_projection(document;
  settings...)` becomes `make_document_projection(document; arguments...)`, and
  the argument `setting` of `wrap_editor!` becomes `argument`. "Settings" then
  means only what a person chooses. Rejected: another word for this plan, such
  as "preferences"; one word with both meanings, which breaks the vocabulary
  rule of the owner.

## 6. Open decisions

None. Section 5 holds the answers to O1 to O11.

## 7. Steps

Each step is a commit in a worktree. With the default settings, each step gives
the pixels and the test counts of the baseline of S0.

- [x] **S0. The baseline on `main`.** Done on 2026-10-01 at `a7fc28eb2`, in
  `environment/all` of the worktree, with no failure and no error:
  `test_kernel()` 4088 pass and 2 broken; `test_platform()` 84484 pass and 8
  broken; `test_sdl()` 806 pass; `test_video()` 41 pass (finding 3 of the
  appearance plan no longer fails); `test_web_backend()` 103 pass;
  `test_write_pdf()` 43 pass. The script is `/var/tmp/editor-settings/s0.jl`,
  and its log `/var/tmp/editor-settings/s0.log`.
  - **The calls that set the render flags and go through `build_editor`.**
    `record_application_video` (`example/backend/sdl/ApplicationVideo.jl`)
    passes `partial_render`, `debug_dirty` and `debug_dirty_hold` to
    `VideoBackend` and then calls `build_editor`; three takes of
    `test/backend/video/editor/ApplicationVideoTest.jl:190-192` use them. S7
    passes these values in the `settings` argument. `NativeWindowTest.jl` passes
    the flags to `SdlBackend` with no `build_editor`, so the wrapper does not
    reach it. omnet-julia makes only `SdlBackend()`, and the scripts of
    `tool/video/` pass no flag.
  - **A history holds a tool tab.** `make_application_document`
    (`source/platform/application/Application.jl:91`) puts the whole pane tree
    into one `UndoBuffer` of the window, and `_reach_tool!` opens a tool tab in
    that tree. The owner then decided that the history records a change of a
    setting (D14).
  - **The prose of R1** also covers the argument `mcp` of `run_editor!`
    (`EditorLoop.jl:142`, "Its setting is"), the comment of
    `EditorDisplay.jl:134`, and the guides `editor.md`, `mcp.md`, `screen.md`,
    `pane.md`, `tooltip.md`, `context-menu.md` and `appearance.md`.
- [x] **R1. The rename of D12**, before any new code uses the word. Done on
  2026-10-01: `test_kernel()` 4088 pass and 2 broken, `test_platform()` 84496
  pass and 8 broken, no failure and no error. The platform count is 12 above S0
  with no new test, so a count of that suite varies from run to run. The parser
  renamed the three functions; the field, the keywords, the argument of the
  three wrapper methods and of the test probe, the local names, the `mcp`
  options of `run_editor!` and the prose of seven guides changed by hand.
  Finding 18 of the appearance plan records the new names for its work.
  `make_wrapper_setting` → `make_wrapper_argument`, `EditorParts.settings` →
  `EditorParts.arguments`, the keywords of `make_document_projection`, the
  argument `setting` of `wrap_editor!` and of its methods, and the prose that
  says "the setting of a wrapper" in the docstrings, the guides
  (`editor.md`, `appearance.md`) and the appearance plan. Use
  `workspace/bin/julia-rename.jl` with `--report` first, and a second pass for
  the prose. Check omnet-julia and inet-julia again (none on 2026-10-01).
  - Tests: `test_appearance_wrapper()`, the kernel tests of the build, and the
    tests of the `tabs` wrapper give the counts of S0.
- [x] **S1. The slice `settings`** (4.2, 4.6, 4.7). Done on 2026-10-01:
  `test_settings()` with the two guards of the slices, 77 pass; the naming
  guard and the documentation guard pass. The slice is
  `source/platform/settings/`, included after `domain`, with no edge to another
  slice; `documentation/package/platform/settings/settings.md` describes it.
  What the work decided inside D3, D4 and D9:
  - **The docstring of a setting is `"Label: text"`.** The label names the row
    of the tab, and the text is its tooltip. A docstring of another form is an
    error of the macro, so every setting has both.
  - **The list of the group types is the method table** of
    `get_setting_descriptions`, as the wrappers of `build_editor` are found by
    their method tables (`compute_loaded_settings_types`). `make_settings(groups...)`
    holds the given groups and the default group of each other loaded type, so a
    `Settings` that a wrapper makes has every group without a table of names.
  - `apply_settings_to_editor!(editor, group)` applies a group to the editor and
    to its backend; `ApplySettingOperation`, the start step and the load call it.
  - `is_settings_target` compares the signature of the method that applies, so
    it needs no stored method.
  - `is_settings_group(settings, document)` answers whether a document is a
    group of a `Settings`, for the wrapper of S7.
  What the step holds: `SettingsGroup`, `@settings`,
  `SettingDescription`, `Settings` with its lookup by type, `apply_settings!`,
  `is_settings_target`, and `ApplySettingOperation` with its evaluation, its
  check, its inverse and its description.
  - Tests: the macro gives the descriptions and the name of the table. A value
    that does not fit changes nothing. The inverse writes the old value and then
    applies it. A target with no method is not a target. Two `Settings` are
    independent.
- [x] **S2. The render settings** (4.3, 4.7, 4.9). Done on 2026-10-01:
  `test_settings()` with the guards 86 pass, `test_sdl()` 813 pass,
  `test_video()` 46 pass. What the work found and decided:
  - **The environment.** A group names its variables with a method of
    `get_setting_environment_names(T)`, and `read_settings_environment!(settings,
    environment = ENV)` of the settings slice reads them, the one place of D6. A
    `Bool` takes `1`, `true`, `yes`, `on` and `0`, `false`, `no`, `off`; another
    word is a warning, where `_envflag` read it as off.
  - **The backend keeps its own read until S7**, when the wrapper reads the
    environment, so each commit of the branch keeps the variables working.
  - **A change of the mode or of the outline** sets `first_paint` of each SDL
    window, which `_render_window!` already reads: the next frame repaints and
    copies the whole window, so the last outline goes. The test checks
    `first_paint` and the damage record of the next frame; the headless probe
    is not needed.
  - **The video backend** drops its retained partial surface (`paint_state`)
    when the mode changes. It takes the hold; its supersample is fixed when the
    renderer of the take opens.
  What the step holds: `RenderSettings` in `screen`.
  The apply of the SDL backend and of the video backend. The read of the
  environment variables moves into the settings slice.
  - Tests, offscreen: a switch of `partial_render` in the middle of a run gives
    the pixels of a run that starts with it. After `debug_dirty` goes off, the
    next frame has no outline (the headless probe of the dirty region).
- [x] **S3. The supersample and the hold in the SDL backend.** Done on
  2026-10-01: `test_sdl()` 821 pass. `SdlBackend` holds `debug_dirty_hold`,
  `supersample` (from `PROJECTURED_SUPERSAMPLE` until S7) and the recent
  repaints of each window by its id; a window that closes drops its entry. The
  outline of a frame is the union of the repaints of the last hold seconds, by
  the wall clock. A window that shows no new frame keeps the last outline, as it
  does with no hold: no wake ends a hold. A new supersample factor sets `ss` of
  each open window, and `_ensure_ss_target!` makes the target again. The
  constructor takes both as keywords. What the step holds: A change of
  `supersample` makes the target of each window again. The SDL backend keeps
  each outline for `debug_dirty_hold` seconds, as the video backend does.
  - Tests: the pixels after a change equal the pixels of a window that starts
    with the new value. An outline stays for the hold and then goes.
- [x] **S4. The fault settings.** Done on 2026-10-01: `test_settings()`,
  the guards and `test_fault()`, 163 pass. Any change of the policy prints the
  view again, as `run_editor!` does, because `print!` puts the whole policy into
  the printer context. **Found for S7:** a caller of `build_editor` that passes
  `fault_policy` and no `Settings` would lose its policy to the default group
  at the start step. With `settings = true`, the start step first copies the
  policy of the editor into `FaultSettings`, so the keyword keeps its meaning.
  What the step holds: `FaultSettings` in the platform `fault` slice,
  and its apply.
  - Tests: after `is_barrier_enabled` goes off, a fault in a projection raises.
    After it goes on, the barrier catches it. The view prints again once.
- [x] **S5. The pointer settings** (4.8). Done on 2026-10-01: the kernel
  layering guard, `test_gesture_recognition()`, `test_settings()`, the platform
  guards and `test_gesture_tracking()`, 202 pass. A limit of `ClickRecognition`
  and `DwellRecognition` is a number or a cell (`Union{Int, AbstractCell}`), read
  with `_get_limit` at each input; the gesture layer now uses the cell layer.
  `make_standard_recognitions(settings::PointerSettings)` gives the cells, read
  with `getfield` from the group; the click distance limits the click and the
  next click. The window wrapper takes the group in S7.
  **Found: `drag_threshold` has no reader in the application.** Only the gallery
  examples build a `DraggingProjection`; the splitters and the tabs have no
  threshold. So the setting is left out: a setting that changes nothing that a
  person uses misleads. The owner confirms or asks for it back.
  What the step holds: The limits of the two recognitions and
  of `DraggingProjection` take a cell. `PointerSettings` and
  `make_standard_recognitions(settings)` in `gesturetracking`.
  - Tests: a change of `multi_click_max_interval` changes the recognition of the
    next double click with no new build. A recognition with plain numbers acts as
    now.
- [x] **S6. The history and the log** (4.8). Done on 2026-10-01:
  `test_settings()`, the guards, `test_undo()` and `test_gesture_tracking()`,
  258 pass. `HistorySettings` (`undo_capacity`) is in the undo slice. An
  `UndoBuffer` takes a number or a cell for its capacity; a `@document`
  constructor keeps a cell that it gets, so the buffer and the group share the
  cell, and a smaller capacity drops the oldest steps at the next step.
  `get_setting_cell(group, name)` of the settings slice gives a part the cell of
  a setting; the pointer recognitions use it too. The application gives its
  buffers the cell in S9.
  **Found: the message log is one log for the process** (`_SESSION_MESSAGE_LOG`
  of `MessageLogDocument.jl`), so its capacity can not be a setting of one
  editor: two editors would write one capacity (PAR-PER-EDITOR-STATE). So
  `message_log_capacity` and `LogSettings` are left out. The owner confirms or
  asks for a log for each editor first.
  What the step holds: The capacity of `UndoBuffer` and of
  `MessageLog` takes a cell. `HistorySettings` and `LogSettings`.
  - Tests: a smaller capacity drops the oldest entries at the next push.
- [x] **S7. The slice `settingsmanaging`: the wrapper** (4.1, 4.5). Done on
  2026-10-01: `test_settings_wrapper()` 34, `test_kernel()` 4094 and 2 broken,
  `test_platform()` 84605 and 8 broken, `test_sdl()` 823, `test_video()` 47,
  `test_web_backend()` 103, and `test_application()`,
  `test_referenced_document_editor()` and `test_mcp_server()` 453 and 2 broken;
  no failure and no error. What the work decided and found:
  - **D13**: `Settings.is_read_from_targets`, set for the `Settings` of `true`;
    `read_settings!` for `SdlBackend`, `VideoBackend` and the fault policy of an
    `Editor`; `read_settings_from_editor!`. So `record_application_video` and
    `build_editor(...; fault_policy)` need no change.
  - The wrapper is `:screen => 10`, outside the appearance wrapper, and has the
    form of `AppearanceManagingProjection`; it reads the `Settings` from its
    input. It wraps the self-contained form of a write only: a reference from
    the root can not step into `Settings.groups`, a dictionary by type, so no
    view makes the other form.
  - The commands are in the gesture table of the `SettingsDocument`, with no
    key; "Open settings" comes with the tab in S8.
  - The `window` wrapper takes the `PointerSettings` from `EditorParts.arguments`.
  - `SdlBackend` reads no environment variable: its keywords default to off,
    off, 0 and 2, and the settings bring the variables. An editor made with
    `make_editor`, with no wrapper, no longer reads them.
  - The tests that check the root after `build_editor` turn the wrapper off:
    `AppearanceWrapperTest`, `WindowWrapperTest`, and `BuildEditorTest`, which
    names the three wrappers of the platform in one named tuple. The selection
    path of `ApplicationTest` has one more `content` step.
  - The guide `documentation/package/platform/settingsmanaging/settingsmanaging.md`.
  What the step holds:
  `SettingsDocument`, `SettingsManagingProjection`, the `settings` wrapper with
  its start step, its method of the seam of the build, and the two commands of
  the palette.
  - Tests: a write into a group becomes an `ApplySettingOperation`, also inside a
    `CompoundOperation`. A write into another document passes unchanged. An
    ordinary edit applies nothing: type, move the caret, open a tab. Two editors
    in one process are independent. `build_editor` with `settings = true` does
    not read the file. F1 and the palette list the two commands.
  - The calls that S0 found pass their values in `settings`, or pass
    `settings = false`. omnet-julia follows; check `Pkg.precompile` there.
- [x] **S8. The tab** (4.4). Done on 2026-10-01: `test_settings_tab()`, the
  wrapper and settings tests and the guards 169; `test_shell()`,
  `test_widget_icon()` and `test_application()` 1002 and 2 broken; no failure
  and no error. What the work decided and found:
  - `SettingsToWidget` in the slice `settingsmanaging`, which moved after
    `natural` so that it registers its row with the natural renderer:
    `Settings => ChainingProjection(SettingsToWidget(), VerticalLayoutToGraphicsCanvas())`.
  - A `Bool` is a `WidgetSwitch` and a number with a range a `WidgetSpinBox`;
    each value, `enabled` state and note is a computed cell, so the view follows
    a change from any path and the unused types that the start step finds after
    the first print. A `Symbol` or a `String` shows as text: a `WidgetSelect`
    writes from its popup window, which does not pass the reader of the tab, so
    the choice waits for S10, the first step with such a setting.
  - **Reset and "Reset all" are normal edits**: the write of the default, and a
    `CompoundOperation` of them, from a per-instance gesture of the button. So
    `ResetSettingsOperation` of 4.6 is not needed.
  - **`is_settings_group_applied(T)`**, declared by the slice of the group (render
    and fault), so that `is_settings_group_used` does not depend on which packages
    with targets are loaded. `Settings.unused_types` keeps the result of the
    start step.
  - The toolbar button and the View menu item open the tab with
    `find_editor_settings(editor)`. The gear glyph `:settings` (0xe154, checked
    in `asset/font/lucide.ttf`) joined the icon table.
  - **The palette command came on 2026-10-02, as "Show the settings".** The
    reason given here before, that only the shell can open a tool tab, was
    wrong. `show_document!` of the screen slice opens a tab or focuses it, and
    the appearance tab already has "Show the appearance" (Ctrl+,). The command
    is a rule with no key in `@gestures SettingsDocument`, so the palette lists
    it as it lists the two toggles. `get_document_title(::Settings) = "Settings"`
    gives the same tab title on the toolbar path and on the palette path.
  - D14 holds: a test puts an `UndoBuffer` around the tab, and Ctrl+Z and Ctrl+Y
    take a change back and put it back, with the apply.
  What the step holds: `SettingsToWidget`, the toolbar item, the View menu
  item and the command "Open settings".
  - Tests, with a press at the drawn pixels: the switch of partial render sets
    the field of the backend at the next frame. A spin box steps in its range. A
    group with no target is disabled. A row of the kind "start" shows its text.
    The pixels, offscreen.
- [x] **S9. Save and load** (4.9). Done on 2026-10-01: the settings, tab and
  wrapper tests, the guards and `test_application()` 535 and 2 broken;
  `test_video()` 47. What the work decided and found:
  - **`TOML` joined the dependencies of `ProjecturedPlatform`**; the manifest of
    `environment/all` changed by one line. The file code is in the settings slice
    (`SettingsFile.jl`): the folder, the read, the write and the two operations,
    so the appearance plan (W6) can use the folder and the form.
  - `LoadSettingsOperation` evaluates an `ApplySettingOperation` for each value
    that differs; its inverse is a `CompoundOperation` that writes every setting
    back. `SaveSettingsOperation` has the inverse `DoNothingOperation`, which a
    history keeps no step for.
  - `Settings.file` names the file of the Save and Load buttons; it is empty for
    the `Settings` of `true`, so a test never writes the file of the person.
  - `make_application_settings(file; fault_policy)` fills the settings of the
    application; `run_application` takes `settings_file`, and its `fault_policy`
    is `nothing` unless given. **The fault policy of the command line is the
    whole policy for the run**, so `--strict-fault-policy` also turns the console
    and the sound of a fault on for that run, whatever the file says.
  - The histories of the window, of each file tab and of each file that the
    explorer opens take the cell of `undo_capacity` (`make_history_wrap`).
  - `record_application_video` makes one `Settings` for the window and the
    editor, with `is_read_from_targets` set, so its backend values stay.
  - Observed, not changed: `run_application` builds its projection with
    `appearance` but does not pass it to `build_editor`, so the `appearance`
    wrapper makes an `Appearance` of its own. This is for the appearance plan.
  What the step holds: The file, the order of the sources,
  `--strict-fault-policy` as a source, the three operations, and the fill in
  `run_application`.
  - Tests: Save writes the file. Load applies its values. A key that is missing
    takes its default. A file with a key that is not known loads. An environment
    variable wins over the file.
- [x] **M1. `main` merged into the branch** (2026-10-02, `main` at `cd427b547`, 42
  commits: the release tests, the split test packages, and W3, W4, W5 and W6 of
  the appearance plan). On the merged tree: `test_kernel()` 4095 and 2 broken,
  `test_platform()` 84679 and 8 broken, `test_sdl()` 826, `test_video()` 45,
  `test_web()` 116, `test_pdf()` 50, `test_mcp()` 434, `test_application()` 340
  and 2 broken, `test_referenced_document_editor()` 101; no failure and no
  error. What the merge decided:
  - **The settings wrapper sits inside the appearance wrapper** (`:screen =>
    -10`), so the `AppearanceDocument` stays the root, as the tests and
    `find_editor_appearance` of the appearance plan expect; the order of the two
    changes neither effect. `find_editor_settings` walks the `content` chain.
  - `get_appearance_file()` takes its folder from `get_configuration_folder()` of
    the settings slice, the one place of the folder, as both plans agreed; an
    empty `XDG_CONFIG_HOME` now counts as unset there too. The style slice uses
    the settings slice.
  - The `shell` wrapper of `main` takes `argument` and reads
    `EditorParts.arguments` (D12).
  - The toolbar, the View menu and their tests hold both Appearance and
    Settings; the settings tab is in the toolbar of a window that records
    nothing, because it is never empty.
- [x] **M2. `main` merged again** (2026-10-02, `main` at `384dd472f`, the drag
  work). `test_platform()` 84694 and 8 broken, `test_application()` 341 and 2
  broken, and the SDL, video, web, PDF, MCP and referenced-editor suites pass.
  `test_kernel()` has one failure, "a gesture reaches the child its route names"
  (`RoutedChangeTest.jl:199`): `main` alone at `8d1edf0ce` has it too (4088
  pass, 1 failure), so it is not from this branch. The drag work has no
  threshold, so `drag_threshold` still has no reader.
- [x] **M3. `main` merged a third time** (2026-10-02, `main` at `fdc919a04`: the
  features of a window became wrappers of `build_editor`). `test_kernel()` 4101
  and 2 broken with the one failure of `main` (`RoutedChangeTest.jl:199`);
  `test_platform()` 84733 and 8 broken with no failure after the fixes below;
  `test_shell()` 337; `test_sdl()` 826, `test_video()` 45, `test_web()` 116,
  `test_pdf()` 50, `test_mcp()` 434, `test_application()` 341 and 2 broken,
  `test_referenced_document_editor()` 101. What the merge decided:
  - The nine new wrappers of `main` take `argument`, and `make_editor_parts`
    uses the names of D12.
  - The history of the window is now the `undo` wrapper: it takes the cell of
    `undo_capacity` from the `Settings` of the `settings` wrapper.
    `make_application_document` gives the histories of the file tabs the cell.
  - `run_application` passes its `Settings` to `build_editor`, and the settings
    carry the fault policy of the command line. `make_application_window` turns
    the settings wrapper off, as it turns off the appearance wrapper, so the
    caller's `build_editor` adds it.
  - The tests that check the root, or press a key straight at a projection,
    turn off the `settings` wrapper and the new `focus_cycling` wrapper; the
    lists of the toolbar hold Settings.
- [x] **S10. The start settings**, a later part after S0 to S9 (D1). Done on
  2026-10-02: the settings tests, the tab tests, `test_appearance_tab()`, the
  guards and `test_application()` 575 and 2 broken; `test_kernel()` with only the
  failure of `main`, `test_platform()` 84746 and 8 broken. What the work did:
  - **The selection of the tab works the normal way (D16)**, which also closes a
    gap of S8: Tab and the arrows reach each control, Space and Return change a
    switch, and a text draws its caret. `set_output_tree_path_computations!`
    joined the kernel beside `set_output_path_computations!`, and the appearance
    tab uses it in place of its private walk.
  - A `Symbol` with its choices is a `WidgetRadioGroup`, which writes its index in
    place; a `String` is a `WidgetText`, whose edit becomes the write of the whole
    text and a caret after the new characters.
  - `StartSettings` of the application slice: `assistant`, `model`, `context` and
    `mcp`, with `is_settings_group_read_at_start`, so its card says that its
    settings take effect at the next start.
  - The command line leaves an option that it does not give as `nothing`, so the
    start settings decide it; `make_application_settings` writes the given values
    last. The help text of the binary says so.
  `StartSettings` in `application`, read by `run_application`.
  - Tests: the file, the environment and the command line in their order.
- [x] **S11. The guides.** Done: `settings.md` and `settingsmanaging.md` (new),
  and the passages in `sdl.md`, `video.md`, `application.md`, `mouse-target.md`,
  `debugging-guide.md`, `keyboard-and-mouse-guide.md` and `testing-guide.md`.
  The plan asked: A new design document
  `documentation/package/platform/settings/`. The changes in the guides of the
  SDL backend, the video backend, the screen, the fault slice and the undo
  slice. The environment variables in `debugging-guide.md`. The settings
  wrapper in `testing-guide.md`. The two commands in
  `keyboard-and-mouse-guide.md`.

## 8. Risks

- A `ReplaceReferencedValueOperation` into a group that does not pass the reader
  chain, such as a direct post to the inbox, writes the cell and applies nothing.
  The tab then shows the new value, and the backend keeps the old one. The guide
  of the assistant must say: post an `ApplySettingOperation`.
- A test or a take that passes `SdlBackend(partial_render = true)` or
  `VideoBackend(partial_render = true)` to `build_editor` gets the `settings`
  wrapper, and its start step writes the default over the value. Step S0 finds
  these calls, and S7 changes them.
- A new supersample makes a new target for each window. That costs memory and one
  full repaint.
- A limit that is a cell costs one more read for each input. This is small.
- omnet-julia builds its editors with `build_editor`, so the wrapper is on there
  too.
- The `settings` wrapper changes the root of every editor, as the `appearance`
  wrapper does. A test that checks the root document after `build_editor`, or
  the depth of a selection path, must turn it off with `settings = false`
  (finding 16 of the appearance plan).
- No 🔒 file changes. `FaultPolicy.jl` and the gesture layer are ⬜, and
  `ClickRecognition.jl` and `DwellRecognition.jl` are not in the inventory. Read
  `SEALING.md` again before each edit.

## 9. Not in this plan

- A setting for each window, or for each document.
- Settings for a project, in a folder of the project.
- The tunings of the frame loop and of the caches (3.7).
- The key bindings as settings (`plan/pending/key-chords-from-bindings.md`).
- The capacity of the faults and of the frame measurements, which are in sealed
  files.
- A minimum level of the message log, and the interval of the statistics.
- A start or a stop of the MCP server while the editor runs.
