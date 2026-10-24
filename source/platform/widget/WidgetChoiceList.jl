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
    WidgetChoiceList(; query = "", row = 1, current = nothing, prompt = "Find",
                     placeholder = "type a name", empty = "Nothing matches", find, choose,
                     edit = nothing)

A list that a person types into: a line of the typed text over the choices that
the text narrows to.

- `query` is the typed text, and `row` the row that Return chooses.
- `current` is the value of the choice that holds now, which shows a check.
- `prompt` names what the list finds, before the typed text; `placeholder` stands
  after it while nothing is typed; `empty` is the row of a list with no choice.
- `find(query)` gives the choices, a vector of [`WidgetChoice`](@ref).
- `choose(value)` gives the operation of a choice, or `nothing` for none.
- `edit(query)` gives the edit of the part that the list belongs to that the
  typed text makes, such as the text of the field that the list opened under, or
  `nothing` for none; `edit` itself is `nothing` for a list that edits no part.

Typing narrows the list, Backspace removes the last character, Up and Down move
the row, and Return chooses it. It is view state of a popup: an undo records no
change of it, no file keeps it, and a walk of the documents does not go into it.

See also `make_choice_list_operation`, which opens one in the context menu window.
"""
@document struct WidgetChoiceList
    query::String = ""
    row::Int = 1
    current::Any = nothing
    prompt::String = "Find"
    placeholder::String = "type a name"
    empty::String = "Nothing matches"
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
    make_choice_list_operation(title, list; point = nothing) -> Operation

The answer that opens `list`, a [`WidgetChoiceList`](@ref), in the context menu
window, at `point` or under the part that answers it, named `title` when F2 shows
more than one menu.
"""
make_choice_list_operation(title::AbstractString, list::WidgetChoiceList; point = nothing) =
    ReplaceViewStateOperation(OpenContextMenuOperation(Tuple{String,Document,Int}[(String(title), list, 0)],
                                                       EmptyReference(), point))

"""
    WidgetChoiceListToWidget(; gap)

The projection of a [`WidgetChoiceList`](@ref): the typed text above a menu of the
choices that it narrows to. The row that Return chooses shows a chevron, and the
current choice a check. `gap` is the space between the text and the menu.
"""
@projection UntrackedCell struct WidgetChoiceListToWidget
    gap::Int = get_widget_style(nothing, :item_gap)
end

make_graphics_projection(::Type{WidgetChoiceList}; measure, appearance) =
    ChainingProjection(
        WidgetChoiceListToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :item_gap)),
        GridLayoutToGraphicsCanvas())

function print_document(p::WidgetChoiceListToWidget, recursion, list::WidgetChoiceList, ctx)
    column = VerticalLayout(CellVector(@computation _make_choice_widgets(list)),
                            Cell(:left), Cell(p.gap), Cell(nothing), Cell(nothing), Cell(nothing))
    SimpleIoMap(p, list, GridLayout(Any[column], 1))
end

# The line of the typed text, and the menu of the choices.
function _make_choice_widgets(list::WidgetChoiceList)
    query = list.query
    line = WidgetLabel(list.prompt * ": " * (isempty(query) ? list.placeholder : query))
    choices = list.find(query)
    items = Any[_make_choice_item(list, index, choice) for (index, choice) in enumerate(choices)]
    isempty(items) && push!(items, WidgetMenuItem(list.empty; enabled = false))
    Any[line, WidgetMenu(items)]
end

# A row of a choice: the chevron of the row that Return chooses, the check of the
# current choice, or the icon of the choice, then the label and the note.
function _make_choice_item(list::WidgetChoiceList, index::Integer, choice::WidgetChoice)
    icon = index == list.row ? :chevron_right : choice.value == list.current ? :check : choice.icon
    keys = choice.note === nothing ? Any[] : Any[String(choice.note)]
    WidgetMenuItem(choice.label; icon, keys,
                   operation = something(list.choose(choice.value), DoNothingOperation()))
end

# A key is read by the list alone, before any widget of it, and `nothing` leaves
# it to the window under the list. A press on a row comes back from the menu.
function read_intent(p::WidgetChoiceListToWidget, recursion, change::Intent, iomap)
    gesture = change.gesture
    change.route === nothing && gesture isa Union{KeyDown, KeyPress} &&
        return Intent(gesture, _read_choice_key(iomap.input, gesture))
    invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
end

# Up, Down and Backspace with no modifier but Shift, and Return, a typed `'\n'`.
# Any other key with no modifier but Shift does nothing, so a letter does not edit
# the page under the list; a key with Ctrl, Alt or Meta goes on.
function _read_choice_key(list::WidgetChoiceList, key::KeyDown)
    modifiers = key.modifiers
    (modifiers.ctrl || modifiers.alt || modifiers.meta) && return nothing
    key.key === :up && return _write_choice_list(list; row = max(1, list.row - 1))
    key.key === :down &&
        return _write_choice_list(list; row = max(1, min(length(list.find(list.query)), list.row + 1)))
    key.key === :backspace && return _type_choice_list(list, String(chop(list.query)))
    DoNothingOperation()
end

function _read_choice_key(list::WidgetChoiceList, key::KeyPress)
    if !isprint(key.char)
        modifiers = key.modifiers
        (modifiers.ctrl || modifiers.alt || modifiers.meta) && return nothing
        return key.char == '\n' ? _choose_choice_row(list) : DoNothingOperation()
    end
    _type_choice_list(list, list.query * key.char)
end

# The typed text of the list, which narrows it to its first row, and the edit of
# the part that the text makes.
function _type_choice_list(list::WidgetChoiceList, query::String)
    write = _write_choice_list(list; query, row = 1)
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

# The list has no part that a path names.
map_reference_forward(::WidgetChoiceListToWidget, iomap, reference) = nothing
map_reference_backward(::WidgetChoiceListToWidget, iomap, reference) = EmptyReference()
