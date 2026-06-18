# Gesture Help (Ctrl-?)

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> A special gesture (Ctrl-?) that asks the projection pipeline to describe every
> gesture currently available in the editor state — using the **same** reader
> declarations that actually dispatch the gestures, so the mapping is written
> exactly once.

---

## Motivation

The user has no way to discover which gestures are active at any given moment.
Gestures are scattered across projections (`TextToGraphics` handles arrow keys,
`FocusingProjection` handles Ctrl-comma/period, `WidgetToGraphics` handles
scroll, etc.) and which ones apply depends on the current document type,
selection, and active projection pipeline.

The hard requirement is **one source of truth**: the gesture → operation mapping
of every reader must be expressed *once*, and both (a) the actual operation that
fires and (b) the context-sensitive help text must be derived from that single
declaration. A second, parallel "list of available gestures" API would inevitably
drift out of sync with what the readers really do.

---

## Prior art: how projectured-lisp did it

The Lisp version already solved this, and the mechanism is the model for this
plan. The relevant files:

- `source/editor/command.lisp` — the `command` class and the `gesture-case` macro.
- `source/document/t.lisp` — `operation/show-context-sensitive-help` and the
  backward-recursion of that operation through the pipeline.
- `source/projection/primitive/help-to-text.lisp` — the projection that renders
  the help.

### The reader pipeline traffics in `command`, not bare operations

A Lisp `command` bundles everything a gesture binding needs:

```lisp
(def class* command ()
  ((domain :type string)        ; category, e.g. "Focusing"
   (description :type string)   ; human description
   (gesture :type gesture)      ; the trigger
   (accessible :type boolean)   ; would it actually succeed right now?
   (operation :type operation)));the change to apply
```

Every reader receives a command (carrying the gesture) and returns a command
(carrying the operation). This is exactly Julia's `Change`, except `Change`
currently carries only `gesture` + `operation` — it is missing the
`domain`/`description`/`accessible` metadata.

### `gesture-case`: the single source of truth

```lisp
(def reader focusing ()
  (merge-commands
    (gesture-case -gesture-
      ((make-key-press-gesture :scancode-comma :control)
       :domain "Focusing" :description "Moves the focus one level up"
       :operation (when (part-of -projection-) (make-instance 'operation/focusing/replace-part ...)))
      ((make-key-press-gesture :scancode-period :control)
       :domain "Focusing" :description "Moves the focus to the selection"
       :operation (make-instance 'operation/focusing/replace-part ...)))
    ...recursed/backward command...
    (make-nothing-command (gesture-of -input-))))
```

The macro expands each case **once** into two roles:

1. **Help role.** If the incoming gesture is the help key (Ctrl-H in Lisp), the
   macro builds an `operation/show-context-sensitive-help` whose `commands` slot
   is a descriptor for *every* case — `gesture` + `domain` + `description` +
   `accessible` — **without evaluating any case's `:operation`**.
2. **Dispatch role.** Otherwise, the first case whose gesture matches has *its*
   `:operation` form evaluated (lazily — only that branch) and returned as the
   command's operation.

So the same `(gesture :domain … :description … :operation …)` list serves both
the help and the actual dispatch. There is no second table.

### `merge-commands` accumulates help across the pipeline

Each reader stage produces help for *its own* gestures. As commands flow back up
the pipeline, `merge-commands` unions two `show-context-sensitive-help`
operations' command lists (dedup by gesture):

```lisp
(if (and (typep (operation-of c1) 'operation/show-context-sensitive-help)
         (typep (operation-of c2) 'operation/show-context-sensitive-help))
    ;; append c1's commands + c2's commands not already present (by gesture=)
    ...)
```

The help operation also rides the *normal* backward machinery
(`operation/read-backward` / `operation/extend` have a
`operation/show-context-sensitive-help` case) so each descriptor's references are
mapped one domain inward at every step, and a command whose extension fails is
marked `:accessible #f`. That is what greys out gestures that exist downstream
but cannot apply in the current context.

### Display reads the operation's command list

`help/context-sensitive->text/text` does nothing more than iterate
`(available-commands-of -input-)` and emit, per command, the gesture text +
domain + description, colored by `accessible-p`. No enumeration API — it just
renders the operation that `gesture-case` already produced.

---

## Design Summary (Julia)

Mirror the Lisp design rather than inventing a parallel enumeration API.

When the user presses **Ctrl-?**:

1. The editor seeds the usual nothing-`Change` carrying the gesture and calls
   `projection_read` as normal — **no special interception in `read!`**.
2. Readers built with the new `@gesture_case` recognize the help gesture and,
   instead of firing one operation, return a `ShowContextSensitiveHelpOperation`
   listing every gesture they declare (each as a `GestureDescriptor`).
3. Higher-order readers (`SequentialProjection`, alternatives, dispatchers) merge
   the help operations coming from every relevant step, so the descriptors from
   the whole active pipeline accumulate (Julia analogue of `merge-commands`).
4. The editor recognizes `ShowContextSensitiveHelpOperation` as the operation,
   and `evaluate!`/`print!` overlays a help document built from its descriptor
   list, rendered through a `HelpToText → … → graphics` pipeline.
5. Any next key/click dismisses the overlay.

The crucial property: **`@gesture_case` is the only place a gesture binding is
written.** Both the dispatched operation and the help descriptor come out of it.

---

## Core mechanism: `@gesture_case`

A macro used inside readers. One call replaces the ad-hoc
`if gesture_matches(…) … elseif … end` chains that readers write today, and
makes them help-aware for free.

```julia
@gesture_case(gesture,
    case(key_press(:comma; ctrl = true);
         domain      = "Focusing",
         description  = "Move focus one level up",
         accessible  = !isempty(projection.part),
         operation   = FocusReplacePartOperation(projection, parent_part(projection))),
    case(key_press(:period; ctrl = true);
         domain      = "Focusing",
         description  = "Focus into the selection",
         accessible  = has_selection(input),
         operation   = FocusReplacePartOperation(projection, selection_part(input))),
)
```

Expansion (sketch):

```julia
let g = gesture
    if is_help_gesture(g)
        ShowContextSensitiveHelpOperation(GestureDescriptor[
            GestureDescriptor(key_press(:comma;  ctrl=true), "Focusing", "Move focus one level up", (!isempty(projection.part))),
            GestureDescriptor(key_press(:period; ctrl=true), "Focusing", "Focus into the selection", (has_selection(input))),
        ])
        # note: the :operation forms are NOT spliced here — only gesture/domain/
        # description/accessible are evaluated to build descriptors.
    elseif gesture_matches(g, key_press(:comma; ctrl=true))
        FocusReplacePartOperation(projection, parent_part(projection))   # only this branch's operation form
    elseif gesture_matches(g, key_press(:period; ctrl=true))
        FocusReplacePartOperation(projection, selection_part(input))
    else
        nothing
    end
end
```

- Each case's `operation` expression is spliced **only** into its own dispatch
  branch, so it is evaluated lazily exactly as the Lisp `:operation` form is —
  side-effect-free guards like `when (part-of …)` translate to the operation
  expression returning `nothing`.
- The `accessible` expression is evaluated only when building descriptors; it
  feeds `GestureDescriptor.available`.
- The reader wraps the macro's result back into a `Change(gesture, op)` (or the
  macro can yield the `Change` directly).

This keeps every concrete binding — gesture, category, human text, guard, and the
operation — in one `case(...)` declaration.

---

## Domain types

```julia
struct GestureDescriptor
    gesture::Any          # the trigger gesture object (so display can describe it, and merge can dedup)
    domain::String        # category, e.g. "Focusing", "Navigation"
    description::String   # short human description
    available::Bool       # would it fire in the current state?
end

struct ShowContextSensitiveHelpOperation <: Operation
    commands::Vector{GestureDescriptor}
end
```

- `GestureDescriptor` is produced *only* by `@gesture_case`; it is never written
  by hand alongside a binding.
- Reuse the existing gesture-describing helpers (the Julia equivalents of
  `describe-gesture-modifiers` / `describe-gesture-keys`) to render
  `descriptor.gesture` as `"Ctrl-,"` etc. — the trigger string is derived, not
  stored, so there is no separate copy to keep in sync.

---

## Accumulating through the pipeline (the `merge-commands` analogue)

Julia's `SequentialProjection` reader is *first-match-wins*: it tries steps
last-to-first and stops at the first step that yields an operation. That is
correct for normal dispatch but wrong for help, which must visit **every** step.

Plan: make the higher-order readers help-aware.

- **`SequentialProjection`** — when `change.gesture` is the help gesture, do not
  stop at the first step. Call each step's reader, collect every
  `ShowContextSensitiveHelpOperation` it returns, and union their
  `commands` (dedup by `gesture`). Return one merged help operation.
- **`AlternativeProjection` / dispatchers** — delegate help to the active branch
  (its reader's help already lists that branch's gestures).
- **Leaf readers** — produce their descriptor list straight from `@gesture_case`.

Define a small helper `merge_help(op1, op2)` (and `merge_help(changes...)`) that
encapsulates the union-by-gesture rule, mirroring `merge-commands`.

**Backward reference mapping (deferred refinement).** In Lisp the help operation
also flows through `operation/read-backward`, mapping each descriptor's
references inward and marking unmappable ones inaccessible. For v1, display needs
only gesture + domain + description (plain strings, domain-independent), so the
union can ignore reference mapping. Computing `available` precisely by mapping
each descriptor backward through the pipeline is a later refinement.

---

## Display

### Overlay document (preferred, simple)

When the operation comes back as a `ShowContextSensitiveHelpOperation`:

1. Wrap its `commands` in a `GestureHelpDocument`.
2. Temporarily swap the editor's active document/projection to display the help
   (same overlay approach as the logging plan).
3. A `HelpToText` (or `GestureHelpToSyntax → SyntaxToText → TextToGraphics`)
   projection renders a categorized table:
   ```
   ── Focusing ─────────────────────────────
   Ctrl-,        Move focus one level up
   Ctrl-.        Focus into the selection        (unavailable: no selection)
   ── Navigation ───────────────────────────
   Left          Move cursor left
   ...
   ```
   Greyed rows = `available == false` (Lisp colors these with lightened text).
4. Any key dismisses the overlay.

This mirrors `help/context-sensitive->text/text` directly.

---

## Steps

### 1. Gesture vocabulary for the help key

Ensure the help gesture is recognizable (`Ctrl-?` / `Ctrl-Shift-/`, or follow the
Lisp `Ctrl-H`). Add `is_help_gesture(gesture)` next to the existing gesture
predicates. Verify the SDL/`Keyboard.jl` backend delivers the modifier + key.

### 2. Add `GestureDescriptor` + `ShowContextSensitiveHelpOperation`

- `GestureDescriptor` struct.
- `ShowContextSensitiveHelpOperation <: Operation` carrying
  `Vector{GestureDescriptor}`.
- A no-op evaluator (it produces no document change; the editor handles it as an
  overlay, like Lisp's empty `(values)` evaluator).
- Export from `Projectured.jl`.

### 3. The `@gesture_case` macro

New macro (e.g. `program/src/editor/GestureCase.jl`):
- `case(gesture; domain, description, accessible = true, operation)` marker.
- Expand to the help-branch (build descriptors, operations **not** evaluated) +
  per-case dispatch branches (operation evaluated lazily) + `nothing` fallback.
- Returns an operation-or-`nothing` (reader wraps in `Change`), or a `Change`
  directly — pick one convention and document it.

### 4. `merge_help` + help-aware higher-order readers

- `merge_help` union-by-gesture helper.
- `SequentialProjection.projection_read`: help-gesture branch that visits all
  steps and merges.
- Alternative/dispatching readers: delegate to active branch.

### 5. Convert leaf readers to `@gesture_case`

Migrate the ad-hoc gesture matching in the highest-value readers so their
bindings become single-source and help-capable:
- `FocusingProjection` (Ctrl-comma / Ctrl-period).
- `TextToGraphics` (arrows, home/end, click).
- `SyntaxToText` (insert/backspace/delete).
- `WidgetToGraphics` variants (scroll, tab selection).

Readers not yet migrated simply contribute no help entries — incremental.

### 6. Editor + overlay rendering

- `read!` needs **no** special help interception — the help operation comes back
  through `projection_read` like any operation. `read!` just returns it.
- `evaluate!`/`print!`: when `editor.operation isa
  ShowContextSensitiveHelpOperation`, render the overlay instead of applying a
  document change; clear it on the next event.
- `HelpToText` (or `GestureHelpToSyntax → …`) projection for the table.

---

## Open questions

- **Lazy operation evaluation in the macro.** Julia macros splice expressions;
  ensure each `operation` form is emitted only in its matching branch so guards
  with side-effect-free `nothing` returns behave like the Lisp `:operation`
  forms. Confirm there are no readers whose operation expression must run for its
  side effects during matching (there should not be).
- **Per-reader merge vs. Sequential-level merge.** Lisp merges *inside every
  reader* (`merge-commands` is called by each). The pragmatic Julia adaptation
  merges at the `SequentialProjection` level. Is per-reader merge worth the extra
  uniformity, or is Sequential-level aggregation enough? Start with
  Sequential-level.
- **Precise `available` via backward mapping.** v1 marks `available` from the
  case's `accessible` guard only. Mapping descriptors backward through the
  pipeline (to grey out downstream gestures that cannot reach the current
  context) is the full Lisp behavior — defer.
- **Mouse/positional gestures.** Clicks/scrolls are position-dependent; list them
  generically ("Left click — select element") for now.
- **Should `Change` itself carry domain/description?** Lisp's `command` does. In
  Julia they are only needed inside `GestureDescriptor`, so `Change` can stay as
  `gesture` + `operation`. Revisit only if per-reader merge (above) is adopted.

---

## Dependencies

- A recognizable help gesture (`is_help_gesture`) — minor backend/predicate work.
- `@gesture_case` macro — the central new piece; everything else builds on it.
- Help-aware `SequentialProjection` reader (merge instead of first-wins for the
  help gesture).
- Display reuses the existing `SyntaxToText → TextToGraphics` pipeline.
- No dependency on the logging or drag-and-drop plans (shares the overlay idea
  with logging but not its code).
