# Fragment of `ArrangementModule` — the bar of an arranged place: the stage of the
# chain of an entry that shows the chips of the entry above the items of the place.

"""
    ArrangementBarProjection(entry)

The stage of the chain of `entry` that shows its chips. It puts the items of the
place second in a `VerticalLayout`, under the `ArrangementChips` of `entry`, and
the printer of the place prints that layout, so the layout routes a press and
maps a path. A path of the items goes below `children[2]`
(`get_arranged_wrap_steps`). The children of the layout fill its width and share
its height, and the chips are in a `LayoutConstraint` that keeps them as tall as
they draw, so the items get the height that the chips leave as a slot: a table
or a list of rows fills it and scrolls its rows there.

The chips are a part that the bar drew, so a path in them is named by the
introduced step of the bar, which holds the path in the layout: for the caret in
the text of a condition, `‹bar: .children[1].child.entry.projections[1].conditions[2].value[3:3]›`
at the place. Below `children[1].child` the path goes through the entry itself, so a
field of the chips edits a document. The stages before the bar pass that step
through, and the bar takes it off.
"""
struct ArrangementBarProjection <: Projection
    entry::Any
end

@iomap struct ArrangementBarIoMap
    projection::Any
    input::Any
    output::Any
end

get_arranged_wrap_steps(::ArrangementBarProjection) = (FieldReferenceStep("children"), ElementReferenceStep(2))

function print_document(p::ArrangementBarProjection, recursion, input, ctx)
    total = get_property(ctx, :arranged_count, nothing)
    chips = ArrangementChips(p.entry, 0, 0)
    set_cell_computation!(getfield(chips, :shown), () -> length(input))
    set_cell_computation!(getfield(chips, :total), () -> total === nothing ? length(input) : total[])
    layout = VerticalLayout(Any[LayoutConstraint(chips; height = Content), input];
                            child_width = Fill, child_height = Fill)
    # The selection and the part under the pointer go below `children[2]` for an
    # item and below `children[1].child` for a part of the chips, so a caret draws
    # in either.
    set_output_path_computations!(layout, input, path -> _map_bar_forward(p, path))
    set_output_path_computations!(chips, input, path -> _map_chips_forward(p, path))
    ArrangementBarIoMap(p, input, layout)
end

# The path in the layout for the path `path` of the items: a path in the chips
# for the introduced step of the bar, and a path of an item below `children[2]`.
function _map_bar_forward(p::ArrangementBarProjection, path)
    path isa Reference || return nothing
    chips = find_introduced_path(p, path)
    chips === nothing || return chips
    ConcreteReference(FieldReferenceStep("children"), ConcreteReference(ElementReferenceStep(2), path))
end

# The path in the chips for the introduced step of the bar, and `nothing` for any
# other path.
function _map_chips_forward(p::ArrangementBarProjection, path)
    path isa Reference || return nothing
    inner = find_introduced_path(p, path)
    inner === nothing && return nothing
    @reference_case inner begin
        children[1].child.rest... => rest
        __ => nothing
    end
end

map_reference_forward(p::ArrangementBarProjection, iomap::ArrangementBarIoMap, reference) =
    _map_bar_forward(p, reference)

function map_reference_backward(p::ArrangementBarProjection, iomap::ArrangementBarIoMap, reference)
    @reference_case reference begin
        children[2].rest... => rest
        children[1].rest... => make_introduced_reference(p, iomap, reference)
        __ => nothing
    end
end
