"""
    DocumentModule

The **document contract**: the `Document` abstract type, the `@document`
codegen, the protocol forward/adapt macros, and the shared value protocol every
concrete document reuses (`copy_document`, `sync_document!`).
It also carries the reflection walk over a document tree (`search_documents`,
with the `is_element_collection` / `is_walk_opaque` traits that steer it) — the
value-collecting search that needs no reference machinery. The kernel defines
only this contract; it carries no concrete documents.

The module is a set of fragments sharing this namespace, each documented at
its own definition:

| Fragment | Contract |
|---|---|
| [`DocumentInterface.jl`](DocumentInterface.jl) | the `Document` supertype + the contract generics (`is_element_collection` / `is_walk_opaque` / `copy_document` / `sync_document!` / `search_documents`) |
| [`DocumentDefaults.jl`](DocumentDefaults.jl) | the default behaviours every document inherits — the `is_element_collection` / `is_walk_opaque` trait answers, the defaults of the sync and copy policy hooks, and the depth-limited debug `show` |
| [`DocumentCopy.jl`](DocumentCopy.jl) | `copy_document` — deep copy, kind-preserving under a `CopyPolicy`, or kind-converting |
| [`DocumentSync.jl`](DocumentSync.jl) | `sync_document!` — the double-buffer shadow sync |
| [`DeclaredType.jl`](DeclaredType.jl) | the check of the declared type of a field at each write and at construction, `DeclaredTypeMismatchException`, and the records of an inventory |
| [`DocumentMacro.jl`](DocumentMacro.jl) | `@document` — the document codegen |
| [`SelectionDocument.jl`](SelectionDocument.jl) | `SelectionDocument` — the value a `selection` cell holds, and `unwrap_selection` |
| [`DocumentWalk.jl`](DocumentWalk.jl) | `walk_document` — the one reflection walk, parameterized by how it names a node (`DocumentWalk`) |
| [`DocumentSearch.jl`](DocumentSearch.jl) | `search_documents` — the value-collecting walk |
| [`ForwardProtocol.jl`](ForwardProtocol.jl) | `@forward_protocol` / `@forward_vector_protocol` / `@adapt_map_protocol` — give a wrapper another type's protocol |
"""
module DocumentModule

using ..CellModule
using ..CellStructModule
using ..FaultModule

export Document, copy_document, get_wrapped_document, replace_wrapped_document!, get_edited_field,
       sync_document!, get_document_family,
       get_document_cell_type, get_document_native_type, get_document_schema_name,
       get_document_title,
       is_descendable_for_sync, compute_sync_element_limit, make_unsynced_placeholder, HiddenElements,
       CopyPolicy, PlainCopyPolicy, DocumentCopyException, copy_document_fields,
       is_descendable_for_copy, make_copy_placeholder, copy_computed_cell, get_copy_memo,
       copy_selection_cell, is_view_state_field,
       DuplicatePolicy, has_document_duplicate, make_document_duplicate,
       is_element_collection, is_walk_opaque, is_collection_field_type,
       get_cell_layout_field_type, search_documents,
       @document, @document_preset,
       @forward_protocol, @forward_vector_protocol, @adapt_map_protocol
export DeclaredTypeMismatchException, DeclaredTypeMismatchRecord, PendingValue,
       set_declared_type_check_mode!, get_declared_type_check_mode,
       collect_declared_type_mismatches, clear_declared_type_mismatches!,
       find_declared_field_type, find_declared_element_type,
       convert_to_declared_type, convert_written_value, is_admitted_by_declared_type
export SelectionDocument, unwrap_selection
export DocumentWalk, walk_document, make_string_predicate
# how deep `show` descends before it elides
export DOCUMENT_SHOW_MAX_DEPTH

include("DocumentInterface.jl")
include("DocumentDefaults.jl")
include("DocumentCopy.jl")
include("DocumentSync.jl")
include("DeclaredType.jl")
include("DocumentMacro.jl")
include("SelectionDocument.jl")
include("DocumentWalk.jl")
include("DocumentSearch.jl")
include("ForwardProtocol.jl")

end # module
