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
the focus back to the evaluator, so the next form can be typed. The pane opens to
the right of the evaluator, or under the pane whose title is `below`.

# Example

    show_lazy_list!(editor, primes, "Primes")
    show_lazy_list!(editor, sevens, "Sevens"; below = "Primes")
"""
function show_lazy_list!(editor, list::ListNode, title::AbstractString; below = nothing)
    view = make_lazy_list_view(list, title; clock = editor.clock)
    target = find_pane(editor, below === nothing ? "Evaluator" : below)
    pane = open_pane!(editor, view; title = title, target = target,
                      side = below === nothing ? :right : :below)
    # The new split moved the evaluator, so it is found again by its title.
    evaluator = find_pane(editor, "Evaluator")
    evaluator === nothing || focus_pane!(editor, evaluator)
    pane
end
