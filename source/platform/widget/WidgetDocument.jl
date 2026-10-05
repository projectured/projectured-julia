# Fragment of `WidgetModule` — the widget document types: the abstract
# `WidgetDocument`, its insertion placeholder, and every concrete widget the
# slice offers.

abstract type WidgetDocument <: Document end

# A widget is what a person sees and sets, so its duplicate is a copy of it. The
# `Action` a button shows declares no duplicate, so the duplicate shares it, as
# every control that shows one command shares it. A widget that holds a bare
# function, such as a validator, refuses the duplicate.
has_document_duplicate(::WidgetDocument) = true

# ── WidgetInsertion ─────────────────────────────────────────────────────

@document struct WidgetInsertion <: WidgetDocument
    value::Any = nothing
    margin::Any = nothing
    border::Any = nothing
    padding::Any = nothing
    style::Any = nothing
    tooltip::Any = nothing
end

# ── WidgetLabel ────────────────────────────────────────────────────────────

"""
    WidgetLabel(content; position, <base kwargs>)

A line of text a person reads and does not edit.

Use it to put a caption, a heading or a short note beside another widget, in a
card, a row or a column. `content` is a string, a document, a cell that holds
one, or a function of no arguments. A function makes a live label: it shows what
the function answers now, and an answer that is neither a string nor a document
shows as its text.

# Example

    open_pane!(editor, WidgetLabel("The delay of every run"); title = "Note")

See also `WidgetText`, which a person edits, `WidgetBadge` for one status word,
and `WidgetAlert` for a message with a title.
"""
@document struct WidgetLabel <: WidgetDocument
    position::Point2D
    content::Any
    # A per-label override. Four things may go here:
    #
    #   * `nothing` — the theme's label style, which is what most labels want;
    #   * a `StyleText` — font AND colour, for a label that owns both;
    #   * a bare `StyleColor` — **this colour, the theme's font**;
    #   * a bare `StyleFont` — **this font, the theme's colour**, for a label
    #     that writes an icon of the icon font beside text of the theme.
    #
    # The bare colour keeps the font of the theme, so a line coloured by
    # severity still follows the window's theme. It wins over `style`.
    text_style::ImmutableCell{StyleText}
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

# A widget that shows a value takes it as the value, as a cell that holds it, or
# as a function of no arguments. A function becomes a computed cell, so the
# widget follows what the function reads. A value that a person edits, such as
# the content of a `WidgetText` or the value of a `WidgetSlider`, takes no
# function: a computed cell takes no edit.

# What a label shows of an answer: a string or a document as it is, and any other
# value as its text.
_make_shown_content(content::Union{AbstractString, Document}) = content
_make_shown_content(content) = string(content)

_make_shown_cell(content::Cell) = content
_make_shown_cell(content::Function) = Cell(@computation _make_shown_content(content()))
_make_shown_cell(content) = Cell(content)

# A part that holds a value of any kind, such as an icon, a list of badges or a
# tooltip, takes it the same three ways, and the value stays what it is.
_make_value_cell(value::Cell) = value
_make_value_cell(value::Function) = Cell(@computation value())
_make_value_cell(value) = Cell(value)

function WidgetLabel(content; position::Point2D=Point2D(0, 0),
                     text_style=nothing,
                     visible::Bool=true,
                     margin=nothing, border=nothing, padding=nothing,
                     style=nothing, tooltip=nothing)
    WidgetLabel(Cell(position), _make_shown_cell(content), Cell(text_style),
                Cell(visible), Cell(margin), Cell(border), Cell(padding),
                Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetLabel, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)

# ── WidgetText ─────────────────────────────────────────────────────────────

"""
    WidgetText(content; position, width, language, placeholder, <base kwargs>)

One line of text a person edits.

Use it to take a name, a filter expression or a value from a person, in a form
or beside a button that uses it.

# Example

    open_pane!(editor, WidgetText("name =~ *delay*"; width = 240); title = "Filter")

`width` is a floor and not a size: the box is at least that many pixels wide and
grows with what is typed into it. It is `0` by default, which is the box that
fits its content exactly — and which is a box of nothing at all when the content
is empty. A form gives its fields a width so that an empty one can still be
clicked. `WidgetSpinBox` carries the same field for the same reason.

`language` names the language of a field of code, such as `:julia`, or is
`nothing`. The field colors its text by [`compute_code_pieces`](@ref), which
the package of the language extends, and it is plain text while no such
package is loaded. The text, its caret and its edits are the same either way.

`placeholder` is a text that the field shows in a muted color while it is
empty, such as an example of what it takes, or `nothing`. It is no part of the
content: the caret, a key and a save see an empty field.

See also `WidgetTextarea` for several lines, `WidgetLabel` for text that is
only read, and `WidgetSpinBox` for a number.
"""
@document struct WidgetText <: WidgetDocument
    position::Point2D
    content::Any
    width::Int
    validator::Any
    language::Any
    placeholder::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetText(content; position::Point2D=Point2D(0, 0),
                    width::Integer=0,
                    validator=nothing,
                    language::Union{Nothing,Symbol}=nothing,
                    placeholder::Union{Nothing,AbstractString}=nothing,
                    visible::Bool=true,
                    enabled::Bool=true,
                    margin=nothing, border=nothing, padding=nothing,
                    style=nothing, tooltip=nothing)
    # `validator` (optional) is a callable consulted before an edit commits (Stage 6).
    WidgetText(Cell(position), Cell(content), Cell(Int(width)), Cell(validator), Cell(language),
               Cell(placeholder), Cell(visible), Cell(enabled), Cell(margin), Cell(border), Cell(padding),
               Cell(style), Cell(tooltip), Cell(nothing))
end

"""
    compute_code_pieces(language::Val, text::AbstractString, appearance) -> Vector{Tuple{Int,Any}}

The pieces of `text` in a field of code in `language`, such as `Val(:julia)`, in
order: the count of the characters of each piece, and its `StyleColor`, or
`nothing` for the color of the field. The counts add up to the length of the
text. `appearance` is the `Appearance` of the field, whose theme of the language
gives the colors, or `nothing` for the default theme. The default is one piece of
the color of the field; the package of a language adds a method for it.
"""
compute_code_pieces(::Val, text::AbstractString, appearance) = Tuple{Int,Any}[(length(text), nothing)]

set_cell_computation!(w::WidgetText, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)

"""
    make_numeric_validator(; integer=false, allow_negative=true) -> (String) -> Bool

A text-input validator (input mask, Stage 6): accepts an inserted edit string
made only of digits — plus, when allowed, `-` (sign) and `.` (decimal point). An
empty string (a deletion) is always accepted. Used by `WidgetSpinBox`; pass it
to `WidgetText(...; validator=…)` for a numeric field. A validator is any
`(String) -> Bool` acceptor; the editable reader drops an edit it rejects.
"""
function make_numeric_validator(; integer::Bool=false, allow_negative::Bool=true)
    function (s::AbstractString)
        isempty(s) && return true
        for c in s
            (isdigit(c) ||
             (allow_negative && c == '-') ||
             (!integer && c == '.')) || return false
        end
        true
    end
end

# ── WidgetSpinBox ────────────────────────────────────────────────────────────

"""
    WidgetSpinBox(value; position, min=nothing, max=nothing, step=1, width=0,
                  validator=make_numeric_validator(), <enabled/visible>)

A number with a stepper up and a stepper down.

Use it to let a person choose a number by steps: a run count, a seed, a
repetition. A step adds or subtracts `step` and stays inside `[min, max]`; a
bound of `nothing` is no bound. `width` is a floor, as it is on `WidgetText`.

# Example

    open_pane!(editor, WidgetSpinBox(10; min = 1, max = 100, width = 80); title = "Runs")

The `validator` is a hook for typed entry; a step is always numeric.

See also `WidgetSlider` for a share between zero and one, and `WidgetText` for
a value typed as text.
"""
@document struct WidgetSpinBox <: WidgetDocument
    position::Point2D
    value::Any
    min::Any
    max::Any
    step::Any
    width::Int
    validator::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetSpinBox(value; position::Point2D=Point2D(0, 0),
                       min=nothing, max=nothing, step=1, width::Integer=0,
                       validator=make_numeric_validator(),
                       visible::Bool=true, enabled::Bool=true,
                       margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing)
    WidgetSpinBox(Cell(position), Cell(value), Cell(min), Cell(max), Cell(step),
                  Cell(Int(width)), Cell(validator), Cell(visible), Cell(enabled),
                  Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))
end

# ── WidgetList ───────────────────────────────────────────────────────────────

"""
    WidgetList(items; position, selected=0, width=0, <enabled/visible>)

A column of rows where one row is selected.

Use it to show the names of the runs, the configurations or the files, and let
a person pick one. `items` are shown as strings; a click selects the row it
hits, and Up and Down move the selection.

# Example

    open_pane!(editor, WidgetList(["Fifo", "TandemQueue"]; selected = 1, width = 200); title = "Configurations")

The row under the pointer lights. The list reads that row from its mouse target,
`items[i]`, which a move writes; the list holds no state of its own for it.

Selection lives in the standard macro-injected `selection` field, as a reference
`items[i-1:i]` — the same representation [`WidgetTable`](@ref) uses for its rows,
so a reader returns a `ReplaceSelectionOperation` like every other widget and an
enclosing projection can map the reference across domains. The `selected`
keyword is 1-based sugar (`0` = none) that builds that reference; read the
selection back with [`get_widget_list_selected`](@ref).

See also `WidgetTable` for rows with columns, `WidgetSelect` for a list that
opens on a click, and `WidgetRadioGroup` for a few choices that stay visible.
"""
@document struct WidgetList <: WidgetDocument
    position::Point2D
    items::CellVector
    width::Int
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

# `field[i-1:i]` — the canonical "element i of this collection field" selection
# reference, shared by every widget that selects a row of something (a list's
# `items`, a table's `rows`). `nothing` for "no selection".
_widget_element_selection(field::AbstractString, i::Integer) = i <= 0 ? nothing :
    ConcreteReference(FieldReferenceStep(field),
        ConcreteReference(RangeReferenceStep(Int(i) - 1, Int(i)), EmptyReference()))

# The index such a reference points at, or 0 if it is not one (or names a
# different field).
function _widget_element_selected(sel, field::AbstractString)
    sel isa ConcreteReference || return 0
    h = sel.head
    (h isa FieldReferenceStep && h.name == field) || return 0
    t = sel.tail
    t isa ConcreteReference || return 0
    r = t.head
    r isa RangeReferenceStep || return 0
    r.start + 1
end

# The canonical selection reference for row `i` (1-based); `nothing` for none.
make_widget_list_selection(i::Integer) = _widget_element_selection("items", i)

"""
    get_widget_list_selected(list) -> Int

The selected row of a [`WidgetList`](@ref) as a 1-based index, or `0` when
nothing is selected. The inverse of the `selected` construction keyword.
"""
get_widget_list_selected(w::WidgetList) = _widget_element_selected(w.selection, "items")

function WidgetList(items::Vector; position::Point2D=Point2D(0, 0),
                    selected::Integer=0, width::Integer=0,
                    visible::Bool=true, enabled::Bool=true,
                    margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing)
    WidgetList(Cell(position), CellVector(Cell[Cell(x) for x in items]),
               Cell(Int(width)), Cell(visible), Cell(enabled),
               Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip),
               Cell(make_widget_list_selection(selected)))
end

# ── WidgetCheckbox ─────────────────────────────────────────────────────────

"""
    WidgetCheckbox(content; label, position, <base kwargs>)

A box a person ticks on or off.

Use it to let a person turn one option on or off: whether a plot shows a
legend, whether a run keeps its vectors. `content` is `true` or `false`, and a
click flips it. `label`, a string or `nothing`, says what it means: the box
draws it after the mark, at the label gap of the theme, and a click on it flips
the box too. A form that puts its labels in a column of their own gives none.

# Example

    open_pane!(editor, WidgetCheckbox(true; label = "Record vectors"); title = "Option")

`enabled` (default `true`) is a shared interactivity flag alongside `visible`:
when `false` the checkbox renders muted and its reader refuses to emit the toggle
operation.

See also `WidgetSwitch`, which is the same choice drawn as a slide, and
`WidgetToggleGroup` for one choice among several.
"""
@document struct WidgetCheckbox <: WidgetDocument
    position::Point2D
    content::Any
    label::Any                  # what the box means, drawn after it, or nothing
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    gestures::Any               # per-instance gesture bindings (see get_instance_gesture_bindings)
    tooltip::Any
end

function WidgetCheckbox(content; label = nothing, position::Point2D=Point2D(0, 0),
                        gestures=GestureBinding[],
                        visible::Bool=true,
                        enabled::Bool=true,
                        margin=nothing, border=nothing, padding=nothing,
                        style=nothing, tooltip=nothing)
    WidgetCheckbox(Cell(position), Cell(content), Cell(label),
                   Cell(visible), Cell(enabled), Cell(margin), Cell(border), Cell(padding),
                   Cell(style), Cell(gestures), Cell(tooltip))
end

set_cell_computation!(w::WidgetCheckbox, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)
get_instance_gesture_bindings(w::WidgetCheckbox) = w.gestures

# ── WidgetButton ───────────────────────────────────────────────────────────

"""
    WidgetButton(content; position, size=nothing, action, <base kwargs>)

A button a person clicks to run a command.

Use it to put an act a person repeats where they can click it: run the sweep
again, stop the runs, open a table. `content` is the label; `action` is what
the click does, a function that takes the editor, or an [`Action`](@ref) that a
menu item or a shortcut shares. `size` is the button's width and height in
pixels.

# Example

    open_pane!(editor, WidgetButton("Run again";
                                    action = editor -> run_simulations!(select_simulations!(editor; config = "TandemQueue")));
               title = "Runner")

`action` is that command. Pass an `Action` to bind a shared one: the button
shows its `label`/`icon`, follows its `enabled`, and fires its callback (the
positional `content` may only duplicate the bound label — a differing one has
nowhere to live and errors). Pass a bare callable — or nothing, for an inert
button — and the constructor folds `content` and `icon` into a fresh
`Action(content; icon, callback)`, so after construction the action is always
the source of truth and the printers consult nothing else. An `Action` may also
be passed as the positional `content` directly. Clicking emits
`InvokeActionOperation(action)`; the callback is called with the editor when it
accepts one argument, otherwise with none.

`gestures` is an optional per-instance `Vector{GestureBinding}` for behavior
beyond the plain click: the reader consults it *before* the built-in
click/Enter/Space handling, so a binding can add a gesture (e.g. right-click,
shift-click), override a default (same pattern shadows it), or suppress one (map
the pattern to a `DoNothingOperation()`). Each binding maps a `GesturePattern` to an
`(doc, event) -> Operation | Nothing` builder — the same reified vocabulary the
gesture-help window shows.

`enabled` (default `true`) is a shared interactivity flag alongside `visible`:
when `false` the button renders muted, ignores hover/press, and its reader
refuses to invoke the action.

`labels` names every label the button can show, when its label changes — Pause
and Resume, say. The button is as wide as the widest of them and of its current
label, so the row it stands in does not move when the label changes. Empty (the
default) means the current label alone.

`pressed` is **transient UI state**: it is `true` while the left button is held
down on the button. The printer reads it, and the mouse target of the button,
which says whether the pointer is on it, to pick the surface fill, so a change of
either re-renders only this button. The `WidgetButton` reader writes `pressed` (a
`ReplaceReferencedValueOperation` into its cell); it is not part of the
document's content and is not meant to be serialised.

See also `Action`, `WidgetSwitch` for a state that stays, and `WidgetToggleGroup`
for one choice among several.
"""
@document struct WidgetButton <: WidgetDocument
    position::Point2D
    size::Point2D
    action::Any
    gestures::Any
    dialog::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    pressed::Bool
    labels::Any
    tooltip::Any
end

function WidgetButton(content; position::Point2D=Point2D(0, 0), size::Union{Nothing,Point2D}=nothing,
                      action=nothing,
                      gestures=GestureBinding[],
                      icon=nothing,
                      dialog=nothing,
                      visible::Bool=true,
                      enabled::Bool=true,
                      margin=nothing, border=nothing, padding=nothing,
                      style=nothing,
                      labels=String[], tooltip=nothing)
    # `gestures` is a per-instance `Vector{GestureBinding}` (behavior, not content).
    # It is consulted by the reader ahead of the built-in click/key handling, so a
    # binding can add (right-click, shift-click, …), override (same pattern), or
    # suppress (map to `DoNothingOperation()`) a default.
    # `icon` (optional) is an icon name drawn left of the label (Stage 5);
    # `dialog` (optional) is a child `WidgetDialog` opened modally on click.
    # `content` and `icon` are constructor sugar, not fields: they fold into the
    # button's `Action`, which is the single home of what the command is.
    WidgetButton(Cell(position), Cell(something(size, Point2D(0, 0))),
                 Cell(resolve_action(content, icon, action)), Cell(gestures),
                 Cell(dialog),
                 Cell(visible), Cell(enabled), Cell(margin), Cell(border), Cell(padding),
                 Cell(style),
                 Cell(false), Cell(labels), Cell(tooltip))
end

# The reactive-label channel: make this button's label computed. The label lives
# on the button's `Action` — for a sugar-built button that action is fresh, so
# the write is local; on a button bound to a SHARED action this renames the
# command in every view of it, deliberately.
set_cell_computation!(w::WidgetButton, f::Function) = (set_cell_computation!(getfield(w.action, :label), f); w)

# Per-instance gesture bindings (see `get_instance_gesture_bindings` / `read_bound_gesture`).
get_instance_gesture_bindings(w::WidgetButton) = w.gestures

"""
    WidgetToolButton(icon; label="", size=Point2D(0, 0), <WidgetButton kwargs>)

An icon-first button (Qt's `QToolButton`): a `WidgetButton` showing `icon` with an
optional short `label`. A thin convenience over `WidgetButton`, so it accepts the
same keywords (`action`, `enabled`, `border`, …). Stage 5.
"""
WidgetToolButton(icon; label="", size::Point2D=Point2D(0, 0), kwargs...) =
    WidgetButton(label; size = size, icon=icon, kwargs...)

# ── WidgetTooltip ──────────────────────────────────────────────────────────

"""
    WidgetTooltip(content; position, size=nothing, <base kwargs>)

A floating tooltip overlay..
"""
@document struct WidgetTooltip <: WidgetDocument
    position::Point2D
    size::Point2D
    content::Any
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetTooltip(content; position::Point2D=Point2D(0, 0), size::Union{Nothing,Point2D}=nothing,
                       visible::Bool=true,
                       margin=nothing, border=nothing, padding=nothing,
                       style=nothing, tooltip=nothing)
    WidgetTooltip(Cell(position), Cell(something(size, Point2D(0, 0))), Cell(content),
                  Cell(visible), Cell(margin), Cell(border), Cell(padding),
                  Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetTooltip, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)

# ── WidgetContextMenu ──────────────────────────────────────────────────────

"""
    WidgetContextMenu(child, menu; <base kwargs>)

Wraps `child`, and draws it unchanged. A **right** click anywhere over it opens
`menu`, a `WidgetMenu`, in the context menu window at the pointer. Its gesture
table answers the right click (`make_context_menu_binding`) with an
`OpenContextMenuOperation`, after the child at the point had its turn, so a
nearer part adds its own menu first and the parts around add theirs after it.
`ContextMenuWindowProjection` at the screen opens the window. Every event goes
to `child`, the right click too. A disabled wrapper has no menu, and the child
still works.
"""
@document struct WidgetContextMenu <: WidgetDocument
    child::Any
    menu::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetContextMenu(child, menu;
                          visible::Bool=true,
                          enabled::Bool=true,
                          margin=nothing, border=nothing, padding=nothing,
                          style=nothing, tooltip=nothing)
    WidgetContextMenu(Cell(child), Cell(menu),
                      Cell(visible), Cell(enabled), Cell(margin), Cell(border), Cell(padding),
                      Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetContextMenu, f::Function) = (set_cell_computation!(getfield(w, :child), f); w)

# ── WidgetDialog ───────────────────────────────────────────────────────────

"""
    WidgetDialog(title, content, buttons; popup_id=:widget_dialog, <base kwargs>)

A **modal** dialog (Stage 3 Step 5): a centered card holding `title`, `content`
(a child widget or string), and a row of `buttons` (`WidgetButton`s), over a
translucent scrim. Opened as a window with `modal=true`, so `WindowManager` drops
input to every other window until it is dismissed. Dismissed by **Esc**, a
**backdrop click** (on the scrim outside the card), or a **button**: a button
click runs its action *and* closes the window named by `popup_id` in one
`CompoundOperation`. Build one with `WidgetMessageBox` / `WidgetInputDialog`, or
open it from a `WidgetButton`'s `dialog` field.
"""
@document struct WidgetDialog <: WidgetDocument
    title::Any
    content::Any
    buttons::CellVector
    popup_id::Symbol
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetDialog(title, content, buttons::Vector;
                     popup_id::Symbol=:widget_dialog,
                     visible::Bool=true,
                     margin=nothing, border=nothing, padding=nothing,
                     style=nothing, tooltip=nothing)
    WidgetDialog(Cell(title), Cell(content),
                 CellVector(Cell[Cell(b) for b in buttons]),
                 Cell(popup_id),
                 Cell(visible), Cell(margin), Cell(border), Cell(padding),
                 Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetDialog, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)

"""
    WidgetMessageBox(title, message; buttons=["OK"], popup_id=:widget_dialog)

A `WidgetDialog` whose content is a `WidgetLabel(message)` and whose buttons are
plain closing `WidgetButton`s — the `QMessageBox` analogue. Each button is as
large as its label.
"""
function WidgetMessageBox(title, message; buttons=["OK"], popup_id::Symbol=:widget_dialog)
    btns = Any[WidgetButton(b) for b in buttons]
    WidgetDialog(title, WidgetLabel(message), btns; popup_id=popup_id)
end

"""
    WidgetInputDialog(title, prompt; value="", popup_id=:widget_dialog, theme=nothing)

A `WidgetDialog` whose content is a prompt label above a `WidgetText` field, with
Cancel / OK buttons — the `QInputDialog` analogue. (Editing the field needs the
text-widget projection, as for any `WidgetText`.) `theme` is the scaled widget
theme of the place that opens the dialog, or `nothing` for the default theme:
the field stands `item_gap` below the prompt, and each button is as large as
its label.
"""
function WidgetInputDialog(title, prompt; value="", popup_id::Symbol=:widget_dialog,
                           theme = nothing)
    content = VerticalLayout(Any[WidgetLabel(prompt), WidgetText(value)];
                             gap = _get_bar_item_gap(theme))
    WidgetDialog(title, content, Any[WidgetButton("Cancel"), WidgetButton("OK")];
                 popup_id=popup_id)
end

# ── WidgetMenu ─────────────────────────────────────────────────────────────

"""
    WidgetMenu(elements; <base kwargs>)

A menu containing a sequence of `WidgetMenuItem`s..
"""
@document struct WidgetMenu <: WidgetDocument
    elements::CellVector = CellVector()
    orientation::Symbol = :vertical
    visible::Bool = true
    margin::Inset = nothing
    border::Inset = nothing
    padding::Inset = nothing
    style::Any = nothing
    tooltip::Any
end

function WidgetMenu(elements::Vector;
                    orientation::Symbol=:vertical,
                    visible::Bool=true,
                    margin=nothing, border=nothing, padding=nothing,
                    style=nothing, tooltip=nothing)
    WidgetMenu(CellVector(Cell[Cell(x) for x in elements]),
               Cell(orientation),
               Cell(visible), Cell(margin), Cell(border), Cell(padding),
               Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetMenu, f::Function) = (set_cell_computation!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetMenuItem ─────────────────────────────────────────────────────────

"""
    WidgetMenuItem(content; action=nothing, submenu=nothing, <base kwargs>)

A single item inside a `WidgetMenu` — a view of an [`Action`], exactly like
[`WidgetButton`](@ref). `action` is the command: an `Action` to bind a shared
one (the item shows its `label`/`icon`, follows its `enabled`, and a click
emits `InvokeActionOperation(action)` — so a menu item, a toolbar button, and a
keyboard shortcut can share one command), or a bare callable/nothing folded
with `content`/`icon` into a fresh `Action`; an `Action` may also be passed as
the positional `content`.
`submenu` is an optional `WidgetMenu` opened as a popup just below the item on
a left click; an item with a submenu opens it **instead of** running its
action, so the one item type serves a menu-bar entry, a nested submenu, and a
leaf command. A click on an enabled leaf item also closes the enclosing popup
(a no-op when the menu is rendered inline). A disabled item (or one bound to a
disabled command) is inert.
`operation` is the edit that the item makes on the part that a context menu
belongs to, relative to that part, or `nothing`. A click on an item that has one
answers [`EditMenuPartOperation`](@ref) in place of its action, and the context
menu window lifts it from the part through the readers around it, so a history
records it as an edit of the person.
"""
@document struct WidgetMenuItem <: WidgetDocument
    action::Any
    gestures::Any
    submenu::Any
    operation::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetMenuItem(content;
                        action=nothing,
                        gestures=GestureBinding[],
                        icon=nothing,
                        submenu=nothing,
                        operation=nothing,
                        visible::Bool=true,
                        enabled::Bool=true,
                        margin=nothing, border=nothing, padding=nothing,
                        style=nothing, tooltip=nothing)
    # See `WidgetButton`: `content` and `icon` are sugar that folds into the
    # item's `Action`.
    WidgetMenuItem(Cell(resolve_action(content, icon, action)), Cell(gestures), Cell(submenu), Cell(operation),
                   Cell(visible), Cell(enabled), Cell(margin), Cell(border), Cell(padding),
                   Cell(style), Cell(tooltip))
end
get_instance_gesture_bindings(w::WidgetMenuItem) = w.gestures

# See the `WidgetButton` method: the label lives on the item's `Action`.
set_cell_computation!(w::WidgetMenuItem, f::Function) = (set_cell_computation!(getfield(w.action, :label), f); w)

# ── WidgetToolbarItem ──────────────────────────────────────────────────────

"""
    WidgetToolbarItem(content; action=nothing, icon=nothing, <base kwargs>)

One button of a `WidgetToolbar`: a view of an [`Action`], like
[`WidgetMenuItem`](@ref) and [`WidgetButton`](@ref), and made from `content`,
`icon` and `action` the same way. A menu item and a toolbar item bound to one
`Action` are two views of one command.

**It shows the icon of its action alone** when the action has one, and the
label when it has none. The label stays on the action, because it names the
command: an item with no tooltip of its own says the label as its tooltip, so
a button that shows only a picture still says what it does.

It is flat at rest. While the pointer is on it, it draws the surface and the
outline of a button, and while the left button is held down on it, a darker
surface. A left press on an enabled item invokes the action. A disabled item,
or one bound to a disabled action, is inert: it draws no surface and shows no
press.

`pressed` is transient pointer state, as on a [`WidgetButton`](@ref): it is
`true` while the left button is held down on the item, and the reader of the
item writes it.
"""
@document struct WidgetToolbarItem <: WidgetDocument
    action::Any
    gestures::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    pressed::Bool
    tooltip::Any
end

function WidgetToolbarItem(content;
                           action=nothing,
                           gestures=GestureBinding[],
                           icon=nothing,
                           visible::Bool=true,
                           enabled::Bool=true,
                           margin=nothing, border=nothing, padding=nothing,
                           style=nothing, tooltip=nothing)
    WidgetToolbarItem(Cell(resolve_action(content, icon, action)), Cell(gestures),
                      Cell(visible), Cell(enabled), Cell(margin), Cell(border), Cell(padding),
                      Cell(style), Cell(false), Cell(tooltip))
end
get_instance_gesture_bindings(w::WidgetToolbarItem) = w.gestures

# See the `WidgetButton` method: the label lives on the item's `Action`.
set_cell_computation!(w::WidgetToolbarItem, f::Function) = (set_cell_computation!(getfield(w.action, :label), f); w)

# ── WidgetComposite ────────────────────────────────────────────────────────

"""
    WidgetComposite(elements; position, child_width, child_height, <base kwargs>)

A container that holds child widgets in order, each at its own position.

Use it to group a few widgets that are placed by hand, each with a `position`
of its own. When a row, a column or a grid is wanted, a layout places its
children itself: `HorizontalLayout`, `VerticalLayout` or `GridLayout`.

A child fits its content, up to the edge of the composite. `child_width` and
`child_height` give all children another policy, such as `Fill`, which makes a
child reach the edge; a `LayoutConstraint` gives one child its own.

# Example

    open_pane!(editor, WidgetComposite(Any[WidgetLabel("Delay"),
                                                          WidgetLabel("Throughput"; position = Point2D(0, 24))]);
               title = "Placed")

See also `WidgetCard`, which frames one thing with a title, and `VerticalLayout`.
"""
@document struct WidgetComposite <: WidgetDocument
    position::Point2D
    elements::CellVector
    child_width::Any
    child_height::Any
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetComposite(elements::Vector; position::Point2D=Point2D(0, 0),
                         child_width::Union{Nothing,SizePolicy}=nothing,
                         child_height::Union{Nothing,SizePolicy}=nothing,
                         visible::Bool=true,
                         margin=nothing, border=nothing, padding=nothing,
                         style=nothing, tooltip=nothing)
    WidgetComposite(Cell(position), CellVector(Cell[Cell(x) for x in elements]),
                    Cell(child_width), Cell(child_height), Cell(visible), Cell(margin), Cell(border), Cell(padding),
                    Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetComposite, f::Function) = (set_cell_computation!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetToolbar ──────────────────────────────────────────────────────────

"""
    WidgetToolbar(elements; <base kwargs>)

A horizontal strip of tool items (buttons, labels, separators) placed
below the menu bar in a `WidgetShell`.
"""
@document struct WidgetToolbar <: WidgetDocument
    elements::CellVector = CellVector()
    visible::Bool = true
    margin::Inset = nothing
    border::Inset = nothing
    padding::Inset = nothing
    style::Any = nothing
    tooltip::Any
end

function WidgetToolbar(elements::Vector;
                       visible::Bool=true,
                       margin=nothing, border=nothing, padding=nothing,
                       style=nothing, tooltip=nothing)
    WidgetToolbar(CellVector(Cell[Cell(x) for x in elements]),
                  Cell(visible), Cell(margin), Cell(border), Cell(padding),
                  Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetToolbar, f::Function) =
    (set_cell_computation!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

"""
    make_pager_widget(; from, total, page, move, theme = nothing) -> HorizontalLayout

The strip that moves a WINDOW over a longer sequence: first, previous, next,
last, and a line saying where the reader is.

A `HorizontalLayout` and not a `WidgetToolbar`. A toolbar is a shell's BAND: it
allocates nothing on its main axis and is given a line of height by the shell
that holds it, so three of them stacked in a card draw on top of each other. A
layout measures its children, which is what stacking needs.

**It is here, once, because paging is not a property of any one table.** A log,
a packet list, a result set and a search result are all windows over something
longer, and each of them wanting its own four buttons is how four of them end up
behaving differently. This composes what already exists — a toolbar, four
buttons and a label — and adds no new document, no new projection and no new
row in any dispatch table.

It holds no state. The window belongs to whatever is being paged, which already
knows how many rows it has and which it is showing, and this asks:

- `from()` — the row the window starts at, counting from one;
- `total()` — how many rows exist behind it;
- `page` — how many one window holds;
- `move(row)` — what to do when the reader presses. Called with the row the
  window should start at, already clamped, and never called with the row it is
  already showing.

Both `from` and `total` are read as functions rather than taken as numbers, so
the label follows a sequence that grows while the reader watches it.

`theme` is the widget theme of the place that builds the strip, scaled or not,
or `nothing` for the default theme: the items stand `item_gap` apart, and each
button is as large as its label.
"""
function make_pager_widget(; from, total, page::Integer, move, theme = nothing)
    rows_a_page = max(1, Int(page))
    # The first row of the LAST window. A sequence shorter than one window has
    # exactly one, which starts at one.
    last_start() = max(1, total() - rows_a_page + 1)
    go(where) = () -> begin
        wanted = where === :first    ? 1 :
                 where === :previous ? from() - rows_a_page :
                 where === :next     ? from() + rows_a_page : last_start()
        landing = clamp(wanted, 1, last_start())
        landing == from() || move(landing)
        nothing
    end
    button(label, where) = WidgetButton(label; action = go(where))
    where_label = WidgetLabel("")
    set_cell_computation!(getfield(where_label, :content), () -> begin
        count = total()
        count <= 0 && return "empty"
        first_row = clamp(from(), 1, count)
        last_row = min(count, first_row + rows_a_page - 1)
        # A window that holds everything says so rather than counting to itself.
        first_row == 1 && last_row == count ? "$(count) rows" :
            "rows $(first_row)–$(last_row) of $(count)"
    end)
    HorizontalLayout(Any[button("|<", :first), button("<", :previous),
                         button(">", :next), button(">|", :last), where_label];
                     gap = _get_bar_item_gap(theme))
end

"""
    make_filter_bar_widget(; text, place, regex, apply, theme = nothing) -> HorizontalLayout

The strip a reader types a filter into: a text box, a place box, and a switch
that says whether the text is a regular expression.

Beside `make_pager_widget` and for the same reason. Narrowing a long list is not a
property of any one list — a log, a packet table, a module tree and a result set
all want it — and a filter each of them grew separately is a filter that means
something slightly different in each.

It holds no state either. The filter belongs to whatever is being filtered, and
this asks:

- `text()`, `place()`, `regex()` — what the filter says now;
- `apply(; text, place, regex)` — what to do when the reader presses find. It
  is called with all three so that a caller writes one filter rather than
  merging three edits.

What it does NOT do is decide what the terms mean. A place is a place to
whatever holds the records, and a regular expression is compiled by the thing
that runs it, once, rather than here per keystroke.

`theme` is the widget theme of the place that builds the strip, scaled or not,
or `nothing` for the default theme: the items stand `item_gap` apart, and each
button is as large as its label.
"""
function make_filter_bar_widget(; text, place, regex, apply, theme = nothing)
    # The boxes own what is typed into them. They are NOT derived from the
    # filter: a cell with a function behind it recomputes, and a box that
    # recomputed would erase the reader mid-word. So the filter seeds them once
    # and the reader owns them after that.
    text_box = WidgetText(text())
    place_box = WidgetText(place())
    regex_switch = WidgetToggle(".*"; pressed = regex())
    # And the press is what says "now". Applying per keystroke would run a
    # filter over the whole history for every letter of a word — the reader
    # would pay for `pack`, `packe` and `packet` to learn about `packet`.
    press = WidgetButton("find";
                         action = () -> begin
                             apply(; text = string(text_box.content),
                                     place = string(place_box.content),
                                     regex = regex_switch.pressed)
                             nothing
                         end)
    HorizontalLayout(Any[WidgetLabel("find"), text_box,
                         WidgetLabel("in"), place_box,
                         regex_switch, press]; gap = _get_bar_item_gap(theme))
end

"""
    make_column_chooser_widget(; columns, is_shown, choose, theme = nothing) -> HorizontalLayout

Which columns a table shows: one checkbox per column, with the label of the
column, ticked when it is shown.

The third of the strips a long table wants, beside `make_pager_widget` and
`make_filter_bar_widget`, and here for the same reason — a table's columns are its
own, but *choosing* them is not.

- `columns` — what may be shown, as `(name, label)` pairs. The name is what the
  caller stores; the label is what the reader reads;
- `is_shown(name)` — whether it is shown now;
- `choose(name, shown)` — what to do when the reader presses one.

It does not decide what happens when every column is turned off. A table that
should keep one is the table that should say so, because which one is not a
question this can answer.

`theme` is the widget theme of the place that builds the strip, scaled or not,
or `nothing` for the default theme: the items stand `item_gap` apart, and each
button is as large as its label.
"""
function make_column_chooser_widget(; columns, is_shown, choose, theme = nothing)
    # A checkbox for each column, with the label of the column. The truth about
    # which columns are shown stays with whatever owns the columns: a box shows
    # what `is_shown` answers, and a press does not flip the box but asks
    # `choose`, through the gestures of the box. The whole strip is rebuilt when
    # the answer changes, which is what makes a tick follow a press.
    function make_box(name, label)
        ask = (document, event) -> InvokeActionOperation(Action(label;
            callback = () -> (choose(name, !is_shown(name)); nothing)))
        bind(pattern) = GestureBinding(pattern, ask; description = "Show or hide the column",
                                       domain = "widget")
        WidgetCheckbox(is_shown(name); label,
                       gestures = GestureBinding[bind(MouseClickPattern(:left; modifiers = Symbol[])),
                                                 bind(KeyDownPattern(:space; modifiers = Symbol[])),
                                                 bind(KeyDownPattern(:return; modifiers = Symbol[]))])
    end
    bar = HorizontalLayout(Any[]; gap = _get_bar_item_gap(theme))
    set_cell_computation!(getfield(bar, :children), () -> Any[
        WidgetLabel("columns");
        [make_box(name, label) for (name, label) in columns]])
    bar
end


# ── WidgetStatusBar ──────────────────────────────────────────────────────────

"""
    WidgetStatusBar(segments; <base kwargs>)

A thin bottom band of status text `segments` (each stringified) — Qt's
`QStatusBar`. Non-interactive in v1. Place one on a `WidgetShell` via its
`status_bar` field; it is rendered below the content.
"""
@document struct WidgetStatusBar <: WidgetDocument
    elements::CellVector = CellVector()
    visible::Bool = true
    margin::Inset = nothing
    border::Inset = nothing
    padding::Inset = nothing
    style::Any = nothing
    tooltip::Any
end

function WidgetStatusBar(segments::Vector;
                         visible::Bool=true,
                         margin=nothing, border=nothing, padding=nothing,
                         style=nothing, tooltip=nothing)
    # A segment given as a cell is kept as it is, so a band can say something
    # that follows the window: `Cell(@computation …)` re-derives when what it
    # read changes, where `Cell(value)` would freeze what it was given.
    WidgetStatusBar(CellVector(Cell[x isa Cell ? x : Cell(x) for x in segments]),
                    Cell(visible), Cell(margin), Cell(border), Cell(padding),
                    Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetStatusBar, f::Function) =
    (set_cell_computation!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetShell ────────────────────────────────────────────────────────────

"""
    WidgetShell(content; size, overlay, menu_bar,
                context_menu, <base kwargs>)

Top-level window shell..
"""
@document struct WidgetShell <: WidgetDocument
    content::Any
    size::Point2D
    overlay::WidgetTooltip
    menu_bar::WidgetMenu
    toolbar::WidgetToolbar
    context_menu::WidgetMenu
    status_bar::WidgetStatusBar
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetShell(content;
                     size=nothing,
                     overlay=nothing,
                     menu_bar=nothing,
                     toolbar=nothing,
                     context_menu=nothing,
                     status_bar=nothing,
                     visible::Bool=true,
                     margin=nothing, border=nothing, padding=nothing,
                     style=nothing, tooltip=nothing)
    WidgetShell(Cell(content), Cell(size),
                Cell(overlay), Cell(menu_bar), Cell(toolbar), Cell(context_menu),
                Cell(status_bar),
                Cell(visible), Cell(margin), Cell(border), Cell(padding),
                Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetShell, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)

# ── WidgetTitlePane ────────────────────────────────────────────────────────

"""
    WidgetTitlePane(title, content; <base kwargs>)

A pane with a title bar over a content area.

Use it to put a title over one widget or document when the border and the
padding of a card are not wanted. `title` and `content` are strings or
documents.

# Example

    table = make_result_table(get_simulation_scalar_results(get_project_result_directory(editor)))
    open_pane!(editor, WidgetTitlePane("Delay", table); title = "Delay")

See also `WidgetCard`, which adds a description and a footer, and `open_pane!`,
whose `title` names a tab.
"""
@document struct WidgetTitlePane <: WidgetDocument
    title::Any
    content::Any
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetTitlePane(title, content;
                         visible::Bool=true,
                         margin=nothing, border=nothing, padding=nothing,
                         style=nothing, tooltip=nothing)
    WidgetTitlePane(Cell(title), Cell(content),
                    Cell(visible), Cell(margin), Cell(border), Cell(padding),
                    Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetTitlePane, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)

# ── WidgetSplitPane ────────────────────────────────────────────────────────

"""
    WidgetSplitPane(orientation, elements; sizes, <base kwargs>)

A container that divides its area between its children along one axis, with a
splitter a person drags.

Use it to put two or more widgets side by side or one above the other and let
a person change how much each gets. `orientation` is `:horizontal` or
`:vertical`; `sizes` gives each child its first size in pixels. For a fixed
arrangement without a splitter, use `HorizontalLayout` or `VerticalLayout`; for
two documents in tabs of their own, use `show_layout` and the panes.

# Example

    root = get_project_result_directory(editor)
    table = make_result_table(get_simulation_scalar_results(root))
    plot = make_result_plot(get_simulation_vector_results(root))
    open_pane!(editor, WidgetSplitPane(:horizontal, Any[table, plot]; sizes = [400, 400]); title = "Split")

`active_splitter` and `drag_anchor` are **transient UI state** holding an
in-progress splitter drag (see `StartSplitterDragOperation`): `active_splitter`
is `0` when no drag is in progress, or `k` while the splitter after slot `k` is
being dragged; `drag_anchor` is `nothing` or a
`(coord, size_a, size_b)` named tuple recording the grab origin so each motion
resizes relative to it. `pinned` is a per-slot `Bool` vector marking slots whose
size was set by a drag — in the constrained layout regime those slots are laid
out at their `sizes` extent exactly (their layout weight is ignored) so a drag
sticks instead of being undone by weighted redistribution. They are not part of
the document's content and are not meant to be serialised.

See also `HorizontalLayout`, `VerticalLayout` and `WidgetTabbedPane`.
"""
@document struct WidgetSplitPane <: WidgetDocument
    orientation::Symbol
    elements::CellVector
    sizes::CellVector
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    active_splitter::Int
    drag_anchor::Any
    pinned::CellVector
    tooltip::Any
end

function WidgetSplitPane(orientation::Symbol, elements::Vector;
                         sizes=nothing,
                         visible::Bool=true,
                         margin=nothing, border=nothing, padding=nothing,
                         style=nothing, tooltip=nothing)
    sizes_cv = sizes isa Vector ? CellVector(Cell[Cell(s) for s in sizes]) : CellVector()
    WidgetSplitPane(Cell(orientation), CellVector(Cell[Cell(x) for x in elements]), sizes_cv,
                    Cell(visible), Cell(margin), Cell(border), Cell(padding),
                    Cell(style), Cell(0), Cell(nothing), CellVector(), Cell(tooltip))
end

WidgetSplitPane(elements::Vector; kwargs...) =
    WidgetSplitPane(:horizontal, elements; kwargs...)

set_cell_computation!(w::WidgetSplitPane, f::Function) = (set_cell_computation!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetTabbedPane ───────────────────────────────────────────────────────

"""
    WidgetTabLabel(text; icon = nothing, icon_role = nothing, badges = Any[], tooltip = nothing)

The label of a tab that says more than a name: an icon before the text, badges
after it, and what the tab says when the pointer rests on it.

Use it as the `selector` of a [`WidgetTabPage`](@ref) when a tab must show a
state, such as a count of the tasks that finished. `icon` is the name of an
icon (a `Symbol`) or `nothing`; `icon_role` draws the icon in the text color of
a role, as a [`WidgetBadge`](@ref) names one, or in the color of the tab's text
when it is `nothing`; `badges` is a vector of `WidgetBadge`s; `tooltip` is a
string or a document. Each part takes a value, a cell that holds it, or a
function of no arguments that computes it, so a label follows what its function
reads with no write. The text is what a rename of the tab edits: a caret in it
is `selector.text{k}`.

# Example

    label = WidgetTabLabel("Fingerprint tests"; icon = :loader,
                           badges = Any[WidgetBadge("37/40"; role = :accent),
                                        WidgetBadge("2 failed"; role = :error)],
                           tooltip = "37 of 40 finished")
    open_pane!(editor, WidgetTabbedPane(Any[WidgetTabPage(label, WidgetLabel("…"))]);
               title = "Tasks")

A label with a text only draws as a plain string selector draws.
"""
@document struct WidgetTabLabel <: WidgetDocument
    text::Any
    icon::Any
    icon_role::Any
    badges::Any
    tooltip::Any
end
WidgetTabLabel(text; icon = nothing, icon_role = nothing, badges = Any[], tooltip = nothing) =
    WidgetTabLabel(_make_shown_cell(text), _make_value_cell(icon), _make_value_cell(icon_role),
                   _make_value_cell(badges), _make_value_cell(tooltip), Cell(nothing))

# The text of a tab's selector: the text of a label, else the selector as a string.
_get_tab_selector_text(selector::WidgetTabLabel) = string(selector.text)
_get_tab_selector_text(selector) = string(selector)

# A single tab page: the tab `selector`, its content `element`, an optional
# `icon`, and whether the tab offers a duplicate button (`duplicable`, drawn only
# when the pane is `duplicable` too). The selector is a string, or a
# `WidgetTabLabel` whose own icon wins over `icon`. A page is a Document, so the
# selection chain descends Document→Document through a tabbed pane: the in-place
# selection sync (`replace_selection!`) reaches the leaf and leaves the routing
# ancestors untouched, and a caret move inside a tab does not re-point the
# pane's active tab.
@document struct WidgetTabPage <: WidgetDocument
    selector::Any
    element::Any
    icon::Any = nothing
    duplicable::Bool = false
    tooltip::Any = nothing
end

# `WidgetTabPage(selector, element)`, `(selector, element, icon)` and
# `(selector, element, icon, duplicable)` are Rule Y constructors: `icon`,
# `duplicable` and `selection` are the trailing defaulted run.

# Wrap a caller's tab entry — a `(selector, element)`, `(selector, element, icon)`
# or `(selector, element, icon, duplicable)` tuple, or an already-built
# `WidgetTabPage` — into a `WidgetTabPage`.
_as_tab_page(p::WidgetTabPage) = p
_as_tab_page(p::Tuple) = WidgetTabPage(p[1], p[2], length(p) >= 3 ? p[3] : nothing,
                                       length(p) >= 4 ? p[4] : false)

"""
    WidgetTabbedPane(selector_element_pairs; closable, new_tab, <base kwargs>)

A container with a tab strip: one child is shown, and a click on a tab shows
another.

Use it to put several widgets in one place when a person needs one at a time.
`selector_element_pairs` is a `Vector` of `(selector, element)` or
`(selector, element, icon)` tuples, and the selector is the tab's label. The
window already gives each document a tab of its own through `open_pane!`, so
this is for tabs inside a widget.

# Example

    root = get_project_result_directory(editor)
    table = make_result_table(get_simulation_scalar_results(root))
    plot = make_result_plot(get_simulation_vector_results(root))
    open_pane!(editor, WidgetTabbedPane(Any[("Scalars", table), ("Vectors", plot)]); title = "Results")

Each pair is wrapped in a [`WidgetTabPage`](@ref). `closable` draws a close
button on every tab, `new_tab` draws a new-tab button after the last one, and
`draggable` makes a button down on a tab a grab. `duplicable` splits the close
button of each page whose own `duplicable` is set: a `+` above the `x`. All four
are off by default, and none of them decides what the gesture *means*: the strip
answers with [`CloseTabOperation`](@ref) / [`OpenTabOperation`](@ref) /
[`DragTabOperation`](@ref) / [`DuplicateTabOperation`](@ref), and the projection
that owns the tabs decides.

See also `WidgetAccordion` for sections in a column, and `WidgetSplitPane` for
children shown at once.
"""
@document struct WidgetTabbedPane <: WidgetDocument
    selector_element_pairs::CellVector = CellVector()
    visible::Bool = true
    margin::Inset = nothing
    border::Inset = nothing
    padding::Inset = nothing
    style::Any = nothing
    tab_scroll::Int = 0
    closable::Bool = false
    new_tab::Bool = false
    draggable::Bool = false
    duplicable::Bool = false
    tooltip::Any
end

# `tab_scroll` is transient view state (like `WidgetScrollPane.scroll_position`): a
# horizontal pixel offset (≥0) that scrolls the tab strip when it is wider than the
# pane, so overflow tabs stay reachable. 0 ⇒ no scroll.
function WidgetTabbedPane(selector_element_pairs::Vector;
                          visible::Bool=true,
                          margin=nothing, border=nothing, padding=nothing,
                          style=nothing,
                          tab_scroll::Integer=0,
                          closable::Bool=false,
                          new_tab::Bool=false,
                          draggable::Bool=false,
                          duplicable::Bool=false, tooltip=nothing)
    WidgetTabbedPane(CellVector(Cell[Cell(_as_tab_page(p)) for p in selector_element_pairs]),
                     Cell(visible), Cell(margin), Cell(border), Cell(padding),
                     Cell(style),
                     Cell(Int(tab_scroll)),
                     Cell(closable), Cell(new_tab), Cell(draggable), Cell(duplicable),
                     Cell(tooltip), Cell(nothing))
end

# Wire the tabs reactively: `f()` returns the same shape the positional constructor
# takes — `(selector, element)` / `(selector, element, icon)` tuples or `WidgetTabPage`s
# — each wrapped via `_as_tab_page` (so it stays consistent with the eager ctor above,
# which the reader relies on: `selector_element_pairs[i]` is always a `WidgetTabPage`).
set_cell_computation!(w::WidgetTabbedPane, f::Function) = (set_cell_computation!(getfield(w.selector_element_pairs, :elements), () -> Cell[Cell(_as_tab_page(x)) for x in f()]); w)

# ── WidgetScrollPane ───────────────────────────────────────────────────────

"""
    WidgetScrollPane(content; position, size,
                     scroll_position, follow_end, <base kwargs>)

A viewport a person scrolls over content that is taller or wider than its
space.

Use it to show a long table or a long text inside a bounded `size`. With
`follow_end = true` the pane keeps the end of its content in view as content is
added, which is what a log or a transcript wants.

# Example

    table = make_result_table(get_simulation_scalar_results(get_project_result_directory(editor)))
    open_pane!(editor, WidgetScrollPane(table; size = Point2D(600, 300)); title = "Scalars")

With `follow_end=true` the pane sticks to the *bottom* of its content — newly
appended content (e.g. streaming chat turns) stays in view instead of scrolling
below the fold — ignoring `scroll_position` on the vertical axis.

`follow_end` may be a cell instead of a value, and the pane then uses that very
cell. A document that owns whether its view follows its end passes its own
field's cell: a scroll that leaves the end writes it, and the document's owner
writes it back to bring the end into view.

`scroll_position` may be a cell too, and a scroll then writes that cell. A
projection that makes a new pane at each print passes the cell of a field of
its document, so the pane keeps its place across the prints.

See also `WidgetCard`, whose `height` bounds a body that scrolls.
"""
@document struct WidgetScrollPane <: WidgetDocument
    content::Any
    position::Point2D
    size::Point2D
    scroll_position::Point2D
    follow_end::Bool
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetScrollPane(content;
                          position=nothing,
                          size=nothing,
                          scroll_position::Union{Point2D,AbstractCell}=Point2D(0, 0),
                          follow_end::Union{Bool,AbstractCell}=false,
                          visible::Bool=true,
                          margin=nothing, border=nothing, padding=nothing,
                          style=nothing, tooltip=nothing)
    WidgetScrollPane(Cell(content),
                     Cell(position), Cell(size),
                     scroll_position isa AbstractCell ? scroll_position : Cell(scroll_position),
                     follow_end isa AbstractCell ? follow_end : Cell(follow_end),
                     Cell(visible), Cell(margin), Cell(border), Cell(padding),
                     Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetScrollPane, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)

# ── WidgetTransformPane ──────────────────────────────────────────────────────

"""
    WidgetTransformPane(content; transform, position, size,
                        <base kwargs>)

A pane that applies a 2-D affine [`AffineTransform`](@ref) to its `content` —
the unification of scrolling (a pure translation) and zooming (a pure scale).
The pane projects to a clipping `GraphicsViewport` whose `transform` carries the
matrix, so content is magnified/panned inside a fixed on-screen box.

`transform` is **transient view state** (like `WidgetScrollPane.scroll_position`)
— it is not serialised. It defaults to `affine_identity`. Gestures edit it via a
single-field `ReplaceReferencedValueOperation(pane, "transform", M')`: Ctrl+wheel zooms
about the cursor, a plain wheel pans, and Ctrl+0 resets to the identity. Only the
translate+scale subset is rendered today; rotation/shear is future work.
"""
@document struct WidgetTransformPane <: WidgetDocument
    content::Any
    position::Point2D
    size::Point2D
    transform::AffineTransform
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetTransformPane(content;
                            transform::AffineTransform=affine_identity,
                            position=nothing,
                            size=nothing,
                            visible::Bool=true,
                            margin=nothing, border=nothing, padding=nothing,
                            style=nothing, tooltip=nothing)
    WidgetTransformPane(Cell(content),
                        Cell(position), Cell(size), Cell(transform),
                        Cell(visible), Cell(margin), Cell(border), Cell(padding),
                        Cell(style), Cell(tooltip), Cell(nothing))
end

set_cell_computation!(w::WidgetTransformPane, f::Function) = (set_cell_computation!(getfield(w, :content), f); w)

# ── WidgetScrollBar ────────────────────────────────────────────────────────

"""
    WidgetScrollBar(orientation; value, thumb_size, position, size, <base kwargs>)

A scroll bar.  `orientation` is `:horizontal` or `:vertical`.
`value` ∈ [0,1] is the current scroll position; `thumb_size` ∈ [0,1] is
the visible-fraction represented by the thumb.
"""
@document struct WidgetScrollBar <: WidgetDocument
    orientation::Symbol
    value::Float64
    thumb_size::Float64
    position::Point2D
    size::Point2D
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

function WidgetScrollBar(orientation::Symbol;
                         value::Float64=0.0,
                         thumb_size::Float64=0.2,
                         position=nothing,
                         size=nothing,
                         visible::Bool=true,
                         margin=nothing, border=nothing, padding=nothing,
                         style=nothing, tooltip=nothing)
    WidgetScrollBar(Cell(orientation), Cell(value), Cell(thumb_size),
                    Cell(position), Cell(size),
                    Cell(visible), Cell(margin), Cell(border), Cell(padding),
                    Cell(style), Cell(tooltip), Cell(nothing))
end

"""
    compute_scroll_bar_value(top_row, count, visible) -> Float64

The value of a vertical [`WidgetScrollBar`](@ref) beside a list of `count`
rows that shows `visible` of them, with the row `top_row` at the top: the place
of the top row among the rows that do not fit, from 0 at the first row to 1
where the last row shows at the bottom, and 0 when every row fits.

Use it in a projection that owns the anchor of a list table, so the bar shows
where the table is. See also [`compute_scroll_bar_top_row`](@ref).
"""
function compute_scroll_bar_value(top_row::Integer, count::Integer, visible::Integer)
    room = count - visible
    room <= 0 && return 0.0
    clamp((top_row - 1) / room, 0.0, 1.0)
end

"""
    compute_scroll_bar_top_row(value, count, visible) -> Int

The row that the value `value` of a vertical [`WidgetScrollBar`](@ref) puts at
the top of a list of `count` rows that shows `visible` of them: the inverse of
[`compute_scroll_bar_value`](@ref). A projection makes a write of the value a
jump to that row.
"""
compute_scroll_bar_top_row(value::Real, count::Integer, visible::Integer) =
    1 + round(Int, clamp(Float64(value), 0.0, 1.0) * max(0, count - visible))

# ════════════════════════════════════════════════════════════════════════════
# Extension widgets (printer-only for now; readers are no-ops)
#
# These carry only the fields they need plus `visible` and `selection` — colors,
# radius and spacing all come from the WidgetTheme at render time, so they don't
# replicate the box-model fields of the older widgets.
# ════════════════════════════════════════════════════════════════════════════

# ── WidgetBadge ─────────────────────────────────────────────────────────────

"""
    WidgetBadge(content; position, variant=:default, role=nothing, <base kwargs>)

A small pill with one word: a status.

Use it to mark a state beside a title or in a row: "running", "failed",
"done", or a count such as `37/40`. `variant` sets its color, one of
`:default`, `:secondary`, `:destructive` and `:outline`. `role` gives it the
colors of a status instead, one of `:success`, `:warning`, `:error`, `:info`
and `:accent`: the surface of the role behind the text of the role. A role wins
over the colors of the variant. `content` takes a function of no arguments too,
and the badge then follows what the function reads.

# Example

    open_pane!(editor, HorizontalLayout(Any[WidgetLabel("TandemQueue"),
                                            WidgetBadge("running"),
                                            WidgetBadge("2 failed"; role = :error)]; gap = 8);
               title = "Status")

The same badge is drawn by every widget that holds badges, such as the label of
a tab ([`WidgetTabLabel`](@ref)).

See also `WidgetAlert` for a message with a title, and `WidgetLabel`.
"""
@document struct WidgetBadge <: WidgetDocument
    position::Point2D
    content::Any
    variant::Symbol
    role::Any
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetBadge(content; position::Point2D=Point2D(0, 0), variant::Symbol=:default, role=nothing,
            visible::Bool=true, margin=nothing, border=nothing, padding=nothing, style=nothing,
            tooltip=nothing) =
    WidgetBadge(Cell(position), _make_shown_cell(content), Cell(variant), Cell(role), Cell(visible),
               Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetSeparator ─────────────────────────────────────────────────────────

"""
    WidgetSeparator(; position, orientation=:horizontal, length=200, <base kwargs>)

A thin rule that divides two parts.

Use it to put a line between two groups in a column or a row. `orientation` is
`:horizontal` or `:vertical`, and `length` is its extent in pixels.

# Example

    open_pane!(editor, VerticalLayout(Any[WidgetLabel("Runs"),
                                          WidgetSeparator(; length = 300),
                                          WidgetLabel("Results")]; gap = 8);
               title = "Divided")

See also `WidgetCard`, which frames a group instead of dividing two.
"""
@document struct WidgetSeparator <: WidgetDocument
    position::Point2D
    orientation::Symbol
    length::Int
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetSeparator(; position::Point2D=Point2D(0, 0), orientation::Symbol=:horizontal,
                length::Integer=200, visible::Bool=true,
                margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetSeparator(Cell(position), Cell(orientation), Cell(Int(length)), Cell(visible),
                    Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetCard ──────────────────────────────────────────────────────────────

"""
    WidgetCard(; position, title, description, content, footer, width=0, collapsed=false,
               variant=:card, collapsible=false, <base kwargs>)

A surface with a title, a description, a content body and a footer, stacked
from top to bottom; each part is optional.

Use it to frame one thing with a title: a table, a plot, a form, a note. The
`content` is any widget or document, and `width` in pixels bounds it. A card
folds to its title when `collapsible` is `true`, and `variant` says how loud its
surface is.

# Example

    table = make_result_table(get_simulation_scalar_results(get_project_result_directory(editor)))
    open_pane!(editor, WidgetCard(; title = "Delay", content = table, width = 600); title = "Delay")

`collapsed` is transient view state (like `WidgetScrollPane.scroll_position`): a
click on the chevron of a collapsible card emits `ToggleCollapseOperation(card)`,
whose default handler flips this cell. A collapsed card draws its header and
nothing else.

`collapsible` says that the card shows its fold state: the renderer draws a
chevron before the title, pointing down when the card is open and right when it
is collapsed, and the chevron is the fold target. A click on the title is a click
on the title. The chevron takes a column of its own, as tall as the title, and
the title, the body and the footer all start past it, so the body lines up under
the title's word. A card that folds without saying so is a card a person can not
read, so a card that is not collapsible does not fold from a click. It needs a
`Document` title, because the chevron's column is as tall as the title's own
box. A producer whose fold state lives elsewhere — a domain node's flag — makes
`collapsed` a computed cell that reads it.

`padding` is the card's own padding: an `Inset` with a number of pixels per
side. `nothing`, the default, means the theme's. A `:plain` card with
`padding = Inset(0, 0, 0, 0)` draws nothing and occupies nothing beyond its
content, and one with `padding = Inset(0, 0, 12, 0)` is indented by 12 pixels
and nothing else, which is what a section inside another card needs.

`variant` says how loud the surface is. The card keeps its shape, its padding
and its header in every variant — only the panel behind them changes:

| variant | fill | border |
| --- | --- | --- |
| `:card` | the theme's card color | the theme's border |
| `:tinted` | the theme's accent | none |
| `:muted` | the theme's muted color | none |
| `:plain` | none | none |

A quiet variant is for a surface that groups without announcing itself — one
band of a transcript, where a border around every message would be noise. It is
still a card, so it still folds from its chevron, and the collapse reader does
not care which variant drew it.

`:tinted` and `:muted` differ so that one can sit INSIDE the other and still be
seen. A transcript nests them: the band that says who spoke is tinted, and the
panel around a block of code inside that band is muted. Two quiet surfaces that
shared a color would draw one shape.

See also `WidgetTitlePane` for a title bar alone, `WidgetAccordion` for several
folding sections, and `VerticalLayout` to stack cards.
"""
@document struct WidgetCard <: WidgetDocument
    position::Point2D
    title::Any
    description::Any
    content::Any
    footer::Any
    width::Int
    height::Int
    visible::Bool
    collapsed::Bool
    variant::Symbol
    collapsible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end

"""
    WidgetCard(; position, title, description, content, footer, width=0, height=0, ...)

`height = 0` (the default) is **content-tall**: the card wraps whatever its
content measures, and its content is laid out with no height allocation. A
positive `height` makes the card **fixed**: it is exactly that tall regardless of
its content, and the content is given the remaining interior height to fill.

Fixed height is what lets a scrolling body work — a `WidgetScrollPane` (or any
widget that wants an allocation to scroll within) needs a bounded height to
scroll *inside*; in the content-tall mode there is nothing to scroll against, so
tall content simply extends past the card.
"""
WidgetCard(; position::Point2D=Point2D(0, 0), title=nothing, description=nothing, content=nothing,
           footer=nothing, width::Integer=0, height::Integer=0,
           visible::Bool=true, collapsed::Bool=false, variant::Symbol=:card,
           collapsible::Bool=false, margin=nothing, border=nothing, padding=nothing,
           style=nothing, tooltip=nothing) =
    WidgetCard(Cell(position), Cell(title), Cell(description), Cell(content),
               Cell(footer), Cell(Int(width)), Cell(Int(height)),
               Cell(visible), Cell(collapsed), Cell(variant),
               Cell(collapsible), Cell(margin), Cell(border), Cell(padding), Cell(style),
               Cell(tooltip), Cell(nothing))

# ── WidgetSwitch ────────────────────────────────────────────────────────────

"""
    WidgetSwitch(; label, position, checked=false, duration=0)

An on/off switch, drawn as a knob on a track.

Use it to let a person turn a setting on or off where a checkbox would look
small: a live update, a dark theme. `checked` is the state, and a click flips
it. `label`, a string or `nothing`, says what it means: the switch draws it
after the track, at the label gap of the theme, and a click on it flips the
switch too. A form that puts its labels in a column of their own gives none.

# Example

    open_pane!(editor, WidgetSwitch(; checked = true, label = "Live update"); title = "Setting")

The knob snaps to its new position. `duration`, `anim_from` and `anim_t0` hold
the state of a slide of the knob, but `WidgetSwitchToGraphicsCanvas` draws no
slide: a slide needs a start time on the editor's clock, and the reader of the
switch has no context that reaches that clock.

See also `WidgetCheckbox` and `WidgetToggleGroup`.
"""
@document struct WidgetSwitch <: WidgetDocument
    position::Point2D
    checked::Bool
    label::Any           # what the switch means, drawn after it, or nothing
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    duration::Int        # slide length in ms; the projection draws no slide
    anim_from::Float64   # knob fraction [0,1] when a slide began
    anim_t0::Float64     # editor time (s) when a slide began; NaN = idle
    gestures::Any        # per-instance gesture bindings (see get_instance_gesture_bindings)
    tooltip::Any
end
WidgetSwitch(; label = nothing, position::Point2D=Point2D(0, 0), checked::Bool=false,
             visible::Bool=true, enabled::Bool=true,
             margin=nothing, border=nothing, padding=nothing, style=nothing,
             duration::Integer=0, gestures=GestureBinding[], tooltip=nothing) =
    WidgetSwitch(Cell(position), Cell(checked), Cell(label), Cell(visible), Cell(enabled),
                 Cell(margin), Cell(border), Cell(padding), Cell(style),
                 Cell(Int(duration)), Cell(0.0), Cell(NaN), Cell(gestures), Cell(tooltip))
get_instance_gesture_bindings(w::WidgetSwitch) = w.gestures

# ── WidgetProgress ──────────────────────────────────────────────────────────

"""
    WidgetProgress(value; position, width=240)

A bar filled to a share between zero and one.

Use it to show how far a set of runs or a long job is. `value` is a number, a
cell that holds one, or a function of no arguments that the bar follows; a number
is written as the job advances. `width` is the bar's length in pixels.

# Example

    open_pane!(editor, WidgetProgress(0.4; width = 300); title = "Progress")

See also `WidgetSlider`, which a person drags, and `WidgetBadge` for a state
in one word.
"""
@document struct WidgetProgress <: WidgetDocument
    position::Point2D
    value::Float64
    width::Int
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
_make_share_cell(value::Real) = Cell(Float64(value))
_make_share_cell(value::Cell) = value
_make_share_cell(value::Function) = Cell(@computation Float64(value()))

WidgetProgress(value::Union{Real, Cell, Function}; position::Point2D=Point2D(0, 0), width::Integer=240, visible::Bool=true,
               margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetProgress(Cell(position), _make_share_cell(value), Cell(Int(width)), Cell(visible),
                   Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetSlider ────────────────────────────────────────────────────────────

"""
    WidgetSlider(value; position, width=240)

A knob a person drags along a track to choose a share between zero and one.

Use it to let a person choose a share: an opacity, a threshold, a fraction of
the runs. `value` is the share, and `width` is the track's length in pixels.

# Example

    open_pane!(editor, WidgetSlider(0.5; width = 300); title = "Threshold")

See also `WidgetSpinBox` for a number chosen by steps, and `WidgetProgress` for
a share that is only shown.
"""
@document struct WidgetSlider <: WidgetDocument
    position::Point2D
    value::Float64
    width::Int
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    dragging::Bool     # the knob is held: a move keeps writing until release
    press_value::Any   # the value of the knob at the press while it is held, else nothing
    target::Any        # what a drag writes to, or nothing = this slider
    field::String      # which field of the target a drag writes
    # What the knob's position MEANS, as a function of the fraction along the
    # track. `nothing` is the fraction itself, which is what a slider over a
    # fraction wants.
    #
    # It exists because a track is linear and a great many quantities are not.
    # A playback speed runs from a thousandth of real time to a thousand times
    # it, and on a linear track everything a reader actually wants is crushed
    # into the middle two millimetres. A mapping of `f -> 10^((f - 0.5) * 6)`
    # gives that quantity a track a hand can use.
    #
    # It applies only to what is written to a TARGET. A slider with no target
    # writes its own `value`, and that is the knob's position rather than what
    # the position means.
    mapping::Any
    tooltip::Any
end
WidgetSlider(value::Real; position::Point2D=Point2D(0, 0), width::Integer=240, visible::Bool=true,
             enabled::Bool=true, margin=nothing, border=nothing, padding=nothing, style=nothing,
             target=nothing, field::AbstractString="value",
             mapping=nothing, tooltip=nothing) =
    WidgetSlider(Cell(position), Cell(Float64(value)), Cell(Int(width)), Cell(visible),
                 Cell(enabled), Cell(margin), Cell(border), Cell(padding), Cell(style),
                 Cell(false), Cell(nothing), Cell(target), Cell(String(field)),
                 Cell(mapping), Cell(tooltip), Cell(nothing))

"""
    resolve_slider_write(w, value) -> (document, field, value)

What a drag on `w` writes: the slider's `target` and `field` when it names one,
and the slider's own `value` when it does not.

The same shape as [`resolve_toggle_group_write`](@ref), and for the same reason:
a control that is *for* something says so in the operation it answers with, so
nothing above has to work out which control was moved.
"""
function resolve_slider_write(w::WidgetSlider, value::Float64)
    target = w.target
    # Its own knob, unscaled: a slider with no target is a fraction of a track
    # and nothing else, and scaling it would make the knob jump under the hand.
    target === nothing && return (w, "value", value)
    (target, String(w.field), w.mapping === nothing ? value : w.mapping(value))
end

# ── WidgetRadioGroup ────────────────────────────────────────────────────────

"""
    WidgetRadioGroup(options; position, selected=1)

A column of round options where one is selected.

Use it to let a person pick one of a few named choices when every choice must
stay visible: a kind of result, a configuration. `options` is a `Vector` of
labels, and `selected` is the 1-based index of the chosen one, or `0` for none.
A press on an option selects it. While the group has the focus, the arrow keys
select the next or the previous option.

# Example

    open_pane!(editor, WidgetRadioGroup(["Scalars", "Vectors", "Histograms"]; selected = 2); title = "Kind")

See also `WidgetToggleGroup` for the same choice in one row, and `WidgetSelect`
for many choices that open on a click.
"""
@document struct WidgetRadioGroup <: WidgetDocument
    position::Point2D
    options::CellVector
    selected::Int
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetRadioGroup(options::Vector; position::Point2D=Point2D(0, 0), selected::Integer=1, visible::Bool=true, enabled::Bool=true,
                 margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetRadioGroup(Cell(position), CellVector(Cell[Cell(o) for o in options]),
                     Cell(Int(selected)), Cell(visible), Cell(enabled),
                     Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetAvatar ────────────────────────────────────────────────────────────

"""
    WidgetAvatar(initials; position, size=64, <base kwargs>)

A circular avatar showing initials (image-clipping is future work).
"""
@document struct WidgetAvatar <: WidgetDocument
    position::Point2D
    initials::Any
    size::Int
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetAvatar(initials; position::Point2D=Point2D(0, 0), size::Integer=64, visible::Bool=true,
             margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetAvatar(Cell(position), Cell(initials), Cell(Int(size)), Cell(visible),
                Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetAlert ─────────────────────────────────────────────────────────────

"""
    WidgetAlert(title; position, description=nothing, icon=nothing, variant=:default, width=0, <base kwargs>)

A bordered message with a bold title and a muted description.

`icon` names an icon drawn before the title, as tall as the title and in its
color, such as `:warning` for a fault.

Use it to tell a person something that needs attention: a run failed, a file
is missing, a check passed. `variant = :destructive` draws it in the color of a
fault; `:default` is calm.

# Example

    open_pane!(editor, WidgetAlert("Run failed"; description = "TandemQueue run 3 stopped with an error.", variant = :destructive, width = 400);
               title = "Alert")

See also `WidgetBadge` for one word of status, and `WidgetLabel` for a plain
line.
"""
@document struct WidgetAlert <: WidgetDocument
    position::Point2D
    title::Any
    description::Any
    icon::Any
    variant::Symbol
    width::Int
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetAlert(title; position::Point2D=Point2D(0, 0), description=nothing, icon=nothing,
            variant::Symbol=:default, width::Integer=0, visible::Bool=true,
            margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetAlert(Cell(position), Cell(title), Cell(description), Cell(icon), Cell(variant),
                Cell(Int(width)), Cell(visible), Cell(margin), Cell(border), Cell(padding),
                Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetSkeleton ──────────────────────────────────────────────────────────

"""
    WidgetSkeleton(; position, width=240, height=20, <base kwargs>)

A muted rounded placeholder block for loading states.
"""
@document struct WidgetSkeleton <: WidgetDocument
    position::Point2D
    width::Int
    height::Int
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetSkeleton(; position::Point2D=Point2D(0, 0), width::Integer=240, height::Integer=20, visible::Bool=true,
               margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetSkeleton(Cell(position), Cell(Int(width)), Cell(Int(height)), Cell(visible),
                  Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetSwatch ────────────────────────────────────────────────────────────

"""
    WidgetSwatch(color; position, size = nothing, <base kwargs>)

A square that shows `color`, such as the color of a field of a theme beside its
text. `size` is the side of the square in pixels, or `nothing` for the
`swatch_size` of the widget theme. A border of the theme frames the square, so a
color near the background shows too. A swatch takes no input.

# Example

    open_pane!(editor, WidgetSwatch(color_solarized_blue); title = "Color")
"""
@document struct WidgetSwatch <: WidgetDocument
    position::Point2D
    color::StyleColor
    size::Any
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetSwatch(color::StyleColor; position::Point2D=Point2D(0, 0), size=nothing, visible::Bool=true,
             margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetSwatch(Cell(position), Cell(color), Cell(size), Cell(visible),
                 Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetHighlight ─────────────────────────────────────────────────────────

"""
    WidgetHighlight(; position, width, height, visible, style)

A translucent accent rectangle with an accent outline: **an area called out**,
not a control. It draws nothing of its own beyond that, takes no input, and is
sized by its caller rather than by content — so it can be laid over other widgets
to say *this is where the thing goes*. A drag's drop indicator is what it was
added for; a selection band over an arbitrary region is the same shape.

It is a highlight and not a [`WidgetSkeleton`](@ref) because the two say opposite
things: a skeleton is a muted stand-in for content that has not arrived, and
disappears into the surface it sits on, which is exactly what a drop indicator
must not do.
"""
@document struct WidgetHighlight <: WidgetDocument
    position::Point2D
    width::Int
    height::Int
    visible::Bool
    style::Any
    tooltip::Any
end
WidgetHighlight(; position::Point2D=Point2D(0, 0), width::Integer=120, height::Integer=80, visible::Bool=true,
                style=nothing, tooltip=nothing) =
    WidgetHighlight(Cell(position), Cell(Int(width)), Cell(Int(height)), Cell(visible), Cell(style),
                    Cell(tooltip), Cell(nothing))

# ── WidgetToggle ────────────────────────────────────────────────────────────

"""
    WidgetToggle(content; position, pressed=false)

A two-state toggle button (pressed = accent surface). A press flips `pressed`,
and so do Return and Space while the toggle has the focus.
"""
@document struct WidgetToggle <: WidgetDocument
    position::Point2D
    content::Any
    pressed::Bool
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetToggle(content; position::Point2D=Point2D(0, 0), pressed::Bool=false, visible::Bool=true, enabled::Bool=true,
             margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetToggle(Cell(position), Cell(content), Cell(pressed), Cell(visible), Cell(enabled),
                Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetToggleGroup ───────────────────────────────────────────────────────

"""
    WidgetToggleGroup(options; position, selected=1, values=nothing, target=nothing, field="selected")

A row of segments where one is pressed.

Use it to let a person pick one of a few short choices in one row: scalars,
vectors, histograms. `options` is what each segment says, and `selected` is the
1-based index of the pressed one.

# Example

    open_pane!(editor, WidgetToggleGroup(["Scalars", "Vectors", "Histograms"]; selected = 1); title = "Kind")

`values` is what each one **means** — the value written when it is picked — and
with none the value is the segment's index.

`target` is what a pick writes to and `field` is which of its fields. With no
target the group writes its own `selected`, which is a control that remembers its
own state and tells nobody. A target is how a segmented control says what it is
*for*: [`WidgetOption`](@ref) carries its `select` the same way, so a pick names
what it changes instead of leaving an enclosing projection to work out which
control was pressed.

See also `WidgetRadioGroup` for the same choice in a column, and `WidgetSwitch`
for on or off.
"""
@document struct WidgetToggleGroup <: WidgetDocument
    position::Point2D
    options::CellVector
    selected::Int
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    values::Any        # what each option means, or nothing = its index
    target::Any        # what a pick writes to, or nothing = this group
    field::String      # which field of the target a pick writes
    tooltip::Any
end
WidgetToggleGroup(options::Vector; position::Point2D=Point2D(0, 0), selected::Integer=1, visible::Bool=true,
                  enabled::Bool=true, margin=nothing, border=nothing, padding=nothing, style=nothing,
                  values=nothing, target=nothing,
                  field::AbstractString="selected", tooltip=nothing) =
    WidgetToggleGroup(Cell(position), CellVector(Cell[Cell(o) for o in options]),
                      Cell(Int(selected)), Cell(visible), Cell(enabled),
                      Cell(margin), Cell(border), Cell(padding), Cell(style),
                      Cell(values), Cell(target), Cell(String(field)), Cell(tooltip), Cell(nothing))

"""
    resolve_toggle_group_write(w, segment) -> (document, field, value)

What picking segment `segment` of `w` writes: its target and field when it has
one, its own `selected` when it has not, and the value that segment means.
"""
function resolve_toggle_group_write(w::WidgetToggleGroup, segment::Int)
    target = w.target
    target === nothing && return (w, "selected", segment)
    values = w.values
    (target, String(w.field), values === nothing ? segment : collect(values)[segment])
end

# ── WidgetSelect ────────────────────────────────────────────────────────────

"""
    WidgetSelect(value; position, options=[], width=0)

A box that shows a value and opens a list of options to pick from.

Use it to let a person pick one of many values without showing them all: a
configuration name, a module path. `value` is the current pick, and `options`
lists what can be picked.

# Example

    open_pane!(editor, WidgetSelect("TandemQueue"; options = ["Fifo", "TandemQueue"], width = 200); title = "Configuration")

A click on the box opens a dropdown of those options as a floating popup window
(see `WidgetSelectToGraphicsCanvas`'s reader and [`WidgetOption`]). Picking an
option writes it back to `value` and dismisses the popup. With no options the
box is inert (renders the closed state only).

See also `WidgetRadioGroup` and `WidgetToggleGroup` for a few choices that stay
visible, and `WidgetList` for a list that stays open.
"""
@document struct WidgetSelect <: WidgetDocument
    position::Point2D
    value::Any
    options::CellVector
    width::Int
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetSelect(value; position::Point2D=Point2D(0, 0), options::Vector=Any[], width::Integer=0,
             visible::Bool=true, enabled::Bool=true,
             margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetSelect(Cell(position), Cell(value),
                 CellVector(Cell[o isa Cell ? o : Cell(o) for o in options]),
                 Cell(Int(width)), Cell(visible), Cell(enabled),
                 Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetOption ──────────────────────────────────────────────────────────────

"""
    WidgetOption(select, value; position, label=string(value), popup_id=:widget_popup, width=0)

One row of an open `WidgetSelect` dropdown. Holds the target `select` document (an
identity pointer, so its click writes straight back to that object regardless of
where it lives in the tree), the `value` to assign, the `label` to render, and the
`popup_id` of the floating window to dismiss. A left click emits a
`CompoundOperation` that writes `select.value = value` and closes `popup_id` — the
window-route close is unpacked by `WindowManagingProjection`, the value write bubbles
to `evaluate_operation`.
"""
@document struct WidgetOption <: WidgetDocument
    position::Point2D
    select::Any
    value::Any
    label::Any
    popup_id::Symbol
    width::Int
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetOption(select, value; position::Point2D=Point2D(0, 0), label=string(value),
             popup_id::Symbol=:widget_popup, width::Integer=0, visible::Bool=true,
             margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetOption(Cell(position), Cell(select), Cell(value), Cell(label),
                 Cell(popup_id), Cell(Int(width)), Cell(visible),
                 Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetTextarea ──────────────────────────────────────────────────────────

"""
    WidgetTextarea(content; position, width=0, rows=4)

Several lines of text.

Use it to show or take a paragraph: a note, a NED fragment, a finding.
`content` is a string, and its newlines split the rows; `rows` is the height in
lines and `width` a floor in pixels. A string is read only. A text document, such
as a `TextBlock`, is edited as the content of a `WidgetText` is, and Return
types a line break.

# Example

    open_pane!(editor, WidgetTextarea("The delay grows with the load.\\nThe queue is the bottleneck."; width = 400, rows = 4); title = "Note")

See also `WidgetText` for one line, and `WidgetLabel` for text that is only
read.
"""
@document struct WidgetTextarea <: WidgetDocument
    position::Point2D
    content::Any
    width::Int
    rows::Int
    visible::Bool
    enabled::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetTextarea(content; position::Point2D=Point2D(0, 0), width::Integer=0, rows::Integer=4, visible::Bool=true, enabled::Bool=true,
               margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetTextarea(Cell(position), Cell(content), Cell(Int(width)), Cell(Int(rows)),
                   Cell(visible), Cell(enabled),
                   Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetAccordion ─────────────────────────────────────────────────────────

# A single accordion item: a `title` and a `body`. A first-class Document rather
# than a raw `(title, body)` tuple, so the selection chain descends
# Document→Document and an in-place caret move in a title/body leaves the
# accordion's routing untouched (printer-locality dimension A; the WidgetTabPage
# fix applied to the accordion).
@document struct WidgetAccordionItem <: WidgetDocument
    title::Any
    body::Any
    tooltip::Any = nothing
end

_as_accordion_item(it::WidgetAccordionItem) = it
_as_accordion_item(it::Tuple) = WidgetAccordionItem(it[1], it[2])

"""
    WidgetAccordion(items; position, expanded=1, width=0)

A column of titled sections where one is open and the others show their title
only.

Use it to put several sections in one column when a person reads one at a
time: the runs, the results, the findings of a study. `items` is a `Vector` of
`(title, body)` tuples, and `expanded` is the 1-based index of the open one, or
`0` for none. A press on the header of an item opens it, or closes it when it is
the open one.

# Example

    root = get_project_result_directory(editor)
    table = make_result_table(get_simulation_scalar_results(root))
    plot = make_result_plot(get_simulation_vector_results(root))
    open_pane!(editor, WidgetAccordion(Any[("Scalars", table), ("Vectors", plot)]; expanded = 2, width = 600); title = "Results")

Each item is wrapped in a [`WidgetAccordionItem`](@ref).

See also `WidgetTabbedPane` for sections behind tabs, and `WidgetCard` for one
section that folds.
"""
@document struct WidgetAccordion <: WidgetDocument
    position::Point2D
    items::CellVector
    expanded::Int
    width::Int
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    tooltip::Any
end
WidgetAccordion(items::Vector; position::Point2D=Point2D(0, 0), expanded::Integer=1, width::Integer=0, visible::Bool=true,
                margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing) =
    WidgetAccordion(Cell(position), CellVector(Cell[Cell(_as_accordion_item(it)) for it in items]),
                    Cell(Int(expanded)), Cell(Int(width)), Cell(visible),
                    Cell(margin), Cell(border), Cell(padding), Cell(style), Cell(tooltip), Cell(nothing))

# ── WidgetTable ─────────────────────────────────────────────────────────────

"""
    WidgetTableColumns()

The value of the field `columns` of a [`WidgetTable`](@ref): what the path
`columns[c]` of a whole column steps through. It holds nothing, and `[c]` gives
the column `c`.
"""
struct WidgetTableColumns end

Base.getindex(::WidgetTableColumns, c::Integer) = WidgetTableColumn(c)

"""
    WidgetTableColumn(index)

A whole column of a table, what the path `columns[c]` names, apart from its
header `column_headers[c]`. It holds its number.
"""
struct WidgetTableColumn
    index::Int
end

"""
    WidgetTable(; position, column_headers, rows, column_count, row_headers, ...)
    WidgetTable(headers::Vector, rows::Vector; position)

A grid of cells with optional column headers and row headers.

Use it to show rows of values by hand, when no verb gives a frame for them:
`headers` is a `Vector` of column names and `rows` a `Vector` of rows. A value in
a row can be of any type: a document is shown as itself, and any other value, such
as a `String` or a number, becomes a `WidgetLabel` of the text `string(value)`
gives. For the bare text of a JSON leaf, pass its `.value`. The result verbs make
their own tables: `make_result_table` answers a frame the window draws as this
widget.

# Example

    open_pane!(editor, WidgetTable(["name", "age"], [["Ada", 36], ["Bob", 41]]); title = "People")

The single table abstraction. A grid of **document cells** (each cell is a
`Document`, recursed through the shared recursion — so a cell can be a
`JsonString`, an `XmlElement`, text, even a nested `WidgetTable`) decorated with
borders / hairline rules, optional header strips, and selection bands. Its
renderer ([`WidgetTableToGraphicsCanvas`](@ref)) delegates *all positioning* to
the `GridLayout`s of its parts — the header row, the header column and the
cells, each in a pane of its own — and draws its decorations at the places
that the grids report ("layout is just layout").

# Fields

- `position::Point2D` — top-left origin.
- `column_headers::CellVector` — optional top strip; each entry a `Document` (or
  `nothing`). Empty vector ⇒ no column-header strip.
- `row_headers::CellVector` — optional left strip; each entry a `Document` (or
  `nothing`). Empty vector ⇒ no row-header strip. When `rows` is a list, a
  `ListNode` of headers that moves in step with it: its head is the header of
  the head row.
- `corner` — `nothing`, or the `Document` drawn where the header row and the
  header column meet. A corner makes the table a table of a list, whose rows
  are a list or, at first, an empty vector. The header column is at least as
  wide as the corner, and the header row at least as tall.
- `rows` — the body: a `CellVector` of rows, or a `ListNode` whose values are
  rows; a row is a `CellVector` of `Document` cells either way. A list is drawn
  one row at a time as a viewport reaches it, and `rows[i]` counts from the
  list's head — the head is row 1, and a row reached through `prev` has an
  index of zero or less.
- `columns` — a [`WidgetTableColumns`](@ref), which holds nothing: what the path
  `columns[c]` of a whole column steps through.

The paths of a table are its field names: `rows[r]` is a row, `columns[c]` a
column, `rows[r][c]` a cell, `column_headers[c]` the header of a column and
`row_headers[r]` the header of a row, each a part of its own. A press on a
column header selects its column and a press on a row header its row; a press
in the content of a header goes to the header.
- `column_count::Int` — number of columns.
- `border_width::Int` — the width of the outer frame and the grid lines. The
  padding inside a cell is the projection's `cell_padding`, from the theme.
- `cell_policy::Symbol` — what a cell does with text wider than its column,
  when the column was given a width: `:clip` draws one line and cuts it at the
  column's edge, `:wrap` breaks the lines there and the row grows. A column
  that is its content has no edge to cut at, and the policy does nothing there.
- `column_cell_policies` — `Vector{Symbol}`, the body columns whose cell policy
  differs from the table's; a column past its end takes the table's.
- `column_align` — `Vector{Symbol}`, where a cell sits in its body column:
  `:left`, `:center` or `:right`; a column past its end is `:left`. A header
  cell sits as the cells of its column do.
- `visible::Bool` — standard Document field; `selection` is macro-injected.
- `margin`, `border`, `padding` — the box around the frame and the grid, each
  `nothing` or an `Inset`; `nothing` takes the projection's default (transparent,
  zero width). Distinct from `border_width` and the cell padding above.
- `style` — `nothing`, a `WidgetStyle`, or a `WidgetTableStyle`; overrides one
  color of the projection.
- `scroll_position`, `top_row` — view state: the one offset of the scrolled
  parts, and the row at the top of a list of rows, counted from its head. The
  row or the column under the pointer lights from the table's mouse target.
- `column_drag` — view state: the drag of the right edge of a header that is
  on, as `(column, x, width)`, the column and the point and the width at the
  press, or `nothing`. A left press within 3 pixels of that edge starts it, and
  each move gives the column a width ([`SetTableColumnWidthOperation`](@ref)).
- `open_cells` — the cells that the owner of the table holds open, a person's
  edit there that is not committed yet, as `(row = k, column = c, reason)` in the
  numbers of the paths of the table; `reason` is why the last commit of the cell
  failed, or `nothing`. `nothing` in place of the list says that no owner opens
  the cells of the table, so it gives every key to its cells and to the parts
  around it. In an open cell Enter and Tab are the commit of the cell
  ([`CommitTableCellOperation`](@ref)) and Escape is its drop
  ([`DropTableCellOperation`](@ref)), which the owner converts; a cell with a
  reason draws a mark, and a rest of the pointer on it shows the reason. On a
  whole cell that is not open, F2 and a typed character that the cell takes no
  key for open the cell ([`EditTableCellOperation`](@ref)), which the owner
  converts too.

The string convenience constructor wraps each string in a `WidgetLabel` so
existing call sites (`WidgetTable(pos, headers, rows)`) keep working unchanged.

See also `make_result_table` and `WidgetList` for one column.
"""
@document struct WidgetTable <: WidgetDocument
    position::Point2D
    column_headers::CellVector   # of Document (or nothing) — optional top strip
    row_headers::CellVector      # of Document (or nothing) — optional left strip; a ListNode beside a list of rows
    corner::Any                  # Document or nothing — where the header row and the header column meet
    rows::Any                    # CellVector of rows, or a ListNode of them; a row is a CellVector of Document cells
    columns::Any                 # WidgetTableColumns: what the path `columns[c]` of a whole column steps through
    column_count::Int
    border_width::Int
    column_policy::Any           # SizePolicy — what every body column is
    row_policy::Any              # SizePolicy — what every body row is
    column_policies::Any         # Vector{SizePolicy} — the body columns that differ
    row_policies::Any            # Vector{SizePolicy} — the body rows that differ
    cell_policy::Symbol          # :clip | :wrap — what every body column's cells do
    column_cell_policies::Any    # Vector{Symbol} — the body columns that differ
    column_align::Any            # Vector{Symbol} — :left, :center or :right for each body column
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    scroll_position::Point2D     # view state: the one offset of the parts of a table that scrolls itself
    top_row::Int                 # view state: the row at the top of a list of rows, counted from its head
    column_drag::Any             # view state: the drag of the edge of a column that is on, or nothing
    open_cells::Any              # the cells that an owner holds open, as `(row, column, reason)`, or `nothing`
    tooltip::Any
end

"""
    make_widget_table_row_selection(i) -> Reference
    get_widget_table_selected_row(table) -> Int

The canonical whole-row selection for a [`WidgetTable`](@ref) (`rows[i-1:i]`,
1-based; `0`/`nothing` = none) and its inverse — the pair a row-selecting reader
emits and an enclosing projection maps across domains. Row selection is what the
table's reader produces for a click on the ROW-HEADER strip, so a table that
wants it must be built with `row_headers`.
"""
make_widget_table_row_selection(i::Integer) = _widget_element_selection("rows", i)
get_widget_table_selected_row(w::WidgetTable) = _widget_element_selected(w.selection, "rows")

# Wrap a raw cell value in a renderable widget document; pass Documents through.
_table_cell_doc(v::Document) = v
_table_cell_doc(::Nothing)   = nothing
_table_cell_doc(v::Function) = WidgetLabel(v)
_table_cell_doc(v)           = WidgetLabel(string(v))

# Wrap one body row (a Vector of values or Documents) into a CellVector of cells.
_table_row(r) = CellVector(Cell[Cell(_table_cell_doc(c)) for c in r])

# The body of a table: a vector of rows becomes a collection of rows, and a list
# of rows stays the list, which the table draws one row at a time.
_table_rows(rows::Vector) = CellVector(Cell[Cell(_table_row(r)) for r in rows])
_table_rows(rows::ListNode) = Cell(rows)

"""
    WidgetTable(; position, column_headers, rows, column_count, row_headers=Any[],
                corner=nothing, border_width=1, visible=true,
                column_policy=Content, row_policy=Content,
                column_policies=Any[], row_policies=Any[],
                cell_policy=:clip, column_cell_policies=Symbol[], column_align=Symbol[],
                scroll_position=Point2D(0, 0))

Document-cell constructor. `column_headers` and `row_headers` are `Vector`s of
`Document`/`nothing`, and a table has no row headers unless it is given some.
`rows` is a `Vector` of rows, each a `Vector` of `Document`/value cells, or a
`ListNode` of rows.

**A table whose rows are a list** is drawn one row at a time as a viewport
reaches it, with no count and no end it has to have. Each node's value is a row,
which [`make_widget_table_row`](@ref) builds from a vector of values or
documents. Every column must be given a width — `Fixed`, or a weight — and the
rows are `Fixed` or `Content`. Its `row_headers` are a `ListNode` too, which
moves in step with `rows`, and then every row is `Fixed`: the header column is
as wide as `corner` and as the header of the head row. When
`column_headers` is a `ListNode` too, the columns are a list as well: the
cells of every row are a `ListNode` anchored at the same column, and so is
`column_align` when it names each column; every column is `column_policy`,
which must be `Fixed`, and at least as wide as its header, and every row is
`Fixed`. Such a table fills
the height that it is offered and scrolls its own parts there: the header row
holds still above the rows, and `scroll_position` is the offset of both.
`top_row` is the row at the top of the cells, counted from the head of the
list, which the table writes as it scrolls. When that row is far from the head,
the table moves the head of `rows` to it, so the rows that it builds stay near
the head.

**A body column and a body row take a `SizePolicy`**, the way a `GridLayout`'s
do: `column_policy` / `row_policy` say what every one is and the two vectors name
the ones that differ. A table whose columns are a list takes `column_policies`
as a list beside its headers, as it takes `column_align`: a value that is a
`Fixed` gives that column its width, and `nothing` leaves the column at
`column_policy` and at least as wide as its header. Both default to `Content`, which is what a table has always
been. A header strip is always `Content` — it is as wide, or as tall, as the
labels in it — so the policies below are the BODY's and the table shifts them
over the strip itself.

**A cell of a column that was given a width clips or wraps**, by `cell_policy`
for every column and `column_cell_policies` for the ones that differ. A table
is a data table until someone says otherwise, so the default is `:clip`: one
line, cut at the column's edge.

**A cell sits at the left of its column** unless `column_align` names `:center`
or `:right` for that column, as a `GridLayout`'s `column_align` does.
"""
function WidgetTable(; position::Point2D=Point2D(0, 0), column_headers::Union{Vector,ListNode},
                     rows::Union{Vector,ListNode}, column_count::Integer,
                     row_headers::Union{Vector,ListNode}=Any[], corner=nothing,
                     border_width::Integer=1, visible::Bool=true,
                     column_policy::SizePolicy=Content, row_policy::SizePolicy=Content,
                     column_policies=Any[], row_policies=Any[],
                     cell_policy::Symbol=:clip, column_cell_policies=Symbol[],
                     column_align=Symbol[], scroll_position::Point2D=Point2D(0, 0),
                     open_cells=nothing,
                     margin=nothing, border=nothing, padding=nothing, style=nothing, tooltip=nothing)
    cell_policy in (:clip, :wrap) ||
        error("WidgetTable: cell_policy is :clip or :wrap, not ", repr(cell_policy))
    if !(column_align isa ListNode)
        for align in column_align
            align in (:left, :center, :right) ||
                error("WidgetTable: a column aligns :left, :center or :right, not ", repr(align))
        end
    end
    rows isa ListNode && row_headers isa Vector && !isempty(row_headers) &&
        error("WidgetTable: a table whose rows are a list takes its row headers as a list")
    rows isa Vector && row_headers isa ListNode &&
        error("WidgetTable: a table whose rows are a vector takes its row headers as a vector")
    rows isa Vector && !isempty(rows) && corner !== nothing &&
        error("WidgetTable: a table with a corner draws its rows as a list, and takes a list ",
              "of rows or an empty vector")
    WidgetTable(Cell(position),
                column_headers isa ListNode ? Cell(column_headers) :
                    CellVector(Cell[Cell(_table_cell_doc(h)) for h in column_headers]),
                row_headers isa ListNode ? Cell(row_headers) :
                    CellVector(Cell[Cell(_table_cell_doc(h)) for h in row_headers]),
                Cell(_table_cell_doc(corner)),
                _table_rows(rows), Cell(WidgetTableColumns()),
                Cell(Int(column_count)), Cell(Int(border_width)),
                Cell(column_policy), Cell(row_policy),
                Cell(column_policies isa ListNode ? column_policies : collect(Any, column_policies)),
                Cell(collect(Any, row_policies)),
                Cell(cell_policy), Cell(collect(Symbol, column_cell_policies)),
                Cell(column_align isa ListNode ? column_align : collect(Symbol, column_align)),
                Cell(visible), Cell(margin), Cell(border), Cell(padding), Cell(style),
                Cell(scroll_position), Cell(1), Cell(nothing), Cell(open_cells === nothing ? nothing : collect(Any, open_cells)), Cell(tooltip))
end

"""
    make_widget_table_row(values) -> CellVector

One row of a table, from a vector of values or documents: a document passes
through, a function of no arguments becomes a live `WidgetLabel` that shows its
answer, and anything else becomes a `WidgetLabel` of its text. It is what a node
of a list-backed table holds.
"""
make_widget_table_row(values) = _table_row(values)

# String convenience shim: headers become a column-header strip, rows become the
# body, columns inferred from the header count (or the widest row). A value that
# is not a document becomes a `WidgetLabel` through `_table_cell_doc`, and a
# function a live one.
function WidgetTable(headers::Vector, rows::Vector; position::Point2D=Point2D(0, 0),
                     border_width::Integer=1, visible::Bool=true,
                     column_policy::SizePolicy=Content, row_policy::SizePolicy=Content,
                     column_policies=Any[], row_policies=Any[],
                     cell_policy::Symbol=:clip, column_cell_policies=Symbol[],
                     column_align=Symbol[],
                     margin=nothing, border=nothing, padding=nothing, style=nothing,
                     tooltip=nothing)
    column_count = isempty(headers) ?
        (isempty(rows) ? 0 : maximum(length(r) for r in rows)) : length(headers)
    WidgetTable(; position = position, column_headers = collect(Any, headers), row_headers = Any[],
                rows = collect(Any, rows), column_count = column_count,
                border_width=border_width, visible=visible,
                column_policy=column_policy, row_policy=row_policy,
                column_policies=column_policies, row_policies=row_policies,
                cell_policy=cell_policy, column_cell_policies=column_cell_policies,
                column_align=column_align,
                margin=margin, border=border, padding=padding, style=style,
                tooltip=tooltip)
end

# What the REPL and the answer of a tool show of a table: how many rows and
# columns it has, and its column headers, which say what it holds. The rows are
# in the tab, and a model that reads this answer can say how many there are
# without a guess. Julia's own display of a value, so a `print` or a `show` of the
# table is as it was.
function Base.show(io::IO, ::MIME"text/plain", table::WidgetTable)
    headers = [_describe_table_header(header) for header in table.column_headers]
    columns = isempty(headers) ? table.column_count : length(headers)
    print(io, "WidgetTable(", _count_table_rows(table.rows), " rows × ", columns, " columns")
    isempty(headers) || print(io, ": ", join(headers, ", "))
    print(io, ")")
end

_count_table_rows(rows) = try count(_ -> true, rows) catch; 0 end

_describe_table_header(header::Cell) = _describe_table_header(header[])
_describe_table_header(header::AbstractString) = String(header)
_describe_table_header(header::WidgetLabel) = _describe_table_header(header.content)
_describe_table_header(::Nothing) = ""
_describe_table_header(header) =
    hasproperty(header, :value) && header.value isa AbstractString ? String(header.value) :
                                                                     string(nameof(typeof(header)))

# ── WidgetTree ──────────────────────────────────────────────────────────────

"""
    WidgetTreeNode(icon, label, children = [])

A single node of a [`WidgetTree`](@ref) carrying a dedicated **icon** slot
distinct from its text **label** (the decoration model used by typical widget
libraries — Swing `JTree` renderers, Qt's `QTreeView` decoration role). `icon`
is `Any`: a glyph `String` today, an image document later. `children` is a
`Vector` of child nodes (each a `WidgetTreeNode` or a leaf `String`), or a
`CellVector` of them; an empty one marks a leaf, and a leaf has no chevron.

The tree reads `children` only for a row that it draws, to know if the row has
a chevron, and for an open node, to draw the rows under it. So a `CellVector`
whose elements are computed one at a time reads nothing for a node that is not
drawn, and one element for each child row that is drawn.
"""
struct WidgetTreeNode
    icon::Any
    label::Any
    children::Any                # a Vector, or a CellVector read only when needed
    gestures::Any
end
# A node is a plain value (not a `Document`), so it has no `selection`; its
# per-instance `gestures` are fired by `read_bound_gesture` against the enclosing
# tree's selection. `gestures` defaults empty so existing 2-/3-arg calls are
# unaffected; pass `gestures=[…]` to give a node its own behavior (e.g. a
# right-click / Enter binding that opens what the node stands for).
WidgetTreeNode(icon, label, children; gestures=GestureBinding[]) =
    WidgetTreeNode(icon, label, children, gestures)
WidgetTreeNode(icon, label; gestures=GestureBinding[]) =
    WidgetTreeNode(icon, label, Any[], gestures)

get_instance_gesture_bindings(node::WidgetTreeNode) = node.gestures

"""
    WidgetTree(roots; position)

A tree / outline view. `roots` is a `Vector` of nodes. A node is a
[`WidgetTreeNode`](@ref) (icon + label + children) or a leaf label (`String`).
For an icon-less tree, a `(label, children::Vector)` tuple is also accepted: the
constructor makes it a `WidgetTreeNode` with no icon, so that a reference of the
tree reaches each child as `children[j]`. Parent nodes get
an expand chevron; an icon (when present) is drawn in its own column before the
label; children are indented. (A widget-styled counterpart to the file-system /
navigator trees.)

`expanded` is **transient UI state** (like [`WidgetButton`](@ref)'s `pressed`):
the set of node paths (1-based index chains) whose children show, toggled by
clicking a parent's chevron. A node is closed until its path is in `expanded`,
so the owner of a tree names the nodes it opens at the start. It is not part of
the tree's content. The row under the pointer lights: the tree reads its node
path from the mouse target of the tree.

`margin`, `border` and `padding` are `nothing` or an `Inset`, each `nothing`
taking the projection's default (transparent, zero width); `style` is `nothing`,
a `WidgetStyle`, or a `WidgetTreeStyle`, overriding one color of the projection.
"""
@document struct WidgetTree <: WidgetDocument
    position::Point2D
    roots::CellVector
    visible::Bool
    margin::Inset
    border::Inset
    padding::Inset
    style::Any
    expanded::Set{Vector{Int}}   # transient: node paths whose children show
    gestures::Any                # per-instance tree-level gesture bindings
    tooltip::Any
end
WidgetTree(roots::Vector; position::Point2D=Point2D(0, 0), visible::Bool=true,
           margin=nothing, border=nothing, padding=nothing, style=nothing,
           expanded=Set{Vector{Int}}(), gestures=GestureBinding[], tooltip=nothing) =
    WidgetTree(Cell(position), CellVector(Cell[Cell(_convert_to_tree_node(n)) for n in roots]),
               Cell(visible), Cell(margin), Cell(border), Cell(padding), Cell(style),
               Cell(Set{Vector{Int}}(expanded)), Cell(gestures), Cell(tooltip))

# A `(label, children)` tuple becomes a node with no icon, and so do the tuples
# among its children. Any other node is kept as it is.
_convert_to_tree_node(node::Tuple{Any, AbstractVector}) =
    WidgetTreeNode("", node[1], Any[_convert_to_tree_node(child) for child in node[2]])
_convert_to_tree_node(node) = node

# Tree-level gestures (over the whole tree); per-node gestures live on each
# `WidgetTreeNode`. See `get_instance_gesture_bindings` / `read_bound_gesture`.
get_instance_gesture_bindings(w::WidgetTree) = w.gestures

# ── Operations ─────────────────────────────────────────────────────────────

"""
    CloseTabOperation(widget, tab_index)

Signals that the close button of tab `tab_index` (1-based) of `widget` was
clicked. It only *reports* — the strip knows a button was pressed and nothing
about what closing means, so the projection that owns the tabs answers it with an
edit of its own document. A click on a tab itself is a `ReplaceSelectionOperation`
of `selector_element_pairs[tab_index]`.
"""
struct CloseTabOperation <: Operation
    widget::WidgetTabbedPane
    tab_index::Int
end

"""
    OpenTabOperation(widget)

Signals that the new-tab button of `widget`'s strip was clicked. Reports only;
see [`CloseTabOperation`](@ref).
"""
struct OpenTabOperation <: Operation
    widget::WidgetTabbedPane
end

"""
    DragTabOperation(widget, tab_index)

Signals that a mouse button went down on tab `tab_index` (1-based) of `widget` —
the grab that may become a drag. Reports only: the strip resolves *which tab* was
grabbed, and the projection that owns the tabs runs the drag from there, because
only it knows where a tab may be dropped.
"""
struct DragTabOperation <: Operation
    widget::WidgetTabbedPane
    tab_index::Int
end

"""
    DuplicateTabOperation(widget, tab_index)

Signals that the duplicate button of tab `tab_index` (1-based) of `widget` was
clicked: the `+` above the close button. Reports only; see
[`CloseTabOperation`](@ref).
"""
struct DuplicateTabOperation <: Operation
    widget::WidgetTabbedPane
    tab_index::Int
end

"""
    StartSplitterDragOperation(split, splitter_index, anchor_coord, slot_sizes)

Begin dragging the splitter after slot `splitter_index` of `split`. Materialises
the pane's `sizes` from the currently measured `slot_sizes` (one per slot) when
empty, records the grab origin (`anchor_coord`, the main-axis coordinate of the
press, plus the two adjacent slot sizes) in `drag_anchor`, and marks the pane as
actively dragging via `active_splitter`. Transient UI state only.
"""
struct StartSplitterDragOperation <: Operation
    split::WidgetSplitPane
    splitter_index::Int
    anchor_coord::Int
    slot_sizes::Vector{Int}
end

"""
    ResizeSplitPaneOperation(split, splitter_index, new_size_a, new_size_b)

Redistribute space across the splitter after slot `splitter_index`: write
`sizes[splitter_index] = new_size_a` and `sizes[splitter_index+1] = new_size_b`.
The reader computes both values so their sum equals the pre-drag total (space is
conserved) and each stays within its slot's min/max. A size and a pin that the
pane already holds are not written again, so a move to the point of the last move
writes no cell.
"""
struct ResizeSplitPaneOperation <: Operation
    split::WidgetSplitPane
    splitter_index::Int
    new_size_a::Int
    new_size_b::Int
end

"""
    EndSplitterDragOperation(split)

Finish a splitter drag: reset `active_splitter` to `0` and clear `drag_anchor`.
"""
struct EndSplitterDragOperation <: Operation
    split::WidgetSplitPane
end

"""
    SetTableColumnWidthOperation(table, column, width)

Give column `column` of `table` the width `width`, the width of its cells in
pixels: the drag of the right edge of a header answers it at each move. A table
whose columns are a vector keeps it as `Fixed(width)` in `column_policies`, and
`column` counts from its first column. A table whose columns are a list counts
`column` from its head column and keeps no width of its own: the owner that
gives its policies as a list reads the operation and keeps the width.
"""
struct SetTableColumnWidthOperation <: Operation
    table::WidgetTable
    column::Int
    width::Int
end

"""
    CommitTableCellOperation(table, row, column, key)

The commit of the open cell in row `row` and column `column` of `table`, in the
numbers of the paths of the table: Enter (`key = :return`), Tab (`:tab`) or
Shift+Tab (`:backtab`) in the cell. The owner of the table that holds the cell
open converts it into its own commit and moves the selection by `key`; a table
that no owner converts commits nothing.
"""
struct CommitTableCellOperation <: Operation
    table::WidgetTable
    row::Int
    column::Int
    key::Symbol
end

"""
    DropTableCellOperation(table, row, column)

The drop of the open cell in row `row` and column `column` of `table`, which
Escape in the cell writes: the owner drops what was typed there.
"""
struct DropTableCellOperation <: Operation
    table::WidgetTable
    row::Int
    column::Int
end

"""
    EditTableCellOperation(table, row, column, text)

The opening of the cell in row `row` and column `column` of `table`, in the
numbers of the paths of the table, by a key on the whole cell that the cell takes
no key for: F2 (`text = nothing`) opens it with its value, and a typed character
(`text`, its text) opens it with the text in place of the value. The owner of
the table converts it into its own opening; a table that no owner converts opens
nothing.
"""
struct EditTableCellOperation <: Operation
    table::WidgetTable
    row::Int
    column::Int
    text::Union{Nothing,String}
end

# ── Action (Stage 4) ────────────────────────────────────────────────────────

"""
    Action(label; icon=nothing, enabled=true, shortcut=nothing, callback=nothing)

A command with a label, a callback and an enabled flag, shared by every control
that shows it.

Use it to name one command once and show it in a button, a menu item and a
keyboard shortcut; the `label` and `enabled` drive every one of them, and
setting `enabled` to `false` disables all of them at once. The `callback` runs
when the command is invoked, with the editor when it accepts one argument and
with none otherwise.

# Example

    again = Action("Run again"; callback = editor -> run_simulations!(select_simulations!(editor; config = "TandemQueue")))
    open_pane!(editor, WidgetButton(again); title = "Runner")

`shortcut` is a `KeyDownPattern` (build one with [`Shortcut`]); `icon` is the
name of an icon drawn before the label. A click invokes it through
[`InvokeActionOperation`].

See also `WidgetButton`, which shows one.
"""
@document struct Action
    label::Any
    icon::Any
    enabled::Bool
    shortcut::Any
    callback::Any
end

function Action(label;
               icon=nothing,
               enabled::Bool=true,
               shortcut=nothing,
               callback=nothing)
    Action(Cell(label), Cell(icon), Cell(enabled), Cell(shortcut), Cell(callback))
end

"""
    show(io::IO, x::Action)

The generic document rendering, with the `callback` named rather than printed.

A callback is a closure, and printing a closure prints what it captured. An
action a projection reader builds captures the io map and the document under
it, so the generic `show` turns one command into megabytes of text — which the
editor then pays for on every operation it logs. Everything else an action
carries is small, so the other fields print as they always did.
"""
function Base.show(io::IO, x::Action)
    depth = get(io, :document_depth, 0)
    print(io, "Action(")
    if depth ≥ DOCUMENT_SHOW_MAX_DEPTH
        print(io, "…")
    else
        inner = IOContext(io, :document_depth => depth + 1)
        first = true
        for f in fieldnames(typeof(x))
            is_view_state_field(f) && continue
            first || print(io, ", ")
            if f === :callback
                print(io, getproperty(x, f) === nothing ? "nothing" : "callback")
            else
                show(inner, getproperty(x, f))
            end
            first = false
        end
    end
    print(io, ")")
end

# How a control acquires its `Action` — the one place the sugar forms resolve.
#
# A bound `Action` (passed as `action =`, `command =`, or the positional
# content) is the source of truth and passes through untouched; a control never
# writes to a shared action, so an own label/icon that DIFFERS from the bound
# action's has nowhere to live and errors loudly (make a second `Action`
# sharing the callback instead). A bare callable — or nothing, for an inert
# control — is folded together with the control's own `content`/`icon` into a
# fresh `Action`, whose cells then ARE the storage: there is exactly one home
# for the command's appearance, and the printers need no precedence rule.
function resolve_action(content, icon, action)
    bound = content isa Action ? content : nothing
    behaviour = action
    if bound !== nothing
        behaviour === nothing ||
            error("the positional content is already an Action; pass no `action` beside it")
        _own_conflicts(icon, bound.icon) &&
            error("an own `icon` differing from the bound Action's cannot be kept — put it on the Action")
        return bound
    end
    if behaviour isa Action
        _own_conflicts(content, behaviour.label) &&
            error("an own content (\"$content\") differing from the bound Action's label cannot be kept — make a second Action sharing the callback")
        _own_conflicts(icon, behaviour.icon) &&
            error("an own `icon` differing from the bound Action's cannot be kept — put it on the Action")
        return behaviour
    end
    Action(content; icon = icon, callback = behaviour)
end

# An own appearance value conflicts with the bound action's only when it is
# actually saying something (a non-empty name or icon) and says something else.
# Restricted to the scalar appearance kinds on purpose: a rich content (an image,
# a nested widget) is never a duplicate of a bound action's label, and comparing
# documents for equality here would be both meaningless and expensive.
_own_conflicts(own::Union{AbstractString,Symbol}, bound) = !isempty(string(own)) && own != bound
_own_conflicts(::Any, ::Any) = false

"""
    Shortcut(key; ctrl=false, alt=false, shift=false, meta=false) -> KeyDownPattern

Build an `Action.shortcut` that matches the physical `key` with exactly the given
modifiers — e.g. `Shortcut(:s; ctrl=true)` for Ctrl+S.
"""
function Shortcut(key::Symbol; ctrl::Bool=false, alt::Bool=false, shift::Bool=false, meta::Bool=false)
    mods = Symbol[]
    ctrl  && push!(mods, :ctrl)
    shift && push!(mods, :shift)
    alt   && push!(mods, :alt)
    meta  && push!(mods, :meta)
    KeyDownPattern(key; modifiers = mods)
end

# True when `evt` fires `action`'s shortcut and the action is enabled. Reuses the
# gesture-layer `matches_gesture_pattern` (exact-modifier `KeyDownPattern` matching).
matches_action_shortcut(action::Action, evt) =
    action.shortcut !== nothing && !(action.enabled === false) && matches_gesture_pattern(action.shortcut, evt)

"""
    InvokeActionOperation(action)

Invoke an [`Action`]'s `callback` — the command shared by a menu item, a toolbar
button, and a keyboard shortcut. Called with the editor when it accepts one
argument, else with none. A disabled action, or a `nothing` callback, is a no-op.
"""
struct InvokeActionOperation <: Operation
    action::Action
end

# The operations of this package name their SUBJECT and not a place: the action
# to invoke, the tabbed pane whose tab to close, the split whose divider moved.
# There is nothing for a projection to re-root and nothing for one to place, so
# they travel up the chain as they are — which is what lets a button rendered
# inside a document reach the editor at all. Without this the generic reader of
# `Projection` drops every one of them, and a control inside a card, a pane or a
# page is dead while it looks and draws exactly right.
OperationModule.is_self_contained_operation(::Union{
    InvokeActionOperation, CloseTabOperation, OpenTabOperation,
    DragTabOperation, DuplicateTabOperation, StartSplitterDragOperation,
    ResizeSplitPaneOperation, EndSplitterDragOperation}) = true

"""
    _write_view_state(widget, field, value) -> ReplaceViewStateOperation

The write of a widget's pointer state — `pressed`, a slider's
`dragging` — marked as view state, so a history never records it.
"""
_write_view_state(widget, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(widget, field, value))

# ── Dormant selections ─────────────────────────────────────────────────────
#
# A tabbed pane shows the tab its own selection names, so clearing that selection
# makes it forget which tab it was showing, and forget the caret inside that tab
# with it. Both keep what the live selection leaves behind.
#
# The pane answers as well as the page because the two sit on opposite sides of
# the divergence: switching tabs diverges at the pane's own `selector_element_pairs`
# collection, where the abandoned branch starts at the page, while a selection
# leaving the pane altogether diverges above it.
has_dormant_selection(::WidgetTabbedPane) = true
has_dormant_selection(::WidgetTabPage) = true
# A split pane's selection names which side had the focus, so the same holds for a
# nested split when the focus comes back from outside it.
has_dormant_selection(::WidgetSplitPane) = true

# ── Operation evaluation ───────────────────────────────────────────────────

# The four strip reports are inert when nothing claimed them. A press on a close
# button with no projection above to say what closing means must do nothing — the
# report reached the editor because no one answered it, which is not an error.
"""
    evaluate_operation(op)

Apply a widget operation.
"""
evaluate_operation(editor, op::CloseTabOperation) = nothing
evaluate_operation(editor, op::OpenTabOperation) = nothing
evaluate_operation(editor, op::DragTabOperation) = nothing
evaluate_operation(editor, op::DuplicateTabOperation) = nothing

function evaluate_operation(editor, op::StartSplitterDragOperation)
    split = op.split
    sizes = split.sizes
    # Materialise `sizes` from the measured slot extents so the first drag has
    # concrete cells to mutate (otherwise the slot falls back to a fixed size).
    if isempty(sizes) || length(sizes) < length(op.slot_sizes)
        sizes.elements = Cell[Cell(s) for s in op.slot_sizes]
    end
    # Keep the per-slot pin vector the same length as `sizes`.
    pinned = split.pinned
    if length(pinned) != length(sizes)
        pinned.elements = Cell[Cell(false) for _ in 1:length(sizes)]
    end
    k = op.splitter_index
    split.active_splitter = k
    split.drag_anchor = (coord = op.anchor_coord,
                         size_a = Int(sizes[k]),
                         size_b = Int(sizes[k + 1]))
end

function evaluate_operation(editor, op::ResizeSplitPaneOperation)
    split = op.split
    sizes = split.sizes
    k = op.splitter_index
    sizes[k] == op.new_size_a || (sizes[k] = op.new_size_a)
    sizes[k + 1] == op.new_size_b || (sizes[k + 1] = op.new_size_b)
    # Pin both dragged slots so the constrained layout honours their new size
    # exactly instead of redistributing it by weight.
    pinned = split.pinned
    if length(pinned) >= k + 1
        pinned[k] === true     || (pinned[k] = true)
        pinned[k + 1] === true || (pinned[k + 1] = true)
    end
end

function evaluate_operation(editor, op::EndSplitterDragOperation)
    op.split.active_splitter = 0
    op.split.drag_anchor = nothing
end

# The width operation names its table, so it travels up a chain as it is, and the
# owner of a table whose columns are a list reads it on the way.
is_self_contained_operation(::SetTableColumnWidthOperation) = true

# The opening, the commit and the drop of a cell name their table, so they travel
# up a chain as they are, and the owner that holds the cell open converts them;
# one that reaches the root found no owner, and does nothing.
is_self_contained_operation(::Union{EditTableCellOperation,CommitTableCellOperation,
                                    DropTableCellOperation}) = true
evaluate_operation(editor, ::Union{EditTableCellOperation,CommitTableCellOperation,DropTableCellOperation}) = nothing

function evaluate_operation(editor, op::SetTableColumnWidthOperation)
    table = op.table
    policies = table.column_policies
    (policies isa AbstractVector && op.column >= 1) || return nothing
    width = Fixed(op.width)
    op.column <= length(policies) && policies[op.column] == width && return nothing
    written = Any[policies...]
    while length(written) < op.column
        push!(written, table.column_policy)
    end
    written[op.column] = width
    table.column_policies = written
    nothing
end

function evaluate_operation(editor, op::InvokeActionOperation)
    action = op.action
    action.enabled === false && return        # a disabled action is inert
    callback = action.callback
    callback === nothing && return
    # A callback can be newer than the loop that presses it: a closure typed into
    # the evaluator, or written by the assistant, is made after the loop was
    # compiled. From the loop's own world `applicable` answers false for it, so
    # the check and the call both run in the latest world.
    if Base.invokelatest(applicable, callback, editor)
        Base.invokelatest(callback, editor)
    elseif Base.invokelatest(applicable, callback)
        Base.invokelatest(callback)
    end
end

# ── Focus traversal (Stage 2): which widgets are Tab stops ──────────────────
#
# The walk itself is generic and lives in `FocusModule`. This is the widget
# domain's one answer to its open trait. See plan/done/widget-focus-traversal.md.

# The interactive widget types that are Tab stops — exactly the Stage-1
# `enabled`-bearing leaves. A disabled instance is *not* a stop.
const FocusableWidget = Union{WidgetButton, WidgetCheckbox, WidgetText,
    WidgetTextarea, WidgetSelect, WidgetSwitch, WidgetSlider, WidgetSpinBox,
    WidgetToggle, WidgetToggleGroup, WidgetRadioGroup, WidgetMenuItem,
    WidgetToolbarItem}

# Every FocusableWidget carries the `enabled` cell, so the read is safe.
FocusModule.is_focusable_document(w::FocusableWidget) = !(getfield(w, :enabled)[] === false)

# ── What a widget says about itself ──────────────────────────────────────────

# A widget stores what it says about itself, where every other document computes
# it: whoever places a widget knows why it is there, and the widget does not. Both
# fields hold `nothing` until somebody sets one. A `String` is wrapped, because most
# tooltips are one line and `tooltip = "Run the selected configurations"` is what
# a caller wants to write.
_find_widget_tooltip(widget::WidgetDocument) = _as_tooltip_document(widget.tooltip)

_as_tooltip_document(::Nothing) = nothing
_as_tooltip_document(text::AbstractString) = PrimitiveString(String(text))
_as_tooltip_document(document) = document

# A toolbar item that shows only a picture still says what it does: with no
# tooltip of its own, it says the label of its action. An empty label says
# nothing.
function _find_widget_tooltip(item::WidgetToolbarItem)
    item.tooltip === nothing || return _as_tooltip_document(item.tooltip)
    label = item.action.label
    label isa AbstractString || return _as_tooltip_document(label)
    isempty(label) ? nothing : _as_tooltip_document(label)
end

# A widget says it when the pointer rests on it: the dwell is a gesture of every
# widget, and a command runs it on the selected one.
get_document_gesture_bindings_own(::Type{WidgetDocument}) =
    GestureBinding[make_tooltip_binding(_find_widget_tooltip)]

# The shell is the window's own frame, so the menu it holds is the window's. A
# right click anywhere in the window reaches the shell last, so its menu is the
# outermost layer of a context menu, which F2 shows from any part of the window.
compute_context_menu(shell::WidgetShell) = shell.context_menu

get_document_gesture_bindings_own(::Type{WidgetShell}) =
    GestureBinding[make_context_menu_binding(compute_context_menu;
                                             description = "Show the window menu")]

# A right click over the child of a `WidgetContextMenu` opens the menu that the
# wrapper gives the child; a disabled wrapper has none.
get_document_gesture_bindings_own(::Type{WidgetContextMenu}) =
    GestureBinding[make_context_menu_binding(_find_widget_context_menu)]

_find_widget_context_menu(widget::WidgetContextMenu) =
    widget.enabled === false ? nothing : widget.menu

# A shell wraps the window's own document in the chrome it is drawn in, and it is
# transparent to everything that reads the tree rather than the picture: a verb
# that asks for the pane tree, a save that looks for the files a window holds.
get_wrapped_document(shell::WidgetShell) = get_wrapped_document(shell.content)

# A saved user interface holds the window a person arranged, with its size, its
# margins and its style, and not the bands around it. The bands are what the
# binary offers, built fresh from its own vocabulary every time it starts, so
# that one binary's menu is not in a file that another binary opens: the menus
# and the toolbar hold actions with callbacks, the status bar holds computations
# that a file would freeze, and the overlay is a tooltip that shows for a moment.
# On open, a size that the application gives wins over the saved one.
pred_arguments(shell::WidgetShell) =
    (shell.content,), _get_field_keywords(shell, (:overlay, :menu_bar, :toolbar,
                                                  :context_menu, :status_bar))

# A saved window keeps a scroll pane whole: what it holds, its size, and where it
# was scrolled. A list of the Help menu is a tab of this kind.
pred_arguments(pane::WidgetScrollPane) = (pane.content,), _get_field_keywords(pane, ())

# The keywords that a file writes for `widget` by default, but for its content,
# which is written as the first argument, and for the fields `left_out`.
_get_field_keywords(widget::WidgetDocument, left_out::Tuple) =
    filter(keyword -> first(keyword) !== :content && !(first(keyword) in left_out),
           last(invoke(pred_arguments, Tuple{Any}, widget)))

# A person sees through a scroll pane to what it shows, which names the pane.
get_edited_field(::WidgetScrollPane) = :content
get_document_title(pane::WidgetScrollPane) = get_document_title(pane.content)
