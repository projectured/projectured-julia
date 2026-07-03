"""
    ComponentModule

The component document domain. Components are higher-level UI building blocks
composed from widget primitives. While widgets provide atomic UI elements
(labels, text fields, scroll panes, split panes), components combine them
into reusable, behavioral units that deliver user-facing functionality.

Components sit between the widget layer and the application layer (workbench):

    Document (domain data) → Component (behavioral UI) → Widget (atomic UI) → Graphics → Screen

A component projects to a widget tree via its own projection (ComponentToWidget),
and can be embedded anywhere a Document is accepted — inside a WorkbenchEditor,
inside another component, or as a standalone top-level document.
"""
module ComponentModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference
export ComponentDocument,
       ComponentMasterDetail,
       IComponentMasterDetail

# ── ComponentDocument (abstract base) ────────────────────────────────────────

"""
    ComponentDocument

Abstract base type for all component documents. Components are composed
from widget primitives and deliver higher-level interactive behavior
(e.g. master-detail selection, forms, dashboards).

Like all documents, every concrete component carries a `selection::Reference`
field.
"""
abstract type ComponentDocument <: Document end

# ── ComponentMasterDetail ────────────────────────────────────────────────────

"""
    ComponentMasterDetail(master, detail; master_title, detail_title, split_ratio)

A two-pane component: the *master* pane (typically a tree or list) on the
left and the *detail* pane (typically an inspector or form) on the right.

Selecting an item in the master pane updates the detail pane reactively.
The detail content is driven by the `detail` cell, which can be set up as
a reactive thunk that recomputes whenever `selected_item` changes.

Fields
------
- `master::Document`       — the document shown in the left/master pane
- `detail::Document`       — the document shown in the right/detail pane (reactive)
- `selected_item::Any`     — the currently selected item from the master pane
- `master_title::String`   — display title for the master pane
- `detail_title::String`   — display title for the detail pane
- `split_ratio::Float64`   — fraction of width allocated to the master pane (0.0–1.0)
- `selection::Reference`   — cursor/selection position within this component
"""
@document struct ComponentMasterDetail <: ComponentDocument
    master::Document
    detail::Document
    selected_item::Any
    master_title::String
    detail_title::String
    split_ratio::Float64
    selection::Reference
end

function ComponentMasterDetail(master::Document, detail::Document;
                               selected_item = nothing,
                               master_title::AbstractString = "Master",
                               detail_title::AbstractString = "Detail",
                               split_ratio::Float64 = 0.3)
    ComponentMasterDetail(Cell(master), Cell(detail),
                          Cell(selected_item),
                          Cell(String(master_title)), Cell(String(detail_title)),
                          Cell(split_ratio),
                          Cell(nothing))
end

end # module
