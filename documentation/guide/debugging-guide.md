# Debugging in the REPL

> **Kind:** procedure · **Status:** current · **Stands on:** [setup-guide.md](setup-guide.md)

Most day-to-day debugging of ProjecturEd is done from a Julia REPL launched
against the repo's top-level project. The root [Project.toml](../../environment/all/Project.toml)
already depends on `Projectured`, `ProjecturedExample`, and `ProjecturedTest`,
so a single `julia --project=environment/all` from the repo root gives you access to every
public symbol used below.

```sh
cd projectured
julia --project=environment/all
```

```julia
julia> using ProjecturedAll, ProjecturedExample, ProjecturedTest
```

## Running an example interactively

`run_example` is the fastest way to put a domain in front of you. It opens an
SDL window using the example's document and projection.

```julia
julia> run_example()                # defaults to "json"
julia> run_example("syntax")        # any name from `examples`
julia> run_example(json_example)    # or pass the Example object directly
```

The gallery lives at
[domain/example/Gallery.jl](../../example/projectured/Gallery.jl); it holds the
`Example`/`Vector` overloads. Its shell, tooltip and clipboard wrappers are
domain vocabulary. The name-lookup overloads live with the global registry in
[projectured/example/ProjecturedExamples.jl](../../example/projectured/ProjecturedExamples.jl), and
`using ProjecturedExample` provides all of them. `run_example` accepts a
few keyword arguments worth knowing:

| Keyword | Effect |
|---|---|
| `width`, `height` | Window size. When unset, defaults to the display size via `get_sdl_display_size()`. |
| `caching=true` | Wraps the projection in `make_graphics_caching` so you can verify cell invalidation behaviour. |
| `scrolling=true` | Wraps the document/projection in the scrolling wrapper so you can drive layout that exceeds the viewport. |
| `shell=true` | Embeds the example inside a `WidgetShell` (a menu bar, a toolbar, and a status bar that names the example). |
| `tooltip=true` | Opens a sibling window showing the *current selection*'s reference (compact + human-readable) while a selection is set. |
| `reset=true` | Rebuilds a fresh `document`/`projection` from the example's factories. Use this after an interactive session has mutated the cached instance. |
| `gesture_log=true` | Shows a panel in the top-right corner with the last gestures and the operation each one made. See [The gesture log overlay](#the-gesture-log-overlay). |

If you get a stale-state bug, try `run_example("foo"; reset=true)` first,
since the `Example` struct caches one shared instance per example.

To drive the same example from a browser instead of an SDL window, pass a
[web backend](../package/kernel/devices-and-backends.md#webbackend) to
`run_example`. Run `using ProjecturedWeb` first, so `WebBackend` is in scope:

```julia
julia> run_example("json"; backend=WebBackend())            # serve on http://127.0.0.1:8080
julia> run_example("json"; backend=WebBackend(port=9000))   # then open the URL; the editor appears in the tab
```

## Stop at the first fault

A running editor survives a fault. The frame barriers catch the exception,
record it, and log it with a traceback that the console logger cuts short. To
see the whole stack, make the editor stop at the first fault:

```sh
bin/projectured --strict-fault-policy
```

The flag gives the editor `make_strict_fault_policy()`, so every barrier raises
the exception again. The program ends with exit code 2 and prints the stack. From
Julia, pass the policy to the loop:

```julia
julia> run_application(; fault_policy = make_strict_fault_policy())
julia> run_editor!(document, projection; window = (; title = "Title"),
                   fault_policy = make_strict_fault_policy())
```

A `FaultCatchingProjection` in the pipeline reads the same policy, so it raises
the exception again too and draws no mark.

The settings tab of a running editor shows the same policy as "Catch faults",
"Log faults" and "Fault sound", and a change there takes effect at once: the
editor prints the view again with the new policy.

## See what a frame repaints

A window repaints only the parts that changed, and it can outline in red what
each frame repaints. Turn the outline on for one run with an environment
variable:

```sh
PROJECTURED_DEBUG_DIRTY=1 bin/projectured
```

`PROJECTURED_PARTIAL_RENDER=0` repaints the whole window at each frame.
`PROJECTURED_SUPERSAMPLE=1` turns the smoothing of the edges off. In a running
editor, the settings tab (the gear of the toolbar, or View > Settings) shows the
same values as the render group, and the commands "Toggle partial render" and
"Toggle repaint outline" of the palette (Ctrl+Shift+P) switch them. A variable
wins over the settings file for that run. See
[settings.md](../package/platform/settings/settings.md).

## The gesture log overlay

`gesture_log=true` puts a panel over the content of each window. The panel shows
what the editor did: one line per gesture, with the operation that the
projection pipeline made from it, newest line first.

```julia
julia> run_example("json"; gesture_log=true)
julia> run_example("json"; gesture_log=true, gesture_log_capacity=40)
julia> run_example("json"; gesture_log=true,                    # keep everything
                   gesture_log_filter=(gesture, operation) -> true)
```

The filter is a predicate `(gesture, operation) -> Bool`. It runs when the
operation is recorded, not when the panel is drawn.
`default_gesture_log_filter` drops the selection operations, because a selection
follows almost every click and almost every arrow key and would fill the whole
buffer.

Use it to answer "did my gesture reach the reader, and what did it make?"
without a breakpoint. A gesture that no reader answers leaves no line, which is
the answer to the first half of the question.

Two things stay outside the panel:

- The readability zoom (`Ctrl+=` / `Ctrl+-`). The editor makes that operation
  after the pipeline declines the gesture, so no projection sees it.
- Everything the recorder does not reach. The recorder sits at the root of the
  composed projection, which is every operation of the gallery pipelines.

The panel is not interactive. A click goes through it to the content below.

The slice is [source/platform/gesturelog/](../../source/platform/gesturelog):
`GestureLogDocument.jl` (the buffer and the rendering of a gesture and an
operation), `GestureLogToSyntax.jl` (one line per entry),
`GestureLogRecording.jl` (the decorator that records) and
`GestureLogOverlay.jl` (the decorator that draws).
Wrap your own pipeline the same way the gallery does:

```julia
log = GestureLog(; capacity = 20)
overlay = GestureLogOverlayProjection(inner = my_projection, log = log)
root = GestureLogRecordingProjection(inner = my_screen_projection, log = log)
```

## Printing without rendering

`print_example` runs the projection's printer and dumps the resulting output
tree as text. It is the cheapest way to see what a projection produces,
without launching SDL.

```julia
julia> print_example("json")
julia> print_example(syntax_example)
```

Implementation is at
[example/platform/Harness.jl](../../example/platform/Harness.jl). It calls
`print_document`, takes `iomap.output`, forces the outer cell if needed,
and uses `print_object` to render the tree with brace delimiters.

## Writing a single screenshot

`write_example_image` renders one example to a `.bmp` or `.png` file, without
opening a window. It takes the same name-or-`Example` argument as
`print_example`.

```julia
julia> write_example_image("json", "/tmp/json.png")
julia> write_example_image(syntax_example, "/tmp/syntax.png")
```

Implementation is at
[example/kernel/Harness.jl](../../example/kernel/Harness.jl); the name-lookup
form lives with `print_example` in
[example/projectured/ProjecturedExamples.jl](../../example/projectured/ProjecturedExamples.jl).
`generate_example_screenshots()` (see "Generating all screenshots" below)
calls it once per example.

## Listing what's available

```julia
julia> examples                     # Vector{Example}
julia> getfield.(examples, :name)   # just the names
```

Every entry is exported as a constant too (e.g. `json_example`,
`widget_example`, `math_table_example`) so you can pass an `Example` object
directly without looking up by string.

## Driving the printer/reader manually

Once you have a document and projection in hand, the same primitives the
editor loop uses are available:

```julia
julia> ex = json_example;
julia> doc, proj = ex.document, ex.projection;

julia> iomap = print_document(proj, doc);    # forward projection
julia> iomap.output                            # the printed tree
julia> iomap.output[]                          # force the outer Cell

julia> using ProjecturedPlatform: KeyDown, ModifierKeys, Intent
julia> change = read_intent(proj, nothing, Intent(KeyDown(:right, ModifierKeys(); time = time())), iomap);
julia> change.operation                              # the operation the reader produced
julia> evaluate_operation((; document = doc), change.operation);   # apply it (editor.document)
julia> print_document(proj, doc)                   # reprint after the edit
```

This is exactly the read-eval-print loop from
[source/kernel/editor/EditorModule.jl](../../source/kernel/editor/EditorModule.jl), peeled
apart so you can step through it one call at a time.

### Bisecting the pipeline (a keystroke declines — which stage?)

When a keystroke produces no edit (`read_intent` returns `nothing`) and you don't
know why, **bisect the projection chain**. A pipeline is a `ChainingProjection`, and
its stages are just a tuple you can slice:

```julia
julia> proj = make_json_projection_example();   # (JsonToSyntax, SyntaxToText, TextToGraphics)
julia> proj.projections                         # the stages, outermost-input first
```

An event/op is read **outermost-stage first** and passed inward stage by stage; the
first stage whose reader declines is where the trail stops. Rebuild shorter chains to
find it, and forward-project through a truncated chain to see the document each stage
actually works on:

```julia
julia> using ProjecturedPlatform.ProjectionAlgebraModule: ChainingProjection
julia> outof(iomap) = (o = iomap.output; o isa Cell ? o[] : o);

# What does the *text* layer see? Project the input through all but the last stage.
julia> textchain = ChainingProjection(proj.projections[1:end-1]...);
julia> tb = outof(print_document(textchain, doc));   # the TextBlock and its selection
julia> getfield(tb, :selection)[]                    # where the caret landed after forward-mapping

# Feed the key to ONE stage in isolation (here the final Text→Graphics stage):
julia> last_stage = proj.projections[end];
julia> ed = (; document = tb, iomap = print_document(last_stage, tb));
julia> read_intent(last_stage, ed.iomap, KeyPress('x'; time = time()))   # an op here, nothing there
```

If a single stage **produces** an operation but the **full chain declines**, the fault
is in a *backward map / lowering* between that stage and the input — the op is built but
a later stage can't translate its reference (e.g. it lands on projection-introduced
chrome — a delimiter/separator with no document pre-image). If the isolated stage
**already declines**, the fault is in that stage's own reader (the selection didn't
forward-map to an editable position, or the gesture has no binding there).

A companion trick: forward-project a hand-built input with the caret placed at each
candidate offset (`@selected Doc(...) field{k}` from
`ProjecturedKernel.SelectionModule`) and feed the same key to each — the offsets that
decline vs. succeed pin the boundary that breaks (e.g. an insertion at a value's *start*
declining while its interior succeeds points at the delimiter|content span boundary).

## Searching the pipeline state (iomaps)

`search_references` / `search_documents` (the content-search primitives from the
[finding-and-selecting guide](../package/kernel/finding-and-selecting.md)) are usually run
against `editor.document`, but they walk **any** object graph — unwrapping cells,
descending struct fields and collections. An **iomap** is exactly such a graph:
the value `print_document` returns links a projection's *input* to its *output*
and stores every nested stage (`input`, `output`, `child_iomaps`, `step_iomaps`,
`inner_iomap`). Searching an iomap therefore searches the **entire projection
pipeline at once** — every intermediate document and every projected output tree,
at every stage — not just the source document.

```julia
julia> iomap = print_document(make_json_projection_example(),
                                make_json_document_example());

julia> search_references(iomap, "Wonderland")            # 16 paths — one per pipeline location
julia> search_documents(iomap, "Wonderland"; raw=true)   # 1 — the shared String value, once
julia> search_references(make_json_document_example(), "Wonderland")   # 1 path — source only
```

The value shows up **16 times** in the iomap because it appears at 16 distinct
*locations* along the pipeline: the source `JsonString`, each projection step's
input, the projected `SyntaxNode` tree, the text, and more. `search_documents(…;
raw=true)` returns it **once**, because all 16 locations share the *same*
underlying `String` object by reference.

Use `raw=true` on purpose here. The default document-scoped search folds each
hit up to its enclosing document, which differs by stage: a `JsonString` in the
JSON stages, a syntax/text leaf in the projected ones. It does **not** collapse
to one. Counting object identity is what `raw=true` gives you. That gap is
itself a diagnostic; see below.

### Reading an iomap path

An iomap-rooted `Reference` prints as its stages, so the path shows which
pipeline stage each hit is in at a glance:

```
::ChainingIoMap.input::JsonObject.entries…::JsonString               # source document
::ChainingIoMap.step_iomaps::Array[1]::TemplateIoMap.input::JsonObject…   # a stage's input
::ChainingIoMap.step_iomaps::Array[1]::TemplateIoMap.output::SyntaxNode…  # a stage's output
::…child_iomaps::Array[4]::TemplateIoMap.input::JsonObjectEntry…                      # nested projection
```

- `.input` — a stage's input document.
- `.output` — a stage's projected output tree.
- `.child_iomaps` / `.step_iomaps` / `.inner_iomap` — descend into nested /
  sequential projections.

`evaluate_reference(iomap, path)` resolves an iomap path back to the value at that
location, exactly as it resolves a document path.

### Debugging reactivity: where did the value go?

Searching the iomap rather than the document answers this question directly. When a value
is present in the source but *missing from the rendered output* — a projection
silently dropped it, a reactive cell didn't invalidate, a structural child-swap
didn't propagate — search the iomap and read which stages it survives to:

- **Present in an early `.input`, absent from a later stage's `.output`** → that
  stage's printer dropped it. Narrow to the projection between those two stages.
- **`search_references` count high but `search_documents(…; raw=true)` count > 1** →
  the value was *copied* somewhere instead of flowing by reference: a stale copy is
  sitting next to the fresh one, a common sign of a broken reactive link.
  When reactivity is healthy the same object flows through and the `raw=true` count
  collapses to one. Count with `raw=true` for this check. The default folds hits
  to their enclosing documents, which legitimately differ across stages.
- **Nothing in any `.output`** → the value never entered the projected tree; look
  at the first projection, not the renderer.

Because one call covers every stage, you can bisect the pipeline without
hand-stepping `print_document` layer by layer.

> The paths returned from an **iomap** search are rooted at the iomap
> (`::…IoMap.input…` / `.output…`), so they are for **inspection only** — do
> **not** feed them to `set_selection!` / `replace_selection!`. For a selectable
> path, search `editor.document` instead (see the
> [finding-and-selecting guide](../package/kernel/finding-and-selecting.md)).

## Tracing projection calls (event propagation)

> ⚠️ **Not working on the current Julia (1.12).** The approach below relies on
> [Cassette.jl](https://github.com/JuliaLabs/Cassette.jl), whose `overdub`
> builds on `@generated` functions. Julia 1.12 changed the generated-function
> contract ("generated functions must return `CodeInfo`"), so Cassette 0.3.14
> errors at `overdub`. This is **documented here for when Cassette catches up**
> (or we move to another engine); do not wire it into the package yet. See the
> alternatives at the end of this section if you need tracing today.

When you want to see *what reads what* — how a single event propagates down
through the projection stack — point logging at the four projection interface
generic functions (`read_intent`, `print_document`,
`map_reference_forward`, `map_reference_backward`). These are declared in
[source/kernel/projection/ProjectionInterface.jl](../../source/kernel/projection/ProjectionInterface.jl) and each
projection adds its own method; the recursion happens peer-to-peer (a
projection's `read_intent` calls `read_intent` on its children
directly), so to see the whole tree you must instrument the generic function
itself, not just the editor's top-level call.

The intended tool is a Cassette `overdub` that logs every call to the selected
functions as an indented tree, with **no edits to any projection method**:

```julia
julia> using Cassette, ProjecturedPlatform
julia> using ProjecturedPlatform: KeyDown, ModifierKeys, Intent
julia> Cassette.@context TraceCtx
julia> const _depth = Ref(0)

# Hook the 4-arg reader: read_intent(p, recursion, change, iomap)
julia> function Cassette.prehook(::TraceCtx, ::typeof(ProjecturedPlatform.read_intent), p, recursion, change, iomap)
           println("  "^_depth[], "→ read ", nameof(typeof(p)), "   <", nameof(typeof(change.gesture)), ">")
           _depth[] += 1
       end
julia> Cassette.posthook(::TraceCtx, out, ::typeof(ProjecturedPlatform.read_intent), p, recursion, change, iomap) = (_depth[] -= 1)

# wrap whatever triggers a read — a manual call, or the editor's read of one event:
julia> ex = json_example; doc, proj = ex.document, ex.projection;
julia> iomap = print_document(proj, doc);
julia> Cassette.overdub(TraceCtx(), () -> read_intent(proj, nothing, Intent(KeyDown(:right, ModifierKeys(); time = time())), iomap))
```

You get an indented call tree of every read as the event flows through the
stack. Add more `prehook`/`posthook` pairs for `print_document` and the two
reference mappers to watch the forward direction and the path mapping too.

**Until Cassette works on 1.12**, two dependency-free fallbacks:

- *Targeted `@debug`.* Drop `@debug "read" typeof(p) typeof(x)` into the
  specific `read_intent` methods you suspect and run with
  `JULIA_DEBUG=Projectured`. No automatic depth tree, but no machinery either.
- *Funnel + toggle.* Rename the real `read_intent` methods to
  `_projection_read` and make the public `read_intent` a thin logging
  wrapper gated by a `TRACE[]` flag (with a depth counter for indentation).
  This reproduces the indented-tree UX with zero dependencies and zero runtime
  cost when off, at the price of a one-time mechanical refactor of the ~111
  method heads. Worth doing if/when we want tracing as a permanent feature
  rather than waiting on Cassette.

## Inspecting selection and references

```julia
julia> doc.selection                          # current Reference
julia> clear_selection!(doc)
julia> set_selection!(doc, some_path)
```

The reference DSL is documented in [the reference guide](../package/kernel/reference.md);
see [the selection guide](../package/kernel/selection.md) for how selections propagate
through nested documents.

## Forcing reactive cells

Every reactive value in the system is a `Cell` (see
[reactive cells](../package/kernel/cell.md)). When something looks empty in the
REPL, it is usually because you are looking at the wrapper, not the value:

```julia
julia> doc.value         # may show a Cell
julia> doc.value[]       # forces evaluation
```

The walker used by the test suite (`_walk!` in
[kernel/test/editor/PrinterTest.jl](../../test/kernel/editor/PrinterTest.jl)) is a
good template if you need to dump every reachable cell of a tree.

## Generating all screenshots

To regenerate every example screenshot in `image/` and re-inject the image
references into the guides and [README.md](../../README.md):

```julia
julia> using ProjecturedExample
julia> generate_example_screenshots()        # writes PNGs into image/
julia> update_guide_screenshots()    # injects ![...] references into guides + README
```

Output goes to `image/` as PNG files in a single step — no external tools.
Both functions accept keyword overrides: `width`, `height`, `image_dir` and
`filter` (a `Regex`/string limiting which examples are regenerated, e.g.
`filter=r"^widget"`) for `generate_example_screenshots`, and `repo_root` for
`update_guide_screenshots`.
`update_guide_screenshots` is idempotent — a second call produces no further
changes.

## Recording a video

`record_video` drives an example through a timed sequence of gestures and
encodes the result to an MP4 — headless, no window required. Timing is in
**video time** (frame counts), so output is deterministic regardless of how long
rendering takes.

```julia
julia> using ProjecturedAll, ProjecturedExample
julia> gestures = [
           (event = KeyPress('h'; time = time()),                   hold = 0.3),
           (event = KeyPress('i'; time = time()),                   hold = 0.3),
           (event = KeyDown(:right, ModifierKeys(); time = time()), hold = 0.5),
       ]
julia> record_example_video("json", gestures, "/tmp/demo.mp4"; fps=30)
```

`event` is any backend-agnostic device event (`KeyDown`, `KeyUp`, `KeyPress`,
`MouseDown`, `MouseUp`, `MouseClick`, `MouseMove`, `MouseScroll`); `hold` is how
many seconds to display the resulting state. The initial state is shown for
`initial_hold` seconds (default `0.5`). Each gesture runs the full editor cycle
(`read_intent` → `evaluate_operation` → `print_document`) and `round(hold *
fps)` identical frames are emitted, so the frame count is predictable: the
recording above is `15 + 9 + 9 + 15 = 48` frames at `fps=30`.

Keyboard typein only edits when something is selected — with no caret the reader
produces no operation and `KeyPress` gestures are silent no-ops. To record a
typing demo, either make the first gesture a `MouseClick` that places the caret,
or pass an `initial_selection` (a `Reference` into the document, the same
kind of value `set_selection!` and `run_example(...; selection=…)` take):

```julia
julia> caret = @reference entries[1].key{0}   # cursor before the 1st key's 1st char
julia> record_video(doc, proj, gestures, "/tmp/demo.mp4"; initial_selection=caret)
```

`record_video(document, projection, gestures, filename)` is the lower-level form;
both accept `fps`, `width`, `height`, `background`, and `initial_hold`. Output
must be `.mp4` (libx264 + `yuv420p`); encoding uses `ffmpeg` bundled via
`FFMPEG.jl`, so no system ffmpeg install is needed.

A timeline entry may also carry an `operation` instead of an `event`:
`(operation = …, hold = …)` injects a domain `Operation` straight into the
evaluator, skipping the reader — for actions with no single device-event trigger
(seed a selection, scroll, swap focus/document). `operation` is an `Operation`
value or a `doc -> op` thunk evaluated at fire time:

```julia
julia> timeline = [
           (operation = ReplaceSelectionOperation(caret), hold = 0.3),  # jump the caret
           (event     = KeyPress('!'; time = time()),     hold = 0.3),  # type there
       ]
julia> record_video(doc, proj, timeline, "/tmp/demo.mp4")
```

## Live examples: scripted sessions on a real window

A `LiveExample` captures an existing example and pairs it with a *timeline* (the
same `(event|operation = …, hold = …)` entries). One timeline drives both a
headless recording and a live, watch-it-happen window:

```julia
julia> using ProjecturedAll, ProjecturedExample
julia> record_live_example("json_typein", "/tmp/demo.mp4")  # headless MP4
julia> play_live_example("json_typein")                     # real window, wall-clock speed
```

`record_live_example` reuses `record_video`. `play_live_example` wraps the
example in a single `WindowDocument`/`ScreenDocument` (the scene `run_example`
builds) and runs `play_live!(editor, timeline; window_id, initial_hold)`: each
frame polls real input *and* fires the next scheduled timeline entry when its
wall-clock time arrives, so the user watches the script run and can still
interact (Escape / window-close quits). `hold` is the dwell after an entry in
both worlds — frame counts for the recorder, a delay for the live player.

Predefined live examples live in `live_examples` (e.g. `json_typein_live`,
`json_select_and_edit_live`); build your own with the `LiveExample` constructor
and the `timed_event` / `timed_operation` helpers.

## Workspace fixtures

Sample documents live in [projectured/example/workspace/](../../example/projectured/workspace)
(`contact-list.json`, `hello-world.html`, `lorem-ipsum.txt`). The examples
that load files read from this directory; point a new example there when
you need an on-disk fixture.

## Common workflow

1. `using ProjecturedAll, ProjecturedExample` to pull in everything.
2. `print_example("name")` to confirm the printer doesn't blow up.
3. `run_example("name"; reset=true)` to see it on screen.
4. If something is wrong, grab `ex = some_example; ex.document, ex.projection`
   and step through `print_document` / `read_intent` /
   `evaluate_operation` by hand.
5. Cross-reference with the test helpers documented in
   [the testing guide](testing-guide.md) — `walk_printer_output`, `walk_reader_events`,
   `walk_repl_loop`, and `explore_position_selections` all take a `(document,
   projection)` pair and exercise one slice of the editor loop.
