# Projection algebra

> **Kind:** design · **Status:** current · **Stands on:** [projection-system.md](../../kernel/projection-system.md), [architecture-invariants.md](../../../rule/architecture-invariants.md)

The projection slice of `ProjecturedPlatform` holds the projections that work on any document: the generic ones, which change the shape of a document, and the higher-order ones, which combine other projections. The kernel holds only the framework that they implement. This document says how the package divides the work with the kernel and which combinations carry the rest of the system; two guides describe each projection.

## How it works

The kernel defines the abstract `Projection`, the four functions (`print_document`, `read_intent`, `map_reference_forward`, `map_reference_backward`), the `IoMap`, the printer context and `@projection_template`. This package defines concrete projections on that framework. Its module is `ProjectionAlgebraModule`, because the kernel already has a `ProjectionModule`.

| Group | Projections | Guide |
| --- | --- | --- |
| Generic | `IdentityProjection`, `ConstantProjection`, `CopyingProjection`, `ReversingProjection`, `SortingProjection`, `FilteringProjection`, `SearchingProjection`, `FocusingProjection` | [generic-projections.md](generic-projections.md) |
| Higher-order | `ChainingProjection`, `TypeDispatchingProjection`, `PredicateDispatchingProjection`, `ReferenceDispatchingProjection`, `RecursiveProjection`, `SwitchingProjection`, `NestingProjection`, `WindowInputUnwrappingProjection` | [higher-order-projections.md](higher-order-projections.md) |
| Compound | `ApplyAtProjection`, `SortingAtProjection` | [higher-order-projections.md](higher-order-projections.md) |

No projection here names a document type of a domain. A generic projection works on the structure: a `CellVector`, a `ListNode`, or a struct with document fields. A dispatcher works on a key that the caller gives: a type, a predicate or a reference. This is the invariant `PAR-HIGHER-ORDER-IS-DOMAIN-FREE`.

### The three combinations that every domain uses

- **`RecursiveProjection(TypeDispatchingProjection(...))`** is the printer of a domain. The dispatcher picks the rule for the type of a node. The recursive wrapper gives itself as the `recursion` argument, so a rule prints its children with `print_child` and does not name the next rule.
- **`ChainingProjection(a, b, c)`** is the chain from a domain to the screen. It prints from left to right and reads from right to left. Its reader starts at the last step and gives the event to the earlier steps until one of them returns an operation. When an earlier step can not carry that operation, that step and the steps before it read the event again, as if no step had answered it.
- **`ApplyAtProjection(reference, projection)`** applies a projection at one place of a document and copies the rest. It is built from the others: a `ReferenceDispatchingProjection` copies the path from the root to the place with `CopyingProjection`, applies a `NestingProjection` at the place, and keeps everything else with `IdentityProjection`. `SortingAtProjection(reference, by)` is the common case.

### Rules that the combinations depend on

- **A stored recursion wins over an inherited one** in `NestingProjection`. So the projection that `ApplyAtProjection` applies at the place does not also apply to the nodes below the place.
- **`TypeDispatchingProjection` returns the IO map of the rule it chose**, not an IO map of its own. So the dispatcher adds no step to a reference path.
- **`SwitchingProjection` records which branch printed.** The reader then goes to the same branch, also after the switch cell changes.
- **`CopyingProjection` copies a `ListNode` lazily.** Only the head is copied at once; `prev` and `next` are cells that copy on the first read. So a copy of an infinite list costs one node.

`ReaderDefaults.jl` holds the default reader for a text edit through a template rule. It is here and not in the kernel, because it names `ReplaceStringRangeOperation`, a type of the primitive slice. It returns `nothing` for a text edit on a leaf with no bound field, such as `JsonNull`, and for a text edit of a delimiter that no field produces. The raw key then goes on to the structural gestures. The reader asks `find_template_value_retype` of the kernel for the `retype` of the leaf that the edit enters, and a node finds that leaf through its children, so a leaf in a container retypes an edit as it does when it is the document. A leaf whose `retype` is `ReplaceNumberRangeOperation` also returns `nothing` for a text with a character that can not be part of a number, so a letter typed into a number makes no edit; see [primitive.md](../primitive/primitive.md#the-range-edits).

## How it fits

The projection slice depends on the kernel, and on the collection slice for the containers and the primitive slice for the string edit. Nearly every slice above it composes its projections. It registers nothing.

Three higher-order projections live in other slices, because each one needs a slice above this one: `WindowManagingProjection` in the screen slice, `TooltipDecoratorProjection` in the tooltip slice, and `DraggingProjection` in the dragging slice.

## Design decisions

- **The framework is in the kernel, and the algebra is a package.** The kernel holds machinery and interfaces only, and no concrete projection. See [plan/done/projections-kernel-to-base.md](../../../../plan/done/projections-kernel-to-base.md).
- **Compose, do not add a combinator.** `ApplyAtProjection` is a combination of four projections, not a new type. A new need is first tried as a combination.

## Usage

```julia
sorted = ApplyAtProjection(@reference(entries), SortingProjection(by = e -> e.key))
sorted = SortingAtProjection(@reference(entries), e -> e.key)     # the same
chain  = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                            RecursiveProjection(SyntaxToText()),
                            TextToGraphics(measure = FontFileMeasure()))
choice = SwitchingProjection([JsonToSyntax(), XmlToSyntax()], Cell(1))
```

- Examples: `example/platform/` has one example for sorting, filtering, reversing, searching, and the lazy list copy.
- Tests: `test_sorting()`, `test_filtering()`, `test_reversing()`, `test_searching()`, `test_copying_projection()` and `test_switching()` in `test/platform/projection/`.

## Limits

- [plan/pending/parallel-projection.md](../../../../plan/pending/parallel-projection.md) describes a `ParallelProjection`. It does not exist.
