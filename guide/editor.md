# Editor

The editor ties everything together: it owns the document, the projection
pipeline, the backend, and the input devices, and runs a read-eval-print loop
that responds to user input. The implementation lives in
[program/src/editor/Editor.jl](../program/src/editor/Editor.jl) and is wrapped
by the entry-point in
[program/src/editor/Application.jl](../program/src/editor/Application.jl).

## The Editor struct

```julia
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    iomap::Union{IoMap, Nothing}        # latest output of projection_print
    operation::Union{Operation, Nothing}# latest output of projection_read
end
```

- `backend` — the display/input backend (e.g. `SdlBackend`)
- `document` — the reactive document being edited
- `projection` — the projection pipeline; typically a `SequentialProjection`
  that ends in a `GraphicsCanvas`-producing step
- `devices` — `Vector{Device}` with the window, keyboard, and mouse
- `iomap` — the most recent IoMap from `projection_print`; needed by
  `projection_read` to translate the next event back to a domain operation
- `operation` — the most recent operation; used by `evaluate!` and the
  per-frame log

## The Read-Eval-Print loop

`run!(editor)` executes:

```julia
while true
    perf_reset!()
    read!(editor)      # poll devices → projection_read → editor.operation
    evaluate!(editor)  # evaluate_operation(editor.operation, editor.document)
    print!(editor)     # projection_print → editor.iomap; render to devices
    perf!(editor)      # log reactive counters
    sleep(0.01)
end
```

A `QuitEditorException` thrown out of `evaluate_operation` exits the loop
cleanly. The MCP server is started before the loop and stopped in the
`finally` block — see below.

### Read

`read_from_devices(backend, devices)` polls the backend's event queue (in
the SDL case, `SDL_PollEvent`) and returns the next backend-agnostic event:
`KeyPress`, `MouseClick`, `MouseMove`, `MouseScroll`, or `QuitEvent`. The
event is then passed through `projection_read(editor.projection,
editor.iomap, event)` — the entire pipeline walks backward, each projection
contributing a translation step until an `Operation` falls out at the
document end.

### Evaluate

`evaluate_operation(operation, document)` is a generic function with methods
defined per operation. For `ReplaceSelectionOperation` the implementation is
`clear_selection!(document); set_selection!(document, op.path)`. For
`QuitEditorOperation` it throws `QuitEditorException`. Other operations
(e.g. `ScrollWidgetOperation`, `ReplaceFocusPartOperation`) mutate the
document or projection state directly. See [the operations guide](operations.md).

### Print

If `editor.iomap` is `nothing`, `projection_print(editor.projection,
editor.document)` runs the whole pipeline and stores the result. The IoMap
is then written to each output device with `write_to_devices(backend,
devices, iomap.output)`. Because every intermediate value is a reactive
`Cell`, subsequent reads only recompute the parts that were invalidated by
the operation — the rest is served from the cache.

The `iomap` is *not* invalidated at the end of a frame — its contents are
reactive and will refresh on the next read.

## Running an editor

The convenience entry point is `application`:

```julia
using Projectured

backend  = SdlBackend()
document = JsonString("hello world")
proj     = SequentialProjection(
    JsonToSyntax(),
    SyntaxToText(),
    TextToGraphics(measure = (t, f) -> sdl_measure_text(backend, t, f)),
)

application(backend, proj, document;
    title  = "Editor",
    width  = 1200,
    height = 800,
)
```

`application` initialises the backend, opens a window, builds a
`Vector{Device}` containing `Window`, `Keyboard`, and `Mouse`, constructs
the `Editor`, and calls `run!`. Cleanup (close window, quit backend) is in
a `finally` block.

## Devices and backends

- `Device` is an abstract type. Concrete subtypes are `Window`, `Keyboard`,
  and `Mouse` — see [the devices and backends guide](devices-and-backends.md).
- `Backend` is the abstraction over the display/input platform. The only
  current implementation is `SdlBackend`. The backend provides
  `measure_text`, `open_window!`, `close_window!`, `read_from_devices`,
  and `write_to_devices`.
- Projections that need to measure text take a `measure::Function` argument
  (e.g. `TextToGraphics`); the backend's `sdl_measure_text` is the usual
  injection.

## MCP server

When `run!` starts, it constructs an `McpServer` bound to the editor and
launches it on `http://127.0.0.1:9876/mcp` (see
[program/src/editor/Mcp.jl](../program/src/editor/Mcp.jl)). The server
speaks JSON-RPC 2.0 via HTTP+SSE using
[ModelContextProtocol.jl](https://github.com/JuliaModelContextProtocol/ModelContextProtocol.jl).

Tools exposed by the server include `execute_julia_code` (run arbitrary
Julia in the editor process with `editor` bound and `using Projectured`
preloaded), plus resource listings for guides, modules, classes, and
function documentation. The intent is that an AI assistant can inspect and
manipulate `editor.document` and `editor.projection` live.

The server is stopped in the `finally` block of `run!`.

## Performance counters

Each frame the editor calls `perf_reset!()` before reading input and
`perf!()` after rendering, which logs

```
[perf] reads=… computes=… invalidations=… writes=…
```

when an operation was applied. Use these to find unintentional
recomputation: if a single keypress causes thousands of `computes`,
something is reading more cells than necessary.

## Adding new operations

If you introduce a new editing operation, you need to:

1. Define a struct subtyping `Operation`.
2. Add an `evaluate_operation(op::YourOp, document)` method.
3. Update the relevant projection's `projection_read` to produce the
   operation from the appropriate event.

See [the operations guide](operations.md) for examples.
