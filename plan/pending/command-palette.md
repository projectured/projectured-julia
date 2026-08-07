# Command palette

A user presses one hot key. A type-in field opens over the document. The user
types a few characters. A list below the field shows every command that matches
the text and that applies to the current selection. Enter runs the selected
command. Escape closes the field.

The palette gives an operation a way to reach the user without a key gesture and
without a mouse gesture. It is the type-in twin of the gesture-help window: the
help window *shows* what the context offers, the palette *runs* it.

## What exists already

Almost every part is in place.

- A gesture binding is reified data. It carries the operation as a closure, a
  description, a domain tag, and an `applicable` precondition —
  [GestureBinding.jl](../../package/kernel/main/binding/GestureBinding.jl).
- A collector gathers every binding reachable at a point in a projection chain —
  `collect_gesture_bindings` in
  [GestureBindings.jl](../../package/kernel/main/projection/GestureBindings.jl).
- A decorator opens the help window from F1 and fills it with that set —
  [GestureHelpDecorator.jl](../../package/domain/main/gesturemap/GestureHelpDecorator.jl).
- `GestureRow` already renders one binding as a line —
  [GestureMap.jl](../../package/domain/main/gesturemap/GestureMap.jl).
- `GraphicsCanvas` composes positioned children, so an overlay needs no new
  graphics type — [Graphics.jl](../../package/visual/main/graphics/Graphics.jl).

The palette therefore reuses the collector, the row type, and the widget stack.
It needs **one** change below the domain package. See "The one kernel change".

## The one kernel change

A binding cannot exist without a gesture today. `GestureBinding.pattern` is a
plain `EventPattern`. The feature is exactly "a command with no gesture", so the
field must accept `nothing`.

Three small edits, all in the unsealed binding layer:

1. `GestureBinding.pattern::Union{EventPattern,Nothing}`. `nothing` means the
   binding has no gesture and only a name reaches it.
2. `GestureBinding.name::Union{String,Nothing}` — the name a user types.
3. `fire_gesture_bindings` skips a binding whose pattern is `nothing`, so such a
   binding never fires from a key or a click.
4. `fire_named_gesture_binding(bindings, target, selection, name)` — the
   counterpart that selects a binding by name and passes `nothing` for the event.
5. `@gestures` accepts `nothing` in the pattern position of the rule form it
   already has. There is no new rule form and no new keyword:

```julia
@gestures JsonObject begin
    KeyDown(:k; ctrl) => "Sort the keys"  => SortKeysOperation(doc, sel)    # gesture + name
    nothing          => "Sort the values" => SortValuesOperation(doc, sel)  # name only
end
```

The rule keeps its three parts. The author writes in the pattern slot exactly
what the field holds. A reader of the table sees the absence of a gesture, and
does not have to know a second surface.

Three rules follow from the shape:

- A `nothing` rule **must** carry a description. The macro raises an error
  without one. A gesture rule derives its description from
  `describe_event_pattern`, and a `nothing` rule has nothing to derive it from.
  The description is also the name the user types, so it is not optional.
- A `nothing` rule binds no pattern variable, because there is no pattern. The
  operation body therefore reads `doc` and `sel` only.
- `override(nothing)` is an error. Override means "claim this key even when an
  output layer took it", and there is no key.

Two edits in `_parse_gesture_block` carry this. Match `nothing` in the pattern
position before the call to `parse_event_pattern_rule`, which expects a call
expression. Then emit the binding with a `nothing` pattern and the authored
description.

**The name lives on the binding, not on the row.** `@gestures` decides it once,
because only the macro knows whether the author wrote a description and whether
the rule reads the event. Everything downstream reads one field.

**How the macro knows the rule reads the event.** `build_event_field_bindings`
returns the body untouched when the rule binds no pattern variable, and wraps it
in a `let` when it does. The macro compares the result with the body it passed
in. The obvious test — `f isa BoundField` over `rule.fields` — is a layering
error, and `test_kernel_layering()` rejects it: `BoundField` is not exported from
the sealed `EventPattern.jl`, so no other module may name it.

The alternative is a second table of named operations beside the gesture table.
The architecture rejects that: what fires and what a listing shows must come
from one declaration. So widen the binding.

Nothing else in the kernel changes. There is no new event, no new operation, and
no change to the editor read loop.

## Why the palette is an overlay, not a window

The help window is a real window. The palette cannot be, and the reason is the
reader route.

`ScreenToScreen` prefixes `windows[i].content` to every operation that leaves a
window's chain — [ScreenToScreen.jl:180](../../package/visual/main/screen/ScreenToScreen.jl#L180).
A command that the palette runs edits the *content* document, not the palette.
If the palette were its own window, its operation would come out with the
palette window's path and would apply to the wrong place. Only an operation that
carries its own root (`ReplaceReferencedValueOperation` with a non-`nothing`
`document`) survives that route, and a command may return any operation type.

So the palette lives **inside the decorated window's chain**. Then Enter reaches
the decorator directly, the decorator returns the command's operation as its own
reader result, and every stage above reroots it exactly as if a key had fired
the binding. This is also the familiar placement for a user: the palette floats
over the document it acts on.

## Which bindings the palette can run

`collect_gesture_bindings` flattens the whole chain —
[Chaining.jl:165](../../package/base/main/projection/higherorder/Chaining.jl#L165).
A binding gathered at the text stage builds its operation against the *text*
document. The reader maps such an operation back to JSON by threading it
backward through the stages. A flat list has lost the stage, so the palette
cannot map it back.

The palette therefore separates two sets.

- **The run set** — the bindings of the decorator's own input document:
  `get_instance_gesture_bindings(input)` and
  `get_document_gesture_bindings(typeof(input))`. Their operations are already
  in the vocabulary the decorator returns, so the decorator runs them by calling
  `binding.operation(input, nothing)`. This is where every authored command
  belongs.
- **The show set** — everything else the collector returns. The palette lists
  these rows with their gesture and marks them "key only". They are navigation
  and text gestures that already have keys.

A binding is in the run set only when all three hold:

1. It belongs to the decorator's input document.
2. The author wrote a description, so it has a name to type.
3. Its rule binds no pattern variable, so the operation closure does not read
   the event. The macro knows this and records it.

A rule with no description keeps no name, because its description is the
auto-derived gesture rendering (`"Ctrl+K"`), which is not a command name.

## Design

### 1. The row carries a name and a run flag

`GestureRow` gets two fields: `name::Union{String,Nothing}` and
`runnable::Bool`. The help window ignores both. The palette uses both. One row
type serves both views, so they cannot drift apart.

A row for a binding with no gesture renders an empty gesture column.

### 2. The palette is a document

```julia
@document struct CommandPalette
    query::String       # what the user typed
    rows::CellVector    # every collected row, in collection order
end
```

The chosen row is the palette's **selection**. `@document` injects the
`selection` field, so the palette declares no index of its own. The reference is
`rows[i-1:i]`, the canonical "element `i` of this collection field" shape that
[WidgetList](../../package/visual/main/widget/Widget.jl) and `WidgetTable`
already use for a row. Two helpers mirror the widget pair:

```julia
command_palette_selection(i)        # -> rows[i-1:i], or nothing for no row
command_palette_selected(palette)   # -> the 1-based row index, or 0
```

The selection names a row of `rows`, not a row of the displayed subset. This
survives a re-filter: the chosen command stays chosen while the user types more
characters, as long as it still matches.

The projection computes the matching subset from `query` inside a reactive cell,
so a keystroke re-filters the list and nothing else re-derives. The projected
`WidgetList` selection is derived from the palette's selection by a map from the
row index in `rows` to the row index in the displayed subset.

Match rule for version 1: a case-insensitive subsequence match over
`"<domain> <description>"`. Rank an earlier first match higher. Put the runnable
and applicable rows first.

After a re-filter, move the selection to the first match when the chosen row no
longer matches. Clear the selection when nothing matches.

The palette has one selection, and it names the chosen row. The query is
therefore edited at its end, as a mini-buffer is. A caret **inside** the query
is deferred; when it arrives it belongs to the projected text field's own
selection, not to the palette's.

### 3. The palette renders through widgets

`CommandPaletteToWidget` prints a `WidgetCard` that holds a `WidgetText` for the
query and a `WidgetList` for the matching rows. Both widgets already handle the
text edit, the hover, the row click, and the row selection —
[Widget.jl](../../package/visual/main/widget/Widget.jl). The existing
`WidgetToGraphics` stage draws the result.

### 4. The decorator owns the state, the overlay, and the keys

`CommandPaletteProjection` wraps a content pipeline, like
`GestureHelpProjection`. It holds a `CommandPaletteState` with an `open` **Cell**
and the palette document. The flag must be a `Cell`, because the printer reads
it inside a reactive thunk. A plain `Bool` would freeze the render — see the
memory note "Projection printers must be reactive".

**Printer.** The decorator always wraps its output in one `GraphicsCanvas`. The
first child is the inner output. The second child is the palette, positioned
over the document, and present only while the flag is set. The wrapper is
present even when the palette is closed, so the output shape never changes and
`map_reference_forward` prepends the same one step in both states.

**Reader.** The order inverts with the flag.

- Closed: the inner pipeline reads first, as it does today. The palette hot key
  is handled after the inner declines.
- Open: the decorator reads first and swallows the event. A printable key and
  Backspace edit `query`. Up, Down, and a row click move the palette's
  `selection`. Escape clears the flag. Enter clears the flag and returns the
  operation of the selected row. The inner pipeline never sees these events, so
  the document selection does not move while the user types.

**How the palette writes its own state.** The palette is the decorator's state.
It does not live in the content document tree, so a bare
`ReplaceSelectionOperation` would be rerooted toward the content document and
would land in the wrong place. Write `query` and `selection` with a
self-contained `ReplaceReferencedValueOperation(palette, "query", …)` and
`ReplaceReferencedValueOperation(palette, "selection", …)` instead. An operation
that carries its own root passes through every rerooting stage unchanged —
[Rerooting.jl](../../package/kernel/main/operation/Rerooting.jl) — which is the
same reason a widget edit works.

**Enter.** The decorator calls `binding.operation(iomap.input, nothing)` and
returns the result as its own reader operation. A row that is not runnable does
nothing, and the palette stays open.

**Reference mapping.** Forward and backward mapping delegate to the inner iomap
and adjust for the one canvas step.

## Files

New files:

- `package/domain/main/gesturemap/CommandPalette.jl` — the document and the
  match function.
- `package/domain/main/gesturemap/CommandPaletteToWidget.jl` — the projection.
- `package/domain/main/gesturemap/CommandPaletteDecorator.jl` — the decorator.
- `package/domain/test/projection/CommandPaletteTest.jl` — the tests.

Changed files:

- `package/kernel/main/binding/GestureBinding.jl` — the optional pattern and the
  skip in the firing loop.
- `package/kernel/main/binding/Gestures.jl` — the `nothing` pattern, the name,
  and the run flag.
- `package/domain/main/gesturemap/GestureMap.jl` — the two new row fields.
- `package/domain/main/ProjecturedDomain.jl` — the three includes.
- `package/domain/example/Gallery.jl` — the decorator, beside the help
  decorator.

Every file above is unsealed. No sealed file changes.

## Phases

Do the work in a dedicated git worktree. Commit after each phase.

### Phase 1 — a binding with no gesture — **done**

1. ~~Widen `GestureBinding.pattern` to `Union{EventPattern,Nothing}`.~~
2. ~~Skip a `nothing` pattern in `fire_gesture_bindings`.~~
3. ~~Accept `nothing` in the pattern position of a `@gestures` rule.~~
4. ~~Raise an error when a `nothing` rule carries no description.~~
5. ~~Raise an error for `override(nothing)`.~~
6. ~~Add the `name` field and `fire_named_gesture_binding`.~~
7. ~~Run `test_kernel()`.~~

`test_kernel()` reports 1393 passed, 3 failed, 2 errored. The five are the known
`DocumentMacro` "Rule C" cases, which fail on clean `main` in a kernel-only
environment. `test_gesture_binding()` reports 66 passed, up from 46.

Two facts found during the work:

- **The layering guard rejects the obvious implementation.** See "How the macro
  knows the rule reads the event" above.
- **`ConversationEditor.composer_read` re-implemented the firing loop.** It
  matched every binding's pattern by hand, so a `nothing` pattern would have
  reached `matches_event_pattern`. It now calls `fire_gesture_bindings`, which is
  what the module documentation says every holder of bindings must do.

### Phase 2 — the rows

1. Add `name` and `runnable` to `GestureRow`.
2. Split the collected set into the run set and the show set.
3. Extend `test_gesture_help()` to cover a command-only binding.

### Phase 3 — the palette document and its projection

1. Add `CommandPalette` and the match function.
2. Add `CommandPaletteToWidget`.
3. Test the match order and the printer without an editor.

### Phase 4 — the decorator

1. Add `CommandPaletteProjection` and `CommandPaletteState`.
2. Write the printer with the constant canvas wrapper.
3. Write the reader with the inverted order.
4. Write the reference mapping.
5. Test that a command runs and that the document changes.

### Phase 5 — the wiring and real commands

1. Wrap each example pipeline in the decorator in `Gallery.jl`.
2. Add two or three `nothing` rules to JSON and to XML. Choose operations that
   have no good key.
3. Test the JSON example in the editor's real order: print, refresh, open the
   palette, type, press Enter, refresh, then compare the document.
4. Write the palette section in
   [package/kernel/doc/devices-and-backends.md](../../package/kernel/doc/devices-and-backends.md),
   which holds the gesture-binding text today.

## Tests

- `test_kernel()` — the binding change.
- `test_gesture_help()` — the row change.
- A new `test_command_palette()` with four cases: the match order, the run set
  filter, the Enter route, and the Escape route.
- One live-order case on the JSON example, as the memory note
  "live-editor-hides-two-bug-classes" requires.

## Open decisions

1. **Which hot key?** The plan proposes Ctrl+Shift+P. F1 is the help window.
   Alt+X is the other candidate, and it matches the Lisp heritage.
2. **Does `GestureBinding` keep its name?** The concept is a *command*: the Lisp
   version calls it that, with `domain`, `description`, `gesture`, and
   `operation` fields —
   `projectured-lisp/source/editor/command.lisp`. A binding with no gesture
   makes the current name wrong. A rename to `CommandBinding` is honest but
   touches many files. The plan keeps the current name.
3. **Which slice?** The plan puts the palette in the `gesturemap` slice, beside
   the help window, because both read one collected set.

## Rejected alternatives

- **A palette window plus a synthetic `CommandInvocation` event.** The palette
  would open a real window, and Enter would post an event to the content window
  so the ordinary reader chain fires the binding. This runs a binding from any
  chain stage, with correct rerooting for free. It costs a new event type, a new
  operation that posts to the recogniser queue, and a window id in the printer
  context. That is a kernel extension for a case the overlay covers without one.
  Reconsider it only if the palette must run deep-stage bindings.
- **A separate table of named commands.** This is a second source of truth
  beside the gesture table, and it would drift.

## Deferred

- A fuzzy rank with a score, and a recent-command list.
- An icon column. The Lisp `command` class has one.
- A command that asks for an argument before it runs.
- A palette that runs a binding from a deeper chain stage.
- A palette over the whole editor rather than over one window.
