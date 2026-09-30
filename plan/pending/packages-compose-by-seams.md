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
  A wrapper that is on by default is on in every editor that `build_editor`
  makes (C10).
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
- **C10. One function wraps, one does not (P1).** The owner: "For P1, the
  defaults keyword is weird. Why don't the tests use the function which does
  not wrap?" So there is no `defaults` keyword:
  - `make_editor` applies no wrapper and chooses no backend. Tests, and a
    program that wants exact control, call it.
  - `build_editor` chooses the backend and applies the wrappers. A wrapper
    that is on by default is always on there. A caller turns it off with its
    keyword, for example `tabs = false`.
  - A container wrapper does nothing when the document is its container
    already: the tabs do not wrap a `PaneTree`, and the window does not wrap a
    `ScreenDocument`.
- **C11. The shape of a wrapper (P2)** is as §4.2 says (the owner: "I agree
  with your recommendations for P2-P3").
- **C12. The functions (P3 with C10)** are as §4.2 says. The name is
  `build_editor`, because the naming rules say that `build_` assembles a
  structure from parts, and the wrappers are the parts. A second name also
  keeps two calls that look alike from giving one editor with tabs and one
  without.
- **C13. The order of the arguments.** The owner: "Concerning the order if
  we ignore backward compatibility, how would you do it?", then "I agree".
  - The document comes first, then the projection. Every other input is a
    keyword, the backend too. This applies to the raw constructor `Editor`
    and to `play_live!` as well. I read "I agree" as agreement to the change
    of `Editor`, which I had put as optional.
  - The reasons: the document is the subject; the projection can be optional,
    and Julia puts an optional positional argument last; the backend is a
    setting, as `devices` and `feeds` are; all variants get one positional
    shape; most callers use this order now.
  - Three exceptions stay. The projection API keeps the projection first,
    because there it is the receiver of the dispatch. A function that changes
    a value takes that value first (`run_editor!(editor)`,
    `show_document!(editor, ...)`). A seam takes its dispatch key first
    (`wrap_editor(::Val{k}, ...)`).
- **C14. The default projection comes from Natural (P7).** The owner: "Yes",
  to the proposal that drops a new `DocumentToGraphics` in Widget, because
  it would repeat a part of `NaturalToGraphics`. So:
  - The kernel declares `make_document_projection(document)` with no method.
    Natural adds the one method, for `Document`, which makes
    `NaturalToGraphics`. This is a method of a foreign function for a foreign
    type in the strict sense, but both packages are in this repository, and
    only Natural adds it.
  - When Natural is loaded, `run_editor!(document)` works with no projection
    named. When it is not loaded, the caller names the projection, for
    example `make_data_frame_view_projection()`.
  - `make_graphics_projection` answers a different question: it gives the
    projection of the nodes of one type, and the natural renderer asks it
    for each type that it meets.

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
| `is_wrapper_default(::Val{k})` | kernel, editor layer, with a method for `Val` that gives `false` | Screen for `window`, Pane for `tabs` |
| `show_document!(editor, content, document; title)` | Screen, with the method for `Any` that opens a new window | Pane: opens a tab in a `PaneTree`, or focuses the tab that shows `document` |
| `make_document_projection(document)` | kernel, editor layer | Natural: one method for `Document`, which makes `NaturalToGraphics` (C14) |
| `make_value_document(value)` | Widget | DataFrames: a `DataFrameView` |
| `make_graphics_projection(::Type{T}; measure)` | Widget | DataFrames, for `DataFrameView` (step 4 found that the seam is keyed by type) |
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
make_editor(document, projection; backend, devices, feeds, fault_policy) -> Editor
build_editor(document, projection = nothing; backend = nothing, devices, feeds,
             fault_policy, wrappers...) -> Editor
run_editor!(document, projection = nothing; wait = true, mcp..., the keywords
            of build_editor) -> Editor
run_editor!(editor::Editor; wait = true, mcp...) -> Editor
Editor(document, projection; backend, devices, clock, tools, faults, fault_policy)
```

`make_editor` applies no wrapper and chooses no backend, so `backend` is a
required keyword. It initializes the backend, opens the native windows and
prints once, as the kernel's `make_editor` does now. `build_editor` does the
steps below and then calls `make_editor`. `run_editor!(document, ...)` is
`build_editor` and then the loop. A projection of `nothing` is
`make_document_projection(document)` (C14). If no package added a method,
the error says to name a projection or to load `ProjecturedNatural`.

The steps of `build_editor`:

1. Choose the backend. If `backend` is given, use it. If not, use the one
   candidate that draws windows. If there is no candidate or more than one,
   raise an error that names the candidates and the backend packages.
2. Collect the keywords that are on. A keyword is on when its value is not
   `false` and not `nothing`. A wrapper whose `is_wrapper_default` is `true`
   is on unless its keyword is `false` (C10). Two keywords that exclude each
   other are an error that names both.
3. Put the wrappers in order, layer by layer:
   - `:document` applies to each document, and also to a document that
     `show_document!` opens later;
   - `:container` holds the documents, for example the tabs;
   - `:window` is the window of the screen package. It is on by default, and
     it does nothing when the backend does not draw windows or when the
     document is a `ScreenDocument` already;
   - `:screen` applies once, to the root.

   A number orders the wrappers inside a layer. One keyword can act in more
   than one layer. For example, the gesture log draws its overlay on each
   document and records on the root.
4. Call `wrap_editor` for each wrapper, from the inside out.
5. Make the editor with `make_editor` and run the start steps that the
   wrappers gave.

`EditorParts` holds what a wrapper can change:
- `document`;
- `projection`;
- `backend`, which is read-only;
- `feeds`;
- `start_steps`, the functions `editor -> nothing` that run after the editor
  exists, for example `attach_fault_target!` of the fault log;
- `opened_window_projections`, the projections for the documents that a wrapper opens
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
- `run_editor!(backend, projection, document)` of the kernel. Its two
  callers, `run_console_example` and inet's `mac_fsm_sdl.jl`, write
  `run_editor!(make_editor(...))`.
- `make_editor(document, projection, title)` and `run_window_editor` of the
  screen package. The title and the size become the setting of `window`.

**These methods take the order of C13:**
- `make_editor(backend, projection, document)` of the kernel becomes
  `make_editor(document, projection; backend)`. An old call fails with a
  `MethodError`, because a `Backend` is not a `Document`.
- `Editor(backend, document, projection, devices)` becomes
  `Editor(document, projection; backend, devices)`. It has about 20 callers,
  most of them in tests.
- `play_live!(backend, timeline; projection, document)` becomes
  `play_live!(document, projection, timeline; backend)`.

The order of the fields of `Editor` does not change.

### 4.3 The display package

The new package is `ProjecturedDisplay`, with the leaves `ProjecturedDisplayTest`
and `ProjecturedDisplayExample` (P5). It depends on the kernel, Screen,
Widget, Reflection, Natural, Text and the stdlib `REPL`. It does not depend on
Pane, DataFrames or a backend.

- `display_in_editor(value; title, backend = nothing) -> document` shows
  `value`:
  - The first call starts the editor with `run_editor!(document; wait =
    false)`.
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

The display draws with `NaturalToGraphics`, as the data frame display does
now. The natural renderer asks `make_graphics_projection` for the type of a
document before it reads its tables (C7), so a `DataFrameView` draws with the
projection of the data frame package, and a reflected tree with the
projection of the reflection package.

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
| `window` | Screen | `:window` | on by default; acts only for a backend that draws windows |
| `tabs` | Pane | `:container` | on by default; does nothing on a `PaneTree` |
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

P1, P2 and P3 are made (C10, C11 and C12). P4, P5 and P6 are made as
recommended below (the owner, 2026-09-30: "I agree, let's start"). P7 is
made (C14).

**Found in step 1.** The code quality rules say "A definition takes at most
one optional positional argument, and never one beside a keyword argument"
and "More than five keyword arguments is a type that is missing".
- `build_editor(document, projection = nothing; ...)` breaks the first rule.
  So there are two methods, `build_editor(document; ...)` and
  `build_editor(document, projection; ...)`, and the same for `run_editor!`.
- A wrapper changes the parts in place, so the seam is `wrap_editor!`, with
  the `!` of the naming rules.
- **Q1, for the owner.** `Editor(document, projection; backend, devices,
  clock, tools, faults, fault_policy, feeds)` has seven keywords. The rule
  for a constructor says: "A constructor takes what the document is, and
  names its chrome." My recommendation: `Editor(document, projection,
  backend, devices; clock, tools, faults, fault_policy, feeds)`, with the
  `@positional` marker. The document and the projection come first, as C13
  says, and the backend and the devices stay positional, because they are
  part of what an editor is.
- **Q2, for the owner.** `run_editor!(editor; wait, mcp, mcp_instructions,
  mcp_host, mcp_port, fault_policy)` has six keywords. My recommendation: one
  keyword `mcp`, whose setting is `false`, `true` or a `NamedTuple` of
  `instructions`, `host` and `port`, as the setting of a wrapper is. Then
  `run_editor!(editor; wait, mcp, fault_policy)` has three.

Step 1 leaves the `Editor` constructor and `wait` for these answers.

The points as they were put:
- **P4.** `make_value_document`, `make_graphics_projection` and
  `refresh_document!` go in Widget. Widget is the lowest package that both
  the data frame package and the display load. My recommendation: Widget.
- **P5.** The name `ProjecturedDisplay` for the package, and `EditorDisplay`
  for the `AbstractDisplay`. My recommendation: these names.
- **P6.** omnet-julia and inet-julia. My recommendation: move the callers in
  omnet-julia in a worktree of its own, and test that worktree against this
  branch in a scratch environment. Move the callers in inet-julia that
  compile now. List the two broken ones for the owner, and do not fix them.

## 6. Steps

Each step ends with its narrowest test and a commit.

- [ ] **1. The kernel.** Add `EditorParts`, the wrapper seams, the backend
  seams and the choice of the backend. Add `build_editor`, the two forms of
  `run_editor!`, and `wait = false`. Change `make_editor`, `Editor` and
  `play_live!` to the order of C13, and move their callers. Remove
  `run_editor!(backend, projection, document)`. Test with doubles in
  `ProjecturedKernelTest`.
  - [x] 1a (2026-09-30). Two new fragments of `EditorModule`:
    `BackendChoice.jl` (`get_backend_name`, `get_backend_output`,
    `collect_backend_types`, `make_default_backend`) and `EditorBuild.jl`
    (`EditorParts`, `EDITOR_WRAPPER_LAYERS`, `wrap_editor!`,
    `get_wrapper_layers`, `get_excluded_wrappers`, `is_wrapper_default`,
    `make_document_projection`, the two methods of `build_editor`), both ⬜ in
    SEALING.md. `make_editor(document, projection; backend, ...)`, the two
    methods of `run_editor!(document, ...)`, and `play_live!(document,
    projection, timeline; backend, ...)`. `run_editor!(backend, projection,
    document)` is gone. `_make_default_devices()` is the one list of the
    default devices. The callers and seven documents follow.
    `test_build_editor` in `test/kernel/editor/BuildEditorTest.jl`.
    - The candidates are read from the method table of `get_backend_output`,
      and a known keyword is `hasmethod(get_wrapper_layers, Tuple{Val{k}})`.
    - A keyword that is off and that no package declares is ignored, so a
      program can say `tabs = false` when the pane package is not loaded.
    - The test doubles use outputs and keywords that no package uses, because
      a method stays for the rest of the process: a double that drew
      `:windows` would be a second candidate for every later test.
  - [ ] 1b. The `Editor` constructor (Q1) and `wait` (Q2).
  - [ ] 1c. The docstring of `make_strict_fault_policy` in the sealed
    `source/kernel/fault/FaultPolicy.jl` shows the old order of
    `make_editor`. It waits for the owner's permission.
- [x] **2. The backends declare themselves.** SDL, Web and Console. Test the
  choice: one candidate, two, none, and a `:text` backend beside a `:windows`
  one. Done 2026-09-30: `:sdl` and `:web` draw `:windows`, `:console` draws
  `:text`; each package imports the two seams it extends.
  `test_backend_choice` in `test/projectured/backend/BackendChoiceTest.jl`
  runs with every backend package loaded: SDL and Web make a caller name its
  backend, and the console is the one backend for text. The run of steps 1a
  and 2 passed 338 tests (build, wait, inbox, playback, the kernel layering
  guard, the referenced document in the application, the console, the choice
  of a backend, and the gallery's editor).
- [x] **3. The window wrapper.** Move `make_window_scene` into the method of
  `window`. Remove `make_editor(document, projection, title)` and
  `run_window_editor`, and move their callers to `build_editor` and
  `run_editor!`: Application, ApplicationVideo, the tests, and the data frame
  display for now.
  - Written 2026-09-30. `wrap_editor!(::Val{:window}, ...)` in
    `WindowScene.jl` takes `(; title, width, height,
    opened_window_projections)`. The default title is the title of the
    document, else "ProjecturEd", and the default size is the display's.
  - The wrapper acts unless the backend declares an output that is not
    `:windows`. So a recorder and a test double, which declare no output, get
    a window, as they did from the screen's `make_editor`.
  - `screen_wrap` is gone, because nothing passed it.
  - `run_editor!(document, ...)` takes the `mcp` keywords of the loop, so a
    caller of `run_window_editor` moves to one call.
  - `test_window_wrapper` in `test/substrate/projection/WindowWrapperTest.jl`.
    Fourteen documents follow. The run of 2026-09-30: the window wrapper 8
    of 8; `test_application` 337 pass and 2 errors, which main gives too
    (the navigator scroll test); the referenced document in the application
    101; the export collisions; the data frames 66.
- [x] **4. The widget seams.** Add `make_value_document`,
  `make_graphics_projection` and `refresh_document!`. The natural renderer
  asks `make_graphics_projection` before its tables, and Natural adds the
  method of `make_document_projection` (C14). Reflection adds its method of
  `make_graphics_projection`.
  - Found: the natural renderer builds one table by type when it is made, and
    `TypeDispatchingProjection` reads only a fixed table. So the seam is keyed
    by type, `make_graphics_projection(::Type{T}; measure)`, and the renderer
    adds a row for each type in the method table, before the rows of
    `register_natural_graphics!`. `collect_graphics_projection_types` puts a
    type before its supertypes, so the first match is the most specific.
  - Found: the reflection package depends on neither Style nor Projection, so
    it can not build the chain of `ReflectionToWidget` and `WidgetToGraphics`
    with a font. The display adds that row itself with the `extra` keyword of
    `NaturalToGraphics`, which is there for a caller's own rows. So
    Reflection adds no method.
  - Found: a method for `Type{<:T}` keeps its `where` inside the tuple of its
    signature, so the collection unwraps the argument too.
  - `test_document_composition` in
    `test/substrate/projection/DocumentCompositionTest.jl`. The natural
    tests (the registry, the notation, every atom) and the data frames pass.
- [ ] **5. The tabs and `show_document!`.** The screen method opens a
  window. The pane method opens or focuses a tab. Add the `tabs` wrapper.
  - Found: `PaneToWidget` passes the content of a tab through unchanged, so
    the stage after it must draw the pane's widgets and also each content.
    The data frame display chains it before `NaturalToGraphics`, which draws
    both. A caller with a projection of its own, such as the chain of JSON,
    has a projection that draws no widget, so a `tabs` wrapper that is on by
    default would break it.
  - **Q3, for the owner.** (a) The tabs wrapper draws its widgets itself,
    with the rows of `WidgetToGraphics` and `LayoutToGraphics`, and sends
    every other document to the caller's projection. `ProjecturedPane` then
    names `ProjecturedStyle` and `ProjecturedText` for the font and the
    measure. Both are in its closure through Widget already, so no package
    joins an image. (b) The tabs wrapper chains `PaneToWidget` before the
    caller's projection and needs one that draws widgets; a caller whose
    projection does not passes `tabs = false`. My recommendation: (a),
    because a wrapper that is on by default must work with any projection.
  - `show_document!` applies no wrapper of the `:document` layer to a new
    document yet: the display is its one caller, and it uses no such
    wrapper. The editor keeps no list of its wrappers until a caller needs
    it.
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
- **Tabs where there were none.** A caller of `build_editor` gets tabs when
  the pane package is loaded (C10). Steps 8 to 12 decide for each caller
  whether it passes `tabs = false`.
- **The order of the wrappers.** A different order changes what a person
  sees. The layer numbers of §4.5 keep the order of the gallery. Step 8
  compares the pixels of three gallery examples before and after.
- **The recorded precompile statements** name functions that go. A statement
  that fails is skipped with no error, so the start of a session gets slower
  with no message. Step 11 records them again.
- **A method that a package adds after the loop starts** is too new for the
  loop, as a function that the REPL defines is now. This is not a new
  problem, and `invokelatest` covers the calls that the display posts.
