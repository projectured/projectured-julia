"""
    WidgetModule

The widget document domain. Widgets are UI-layer documents that sit above
the graphics domain and below application-specific projections. Each widget
type subtypes the abstract WidgetDocument base (itself a Document) and
carries reactive Cell fields for all mutable properties.
"""
module WidgetModule

import ..CellModule: Cell, set_cell_function!, set_cell_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..OperationApiModule: Operation, evaluate_operation
import ..EventPatternModule: KeyDownPattern, matches_event_pattern
import ..GestureBindingModule: GestureBinding, get_instance_gesture_bindings
import ..ColorModule: StyleColor
import ..StyleTextModule: StyleText, DStyleText
import ..ReferenceModule: Reference, ConcreteReference, ElementReferenceStep,
                          EmptyReference, FieldReferenceStep, RangeReferenceStep
import ..GeometryModule: Inset, Point2D, inset_default,
                        inset_size, inset_width, inset_height,
                        inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right,
                        AffineTransform, affine_identity
export Inset, Point2D, WidgetDocument, WidgetToolButton, WidgetMessageBox, WidgetInputDialog,
       WidgetTreeNode, SelectTabOperation, StartSplitterDragOperation, ResizeSplitPaneOperation,
       EndSplitterDragOperation, InvokeWidgetActionOperation, Shortcut, action_shortcut_matches,
       InvokeActionOperation, numeric_validator, evaluate_operation, inset_default, inset_size,
       inset_width, inset_height, inset_top_left, inset_top_right, inset_bottom_left,
       inset_bottom_right, set_cell_function!,
       widget_list_selection, widget_list_selected,
       widget_table_row_selection, widget_table_selected_row

# ── WidgetDocument (abstract base) ─────────────────────────────────────────────────

"""
    WidgetDocument

Abstract base type for all widget documents.  Subtypes the `Document`
contract.  Every
concrete widget carries the seven base fields (`visible`, `margin`,
`margin_color`, `border`, `border_color`, `padding`, `padding_color`)
plus its own positional / content fields; `@document` injects the
`selection::Union{Nothing, Reference}`.
"""
abstract type WidgetDocument <: Document end

# ── WidgetInsertion ─────────────────────────────────────────────────────

@document struct WidgetInsertion <: WidgetDocument
    value::Any = nothing
end

# ── WidgetLabel ────────────────────────────────────────────────────────────

"""
    WidgetLabel(position, content; <base kwargs>)

A positioned, non-interactive label..
"""
@document struct WidgetLabel <: WidgetDocument
    position::Point2D
    content::Any
    text_style::ImmutableCell{DStyleText}   # per-label font+color override (nothing → theme label style)
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetLabel(position::Point2D, content;
                     text_style=nothing,
                     visible::Bool=true,
                     margin::Inset=inset_default,
                     margin_color=nothing,
                     border::Inset=inset_default,
                     border_color=nothing,
                     padding::Inset=inset_default,
                     padding_color=nothing)
    WidgetLabel(Cell(position), Cell(content), Cell(text_style),
                Cell(visible), Cell(margin), Cell(margin_color),
                Cell(border), Cell(border_color),
                Cell(padding), Cell(padding_color),
                Cell(nothing))
end

set_cell_function!(w::WidgetLabel, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

# ── WidgetText ─────────────────────────────────────────────────────────────

"""
    WidgetText(position, content; content_fill_color, <base kwargs>)

An editable text widget..
"""
@document struct WidgetText <: WidgetDocument
    position::Point2D
    content::Any
    content_fill_color::StyleColor
    validator::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetText(position::Point2D, content;
                    content_fill_color=nothing,
                    validator=nothing,
                    visible::Bool=true,
                    enabled::Bool=true,
                    margin::Inset=inset_default,
                    margin_color=nothing,
                    border::Inset=inset_default,
                    border_color=nothing,
                    padding::Inset=inset_default,
                    padding_color=nothing)
    # `validator` (optional) is a callable consulted before an edit commits
    # (Stage 6). Stored as a primitive cell value, like an action callback.
    validator_cell = Cell(nothing); set_cell_value!(validator_cell, validator)
    WidgetText(Cell(position), Cell(content), Cell(content_fill_color), validator_cell,
               Cell(visible), Cell(enabled), Cell(margin), Cell(margin_color),
               Cell(border), Cell(border_color),
               Cell(padding), Cell(padding_color),
               Cell(nothing))
end

set_cell_function!(w::WidgetText, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

"""
    numeric_validator(; integer=false, allow_negative=true) -> (String) -> Bool

A text-input validator (input mask, Stage 6): accepts an inserted edit string
made only of digits — plus, when allowed, `-` (sign) and `.` (decimal point). An
empty string (a deletion) is always accepted. Used by `WidgetSpinBox`; pass it
to `WidgetText(...; validator=…)` for a numeric field. A validator is any
`(String) -> Bool` acceptor; the editable reader drops an edit it rejects.
"""
function numeric_validator(; integer::Bool=false, allow_negative::Bool=true)
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
    WidgetSpinBox(position, value; min=nothing, max=nothing, step=1, width=120,
                  validator=numeric_validator(), <enabled/visible>)

A numeric stepper (Qt's `QSpinBox`): shows `value` with up/down steppers that add
/ subtract `step`, clamped to `[min, max]` (a `nothing` bound is unbounded). The
`validator` is a hook for future typed entry; stepping is always numeric. Stage 6.
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
end

function WidgetSpinBox(position::Point2D, value;
                       min=nothing, max=nothing, step=1, width::Integer=120,
                       validator=numeric_validator(),
                       visible::Bool=true, enabled::Bool=true)
    validator_cell = Cell(nothing); set_cell_value!(validator_cell, validator)
    WidgetSpinBox(Cell(position), Cell(value), Cell(min), Cell(max), Cell(step),
                  Cell(Int(width)), validator_cell, Cell(visible), Cell(enabled), Cell(nothing))
end

# ── WidgetList ───────────────────────────────────────────────────────────────

"""
    WidgetList(position, items; selected=0, width=220, <enabled/visible>)

A single-column selectable list (Qt's `QListWidget`): `items` are stringified
rows; the selected row draws a selection band. A click selects the hit row;
Up/Down move the selection. Stage 6.

Selection lives in the standard macro-injected `selection` field, as a reference
`items[i-1:i]` — the same representation [`WidgetTable`](@ref) uses for its rows,
so a reader returns a `ReplaceSelectionOperation` like every other widget and an
enclosing projection can map the reference across domains. The `selected`
keyword is 1-based sugar (`0` = none) that builds that reference; read the
selection back with [`widget_list_selected`](@ref).
"""
@document struct WidgetList <: WidgetDocument
    position::Point2D
    items::CellVector
    width::Int
    visible::Bool
    enabled::Bool
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
widget_list_selection(i::Integer) = _widget_element_selection("items", i)

"""
    widget_list_selected(list) -> Int

The selected row of a [`WidgetList`](@ref) as a 1-based index, or `0` when
nothing is selected. The inverse of the `selected` construction keyword.
"""
widget_list_selected(w::WidgetList) = _widget_element_selected(w.selection, "items")

function WidgetList(position::Point2D, items::Vector;
                    selected::Integer=0, width::Integer=220,
                    visible::Bool=true, enabled::Bool=true)
    WidgetList(Cell(position), CellVector(Cell[Cell(x) for x in items]),
               Cell(Int(width)), Cell(visible), Cell(enabled),
               Cell(widget_list_selection(selected)))
end

# ── WidgetCheckbox ─────────────────────────────────────────────────────────

"""
    WidgetCheckbox(position, content; <base kwargs>)

A checkbox widget..

`enabled` (default `true`) is a shared interactivity flag alongside `visible`:
when `false` the checkbox renders muted and its reader refuses to emit the toggle
operation.
"""
@document struct WidgetCheckbox <: WidgetDocument
    position::Point2D
    content::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    gestures::Any               # per-instance gesture bindings (see get_instance_gesture_bindings)
end

function WidgetCheckbox(position::Point2D, content;
                        gestures=GestureBinding[],
                        visible::Bool=true,
                        enabled::Bool=true,
                        margin::Inset=inset_default,
                        margin_color=nothing,
                        border::Inset=inset_default,
                        border_color=nothing,
                        padding::Inset=inset_default,
                        padding_color=nothing)
    WidgetCheckbox(Cell(position), Cell(content),
                   Cell(visible), Cell(enabled), Cell(margin), Cell(margin_color),
                   Cell(border), Cell(border_color),
                   Cell(padding), Cell(padding_color),
                   Cell(gestures))
end

set_cell_function!(w::WidgetCheckbox, f::Function) = (set_cell_function!(getfield(w, :content), f); w)
get_instance_gesture_bindings(w::WidgetCheckbox) = w.gestures

# ── WidgetButton ───────────────────────────────────────────────────────────

"""
    WidgetButton(position, size, content; action, <base kwargs>)

A clickable button.

`action` is an optional callable invoked when the button is clicked (via
`InvokeWidgetActionOperation`). It is called with the editor when it accepts one
argument, otherwise with none, so it can mutate `editor.document` / projection
state. A `nothing` action makes the button inert on click.

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

`hovered` and `pressed` are **transient UI state** holding the pointer
interaction: `hovered` is `true` while the pointer is inside the button,
`pressed` is `true` while the left button is held down on it. The printer reads
them to pick the surface fill, so changing them re-renders only this button.
They are written by the `WidgetButton` reader (a `ReplaceReferencedValueOperation` into the
`hovered` / `pressed` cell) and are not part of the document's content — they
are not meant to be serialised.
"""
@document struct WidgetButton <: WidgetDocument
    position::Point2D
    size::Point2D
    content::Any
    action::Any
    gestures::Any
    command::Any
    icon::Any
    dialog::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    hovered::Bool
    pressed::Bool
end

function WidgetButton(position::Point2D, size::Point2D, content;
                      action=nothing,
                      gestures=GestureBinding[],
                      command=nothing,
                      icon=nothing,
                      dialog=nothing,
                      visible::Bool=true,
                      enabled::Bool=true,
                      margin::Inset=inset_default,
                      margin_color=nothing,
                      border::Inset=inset_default,
                      border_color=nothing,
                      padding::Inset=inset_default,
                      padding_color=nothing)
    # `action` is a callback, not reactive content. `Cell(f::Function)` builds a
    # *computed* cell (thunk called with 0 args), so wrapping the callback as
    # `Cell(action)` would invoke it on read. Store it as a primitive cell value.
    action_cell = Cell(nothing); set_cell_value!(action_cell, action)
    # `gestures` is a per-instance `Vector{GestureBinding}` (behavior, not content).
    # It is consulted by the reader ahead of the built-in click/key handling, so a
    # binding can add (right-click, shift-click, …), override (same pattern), or
    # suppress (map to `DoNothingOperation()`) a default. Stored as a plain primitive cell.
    gestures_cell = Cell(nothing); set_cell_value!(gestures_cell, gestures)
    # `command` (optional) is a shared `Action` (Stage 4); `icon` (optional) is an
    # icon name drawn left of the label (Stage 5); `dialog` (optional) is a child
    # `WidgetDialog` opened modally on click.
    WidgetButton(Cell(position), Cell(size), Cell(content), action_cell, gestures_cell,
                 Cell(command), Cell(icon), Cell(dialog),
                 Cell(visible), Cell(enabled), Cell(margin), Cell(margin_color),
                 Cell(border), Cell(border_color),
                 Cell(padding), Cell(padding_color),
                 Cell(false), Cell(false))
end

set_cell_function!(w::WidgetButton, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

# Per-instance gesture bindings (see `get_instance_gesture_bindings` / `read_bound_gesture`).
get_instance_gesture_bindings(w::WidgetButton) = w.gestures

"""
    WidgetToolButton(icon; label="", size=Point2D(0, 0), <WidgetButton kwargs>)

An icon-first button (Qt's `QToolButton`): a `WidgetButton` showing `icon` with an
optional short `label`. A thin convenience over `WidgetButton`, so it accepts the
same keywords (`command`, `action`, `enabled`, `border`, …). Stage 5.
"""
WidgetToolButton(icon; label="", size::Point2D=Point2D(0, 0), kwargs...) =
    WidgetButton(Point2D(0, 0), size, label; icon=icon, kwargs...)

# ── WidgetTooltip ──────────────────────────────────────────────────────────

"""
    WidgetTooltip(position, size, content; <base kwargs>)

A floating tooltip overlay..
"""
@document struct WidgetTooltip <: WidgetDocument
    position::Point2D
    size::Point2D
    content::Any
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetTooltip(position::Point2D, size::Point2D, content;
                       visible::Bool=true,
                       margin::Inset=inset_default,
                       margin_color=nothing,
                       border::Inset=inset_default,
                       border_color=nothing,
                       padding::Inset=inset_default,
                       padding_color=nothing)
    WidgetTooltip(Cell(position), Cell(size), Cell(content),
                  Cell(visible), Cell(margin), Cell(margin_color),
                  Cell(border), Cell(border_color),
                  Cell(padding), Cell(padding_color),
                  Cell(nothing))
end

set_cell_function!(w::WidgetTooltip, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

# ── WidgetContextMenu ──────────────────────────────────────────────────────

"""
    WidgetContextMenu(child, menu; <base kwargs>)

Wraps `child`, rendering it unchanged (a transparent behavioural wrapper). A
**right** click anywhere over it opens `menu` (a `WidgetMenu`) as a popup placed at
the pointer (Stage 3 Step 4d). It reuses the popup window route: the right click
emits an `OpenPopupOperation` anchored to this wrapper with the *local* click
coordinates as the offset, so a content-root resolver places the menu at the
pointer — no pointer injection. Non-right events route to `child`. A disabled
wrapper ignores the right click (the child still works).
"""
@document struct WidgetContextMenu <: WidgetDocument
    child::Any
    menu::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetContextMenu(child, menu;
                          visible::Bool=true,
                          enabled::Bool=true,
                          margin::Inset=inset_default,
                          margin_color=nothing,
                          border::Inset=inset_default,
                          border_color=nothing,
                          padding::Inset=inset_default,
                          padding_color=nothing)
    WidgetContextMenu(Cell(child), Cell(menu),
                      Cell(visible), Cell(enabled), Cell(margin), Cell(margin_color),
                      Cell(border), Cell(border_color),
                      Cell(padding), Cell(padding_color),
                      Cell(nothing))
end

set_cell_function!(w::WidgetContextMenu, f::Function) = (set_cell_function!(getfield(w, :child), f); w)

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
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetDialog(title, content, buttons::Vector;
                     popup_id::Symbol=:widget_dialog,
                     visible::Bool=true,
                     margin::Inset=inset_default,
                     margin_color=nothing,
                     border::Inset=inset_default,
                     border_color=nothing,
                     padding::Inset=inset_default,
                     padding_color=nothing)
    WidgetDialog(Cell(title), Cell(content),
                 CellVector(Cell[Cell(b) for b in buttons]),
                 Cell(popup_id),
                 Cell(visible), Cell(margin), Cell(margin_color),
                 Cell(border), Cell(border_color),
                 Cell(padding), Cell(padding_color),
                 Cell(nothing))
end

set_cell_function!(w::WidgetDialog, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

"""
    WidgetMessageBox(title, message; buttons=["OK"], popup_id=:widget_dialog)

A `WidgetDialog` whose content is a `WidgetLabel(message)` and whose buttons are
plain closing `WidgetButton`s — the `QMessageBox` analogue.
"""
function WidgetMessageBox(title, message; buttons=["OK"], popup_id::Symbol=:widget_dialog)
    btns = Any[WidgetButton(Point2D(0, 0), Point2D(72, 0), b) for b in buttons]
    WidgetDialog(title, WidgetLabel(Point2D(0, 0), message), btns; popup_id=popup_id)
end

"""
    WidgetInputDialog(title, prompt; value="", popup_id=:widget_dialog)

A `WidgetDialog` whose content is a prompt label above a `WidgetText` field, with
Cancel / OK buttons — the `QInputDialog` analogue. (Editing the field needs the
text-widget projection, as for any `WidgetText`.)
"""
function WidgetInputDialog(title, prompt; value="", popup_id::Symbol=:widget_dialog)
    content = WidgetComposite(Point2D(0, 0), Any[
        WidgetLabel(Point2D(0, 0), prompt),
        WidgetText(Point2D(0, 28), value),
    ])
    WidgetDialog(title, content,
                 Any[WidgetButton(Point2D(0, 0), Point2D(72, 0), "Cancel"),
                     WidgetButton(Point2D(0, 0), Point2D(72, 0), "OK")];
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
    margin::Inset = inset_default
    margin_color::StyleColor = nothing
    border::Inset = inset_default
    border_color::StyleColor = nothing
    padding::Inset = inset_default
    padding_color::StyleColor = nothing
end

function WidgetMenu(elements::Vector;
                    orientation::Symbol=:vertical,
                    visible::Bool=true,
                    margin::Inset=inset_default,
                    margin_color=nothing,
                    border::Inset=inset_default,
                    border_color=nothing,
                    padding::Inset=inset_default,
                    padding_color=nothing)
    WidgetMenu(CellVector(Cell[Cell(x) for x in elements]),
               Cell(orientation),
               Cell(visible), Cell(margin), Cell(margin_color),
               Cell(border), Cell(border_color),
               Cell(padding), Cell(padding_color),
               Cell(nothing))
end

set_cell_function!(w::WidgetMenu, f::Function) = (set_cell_function!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetMenuItem ─────────────────────────────────────────────────────────

"""
    WidgetMenuItem(content; action=nothing, command=nothing, submenu=nothing, <base kwargs>)

A single item inside a `WidgetMenu`. `action` is an optional callback (same
contract as `WidgetButton.action`: called with the editor when it accepts one
argument, else with none) invoked via `InvokeWidgetActionOperation` on a left
click. `command` is an optional shared [`Action`] (Stage 4): when bound, the item
shows the action's `label`, follows its `enabled`, and a click emits
`InvokeActionOperation(command)` — so a menu item, a toolbar button, and a keyboard
shortcut can share one command. `submenu` is an optional `WidgetMenu` opened as a
popup just below the item on a left click; an item with a submenu opens it
**instead of** running its action/command, so the one item type serves a menu-bar
entry, a nested submenu, and a leaf command. A click on an enabled leaf item also
closes the enclosing popup (a no-op when the menu is rendered inline). A disabled
item (or one bound to a disabled command) is inert.
"""
@document struct WidgetMenuItem <: WidgetDocument
    content::Any
    action::Any
    gestures::Any
    command::Any
    icon::Any
    submenu::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    hovered::Bool
end

function WidgetMenuItem(content;
                        action=nothing,
                        gestures=GestureBinding[],
                        command=nothing,
                        icon=nothing,
                        submenu=nothing,
                        visible::Bool=true,
                        enabled::Bool=true,
                        margin::Inset=inset_default,
                        margin_color=nothing,
                        border::Inset=inset_default,
                        border_color=nothing,
                        padding::Inset=inset_default,
                        padding_color=nothing)
    # `action` is a callback, not reactive content — store it as a primitive cell
    # value (a computed `Cell(f)` would invoke it on read). Mirrors WidgetButton.
    action_cell = Cell(nothing); set_cell_value!(action_cell, action)
    WidgetMenuItem(Cell(content), action_cell, Cell(gestures), Cell(command), Cell(icon), Cell(submenu),
                   Cell(visible), Cell(enabled), Cell(margin), Cell(margin_color),
                   Cell(border), Cell(border_color),
                   Cell(padding), Cell(padding_color),
                   Cell(false))
end
get_instance_gesture_bindings(w::WidgetMenuItem) = w.gestures

set_cell_function!(w::WidgetMenuItem, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

# ── WidgetComposite ────────────────────────────────────────────────────────

"""
    WidgetComposite(position, elements; <base kwargs>)

A positioned container holding an ordered sequence of child widgets.

"""
@document struct WidgetComposite <: WidgetDocument
    position::Point2D
    elements::CellVector
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetComposite(position::Point2D, elements::Vector;
                         visible::Bool=true,
                         margin::Inset=inset_default,
                         margin_color=nothing,
                         border::Inset=inset_default,
                         border_color=nothing,
                         padding::Inset=inset_default,
                         padding_color=nothing)
    WidgetComposite(Cell(position), CellVector(Cell[Cell(x) for x in elements]),
                    Cell(visible), Cell(margin), Cell(margin_color),
                    Cell(border), Cell(border_color),
                    Cell(padding), Cell(padding_color),
                    Cell(nothing))
end

set_cell_function!(w::WidgetComposite, f::Function) = (set_cell_function!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetToolbar ──────────────────────────────────────────────────────────

"""
    WidgetToolbar(elements; <base kwargs>)

A horizontal strip of tool items (buttons, labels, separators) placed
below the menu bar in a `WidgetShell`.
"""
@document struct WidgetToolbar <: WidgetDocument
    elements::CellVector = CellVector()
    visible::Bool = true
    margin::Inset = inset_default
    margin_color::StyleColor = nothing
    border::Inset = inset_default
    border_color::StyleColor = nothing
    padding::Inset = inset_default
    padding_color::StyleColor = nothing
end

function WidgetToolbar(elements::Vector;
                       visible::Bool=true,
                       margin::Inset=inset_default,
                       margin_color=nothing,
                       border::Inset=inset_default,
                       border_color=nothing,
                       padding::Inset=inset_default,
                       padding_color=nothing)
    WidgetToolbar(CellVector(Cell[Cell(x) for x in elements]),
                  Cell(visible), Cell(margin), Cell(margin_color),
                  Cell(border), Cell(border_color),
                  Cell(padding), Cell(padding_color),
                  Cell(nothing))
end

set_cell_function!(w::WidgetToolbar, f::Function) =
    (set_cell_function!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

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
    margin::Inset = inset_default
    margin_color::StyleColor = nothing
    border::Inset = inset_default
    border_color::StyleColor = nothing
    padding::Inset = inset_default
    padding_color::StyleColor = nothing
end

function WidgetStatusBar(segments::Vector;
                         visible::Bool=true,
                         margin::Inset=inset_default,
                         margin_color=nothing,
                         border::Inset=inset_default,
                         border_color=nothing,
                         padding::Inset=inset_default,
                         padding_color=nothing)
    WidgetStatusBar(CellVector(Cell[Cell(x) for x in segments]),
                    Cell(visible), Cell(margin), Cell(margin_color),
                    Cell(border), Cell(border_color),
                    Cell(padding), Cell(padding_color),
                    Cell(nothing))
end

set_cell_function!(w::WidgetStatusBar, f::Function) =
    (set_cell_function!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetShell ────────────────────────────────────────────────────────────

"""
    WidgetShell(content; content_fill_color, size, tooltip, menu_bar,
                context_menu, <base kwargs>)

Top-level window shell..
"""
@document struct WidgetShell <: WidgetDocument
    content::Any
    content_fill_color::StyleColor
    size::Point2D
    tooltip::WidgetTooltip
    menu_bar::WidgetMenu
    toolbar::WidgetToolbar
    context_menu::WidgetMenu
    status_bar::WidgetStatusBar
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetShell(content;
                     content_fill_color=nothing,
                     size=nothing,
                     tooltip=nothing,
                     menu_bar=nothing,
                     toolbar=nothing,
                     context_menu=nothing,
                     status_bar=nothing,
                     visible::Bool=true,
                     margin::Inset=inset_default,
                     margin_color=nothing,
                     border::Inset=inset_default,
                     border_color=nothing,
                     padding::Inset=inset_default,
                     padding_color=nothing)
    WidgetShell(Cell(content), Cell(content_fill_color), Cell(size),
                Cell(tooltip), Cell(menu_bar), Cell(toolbar), Cell(context_menu),
                Cell(status_bar),
                Cell(visible), Cell(margin), Cell(margin_color),
                Cell(border), Cell(border_color),
                Cell(padding), Cell(padding_color),
                Cell(nothing))
end

set_cell_function!(w::WidgetShell, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

# ── WidgetTitlePane ────────────────────────────────────────────────────────

"""
    WidgetTitlePane(title, content; title_fill_color, content_fill_color,
                    <base kwargs>)

A pane with a title bar and a content area..
"""
@document struct WidgetTitlePane <: WidgetDocument
    title::Any
    title_fill_color::StyleColor
    content::Any
    content_fill_color::StyleColor
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetTitlePane(title, content;
                         title_fill_color=nothing,
                         content_fill_color=nothing,
                         visible::Bool=true,
                         margin::Inset=inset_default,
                         margin_color=nothing,
                         border::Inset=inset_default,
                         border_color=nothing,
                         padding::Inset=inset_default,
                         padding_color=nothing)
    WidgetTitlePane(Cell(title), Cell(title_fill_color),
                    Cell(content), Cell(content_fill_color),
                    Cell(visible), Cell(margin), Cell(margin_color),
                    Cell(border), Cell(border_color),
                    Cell(padding), Cell(padding_color),
                    Cell(nothing))
end

set_cell_function!(w::WidgetTitlePane, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

# ── WidgetSplitPane ────────────────────────────────────────────────────────

"""
    WidgetSplitPane(orientation, elements; sizes, <base kwargs>)

A container that divides its area among child widgets along an axis.
`orientation` is `:horizontal` or `:vertical`..

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
"""
@document struct WidgetSplitPane <: WidgetDocument
    orientation::Symbol
    elements::CellVector
    sizes::CellVector
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    active_splitter::Int
    drag_anchor::Any
    pinned::CellVector
end

function WidgetSplitPane(orientation::Symbol, elements::Vector;
                         sizes=nothing,
                         visible::Bool=true,
                         margin::Inset=inset_default,
                         margin_color=nothing,
                         border::Inset=inset_default,
                         border_color=nothing,
                         padding::Inset=inset_default,
                         padding_color=nothing)
    sizes_cv = sizes isa Vector ? CellVector(Cell[Cell(s) for s in sizes]) : CellVector()
    WidgetSplitPane(Cell(orientation), CellVector(Cell[Cell(x) for x in elements]), sizes_cv,
                    Cell(visible), Cell(margin), Cell(margin_color),
                    Cell(border), Cell(border_color),
                    Cell(padding), Cell(padding_color),
                    Cell(0), Cell(nothing), CellVector())
end

WidgetSplitPane(elements::Vector; kwargs...) =
    WidgetSplitPane(:horizontal, elements; kwargs...)

set_cell_function!(w::WidgetSplitPane, f::Function) = (set_cell_function!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetTabbedPane ───────────────────────────────────────────────────────

# A single tab page: the tab `selector` (label), its content `element`, and an
# optional `icon`. A first-class Document rather than a raw `(selector, element,
# icon)` tuple, so the selection chain descends Document→Document through a tabbed
# pane. With a tuple in the path, the in-place selection sync (`replace_selection!`)
# could not step past the non-Document tuple and diverged, re-pointing the pane's
# active-tab path on every within-tab caret move — a printer-locality dimension-A
# violation (see plan/pending/printer-locality.md). With a Document the in-place
# mutation reaches the leaf and leaves the routing ancestors untouched.
@document struct WidgetTabPage <: WidgetDocument
    selector::Any
    element::Any
    icon::Any = nothing
end

# `WidgetTabPage(selector, element)` and `(selector, element, icon)` are both Rule Y
# constructors: `icon` and `selection` are the trailing defaulted run.

# Wrap a caller's tab entry — a `(selector, element)` or `(selector, element, icon)`
# tuple, or an already-built `WidgetTabPage` — into a `WidgetTabPage`.
_as_tab_page(p::WidgetTabPage) = p
_as_tab_page(p::Tuple) = WidgetTabPage(p[1], p[2], length(p) >= 3 ? p[3] : nothing)

"""
    WidgetTabbedPane(selector_element_pairs; <base kwargs>)

A tabbed container.  `selector_element_pairs` is a `Vector` of
`(selector, element)` or `(selector, element, icon)` tuples (each wrapped in a
[`WidgetTabPage`](@ref)).
"""
@document struct WidgetTabbedPane <: WidgetDocument
    selector_element_pairs::CellVector = CellVector()
    visible::Bool = true
    margin::Inset = inset_default
    margin_color::StyleColor = nothing
    border::Inset = inset_default
    border_color::StyleColor = nothing
    padding::Inset = inset_default
    padding_color::StyleColor = nothing
    tab_scroll::Int = 0
end

# `tab_scroll` is transient view state (like `WidgetScrollPane.scroll_position`): a
# horizontal pixel offset (≥0) that scrolls the tab strip when it is wider than the
# pane, so overflow tabs stay reachable. 0 ⇒ no scroll.
function WidgetTabbedPane(selector_element_pairs::Vector;
                          visible::Bool=true,
                          margin::Inset=inset_default,
                          margin_color=nothing,
                          border::Inset=inset_default,
                          border_color=nothing,
                          padding::Inset=inset_default,
                          padding_color=nothing,
                          tab_scroll::Integer=0)
    WidgetTabbedPane(CellVector(Cell[Cell(_as_tab_page(p)) for p in selector_element_pairs]),
                     Cell(visible), Cell(margin), Cell(margin_color),
                     Cell(border), Cell(border_color),
                     Cell(padding), Cell(padding_color),
                     Cell(Int(tab_scroll)),
                     Cell(nothing))
end

# Wire the tabs reactively: `f()` returns the same shape the positional constructor
# takes — `(selector, element)` / `(selector, element, icon)` tuples or `WidgetTabPage`s
# — each wrapped via `_as_tab_page` (so it stays consistent with the eager ctor above,
# which the reader relies on: `selector_element_pairs[i]` is always a `WidgetTabPage`).
set_cell_function!(w::WidgetTabbedPane, f::Function) = (set_cell_function!(getfield(w.selector_element_pairs, :elements), () -> Cell[Cell(_as_tab_page(x)) for x in f()]); w)

# ── WidgetScrollPane ───────────────────────────────────────────────────────

"""
    WidgetScrollPane(content; content_fill_color, position, size,
                     scroll_position, follow_end, <base kwargs>)

A scrollable viewport. With `follow_end=true` the pane sticks to the *bottom* of
its content — newly appended content (e.g. streaming chat turns) stays in view
instead of scrolling below the fold — ignoring `scroll_position` on the vertical
axis.
"""
@document struct WidgetScrollPane <: WidgetDocument
    content::Any
    content_fill_color::StyleColor
    position::Point2D
    size::Point2D
    scroll_position::Point2D
    follow_end::Bool
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetScrollPane(content;
                          content_fill_color=nothing,
                          position=nothing,
                          size=nothing,
                          scroll_position::Point2D=Point2D(0, 0),
                          follow_end::Bool=false,
                          visible::Bool=true,
                          margin::Inset=inset_default,
                          margin_color=nothing,
                          border::Inset=inset_default,
                          border_color=nothing,
                          padding::Inset=inset_default,
                          padding_color=nothing)
    WidgetScrollPane(Cell(content), Cell(content_fill_color),
                     Cell(position), Cell(size), Cell(scroll_position),
                     Cell(follow_end),
                     Cell(visible), Cell(margin), Cell(margin_color),
                     Cell(border), Cell(border_color),
                     Cell(padding), Cell(padding_color),
                     Cell(nothing))
end

set_cell_function!(w::WidgetScrollPane, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

# ── WidgetTransformPane ──────────────────────────────────────────────────────

"""
    WidgetTransformPane(content; transform, content_fill_color, position, size,
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
    content_fill_color::StyleColor
    position::Point2D
    size::Point2D
    transform::AffineTransform
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetTransformPane(content;
                            transform::AffineTransform=affine_identity,
                            content_fill_color=nothing,
                            position=nothing,
                            size=nothing,
                            visible::Bool=true,
                            margin::Inset=inset_default,
                            margin_color=nothing,
                            border::Inset=inset_default,
                            border_color=nothing,
                            padding::Inset=inset_default,
                            padding_color=nothing)
    WidgetTransformPane(Cell(content), Cell(content_fill_color),
                        Cell(position), Cell(size), Cell(transform),
                        Cell(visible), Cell(margin), Cell(margin_color),
                        Cell(border), Cell(border_color),
                        Cell(padding), Cell(padding_color),
                        Cell(nothing))
end

set_cell_function!(w::WidgetTransformPane, f::Function) = (set_cell_function!(getfield(w, :content), f); w)

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
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
end

function WidgetScrollBar(orientation::Symbol;
                         value::Float64=0.0,
                         thumb_size::Float64=0.2,
                         position=nothing,
                         size=nothing,
                         visible::Bool=true,
                         margin::Inset=inset_default,
                         margin_color=nothing,
                         border::Inset=inset_default,
                         border_color=nothing,
                         padding::Inset=inset_default,
                         padding_color=nothing)
    WidgetScrollBar(Cell(orientation), Cell(value), Cell(thumb_size),
                    Cell(position), Cell(size),
                    Cell(visible), Cell(margin), Cell(margin_color),
                    Cell(border), Cell(border_color),
                    Cell(padding), Cell(padding_color),
                    Cell(nothing))
end

# ════════════════════════════════════════════════════════════════════════════
# Extension widgets (printer-only for now; readers are no-ops)
#
# These carry only the fields they need plus `visible` and `selection` — colors,
# radius and spacing all come from the WidgetTheme at render time, so they don't
# replicate the box-model fields of the older widgets.
# ════════════════════════════════════════════════════════════════════════════

# ── WidgetBadge ─────────────────────────────────────────────────────────────

"""
    WidgetBadge(position, content; variant=:default)

A small pill-shaped status label. `variant` ∈
`:default | :secondary | :destructive | :outline`.
"""
@document struct WidgetBadge <: WidgetDocument
    position::Point2D
    content::Any
    variant::Symbol
    visible::Bool
end
WidgetBadge(position::Point2D, content; variant::Symbol=:default, visible::Bool=true) =
    WidgetBadge(Cell(position), Cell(content), Cell(variant), Cell(visible), Cell(nothing))

# ── WidgetSeparator ─────────────────────────────────────────────────────────

"""
    WidgetSeparator(position; orientation=:horizontal, length=200)

A 1px divider rule.
"""
@document struct WidgetSeparator <: WidgetDocument
    position::Point2D
    orientation::Symbol
    length::Int
    visible::Bool
end
WidgetSeparator(position::Point2D; orientation::Symbol=:horizontal,
                length::Integer=200, visible::Bool=true) =
    WidgetSeparator(Cell(position), Cell(orientation), Cell(Int(length)), Cell(visible), Cell(nothing))

# ── WidgetCard ──────────────────────────────────────────────────────────────

"""
    WidgetCard(position; title, description, content, footer, width=320, collapsed=false)

A rounded, bordered surface with an optional title / description header, a
content body and an optional footer, stacked vertically.

`collapsed` is transient view state (like `WidgetScrollPane.scroll_position`): a
header click emits `ToggleCollapseOperation(card)`, whose default handler flips
this cell. Producers that want a collapsible card read `card.collapsed` from the
reactive `title`/`content` they build (chevron glyph, empty body when collapsed).
Cards left at the default `collapsed=false` render exactly as before.
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
end

"""
    WidgetCard(position; title, description, content, footer, width=320, height=0, ...)

`height = 0` (the default) is **content-tall**: the card wraps whatever its
content measures, and its content is laid out with no height allocation. A
positive `height` makes the card **fixed**: it is exactly that tall regardless of
its content, and the content is given the remaining interior height to fill.

Fixed height is what lets a scrolling body work — a `WidgetScrollPane` (or any
widget that wants an allocation to scroll within) needs a bounded height to
scroll *inside*; in the content-tall mode there is nothing to scroll against, so
tall content simply extends past the card.
"""
WidgetCard(position::Point2D; title=nothing, description=nothing, content=nothing,
           footer=nothing, width::Integer=320, height::Integer=0,
           visible::Bool=true, collapsed::Bool=false) =
    WidgetCard(Cell(position), Cell(title), Cell(description), Cell(content),
               Cell(footer), Cell(Int(width)), Cell(Int(height)),
               Cell(visible), Cell(collapsed), Cell(nothing))

# ── WidgetSwitch ────────────────────────────────────────────────────────────

"""
    WidgetSwitch(position, checked; duration=0)

An on/off toggle switch (rounded track + knob). When `duration` is greater than
zero the knob *slides* between the off and on positions over `duration`
milliseconds on each toggle; `duration = 0` (the default) snaps instantly. The
slide is armed by the switch's reader (see `WidgetSwitchToGraphicsCanvas`): a
toggle becomes a `CompoundOperation` that records `anim_from` (the knob fraction
at the moment of the toggle) and `anim_t0` (the editor time when it started),
then flips `checked`. `anim_from`/`anim_t0` are presentation state, not part of
the logical on/off value.
"""
@document struct WidgetSwitch <: WidgetDocument
    position::Point2D
    checked::Bool
    visible::Bool
    enabled::Bool
    duration::Int        # slide length in ms; 0 disables the animation
    anim_from::Float64   # knob fraction [0,1] when the current slide began
    anim_t0::Float64     # editor time (s) when the current slide began; NaN = idle
    gestures::Any        # per-instance gesture bindings (see get_instance_gesture_bindings)
end
WidgetSwitch(position::Point2D, checked::Bool=false; visible::Bool=true, enabled::Bool=true,
             duration::Integer=0, gestures=GestureBinding[]) =
    WidgetSwitch(Cell(position), Cell(checked), Cell(visible), Cell(enabled),
                 Cell(Int(duration)), Cell(0.0), Cell(NaN), Cell(gestures))
get_instance_gesture_bindings(w::WidgetSwitch) = w.gestures

# ── WidgetProgress ──────────────────────────────────────────────────────────

"""
    WidgetProgress(position, value; width=240)

A horizontal progress bar. `value` ∈ [0, 1].
"""
@document struct WidgetProgress <: WidgetDocument
    position::Point2D
    value::Float64
    width::Int
    visible::Bool
end
WidgetProgress(position::Point2D, value::Real=0.0; width::Integer=240, visible::Bool=true) =
    WidgetProgress(Cell(position), Cell(Float64(value)), Cell(Int(width)), Cell(visible), Cell(nothing))

# ── WidgetSlider ────────────────────────────────────────────────────────────

"""
    WidgetSlider(position, value; width=240)

A slider with a track, filled portion and a draggable knob. `value` ∈ [0, 1].
"""
@document struct WidgetSlider <: WidgetDocument
    position::Point2D
    value::Float64
    width::Int
    visible::Bool
    enabled::Bool
end
WidgetSlider(position::Point2D, value::Real=0.5; width::Integer=240, visible::Bool=true, enabled::Bool=true) =
    WidgetSlider(Cell(position), Cell(Float64(value)), Cell(Int(width)), Cell(visible), Cell(enabled), Cell(nothing))

# ── WidgetRadioGroup ────────────────────────────────────────────────────────

"""
    WidgetRadioGroup(position, options; selected=1)

A vertical group of radio options (`options` is a `Vector` of labels);
`selected` is the 1-based selected index.
"""
@document struct WidgetRadioGroup <: WidgetDocument
    position::Point2D
    options::CellVector
    selected::Int
    visible::Bool
    enabled::Bool
end
WidgetRadioGroup(position::Point2D, options::Vector; selected::Integer=1, visible::Bool=true, enabled::Bool=true) =
    WidgetRadioGroup(Cell(position), CellVector(Cell[Cell(o) for o in options]),
                     Cell(Int(selected)), Cell(visible), Cell(enabled), Cell(nothing))

# ── WidgetAvatar ────────────────────────────────────────────────────────────

"""
    WidgetAvatar(position, initials; size=64)

A circular avatar showing initials (image-clipping is future work).
"""
@document struct WidgetAvatar <: WidgetDocument
    position::Point2D
    initials::Any
    size::Int
    visible::Bool
end
WidgetAvatar(position::Point2D, initials; size::Integer=64, visible::Bool=true) =
    WidgetAvatar(Cell(position), Cell(initials), Cell(Int(size)), Cell(visible), Cell(nothing))

# ── WidgetAlert ─────────────────────────────────────────────────────────────

"""
    WidgetAlert(position, title, description; variant=:default, width=360)

A rounded, bordered callout with a bold title and muted description.
`variant` ∈ `:default | :destructive`.
"""
@document struct WidgetAlert <: WidgetDocument
    position::Point2D
    title::Any
    description::Any
    variant::Symbol
    width::Int
    visible::Bool
end
WidgetAlert(position::Point2D, title, description=nothing;
            variant::Symbol=:default, width::Integer=360, visible::Bool=true) =
    WidgetAlert(Cell(position), Cell(title), Cell(description), Cell(variant),
                Cell(Int(width)), Cell(visible), Cell(nothing))

# ── WidgetSkeleton ──────────────────────────────────────────────────────────

"""
    WidgetSkeleton(position; width=240, height=20)

A muted rounded placeholder block for loading states.
"""
@document struct WidgetSkeleton <: WidgetDocument
    position::Point2D
    width::Int
    height::Int
    visible::Bool
end
WidgetSkeleton(position::Point2D; width::Integer=240, height::Integer=20, visible::Bool=true) =
    WidgetSkeleton(Cell(position), Cell(Int(width)), Cell(Int(height)), Cell(visible), Cell(nothing))

# ── WidgetToggle ────────────────────────────────────────────────────────────

"""
    WidgetToggle(position, content; pressed=false)

A two-state toggle button (pressed = accent surface).
"""
@document struct WidgetToggle <: WidgetDocument
    position::Point2D
    content::Any
    pressed::Bool
    visible::Bool
    enabled::Bool
end
WidgetToggle(position::Point2D, content; pressed::Bool=false, visible::Bool=true, enabled::Bool=true) =
    WidgetToggle(Cell(position), Cell(content), Cell(pressed), Cell(visible), Cell(enabled), Cell(nothing))

# ── WidgetToggleGroup ───────────────────────────────────────────────────────

"""
    WidgetToggleGroup(position, options; selected=1)

A segmented control: a row of options with one selected segment.
"""
@document struct WidgetToggleGroup <: WidgetDocument
    position::Point2D
    options::CellVector
    selected::Int
    visible::Bool
    enabled::Bool
end
WidgetToggleGroup(position::Point2D, options::Vector; selected::Integer=1, visible::Bool=true, enabled::Bool=true) =
    WidgetToggleGroup(Cell(position), CellVector(Cell[Cell(o) for o in options]),
                      Cell(Int(selected)), Cell(visible), Cell(enabled), Cell(nothing))

# ── WidgetSelect ────────────────────────────────────────────────────────────

"""
    WidgetSelect(position, value; options=[], width=220)

A select / combobox: an input-like box showing `value` with a trailing chevron.
`options` lists the selectable values; clicking the box opens a dropdown of those
options as a floating popup window (see `WidgetSelectToGraphicsCanvas`'s reader and
[`WidgetOption`]). Picking an option writes it back to `value` and dismisses the
popup. With no options the box is inert (renders the closed state only).
"""
@document struct WidgetSelect <: WidgetDocument
    position::Point2D
    value::Any
    options::CellVector
    width::Int
    visible::Bool
    enabled::Bool
end
WidgetSelect(position::Point2D, value; options::Vector=Any[], width::Integer=220,
             visible::Bool=true, enabled::Bool=true) =
    WidgetSelect(Cell(position), Cell(value),
                 CellVector(Cell[o isa Cell ? o : Cell(o) for o in options]),
                 Cell(Int(width)), Cell(visible), Cell(enabled), Cell(nothing))

# ── WidgetOption ──────────────────────────────────────────────────────────────

"""
    WidgetOption(position, select, value; label=string(value), popup_id=:widget_popup, width=220)

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
end
WidgetOption(position::Point2D, select, value; label=string(value),
             popup_id::Symbol=:widget_popup, width::Integer=220, visible::Bool=true) =
    WidgetOption(Cell(position), Cell(select), Cell(value), Cell(label),
                 Cell(popup_id), Cell(Int(width)), Cell(visible), Cell(nothing))

# ── WidgetTextarea ──────────────────────────────────────────────────────────

"""
    WidgetTextarea(position, content; width=320, rows=4)

A multi-line text surface. `content` is a string (newlines split into rows).
"""
@document struct WidgetTextarea <: WidgetDocument
    position::Point2D
    content::Any
    width::Int
    rows::Int
    visible::Bool
    enabled::Bool
end
WidgetTextarea(position::Point2D, content; width::Integer=320, rows::Integer=4, visible::Bool=true, enabled::Bool=true) =
    WidgetTextarea(Cell(position), Cell(content), Cell(Int(width)), Cell(Int(rows)),
                   Cell(visible), Cell(enabled), Cell(nothing))

# ── WidgetAccordion ─────────────────────────────────────────────────────────

# A single accordion item: a `title` and a `body`. A first-class Document rather
# than a raw `(title, body)` tuple, so the selection chain descends
# Document→Document and an in-place caret move in a title/body leaves the
# accordion's routing untouched (printer-locality dimension A; the WidgetTabPage
# fix applied to the accordion).
@document struct WidgetAccordionItem <: WidgetDocument
    title::Any
    body::Any
end

_as_accordion_item(it::WidgetAccordionItem) = it
_as_accordion_item(it::Tuple) = WidgetAccordionItem(it[1], it[2])

"""
    WidgetAccordion(position, items; expanded=1, width=360)

A vertical accordion. `items` is a `Vector` of `(title, body)` tuples (each wrapped
in a [`WidgetAccordionItem`](@ref)); `expanded` is the 1-based index of the open
item (0 = all collapsed).
"""
@document struct WidgetAccordion <: WidgetDocument
    position::Point2D
    items::CellVector
    expanded::Int
    width::Int
    visible::Bool
end
WidgetAccordion(position::Point2D, items::Vector; expanded::Integer=1, width::Integer=360, visible::Bool=true) =
    WidgetAccordion(Cell(position), CellVector(Cell[Cell(_as_accordion_item(it)) for it in items]),
                    Cell(Int(expanded)), Cell(Int(width)), Cell(visible), Cell(nothing))

# ── WidgetTable ─────────────────────────────────────────────────────────────

"""
    WidgetTable(position, column_headers, row_headers, rows, column_count; ...)
    WidgetTable(position, headers::Vector, rows::Vector)   # string convenience shim

The single table abstraction. A grid of **document cells** (each cell is a
`Document`, recursed through the shared recursion — so a cell can be a
`JsonString`, an `XmlElement`, text, even a nested `WidgetTable`) decorated with
borders / hairline rules, optional header strips, and selection bands. Its
renderer ([`WidgetTableToGraphicsCanvas`](@ref)) delegates *all positioning* to
a `GridLayout` and overlays decorations from the grid geometry it reads off the
layout iomap ("layout is just layout").

# Fields

- `position::Point2D` — top-left origin.
- `column_headers::CellVector` — optional top strip; each entry a `Document` (or
  `nothing`). Empty vector ⇒ no column-header strip.
- `row_headers::CellVector` — optional left strip; each entry a `Document` (or
  `nothing`). Empty vector ⇒ no row-header strip.
- `rows::CellVector` — the body; each entry is a `CellVector` of `Document` cells
  (row-major). Field names `rows` / `column_headers` / `row_headers` are the
  public reference vocabulary for selection.
- `column_count::Int` — number of columns.
- `padding::Int` — inner padding (px) between a cell's border and its content.
- `border_width::Int` — hairline rule / border width (px).
- `visible::Bool` — standard Document field; `selection` is macro-injected.

The string convenience constructor wraps each string in a `WidgetLabel` so
existing call sites (`WidgetTable(pos, headers, rows)`) keep working unchanged.
"""
@document struct WidgetTable <: WidgetDocument
    position::Point2D
    column_headers::CellVector   # of Document (or nothing) — optional top strip
    row_headers::CellVector      # of Document (or nothing) — optional left strip
    rows::CellVector             # each row is a CellVector of Document cells
    column_count::Int
    padding::Int
    border_width::Int
    visible::Bool
    hovered::Union{Nothing, Reference}   # transient: whole-row (or column-header) ref under the pointer, or nothing
end

"""
    widget_table_row_selection(i) -> Reference
    widget_table_selected_row(table) -> Int

The canonical whole-row selection for a [`WidgetTable`](@ref) (`rows[i-1:i]`,
1-based; `0`/`nothing` = none) and its inverse — the pair a row-selecting reader
emits and an enclosing projection maps across domains. Row selection is what the
table's reader produces for a click on the ROW-HEADER strip, so a table that
wants it must be built with `row_headers`.
"""
widget_table_row_selection(i::Integer) = _widget_element_selection("rows", i)
widget_table_selected_row(w::WidgetTable) = _widget_element_selected(w.selection, "rows")

# Wrap a raw cell value in a renderable widget document; pass Documents through.
_table_cell_doc(v::Document) = v
_table_cell_doc(::Nothing)   = nothing
_table_cell_doc(v)           = WidgetLabel(Point2D(0, 0), string(v))

# Wrap one body row (a Vector of values or Documents) into a CellVector of cells.
_table_row(r) = CellVector(Cell[Cell(_table_cell_doc(c)) for c in r])

"""
    WidgetTable(position, column_headers, row_headers, rows, column_count; padding=8, border_width=1, visible=true)

Document-cell constructor. `column_headers` / `row_headers` are `Vector`s of
`Document`/`nothing` (pass `[]` for none); `rows` is a `Vector` of rows, each a
`Vector` of `Document`/value cells.
"""
function WidgetTable(position::Point2D, column_headers::Vector, row_headers::Vector,
                     rows::Vector, column_count::Integer;
                     padding::Integer=8, border_width::Integer=1, visible::Bool=true)
    WidgetTable(Cell(position),
                CellVector(Cell[Cell(_table_cell_doc(h)) for h in column_headers]),
                CellVector(Cell[Cell(_table_cell_doc(h)) for h in row_headers]),
                CellVector(Cell[Cell(_table_row(r)) for r in rows]),
                Cell(Int(column_count)), Cell(Int(padding)), Cell(Int(border_width)),
                Cell(visible), Cell(nothing))
end

# String convenience shim: headers become a column-header strip, rows become the
# body, columns inferred from the header count (or the widest row). Strings are
# wrapped in WidgetLabels via `_table_cell_doc`.
function WidgetTable(position::Point2D, headers::Vector, rows::Vector;
                     padding::Integer=8, border_width::Integer=1, visible::Bool=true)
    column_count = isempty(headers) ?
        (isempty(rows) ? 0 : maximum(length(r) for r in rows)) : length(headers)
    WidgetTable(position, collect(Any, headers), Any[], collect(Any, rows), column_count;
                padding=padding, border_width=border_width, visible=visible)
end

# ── WidgetTree ──────────────────────────────────────────────────────────────

"""
    WidgetTreeNode(icon, label, children = [])

A single node of a [`WidgetTree`](@ref) carrying a dedicated **icon** slot
distinct from its text **label** (the decoration model used by typical widget
libraries — Swing `JTree` renderers, Qt's `QTreeView` decoration role). `icon`
is `Any`: a glyph `String` today, an image document later. `children` is a
`Vector` of child nodes (each a `WidgetTreeNode`, a leaf `String`, or a
bare `(label, children)` tuple); an empty vector marks a leaf.
"""
struct WidgetTreeNode
    icon::Any
    label::Any
    children::Vector
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
    WidgetTree(position, roots)

A tree / outline view. `roots` is a `Vector` of nodes. A node is a
[`WidgetTreeNode`](@ref) (icon + label + children), or — for icon-less trees —
a leaf label (`String`) or a `(label, children::Vector)` tuple. Parent nodes get
an expand chevron; an icon (when present) is drawn in its own column before the
label; children are indented. (A widget-styled counterpart to the file-system /
navigator trees.)

`hovered` and `collapsed` are **transient UI state** (like [`WidgetButton`](@ref)'s
`hovered`): `hovered` holds the node-path reference of the row under the pointer
(or `nothing`), written by the reader from `MouseEnter`/`MouseMove`/`MouseLeave`
crossings; `collapsed` is the set of node paths (1-based index chains) whose
children are currently hidden, toggled by clicking a parent's chevron. Neither is
part of the tree's content.
"""
@document struct WidgetTree <: WidgetDocument
    position::Point2D
    roots::CellVector
    visible::Bool
    hovered::Union{Nothing, Reference}           # transient: node-path ref of the row under the pointer, or nothing
    collapsed::Set{Vector{Int}}  # transient: node paths whose children are hidden
    gestures::Any                # per-instance tree-level gesture bindings
end
WidgetTree(position::Point2D, roots::Vector; visible::Bool=true, gestures=GestureBinding[]) =
    WidgetTree(Cell(position), CellVector(Cell[Cell(n) for n in roots]), Cell(visible),
               Cell(nothing), Cell(Set{Vector{Int}}()), Cell(gestures))

# Tree-level gestures (over the whole tree); per-node gestures live on each
# `WidgetTreeNode`. See `get_instance_gesture_bindings` / `read_bound_gesture`.
get_instance_gesture_bindings(w::WidgetTree) = w.gestures

# ── Operations ─────────────────────────────────────────────────────────────

# HideWidgetOperation / ShowWidgetOperation / ScrollWidgetOperation /
# SetScrollBarValueOperation were folded into ReplaceReferencedValueOperation — a carried
# widget + a single-field write (`visible` / `scroll_position` / `value`). The
# producing readers (ProjectionConfiguring, WidgetScrollPane/ScrollBar readers in
# WidgetToGraphics) now emit `ReplaceReferencedValueOperation(widget, "field", value)` and
# do the clamp/old+delta arithmetic themselves. See
# plan/done/consolidate-operations-replace.md (step 2).

"""
    SelectTabOperation(widget, tab_index)

Signals that tab `tab_index` (1-based) of `widget` was clicked.
Carries the widget identity so the workbench layer can disambiguate
between multiple tab panes on screen.
"""
struct SelectTabOperation <: Operation
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
conserved) and each stays within its slot's min/max.
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

# ── Action (Stage 4) ────────────────────────────────────────────────────────

"""
    Action(label; icon=nothing, enabled=true, shortcut=nothing, callback=nothing)

A shared command object (Qt's `QAction`): a menu item, a toolbar button, and a
keyboard shortcut can all reference the same `Action`, so its `label`/`enabled`
drive every presenter and toggling `enabled` disables all of them at once.
`shortcut` is a `KeyDownPattern` (build one with [`Shortcut`]); `callback` runs on
invocation (called with the editor when it accepts one argument, else with none).
`icon` is a slot populated by Stage 5. Invoked via [`InvokeActionOperation`].
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
    # `callback` is a callable, not reactive content — store it as a primitive cell
    # value (a computed `Cell(f)` would invoke it on read). Mirrors WidgetButton.
    callback_cell = Cell(nothing); set_cell_value!(callback_cell, callback)
    Action(Cell(label), Cell(icon), Cell(enabled), Cell(shortcut), callback_cell)
end

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
    KeyDownPattern(key, mods, nothing)
end

# True when `evt` fires `action`'s shortcut and the action is enabled. Reuses the
# gesture-layer `matches_event_pattern` (exact-modifier `KeyDownPattern` matching).
action_shortcut_matches(action::Action, evt) =
    action.shortcut !== nothing && !(action.enabled === false) && matches_event_pattern(action.shortcut, evt)

"""
    InvokeWidgetActionOperation(widget)

Invoke `widget`'s `action` callable (e.g. a `WidgetButton` click). The action is
called with the editor when it accepts one argument, otherwise with none, so it
can mutate `editor.document` or projection state. A `nothing` action is a no-op.
"""
struct InvokeWidgetActionOperation <: Operation
    widget::WidgetDocument
end

"""
    InvokeActionOperation(action)

Invoke an [`Action`]'s `callback` — the command shared by a menu item, a toolbar
button, and a keyboard shortcut. Called with the editor when it accepts one
argument, else with none. A disabled action, or a `nothing` callback, is a no-op.
"""
struct InvokeActionOperation <: Operation
    action::Action
end

# SetWidgetHoverOperation / SetWidgetPressedOperation were folded into
# ReplaceReferencedValueOperation: the WidgetButton reader emits
# `ReplaceReferencedValueOperation(widget, "hovered"/"pressed", bool)`. See
# plan/done/consolidate-operations-replace.md (step 2).

# ── Operation evaluation ───────────────────────────────────────────────────

"""
    evaluate_operation(op)

Apply a widget operation.
"""
function evaluate_operation(editor, op::SelectTabOperation)
    op.widget.selection = ConcreteReference(ElementReferenceStep(op.tab_index), EmptyReference())
end

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
    sizes[k]     = op.new_size_a
    sizes[k + 1] = op.new_size_b
    # Pin both dragged slots so the constrained layout honours their new size
    # exactly instead of redistributing it by weight.
    pinned = split.pinned
    if length(pinned) >= k + 1
        pinned[k]     = true
        pinned[k + 1] = true
    end
end

function evaluate_operation(editor, op::EndSplitterDragOperation)
    op.split.active_splitter = 0
    op.split.drag_anchor = nothing
end

function evaluate_operation(editor, op::InvokeWidgetActionOperation)
    action = op.widget.action
    action === nothing && return
    # Prefer an editor-taking action so it can reach the document/projection;
    # fall back to a 0-arg callable.
    if applicable(action, editor)
        action(editor)
    elseif applicable(action)
        action()
    end
end

function evaluate_operation(editor, op::InvokeActionOperation)
    action = op.action
    action.enabled === false && return        # a disabled action is inert
    callback = action.callback
    callback === nothing && return
    if applicable(callback, editor)
        callback(editor)
    elseif applicable(callback)
        callback()
    end
end

# ── Focus traversal (Stage 2): finding focusable leaves ─────────────────────
#
# Focus is selection. These pure helpers locate the *first* / *last* focusable
# leaf in a subtree as a relative whole-element (∅) path, mirroring the generic
# field/element descent the selection machinery uses so the produced path matches
# the projection readers' re-rooting (`elements[i]` / `children[i]`, with
# `RangeReferenceStep(i-1, i)` for the i-th element). They live in this document-layer
# module so both `WidgetToGraphics` and the earlier-included `LayoutToGraphics`
# can share them for Tab traversal. See plan/pending/widget-focus-traversal.md.

export first_focusable_path, last_focusable_path

# The interactive widget types that are Tab stops — exactly the Stage-1
# `enabled`-bearing leaves. A disabled instance is *not* a stop.
const FocusableWidget = Union{WidgetButton, WidgetCheckbox, WidgetText,
    WidgetTextarea, WidgetSelect, WidgetSwitch, WidgetSlider, WidgetToggle,
    WidgetToggleGroup, WidgetRadioGroup, WidgetMenuItem}

# True when `w` is an enabled interactive leaf (every FocusableWidget carries the
# `enabled` cell, so the read is safe).
_is_focusable_widget(w) = w isa FocusableWidget && !(getfield(w, :enabled)[] === false)

# `(steps::Tuple, child)` pairs for each child Document of `node`, in document
# order — a CellVector field yields one pair per element (`field[i]`), a single
# sub-document field yields one pair (`field`). `selection` and scalar/leaf fields
# are skipped.
function _child_document_refs(node)
    refs = Tuple{Tuple,Any}[]
    if node isa CellVector
        for i in 1:length(node)
            push!(refs, ((RangeReferenceStep(i - 1, i),), node[i]))
        end
        return refs
    end
    T = typeof(node)
    isstructtype(T) || return refs
    for fname in fieldnames(T)
        fname === :selection && continue
        fv = getfield(node, fname)
        v = fv isa Cell ? fv[] : fv
        v === nothing && continue
        if v isa CellVector
            for i in 1:length(v)
                push!(refs, ((FieldReferenceStep(string(fname)), RangeReferenceStep(i - 1, i)), v[i]))
            end
        elseif v isa Document
            push!(refs, ((FieldReferenceStep(string(fname)),), v))
        end
    end
    refs
end

# Prepend `steps` (outermost-first tuple) onto `path`.
function _prepend_steps(steps::Tuple, path::Reference)
    for s in Base.reverse(steps)
        path = ConcreteReference(s, path)
    end
    path
end

# Relative ∅-path to the first (last, when `reverse`) enabled interactive leaf in
# `node`'s subtree, or `nothing` if it holds no focusable widget. `visited` guards
# against cycles in the document graph: an embedded `ListNode` is a doubly-linked
# list (`prev`/`next` both point at Documents), so a naive walk recurses
# `next → prev → next …` forever (this is what made Tab stack-overflow on the
# workbench/assistant, which embed ListNode-backed text/syntax). Acyclic trees (the
# widget examples) visit each node once regardless, so their focus order is unchanged.
function _focusable_path(node, reverse::Bool, visited::Set{UInt}=Set{UInt}())
    node === nothing && return nothing
    _is_focusable_widget(node) && return EmptyReference()
    id = objectid(node)
    id in visited && return nothing
    push!(visited, id)
    refs = _child_document_refs(node)
    for (steps, child) in (reverse ? Base.reverse(refs) : refs)
        sub = _focusable_path(child, reverse, visited)
        sub === nothing || return _prepend_steps(steps, sub)
    end
    nothing
end

"""
    first_focusable_path(node) -> Reference
    last_focusable_path(node)  -> Reference

The relative whole-element (∅) selection path to the first / last enabled
interactive widget in `node`'s subtree, or `nothing` if there is none. Disabled
widgets (Stage 1) are skipped.
"""
first_focusable_path(node) = _focusable_path(node, false)
last_focusable_path(node)  = _focusable_path(node, true)

# The next slot after `after` (in `reverse` direction) among `children` whose
# subtree contains a focusable widget; 0 if there is none. `children` is any
# 1-indexed collection of child documents (a CellVector or Vector).
function _next_focusable_in(children, after::Int, reverse::Bool)
    n = length(children)
    if reverse
        for j in (after - 1):-1:1
            _focusable_path(children[j], true) === nothing || return j
        end
    else
        for j in (after + 1):n
            _focusable_path(children[j], false) === nothing || return j
        end
    end
    0
end

end # module
