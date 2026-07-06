"""
    CollectionModule

Generic reactive collection document types. Four structural shapes: an indexed
growable vector (each slot is a reactive Cell), a dense rectangular matrix of
reactive Cells, a table (CellVector of CellVector rows) optimised for row
insert/delete, and a doubly-linked list with a fixed head and two unlimited
tails. Per-slot reactivity means a change to one element invalidates only that
slot's dependents, not the entire collection.

# Invariants
- **Value change vs. structural change.** `cv[i] = val` writes *into* slot `i`'s
  existing Cell — a value change that keeps the slot's dependents wired.
  `cv[i] = cell::Cell` *replaces* the slot's Cell — a structural change that
  drops the old cell's dependents (they will not be notified again).
- **Structural mutators must reassign `.elements`.** `push!`, `pop!`, `insert!`,
  `deleteat!`, and the `Cell`-replacing `setindex!` all mutate the underlying
  `Vector{Cell}` in place *and then* reassign `cv.elements = elems`. That
  reassignment (of the same object) is what fires the structure Cell and
  invalidates dependents that track the vector's shape; omitting it leaves
  structural observers stale. Any new structural mutator must do the same.
"""
module CollectionModule

import ..CellModule: Cell, AbstractCell, ReactiveCell, ImmutableCell, MutableCell, set_function!, set_value!
import ..DocumentModule: Document, copy_document, rekind, sync_document!, _same_cell,
       _same_wrapper, _shadow_elem, @document, @forward
import ..ReferenceModule: Reference, RangeReference
import ..OperationModule: child_reference_steps
import ..ChildrenContainerModule: make_children_container, children_container_type
export CollectionDocument, get_left_tail, get_right_tail, get_cell_at, take_first, insertrow!,
       insertcol!, deleterow!, deletecol!, insertrow, deleterow

# The four collection shapes, one fragment file each (fragments share this
# module's namespace). CellVector first — CellTable's rows are a CellVector.
include("collection/CellVector.jl")
include("collection/CellMatrix.jl")
include("collection/CellTable.jl")
include("collection/ListNode.jl")

"""
    CollectionDocument

Type alias for the union of the collection document types:
- `CellVector` — indexed growable vector (finite, eager);
- `CellMatrix` — dense rectangular matrix of cells;
- `CellTable`  — a `CellVector` of `CellVector` rows;
- `ListNode`   — doubly-linked list node (potentially infinite, lazy).
"""
const CollectionDocument = Union{CellVector, CellMatrix, CellTable, ListNode}

end # module
