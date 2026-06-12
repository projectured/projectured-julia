# Plan — type-in for text, syntax, then JSON domains

## Context

Type-in (printable character → insert; Backspace → delete-left or delete-selection; Delete → delete-right or delete-selection) currently works only when the editor's root document is a `PrimitiveString`. The producer is `PrimitiveStringToSyntaxLeaf.projection_read(::KeyPress|::KeyDown)` in [program/src/projection/primitive/PrimitiveToSyntax.jl:163-198](../program/src/projection/primitive/PrimitiveToSyntax.jl#L163-L198); the sibling `PrimitiveStringToText` does the analogous thing for the primitive-to-text pipeline ([program/src/projection/primitive/PrimitiveToText.jl:146-180](../program/src/projection/primitive/PrimitiveToText.jl#L146-L180)). Operation evaluation in [program/src/document/Primitive.jl:131-182](../program/src/document/Primitive.jl#L131-L182) hardcodes the terminal `.value[range]` shape and the `PrimitiveString` / `PrimitiveNumber` target types.

We want type-in to work in three more domains, in this order:

1. **Text** — root document is a `TextText`; typing edits the `content` field of a `TextString` span.
2. **Syntax** — root document is a `SyntaxLeaf` (or a tree of `SyntaxNode`s containing leaves); typing edits the `content` field of the leaf's `value` `TextString` (and analogously `open`/`close` if desired, deferred).
3. **JSON** — root document is a `JsonString` / `JsonNumber`, possibly nested inside `JsonArray` / `JsonObject`; typing edits the JSON primitive's `value` field.

The key vehicle is the existing `StringReplaceRangeOperation` (and its sibling `NumberReplaceRangeOperation`). We extend it along two axes: the evaluator becomes polymorphic in the target type, and projection readers in each layer either **produce** the operation (from a raw `KeyPress` / `KeyDown`) or **translate** an operation arriving from a downstream reader into their own input domain.

The `SequentialProjection` reader chain ([program/src/projection/higherorder/Sequential.jl:78-92](../program/src/projection/higherorder/Sequential.jl#L78-L92)) is what makes the layered translation work: it starts at the last (output-side) projection, walks earlier projections until one returns non-`nothing`, then folds the result back through earlier projections in reverse.

## Decisions

1. **One producer per pipeline, lowest layer.** The projection closest to the device (the last in the sequential chain) catches `KeyPress`/`KeyDown` and emits a `StringReplaceRangeOperation` against its **own input domain**:
   - Text pipeline (`WordWrapping → TextToGraphics`): the producer is `TextToGraphics`, on the wrapped `TextText`.
   - Syntax pipeline (`SyntaxToText → TextToGraphics`): the producer is still `TextToGraphics`, on the rendered `TextText`; `SyntaxToText` translates it backward into the syntax domain.
   - JSON pipeline (`JsonToSyntax → SyntaxToText → TextToGraphics`): same producer, with both `SyntaxToText` and `JsonToSyntax` translating in turn.

   This matches the existing pattern for `MousePress` / `ReplaceSelectionOperation` in `TextToGraphics` ([program/src/projection/primitive/TextToGraphics.jl:87-102](../program/src/projection/primitive/TextToGraphics.jl#L87-L102)).

2. **Reference shape mirrors the domain's selection convention.** The `reference` field of the emitted operation uses the same shape as the document's `selection` cursor in that domain. After evaluation, the document's selection is updated to the same path with the terminal `RangeReference` collapsed to a zero-width cursor at `start + length(replacement)`.

   | Domain            | Selection shape                       | Op reference shape                    |
   |-------------------|---------------------------------------|---------------------------------------|
   | `PrimitiveString` | `.value[k]`                           | `.value[s:e]`                         |
   | `PrimitiveNumber` | `.value[k]`                           | `.value[s:e]`                         |
   | `TextText`        | `.elements[i].content[k]`             | `.elements[i].content[s:e]`           |
   | `SyntaxLeaf`      | `.value[k]` (also `.open`/`.close`)   | `.value[s:e]` (initially)             |
   | `JsonString`      | `.value[k]`                           | `.value[s:e]`                         |
   | `JsonNumber`      | `.value[k]`                           | `.value[s:e]`                         |
   | `JsonArray`       | `.elements[i].…`                      | `.elements[i].…`                      |
   | `JsonObject`      | `.entries[i].key[k]` / `.entries[i].value.…` | same                          |

3. **Polymorphic evaluator.** `evaluate_operation(editor, op::StringReplaceRangeOperation)` splits `op.reference` into `(prefix, terminal_range)`, walks `prefix` against `editor.document` to find the target, then dispatches a helper `_apply_string_replace!(target, field_name, s, e, replacement)` on the target type. Each domain module owns the method for its own document type:
   - `PrimitiveString` → write `target.value`.
   - `TextString` (in `TextModule`) → write `target.content`.
   - `SyntaxLeaf` (in `SyntaxModule`) → write `target.value.content` (or `.open.content` / `.close.content` once we open those up); the trailing field-name in the prefix tells the dispatcher which TextString to descend into.
   - `JsonString` → write `target.value`.

   The same idea handles `NumberReplaceRangeOperation` for `PrimitiveNumber` and `JsonNumber`. The editor's root `document.selection` is updated to `op.reference` with the terminal `RangeReference(s, e)` rewritten to a zero-width `RangeReference(s+L, s+L)` where `L = length(replacement)` — this is independent of target type and replaces the current `target.selection = …` update, which only worked when target was the root.

4. **Phased rollout.** Each phase delivers a runnable, testable example. The order is text → syntax → JSON because (a) syntax sits above text and reuses the text-layer producer, and (b) JSON sits above syntax and reuses the syntax-layer translator. Each phase only touches the readers it needs and leaves the higher domains for the next phase.

5. **Range falling outside a single leaf** is rejected (the reader returns `nothing`). Typing is a per-leaf operation; multi-leaf range replacement is deferred.

6. **`WordWrapping`** has a `map_reference_backward` that already translates output `.elements[i].content[k]` → input `.elements[i'].content[k']`. We add a `projection_read(::WordWrapping, iomap, op::StringReplaceRangeOperation)` that uses it, mirroring the existing `ReplaceSelectionOperation` method at [program/src/projection/primitive/WordWrapping.jl:244-248](../program/src/projection/primitive/WordWrapping.jl#L244-L248).

## Phase 0 — Polymorphic evaluator (prerequisite)

### 0.1 Generalize the evaluator — [program/src/document/Primitive.jl:131-182](../program/src/document/Primitive.jl#L131-L182)

Replace `_split_replace_reference` with a version that returns `(prefix, field_name, range_step)` and drops the hardcoded `name == "value"` assertion (the field name is now data, not a precondition). Replace the two `evaluate_operation` methods with a single dispatcher per op type:

```julia
function _split_replace_reference(path::ReferencePath)
    # …walk to last two steps as today, but return field_name as the data and
    # do NOT require it equal "value"…
    return (prefix, field_name::String, range_step::RangeReference)
end

function evaluate_operation(editor, op::StringReplaceRangeOperation)
    document = editor.document
    prefix, field_name, range = _split_replace_reference(op.reference)
    target = evaluate_reference(document, prefix)
    _apply_string_replace!(target, field_name, range.start, range.stop, op.replacement)
    document.selection = _replace_terminal_with_cursor(op.reference, op.replacement)
end

function evaluate_operation(editor, op::NumberReplaceRangeOperation)
    document = editor.document
    prefix, field_name, range = _split_replace_reference(op.reference)
    target = evaluate_reference(document, prefix)
    _apply_number_replace!(target, field_name, range.start, range.stop, op.replacement)
    document.selection = _replace_terminal_with_cursor(op.reference, op.replacement)
end

# Default — never matches a real target type; turn missing methods into a useful error.
function _apply_string_replace!(target, field_name, s, e, replacement)
    error("No _apply_string_replace! method for target $(typeof(target)).$(field_name)")
end
function _apply_number_replace! end  # same shape
```

Define `_apply_string_replace!(::PrimitiveString, "value", …)` and `_apply_number_replace!(::PrimitiveNumber, "value", …)` here in `PrimitiveModule` — these are the methods the existing `PrimitiveString`/`PrimitiveNumber` cases already implement inline.

Export `_apply_string_replace!` and `_apply_number_replace!` from `PrimitiveModule` (or move both functions and the splitter to `OperationApiModule` so each domain can add methods without importing from `PrimitiveModule`). Pick one and keep it consistent. The cleaner shape is **move the functions to `OperationApiModule`** since they are part of the operation protocol, not part of the primitive domain:

- New file: `program/src/api/OperationApi.jl` already exists as [program/src/api/Operation.jl](../program/src/api/Operation.jl) — add `_apply_string_replace!` and `_apply_number_replace!` declarations there, plus the splitter helper. `PrimitiveModule` imports them and adds the primitive methods.

### 0.2 Tests — extend [test/src/document/PrimitiveTest.jl](../test/src/document/PrimitiveTest.jl)

Existing tests in [test/src/document/PrimitiveTest.jl:30-110](../test/src/document/PrimitiveTest.jl#L30-L110) still pass unchanged (they hit `.value[range]` on `PrimitiveString` / `PrimitiveNumber` roots). Add one regression test that the new selection assignment writes to `editor.document.selection` — not just `target.selection` — so nested cases work later.

## Phase 1 — Text domain

Goal: an editor with a `TextText` root document supports typing into any of its `TextString` spans.

### 1.1 Producer in `TextToGraphics` — [program/src/projection/primitive/TextToGraphics.jl](../program/src/projection/primitive/TextToGraphics.jl)

Add `projection_read(::TextToGraphics, iomap, ::KeyPress)` and a sibling `projection_read(::TextToGraphics, iomap, ::KeyDown)` for backspace/delete. Both:

- Read `iomap.input.selection[]` (a `TextText` selection, shape `.elements[i].content[range]`).
- Reject non-`.elements[i].content[range]` shapes by returning `nothing`.
- For `KeyPress`: if `!ctrl`, emit `StringReplaceRangeOperation(.elements[i].content[range], evt.text)`.
- For `KeyDown` backspace/delete: compute the deletion range exactly as `PrimitiveStringToText.projection_read(::KeyDown)` does ([program/src/projection/primitive/PrimitiveToText.jl:154-180](../program/src/projection/primitive/PrimitiveToText.jl#L154-L180)), but anchored at `.elements[i].content[…]`. The length used for the boundary check is `length(iomap.input[i].content)` (the i-th span).
- The current `projection_read(::TextToGraphics, iomap, evt)` at [program/src/projection/primitive/TextToGraphics.jl:104](../program/src/projection/primitive/TextToGraphics.jl#L104) already handles arrow keys etc. and returns `evt` for unhandled keys, so the new methods slot in cleanly above it.

The KeyDown method must run **before** the existing generic method that handles arrows — Julia's method dispatch will pick the most specific signature, but we should also make sure arrows don't fall into the new method. The simplest split: keep the existing function as-is for arrows / home / end / up / down, and gate the new behavior to `evt.key ∈ (:backspace, :delete)` returning `nothing` otherwise (so the existing arrow-handler still wins via the generic `evt` method).

### 1.2 `_apply_string_replace!(::TextString, "content", …)` — [program/src/document/Text.jl](../program/src/document/Text.jl)

In `TextModule`, add:

```julia
import ..OperationApiModule: _apply_string_replace!
function _apply_string_replace!(target::TextString, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "content" || error("TextString supports only field 'content'")
    old = target.content::AbstractString
    target.content = old[1:s] * replacement * old[e+1:end]
end
```

(The `target.content = …` write through `@document`-generated `setproperty!` updates the reactive cell, so downstream layout invalidates correctly.)

### 1.3 `WordWrapping` translator — [program/src/projection/primitive/WordWrapping.jl:244-252](../program/src/projection/primitive/WordWrapping.jl#L244-L252)

Add:

```julia
function projection_read(p::WordWrapping, iomap::WordWrappingIoMap, op::StringReplaceRangeOperation)
    input_path = map_reference_backward(p, iomap, op.reference)
    input_path === nothing && return nothing
    StringReplaceRangeOperation(input_path, op.replacement)
end
```

The existing `op` fallback at line 252 (`projection_read(::WordWrapping, ::WordWrappingIoMap, op) = op`) already lets unrelated ops pass through, so we just need the specialized method.

If a range crosses a wrap boundary (start and stop map to different input spans), return `nothing` — out of scope for now.

### 1.4 Driving example — [example/src/document/Text.jl](../example/src/document/Text.jl) + [example/src/projection/Text.jl](../example/src/projection/Text.jl)

The existing `make_text_document_example` already sets a selection at `elements[1].content{3}`, which is exactly the cursor shape we need. The existing `make_text_projection_example` chains `WordWrapping → TextToGraphics`. With the new producer + translator, typing should just work — no example changes needed beyond verifying the wiring.

Add a second smaller example with multiple `TextString` spans (so the per-span boundary behavior is exercised) and wire it into `Examples.jl` the same way other examples are registered.

### 1.5 Tests

New file `test/src/projection/TextToGraphicsTest.jl` (extending whatever the existing TextToGraphics test file is named, if any):

- `KeyPress('x')` with selection `elements[1].content{0}` on a `TextText` of one span → `StringReplaceRangeOperation(.elements[1].content[0:0], "x")`.
- `KeyDown(:backspace, …)` with selection `elements[1].content{2}` → range becomes `[1:2]`, replacement `""`.
- `KeyDown(:delete, …)` at end of span → `nothing` (no character to the right within the same span — multi-span delete deferred).
- After `evaluate_operation`, the `TextText`'s `.selection` cell holds `.elements[1].content{s+len}` (zero-width cursor at the post-edit position).
- `WordWrapping`: feed it a `StringReplaceRangeOperation` on the wrapped output and confirm the translated input path uses the un-wrapped span index.

## Phase 2 — Syntax domain

Goal: an editor with a `SyntaxLeaf` (or arbitrary `SyntaxNode` tree) root document supports typing into the `value` field of a leaf.

### 2.1 `SyntaxLeafToText` translator — [program/src/projection/primitive/SyntaxToText.jl:70-79](../program/src/projection/primitive/SyntaxToText.jl#L70-L79)

Add:

```julia
function projection_read(p::SyntaxLeafToText, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    # op.reference is a TextText path: .elements[i].content[s:e] with i ∈ 1:3
    # → SyntaxLeaf path: .open[s:e] (i=1) / .value[s:e] (i=2) / .close[s:e] (i=3)
    span_idx, char_start, char_stop = _parse_text_elem_range(op.reference)
    span_idx === nothing && return nothing
    field = span_idx == 1 ? "open" :
            span_idx == 2 ? "value" :
            span_idx == 3 ? "close" : (return nothing)
    new_ref = ConcreteReferencePath(FieldReference(field),
                  ConcreteReferencePath(RangeReference(char_start, char_stop),
                                        EmptyReferencePath()))
    StringReplaceRangeOperation(new_ref, op.replacement)
end
```

`_parse_text_elem_range` is a tiny variant of the existing `_parse_text_elem_path` ([program/src/projection/primitive/SyntaxToText.jl:583](../program/src/projection/primitive/SyntaxToText.jl#L583)) that returns the full range (start, stop), not just the cursor start — refactor `_parse_text_elem_path` to optionally return the stop, or add the new parser alongside.

For now, only act when `i == 2` (`.value`). Editing `.open` / `.close` (the quote characters in a JsonString-rendered leaf) is rarely meaningful and routes through a projection-introduced span — defer it. Return `nothing` for `i == 1` or `i == 3` so the higher domains can deal with the structural delimiter case later.

### 2.2 `SyntaxNodeToText` translator — [program/src/projection/primitive/SyntaxToText.jl:146-150](../program/src/projection/primitive/SyntaxToText.jl#L146-L150)

Add a `projection_read(::SyntaxNodeToText, iomap, op::StringReplaceRangeOperation)` that:

1. Translates `op.reference`'s start position via `_text_elem_path_to_flat` + `_pos_to_selection` to obtain the syntax-domain selection path for the start of the range (this reuses the existing helpers used by `ReplaceSelectionOperation`).
2. Translates the stop position the same way; verifies the two paths have the same `prefix.value[…]` shape (i.e., both fall inside the same leaf's value span). If not, return `nothing`.
3. Builds `StringReplaceRangeOperation(syntax_prefix.value[s:e], op.replacement)`.

This walks naturally through nested nodes — `_pos_to_selection` already constructs `.children[i].^(child_path)` recursively.

### 2.3 `_apply_string_replace!(::SyntaxLeaf, …)` — [program/src/document/Syntax.jl](../program/src/document/Syntax.jl)

```julia
import ..OperationApiModule: _apply_string_replace!
function _apply_string_replace!(target::SyntaxLeaf, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name in ("open", "value", "close") || error("SyntaxLeaf: unsupported field $field_name")
    span = getfield(target, Symbol(field_name))::TextString
    old = span.content::AbstractString
    span.content = old[1:s] * replacement * old[e+1:end]
end
```

### 2.4 Driving example

Add `make_syntax_leaf_document_example()` in [example/src/document/Syntax.jl](../example/src/document/Syntax.jl) returning a bare `SyntaxLeaf("\"", "\"", "hello")` with selection at `.value{0}`. Reuse `make_syntax_projection_example` ([example/src/projection/Syntax.jl](../example/src/projection/Syntax.jl)) — no projection-side example changes needed.

### 2.5 Tests

`test/src/projection/SyntaxToTextTest.jl` (extend existing file) — for `SyntaxLeafToText`:

- Feed a `StringReplaceRangeOperation(.elements[2].content[0:0], "x")` on the rendered 3-span TextText → expect `StringReplaceRangeOperation(.value[0:0], "x")`.
- `.elements[1]` (the open quote) → `nothing` (deferred).
- After `evaluate_operation` on a `SyntaxLeaf` root with the syntax-domain op, `leaf.value.content` reflects the edit and `leaf.selection[]` is a zero-width cursor at the new position.

For `SyntaxNodeToText`:

- Build a small node `[ "a", "b" ]` (open=`[`, close=`]`, sep=`, `, two leaves). Compute the flat-text positions for `.children[1].value[0:0]`, feed a text-domain op there, expect a node-domain op at `.children[1].value[0:0]` with the same replacement.
- A range crossing two children → `nothing`.

## Phase 3 — JSON domain

Goal: an editor with any JSON root (typically `JsonObject` / `JsonArray`) supports typing into `JsonString` / `JsonNumber` leaves, including the keys (`JsonObjectEntry.key`).

### 3.1 `JsonStringToSyntaxLeaf` translator — [program/src/projection/primitive/JsonToSyntax.jl:170-180](../program/src/projection/primitive/JsonToSyntax.jl#L170-L180)

Add:

```julia
function projection_read(p::JsonStringToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    # op.reference is a SyntaxLeaf-domain path: .value[s:e]
    path = op.reference
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    inner = path.tail
    inner isa ConcreteReferencePath && inner.head isa RangeReference || return nothing
    # JsonString's value field is the raw string; identity translation works.
    op
end
```

(Identity — `JsonString.value` and `SyntaxLeaf.value.content` carry the same characters.)

If the JSON string has escape sequences (`json_escape`), a syntax-domain `.value[k]` is in the *escaped* coordinate system while `JsonString.value` is in the *raw* coordinate system. The existing `map_reference_*` methods already say the mapping is identity "when no escape sequences precede position k" ([program/src/projection/primitive/JsonToSyntax.jl:155-161](../program/src/projection/primitive/JsonToSyntax.jl#L155-L161)). Document the same caveat here and defer proper escape-aware mapping.

### 3.2 `JsonNumberToSyntaxLeaf` translator — same file, around line 123

Convert a `StringReplaceRangeOperation` from the syntax domain into a `NumberReplaceRangeOperation` at the same `.value[range]` so the number evaluator's `tryparse(Float64, …)` logic kicks in. Reject if the resulting string would still be unparseable — actually no, let the evaluator handle it (`tryparse` already returns `nothing` for bad input, which `evaluate_operation(::NumberReplaceRangeOperation)` already handles by clearing the value). This matches the existing behavior for `PrimitiveNumber`.

```julia
function projection_read(p::JsonNumberToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    path = op.reference
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    NumberReplaceRangeOperation(path, op.replacement)
end
```

(Also handle `op::NumberReplaceRangeOperation` as identity for symmetry, even though no upstream produces one yet.)

### 3.3 `JsonArrayToSyntaxNode` translator — [program/src/projection/primitive/JsonToSyntax.jl:240-246](../program/src/projection/primitive/JsonToSyntax.jl#L240-L246)

The existing `projection_read(::JsonArrayToSyntaxNode, iomap, ::ReplaceSelectionOperation)` already shows the shape: it uses `_translate_json_path` to map `.children[i].…` → `.elements[i].…`. Add the analogous method for `StringReplaceRangeOperation` / `NumberReplaceRangeOperation`:

```julia
function projection_read(p::JsonArrayToSyntaxNode, iomap::ChildrenIoMap, op::Union{StringReplaceRangeOperation, NumberReplaceRangeOperation})
    new_ref = _translate_json_path(iomap.input::JsonArray, op.reference)
    new_ref === nothing && return nothing
    typeof(op)(new_ref, op.replacement)
end
```

### 3.4 `JsonObjectToSyntaxNode` translator — [program/src/projection/primitive/JsonToSyntax.jl:329-335](../program/src/projection/primitive/JsonToSyntax.jl#L329-L335)

Same shape as 3.3, using the existing `_translate_json_path(::JsonObject, …)` which already maps:

- `.children[i].children[1].value.…` → `.entries[i].key.…`
- `.children[i].children[2].…` → `.entries[i].value.…`

So typing in a key produces `StringReplaceRangeOperation(.entries[i].key[s:e], …)`. The key field is currently a plain `String` field on `JsonObjectEntry`, not a `JsonString` — we need to either:

- Wrap it: change `JsonObjectEntry.key::String` to `JsonObjectEntry.key::JsonString` (substantial refactor — touches `jsonvalue`, `JsonObject`, every test that constructs entries). **Defer.**
- Or: add `_apply_string_replace!(::JsonObjectEntry, "key", …)` that mutates `target.key` directly. This is a plain field write — confirm via [program/src/document/Json.jl:JsonObjectEntry](../program/src/document/Json.jl) whether `@document` makes the field reactive. If yes, this is one-line.

Go with the second option for the initial cut.

### 3.5 `_apply_string_replace!(::JsonString, "value", …)` and `_apply_number_replace!(::JsonNumber, "value", …)` — [program/src/document/Json.jl](../program/src/document/Json.jl)

Direct field writes, matching the `PrimitiveString` / `PrimitiveNumber` implementations.

### 3.6 Driving example

[example/src/document/Json.jl](../example/src/document/Json.jl) already has rich JSON examples. Use `make_json_string_document_example` as the simplest case (root = `JsonString`), then `make_json_document_example` for the nested case (root = `JsonObject` containing strings, numbers, nested arrays). No new examples needed — verify typing works end-to-end in each.

### 3.7 Tests

`test/src/projection/JsonToSyntaxTest.jl` (extend existing or add new):

- `JsonStringToSyntaxLeaf`: input op `.value[0:0] "x"` → output op `.value[0:0] "x"` (identity), evaluator updates `j.value` and `j.selection`.
- `JsonNumberToSyntaxLeaf`: input op `.value[0:1] "9"` on `JsonNumber(42)` → produces `NumberReplaceRangeOperation`; after eval, `j.value == 92.0`.
- `JsonArrayToSyntaxNode`: synthesize a node-domain op at `.children[1].value[0:0] "x"` on an array `[JsonString("a")]`, expect translated op `.elements[1].value[0:0] "x"`; eval updates `arr.elements[1].value`.
- `JsonObjectToSyntaxNode`: same for an object `{"k": "v"}` — both editing the key and editing the value.

## Verification

1. `julia --project=program -e 'include("test/runtests.jl")'` passes; the previously-existing `PrimitiveTest`, `PrimitiveToTextTest`, and `PrimitiveToSyntaxTest` tests still pass without modification (they exercise the special-cased `PrimitiveString` / `PrimitiveNumber` paths via the new polymorphic evaluator).
2. Run each phase's driving example interactively:
   - Phase 1: open `make_text_document_example()`, click into a span, type — characters appear at the cursor; Backspace / Delete work; arrows still navigate.
   - Phase 2: open `make_syntax_leaf_document_example()`, type into the value; the quote characters at the start/end are untouched.
   - Phase 3: open `make_json_document_example()`, click into a value or a key, type; numbers reparse on each edit, strings update in place.
3. `grep -rn "StringReplaceRangeOperation\|NumberReplaceRangeOperation\|_apply_string_replace\|_apply_number_replace" program/ test/ example/` — confirm no call sites broke.

## Out of scope

- Editing the projection-introduced delimiter characters (`"`, `[`, `{`, etc.) — these would need to translate into structural edits (e.g., wrapping a value), which is a different kind of operation.
- Multi-leaf range replacement (typing-over a selection that spans multiple syntax leaves or wrapping segments).
- Escape-aware character offset mapping for `JsonString` (the `json_escape` issue).
- Typing into `JsonNull` / `JsonBool` (would need a "replace with another primitive" structural operation).
- Refactor of `JsonObjectEntry.key` from `String` to `JsonString`.
- IME / non-ASCII text input (still pinned to the SDL `KeyPress.text` field as it stands today).
- Undo / redo, cut / copy / paste, multi-cursor.
- Interaction with `SyntaxIndentation` / `SyntaxCollapsible` / `SyntaxDelimitation` wrappers — these aren't in the current default JSON pipeline, but if added, each would need its own `StringReplaceRangeOperation` translator.
