"""
    ProjectionModule

Shared projection interface. Declares the four generic functions every
projection implements — `print_document`, `read_intent`,
`map_reference_forward`, `map_reference_backward` — dispatched on by all
projection types, primitive and higher-order alike. Keeping the interface here
avoids circular dependencies between projection modules.

The four functions form two symmetric pairs, one per direction of data flow:

- **Forward (printing).** `print_document` transforms input → output and, for
  the cursor, calls `map_reference_forward` to map the input selection into an
  output selection.
- **Backward (reading).** `read_intent` turns an output-domain event/
  operation back into an input-domain operation and, for the cursor, calls
  `map_reference_backward` to map an output reference into an input reference.

Rule of thumb: **`print_document` uses `map_reference_forward`;
`read_intent` uses `map_reference_backward`.** The two mappers are the
single source of truth for how a path crosses this projection — written once,
reused on both sides.

# The recursion contract

These four functions are **the** interface every projection implements — nothing
else is universal. The contract that keeps arbitrary projections composable is:

> Recursion across projections flows **only** through these four functions. When a
> projection descends into a child document, each function hands that child to the
> **child projection's own** version of *the same* function. The vehicles are the
> `recursion` parameter — invoked via `print_child(recursion, child,
> ctx)` on the printer side — and the **stored child IoMaps**
> (`ChildrenIoMap.child_iomaps`) that the reader and both mappers walk on the
> backward side. Each function maps its **own single level** and delegates the rest.

Two things are therefore **forbidden**:

1. **No fifth recursive function.** A projection must not introduce a *new*
   generic function to perform descent. The four above are implemented by every
   projection; a fifth would not be, so the first pipeline that composes a
   projection needing it with one that does not breaks at that boundary. All
   descent must ride the functions everyone already implements. (This is also why
   the contract is validated *externally*, by a harness driving these four — see
   [documentation/guide/testing-guide.md](../../../documentation/guide/testing-guide.md)
   — never by adding an interface method.)
2. **No self-walking / flattening by child type.** A function must not recurse over
   the input (or output) subtree itself, dispatching on each child's concrete type,
   and bake the whole subtree into its result. That hard-codes which projection
   renders each descendant and forecloses composing a child with another domain or
   a substituted projection — the "School B" anti-pattern. Delegate through the
   child IoMap / `recursion` instead ("School A").

See [projection-system.md](../../../documentation/package/kernel/projection-system.md)
("The recursion contract" and "Recursion across projections") for worked recipes
and [selection.md](../../../documentation/package/kernel/selection.md) for the
selection mechanism.

# The fragments

| Fragment | Contract |
|---|---|
| [`PrinterContext.jl`](PrinterContext.jl) | `PrinterContext` — the range of each axis, the clock and the properties a printer carries down the tree |
| [`ProjectionReferenceStep.jl`](ProjectionReferenceStep.jl) | `ProjectionReferenceStep` — a reference step pointing at an element a projection introduced |
| [`ProjectionInterface.jl`](ProjectionInterface.jl) | the `Projection` supertype, the four open generics and the open seams |
| [`ProjectionDefaults.jl`](ProjectionDefaults.jl) | the fallback method of each generic |
| [`OutputPaths.jl`](OutputPaths.jl) | `make_output_path_cells` — every kind of path of an output document, from one forward map; `set_output_tree_path_computations!` carries them down a built output |
| [`ProjectionMacro.jl`](ProjectionMacro.jl) | `@projection` — the projection codegen |
| [`ProjectionGestureBindings.jl`](ProjectionGestureBindings.jl) | the default gesture table of a projection, and `read_projection_gesture` |
| [`ProjectionTemplate.jl`](ProjectionTemplate.jl) | `@projection_template` — the builder-and-walk engine that many structural projections are written with |
"""
module ProjectionModule

using ..CellModule
using ..CellStructModule
using ..ClockModule
using ..DocumentModule
using ..EventModule
using ..FaultModule
using ..GestureBindingModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ReferenceModule
using ..SelectionModule

export Projection, print_document, print_child, print_document_pure, print_child_pure,
       read_intent, map_reference_forward, map_reference_backward, read_routed_intent,
       get_child_iomaps, read_routed_child, read_child_by_route, read_gesture_outward,
       get_content_iomap
export show_barrier_mark!, retry_barrier_print!
export @projection, print_pure
export make_output_path_cells, set_output_path_computations!, map_mouse_target_forward,
       set_output_tree_path_computations!
export read_move_answer
export ProjectionReferenceStep, make_introduced_reference, is_introduced_reference,
       has_introduced_step, find_introduced_path, normalize_named_node_reference
export PrinterContext, make_child_context, with_exact_size, with_bounded_size, with_size_range,
       with_inner_size, get_exact_width, get_exact_height, with_free_axis, with_clock,
       with_property, get_property
export make_children_container, get_children_container_type,
       get_projection_gesture_bindings
export read_projection_gesture
export TemplateIoMap, var"@projection_template"
export print_template_document, read_template_intent, make_template_builder,
       find_template_value_retype, find_template_output_child

include("PrinterContext.jl")
include("ProjectionReferenceStep.jl")
include("ProjectionInterface.jl")
include("ProjectionDefaults.jl")
include("OutputPaths.jl")
include("ProjectionMacro.jl")
include("ProjectionGestureBindings.jl")
include("ProjectionTemplate.jl")

end # module
