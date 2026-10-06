# Fragment of `NavigatorModule` — the edit of the address in the path view, as in
# the address bar of a browser: Ctrl+L starts it, Enter opens the path that the
# steps name, and Escape ends it. Each operation writes the address copy as view
# state and moves the selection, with a path from the navigator.

"""
    make_navigator_address_edit_operation(navigator) -> Operation or nothing

The operation that starts an edit of the address of `navigator` in the path view,
as Ctrl+L does: the address copy takes the steps of the page and an empty
`ReferenceInsertion` after them, which holds the caret. The copy keeps the view
before the edit, which the end of the edit shows again. `nothing` while an edit is
on.
"""
function make_navigator_address_edit_operation(navigator::Navigator)
    draft = navigator.address_draft
    draft.edited && return nothing
    steps = CellVector(Cell[Cell(step) for step in Any[get_reference_steps(get_navigator_page_address(navigator))...,
                                                       ReferenceInsertion()]])
    n = length(steps)
    caret = annotate_reference_types(steps, Reference(RangeReferenceStep(n - 1, n), FieldReferenceStep("value"),
                                                      RangeReferenceStep(0, 0)))
    writes = Any[ReplaceReferencedValueOperation(draft, "view_before", draft.view),
                 ReplaceReferencedValueOperation(draft, "view", :path),
                 ReplaceReferencedValueOperation(draft, "steps", steps),
                 ReplaceReferencedValueOperation(draft, "unreached_step", 0),
                 ReplaceReferencedValueOperation(draft, "edited", true)]
    CompoundOperation(Any[ReplaceViewStateOperation(CompoundOperation(writes)),
                          ReplaceSelectionOperation(_make_draft_path(navigator, caret))])
end

"""
    make_navigator_address_commit_operation(navigator) -> Operation or nothing

The operation that Enter answers in the path view: the steps of the address copy,
with the text of each insertion read as steps, opened as a visit, and the view
before the edit shown again. A path that does not reach to its end stays in the
copy, with its insertions as steps, the selection on the first step that reaches
no node, and `unreached_step` on it. An insertion whose text is no path stays as
it is, and the operation does nothing. `nothing` while no edit is on.
"""
function make_navigator_address_commit_operation(navigator::Navigator)
    draft = navigator.address_draft
    draft.edited || return nothing
    steps = ReferenceStep[]
    for step in draft.steps
        parsed = _parse_step_text(step)
        parsed === nothing && return DoNothingOperation()
        append!(steps, parsed)
    end
    address = extend_reference(EmptyReference(), steps...)
    reached = length(get_reference_steps(get_valid_reference_prefix(navigator.content, address)))
    if reached == length(steps)
        show_before = ReplaceViewStateOperation(ReplaceReferencedValueOperation(draft, "view", draft.view_before))
        opened = make_navigator_open_operation(navigator, address)
        opened === nothing && return make_navigator_address_reset_operation(navigator)
        return CompoundOperation(Any[opened, show_before])
    end
    kept = CellVector(Cell[Cell(step) for step in steps])
    writes = Any[ReplaceReferencedValueOperation(draft, "steps", kept),
                 ReplaceReferencedValueOperation(draft, "unreached_step", reached + 1)]
    unreached = annotate_reference_types(kept, Reference(RangeReferenceStep(reached, reached + 1)))
    CompoundOperation(Any[ReplaceViewStateOperation(CompoundOperation(writes)),
                          ReplaceSelectionOperation(_make_draft_path(navigator, unreached))])
end

"""
    make_navigator_address_reset_operation(navigator) -> Operation or nothing

The operation that Escape answers in the path view: the address copy is the
address again, the view before the edit shows, and the page is selected. `nothing`
while no edit is on.
"""
function make_navigator_address_reset_operation(navigator::Navigator)
    draft = navigator.address_draft
    draft.edited || return nothing
    writes = Any[ReplaceReferencedValueOperation(draft, "edited", false),
                 ReplaceReferencedValueOperation(draft, "steps", CellVector()),
                 ReplaceReferencedValueOperation(draft, "unreached_step", 0),
                 ReplaceReferencedValueOperation(draft, "view", draft.view_before)]
    page = annotate_reference_types(navigator.content, get_navigator_page_address(navigator))
    CompoundOperation(Any[ReplaceViewStateOperation(CompoundOperation(writes)),
                          ReplaceSelectionOperation(ConcreteReference(get_reference_node_type(navigator),
                                                                      _CONTENT_STEP, page))])
end

"""
    is_navigator_address_selected(navigator) -> Bool

Whether a person edits the address of `navigator`: an edit is on, and the
selection is in the address copy.
"""
function is_navigator_address_selected(navigator::Navigator)
    navigator.address_draft.edited || return false
    selection = navigator.selection
    selection isa ConcreteReference && get_reference_head(selection) == _DRAFT_STEP
end

const _DRAFT_STEP = FieldReferenceStep("address_draft")
const _STEPS_STEP = FieldReferenceStep("steps")

# The path from `navigator` to `rest`, a typed path in the steps of its address
# copy.
_make_draft_path(navigator::Navigator, rest) =
    ConcreteReference(get_reference_node_type(navigator), _DRAFT_STEP,
                      ConcreteReference(get_reference_node_type(navigator.address_draft), _STEPS_STEP, rest))
