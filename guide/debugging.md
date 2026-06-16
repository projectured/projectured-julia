# Debugging in the REPL

Most day-to-day debugging of ProjecturEd is done from a Julia REPL launched
against the repo's top-level project. The root [Project.toml](../Project.toml)
already depends on `Projectured`, `ProjecturedExample`, and `ProjecturedTest`,
so a single `julia --project=.` from the repo root gives you access to every
public symbol used below.

```sh
cd projectured
julia --project=.
```

```julia
julia> using Projectured, ProjecturedExample, ProjecturedTest
```

## Running an example interactively

`run_example` is the fastest way to put a domain in front of you. It opens an
SDL window using the example's document and projection.

```julia
julia> run_example()                # defaults to "json"
julia> run_example("syntax")        # any name from `examples`
julia> run_example(json_example)    # or pass the Example object directly
```

The function lives at
[example/src/Examples.jl](../example/src/Examples.jl) (the `Example` overload at
`run_example(example::Example; …)`, plus name/`Vector` overloads); it accepts a
few keyword arguments worth knowing:

| Keyword | Effect |
|---|---|
| `width`, `height` | Window size. When unset, defaults to the display size via `sdl_display_size()`. |
| `caching=true` | Wraps the projection in `make_graphics_caching` so you can verify cell invalidation behaviour. |
| `scrolling=true` | Wraps the document/projection in the scrolling wrapper so you can drive layout that exceeds the viewport. |
| `workbench=true` | Embeds the example inside the workbench shell. |
| `reset=true` | Rebuilds a fresh `document`/`projection` from the example's factories. Use this after an interactive session has mutated the cached instance. |

If you get a stale-state bug, `run_example("foo"; reset=true)` is almost
always the first thing to try — the `Example` struct caches one shared
instance per example.

## Printing without rendering

`print_example` runs the projection's printer and dumps the resulting output
tree as text. It is the cheapest way to see what a projection produces,
without launching SDL.

```julia
julia> print_example("json")
julia> print_example(syntax_example)
```

Implementation is at
[example/src/Examples.jl:75](../example/src/Examples.jl#L75). It calls
`projection_print`, takes `iomap.output`, forces the outer cell if needed,
and uses `print_object` to render the tree with brace delimiters.

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

julia> iomap = projection_print(proj, doc);    # forward projection
julia> iomap.output                            # the printed tree
julia> iomap.output[]                          # force the outer Cell

julia> using Projectured: KeyDown, Modifiers
julia> op = projection_read(proj, iomap, KeyDown(:right, Modifiers()));
julia> evaluate_operation((; document = doc), op);   # apply it (editor.document)
julia> projection_print(proj, doc)                   # reprint after the edit
```

This is exactly the read-eval-print loop from
[program/src/editor/Editor.jl](../program/src/editor/Editor.jl), peeled
apart so you can step through it one call at a time.

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
generic functions (`projection_read`, `projection_print`,
`map_reference_forward`, `map_reference_backward`). These are declared in
[program/src/api/Projection.jl](../program/src/api/Projection.jl) and each
projection adds its own method; the recursion happens peer-to-peer (a
projection's `projection_read` calls `projection_read` on its children
directly), so to see the whole tree you must instrument the generic function
itself, not just the editor's top-level call.

The intended tool is a Cassette `overdub` that logs every call to the selected
functions as an indented tree, with **no edits to any projection method**:

```julia
julia> using Cassette, Projectured
julia> using Projectured: KeyDown, Modifiers
julia> Cassette.@context TraceCtx
julia> const _depth = Ref(0)

julia> function Cassette.prehook(::TraceCtx, ::typeof(Projectured.projection_read), p, iomap, x)
           println("  "^_depth[], "→ read ", nameof(typeof(p)), "   <", nameof(typeof(x)), ">")
           _depth[] += 1
       end
julia> Cassette.posthook(::TraceCtx, out, ::typeof(Projectured.projection_read), p, iomap, x) = (_depth[] -= 1)

# wrap whatever triggers a read — a manual call, or the editor's read of one event:
julia> ex = json_example; doc, proj = ex.document, ex.projection;
julia> iomap = projection_print(proj, doc);
julia> Cassette.overdub(TraceCtx(), () -> projection_read(proj, iomap, KeyDown(:right, Modifiers())))
```

You get an indented call tree of every read as the event flows through the
stack. Add more `prehook`/`posthook` pairs for `projection_print` and the two
reference mappers to watch the forward direction and the path mapping too.

**Until Cassette works on 1.12**, two dependency-free fallbacks:

- *Targeted `@debug`.* Drop `@debug "read" typeof(p) typeof(x)` into the
  specific `projection_read` methods you suspect and run with
  `JULIA_DEBUG=Projectured`. No automatic depth tree, but no machinery either.
- *Funnel + toggle.* Rename the real `projection_read` methods to
  `_projection_read` and make the public `projection_read` a thin logging
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

The reference DSL is documented in [the reference guide](editor/reference.md);
see [the selection guide](editor/selection.md) for how selections propagate
through nested documents.

## Forcing reactive cells

Every reactive value in the system is a `Cell` (see
[reactive cells](reactive-cells.md)). When something looks empty in the
REPL, it is usually because you are looking at the wrapper, not the value:

```julia
julia> doc.value         # may show a Cell
julia> doc.value[]       # forces evaluation
```

The walker used by the test suite (`_walk!` in
[test/src/editor/PrinterTest.jl](../test/src/editor/PrinterTest.jl)) is a
good template if you need to dump every reachable cell of a tree.

## Generating all screenshots

To regenerate every example screenshot in `image/` and re-inject the image
references into the guides and `README.md`:

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
julia> using Projectured, ProjecturedExample
julia> gestures = [
           (event = KeyPress('h'),                       hold = 0.3),
           (event = KeyPress('i'),                       hold = 0.3),
           (event = KeyDown(:right, Modifiers(), false), hold = 0.5),
       ]
julia> record_video_example("json", gestures, "/tmp/demo.mp4"; fps=30)
```

`event` is any backend-agnostic device event (`KeyDown`, `KeyUp`, `KeyPress`,
`MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, `MouseScroll`); `hold` is how
many seconds to display the resulting state. The initial state is shown for
`initial_hold` seconds (default `0.5`). Each gesture runs the full editor cycle
(`projection_read` → `evaluate_operation` → `projection_print`) and `round(hold *
fps)` identical frames are emitted, so the frame count is predictable: the
recording above is `15 + 9 + 9 + 15 = 48` frames at `fps=30`.

`record_video(document, projection, gestures, filename)` is the lower-level form;
both accept `fps`, `width`, `height`, `background`, and `initial_hold`. Output
must be `.mp4` (libx264 + `yuv420p`); encoding uses `ffmpeg` bundled via
`FFMPEG.jl`, so no system ffmpeg install is needed.

## Workspace fixtures

Sample documents live in [example/workspace/](../example/workspace/)
(`contact-list.json`, `hello-world.html`, `lorem-ipsum.txt`). The examples
that load files read from this directory; point a new example there when
you need an on-disk fixture.

## Common workflow

1. `using Projectured, ProjecturedExample` to pull in everything.
2. `print_example("name")` to confirm the printer doesn't blow up.
3. `run_example("name"; reset=true)` to see it on screen.
4. If something is wrong, grab `ex = some_example; ex.document, ex.projection`
   and step through `projection_print` / `projection_read` /
   `evaluate_operation` by hand.
5. Cross-reference with the test helpers documented in
   [the testing guide](testing.md) — `walk_printer_output`, `walk_reader_events`,
   `walk_repl_loop`, and `explore_text_selections` all take a `(document,
   projection)` pair and exercise one slice of the editor loop.
