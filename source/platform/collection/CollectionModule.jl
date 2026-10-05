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

using ..CellModule
using ..CellStructModule
using ..DocumentModule
using ..ReferenceModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: copy_document, sync_document!, has_document_duplicate,
                         is_element_collection, is_collection_field_type,
                         get_cell_layout_field_type
import ..OperationModule: child_reference_steps, get_slot_at
import ..ProjectionModule: make_children_container, get_children_container_type

export CollectionDocument, CellVector, CellMatrix, CellTable, ListNode,
       get_left_tail, get_right_tail, find_list_node, make_index_list, get_cell_at, take_first,
       count_computed_nodes, insert_row!, insert_column!, delete_row!, delete_column!


include("CellVector.jl")
include("CellMatrix.jl")
include("CellTable.jl")
include("ListNode.jl")
include("CollectionDocument.jl")

end # module
