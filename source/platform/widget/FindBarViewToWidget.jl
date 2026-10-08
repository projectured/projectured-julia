# Fragment of `WidgetModule` — a find bar view as a vertical layout. The bar
# stands in a row with the button of its placement, and the row is above the
# content, or over it, or not there while the bar is hidden:
#
#     above    children[1].children[1].<rest>               the bar
#              children[1].children[2]                      the button
#              children[2].<rest>                           the content
#     over     children[1].children[1].<rest>               the content
#              children[1].children[2].children[1].<rest>   the bar
#              children[1].children[2].children[2]          the button
#     hidden   children[1].<rest>                           the content
#
# The printer prints no child. The layout stage that follows prints the layout
# through the recursion, which draws the bar and the content with the rows of
# their own types. A vertical layout prints its children again when its list
# changes, so a write of `visible` of the bar or of `overlaid` of the view
# arranges them again. The maps put the steps of the arrangement before a path in
# the bar or in the content, and take them off.

"""
    FindBarViewToWidget(; gap)

The projection of a [`FindBarView`](@ref): the bar above the content, or over it
at its top left corner, with a button beside the bar that switches between the
two. `gap` is the space between the bar and the content, and between the bar and
the button.

Chain it with `VerticalLayoutToGraphicsCanvas`, in a recursion that draws the
bar, the content and the layouts:

    FindBarView => ChainingProjection(FindBarViewToWidget(), VerticalLayoutToGraphicsCanvas())

Ctrl+F and Escape are rules of the `@gestures` table of the view. A key that the
part under the caret answered reaches that table as a claimed key, which the
`override` rules of the table take.
"""
struct FindBarViewToWidget <: Projection
    gap::Int
end

FindBarViewToWidget(; gap::Integer = get_widget_style(nothing, :section_gap)) =
    FindBarViewToWidget(Int(gap))

const _FIND_FIRST_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _FIND_SECOND_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))

function print_document(p::FindBarViewToWidget, recursion, view::FindBarView, ctx)
    button = _make_find_bar_placement_button(view)
    row = HorizontalLayout(CellVector(@computation Any[view.bar, button]), Cell(:top), Cell(p.gap),
                           Cell(nothing), Cell(nothing), Cell(nothing))
    stack = StackLayout(CellVector(@computation Any[view.content, row]), Cell(:left), Cell(:top),
                        Cell(0), Cell(nothing))
    output = VerticalLayout(CellVector(@computation _arrange_find_bar(view, row, stack)),
                            Cell(:left), Cell(p.gap), Cell(Fill), Cell(nothing), Cell(nothing))
    iomap = SimpleIoMap(p, view, output)
    # The layouts pass a key by their own selection, so each carries the part of
    # the path of the view below it. The bar and the content are documents of the
    # view, which hold their own.
    set_output_path_computations!(output, view, path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    set_output_path_computations!(stack, output, path -> _take_find_bar_steps(path, _FIND_FIRST_STEPS))
    set_output_path_computations!(row, output, path -> _take_find_bar_steps(path,
        view.overlaid ? (_FIND_FIRST_STEPS..., _FIND_SECOND_STEPS...) : _FIND_FIRST_STEPS))
    iomap
end

# The children of the layout, for the arrangement that the view shows now.
function _arrange_find_bar(view::FindBarView, row, stack)
    _is_find_bar_shown(view.bar) || return Any[view.content]
    view.overlaid ? Any[stack] : Any[row, view.content]
end

_is_find_bar_shown(bar) = _get_find_bar_flag(bar, :visible) !== false

# The steps from the layout to the bar, to the button and to the content, for the
# arrangement that the view shows now; `nothing` for a part that is not shown.
function _get_find_bar_part_steps(view::FindBarView)
    first, second = _FIND_FIRST_STEPS, _FIND_SECOND_STEPS
    _is_find_bar_shown(view.bar) || return (bar = nothing, button = nothing, content = first)
    view.overlaid ?
        (bar = (first..., second..., first...), button = (first..., second..., second...),
         content = (first..., first...)) :
        (bar = (first..., first...), button = (first..., second...), content = second)
end

# The button of the placement. Its press answers the switch of `overlaid`, read
# when the press comes, and its label says where a press puts the bar.
function _make_find_bar_placement_button(view::FindBarView)
    description = "Put the find bar over the content, or above it"
    press = GestureBinding(MouseClickPattern(:left),
                           (button, gesture) -> make_find_bar_placement_operation(view);
                           description, domain = "find bar")
    button = WidgetButton("Over"; gestures = GestureBinding[press], labels = ["Over", "Above"],
                          tooltip = description)
    set_cell_computation!(button, () -> view.overlaid ? "Above" : "Over")
end

# The part of `path` below `steps`, or `nothing` when `path` does not start with
# `steps`.
function _take_find_bar_steps(path, steps)
    for step in steps
        (path isa ConcreteReference && path.head == step) || return nothing
        path = path.tail
    end
    path
end

_has_find_bar_prefix(steps, prefix) =
    length(steps) >= length(prefix) && all(k -> steps[k] == prefix[k], eachindex(prefix))

# `bar.<rest>` ↔ the bar in the layout, and `content.<rest>` ↔ the content in it.
# A path in a side that is not shown has no image.
function map_reference_forward(::FindBarViewToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    reference isa ConcreteReference || return nothing
    view = iomap.input
    head = get_reference_head(reference)
    parts = _get_find_bar_part_steps(view)
    steps, side = head == _FIND_BAR_STEP ? (parts.bar, view.bar) :
                  head == _FIND_CONTENT_STEP ? (parts.content, view.content) : (nothing, nothing)
    steps === nothing && return nothing
    # The rest keeps the checkpoints that it came with; the steps of the layouts
    # take their types.
    rest = get_reference_tail(reference)
    is_fully_typed_reference(rest) ||
        (rest = annotate_reference_types(side, strip_reference_types(rest)))
    concat_references(annotate_reference_types(output, extend_reference(EmptyReference(), steps...)),
                      rest)
end

# A path into the button names nothing, so a press on it leaves the selection
# where it is; a path into a layout itself names the whole view.
function map_reference_backward(::FindBarViewToWidget, iomap::SimpleIoMap, reference)
    parts = _get_find_bar_part_steps(iomap.input)
    steps = get_reference_steps(strip_reference_types(reference))
    for (prefix, step) in ((parts.bar, _FIND_BAR_STEP), (parts.content, _FIND_CONTENT_STEP))
        (prefix === nothing || !_has_find_bar_prefix(steps, prefix)) && continue
        rest = reference
        for _ in prefix
            rest = get_reference_tail(rest)
        end
        return concat_references(ConcreteReference(step, EmptyReference()), rest)
    end
    parts.button !== nothing && _has_find_bar_prefix(steps, parts.button) && return nothing
    EmptyReference()
end

# The generic bridge maps the answer of the layout back, and reads the table of
# the view for a key that no part answered. A key that a part answered reaches the
# table as a claimed key, so only an `override` rule takes it over; a collection
# of the keys joins the keys of the table, for the gesture help.
function read_intent(p::FindBarViewToWidget, recursion, change::Intent, iomap::SimpleIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    change.operation === nothing && return answer
    own = _add_find_bar_answer(iomap.input, change.gesture, answer.operation, change.operation)
    own === nothing ? answer : Intent(change.gesture, own, answer.description, answer.domain)
end

_add_find_bar_answer(view::FindBarView, gesture::Union{KeyPress, KeyDown}, answer, claimed) =
    read_gesture(view, gesture; claimed)

function _add_find_bar_answer(view::FindBarView, gesture::CollectIntents, answer, claimed)
    answer isa CollectedIntentsOperation || return nothing
    own = read_gesture(view, gesture)
    own isa CollectedIntentsOperation ? merge_collected_intents(answer, own) : nothing
end

_add_find_bar_answer(view::FindBarView, gesture, answer, claimed) = nothing
