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
[example/src/Examples.jl:47](../example/src/Examples.jl#L47); it accepts a
few keyword arguments worth knowing:

| Keyword | Effect |
|---|---|
| `width`, `height` | Window size (defaults 2400×1600). |
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

julia> using Projectured: KeyPress
julia> op = projection_read(proj, iomap, KeyPress(:right, false));
julia> evaluate_operation(op, doc);            # apply it back to the document
julia> projection_print(proj, doc)             # reprint after the edit
```

This is exactly the read-eval-print loop from
[program/src/editor/Editor.jl](../program/src/editor/Editor.jl), peeled
apart so you can step through it one call at a time.

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
julia> generate_screenshots()        # writes PNGs into image/
julia> update_guide_screenshots()    # injects ![...] references into guides + README
```

Output goes to `image/` as PNG files in a single step — no external tools.
Both functions accept keyword overrides: `width`, `height`, `image_dir` for
`generate_screenshots`, and `repo_root` for `update_guide_screenshots`.
`update_guide_screenshots` is idempotent — a second call produces no further
changes.

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
   `walk_repl_loop`, and `explore_selections` all take a `(document,
   projection)` pair and exercise one slice of the editor loop.
