# Multiple Windows

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

## Summary

Introduce `ScreenDocument` and `WindowDocument` as ordinary projectional
document types. A `ScreenDocument` holds a list of `WindowDocument`s;
each `WindowDocument` carries window metadata (title, position, size,
bg, style, id) and a `content::Document` of any type.

No new projection is needed. The existing primitives already compose
into exactly the right pipeline:

```julia
projection = RecursiveProjection(
    TypeDispatchingProjection(
        ScreenDocument => CopyingProjection(),
        WindowDocument => CopyingProjection(),
        Any            => example_projection,
    )
)
```

- `RecursiveProjection` passes itself as the `recursion` argument, so
  whenever any inner step recurses on a child node, it re-enters the
  type dispatcher.
- `TypeDispatchingProjection` selects by the input's runtime type
  (first match wins). `ScreenDocument` and `WindowDocument` go to
  `CopyingProjection`. The `Any` catch-all forwards every other
  type — including the example's domain document — to the example's
  projection.
- `CopyingProjection` walks `ScreenDocument` (its `windows`
  `CellVector`) and `WindowDocument` (its struct fields), copying
  non-document fields verbatim and recursing on document-typed
  fields via the `recursion` arg, which routes back through the
  dispatcher.

By the time recursion reaches `WindowDocument.content`, the
dispatcher's `Any` case fires and the example projection runs on
the content as if no wrapper existed.

`ScreenDocument` is **not mandatory** as the editor's root. The
editor runs whatever document/projection it is given; all that
matters is that the printer's output type can be written to the
output devices. In practice, however, `application` opens no
windows by itself — window metadata (title, position, size, bg,
style) lives on `WindowDocument`. To see anything on screen, the
pipeline must produce a `ScreenDocument`. The bare-`GraphicsCanvas`
output path remains useful for offscreen rendering (`write_image`,
test helpers) but is no longer a path through `application`.

`write_to_devices` therefore has one new dispatch:

- `ScreenDocument` → reconcile windows against the list (used by
  `application` / the editor loop).
- `GraphicsCanvas` → existing offscreen / single-window-write
  method, retained for `write_image` and tests.

Helpers like `run_example` wrap their inputs:

```julia
ScreenDocument([WindowDocument(id=:main, …, content=example_doc)])
```

and build the composed projection above. The example itself
doesn't change.

---

## Why this shape

- No new projection type. The behaviour we want
  ("preserve metadata, recurse into content") is literally what
  `CopyingProjection` already does for every other struct
  document, and `TypeDispatchingProjection` + `RecursiveProjection`
  is the existing way to switch projections based on the node
  being visited.
- `ScreenDocument` and `WindowDocument` are documents like any
  other. They get reactive cells, references, selections, copying,
  and recursive composition for free.
- They can serve as **input** (a root document modelling "this
  editor has these windows") or as **output** (terminal stage of
  the projection pipeline). The same types do both jobs.
- The editor stays type-agnostic about its output.
  `write_to_devices` is the only seam that knows how to materialise
  a particular output type — adding `ScreenDocument` support there
  is a localised change.

---

## Design

### `ScreenDocument` and `WindowDocument`

```julia
@document struct ScreenDocument <: Document
    windows::CellVector       # element type: WindowDocument
    selection::Reference
end

@document struct WindowDocument <: Document
    id::Symbol                # stable identity across frames (e.g. :main, :tooltip)
    title::String
    x::Int                    # screen position; -1 = backend chooses
    y::Int
    width::Int                # 0 = auto-size from content canvas
    height::Int
    bg::NTuple{4,UInt8}
    style::Symbol             # :normal, :tooltip, :floating, ...
    content::Document         # any document; pre-projection a domain doc, post-projection a GraphicsCanvas
    selection::Reference
end
```

`id` is the backend-visible window identity. It is chosen by
whoever constructs the `WindowDocument` and must be unique within
its `ScreenDocument`. Two windows with the same id is a usage bug.

All other metadata fields are plain values. `CopyingProjection`'s
struct case copies them through to the output `WindowDocument`
unchanged because they aren't `Document`-typed. `content` is the
one `Document`-typed field, so it is the only field
`CopyingProjection` recurses into — which is exactly where we want
the example's projection to take over.

### How `run_example` wraps a domain example

`run_example` still takes `title`, `width`, `height` keyword
arguments — but they now flow into the `WindowDocument` it
constructs rather than into `application`:

```julia
function run_example(domain_doc, domain_projection;
                    title="Example", width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT)
    screen = ScreenDocument([
        WindowDocument(; id=:main, title=title,
                        width=width, height=height,
                        content=domain_doc),
    ])
    projection = RecursiveProjection(
        TypeDispatchingProjection(
            ScreenDocument => CopyingProjection(),
            WindowDocument => CopyingProjection(),
            Any            => domain_projection,
        )
    )
    application(backend, projection, screen)
end
```

The example's `domain_projection` operates on its `domain_doc`
exactly as today; the only new code is the wrapping.

Multi-window examples push more than one `WindowDocument` into
`screen.windows`. If different windows want different projections,
extend the type dispatcher with more entries, or branch on the
content type the example uses.

### Editor stays output-type-agnostic

`Editor`, `read!`, `evaluate!`, `print!`, `run!` are unchanged.
The only place output-type knowledge lives is `write_to_devices`
on the backend. Today there is one method:

```julia
write_to_devices(::SdlBackend, devices, canvas::GraphicsCanvas)
```

This plan adds a second:

```julia
write_to_devices(::SdlBackend, devices, screen::ScreenDocument)
```

The `GraphicsCanvas` method is retained for `write_image` and
similar offscreen uses, but `application` itself drives windows
only via the `ScreenDocument` method — see "Application bootstrap"
below.

### Backend reconciliation

`SdlBackend` gains a registry of live windows keyed by
`WindowDocument.id`:

```julia
mutable struct SdlBackend <: Backend
    # ...existing fields...
    windows::Dict{Symbol, Window}        # id → live Window
    window_ids::Dict{UInt32, Symbol}     # SDL windowID → id
end

function write_to_devices(backend::SdlBackend, devices, screen::ScreenDocument)
    desired = Set(w.id for w in screen.windows)

    # Close windows whose id disappeared.
    for id in collect(keys(backend.windows))
        if !(id in desired)
            win = backend.windows[id]
            delete!(backend.window_ids, _sdl_id(win))
            close_window!(backend, win)
            delete!(backend.windows, id)
        end
    end

    # Open or update.
    for w in screen.windows
        sdl_win = get(backend.windows, w.id, nothing)
        if sdl_win === nothing
            sdl_win = Window(w.title, w.width, w.height; bg=w.bg)
            open_window!(backend, sdl_win)
            _apply_style!(backend, sdl_win, w.style)
            _set_window_position!(backend, sdl_win, w.x, w.y)
            backend.windows[w.id] = sdl_win
            backend.window_ids[_sdl_id(sdl_win)] = w.id
        else
            _update_window_geometry!(backend, sdl_win, w)
        end
        write_to_device(backend, sdl_win, w.content::GraphicsCanvas)
    end
end
```

The backend never decides what windows should exist — it mirrors
the projection output.

### Event routing

```julia
struct EventEnvelope
    window_id::Symbol         # the WindowDocument.id this event belongs to; :none for app-level
    event::Any
end
```

`read_from_devices` looks up SDL's `windowID` in `window_ids` and
returns an `EventEnvelope`. The editor passes it to
`projection_read`.

`CopyingProjection`'s reader already routes the event to the
correct child iomap based on the active reference; the composed
`RecursiveProjection(TypeDispatchingProjection(…))` shape means an
event targeting a particular `WindowDocument.content` naturally
reaches the example's inner reader. Inner readers don't need to
know about envelopes — only the editor's top-level read path that
hands the event in.

`SDL_QUIT` → envelope with `window_id = :none` → editor ends.
`SDL_WINDOWEVENT_CLOSE` → envelope with that window's id and an
inner `WindowCloseRequest`. The active copying-based reader
interprets this as "emit an operation that removes that
`WindowDocument` from `windows`".

### `Window` device → `Screen` device

Today's `Window <: Device` conflates two things: the hardware
target ("the display we're rendering to") and the native SDL
window resources ("title, position, size, renderer pointer").
In the new world these come apart cleanly:

- The hardware target is renamed `Screen <: Device`. It is the
  generic-side description of "we have a screen / a display to
  render onto". `Screen` carries no per-window state — it is
  effectively a marker; multi-monitor setups would be expressed
  as multiple `Screen` devices (out of scope for v1).
- The actual native SDL windows become a backend-internal record
  (the existing `SdlWindowHandle`, possibly renamed
  `SdlWindowResources` for clarity). One handle per
  `WindowDocument.id`, owned by the backend's `windows`
  registry.

`Screen` is a `Device` so it lives in `Editor.devices` alongside
`Keyboard` and `Mouse`. The backend opens / closes / updates
native windows on the screen as the `ScreenDocument` reconciler
demands.

Files:

- `program/src/device/Window.jl` → `program/src/device/Screen.jl`
  (renamed; `WindowModule` → `ScreenModule`, `Window` → `Screen`).
- `program/src/backend/Sdl.jl` retains `SdlWindowHandle` (or
  `SdlWindowResources`) as a purely backend-internal struct, no
  longer used in `Editor.devices`.

### Application bootstrap

`application` drops its `title`, `width`, `height` keyword
arguments — those now live on `WindowDocument` and reach the
backend via the `ScreenDocument` reconciler. The new signature is
simply:

```julia
function application(backend::Backend, projection, document)
    init!(backend)
    try
        editor = Editor(backend, document, projection,
                        Device[Screen(), Keyboard(), Mouse()])
        run!(editor)
    finally
        quit!(backend)
    end
end
```

No native window is opened by `application`; the backend opens
one (or more) the first time `write_to_devices` sees a
`ScreenDocument`. `Editor.devices` describes the hardware:
`Screen`, `Keyboard`, `Mouse`.

To open any window with `application`, the pipeline must produce
a `ScreenDocument`. The `RecursiveProjection(TypeDispatchingProjection(...))`
wrapping shown for `run_example` is the canonical way to do that
on top of an existing single-window pipeline. Examples that
construct their own `application` call adopt the same wrapping
(or are migrated to go through `run_example`).

---

## What is intentionally NOT here

- No `ScreenProjection`, `WindowProjection`, or any other new
  projection type. `RecursiveProjection` +
  `TypeDispatchingProjection` + `CopyingProjection` express the
  pattern.
- No tooltip-specific projection, trigger predicate, or hover
  delay. Tooltips are a controller that mutates the input
  `ScreenDocument` (push/remove a `WindowDocument(id=:tooltip, …)`).
- No multiple editors / multiple event loops.
- No per-window content projection dispatch in a new type — if
  windows want different projections, extend the
  `TypeDispatchingProjection` with more entries.
- No cross-window selection mapping. Each `WindowDocument` may
  have its own content selection.
- No always-on-top / focus rules baked in. `style::Symbol` carries
  intent; the backend applies per-style behaviour.

---

## Implementation Steps

### Step 1 — `ScreenDocument` and `WindowDocument`

- Add `program/src/document/Screen.jl` defining both types.
- Register the module in `Projectured.jl`.
- Verify `CopyingProjection` already handles them via its struct
  / `CellVector` branches; add coverage in `test_printers` /
  `test_readers`.

### Step 2 — `TypeDispatchingProjection` `Any` fallback

- Confirm the existing `TypeDispatchingProjection` matches first
  pair whose `isa` succeeds, so `Any => domain_projection` as the
  last entry acts as a catch-all (it does — see the source).
- If a more explicit "default" slot is preferred for readability,
  add one. Otherwise document the `Any` idiom in the projection's
  docstring.

### Step 3 — Backend reconciler

- Add `windows::Dict{Symbol, Window}` and
  `window_ids::Dict{UInt32, Symbol}` to `SdlBackend`.
- Add `write_to_devices(::SdlBackend, devices, ::ScreenDocument)`
  alongside the existing `GraphicsCanvas` method.
- Helpers: `_apply_style!`, `_set_window_position!`,
  `_update_window_geometry!`.
- Cache `SDL_GetWindowID` on `SdlWindowHandle` at `open_window!`
  time so `window_ids` can be populated.

### Step 4 — Event envelopes

- Replace `read_from_devices`'s return with
  `Union{EventEnvelope, Nothing}`.
- Read SDL events' `windowID` fields, translate to `Symbol` via
  `window_ids`; `:none` when missing or zero.
- The editor's `read!` passes the envelope to `projection_read`.
- For single-canvas pipelines, the envelope's `window_id` is
  ignored — the inner event reaches existing readers unchanged.

### Step 5 — Window-close request

- Translate `SDL_WINDOWEVENT_CLOSE` into an envelope whose event
  is a new `WindowCloseRequest`.
- When the input is a `ScreenDocument`, the active copying-based
  reader produces an operation that removes the matching
  `WindowDocument` from `windows`.
- An empty `windows` list ends the editor.
- `SDL_QUIT` (envelope with `:none`) ends the editor.

### Step 6 — Rename `Window` device → `Screen` device

- Rename `program/src/device/Window.jl` to `device/Screen.jl`,
  module `ScreenModule`, struct `Screen <: Device` with no
  per-window state (title/width/height/bg are gone).
- Update `Projectured.jl` imports/exports.
- The SDL native-window record (`SdlWindowHandle`) stays inside
  `backend/Sdl.jl` and stops appearing in user-facing code.
- `application` constructs `Screen()` (rather than `Window(...)`)
  and adds it to `devices` alongside `Keyboard()` and `Mouse()`.

### Step 7 — Drop `title`/`width`/`height` from `application`

- Change `application(backend, projection, document; title, width, height)`
  to `application(backend, projection, document)`.
- The backend opens native windows lazily during reconciliation,
  so the application can return after `quit!` without explicit
  `close_window!` calls.

### Step 8 — `run_example` wrapping

- Update `run_example`, `print_example`, `write_image_example`
  (and any equivalent helpers in `guide/debugging.md`) to wrap
  the domain doc in `ScreenDocument([WindowDocument(...)])` and
  the projection in the
  `RecursiveProjection(TypeDispatchingProjection(...))` shape
  above. The `title`/`width`/`height` kwargs accepted by
  `run_example` flow into the `WindowDocument`, not into
  `application`.
- Individual examples don't change — they keep passing their
  domain doc and domain projection.

### Step 9 — Drain events per frame

- Today's loop does one read/eval/print per frame. With multiple
  windows under load, repaints starve.
- Drain all envelopes from `read_from_devices` (each → operation
  → `evaluate!`), then call `print!` once at frame end.
- Confirm single-window cadence is unchanged.

### Step 10 — Example: a two-window demo

- A small example whose root is a `ScreenDocument` with two
  `WindowDocument`s — say a JSON tree in `:main` and a path
  printer in `:info` — exercising the reconciler and event
  routing end-to-end. The type dispatcher can fan out by content
  type if the two windows need different projections.

### Step 11 — Document known limitations

- `_FONT_SCALE` is detected from the first opened window.
- A projection that thrashes window metadata every frame will
  thrash the backend.
- Each `WindowDocument` must have a unique `id` within its
  `ScreenDocument`.

---

## What this unlocks

- **Tooltips** become a controller that pushes/removes a
  `WindowDocument(id=:tooltip, …)` in the input `ScreenDocument`,
  or a projection that does the same in its output.
- **Debugger / inspector panels** are extra `WindowDocument`s.
- **Side-by-side preview** is two `WindowDocument`s whose content
  cells share reactive cells.
- **AI / MCP-driven window opening** — a tool emits an operation
  that pushes a `WindowDocument`; existing AI plumbing works.

The common thread: every "open a window" feature is "add a
`WindowDocument`". Every "close a window" is "remove a
`WindowDocument`". The backend mirrors.

---

## Open Questions

- **Where does dynamic-window state live?** Either in a
  `ScreenDocument` root (operations push/remove windows) or in
  some projection's cells that influence what the projection
  emits each frame. Both are supported.
- **`id` collisions** within one screen are a usage bug. Worth
  asserting in `ScreenDocument`'s constructor or at the start of
  reconciliation.
- **Per-window content projections.** v1 uses one
  `domain_projection` under the `Any` case. Multi-window examples
  that want different projections per window add more entries to
  the type dispatcher. No new type required.
- **Multi-monitor.** A `Screen <: Device` carries no per-display
  state today; multi-monitor would mean multiple `Screen`
  entries in `devices` and a way for `WindowDocument` to target
  one. Out of scope for v1.

---

## Relationship to Existing Architecture

| Concept | Current | With multiple windows |
|---------|---------|------------------------|
| Editor's root document | Domain document | Anything; including `ScreenDocument` when multi-window is wanted |
| Projection pipeline output | `GraphicsCanvas` | `GraphicsCanvas` *or* `ScreenDocument` (backend dispatches) |
| `ScreenDocument` / `WindowDocument` | Don't exist | Ordinary projectional documents; can be input or output |
| New projection types | — | None. Use existing `RecursiveProjection` + `TypeDispatchingProjection` + `CopyingProjection`. |
| `Window` device | Conflated "we render here" with "the SDL window's title/size" | Split: `Screen <: Device` describes the hardware target; native SDL window resources are a backend-internal record |
| `application` signature | `(backend, projection, document; title, width, height)` | `(backend, projection, document)` — window metadata lives on `WindowDocument` |
| `IoMap.output` | `GraphicsCanvas` | Widened |
| `SdlBackend` | One `write_to_devices` method | Two methods: `GraphicsCanvas` and `ScreenDocument` |
| `read_from_devices` | Returns bare event | Returns `EventEnvelope { window_id, event }` |
| Opening / closing a window | Implicit | Mutation of the input `ScreenDocument` (or a different projection output) |
| Distinguished main window | Yes | No |
| Tooltip / preview / debugger | Not supported | Just another `WindowDocument` |

The change is fully additive. Existing pipelines keep working.
New multi-window pipelines are built with existing projection
primitives and two new document types.
