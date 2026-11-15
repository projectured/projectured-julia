# Fragment of `WidgetModule` — a list that a person types into: a line of the typed
# text over the choices that the text narrows to, each a row of an icon, a label
# and a note. A popup shows it, such as the context menu window, which gives a key
# to the list first while the list is open, so a person types into the list and
# the window under it keeps the focus.
#
# A press on a row, or Return, answers the edit of a row of a context menu: the
# operation of the choice, which the context menu window lifts through the readers
# of the part that the list belongs to, and the close of the window.

"""
    WidgetChoice(label; value = label, icon = nothing, note = nothing)

One row of a [`WidgetChoiceList`](@ref): `label` is what the row says, `value` what
the list gives to its `choose` when the row is chosen, `icon` a glyph before the
label or `nothing`, and `note` a quiet text after it, such as what the choice is,
or `nothing`.
"""
struct WidgetChoice
    label::String
    value::Any
    icon::Any
    note::Any
end

WidgetChoice(label::AbstractString; value = label, icon = nothing, note = nothing) =
    WidgetChoice(String(label), value, icon, note)

"""
    WidgetChoiceList(; query = "", row = 1, top = 1, shown_rows = 12, current = nothing,
                     prompt = "Find", placeholder = "type a name", empty = "Nothing matches",
                     footer = nothing, fills_offer = false, find, choose, edit = nothing)

A list that a person types into: a line of the typed text over the choices that
the text narrows to.

- `query` is the typed text, and `row` the row that Return chooses, which the menu
  lights as it lights the item that its keys move to.
- `top` is the first row that the list shows, and `shown_rows` how many rows it
  shows at most. The rows are a lazy list with its head at `top`, so the list
  builds only the rows that it shows, however many choices `find` gives.
- `current` is the value of the choice that holds now, which shows a check.
- `prompt` names what the list finds, before the typed text; `placeholder` stands
  after it while nothing is typed; `empty` is the row of a list with no choice.
- `footer` is a line under the rows, such as that the choices are still read:
  `nothing`, a string, or a function of no arguments that answers either, which
  the view reads as it draws, so the line follows what the function reads.
- `fills_offer` makes the list as wide as the width that its window gives: the
  slot of a window of a fixed size, or the minimum width of a window that fits
  its content, as a placement of a fixed width sets; else the list is as wide as
  its rows.
- `find(query)` gives the choices in their order, an `AbstractVector` of
  [`WidgetChoice`](@ref); a vector that makes each choice when it is read costs
  only the rows that show.
- `choose(value)` gives the operation of a choice, or `nothing` for none.
- `edit(query)` gives the edit of the part that the list belongs to that the
  typed text makes, such as the text of the field that the list opened under, or
  `nothing` for none; `edit` itself is `nothing` for a list that edits no part.

The typed text is a text of the text domain. A list with no `edit` takes the
selection to the end of its typed text when its window opens, so a person types,
removes and moves the caret there as in every text, and the window gives the
selection back when it closes. A list with `edit` leaves the selection in the
part that it belongs to, such as the field under it, and gives a key of the text
on to that part. Typing narrows the list, Up and Down move the row, Page Up and
Page Down move it by the rows that show, and Return chooses it. The rows that
show follow the row, and the wheel scrolls them. It is view state of a popup: an
undo records no change of it, no file keeps it, and a walk of the documents does
not go into it.

See also `make_choice_list_operation`, which opens one in the context menu window.
"""
@document struct WidgetChoiceList
    query::String = ""
    row::Int = 1
    top::Int = 1
    shown_rows::Int = 12
    current::Any = nothing
    prompt::String = "Find"
    placeholder::String = "type a name"
    empty::String = "Nothing matches"
    footer::Any = nothing
    fills_offer::Bool = false
    find::Any = query -> WidgetChoice[]
    choose::Any = value -> nothing
    edit::Any = nothing
end

is_walk_opaque(::WidgetChoiceList) = true

"""
    make_insertion_choice(type) -> WidgetChoice

The row of a kind of document in a list of kinds: its shortest name, an alias
such as "code" when its domain gives one, the icon of the kind
(`get_insertion_icon`), and the first sentence of its docstring as the note. The
value of the row is `type`.
"""
function make_insertion_choice(type::Type)
    names = get_insertion_names(type)
    aliases = get_insertion_aliases(type)
    label = isempty(aliases) ? names[min(2, length(names))] : first(aliases)
    note = _cut_choice_note(compute_docstring_summary(type))
    WidgetChoice(uppercasefirst(label); value = type, icon = get_insertion_icon(type),
                 note = isempty(note) ? nothing : note)
end

# The first sentence of `text`, at most 60 characters.
function _cut_choice_note(text::AbstractString)
    sentence = first(split(text, r"(?<=\.)\s"; limit = 2))
    length(sentence) <= 60 ? String(sentence) : String(first(sentence, 59)) * "…"
end

"""
    make_choice_list_operation(title, list; point = nothing, placement = nothing) -> Operation

The answer that opens `list`, a [`WidgetChoiceList`](@ref), in the context menu
window, at `point` or under the part that answers it, named `title` when F2 shows
more than one menu. `placement` is a function of the reference of that part
which answers the placement of the window, such as `make_shell_top_placement`.
"""
make_choice_list_operation(title::AbstractString, list::WidgetChoiceList; point = nothing,
                           placement = nothing) =
    ReplaceViewStateOperation(OpenContextMenuOperation(Tuple{String,Document,Int}[(String(title), list, 0)],
                                                       EmptyReference(), point, placement))

"""
    WidgetChoiceListToWidget(; gap)

The projection of a [`WidgetChoiceList`](@ref): the typed text above a menu of the
choices that it narrows to. The menu lights the row that Return chooses, and the
current choice shows a check. `gap` is the space between the text and the menu.
"""
@projection UntrackedCell struct WidgetChoiceListToWidget
    gap::Int = get_widget_style(nothing, :line_gap)
end

make_graphics_projection(::Type{WidgetChoiceList}; measure, appearance) =
    ChainingProjection(
        WidgetChoiceListToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :line_gap)),
        GridLayoutToGraphicsCanvas())

function print_document(p::WidgetChoiceListToWidget, recursion, list::WidgetChoiceList, ctx)
    width = list.fills_offer ? _get_choice_list_width(ctx) : nothing
    line = _make_choice_query_line(list)
    column = VerticalLayout(CellVector(@computation _make_choice_widgets(list, line, width)),
                            Cell(:left), Cell(p.gap), Cell(nothing), Cell(nothing), Cell(nothing))
    output = GridLayout(Any[column], 1)
    iomap = SimpleIoMap(p, list, output)
    # A key goes to the field of the typed text by the selection, so the grid and
    # each container down to the field carry the place of the caret.
    set_output_path_computations!(output, list, path -> map_reference_forward(p, iomap, path); dormant = false)
    set_output_tree_path_computations!(output)
    iomap
end

# The line of the typed text: the prompt, and a field that the text domain edits,
# which shows the placeholder while it is empty and its box only while it holds
# the caret. It is made once, so the field keeps its place while the rows change.
function _make_choice_query_line(list::WidgetChoiceList)
    field = WidgetText(""; placeholder = list.placeholder, quiet = true)
    set_cell_computation!(field, () -> list.query)
    HorizontalLayout(Any[WidgetLabel(list.prompt * ": "), field]; vertical_align = :center)
end

# The steps from the grid of the list to the field of its typed text: the column,
# its first child, the line, and its second child, the field.
const _CHOICE_QUERY_FIELD_STEPS = (FieldReferenceStep("children"), ElementReferenceStep(1),
                                   FieldReferenceStep("children"), ElementReferenceStep(1),
                                   FieldReferenceStep("children"), ElementReferenceStep(2))

# The range step of a place `query{s:e}` of the list, or `nothing`.
function _find_choice_query_range(reference)
    reference isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    (length(steps) == 2 && steps[1] == FieldReferenceStep("query") && steps[2] isa RangeReferenceStep) ||
        return nothing
    steps[2]
end

_make_choice_query_reference(range::RangeReferenceStep) =
    Reference(FieldReferenceStep("query"), RangeReferenceStep(range.start, range.stop, range.direction))

# The place in the typed text where a window that opens with `document` puts the
# selection, or `nothing` (`OpenWindowOperation`): the end of the typed text of a
# list with no `edit`.
_find_window_selection(document) = nothing
_find_window_selection(list::WidgetChoiceList) =
    list.edit === nothing ? _make_choice_query_reference(RangeReferenceStep(length(list.query), length(list.query))) :
                            nothing

# The width that a list that fills its offer gives its menu: the slot of a window
# of a fixed size, or the minimum width of a window that fits its content, which a
# placement sets (`layout-rules.md` §1).
function _get_choice_list_width(ctx)
    slot = get_exact_width(ctx)
    slot !== nothing ? slot : ctx.minimum_width
end

# The line of the typed text, and the menu of the rows that show, which lights the
# row that Return chooses while it shows. The rows are a lazy list of the choices
# with its head at the first row that shows, and the menu walks only the rows that
# show.
function _make_choice_widgets(list::WidgetChoiceList, line, width = nothing)
    minimum_width = width === nothing ? nothing : width[]
    query = list.query
    choices = list.find(query)
    count = length(choices)
    footer = list.footer isa Function ? list.footer() : list.footer
    under = footer === nothing ? Any[] : Any[WidgetLabel(String(footer))]
    count == 0 && return Any[line, WidgetMenu(Any[WidgetMenuItem(list.empty; enabled = false)]; minimum_width),
                             under...]
    top = _clamp_choice_top(list, count, list.top)
    rows = make_index_list(count, top, index -> _make_choice_item(list, choices[index]))
    shown = min(list.shown_rows, count - top + 1)
    highlighted = top <= list.row < top + shown ? list.row - top + 1 : 0
    Any[line, WidgetMenu(take_first(rows, shown); highlighted, minimum_width), under...]
end

# The first row that shows, so that the rows that show are in the list.
_clamp_choice_top(list::WidgetChoiceList, count::Integer, top::Integer) =
    clamp(top, 1, max(1, count - list.shown_rows + 1))

# The first row that shows `row`: `top` when it shows it already, else the top
# that brings it to the nearest edge.
_follow_choice_row(list::WidgetChoiceList, count::Integer, row::Integer) =
    _clamp_choice_top(list, count, row < list.top ? row :
                                   row >= list.top + list.shown_rows ? row - list.shown_rows + 1 :
                                   list.top)

# A row of a choice: the check of the current choice or the icon of the choice,
# then the label and the note.
function _make_choice_item(list::WidgetChoiceList, choice::WidgetChoice)
    icon = choice.value == list.current ? :check : choice.icon
    keys = choice.note === nothing ? Any[] : Any[String(choice.note)]
    WidgetMenuItem(choice.label; icon, keys,
                   operation = something(list.choose(choice.value), DoNothingOperation()))
end

# A key is read by the list: its own keys first, then the answer of the field of
# its typed text, which the text domain made. A list with `edit` gives a key of
# the text on to the window under it, where the part that it belongs to reads it.
# Any other key with no modifier but Shift does nothing, so a letter does not edit
# the page under the list; a key with Ctrl, Alt or Meta goes on. A press on a row
# comes back from the menu.
function read_intent(p::WidgetChoiceListToWidget, recursion, change::Intent, iomap)
    gesture = change.gesture
    list = iomap.input
    if change.route === nothing && gesture isa Union{KeyDown, KeyPress}
        own = _read_choice_key(list, gesture)
        own === nothing || return Intent(gesture, own)
        list.edit === nothing || return Intent(gesture, nothing)
        typed = _read_choice_query_answer(p, iomap, change.operation)
        typed === nothing || return Intent(gesture, typed)
        modifiers = gesture.modifiers
        return Intent(gesture, (modifiers.ctrl || modifiers.alt || modifiers.meta) ? nothing : DoNothingOperation())
    end
    change.route === nothing && gesture isa MouseScroll &&
        return Intent(gesture, _scroll_choice_list(list, gesture))
    invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
end

# Up, Down, Page Up and Page Down move the row, and Return, a typed `'\n'`, chooses
# it, each with no modifier but Shift. Any other key is `nothing`.
function _read_choice_key(list::WidgetChoiceList, key::KeyDown)
    modifiers = key.modifiers
    (modifiers.ctrl || modifiers.alt || modifiers.meta) && return nothing
    step = key.key === :up ? -1 : key.key === :down ? 1 :
           key.key === :page_up ? -list.shown_rows : key.key === :page_down ? list.shown_rows : 0
    step == 0 ? nothing : _move_choice_row(list, step)
end

function _read_choice_key(list::WidgetChoiceList, key::KeyPress)
    modifiers = key.modifiers
    (modifiers.ctrl || modifiers.alt || modifiers.meta) && return nothing
    key.char == '\n' ? _choose_choice_row(list) : nothing
end

# The answer of the field of the typed text, as an answer of the list: an edit of
# the typed text narrows the list and puts the caret after the inserted text, and a
# move of the caret or a range is a selection in the typed text. `nothing` for any
# other answer, or for a part of it that has no place in the typed text.
_read_choice_query_answer(p, iomap, operation) = nothing

function _read_choice_query_answer(p, iomap, operation::ReplaceStringRangeOperation)
    range = _find_choice_query_range(map_reference_backward(p, iomap, operation.reference))
    range === nothing && return nothing
    list = iomap.input
    query = _apply_range(list.query, range.start, range.stop, operation.replacement)
    caret = range.start + length(operation.replacement)
    CompoundOperation(Any[_type_choice_list(list, query),
                          ReplaceSelectionOperation(_make_choice_query_reference(RangeReferenceStep(caret, caret)))])
end

function _read_choice_query_answer(p, iomap, operation::ReplaceSelectionOperation)
    range = _find_choice_query_range(map_reference_backward(p, iomap, operation.path))
    range === nothing ? nothing : ReplaceSelectionOperation(_make_choice_query_reference(range))
end

function _read_choice_query_answer(p, iomap, operation::CompoundOperation)
    members = Any[_read_choice_query_answer(p, iomap, member) for member in operation.operations]
    any(isnothing, members) ? nothing : CompoundOperation(members)
end

# The row `step` rows on, in the list, and the rows that show it.
function _move_choice_row(list::WidgetChoiceList, step::Integer)
    count = length(list.find(list.query))
    row = clamp(list.row + step, 1, max(1, count))
    _write_choice_list(list; row, top = _follow_choice_row(list, count, row))
end

# A turn of the wheel scrolls the rows that show by three rows a step; a positive
# turn scrolls up. The row that Return chooses stays.
function _scroll_choice_list(list::WidgetChoiceList, scroll::MouseScroll)
    scroll.dy == 0 && return nothing
    count = length(list.find(list.query))
    top = _clamp_choice_top(list, count, list.top - 3 * scroll.dy)
    top == list.top ? DoNothingOperation() : _write_choice_list(list; top)
end

# The typed text of the list, which narrows it to its first row, and the edit of
# the part that the text makes.
function _type_choice_list(list::WidgetChoiceList, query::String)
    write = _write_choice_list(list; query, row = 1, top = 1)
    edited = list.edit === nothing ? nothing : list.edit(query)
    edited === nothing ? write : CompoundOperation(Any[write, EditMenuPartOperation(edited, "Type")])
end

# The writes of the list, as view state.
_write_choice_list(list::WidgetChoiceList; values...) =
    ReplaceViewStateOperation(CompoundOperation(Any[ReplaceReferencedValueOperation(list, String(name), value)
                                                    for (name, value) in values]))

# The choice of the row of Return, as a press on its menu item answers it.
function _choose_choice_row(list::WidgetChoiceList)
    choices = list.find(list.query)
    1 <= list.row <= length(choices) || return DoNothingOperation()
    choice = choices[list.row]
    operation = list.choose(choice.value)
    close = CloseWindowOperation(:widget_popup)
    operation === nothing ? close : CompoundOperation(Any[EditMenuPartOperation(operation, choice.label), close])
end

# A place `query{s:e}` of a list with no `edit` is the range of the field of its
# typed text, and the whole list is the whole grid. A list with `edit` holds no
# caret, and no other part of the list has a place.
function map_reference_forward(::WidgetChoiceListToWidget, iomap, reference)
    reference isa EmptyReference && return EmptyReference()
    iomap.input.edit === nothing || return nothing
    range = _find_choice_query_range(reference)
    range === nothing && return nothing
    Reference(_CHOICE_QUERY_FIELD_STEPS..., FieldReferenceStep("content"),
              RangeReferenceStep(range.start, range.stop, range.direction))
end

# A range of the field of the typed text is that range of the typed text; any
# other place of the grid is the whole list.
function map_reference_backward(::WidgetChoiceListToWidget, iomap, reference)
    reference isa Reference || return EmptyReference()
    steps = get_reference_steps(strip_reference_types(reference))
    n = length(_CHOICE_QUERY_FIELD_STEPS)
    (length(steps) == n + 2 && all(k -> steps[k] == _CHOICE_QUERY_FIELD_STEPS[k], 1:n) &&
     steps[n + 1] == FieldReferenceStep("content") && steps[end] isa RangeReferenceStep) ||
        return EmptyReference()
    _make_choice_query_reference(steps[end])
end
