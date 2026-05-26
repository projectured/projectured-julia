# Arbitrary Tooltip Support via Multi-Output Projections

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

## Summary

Extend the projection pipeline so that a single `projection_print` call can
produce **multiple** `GraphicsCanvas` documents — one per SDL window. The
editor's main window remains one output; additional outputs (tooltips, info
panels, previews) are rendered into separate SDL windows that the backend
manages independently. Tooltip content, positioning, and lifecycle are all
controlled by projections — no special-case tooltip rendering code exists
outside the projection system.

---

## Motivation

Currently the pipeline is 1-document-in → 1-canvas-out:

```
document → projection_print → IoMap { input, output::GraphicsCanvas }
                                          ↓
                              write_to_devices → single SDL window
```

This makes it impossible to show auxiliary information (type signatures,
documentation, error messages, previews) in a separate floating window
without bypassing the projection system entirely. By making the projection
output a **named collection of canvases**, each canvas maps to a window,
and tooltip logic lives inside projections where it belongs.

---

## Design

### Multi-canvas output

Instead of `IoMap.output::GraphicsCanvas`, the pipeline produces a
`MultiOutput`:

```julia
struct MultiOutput
    primary::GraphicsCanvas          # the main editor canvas (always present)
    secondaries::Dict{Symbol, GraphicsCanvas}  # :tooltip, :preview, …
end
```

The backend's `write_to_devices` inspects the `MultiOutput`:
- The `primary` canvas is rendered to the main `Window` (as today).
- Each entry in `secondaries` is rendered to its corresponding secondary
  window. If the window does not yet exist, the backend creates it; if the
  canvas is `nothing` (or the key is absent), the backend hides/destroys
  the secondary window.

This keeps the existing single-output path working unchanged — a projection
that returns a plain `GraphicsCanvas` is implicitly treated as
`MultiOutput(canvas, Dict())` via a trivial adapter.

### Tooltip projection

A new **domain-preserving** projection on the Graphics domain:

```julia
struct TooltipProjection <: Projection
    trigger::Function       # (document, selection) → Bool — when to show
    content::Function       # (document, selection) → Document — what to show
    inner_projection::Any   # projects tooltip content → GraphicsCanvas
    position::Function      # (primary_canvas, selection) → (x, y) — where
    delay_ms::Int           # hover delay before showing
end
```

This projection wraps the final graphics-producing step. Its printer:
1. Runs the wrapped projection to get the primary `GraphicsCanvas`.
2. Evaluates `trigger` against the current document + selection.
3. If triggered, runs `content` to get a tooltip document, projects it
   through `inner_projection` to get a tooltip `GraphicsCanvas`.
4. Returns a `MultiOutput` with the primary canvas and the tooltip canvas
   under `:tooltip`.

Its reader passes events through to the inner projection unchanged (the
tooltip is read-only for now; interactive tooltips are a future extension).

### Window management in the backend

`SdlBackend` gains a registry of secondary windows:

```julia
mutable struct SdlBackend <: Backend
    font_cache::Dict{Tuple{String,Int}, Ptr{Nothing}}
    secondary_windows::Dict{Symbol, Window}   # managed tooltip/preview windows
end
```

`write_to_devices` is extended:

```julia
function write_to_devices(backend::SdlBackend, devices, output)
    canvas, secondaries = if output isa MultiOutput
        output.primary, output.secondaries
    else
        output, Dict{Symbol, GraphicsCanvas}()
    end

    # Render primary canvas to main window (unchanged)
    for device in devices
        device isa Window && write_to_device(backend, device, canvas)
    end

    # Manage secondary windows
    for (name, sec_canvas) in secondaries
        _ensure_secondary_window!(backend, name, sec_canvas)
    end
    # Hide/destroy windows whose keys are no longer present
    for name in keys(backend.secondary_windows)
        if !haskey(secondaries, name)
            _close_secondary_window!(backend, name)
        end
    end
end
```

Secondary windows are:
- Borderless (SDL_WINDOW_BORDERLESS) for tooltip-style popups.
- Always-on-top relative to the main window.
- Positioned relative to the main window's screen coordinates (the
  projection provides a logical position; the backend translates to screen
  coordinates using `SDL_GetWindowPosition`).

### Tooltip lifecycle

| State | Condition | Action |
|-------|-----------|--------|
| Hidden | `trigger` returns `false` | No `:tooltip` key in `secondaries` → window hidden/destroyed |
| Pending | `trigger` returns `true`, timer < `delay_ms` | No window yet; timer ticking |
| Shown | `trigger` returns `true`, timer ≥ `delay_ms` | `:tooltip` canvas present → window created/updated |
| Dismissed | User presses Escape or moves selection away | `trigger` returns `false` → hidden |

Timer state lives in a cell on the `TooltipProjection` struct (or in the
IoMap) so it participates in the reactive system.

### Event routing for multi-window

SDL delivers events tagged with a `windowID`. Currently `read_from_devices`
ignores window IDs (there is only one window). With multiple windows:

1. Events on the **primary** window are handled as today.
2. Events on a **secondary** window are either:
   - Ignored (tooltip is non-interactive, the default).
   - Routed to the tooltip's own projection reader (future: interactive
     tooltips with clickable links, scrollable content).
3. Focus changes: clicking the tooltip window should not steal focus from
   the main editor. Use `SDL_WINDOW_TOOLTIP` flag or re-focus the main
   window on tooltip click.

---

## Implementation Steps

### Step 1: `MultiOutput` type and backward-compatible adapter

- Define `MultiOutput` in a new or existing module.
- Add a trivial conversion so existing projections that return a plain
  `GraphicsCanvas` are wrapped transparently.
- `write_to_devices` handles both `GraphicsCanvas` and `MultiOutput`.
- **No behavioral change yet** — all existing examples continue to work.

### Step 2: Secondary window management in `SdlBackend`

- Add `secondary_windows` field to `SdlBackend`.
- Implement `_ensure_secondary_window!` (create or update) and
  `_close_secondary_window!` (hide/destroy).
- Secondary windows are borderless, positioned, and non-focusable.
- Test by manually constructing a `MultiOutput` with a dummy tooltip canvas.

### Step 3: `TooltipProjection` — static tooltip

- Implement the projection struct with `trigger`, `content`,
  `inner_projection`, and `position`.
- Printer: evaluate trigger, project tooltip content, produce `MultiOutput`.
- Reader: pass-through to inner projection (tooltip non-interactive).
- No delay logic yet — tooltip appears immediately when triggered.
- Example: show the JSON path of the currently selected node.

### Step 4: Hover delay and dismissal

- Add timer logic (a `Cell{Float64}` holding the timestamp when trigger
  became true).
- Printer suppresses the tooltip canvas until `delay_ms` has elapsed.
- Dismissal clears the timer when trigger becomes false.
- The REPL loop's `sleep(0.01)` provides the frame cadence; the tooltip
  appears after enough frames have passed.

### Step 5: Event routing with window IDs

- Extend `read_from_devices` to tag events with the originating window ID.
- Main window events continue to the projection reader.
- Secondary window events are either discarded or (optionally) forwarded
  to the tooltip's reader for interactive tooltips.

### Step 6: Tooltip positioning and sizing

- `position` function receives the primary canvas geometry and the current
  selection's screen coordinates (from the IoMap's `char_to_coord`).
- Tooltip window is placed near the cursor, clamped to screen bounds.
- Tooltip canvas size determines window size (the window auto-sizes to fit
  its content, or uses a configurable maximum with scroll).

### Step 7: Configurable tooltip projections (examples)

- **Type tooltip**: for a JSON value, show its inferred schema.
- **Error tooltip**: for a node with validation errors, show the error.
- **Documentation tooltip**: for a Julia function call, show its docstring.
- **Preview tooltip**: for an image path, show a rendered thumbnail.

Each is a different `content` function + `inner_projection` pipeline,
demonstrating the generality of the approach.

---

## Open Questions

- **Multiple secondaries simultaneously** — can the editor show a tooltip
  *and* a preview panel at the same time? The `Dict{Symbol, GraphicsCanvas}`
  design supports this naturally, but managing overlapping popups adds UI
  complexity (z-ordering, dismissal priority). Start with one tooltip and
  generalize later.

- **Tooltip as a separate Editor** — should a tooltip have its own
  read-eval-print loop (its own `Editor` struct with its own projection and
  iomap)? This would make interactive tooltips straightforward (each tooltip
  is a mini-editor) but adds complexity. For read-only tooltips, a
  projection-only approach (no reader, no operations) is simpler.

- **Reactive timer** — the tooltip delay requires time awareness. The
  reactive cell system is event-driven, not time-driven. Options:
  (a) sample wall-clock time in the printer and invalidate on next frame;
  (b) add a `TimerCell` concept that self-invalidates after a duration;
  (c) handle the delay in the editor loop outside the projection. Option
  (a) is simplest and fits the existing frame-based loop.

- **Platform differences** — SDL tooltip windows behave differently across
  platforms (X11 vs Wayland vs macOS). `SDL_WINDOW_TOOLTIP` is an SDL hint
  that may not be respected everywhere. Fallback: use a regular borderless
  window with explicit repositioning.

- **Projection composability** — `TooltipProjection` wraps the final step
  of the pipeline. If multiple tooltip projections are composed (e.g.
  type tooltip + error tooltip), they need to merge their secondary outputs.
  A `MergeMultiOutputProjection` higher-order projection could combine
  `Dict`s from multiple inner projections.

---

## Relationship to Existing Architecture

| Concept | Current | With Tooltips |
|---------|---------|---------------|
| `projection_print` output | `IoMap{…, GraphicsCanvas, …}` | `IoMap{…, MultiOutput, …}` |
| `write_to_devices` | Renders one canvas to one window | Renders primary + secondaries to multiple windows |
| `SdlBackend` | Stateless (font cache only) | Manages secondary window lifecycle |
| `read_from_devices` | Ignores window IDs | Routes events by window ID |
| Tooltip content | N/A (not supported) | A projection producing a `GraphicsCanvas` |
| Tooltip trigger | N/A | A predicate on document + selection |

The change is **additive** — existing single-window pipelines work unchanged.
The only breaking change is the type of `IoMap.output` widening from
`GraphicsCanvas` to `Union{GraphicsCanvas, MultiOutput}`, which is handled
by the adapter in step 1.
