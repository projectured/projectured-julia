# The operation layer

Layer 4 of the kernel — **changing documents**. An operation is the reified
edit the reader side of the projection pipeline produces and
`evaluate_operation` applies. The layer holds the abstract `Operation`
supertype, the built-in concrete operations, the selection propagation, the
splice helpers, and — new in P4 — the **two open seams** every path-bearing
operation or container document extends.

The layer lives in [src/operation/](../src/operation/), inside one aggregator
module (`OperationModule`) split across three fragments:

```
OperationModule.jl        (OperationModule)             — the aggregator
        │ imports Cell + Document + Reference; exports every public name
        ├─ Interface.jl        — Operation abstract + evaluate_operation +
        │                        invalidate_projection! generics
        ├─ Operations.jl       — the built-in ops (DoNothing, ReplaceSelection,
        │                        ReplaceReferencedValue, CompoundOperation,
        │                        SelectNextInsertion, Adjust*, Quit,
        │                        ToggleCollapse), splice helpers, selection
        │                        propagation (clear/set/update), and the
        │                        R1 child_reference_steps seam
        └─ Rerooting.jl        — reroot_reference + the R2 open
                                 reroot_operation seam with its base methods
```

Kernel plan P4 merged the former `OperationApiModule` (`api/OperationApi.jl`),
`OperationModule` (`common/Operation.jl`), and `OperationRerootingModule`
(`common/OperationRerooting.jl`) — three modules only ever imported together.
The three files remain as fragments sharing this namespace.

## R1 — the open `child_reference_steps(node)` traversal seam

Before P4, `SelectNextInsertionOperation`'s pre-order document walk was hard-coded:

```julia
function _preorder_documents!(node, ...)
    ...
    if node isa CellVector
        for i in 1:length(node)
            _preorder_documents!(node[i], append_reference(path, RangeReference(i-1, i)), ...)
        end
        return
    end
    for nm in fieldnames(typeof(node))
        ...
```

The `isa CellVector` branch was the smell — an operation-layer file
hard-referencing a concrete document type. R1 dissolves it into an open
generic:

```julia
function child_reference_steps end                # declaration in Operations.jl

child_reference_steps(node) = [(FieldReference(...), val), ...]   # default (fieldnames)

# in document/Collection.jl (moves to base at P7):
child_reference_steps(node::CellVector) = [(RangeReference(i-1, i), node[i]), ...]
```

A new container document type adds a `child_reference_steps` method beside its
type definition. The default handles ordinary structs.

**Testing pressure.** `test/operation/TraversalTest.jl` defines a test-local
`@document struct ToyList` and registers its own `child_reference_steps`
method — the exact pressure that keeps the seam honest. If a fresh test-local
type couldn't drive the walk, the seam wouldn't be open.

## R2 — the open `reroot_operation(op, steps)` generic

Before P4, `reroot_operation` was a closed if-chain:

```julia
function reroot_operation(op, steps)
    op === nothing && return nothing
    if op isa ReplaceReferencedValueOperation ...
    elseif op isa ReplaceSelectionOperation ...
    elseif op isa ReplaceStringRangeOperation ...      # ← Primitive!
    elseif op isa ReplaceNumberRangeOperation ...      # ← Primitive!
    elseif op isa CompoundOperation ...
    else op
    end
end
```

The `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation` branches
imported `PrimitiveModule` from a lower kernel layer — a wrong-direction edge.
R2 converts it to an open generic, with the base methods in
`Rerooting.jl`:

```julia
function reroot_operation end
reroot_operation(::Nothing, steps) = nothing
reroot_operation(op, steps) = op                      # catch-all: unchanged
reroot_operation(op::ReplaceSelectionOperation, steps) = ...
reroot_operation(op::ReplaceReferencedValueOperation, steps) = ...
reroot_operation(op::CompoundOperation, steps) = ...
```

The `Primitive` methods now live in `document/Primitive.jl` beside the
operation type declarations (they leave with Primitive for base at P7):

```julia
# document/Primitive.jl:
reroot_operation(op::ReplaceStringRangeOperation, steps) =
    ReplaceStringRangeOperation(reroot_reference(op.reference, steps), op.replacement)
reroot_operation(op::ReplaceNumberRangeOperation, steps) = ...
```

**Invariant.** A new path-bearing operation type MUST add a `reroot_operation`
method. Missing methods fall through to the catch-all and are returned
unchanged — their reference is not rerooted. Kept in sync with the default
`ProjectionModule.read_intent`; see documentation/operations.md.

**Testing pressure.** `test/operation/RerootingTest.jl` declares a test-local
`ToyPathOp <: Operation` and registers its own `reroot_operation` method,
proving the seam is genuinely open — you cannot depend on a concrete
higher-layer type at layer 4.

## Downward edges

- `..CellModule: Cell, AbstractCell`
- `..DocumentModule: Document, clear_selection!, set_selection!, with_selection`
- `..ReferenceModule: ReferencePath, …, append_reference, evaluate_reference, …`

That is the whole import surface. No projection, no device, no editor. This
is what keeps the operation layer at index 4 in the DAG.
