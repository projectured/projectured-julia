# Packages compose by seams

Status: design, 2026-09-30. Work in the worktree of the branch `data-frame`
(`../projectured-julia-data-frame`), as D13.5 (a) of
[view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md) says.
omnet-julia and inet-julia follow in worktrees of their own (step 12).

## 1. The request

The owner, 2026-09-30:

- "Remove the ProjecturedSdl dependency, backends should register themselves
  and automatically used if there's only one and none was given. I would also
  remove the wrapper package dependencies if possible too. And they would also
  register and map to a keyword argument in the run editor function
  somewhere. The point is to have as few dependencies as possible."
- "The data frames package should not depend on panes I think, the whole
  display stuff belongs to somewhere else. [...] I want composition, the user
  loads packages and gets more features which may combine by default or can
  be combined. Data frames can be displayed with or without panes. The data
  frames package should depend on the minimal number of packages for it to be
  useful."
- "For Q1, can we do with seams only? What would be the shape?", then "Sounds
  good", "I agree with your recommendations" and "Good".

## 2. Decisions (the owner, 2026-09-30)

- **C1. Seams only.** No registry table, no `__init__` registration and no
  package extension. A seam is a generic function that a low package
  declares. The package that owns a type adds a method for it. A method that
  a package adds is in the precompile cache of that package.
- **C2. D13 with seams.** The seams of the backends and of the wrappers, and
  the run function, are in the kernel (13.1 b). A keyword maps to a wrapper
  function, a layer for its order, and the keywords that it excludes (13.2 a).
  Two candidate backends and no backend named is an error that names both
  (13.3 a). The run of the editor beside the REPL is a keyword of the run
  function (13.4 a). Every caller moves in this plan (13.5 a).
- **C3. A backend says what it draws (Q5 a).** It draws windows or text. The
  run function counts only the backends that can draw its output. So the
  umbrella, which always loads `ProjecturedConsole`, plus SDL, runs with no
  backend named.
- **C4. Three layers.** The data frame package is a document and its
  projection, and nothing more. A new generic package shows any value from the
  REPL in an editor. Seams join the two, and join the display with the panes.
- **C5. Tabs combine by default (Q3).** When the pane package is loaded, the
  display shows each value as a tab of one window. A keyword turns this off.
  §4.3 says at which level "by default" applies. That point waits for the
  owner (P1).
- **C6. No pause (Q4).** The editor loop runs on its own thread during a REPL
  input and takes input as usual. After each input, the display asks each
  shown document to refresh. A key does the same for a change that a
  background task makes. The docstring of the display states the rare race.
- **C7. The natural tables stay for now (open point, option a).** Only
  `make_graphics_projection` comes now. The natural renderer asks it before its
  tables. A later plan moves the other eight natural register functions to
  seams.
- **C8. The names.** A seam that creates something is `make_`. It has no
  method in the package that declares it, so a `make_` call always creates.
  A caller that is not sure asks `hasmethod` first.
- **C9. No inspector wrapper.** Another branch removes the inspector.

## 3. What exists now

The inventory of 2026-09-30 found four ways to wrap an editor:

- **The gallery.** `make_example_editor` in
  [Gallery.jl](../../example/projectured/Gallery.jl) has 14 keywords:
  - five exclusive keywords, where the first true flag wins with no error;
  - eight layered keywords, applied to each window;
  - `tooltip` and the gesture log on the screen;
  - a selection lift (`content_unwrap`) for the wrappers that wrap the
    document.

  Six of the helpers are in `example/`, not in `source/`: scrolling,
  introspection, shell, caching, the text wrappers and the command palette.
- **The shell.** `make_window_wrap` in
  [WindowWrap.jl](../../source/shell/WindowWrap.jl) is a fold of nine layers.
  `run_with_window_tools` adds feeds and a start step.
- **omnet-julia.** `WINDOW_WRAPPERS` in `source/build/Program.jl` has two
  entries.
- **The screen.** `make_editor(document, projection, title; backend, ...)` in
  [WindowScene.jl](../../source/screen/WindowScene.jl) puts the document in
  one window. It takes `opened_window_projections` and `screen_wrap`.

A backend is chosen in five ways:

- `default_backend()` of `ProjecturedExample` finds the subtypes of `Backend`
  and uses a fixed order of preference.
- The builder has the table `PROJECTURED_BACKENDS` and passes
  `run_application_command(ARGS; backends)`.
- The data frame display uses `something(backend, SdlBackend())`.
- omnet's `Program.jl` writes the constructor into the program.
- Many scripts use `backend = SdlBackend()`.

The backends:

| Backend | Package | Draws | Note |
|---|---|---|---|
| `SdlBackend` | ProjecturedSdl | windows | the only package that defines `render_canvas` |
| `WebBackend` | ProjecturedWeb | windows, in a browser | |
| `ConsoleBackend` | ProjecturedConsole | a `TextBlock` only | always loaded by the umbrella |
| `VideoBackend` | ProjecturedVideo | frames of a timeline | depends on ProjecturedSdl, needs a timeline |
| test doubles | tests, `ProjecturedKernelExample` | anything | |

Two call sites in inet-julia do not compile against the API now:
- `Editor(shell, renderer)` in `example/model/queuing/run.jl`;
- `on_start` and `ProjecturedSdl.sdl_display_size` in
  `example/watch/mac_fsm_sdl.jl` and `package/InetExample`.

## 4. The design

### 4.1 The seams

| Seam | Declared in | Methods come from |
|---|---|---|
| `get_backend_name(::Type{<:Backend}) -> Symbol` | kernel, editor layer | each backend package: `:sdl`, `:web`, `:console` |
| `get_backend_output(::Type{<:Backend}) -> Symbol` | kernel, editor layer | SDL and Web: `:windows`. Console: `:text`. Video and the test doubles: none, so they are not candidates. |
| `wrap_editor(::Val{k}, layer::Symbol, setting, parts::EditorParts) -> EditorParts` | kernel, editor layer | each wrapper package |
| `get_wrapper_layers(::Val{k})` | kernel, editor layer | each wrapper package |
| `get_excluded_wrappers(::Val{k})` | kernel, editor layer, with a method for `Val` that gives `()` | the wrappers that exclude another |
| `show_document!(editor, content, document; title)` | Screen, with the method for `Any` that opens a new window | Pane: opens a tab in a `PaneTree`, or focuses the tab that shows `document` |
| `make_value_document(value)` | Widget | DataFrames: a `DataFrameView` |
| `make_graphics_projection(document; measure)` | Widget | DataFrames, for `DataFrameView`. Reflection, for `AReflectedNode`. |
| `refresh_document!(document)` | Widget | DataFrames, for `DataFrameView` (phase 3 of the data frame plan) |

The backend files of the kernel are 🔒 in [SEALING.md](../../SEALING.md). So
the backend seams go in the editor layer, which is not sealed. They do not go
beside `Backend`. Each new kernel file goes into the inventory of SEALING.md
as ⬜.

**The run function finds what is loaded in two ways.**
- A keyword `k` is known when `hasmethod(wrap_editor, Tuple{Val{k}, Symbol,
  Any, EditorParts})` is true. A keyword that is not known is an error that
  names the known keywords.
- The candidate backends are the types in the methods of
  `get_backend_output` that give the output of the run. `methods` is part of
  Base, and it works after precompile and in a program that `create_app`
  makes. A trimmed program must name its backend.

**Two packages can define one keyword.** If neither package loads the other,
precompile does not see the clash. At load time the later method replaces the
first one. A static check in the style of the naming guard finds this.

### 4.2 The run function

These are in the kernel, editor layer:

```julia
make_editor(document, projection; backend = nothing, defaults = false,
            feeds = Feed[], fault_policy = FaultPolicy(), wrappers...) -> Editor
run_editor!(document, projection; wait = true, mcp..., same keywords) -> Editor
run_editor!(editor::Editor; mcp...)
```

The steps of `make_editor`:

1. Choose the backend. If `backend` is given, use it. If not, use the one
   candidate that draws windows. If there is no candidate or more than one,
   raise an error that names the candidates and the backend packages.
2. Collect the keywords that are on. A keyword is on when its value is not
   `false` and not `nothing`. With `defaults = true`, a wrapper that says it is
   on by default is also on (P1). Two keywords that exclude each other are an
   error that names both.
3. Put the wrappers in order, layer by layer:
   - `:document` applies to each document, and also to a document that
     `show_document!` opens later;
   - `:container` holds the documents, for example the tabs;
   - `:window` is the window of the screen package. It is on by default when
     the backend draws windows and the document is not a `ScreenDocument`
     already;
   - `:screen` applies once, to the root.

   A number orders the wrappers inside a layer. One keyword can act in more
   than one layer. For example, the gesture log draws its overlay on each
   document and records on the root.
4. Call `wrap_editor` for each wrapper, from the inside out.
5. Make the editor with the kernel's constructor and run the start steps that
   the wrappers gave.

`EditorParts` holds what a wrapper can change:
- `document`;
- `projection`;
- `backend`, which is read-only;
- `feeds`;
- `start_steps`, the functions `editor -> nothing` that run after the editor
  exists, for example `attach_fault_target!` of the fault log;
- `opened_projections`, the projections for the documents that a wrapper opens
  later in a window of their own, for example the gesture map of F1.

The editor keeps the wrappers that are on and their settings, so
`show_document!` can apply the `:document` layer to a new document.

**The value of a keyword is its setting.** `true` means "on, with the
defaults". A `NamedTuple` gives settings, for example
`window = (; title = "Data frames", width = 1000, height = 600)`.

**A wrapper that wraps the document lifts the selection itself.** The inner
selection goes into the new root, with the step of the wrapper's field in
front. This replaces `content_unwrap` of the gallery. `make_window_scene`
does it this way now.

**`wait = false`** runs the loop on a thread of its own and returns the editor
at once (D13.4). If the process has one thread, the loop runs in an `@async`
task. The code is `_find_editor_thread` and `_spawn_pinned` of
`DataFrameDisplay.jl`, and it moves into the kernel. The loop keeps the world
of its start, so a call that the REPL posts to it goes through
`Base.invokelatest`.

**These methods go:**
- `make_editor(backend, projection, document)` and
  `run_editor!(backend, projection, document)` of the kernel. Their callers
  are tests, which pass `backend =`.
- `make_editor(document, projection, title)` and `run_window_editor` of the
  screen package. The title and the size become the setting of `window`.

### 4.3 The display package

The new package is `ProjecturedDisplay`, with the leaves `ProjecturedDisplayTest`
and `ProjecturedDisplayExample` (P5). It depends on the kernel, Screen,
Widget, Reflection, Natural, Text and the stdlib `REPL`. It does not depend on
Pane, DataFrames or a backend.

- `display_in_editor(value; title, backend = nothing) -> document` shows
  `value`:
  - The first call starts the editor with `run_editor!(...; wait = false,
    defaults = true)`.
  - A later call uses `show_document!`. A value that is shown already gets
    focus again.
  - The document is `make_value_document(value)` if that method exists. If
    not, it is the reflected tree of `run_value_viewer`, with its
    `ReflectionFeed`.
- `EditorDisplay <: AbstractDisplay` is the struct that the data frame
  package calls `ProjecturedDisplay` now. The package pushes no display (D9),
  so `display(EditorDisplay(), value)` is the explicit call.
- After each REPL input, a hook calls `refresh_document!` on the editor task
  for each shown document that has a method.
- `run_value_viewer` moves here from `ProjecturedExample`.

The projection of a shown document is `DocumentToGraphics(; measure)`, a new
projection in Widget:
- a widget or a layout draws through `WidgetToGraphics` and
  `LayoutToGraphics`;
- any other document draws through the projection that
  `make_graphics_projection` makes for its type. The projection is made once
  for each type.

The natural renderer asks the same seam before its tables (C7).

**P1: the level of "by default".** The test environment loads every package,
and so does a program that loads the pane package for another reason. If a
wrapper were on in every editor once its package is loaded, the tabs would
wrap the document of every test and of every such program. My
recommendation: a seam `is_wrapper_default(::Val{k})`, which the run function
reads only when the caller passes `defaults = true`. The display and the
gallery pass it, and a program or a test does not. The pane package says
`true` for `tabs`. The window does not use this seam: it follows the backend
(§4.2, step 3).

### 4.4 The data frame package after the move

- It depends on DataFrames, Kernel, Collection, Projection, Layout, Widget,
  Style and Primitive.
- It does not depend on Sdl, Screen, Pane or Natural.
- `DataFrameDisplay.jl` goes: the display moves to `ProjecturedDisplay`, and
  the tab code moves to the pane method of `show_document!`.
- It adds three methods:
  - `make_value_document(frame::AbstractDataFrame) = DataFrameView(frame)`;
  - `make_graphics_projection(::DataFrameView; measure)`;
  - later, `refresh_document!(::DataFrameView)` (phase 3).
- The `__init__` that registers the natural row goes.

`make_value_document(::AbstractDataFrame)` adds a method of a foreign
function for a foreign type. This is type piracy in the strict sense, and a
package extension does the same. ProjecturedDataFrames is the only glue for
that pair.

### 4.5 The wrappers and the packages that own them

| Keyword | Package | Layer | Note |
|---|---|---|---|
| `window` | Screen | `:window` | on for a backend that draws windows |
| `tabs` | Pane | `:container` | on by default with `defaults = true` (P1) |
| `dragging` | Dragging | `:document` | |
| `clipboard`, `clipboard_collection` | Clipboard | `:document` | excludes `tooltip` |
| `hover` | Widget | `:document` | |
| `caching` | Graphics | `:document` | takes `render_canvas` of the backend |
| `gesture_help`, `command_palette` | GestureHelp | `:document` | the shared help state is set up in a start step |
| `gesture_log` | GestureLog | `:document` and `:screen` | overlay and recording |
| `fault_tolerant` | Fault | `:document` | a start step attaches the log |
| `tooltip` | Tooltip | `:document` | opens sibling windows |
| `scrolling`, `introspection`, `shell`, `text_highlighting`, `text_filtering` | ProjecturedExample | `:document` | the five exclusive keywords of the gallery become exclusions |
| the layers of `make_window_wrap` | Shell and the packages above | | step 9 |

## 5. Points that wait for the owner

- **P1.** The level of "by default", §4.3. My recommendation: the
  `defaults = true` keyword, and `is_wrapper_default`.
- **P2.** The shape of a wrapper: `wrap_editor(::Val{k}, layer, setting,
  parts)`, `EditorParts`, and the four named layers, as in §4.2. My
  recommendation: as written.
- **P3.** The run functions `make_editor(document, projection; ...)` and
  `run_editor!(document, projection; ...)` replace the backend-first methods of
  the kernel and the title methods of Screen, §4.2. My recommendation: as
  written.
- **P4.** `make_value_document`, `make_graphics_projection`,
  `refresh_document!` and `DocumentToGraphics` go in Widget. Widget is the
  lowest package that both the data frame package and the display load. My
  recommendation: Widget.
- **P5.** The name `ProjecturedDisplay` for the package, and `EditorDisplay`
  for the `AbstractDisplay`. My recommendation: these names.
- **P6.** omnet-julia and inet-julia. My recommendation: move the callers in
  omnet-julia in a worktree of its own, and test that worktree against this
  branch in a scratch environment. Move the callers in inet-julia that
  compile now. List the two broken ones for the owner, and do not fix them.

## 6. Steps

Each step ends with its narrowest test and a commit.

- [ ] **1. The kernel.** Add `EditorParts`, the wrapper seams, the backend
  seams, the choice of the backend, the new `make_editor` and `run_editor!`,
  and `wait = false`. Remove the backend-first methods and move their tests.
  Test with doubles in `ProjecturedKernelTest`.
- [ ] **2. The backends declare themselves.** SDL, Web and Console. Test the
  choice: one candidate, two, none, and a `:text` backend beside a `:windows`
  one.
- [ ] **3. The window wrapper.** Move `make_window_scene` into the method of
  `window`. Remove `make_editor(document, projection, title)` and
  `run_window_editor`, and move their callers: Application,
  ApplicationVideo, the tests, and the data frame display for now.
- [ ] **4. The widget seams.** Add `make_value_document`,
  `make_graphics_projection`, `refresh_document!` and `DocumentToGraphics`.
  The natural renderer asks `make_graphics_projection` before its tables.
  Reflection adds its method.
- [ ] **5. The tabs and `show_document!`.** The screen method opens a
  window. The pane method opens or focuses a tab. Add the `tabs` wrapper.
- [ ] **6. `ProjecturedDisplay`.** Add `display_in_editor`, `EditorDisplay`,
  the REPL hook that refreshes, and `run_value_viewer`. Add the package to
  `environment/all`, to the table of package-rules.md, and to the naming
  guard. Run `test_package_graph()`.
- [ ] **7. The data frame package.** Remove the dependencies of §4.4, add
  its methods, and move `DataFrameDisplayTest.jl` to the display test
  package. Run `test_data_frame_view()` and the layering guard.
- [ ] **8. The gallery.** Each keyword of `make_example_editor` becomes a
  wrapper in the package of §4.5. `run_example` keeps its signature. The
  selection lift moves into the wrappers.
- [ ] **9. The shell.** `make_window_wrap` and `run_with_window_tools` become
  wrappers. Move `make_application_window`.
- [ ] **10. The builder.** The generated `main` loads the backend packages
  and calls `run_application_command(ARGS)`. `--backend=NAME` matches
  `get_backend_name`. Remove `PROJECTURED_BACKENDS` and `default_backend()`.
- [ ] **11. The other callers here.** FeedExamples, FaultExamples,
  FileEditor, LiveExamples, `run_console_example` and
  `source/repl/record/driver.jl`. Record the precompile statements again,
  because they name `_build_window_scene` and `_multi_window_projection`.
- [ ] **12. omnet-julia and inet-julia** (P6).
- [ ] **13. The documents.** Update the kernel editor, screen, pane, widget
  and natural documents, add a document for the new package, and update
  engineer-tour.md where it names the old run functions.
- [ ] **14. The sweep.** Run the suites of the packages that changed, and
  compare them with main. Build omnet-julia against the branch.

## 7. Risks

- **A change of behavior in the gallery.** Two exclusive keywords are an
  error now. The inventory found no caller that passes two of them.
- **The order of the wrappers.** A different order changes what a person
  sees. The layer numbers of §4.5 keep the order of the gallery. Step 8
  compares the pixels of three gallery examples before and after.
- **The recorded precompile statements** name functions that go. A statement
  that fails is skipped with no error, so the start of a session gets slower
  with no message. Step 11 records them again.
- **A method that a package adds after the loop starts** is too new for the
  loop, as a function that the REPL defines is now. This is not a new
  problem, and `invokelatest` covers the calls that the display posts.
