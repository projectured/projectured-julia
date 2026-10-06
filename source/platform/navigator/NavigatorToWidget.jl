# Fragment of `NavigatorModule` — a navigator as a grid of one column: the bar,
# then the page.
#
#     children[1]           the bar: Back, Forward, Parent and the address
#     children[2].<rest>    the page; <rest> is a path in the page
#
# The printer prints no child. The grid holds the page itself, so the layout stage
# that follows prints it once, through the recursion, with the row of its own type.
# The maps put the address before a path in the page and take it off, as
# `FocusingProjection` does with its part, behind the field `content`.

"""
    NavigatorToWidget(; gap, section_gap)

The projection of a [`Navigator`](@ref): a bar of the Back, Forward and Parent
buttons and the address, above the page. `gap` is the space between the parts of
the bar, and `section_gap` the space between the bar and the page.

A press on a button answers the operation of the button, a key that the page
does not answer reaches the `@gestures` table of the navigator, and a path in the
page goes back with the field `content` and the address before it.
"""
@projection UntrackedCell struct NavigatorToWidget
    gap::Int = get_widget_style(nothing, :label_gap)
    section_gap::Int = get_widget_style(nothing, :section_gap)
end

"""
    make_navigator_projection(; widget_theme = nothing) -> NavigatorToWidget

The projection of a navigator, with the gaps of `widget_theme`: a `WidgetTheme`,
scaled or not, or the default values for `nothing`.
"""
make_navigator_projection(; widget_theme = nothing) =
    NavigatorToWidget(; gap = get_widget_style(widget_theme, :label_gap),
                      section_gap = get_widget_style(widget_theme, :section_gap))

# `actions` holds the action of each button of the bar, so the reader knows the
# press of which button an `InvokeActionOperation` reports.
@iomap struct NavigatorToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    actions::Any
end

const _BAR_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _PAGE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))

function print_document(p::NavigatorToWidget, recursion, navigator::Navigator, ctx)
    actions = (back = _make_action("Back", () -> !isempty(navigator.back)),
               forward = _make_action("Forward", () -> !isempty(navigator.forward)),
               parent = _make_action("Parent", () -> find_navigator_parent_address(navigator) !== nothing))
    address = WidgetLabel(() -> _make_address_text(navigator))
    bar = HorizontalLayout(Any[WidgetButton(actions.back; tooltip = "Go back to the page before."),
                               WidgetButton(actions.forward; tooltip = "Go forward to the next page."),
                               WidgetButton(actions.parent; tooltip = "Go to the page that holds this page."),
                               address];
                           vertical_align = :center, gap = p.gap)
    page = Cell(@computation get_navigator_page(navigator))
    output = GridLayout(Any[bar, page], 1; vertical_gap = p.section_gap,
                        column_policy = Fill, row_policies = Any[Content, Fill])
    iomap = NavigatorToWidgetIoMap(p, navigator, output, actions)
    # The grid passes a key to the part that its selection names, so it maps only a
    # live selection.
    set_output_path_computations!(output, navigator, path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    iomap
end

# A button of the bar. Its press is the operation that the reader makes for it,
# and `is_enabled` turns it off where that operation does nothing. The action has
# no callback: the press always comes back through the reader of this view, and a
# callback at the editor could not root the selection, whose path starts at the
# navigator.
function _make_action(label::AbstractString, is_enabled::Function)
    action = Action(label)
    set_cell_computation!(getfield(action, :enabled), is_enabled)
    action
end

# The address as a line: the title of each document from the content to the page,
# past the collections, as `get_parent` reads them.
function _make_address_text(navigator::Navigator)
    content = navigator.content
    steps = get_reference_steps(get_navigator_page_address(navigator))
    parts = String[_get_address_part(content, nothing)]
    for last_step in eachindex(steps)
        node = evaluate_reference(content, extend_reference(EmptyReference(), steps[1:last_step]...))
        _is_page_node(node) && push!(parts, _get_address_part(node, steps[last_step]))
    end
    join(parts, " › ")
end

# The title of a document on the address, or the step that reaches it, or the
# name of its type at the root.
function _get_address_part(node, step)
    title = get_document_title(node)
    title === nothing || return String(title)
    step === nothing ? string(nameof(typeof(node))) : sprint(show, step)
end

# ── Reader ────────────────────────────────────────────────────────────────────
#
# The generic bridge reads first: it maps a path of the page back, and it reads
# the `@gestures` table of the navigator for a key that the page does not answer.
# Then the reader takes two kinds of answer for itself:
#
# - a press on a button of the bar answers `InvokeActionOperation`, which travels
#   up as it is, and becomes the operation of the button;
# - an `OpenPageOperation` from the page becomes a visit, or, for a new tab, an
#   open with the content of the navigator as its root, which goes on up.
function read_intent(p::NavigatorToWidget, recursion, change::Intent, iomap::NavigatorToWidgetIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    operation = answer.operation
    operation === nothing && return answer
    Intent(answer.gesture, _translate_answer(iomap, operation), answer.description, answer.domain)
end

function _translate_answer(iomap::NavigatorToWidgetIoMap, operation::InvokeActionOperation)
    navigator, actions = iomap.input, iomap.actions
    make = operation.action === actions.back ? make_navigator_back_operation :
           operation.action === actions.forward ? make_navigator_forward_operation :
           operation.action === actions.parent ? make_navigator_parent_operation : nothing
    make === nothing && return operation
    something(make(navigator), DoNothingOperation())
end

function _translate_answer(iomap::NavigatorToWidgetIoMap, operation::OpenPageOperation)
    navigator = iomap.input
    if operation.document === nothing
        # The path of an open from the page starts at the field `content`; any
        # other path names no part of the content, and the open goes on up.
        reference = operation.reference
        (reference isa ConcreteReference && get_reference_head(reference) == _CONTENT_STEP) ||
            return operation
        address = get_reference_tail(reference)
        operation.place === :here ||
            return OpenPageOperation(navigator.content, address, operation.place)
        return something(make_navigator_open_operation(navigator, address), DoNothingOperation())
    end
    operation.place === :here || return operation
    something(make_navigator_open_operation(navigator, operation.document, operation.reference),
              DoNothingOperation())
end

_translate_answer(iomap::NavigatorToWidgetIoMap, operation::CompoundOperation) =
    CompoundOperation(Any[_translate_answer(iomap, member) for member in operation.operations])
_translate_answer(iomap::NavigatorToWidgetIoMap, operation::WrappingOperation) =
    rewrap_operation(operation, _translate_answer(iomap, get_wrapped_operation(operation)))
_translate_answer(::NavigatorToWidgetIoMap, operation) = operation

# ── Maps ──────────────────────────────────────────────────────────────────────
#
# `content.<address>.<rest>` ↔ `children[2].<rest>`. A path in the content that is
# not on the page has no image. A path into the bar names nothing, so a press on a
# button leaves the selection where it is; any other path names the whole
# navigator.

function map_reference_forward(::NavigatorToWidget, iomap::NavigatorToWidgetIoMap, reference)
    steps = get_reference_steps(strip_reference_types(reference))
    isempty(steps) && return EmptyReference()
    steps[1] == _CONTENT_STEP || return nothing
    page = get_reference_steps(get_navigator_page_address(iomap.input))
    rest = steps[2:end]
    _starts_with(rest, page) || return nothing
    extend_reference(EmptyReference(), _PAGE_STEPS..., rest[(length(page) + 1):end]...)
end

function map_reference_backward(::NavigatorToWidget, iomap::NavigatorToWidgetIoMap, reference)
    steps = get_reference_steps(strip_reference_types(reference))
    _starts_with(steps, _BAR_STEPS) && return nothing
    _starts_with(steps, _PAGE_STEPS) || return EmptyReference()
    # The rest keeps the checkpoints that the page wrote; the steps before it
    # carry none.
    rest = reference
    for _ in _PAGE_STEPS
        rest = get_reference_tail(rest)
    end
    page = get_navigator_page_address(iomap.input)
    concat_references(extend_reference(EmptyReference(), _CONTENT_STEP, get_reference_steps(page)...), rest)
end
