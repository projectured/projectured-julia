# Plan — expand `@reference` usage and DSL

## Context

The codebase has two reference-related macros:

- [`@reference`](../program/src/reference/ReferenceBuilder.jl) — *constructs* a `ReferencePath` from a path-shaped DSL (`address.city`, `items[i].name`, `cursor.point(x, y)`, `rendered.proj(p, [0])`).
- [`@reference_case`](../program/src/reference/ReferenceCase.jl) — *destructures* a `ReferencePath` via pattern matching (used heavily in `map_reference_*` and `projection_read`).

`@reference_case` is broadly used. `@reference` is barely used — only 13 call sites, almost all of them the trivial `value{k} => @reference value{k}` identity passthrough for `Primitive*ToSyntaxLeaf` / `Json*ToSyntaxLeaf`. Meanwhile the codebase has:

- **469** raw `ConcreteReferencePath(…)` / `append_reference(…)` / `EmptyReferencePath()` call sites
- **321** raw `FieldReference(…)` / `ElementReference(…)` / `PositionReference(…)` / `RangeReference(…)` / `PointReference(…)` / `ProjectionReference(…)` / `ReferencePath(…)` step constructors
- **86** hand-rolled `h isa FieldReference && h.name == "…"` chains that `@reference_case` already handles cleanly

Concentration is in the *primitive* projections — [BookToSyntax.jl](../program/src/projection/primitive/BookToSyntax.jl) (59 sites), [JuliaToSyntax.jl](../program/src/projection/primitive/JuliaToSyntax.jl) (41), [MathToSyntax.jl](../program/src/projection/primitive/MathToSyntax.jl) (37), [JsonToSyntax.jl](../program/src/projection/primitive/JsonToSyntax.jl) (27), [XmlToSyntax.jl](../program/src/projection/primitive/XmlToSyntax.jl) (20). These read like LISP s-expressions:

```julia
ConcreteReferencePath(FieldReference("children"),
    ConcreteReferencePath(ElementReference(2),
        ConcreteReferencePath(FieldReference("children"),
            ConcreteReferencePath(ElementReference(child_i), inner))))
```

`@reference` could express this as `children[2].children[child_i].^(inner)` — **if** the macro had a path-splice operator at the top level. It currently does not; `^()` is only recognized inside `proj()`'s `outpath` (see [ReferenceBuilder.jl:151-158](../program/src/reference/ReferenceBuilder.jl#L151-L158)).

This plan (a) closes the gaps in the constructor DSL so it can express every shape currently built by hand, (b) catalogs the migration to convert raw construction to `@reference`, and (c) factors out the boilerplate identity-passthrough projections so they stop repeating.

## Goals

1. **Reduce surface area.** Direct calls to `ConcreteReferencePath`, `FieldReference`, `ElementReference`, `PositionReference`, `RangeReference`, `EmptyReferencePath`, `append_reference` should be largely confined to the `reference/` and `document/` directories. Projection code should read in the path DSL.
2. **No semantic change.** The plan is mechanical: every rewrite is a textual substitution that produces structurally identical paths.
3. **One small DSL extension at a time.** Each macro change is independently verifiable by re-running the existing test suite (which already exercises every projection's printer/reader pair).

## Gap analysis

What the current `@reference` macro can express:

| Shape | DSL | Generates |
|---|---|---|
| Field chain | `a.b.c` | `Field("a") · Field("b") · Field("c")` |
| Element step | `xs[i]` | `Field("xs") · Element(i)` |
| Position step | `xs{k}` | `Field("xs") · Position(k)` |
| Dynamic field | `o.field(name)` | `Field(name)` |
| Pixel point | `c.point(x, y)` | `Field("c") · Point(x, y)` |
| Projection step | `o.proj(p, [0])` | `Field("o") · Projection(p, Element(0))` |
| Path splice inside `proj` | `o.proj(p, ^(tail))` | `Field("o") · Projection(p, tail)` |

What hand-written code uses that the DSL **cannot** express today:

1. **Path-tail splice at top level** — `ConcreteReferencePath(FieldReference("value"), path.tail)` appears 50+ times. There is no top-level `^()` to splice a runtime tail.
2. **Single-step splice** — `ConcreteReferencePath(FieldReference("value"), ConcreteReferencePath(range, EmptyReferencePath()))` where `range::RangeReference` is a runtime value, appears in [PrimitiveToSyntax.jl:156-158](../program/src/projection/primitive/PrimitiveToSyntax.jl#L156-L158), [WorkbenchAssistant.jl:124-127, 619-622](../program/src/editor/WorkbenchAssistant.jl#L124-L127), [Primitive.jl:160-161](../program/src/document/Primitive.jl#L160-L161), etc. There is no way to splice a single `ReferenceStep` value.
3. **Explicit range step** — `RangeReference(s, e)` constructions for multi-element selections. `Base.show` already prints these as `{s:e}`, but the DSL does not accept `{s:e}` as input.
4. **Building a single step in isolation** — `FieldReference("value")` and friends as first-class values (e.g. for passing as varargs to `append_reference`). The macro returns a `ReferencePath`, not a `ReferenceStep`; there is no `@step` companion.

## Decisions

1. **`^(expr)` becomes a universal splice operator inside `@reference`.** Allowed at any path position. Semantics at codegen time: emit a call to a new internal helper `_splice(expr)` which, at runtime, accepts either a `ReferencePath` (concatenated) or a `ReferenceStep` (wrapped into a one-step path then concatenated). This subsumes the existing `proj(p, ^(tail))` behavior; the new path is also accepted at the top level, e.g. `@reference value.^(path.tail)`.
2. **Add `{s:e}` range syntax to both macros.** In `@reference`, `xs{s:e}` produces `RangeReference(s, e)` (no `is_element_reference`/`is_position_reference` collapse — the user is explicitly asking for a range). In `@reference_case`, `xs{s:e}` matches any `RangeReference` and binds `s` and `e` to the boundaries.
3. **Add `@step` companion macro.** `@step value` → `FieldReference("value")`; `@step xs[i]` → `ElementReference(i)`; `@step xs{k}` → `PositionReference(k)`; `@step xs{s:e}` → `RangeReference(s, e)`; `@step c.point(x,y)` → `PointReference(x, y)`. Only single-step expressions are accepted (no `.` chaining). Reuses `_parse_build_path` from `ReferenceBuilder.jl`.
4. **No new pattern-matching forms in `@reference_case`** beyond `{s:e}`. `@reference_case` already covers every shape needed for reads; the win is on the *construction* side.
5. **Refactor identity-passthrough boilerplate.** All five `Primitive*ToSyntaxLeaf` and three `Json*ToSyntaxLeaf` types repeat the same `value{k} => @reference value{k}` map in both `map_reference_forward` and `map_reference_backward`. Replace with a single shared helper `_passthrough_value_cursor(reference)` defined once. (Tactical, not part of the DSL change — but it deletes ~24 small functions.)
6. **No deletion of low-level constructors.** `ConcreteReferencePath`, `FieldReference`, etc. remain available and exported. The reference module itself and the operation `evaluate_*` machinery in [Reference.jl:368+](../program/src/reference/Reference.jl) must construct paths from runtime values without a macro; that code does not migrate.
7. **Migration is opt-in per file, not one big sweep.** Each file is touched separately so the diff stays reviewable and any printer/reader regressions are easy to bisect.

## Files to modify

### 1. Extend `@reference` constructor — [program/src/reference/ReferenceBuilder.jl](../program/src/reference/ReferenceBuilder.jl)

**Path splice at top level.** Today `_parse_build_path!` errors on `^(expr)` outside of `proj()`. Add a new `BSPathSplice` arm that simply records the spliced expression:

```julia
elseif ex isa Expr && ex.head == :call && ex.args[1] == :(^)
    length(ex.args) == 2 || error("^(expr) expects exactly one argument: $ex")
    push!(steps, BSPathSplice(ex.args[2]))
    return steps
```

**Codegen.** A `BSPathSplice` at the *tail* of a chain just yields the spliced expression (already implemented in `_gen_build_path` for the single-step splice case). When the splice is not at the tail it has to concatenate; introduce a small helper:

```julia
# in ReferenceBuilderModule, used by codegen:
_splice(p::ReferencePath) = p
_splice(s::ReferenceStep) = ConcreteReferencePath(s, EmptyReferencePath())
_concat(a::EmptyReferencePath, b::ReferencePath) = b
_concat(a::ConcreteReferencePath, b::ReferencePath) =
    ConcreteReferencePath(a.head, _concat(a.tail, b))
```

The macro emits `_concat(<prefix>, _splice(<spliced expr>))` for each splice point. For the common case where the splice is the final element of the chain (`@reference a.b.^(rest)`) the prefix-concat collapses to a direct `_concat` call; for `@reference a.^(mid).b` it materializes a tail path for `b` then concatenates. **Do not** try to inline this into the macro — keep the runtime helpers small and easy to read.

**Range syntax `{s:e}`.** In `_parse_build_path!`, the `:braces` arm currently accepts only a one-argument form. Extend it to accept either `{k}` (one arg → `BSPosition`) or `{s:e}` (the parser emits this as a `:braces` with a single `:call` arg whose head is `:(:)`; or with two args depending on Julia version — verify both shapes). Lower to a new `BSRangeBraces` build step that generates `RangeReference(s, e)`.

The existing `xs[s, e]` (two-arg `:ref`) is kept as an alias for backward compatibility but the docstring should now point users at `xs{s:e}` as the preferred form (it matches `Base.show`).

**`@reference()` with no args** already returns `EmptyReferencePath()` — keep that.

### 2. Extend `@reference_case` patterns — [program/src/reference/ReferenceCase.jl](../program/src/reference/ReferenceCase.jl)

Add `{s:e}` pattern (mirror of the constructor extension): in `_parse_path!` extend the `:braces` arm, lower to a new `PSRangeBraces` step that generates the same match code as `PSRange` but written with the boundary syntax. Both patterns ultimately produce a `RangeReference` match — `PSRangeBraces` exists only to give a clear surface syntax. (Alternatively, rewrite `{s:e}` to the existing `PSRange` at parse time and don't introduce a new step type.)

No other changes to `@reference_case`.

### 3. Add `@step` macro — [program/src/reference/ReferenceBuilder.jl](../program/src/reference/ReferenceBuilder.jl)

Defined in the same module as `@reference`. Parses with `_parse_build_path` and requires the result to be a single step (length 1, not a `BSPathSplice` or `BSProjection` with empty outpath). Returns the generated `ReferenceStep` expression directly (no `ReferencePath` wrapper).

Export from `ReferenceBuilderModule` and re-export from [Projectured.jl:153, 336](../program/src/Projectured.jl).

Add unit tests in [test/src/reference/](../test/src/reference/) (or wherever the existing macro tests live — `grep` for `@reference` test files).

### 4. Update guide — [guide/editor/reference.md](../guide/editor/reference.md)

The "Reference DSL: `@reference`" section needs a new sub-section covering `^()` splice, `{s:e}` range syntax, and `@step`. The "Reference Pattern Matching: `@reference_case`" section needs `{s:e}` added to the pattern list. Mention the runtime dispatch behavior of `^()` (path vs step).

Also update [guide/projection-system.md](../guide/projection-system.md) where it shows printer/reader examples — switch the examples to the new splice syntax.

### 5. Add identity-passthrough helper — [program/src/common/Projection.jl](../program/src/common/Projection.jl)

```julia
"""
    @passthrough_value_cursor reference

Expands to the `@reference_case` that maps `.value{k}` to itself and falls
through otherwise. Used by leaf projections (PrimitiveBool, JsonString, …)
whose only mappable input reference is a cursor inside `.value`.
"""
macro passthrough_value_cursor(ref)
    quote
        @reference_case $(esc(ref)) begin
            value{k} => @reference value{k}
        end
    end
end
```

Export it. Then in [PrimitiveToSyntax.jl](../program/src/projection/primitive/PrimitiveToSyntax.jl) and [JsonToSyntax.jl](../program/src/projection/primitive/JsonToSyntax.jl), replace the eight pairs of identity `map_reference_forward` / `map_reference_backward` functions (lines 36-46, 70-80, 107-117 of PrimitiveToSyntax; 66-76, 102-112, 142-152 of JsonToSyntax) with one-liners:

```julia
map_reference_forward(::PrimitiveBoolToSyntaxLeaf, iomap, reference)  = @passthrough_value_cursor reference
map_reference_backward(::PrimitiveBoolToSyntaxLeaf, iomap, reference) = @passthrough_value_cursor reference
```

This deletes ~80 lines and removes the only existing `@reference` usage from these files, replacing it with a more semantic name. (Net effect on `@reference` adoption is positive elsewhere — see migration list below.)

### 6. Migration — high-impact files

The following files have raw construction patterns that the extended `@reference` can now express cleanly. Each is a separate commit:

| File | Approx. raw sites | Notable patterns |
|---|---|---|
| [BookToSyntax.jl](../program/src/projection/primitive/BookToSyntax.jl) | 59 | `CP(Field("children"), CP(Element(2), CP(Field("children"), CP(Element(i), inner))))` → `@reference children[2].children[^(i)].^(inner)` |
| [JuliaToSyntax.jl](../program/src/projection/primitive/JuliaToSyntax.jl) | 41 | similar nested `.children[i]` chains |
| [MathToSyntax.jl](../program/src/projection/primitive/MathToSyntax.jl) | 37 | similar |
| [JsonToSyntax.jl](../program/src/projection/primitive/JsonToSyntax.jl) | 27 | `_translate_json_path` / `_forward_json_path` rebuild chains |
| [XmlToSyntax.jl](../program/src/projection/primitive/XmlToSyntax.jl) | 20 | `_translate_xml_path` / `_forward_xml_path` |
| [SyntaxToText.jl](../program/src/projection/primitive/SyntaxToText.jl) | 20 | `_pos_to_selection`, `_text_elem_path` |
| [ConversationToWidget.jl](../program/src/projection/primitive/ConversationToWidget.jl) | 18 | conversation entry path rebuilds |
| [WorkbenchToWidget.jl](../program/src/projection/primitive/WorkbenchToWidget.jl) | 16 | document slot path rebuilds |
| [PrimitiveToText.jl](../program/src/projection/primitive/PrimitiveToText.jl) | 11 | mirrors `PrimitiveToSyntax` |
| [Focusing.jl](../program/src/projection/generic/Focusing.jl) | 11 | uses `_concat_path` / `_drop_last` helpers that may simplify against `@reference` |
| [TextToGraphics.jl](../program/src/projection/primitive/TextToGraphics.jl) | 10 | `_build_selection_path` is `@reference elements[span].content{char}` |
| [Copying.jl](../program/src/projection/generic/Copying.jl) | 10 | passthrough |
| [WorkbenchAssistant.jl](../program/src/editor/WorkbenchAssistant.jl) | 10 | `_input_path` is `@reference input.value.^(range)` |
| [TableToGraphics.jl](../program/src/projection/primitive/TableToGraphics.jl) | 8 | `cells[i].content` paths |
| [Sorting.jl](../program/src/projection/generic/Sorting.jl) | 6 | `append_reference(reference, PositionReference(i))` → keep `append_reference` (runtime varargs) or use `@reference ^(reference){i}` |

Two files stay as-is because they touch internals:
- [program/src/document/Primitive.jl](../program/src/document/Primitive.jl) — `evaluate_operation` constructs the new-cursor path from runtime values; one site is `ConcreteReferencePath(RangeReference(new_pos, new_pos), EmptyReferencePath())` which becomes `@reference {^(new_pos)}` (still useful) but the surrounding code reads paths step-by-step and is clearer without the macro.
- [program/src/reference/Reference.jl](../program/src/reference/Reference.jl) — defines the constructors; cannot use the macro.

**Migration recipe** for each file:
1. Replace nested `ConcreteReferencePath(FieldReference(f), …)` chains with `@reference f.…`.
2. Replace `ConcreteReferencePath(step, path.tail)` with `@reference ^(step).^(path.tail)` (or, more readably, swap `path.tail` for a named local first).
3. Replace `ConcreteReferencePath(RangeReference(s, e), EmptyReferencePath())` with `@reference {^(s):^(e)}`.
4. Replace `append_reference(reference, FieldReference("f"), ElementReference(i))` with `@reference ^(reference).f[^(i)]`.
5. Run the file's printer/reader tests; the output paths must `==` the originals.

## Verification

1. **Per-file tests.** Each migrated projection has selection round-trip tests in [test/src/](../test/src/) — see [guide/testing.md](../guide/testing.md). Running `test_printers`, `test_readers`, `test_selections` for the touched projection is the bisect-friendly checkpoint.
2. **Macro tests.** Add a `test/src/reference/ReferenceBuilderTest.jl` (or extend existing) covering:
   - `@reference a.^(p)` where `p::ReferencePath` concatenates correctly
   - `@reference a.^(s)` where `s::ReferenceStep` wraps then concatenates
   - `@reference ^(p)` at the very front
   - `@reference a.^(p).b` with splice in the middle
   - `@reference xs{1:3}` produces `RangeReference(1, 3)`
   - `@step value` returns `FieldReference("value")`
   - `@step xs[i]` returns `ElementReference(i)`
   - `@step xs{1:3}` returns `RangeReference(1, 3)`
3. **End-to-end.** `test_all` from [guide/testing.md](../guide/testing.md) must pass with zero new failures. The driving examples ([example/](../example/)) must still render the same screenshots — run [test/src/editor/](../test/src/editor/) regression tests.
4. **`grep` audit.** After migration, the count of raw `ConcreteReferencePath(` outside `program/src/reference/` and `program/src/document/` should drop from ~469 to under ~50 (only places that genuinely need runtime introspection or single-step construction).

## Out of scope

- A bidirectional/inverse macro that emits both `map_reference_forward` and `map_reference_backward` from one declaration. Several leaf projections have nearly-identical forward/backward bodies; collapsing them into a single declaration is a follow-up that should land after we know which shapes are actually shared.
- Replacing `append_reference` with the splice DSL across the board. `append_reference` with varargs of runtime steps (as in the recursive printer loops in `JsonArrayToSyntaxNode`, `XmlElementToSyntaxNode`, `BookBookToSyntaxNode`) is already concise; converting them to `@reference ^(reference).elements[^(i)]` is a wash. Keep the macro use focused on places where it removes nesting.
- Anything in `program/src/reference/` itself — those modules construct paths from runtime values and benefit nothing from the macro.
- A `@reference` form that accepts a leading `^(base)` to mean "start from this path" instead of "splice this path in". Use the splice operator — `@reference ^(base).rest` already reads correctly.
- Removing `[s, e]` (two-arg `:ref`) as a range syntax. Keep it as an alias for `{s:e}` to avoid breaking existing call sites; just stop documenting it as primary.
