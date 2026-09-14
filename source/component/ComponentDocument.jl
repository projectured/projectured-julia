# Fragment of `ComponentModule` — the component document types: the abstract
# `ComponentDocument` and the composite layouts built from it.

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
"""
@document struct ComponentMasterDetail <: ComponentDocument
    master::Document
    detail::Document
    selected_item::Any
    master_title::String
    detail_title::String
    split_ratio::Float64
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
