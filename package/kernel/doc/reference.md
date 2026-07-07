# The reference layer

Layer 3 of the kernel — **paths into documents**. A reference is a linked list
of typed steps addressing one location inside a document tree. This page is
the layer's structural overview; the hands-on "how do references work" guide
is in [documentation/editor/reference.md](../../../documentation/editor/reference.md).

The layer lives in [main/reference/](../main/reference/), inside one aggregator
module (`ReferenceModule`) split across three fragments that share its
namespace:

```
ReferenceModule.jl       (ReferenceModule)             — the aggregator
        │ imports Cell (from CellModule) and @document (from DocumentModule)
        │ and exports every public name below
        ├─ Reference.jl        — the step + path types (RangeReference,
        │                        FieldReference, TypeReference, …,
        │                        EmptyReferencePath, ConcreteReferencePath)
        │                        plus the value protocol on them
        │                        (append_reference, evaluate_reference,
        │                        annotate_reference_types, …)
        ├─ ReferenceCase.jl    — the @reference_case pattern-matching DSL
        │                        (destructures a path against pattern => result
        │                        rules), plus when/prefix guards
        └─ ReferenceBuilder.jl — the @reference / @step construction DSL
                                 (compact surface syntax for building paths)
```

The three fragments are only ever imported together, so they share one
`ReferenceModule` namespace instead of being separate modules — splitting
them would just multiply import headers. They still live in separate files
for readability, but as **fragments** (0-module files sharing the
aggregator's namespace), not separate modules.

## Step kinds

Each step descends one level into a document tree. The full vocabulary:

| Step | Selects | Notes |
| --- | --- | --- |
| `FieldReference("foo")` | the field named `foo` | resolved by `getfield(doc, :foo)` — struct field names are public API |
| `ElementReference(i)` | the *i*-th element of a sequence | 1-based (Julia convention) |
| `PositionReference(k)` | position *k* in a sequence | a zero-width range |
| `RangeReference(s, e)` | the range `s..e` | `Element` and `Position` are backward-compatible constructor aliases |
| `TypeReference(T)` | a same-position `::T` checkpoint | annotates a step for round-tripping |
| `FunctionReference(f)` | a function value | for closures held by name |
| `ProjectionReference(p, sub)` | a projection-introduced element | see the opaque-payload pattern below |
| `PointReference(x, y)` | a pixel coordinate | for graphics/geometry endpoints |
| `TextRectangularReference(…)` | a rectangular text region | text-domain endpoint |

A `ReferencePath` chains steps: `EmptyReferencePath()` at the root,
`ConcreteReferencePath(step, tail)` for a non-empty path. The list *shape* is
persistent — extending a path reuses the existing tail rather than copying —
but each `@document`-backed step/path struct is mutable and stores its
dynamic values in reactive `Cell`s, so `update_selection!` can move a caret
by writing those cells in place without rebuilding the chain.

## Two DSLs — construction and destructuring

The two DSLs are surface-syntax siblings:

- **Construction (`@reference` / `@step`)** — turn compact source like
  `@reference a.b[3].{c:e}` into the nested
  `ConcreteReferencePath(FieldReference("a"), …)` you would otherwise write
  by hand. `^(expr)` splices a runtime path or step into the literal;
  `@step` produces a single step for the same syntax.
- **Destructuring (`@reference_case`)** — matches a path against
  `pattern => result` rules (à la Julia's `match`), binding the variable
  parts (indices, field names, tails) for the result expression. The
  `when(pattern, cond)` and `prefix(pattern)` helpers add a guard and a
  prefix-rather-than-exact match.

Both operate on the same reference vocabulary. Domain code that both
constructs and matches references (every non-trivial `read_intent`) benefits
from having them side by side — a change to one DSL's syntax is a change to
its twin's grammar.

## The opaque-payload pattern (a documented layer-edge)

`ProjectionReference` stores its projection as an **untyped `Any` payload**
— the reference layer defines only the step's shape and never imports
`Projection`. Only higher layers (the projection layer) construct and
interpret the payload. So the only edge between projection and reference
is `projection → reference` (for `PrinterContext`, reference mapping, and
similar), and it points down. This is the same pattern `Intent` uses
(the reader's backward-flowing type), and it is the kernel's answer to
"you'd think this needs a cycle" cases: mention the higher type opaquely,
never call into it.

The `Reference.jl` fragment documents this at the type declaration.

## Downward edges

- `..CellModule: Cell, AbstractCell` — the reactive box the mutable step
  fields live in.
- `..DocumentModule: @document` — the macro that builds each step/path
  struct with its cells.

That's the whole import surface of the layer. No projection, no operation,
no device. This is what makes the reference layer sit at index 3 in the
kernel's dependency DAG.

## Testing

`test/reference/` migrates ProjecturedTest's `ReferenceBuilderTest.jl`
verbatim (rewritten to `using ProjecturedKernel.ReferenceModule` — no
umbrella needed) and adds `ReferenceEvalTest.jl` which walks
`evaluate_reference` over a test-local `@document struct ToyBranch`. No
concrete engine document is imported; the reference DSLs must stand on
their own.
