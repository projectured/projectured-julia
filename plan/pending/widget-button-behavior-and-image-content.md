# Widget Button Behavior + Image Content

> **Note:** This document was generated with AI assistance as a planning
> artifact. It is a design proposal grounded in the current code, not a frozen
> specification. Evaluate and adapt each decision before implementing.

## Summary

Two related extensions to the widget domain, both staying inside the existing
**event → operation → `evaluate_operation` → reactive re-render** discipline:

1. **Make `WidgetButton` interactive.** Today its
   [`projection_read`](../../package/domain/src/projection/primitive/WidgetToGraphics.jl)
   returns `nothing` — the button is inert. We give it:
   - **mouse-over feedback** — a transient `hovered` flag that re-styles the
     button while the pointer is inside it;
   - **press feedback** — a transient `pressed` flag for the held-down look;
   - **click → call a function on the widget** — a `WidgetButton.action`
     callable invoked through a new `InvokeWidgetActionOperation`;
   - **state-driven graphics** — the printer reads `hovered`/`pressed`
     reactively and picks the fill, so the render updates with no extra plumbing
     (the same pattern `WidgetSplitPane` already uses for its drag state).

2. **Let a widget show an image as its content.** `WidgetButton.content` (and
   `WidgetLabel.content`) is `Any` and is currently `string(...)`-ified. We
   teach the printer to accept an `ImageDocument` (`ImageFile` / `ImageMemory`,
   already in the [image domain](../../package/domain/src/document/Image.jl)) and
   emit a `GraphicsImage` — the same primitive inline text images already use.

Neither piece invents a new output type or touches the backend render loop:
buttons reuse the existing operation pipeline, and image content reuses the
`GraphicsImage` element the SDL/PDF backends already draw.

---

## Background — what already exists

Established mechanisms this plan builds on (all verified in the current tree):

- **Operation pipeline.** A reader returns an `Operation`; it bubbles up the
  projection chain (containers prefix references via `prepend_steps_to_op`);
  the editor runs `evaluate_operation(editor, op)`. Readers stay side-effect
  free — all mutation happens in `evaluate_operation`. See
  [editor.md](../../documentation/editor.md).
- **Transient UI state on a widget.** `WidgetSplitPane` keeps an in-progress
  drag on `active_splitter` / `drag_anchor` / `pinned` `Cell`s, documented as
  *"transient UI state… not meant to be serialised"*, mutated by
  `Start/Resize/EndSplitterDragOperation`, and read back by the printer so the
  layout re-renders. Button hover/press state follows this precedent exactly.
- **Leaf control emitting an operation on click.** `WidgetCheckbox`'s reader, on
  `MousePress`, returns
  `ReplaceReferencedValue(w, content, new_value)`; a configuring projection
  (`ObjectToWidget` / `ProjectionConfiguring`) can intercept it by control
  identity. This is the "value-bound control" model — relevant to one of the
  action design options below.
- **Container event routing.** `_route_to_children` / `_route_composite_event`
  hit-test a coordinate event against each child canvas and deliver it to the
  **first hit child**, returning its op. Currently wired for `MouseScroll` and
  `MousePress` only — *not* `MouseMove`. This is the crux of the hover design.
- **Pointer-driven hover precedent.** `HoverProbeProjection` already reverse-
  projects `MouseMove` (feeding a synthetic `MousePress` through the inner
  reader) to discover what is under the pointer and drives a follower window. A
  hover *tracker* for widgets is the same shape.
- **Image plumbing.** `GraphicsImage(x, y, w, h, data)` is rendered by the SDL
  backend (`_render_image!`) and PDF backend; `data` is `(pixels, nw, nh)` /
  `Ptr` / `Vector{UInt8}`. `ImageFile.raw` is filled by `decode_image_file!`
  (`sdl_decode_image`). `TextToGraphics` already turns a `TextGraphics`
  span → `GraphicsImage` by reading `content.raw` via `_extract_image_data`.
  Widget image content reuses this seam.

---

## Part 1 — Button behavior

### 1.1 Document changes (`document/Widget.jl`)

Add an action and two transient state flags to `WidgetButton`:

```julia
@document struct WidgetButton <: WidgetDocument
    position::Point2D
    size::Point2D
    content::Any
    action::Any        # 0- or 1-arg callable, or nothing  (NOT serialised behaviour)
    # …existing box-model fields…
    selection::Reference
    hovered::Bool      # transient UI state — pointer is inside the button
    pressed::Bool      # transient UI state — left button held down on it
end
```

- `action` defaults to `nothing`; the constructor gains an `action=nothing`
  keyword. `hovered` / `pressed` default to `false` and are documented as
  transient (mirroring the `WidgetSplitPane` docstring) — printer-read,
  reader-written, never persisted.
- Keep the positional `WidgetButton(position, size, content; …)` signature
  backward compatible.

### 1.2 Operations (`document/Widget.jl`)

```julia
struct InvokeWidgetActionOperation <: Operation
    widget::WidgetDocument
end

struct SetWidgetHoverOperation <: Operation
    widget::WidgetDocument
    value::Bool
end

struct SetWidgetPressedOperation <: Operation
    widget::WidgetDocument
    value::Bool
end
```

`evaluate_operation` methods:

- `InvokeWidgetActionOperation` — call `w.action` if it is callable. Pass the
  editor when the function accepts it, so the action can mutate
  `editor.document` / projection state:
  `applicable(w.action, editor) ? w.action(editor) : w.action()`. A `nothing`
  action is a no-op.
- `SetWidgetHoverOperation` / `SetWidgetPressedOperation` — set the
  corresponding `Cell` (idempotent; writing the same value is cheap and the
  reactive system already de-dupes unchanged cells).

> A single `SetWidgetFlagOperation(widget, field::Symbol, value::Bool)` could
> collapse the two flag ops. Decide during implementation; two explicit structs
> are clearer and match the codebase's preference for named operations.

### 1.3 Reader (`projection/primitive/WidgetToGraphics.jl`)

Replace the inert `projection_read(::WidgetButtonToGraphicsCanvas, …, evt) =
nothing` with an `@event_case` reader on the button's `SimpleIoMap`:

| Event | Returns |
|---|---|
| `MousePress(:left)` | `InvokeWidgetActionOperation(w)` |
| `MouseDown(:left)` | `SetWidgetPressedOperation(w, true)` |
| `MouseUp(:left)` | `SetWidgetPressedOperation(w, false)` |
| `MouseMove` | `SetWidgetHoverOperation(w, true)` (only the pointer-is-inside half — see 1.5) |
| _other_ | `nothing` |

The reader only ever runs when the parent container hit-tested the pointer onto
the button, so every event it sees is already "inside". `MousePress` is the
synthesized click (down+up on the same target), so the action fires there;
`MouseDown`/`MouseUp` exist purely for the pressed-look.

### 1.4 State-driven printer (`projection/primitive/WidgetToGraphics.jl`)

`WidgetButtonToGraphicsCanvas` already owns its style params (`background_color`,
`border`, `label`, `padding`, `corner_radius`, `shadow_offset`). Extend it with
hover/active/pressed fills supplied by the factory from the theme:

- add `hover_color`, `active_color` (pressed) — e.g. `theme.accent` /
  `theme.muted`, and optionally a `disabled_color`/`disabled_label` for
  `action === nothing`.
- in `projection_print`, choose the fill reactively:
  `w.pressed ? p.active_color : w.hovered ? p.hover_color : p.background_color`,
  and drop the soft-shadow rect while pressed (the standard "button sinks"
  affordance). Because the printer reads `w.hovered` / `w.pressed` cells, the
  reactive cache invalidates exactly those buttons on a state change.

Wire the new fields in the `WidgetToGraphics(...)` factory's `WidgetButton`
entry; both light and dark themes already expose `accent` / `muted`.

### 1.5 Design decision — hover-out (pointer leaving the button)

`_route_to_children` delivers a move only to the **hit** child, so a button
learns when the pointer *enters* but never when it *leaves* (the leaving move
goes to whatever is under the pointer now, or nowhere). Three options:

**Option A — hover tracker (recommended).** A thin higher-order
`WidgetHoverTrackingProjection` wrapping the widget pipeline, modeled on
`HoverProbeProjection`. It holds `last_hovered::Ref{Any}`. On `MouseMove`:
forward the move to `inner` (which, with the small routing addition below,
reaches the hit button and yields `SetWidgetHoverOperation(w, true)`); read the
target widget off that op; if it differs from `last_hovered`, return a
`CompoundOperation([SetWidgetHoverOperation(old, false), <the new op>])` and
update `last_hovered`. Pointer over dead space ⇒ inner yields nothing ⇒ clear
the old. Centralizes the clear in one place, no per-container bookkeeping,
naturally handles "leave to nothing". Press-clear rides along: any `MouseUp`
clears `pressed` on `last_hovered`.

  Requires one routing addition: containers must forward `MouseMove` to the hit
  child (today only `MouseScroll`/`MousePress` are routed). Add `MouseMove` to
  the `@event_case` in the composite/menu/shell/etc. readers using the existing
  `_route_*` helper — mechanical and additive.

**Option B — broadcast to all children.** Containers forward `MouseMove` to
*every* child; the hit one returns hover-true, the rest hover-false; collect into
a `CompoundOperation`. No central tracker, but every container's MouseMove path
must fan out and merge N ops, and reference-prefixing must map over compound
members. More invasive than A.

**Option C — editor-level hovered-widget field.** The kernel editor tracks the
hovered widget. Simplest logic, but pushes widget concerns into the backend-
agnostic editor and is the least composable. Reject unless A/B prove awkward.

Recommendation: **Option A**. It reuses the `HoverProbe` shape, keeps hover
logic in the widget/projection layer, and the only shared change (route
`MouseMove` to the hit child) is independently useful.

### 1.6 The "call function on widget" model

Two models, not exclusive:

- **Action callable on the widget (recommended, primary).** `WidgetButton.action`
  + `InvokeWidgetActionOperation` (above). The function lives on the widget and
  runs in the evaluate phase with editor access — the literal interpretation of
  the request and the most direct way to script a button.
- **Bound-parameter interception (secondary).** Like the checkbox, a button with
  no `action` can let a configuring projection intercept
  `InvokeWidgetActionOperation` by widget identity (e.g. `ObjectToWidget`
  growing button support to fire a method on the projected object). Documented
  as the extension point; not required for v1.

---

## Part 2 — Image as widget content

### 2.1 Accept an `ImageDocument` in `content`

`content` stays `Any`. Teach the leaf-widget printers to branch on it. Add a
shared helper in `WidgetToGraphics.jl`:

```julia
# Returns (kind, w, h, payload):
#   :text  → measured string  (existing path)
#   :image → GraphicsImage-ready (natural_w, natural_h, raw_data)
_content_render(p, content) = …
```

- `content isa ImageDocument` → read `content.raw`. When it is
  `(pixels, nw, nh)`, the natural size is `(nw, nh)`; emit
  `GraphicsImage(x, y, w, h, content.raw)` centered in the content box (same
  centering math the button uses for its label). When `raw === nothing` (not yet
  decoded), render a muted placeholder rect at the requested/natural box so
  layout is stable.
- everything else → `string(content)` (unchanged).

Apply to **`WidgetButton`** and **`WidgetLabel`** in v1 (the two the request
targets). The helper makes extending to `WidgetMenuItem` / `WidgetBadge` / cells
later a one-line change; list that as follow-up, not v1 scope.

### 2.2 Sizing

- **Button:** `button_w = max(size.x, content_w + 2·pad_x)` with `content_w`/`_h`
  from the image natural size instead of text metrics; center the
  `GraphicsImage` exactly as the label is centered.
- **Label:** size to the image natural size (label currently sizes to text).
- Optional: allow an explicit display size (scale the image into a smaller box —
  `_blit_rgba!`/`SDL_RenderCopy` already scale `nw×nh → w×h`). Keep v1 to natural
  size unless the widget's `size` is smaller, then fit.

### 2.3 Design decision — where does an `ImageFile` get decoded?

The widget printer is in the **backend-agnostic domain layer**; it must not call
`sdl_decode_image`. `ImageFile.raw` is populated by `decode_image_file!` (SDL).
Mirror how inline text images resolve this:

- **Printer is pure:** it only *reads* `content.raw`; missing ⇒ placeholder.
- **A decode pass fills `raw`:** the editor/example wiring runs
  `decode_image_file!` over `ImageFile`s before/at first print (the same seam
  inline images use). For `ImageMemory`, `raw` is supplied by the caller and
  needs no decode.

Document this seam explicitly; do not let the domain layer reach into SDL.

---

## Part 3 — Examples, tests, docs

### Examples (`package/example/src/document/Widget.jl`, `Examples.jl`)

- `make_widget_button_action_example` — a button whose `action` increments a
  counter shown by a sibling `WidgetLabel` (a `WidgetComposite` of the two), so
  click → re-render is visible via `run_example` / `play_live_example`.
- `make_widget_button_image_example` — a `WidgetButton` (and/or `WidgetLabel`)
  whose `content` is an `ImageFile` of a small bundled asset.
- Register both in the `Examples.jl` table and the `widget_*_example` exports.

### Tests (`package/test/src/projection/…`)

Narrow scope per [CLAUDE.md](../../CLAUDE.md) — do not run `test_all`:

- `test_printer(widget_button_example)` — button renders unchanged (regression).
- Reader unit tests on `WidgetButtonToGraphicsCanvas`:
  `MousePress(:left)` → `InvokeWidgetActionOperation`; `MouseDown`/`MouseUp` →
  pressed ops; `MouseMove` → hover op.
- `evaluate_operation(editor, InvokeWidgetActionOperation(w))` runs `w.action`
  (assert the side effect, e.g. counter incremented).
- Hover tracker (Option A): a `MouseMove` onto button B after button A clears
  A's `hovered` and sets B's (assert the `CompoundOperation`).
- Image content: `test_printer` over the image example produces a
  `GraphicsImage` element of the expected size; `write_example_image(...)` smoke
  render. Placeholder path when `raw === nothing`.

### Docs

- [documentation/document/widget.md](../../documentation/document/widget.md):
  update the `WidgetButton` row (action + hover/press), the operations table
  (the three new ops), and a short "image content" note under leaf widgets.
- This plan moves to `plan/done/` with an "Implementation Steps Completed"
  section when finished.

---

## Suggested order of work

1. `WidgetButton` fields (`action`, `hovered`, `pressed`) + the three operations
   and their `evaluate_operation` methods. (Part 1.1–1.2)
2. Button reader: click → action; down/up → pressed; move → hover. (1.3)
3. State-driven printer fills + factory wiring; verify with an example image. (1.4)
4. Hover-out: route `MouseMove` to the hit child in containers + the hover
   tracker. (1.5)
5. Image content helper + button/label printers + decode seam. (Part 2)
6. Examples, tests, docs. (Part 3)

Steps 1–3 already deliver "click calls a function + pressed feedback"; step 4
completes mouse-over feedback; steps 5–6 add image content. Each step is
independently testable with the narrow `test_printer` / reader tests above.

---

## Open questions

- **One flag op vs two?** `SetWidgetHoverOperation`/`SetWidgetPressedOperation`
  vs a generic `SetWidgetFlagOperation(widget, field, value)`.
- **Action arity / signature.** `action(editor)` vs `action()` vs passing the
  widget too. Proposal: accept both via `applicable`.
- **Disabled state.** Treat `action === nothing` as disabled (muted fill, no
  hover/press)? Or a separate `enabled` flag?
- **Image display size.** Natural size only in v1, or honor `size` as a scale
  box from the start?
- **Generalize image content** beyond button/label now, or land those two and
  extend the shared helper later?
