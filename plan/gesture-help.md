# Gesture Help (Ctrl-?)

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> A special gesture (Ctrl-?) that introspects the projection pipeline to display
> all gestures currently available in the editor state.

---

## Motivation

The user has no way to discover which gestures are active at any given moment.
Gestures are scattered across projections (`TextToGraphics` handles arrow keys,
`FocusingProjection` handles Ctrl-comma/period, `WidgetToGraphics` handles
scroll, etc.) and which ones apply depends on the current document type,
selection, and active projection pipeline. A help overlay that queries the
actual readers removes guesswork.

---

## Design Summary

When the user presses **Ctrl-?** (Ctrl-Shift-/ on most layouts):

1. The editor intercepts the event before normal `projection_read` dispatch.
2. It calls a new **`projection_available_gestures`** function that walks the
   projection pipeline (using the current `iomap`) and collects gesture
   descriptors from every reader that could handle an event in the current state.
3. The collected gestures are displayed as a temporary overlay (tooltip-style
   popup or full-screen panel) projected via the existing pipeline.
4. Pressing Escape (or any other key) dismisses the overlay and returns to
   normal editing.

---

## Core Concept: `projection_available_gestures`

Each projection that implements `projection_read` also implements:

```julia
projection_available_gestures(projection, iomap) -> Vector{GestureDescriptor}
```

This function returns a list of gestures the projection *could* handle in the
current state (given the current iomap contents — selection, focus, document
shape, etc.). Projections that have no gestures return an empty vector.

A default fallback on `Projection` returns `GestureDescriptor[]`.

---

## Domain Types

```julia
struct GestureDescriptor
    trigger::String          # human-readable trigger, e.g. "Ctrl-," or "Left click"
    description::String      # what it does, e.g. "Navigate focus out (unfocus)"
    category::Symbol         # :navigation, :editing, :selection, :focus, :scroll, ...
    source::String           # projection name, e.g. "FocusingProjection"
    available::Bool          # true if the gesture would produce an operation right now
end
```

- **`trigger`** — the key combo or mouse action.
- **`description`** — short human description.
- **`category`** — for grouping in the display.
- **`source`** — which projection provides it (for debugging/filtering).
- **`available`** — whether the gesture would actually succeed given the current
  state (e.g. "Ctrl-," is only available when focus part is non-empty).

---

## Gathering Gestures Through the Pipeline

### SequentialProjection

Walk each step from last to first (same order as `projection_read`) and
concatenate all gesture descriptors. This mirrors the reader's try-each-step
semantics.

```julia
function projection_available_gestures(seq::SequentialProjection, iomap::SequentialProjectionIoMap)
    gestures = GestureDescriptor[]
    for i in length(seq.projections):-1:1
        append!(gestures, projection_available_gestures(seq.projections[i], iomap.step_iomaps[i]))
    end
    gestures
end
```

### AlternativeProjection

Delegate to the active branch:

```julia
function projection_available_gestures(ap::AlternativeProjection, iomap::AlternativeProjectionIoMap)
    projection_available_gestures(ap.projections[iomap.index], iomap.inner_iomap)
end
```

### NestingProjection / RecursiveProjection

Delegate to the inner projection using the child iomap.

### Leaf projections (TextToGraphics, FocusingProjection, etc.)

Each implements the method by returning descriptors for its known gestures,
conditionally marking `available` based on current state.

---

## Example: FocusingProjection

```julia
function projection_available_gestures(p::FocusingProjection, iomap::SimpleIoMap)
    gestures = GestureDescriptor[]
    push!(gestures, GestureDescriptor(
        "Ctrl-,", "Navigate focus outward (unfocus one level)",
        :focus, "FocusingProjection", !isempty(p.part)
    ))
    has_sel = hasproperty(iomap.input, :selection) &&
              iomap.input.selection !== nothing &&
              !isempty(iomap.input.selection)
    push!(gestures, GestureDescriptor(
        "Ctrl-.", "Focus into selected element",
        :focus, "FocusingProjection", has_sel
    ))
    gestures
end
```

## Example: TextToGraphics

```julia
function projection_available_gestures(p::TextToGraphics, iomap::TextToGraphicsIoMap)
    has_cursor = _cursor_position(iomap.input.selection) !== nothing
    [
        GestureDescriptor("Left",      "Move cursor left",           :navigation, "TextToGraphics", has_cursor),
        GestureDescriptor("Right",     "Move cursor right",          :navigation, "TextToGraphics", has_cursor),
        GestureDescriptor("Up",        "Move cursor up one line",    :navigation, "TextToGraphics", has_cursor),
        GestureDescriptor("Down",      "Move cursor down one line",  :navigation, "TextToGraphics", has_cursor),
        GestureDescriptor("Home",      "Move to start of line",      :navigation, "TextToGraphics", has_cursor),
        GestureDescriptor("End",       "Move to end of line",        :navigation, "TextToGraphics", has_cursor),
        GestureDescriptor("Ctrl-Home", "Move to start of document",  :navigation, "TextToGraphics", true),
        GestureDescriptor("Ctrl-End",  "Move to end of document",    :navigation, "TextToGraphics", true),
        GestureDescriptor("Click",     "Place cursor at position",   :selection,  "TextToGraphics", true),
    ]
end
```

---

## Display

### Option A: Overlay document (preferred, simple)

When Ctrl-? is pressed:

1. Build a `GestureHelpDocument` containing the collected `Vector{GestureDescriptor}`.
2. Temporarily swap the editor's active document/projection to display the help
   (similar to the log overlay approach in `logging.md`).
3. The help projection (`GestureHelpToSyntax → SyntaxToText → TextToGraphics`)
   renders a categorized table:
   ```
   ── Navigation ──────────────────────────
   Left          Move cursor left              [TextToGraphics]
   Right         Move cursor right             [TextToGraphics]
   ...
   ── Focus ────────────────────────────────
   Ctrl-,        Navigate focus outward        [FocusingProjection]  ✓
   Ctrl-.        Focus into selected element   [FocusingProjection]  ✗ (no selection)
   ```
4. Any key dismisses the overlay.

### Option B: Tooltip popup

Display the gestures in a `WidgetTooltip` anchored to the cursor position.
Richer but requires widget layout to be in place.

Start with **Option A**.

---

## Steps

### 1. Add `:question_mark` to `KeyPress` vocabulary

Update `Keyboard.jl` symbol list documentation. Ensure the SDL backend maps
Shift-/ (or the `?` key on international layouts) to `:question_mark`.
Verify `ctrl` flag is set when Ctrl is held.

### 2. Define `GestureDescriptor` struct

New file `program/src/document/GestureHelp.jl`:
- `GestureDescriptor` struct
- `GestureHelpDocument` (wraps a `Vector{GestureDescriptor}`)
- Include in `Projectured.jl`

### 3. Define `projection_available_gestures` API

Add to `program/src/api/Projection.jl`:
```julia
function projection_available_gestures end
```

Add default fallback in `program/src/common/Projection.jl`:
```julia
projection_available_gestures(::Projection, iomap) = GestureDescriptor[]
```

### 4. Implement for higher-order projections

- `SequentialProjection` — concatenate from all steps
- `AlternativeProjection` — delegate to active branch
- `NestingProjection` — delegate to inner
- `RecursiveProjection` — delegate to inner

### 5. Implement for leaf projections

Start with the most impactful ones:
- `TextToGraphics` (arrow keys, home/end, click)
- `FocusingProjection` (Ctrl-comma, Ctrl-period)
- `SyntaxToText` (character insertion, backspace, delete)
- `WidgetToGraphics` variants (scroll, tab selection)
- `WorkbenchToWidget` (if it handles keys)

Others can return empty and be filled in incrementally.

### 6. Intercept Ctrl-? in `read!`

In `Editor.read!`, before calling `projection_read`, check if the event is
`KeyPress(:question_mark, true)`. If so:
- Call `projection_available_gestures(editor.projection, editor.iomap)`
- Store result and set a flag indicating help mode is active
- On next event (any key/click), clear the flag and resume normal operation

### 7. `GestureHelpToSyntax` projection (printer)

A simple projection that takes a `GestureHelpDocument` and produces a
`SyntaxDocument` with categorized rows. Reuse existing syntax/text/graphics
pipeline for rendering.

### 8. Help overlay rendering

When help mode is active, `print!` renders the `GestureHelpDocument` instead
of the normal document. This is a temporary swap — no permanent state change.

---

## Open Questions

- **Conditional availability** — some gestures are always available (click),
  others depend on state (arrow keys need a cursor). How granular should
  `available` be? Start with coarse (has cursor / has selection / has focus)
  and refine later.
- **Mouse gestures** — clicks and scrolls are position-dependent. Should we
  list "Click on element X" per-element, or just "Left click — select element"
  generically? Start generic.
- **Gesture conflicts** — `SequentialProjection` tries steps last-to-first and
  the first handler wins. Should the help display indicate priority/shadowing?
  Nice-to-have but not essential for v1.
- **Internationalization** — trigger strings are currently English. Acceptable
  for now.
- **Performance** — `projection_available_gestures` only runs on Ctrl-?, not
  every frame. No performance concern.

---

## Dependencies

- Requires `KeyPress` to support `:question_mark` (or `:slash` with shift
  detection) — minor SDL backend change.
- Display reuses existing `SyntaxToText → TextToGraphics` pipeline.
- No dependency on logging or drag-and-drop plans.
