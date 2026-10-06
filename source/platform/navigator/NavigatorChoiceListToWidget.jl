# Fragment of `NavigatorModule` — the list of the choices at a step of the address,
# as the context menu window shows it: a line with the typed text, then a menu of
# the choices that the text narrows to. The context menu window gives a key to the
# list first while the list is open, so a person types into the list, and the
# window under it keeps the focus.
#
# A press on a row, or Return, answers the edit of a row of a context menu: the
# choice operation, which the context menu window lifts through the reader of the
# navigator, and the close of the window.

"""
    NavigatorChoiceListToWidget(; gap)

The projection of a [`NavigatorChoiceList`](@ref): the typed text above a menu of
the choices that it narrows to. The row that Return chooses shows a chevron, and
the step of the address a check. Typing narrows the list, Backspace removes the
last character, Up and Down move the row, and Return chooses it. `gap` is the
space between the text and the menu.
"""
@projection UntrackedCell struct NavigatorChoiceListToWidget
    gap::Int = get_widget_style(nothing, :item_gap)
end

"""
    make_navigator_choice_list_projection(; widget_theme = nothing) -> NavigatorChoiceListToWidget

The projection of the list of choices, with the gap of `widget_theme`: a
`WidgetTheme`, scaled or not, or the default value for `nothing`.
"""
make_navigator_choice_list_projection(; widget_theme = nothing) =
    NavigatorChoiceListToWidget(; gap = get_widget_style(widget_theme, :item_gap))

function print_document(p::NavigatorChoiceListToWidget, recursion, list::NavigatorChoiceList, ctx)
    column = VerticalLayout(CellVector(@computation _make_choice_widgets(list)),
                            Cell(:left), Cell(p.gap), Cell(nothing), Cell(nothing), Cell(nothing))
    SimpleIoMap(p, list, GridLayout(Any[column], 1))
end

# The line of the typed text, and the menu of the choices.
function _make_choice_widgets(list::NavigatorChoiceList)
    query = list.query
    line = WidgetLabel(isempty(query) ? "Find: type a name or a number" : "Find: " * query)
    choices = list.find(query)
    items = Any[_make_choice_item(list, index, label, step) for (index, (label, step)) in enumerate(choices)]
    isempty(items) && push!(items, WidgetMenuItem("No part matches"; enabled = false))
    Any[line, WidgetMenu(items)]
end

function _make_choice_item(list::NavigatorChoiceList, index::Integer, label::AbstractString, step)
    icon = index == list.row ? :chevron_right : step == list.current ? :check : nothing
    WidgetMenuItem(label; icon, operation = something(list.choose(step), DoNothingOperation()))
end

# A key is read by the list alone, before any widget of it, and `nothing` leaves
# it to the window under the list. A press on a row comes back from the menu.
function read_intent(p::NavigatorChoiceListToWidget, recursion, change::Intent, iomap)
    gesture = change.gesture
    change.route === nothing && gesture isa Union{KeyDown, KeyPress} &&
        return Intent(gesture, _read_choice_key(iomap.input, gesture))
    invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
end

# Return, Up, Down and Backspace with no modifier but Shift. Any other key with no
# modifier but Shift does nothing, so a letter does not edit the page under the
# list; a key with Ctrl, Alt or Meta goes on.
function _read_choice_key(list::NavigatorChoiceList, key::KeyDown)
    modifiers = key.modifiers
    (modifiers.ctrl || modifiers.alt || modifiers.meta) && return nothing
    key.key === :return && return _choose_choice_row(list)
    key.key === :up && return _write_choice_list(list; row = max(1, list.row - 1))
    key.key === :down &&
        return _write_choice_list(list; row = max(1, min(length(list.find(list.query)), list.row + 1)))
    key.key === :backspace && return _write_choice_list(list; query = String(chop(list.query)), row = 1)
    DoNothingOperation()
end

function _read_choice_key(list::NavigatorChoiceList, key::KeyPress)
    isprint(key.char) || return nothing
    _write_choice_list(list; query = list.query * key.char, row = 1)
end

# The writes of the list, as view state.
function _write_choice_list(list::NavigatorChoiceList; values...)
    ReplaceViewStateOperation(CompoundOperation(Any[ReplaceReferencedValueOperation(list, String(name), value)
                                                    for (name, value) in values]))
end

# The choice of the row of Return, as a press on its menu item answers it.
function _choose_choice_row(list::NavigatorChoiceList)
    choices = list.find(list.query)
    1 <= list.row <= length(choices) || return DoNothingOperation()
    label, step = choices[list.row]
    operation = list.choose(step)
    close = CloseWindowOperation(:widget_popup)
    operation === nothing ? close : CompoundOperation(Any[EditMenuPartOperation(operation, label), close])
end

# The list has no part that a path names.
map_reference_forward(::NavigatorChoiceListToWidget, iomap, reference) = nothing
map_reference_backward(::NavigatorChoiceListToWidget, iomap, reference) = EmptyReference()
