function make_lazy_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        NestingProjection(CollectionToSyntax(), PrimitiveNumberToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

function make_lazy_bidirectional_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        NestingProjection(CollectionToSyntax(), PrimitiveNumberToSyntaxLeaf()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

"""
    make_lazy_list_view(list, title; clock) -> GridLayout

A lazy list in a scroll pane, under a label that says how many of its links exist:
"<title>, computed: N". The label counts with `count_computed_nodes`, which
computes no link, and it counts again on each tick of `clock`, so it follows what
the scroll pane reads. The layout fills its place, and the scroll pane takes the
height under the label.

# Example

    view = make_lazy_list_view(sieve(integers_from(2)), "Primes"; clock = editor.clock)
"""
make_lazy_list_view(list::ListNode, title::AbstractString; clock) =
    GridLayout(Any[
        WidgetLabel(() -> (get_reactive_clock_time(clock);
                           string(title, ", computed: ", count_computed_nodes(list)))),
        WidgetScrollPane(list)], 1;
        vertical_gap = 6, column_policy = Fill, row_policies = Any[Content, Fill])

"""
    show_lazy_list!(editor, list, title; below = nothing) -> ReferencedDocument

Opens `list` in a pane of its own, in the view of `make_lazy_list_view`, and gives
the focus back to the evaluator, so the next form can be typed.

The pane opens under the pane whose title is `below`. Left out, the lists fill the
window in the order that they are shown: the first opens to the right of the
evaluator, the second under the first, the third under the evaluator, and each
later one under the list before it.

# Example

    show_lazy_list!(editor, primes, "Primes")      # to the right of the evaluator
    show_lazy_list!(editor, sevens, "Sevens")      # under "Primes"
"""
function show_lazy_list!(editor, list::ListNode, title::AbstractString; below = nothing)
    view = make_lazy_list_view(list, title; clock = editor.clock)
    shown = filter(t -> find_pane(t; editor) !== nothing,
                   get!(() -> String[], _LAZY_LIST_TITLES, editor.tools))
    anchor, side = below !== nothing ? (below, :below) :
                   length(shown) == 0 ? ("Evaluator", :right) :
                   length(shown) == 1 ? (shown[1], :below) :
                   length(shown) == 2 ? ("Evaluator", :below) : (shown[end], :below)
    pane = open_pane!(view; title = title, target = find_pane(anchor; editor), side = side, editor)
    _LAZY_LIST_TITLES[editor.tools] = push!(shown, title)
    # The new split moved the evaluator, so it is found again by its title.
    evaluator = find_pane("Evaluator"; editor)
    evaluator === nothing || focus_pane!(evaluator; editor)
    pane
end

# The titles of the lists that `show_lazy_list!` opened, for each editor, in the
# order that they were opened. The table is weak, so an editor that is gone takes
# its list with it.
const _LAZY_LIST_TITLES = WeakKeyDict{Any,Vector{String}}()
