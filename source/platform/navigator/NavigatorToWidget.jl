# Fragment of `NavigatorModule` — a navigator as a grid of one column: the bar,
# then the page.
#
#     children[1]                       the bar: Back, Forward, Parent and the items of the address
#     children[2].children[1].<rest>    the page; <rest> is a path in the page
#
# The printer prints no child. The page itself stands in a vertical layout of one
# child, whose list of children is computed from the address. The layout stage
# that follows prints it through the recursion, with the row of its own type, and
# a vertical layout prints its children again when its list changes, where a grid
# prints them once.
# The maps put the address before a path in the page and take it off, as
# `FocusingProjection` does with its part, behind the field `content`.

"""
    NavigatorToWidget(; gap, section_gap)

The projection of a [`Navigator`](@ref): a bar above the page. The bar holds the
Back, Forward and Parent buttons, which show an arrow, and the address as a
breadcrumb: the name of each document from the content to the page. A press on a
name opens that page. `gap` is the space between the parts of the bar, and
`section_gap` the space between the bar and the page.

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

# `actions` holds the action of each button of the bar, and `crumbs` each item of
# the address, so the reader knows the press of which part an
# `InvokeActionOperation` reports. `crumbs` follows the address.
@iomap struct NavigatorToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    actions::Any
    crumbs::Any
end

const _BAR_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _PAGE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2),
                     FieldReferenceStep("children"), RangeReferenceStep(0, 1))

function print_document(p::NavigatorToWidget, recursion, navigator::Navigator, ctx)
    actions = (back = _make_action("Back", :arrow_left, () -> !isempty(navigator.back)),
               forward = _make_action("Forward", :arrow_right, () -> !isempty(navigator.forward)),
               parent = _make_action("Parent", :arrow_up,
                                     () -> find_navigator_parent_address(navigator) !== nothing))
    buttons = Any[WidgetToolbarItem(actions.back; tooltip = "Go back to the page before (Ctrl+[)."),
                  WidgetToolbarItem(actions.forward; tooltip = "Go forward to the next page (Ctrl+])."),
                  WidgetToolbarItem(actions.parent; tooltip = "Go to the page that holds this page (Ctrl+Up).")]
    crumbs = Cell(@computation _make_address_crumbs(navigator))
    switch = _make_view_switch(navigator.address_draft)
    bar = HorizontalLayout(CellVector(Computation(() -> Any[buttons..., switch,
                                                            _make_address_part(navigator, crumbs[])...])),
                           Cell(:center), Cell(p.gap), Cell(Content), Cell(nothing), Cell(nothing))
    page = VerticalLayout(CellVector(@computation Any[get_navigator_page(navigator)]),
                          Cell(:left), Cell(0), Cell(Fill), Cell(Fill), Cell(nothing))
    output = GridLayout(Any[bar, page], 1; vertical_gap = p.section_gap,
                        column_policy = Fill, row_policies = Any[Content, Fill])
    iomap = NavigatorToWidgetIoMap(p, navigator, output, actions, crumbs)
    # The grid passes a key to the part that its selection names, so it maps only a
    # live selection.
    set_output_path_computations!(output, navigator, path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    iomap
end

# A button of the bar, which shows `icon` and says `label`. Its press is the
# operation that the reader makes for it, and `is_enabled` turns it off where that
# operation does nothing. The action has no callback: the press always comes back
# through the reader of this view, and a callback at the editor could not root the
# selection, whose path starts at the navigator.
function _make_action(label::AbstractString, icon::Symbol, is_enabled::Function)
    action = Action(label; icon)
    set_cell_computation!(getfield(action, :enabled), is_enabled)
    action
end

# ── The views of the address ──────────────────────────────────────────────────
#
# The bar shows the address in one of three views, which the address copy names:
# the names of the documents on it, the path, or the path with the type of each
# node. One control steps through them.

const _ADDRESS_VIEWS = [:titles, :path, :types]

# The control that steps through the views: it shows the current one, and a press
# writes the next into the address copy, which the reader marks as view state.
function _make_view_switch(draft::NavigatorAddress)
    switch = WidgetToggleGroup(["Names", "Path", "Types"]; look = :step, values = _ADDRESS_VIEWS,
                               target = draft, field = "view",
                               tooltip = "The address as names, as a path, or as a path with types: " *
                                         "a press shows the next, Shift+press the one before.")
    set_cell_computation!(getfield(switch, :selected),
                          () -> something(findfirst(==(draft.view), _ADDRESS_VIEWS), 1))
    switch
end

# The widgets of the address in the view that the address copy names.
function _make_address_part(navigator::Navigator, crumbs)
    view = navigator.address_draft.view
    view === :path && return Any[WidgetLabel(_get_path_text(navigator))]
    view === :types && return Any[WidgetLabel(_get_types_text(navigator))]
    _get_crumb_widgets(crumbs)
end

# The path of the steps that the bar shows, or a word for the whole content.
function _get_path_text(navigator::Navigator)
    steps = get_navigator_address_steps(navigator)
    isempty(steps) && return "(the whole content)"
    join(_get_step_text(step) for step in steps)
end

_get_step_text(step::FieldReferenceStep) = "." * step.name
_get_step_text(step::RangeReferenceStep) = "[" * string(step.stop) * "]"
_get_step_text(step::ReferenceInsertion) = step.value

# The path of the page with the type of each node, and, when an edit cut the
# address, a mark and the part that no longer reaches a node.
function _get_types_text(navigator::Navigator)
    page = get_navigator_page_address(navigator)
    text = string(annotate_reference_types(navigator.content, page))
    stored = get_reference_steps(navigator.address)
    reached = length(get_reference_steps(page))
    reached < length(stored) || return text
    text * "  ✗ " * join(_get_step_text(step) for step in stored[(reached + 1):end])
end

# ── The address ───────────────────────────────────────────────────────────────
#
# One item for each document from the content to the page at which a navigator
# stops (`is_navigator_stop`), and the page last. An item names its document by its
# title, or by the steps that reach it, or at the root by the name of its type; its
# tooltip is its path from the content. A press on an item opens its page, and the
# page itself is a plain name.

# One item of the address: what it draws, the action of its press, and the
# address that the press opens. The page has no action.
struct _AddressCrumb
    widget::Any
    action::Any
    address::Reference
end

function _make_address_crumbs(navigator::Navigator)
    parts = _get_address_parts(navigator)
    crumbs = _AddressCrumb[]
    for (index, (label, tooltip, address)) in enumerate(parts)
        if index == length(parts)
            push!(crumbs, _AddressCrumb(WidgetLabel(label; tooltip), nothing, address))
        else
            action = Action(label)
            push!(crumbs, _AddressCrumb(WidgetToolbarItem(action; tooltip), action, address))
        end
    end
    crumbs
end

# The name, the tooltip and the address of each document from the content to the
# page, past the collections, and of the page last.
function _get_address_parts(navigator::Navigator)
    content = navigator.content
    steps = get_reference_steps(get_navigator_page_address(navigator))
    prefix(stop) = extend_reference(EmptyReference(), steps[1:stop]...)
    stops = Int[0]
    for stop in eachindex(steps)
        (stop == length(steps) || is_navigator_stop(evaluate_reference(content, prefix(stop)))) &&
            push!(stops, stop)
    end
    parts = Tuple{String,String,Reference}[]
    for (index, stop) in enumerate(stops)
        address = prefix(stop)
        label = _get_address_label(evaluate_reference(content, address),
                                   steps[(index == 1 ? 1 : stops[index - 1] + 1):stop])
        tooltip = stop == 0 ? "The whole content." : print_path_text(address)
        push!(parts, (label, tooltip, address))
    end
    parts
end

# The widgets of the address, with a mark between two items.
function _get_crumb_widgets(crumbs::Vector{_AddressCrumb})
    widgets = Any[]
    for (index, crumb) in enumerate(crumbs)
        index == 1 || push!(widgets, WidgetLabel("›"))
        push!(widgets, crumb.widget)
    end
    widgets
end

# The title of a document on the address; the steps that reach it from the item
# before, when it has no title; the name of its type at the root.
function _get_address_label(node, steps)
    title = get_document_title(node)
    title === nothing || return String(title)
    isempty(steps) && return string(nameof(typeof(node)))
    lstrip(join(sprint(show, step) for step in steps), '.')
end

# ── Reader ────────────────────────────────────────────────────────────────────
#
# The generic bridge reads first: it maps a path of the page back, and it reads
# the `@gestures` table of the navigator for a key that the page does not answer.
# Then the reader takes two kinds of answer for itself:
#
# - a press on a button or on an item of the address answers
#   `InvokeActionOperation`, which travels up as it is, and becomes the operation
#   of the button or the open of the page of the item;
# - an `OpenPageOperation` from the page becomes a visit, or, for a new tab, an
#   open with the content of the navigator as its root, which goes on up.
#
# After an answer of the page that collects, such as the menu of a part, the
# navigator adds the answer of its own table, as a document around a part does;
# the keys of its table join the keys of the page for the gesture help. A key that
# the page answered goes to the table as a claimed key, which an `override` rule
# of the table takes.
function read_intent(p::NavigatorToWidget, recursion, change::Intent, iomap::NavigatorToWidgetIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    operation = answer.operation
    operation === nothing && return answer
    if change.operation !== nothing && change.gesture !== nothing
        operation = _add_own_answer(iomap.input, change.gesture, operation)
    end
    Intent(answer.gesture, _translate_answer(iomap, operation), answer.description, answer.domain)
end

_add_own_answer(navigator::Navigator, gesture, operation) =
    read_gesture_outward(operation, gesture, navigator; steps = ReferenceStep[], with_part = true)

# A key that the page answered reaches the table of the navigator as a claimed
# key, so only an `override` rule takes it over, as the evaluator does.
function _add_own_answer(navigator::Navigator, gesture::Union{KeyPress, KeyDown}, operation)
    own = read_gesture(navigator, gesture; claimed = operation)
    own === nothing ? operation : own
end

function _add_own_answer(navigator::Navigator, gesture::CollectIntents, operation)
    operation isa CollectedIntentsOperation || return operation
    own = read_gesture(navigator, gesture)
    own isa CollectedIntentsOperation ? merge_collected_intents(operation, own) : operation
end

function _translate_answer(iomap::NavigatorToWidgetIoMap, operation::InvokeActionOperation)
    navigator, actions = iomap.input, iomap.actions
    make = operation.action === actions.back ? make_navigator_back_operation :
           operation.action === actions.forward ? make_navigator_forward_operation :
           operation.action === actions.parent ? make_navigator_parent_operation : nothing
    make === nothing || return something(make(navigator), DoNothingOperation())
    # A press on an item of the address opens its page, with the page that the
    # person leaves selected, as Parent does.
    index = findfirst(crumb -> crumb.action === operation.action, iomap.crumbs)
    index === nothing && return operation
    something(make_navigator_open_operation(navigator, iomap.crumbs[index].address;
                                            selection = get_navigator_page_address(navigator)),
              DoNothingOperation())
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

# A write of the address copy, such as the view that the control picks, is view
# state.
function _translate_answer(iomap::NavigatorToWidgetIoMap, operation::ReplaceReferencedValueOperation)
    operation.document === iomap.input.address_draft || return operation
    ReplaceViewStateOperation(operation)
end

_translate_answer(iomap::NavigatorToWidgetIoMap, operation::CompoundOperation) =
    CompoundOperation(Any[_translate_answer(iomap, member) for member in operation.operations])
_translate_answer(iomap::NavigatorToWidgetIoMap, operation::WrappingOperation) =
    rewrap_operation(operation, _translate_answer(iomap, get_wrapped_operation(operation)))
_translate_answer(::NavigatorToWidgetIoMap, operation) = operation

# ── Maps ──────────────────────────────────────────────────────────────────────
#
# `content.<address>.<rest>` ↔ `children[2].children[1].<rest>`. A path in the content that is
# not on the page has no image. A path into the bar names nothing, so a press on a
# button leaves the selection where it is; any other path names the whole
# navigator.

function map_reference_forward(::NavigatorToWidget, iomap::NavigatorToWidgetIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    steps = get_reference_steps(reference)
    steps[1] == _CONTENT_STEP || return nothing
    page = get_reference_steps(get_navigator_page_address(iomap.input))
    _starts_with(steps[2:end], page) || return nothing
    # The rest is a path in the page, which the layout holds itself, so it keeps the
    # checkpoints that it came with; the steps of the grid and the layout take their
    # types. A container that splices the image into its own path needs every one.
    rest = reference
    for _ in 0:length(page)
        rest = get_reference_tail(rest)
    end
    is_fully_typed_reference(rest) ||
        (rest = annotate_reference_types(get_navigator_page(iomap.input), strip_reference_types(rest)))
    _attach_rest(annotate_reference_types(output, extend_reference(EmptyReference(), _PAGE_STEPS...)), rest)
end

# `prefix` with `rest` in place of its terminal.
_attach_rest(prefix::ConcreteReference, rest) =
    ConcreteReference(prefix.type, prefix.head, _attach_rest(prefix.tail, rest))
_attach_rest(::EmptyReference, rest) = rest

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
