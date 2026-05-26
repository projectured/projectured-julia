# Plan — reference-based text editing via `StringReplaceRangeOperation`

## Context

`StringReplaceRangeOperation` already exists in [program/src/document/Primitive.jl:108-130](../program/src/document/Primitive.jl#L108-L130) but carries `(document::PrimitiveString, start_index, end_index, replacement)` and is not produced by any projection — no key event currently edits a string. We want to (a) redesign the operation around a single `reference::ReferencePath` field plus a `replacement::String`, mirroring how `ReplaceSelectionOperation.path` already works, and (b) wire it up so typing a printable character, Backspace, or Delete in the editor actually edits a `PrimitiveString`. `NumberReplaceRangeOperation`, which has the identical legacy shape, is refactored the same way for consistency. Selection has to advance after each edit (otherwise typing "foo" reads back as "oof"), so the operation's evaluator also updates the target `PrimitiveString.selection` to the cursor position after the replacement.

## Decisions

1. **Reference shape** — a full `ReferencePath` from `editor.document` whose terminal step is `RangeReference(s, e)` and whose penultimate step is `FieldReference("value")`. Splitting these two off identifies (i) the target `PrimitiveString` (walk all but the last two steps), and (ii) the range `[s+1 .. e]` (0-based boundaries, 1-based char indices when materialized).
2. **Cursor advance** — `evaluate_operation` writes the target `PrimitiveString.selection` to a zero-width `RangeReference(s + length(replacement), s + length(replacement))` under the same `FieldReference("value")` parent path.
3. **Gestures** — printable char (insert / replace-selection), Backspace (delete-left or delete-selection), Delete (delete-right or delete-selection). Selection-replace is implicit because all three are expressed as range replacements.
4. **Inter-string boundary case** — explicitly deferred. Document in code that when the cursor sits between two adjacent `PrimitiveString` spans the behaviour is undefined.
5. **Scope** — operation + producer. The producer is `PrimitiveStringToSyntaxLeaf.projection_read` consuming `KeyPress`. Upstream operation-translation (extending the reference path through enclosing projections) is **not** needed because the driving example has a single `PrimitiveString` as its root document, so the path produced locally is already the full path.
6. **Driving example** — a small example whose root document is a `PrimitiveString`, used to exercise the feature interactively.

## Files to modify

### 1. Extend `KeyPress` — [program/src/device/Keyboard.jl](../program/src/device/Keyboard.jl)
Add a `char::Union{Char,Nothing}` field (default `nothing`), and extend the documented symbol set with `:backspace` and `:delete`. Update the docstring. Two-arg constructor stays for back-compat: `KeyPress(key, ctrl) = KeyPress(key, ctrl, nothing)`.

### 2. Extend SDL keymap — [program/src/backend/Sdl.jl](../program/src/backend/Sdl.jl)
In `sdl_to_keypress`:
- Map SDLK_BACKSPACE (8) → `KeyPress(:backspace, ctrl)`.
- Map SDLK_DELETE (127 or 0x4000007F) → `KeyPress(:delete, ctrl)`.
- Map printable ASCII (0x20..0x7E): when shift is held, transform via a hand-rolled table (letters → uppercase, `1`→`!`, `2`→`@`, … `;`→`:`, `'`→`"`, etc.); otherwise pass through. Emit `KeyPress(:char, ctrl, c)`.

### 3. Redesign the two operations — [program/src/document/Primitive.jl](../program/src/document/Primitive.jl)
Replace the struct definitions at lines 95-113 with:

```julia
struct NumberReplaceRangeOperation <: Operation
    reference::ReferencePath  # ends in [..., FieldReference("value"), RangeReference(s, e)]
    replacement::String
end

struct StringReplaceRangeOperation <: Operation
    reference::ReferencePath
    replacement::String
end
```

Replace the two `evaluate_operation` methods at lines 117-130 with versions that:
- Walk `op.reference` from the passed `document` to extract `(parent_path, value_step, range_step)`; assert `value_step == FieldReference("value")` and `range_step isa RangeReference`.
- Resolve `target = evaluate_reference(document, parent_path)`; `target` is the `PrimitiveString` (or `PrimitiveNumber`).
- Compute `new_str = old_str[1:s] * replacement * old_str[e+1:end]` (using the 0-based boundaries from `range_step`).
- For the number op, parse back to `Float64`, set `nothing` on empty.
- Set `target.value = …`.
- Set `target.selection = ConcreteReferencePath(FieldReference("value"), ConcreteReferencePath(RangeReference(new_pos, new_pos), EmptyReferencePath()))` where `new_pos = range_step.start + length(replacement)`.

Reuse `evaluate_reference` from [program/src/reference/Reference.jl:368](../program/src/reference/Reference.jl#L368) for the walk. Update the docstrings on lines 87-93 and 102-107 accordingly. Re-exports at [program/src/Projectured.jl:153, 318](../program/src/Projectured.jl) need no change (names unchanged).

### 4. Produce the operation from `PrimitiveStringToSyntaxLeaf` — [program/src/projection/primitive/PrimitiveToSyntax.jl](../program/src/projection/primitive/PrimitiveToSyntax.jl)
Add a new method beside the existing `projection_read` at line 125:

```julia
function projection_read(p::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, evt::KeyPress)
    s = iomap.input  # the PrimitiveString
    sel = getfield(s, :selection)[]
    # require sel to be FieldReference("value") → RangeReference(start, stop)
    (sel isa ConcreteReferencePath) || return nothing
    (sel.head isa FieldReference && sel.head.name == "value") || return nothing
    inner = sel.tail
    (inner isa ConcreteReferencePath && inner.head isa RangeReference) || return nothing
    range = inner.head
    text = something(s.value, "")
    n = length(text)

    new_range, replacement = if evt.key == :char && evt.char !== nothing && !evt.ctrl
        (range, string(evt.char))
    elseif evt.key == :backspace
        if range.start != range.stop
            (range, "")
        elseif range.start > 0
            (RangeReference(range.start - 1, range.start), "")
        else
            return nothing
        end
    elseif evt.key == :delete
        if range.start != range.stop
            (range, "")
        elseif range.stop < n
            (RangeReference(range.stop, range.stop + 1), "")
        else
            return nothing
        end
    else
        return evt   # pass through anything else (incl. arrows, return, ctrl-X, etc.)
    end

    ref = ConcreteReferencePath(FieldReference("value"),
              ConcreteReferencePath(new_range, EmptyReferencePath()))
    return StringReplaceRangeOperation(ref, replacement)
end
```

This is "local" — the ref is rooted at the `PrimitiveString` itself. For the single-`PrimitiveString` driving example, this *is* the full path from `editor.document`. Translating the operation through enclosing projections (for nested examples) is left for a follow-up. Note KeyPress already falls through `TextToGraphics.projection_read` for unknown keys (it returns `evt` at line 174). If `SyntaxToText`'s default falls through too, no further wiring is needed; if not, add a `projection_read(p, iomap, evt::KeyPress) = evt` passthrough to the relevant `SyntaxToText` projection types.

### 5. Driving example — [example/src/](../example/src/)
Add a small example file (e.g. `example/src/document/PrimitiveStringEdit.jl`) that builds a root `PrimitiveString`, opens it in the editor with the `PrimitiveToSyntax` → `SyntaxToText` → `TextToGraphics` pipeline already used by sibling examples, and lets the user type into it. Wire it into the example registry the same way existing examples are.

### 6. Tests — [test/src/document/](../test/src/document/)
Add `test/src/document/PrimitiveTest.jl` (or extend an existing one) covering:
- `evaluate_operation(StringReplaceRangeOperation(ref, "x"), doc)` on a root `PrimitiveString` with `ref` = cursor at position 0 inserts `"x"` and moves selection to position 1.
- Backspace at cursor position k deletes the k-th char and selection lands at k-1.
- Delete at cursor position k deletes the (k+1)-th char and selection stays at k.
- Non-empty range with empty replacement deletes the range; with non-empty replacement substitutes; selection lands at start+len(replacement).
- Same coverage for `NumberReplaceRangeOperation` including parse-back-to-`Float64` and the empty-string → `nothing` case.
- `projection_read(PrimitiveStringToSyntaxLeaf, iomap, KeyPress(:char, false, 'x'))` with a configured selection produces a `StringReplaceRangeOperation` with the expected reference path and replacement.

## Verification

1. `julia --project=program -e 'include("test/runtests.jl")'` — or whatever the project's `test_all` entry point is per [guide/testing.md](../guide/testing.md) — passes.
2. Run the new driving example. Type characters: they appear at the cursor and the cursor advances. Hit Backspace: the char to the left disappears and the cursor moves left. Hit Delete: the char to the right disappears and the cursor stays. With arrow keys (already working), navigate then type — edit lands at the moved cursor.
3. Verify no other call sites of `StringReplaceRangeOperation` / `NumberReplaceRangeOperation` broke: `grep -rn "StringReplaceRangeOperation\|NumberReplaceRangeOperation" program/ test/ example/`.

## Out of scope

- Cursor / selection behaviour when the cursor sits exactly on the boundary between two adjacent `PrimitiveString` spans (deferred).
- Translating `StringReplaceRangeOperation` through enclosing projections so it can be produced when the `PrimitiveString` is nested deep inside a structured document (deferred to a follow-up that adds `projection_read` methods on `CollectionToSyntax`, `ObjectToSyntax`, `XmlElementToSyntaxNode`, etc., each extending the reference path with their own outer step).
- IME / international text input (SDL `TEXTINPUT` handling).
- Undo/redo.
- Cut / copy / paste.
