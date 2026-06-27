"""
    WidgetModule

The widget document domain. Widgets are UI-layer documents that sit above
the graphics domain and below application-specific projections. Each widget
type subtypes the abstract WidgetDocument base (itself a Document) and
carries reactive Cell fields for all mutable properties.
"""
module WidgetModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..OperationApiModule: Operation, evaluate_operation
import ..ColorModule: StyleColor
import ..ReferenceModule: Reference, ReferencePath, ConcreteReferencePath, ElementReference,
                          EmptyReferencePath, FieldReference, RangeReference
import ..GeometryModule: Inset, Point2D, inset_default,
                        inset_size, inset_width, inset_height,
                        inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right
export Inset, Point2D,
       WidgetDocument, WidgetInsertion,
       WidgetLabel, WidgetText, WidgetCheckbox, WidgetButton,
       WidgetTooltip, WidgetMenu, WidgetMenuItem, WidgetComposite,
       WidgetShell, WidgetTitlePane, WidgetSplitPane, WidgetTabbedPane,
       WidgetScrollPane, WidgetToolbar, WidgetScrollBar,
       WidgetBadge, WidgetSeparator, WidgetCard, WidgetSwitch, WidgetProgress,
       WidgetSlider, WidgetRadioGroup, WidgetAvatar, WidgetAlert, WidgetSkeleton,
       WidgetToggle, WidgetToggleGroup, WidgetSelect, WidgetOption, WidgetTextarea, WidgetAccordion,
       WidgetTable, WidgetTree, WidgetTreeNode,
       SelectTabOperation,
       StartSplitterDragOperation, ResizeSplitPaneOperation, EndSplitterDragOperation,
       InvokeWidgetActionOperation,
       evaluate_operation,
       inset_default, inset_size, inset_width, inset_height,
       inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right,
       setfn!,
       IWidgetInsertion,
       IWidgetLabel, IWidgetText, IWidgetCheckbox, IWidgetButton,
       IWidgetTooltip, IWidgetMenu, IWidgetMenuItem, IWidgetComposite,
       IWidgetShell, IWidgetTitlePane, IWidgetSplitPane, IWidgetTabbedPane,
       IWidgetScrollPane, IWidgetToolbar, IWidgetScrollBar,
       IWidgetBadge, IWidgetSeparator, IWidgetCard, IWidgetSwitch, IWidgetProgress,
       IWidgetSlider, IWidgetRadioGroup, IWidgetAvatar, IWidgetAlert, IWidgetSkeleton,
       IWidgetToggle, IWidgetToggleGroup, IWidgetSelect, IWidgetOption, IWidgetTextarea, IWidgetAccordion,
       IWidgetTable, IWidgetTree

# ── WidgetDocument (abstract base) ─────────────────────────────────────────────────

"""
    WidgetDocument

Abstract base type for all widget documents.  Subtypes the `Document`
contract.  Every
concrete widget carries the seven base fields (`visible`, `margin`,
`margin_color`, `border`, `border_color`, `padding`, `padding_color`)
plus its own positional / content fields and a `selection::Reference`.
"""
abstract type WidgetDocument <: Document end

# ── WidgetInsertion ─────────────────────────────────────────────────────

@document struct WidgetInsertion <: WidgetDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── WidgetLabel ────────────────────────────────────────────────────────────

"""
    WidgetLabel(position, content; <base kwargs>)

A positioned, non-interactive label..
"""
@document struct WidgetLabel <: WidgetDocument
    position::Point2D
    content::Any
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
end

function WidgetLabel(position::Point2D, content;
                     visible::Bool=true,
                     margin::Inset=inset_default,
                     margin_color=nothing,
                     border::Inset=inset_default,
                     border_color=nothing,
                     padding::Inset=inset_default,
                     padding_color=nothing)
    WidgetLabel(Cell(position), Cell(content),
                Cell(visible), Cell(margin), Cell(margin_color),
                Cell(border), Cell(border_color),
                Cell(padding), Cell(padding_color),
                Cell(nothing))
end

setfn!(w::WidgetLabel, f::Function) = (setfn!(getfield(w, :content), f); w)

# ── WidgetText ─────────────────────────────────────────────────────────────

"""
    WidgetText(position, content; content_fill_color, <base kwargs>)

An editable text widget..
"""
@document struct WidgetText <: WidgetDocument
    position::Point2D
    content::Any
    content_fill_color::StyleColor
    visible::Bool
    enabled::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
end

function WidgetText(position::Point2D, content;
                    content_fill_color=nothing,
                    visible::Bool=true,
                    enabled::Bool=true,
                    margin::Inset=inset_default,
                    margin_color=nothing,
                    border::Inset=inset_default,
                    border_color=nothing,
                    padding::Inset=inset_default,
                    padding_color=nothing)
    WidgetText(Cell(position), Cell(content), Cell(content_fill_color),
               Cell(visible), Cell(enabled), Cell(margin), Cell(margin_color),
               Cell(border), Cell(border_color),
               Cell(padding), Cell(padding_color),
               Cell(nothing))
end

setfn!(w::WidgetText, f::Function) = (setfn!(getfield(w, :content), f); w)

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
    selection::Reference
end

function WidgetCheckbox(position::Point2D, content;
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
                   Cell(nothing))
end

setfn!(w::WidgetCheckbox, f::Function) = (setfn!(getfield(w, :content), f); w)

# ── WidgetButton ───────────────────────────────────────────────────────────

"""
    WidgetButton(position, size, content; action, <base kwargs>)

A clickable button.

`action` is an optional callable invoked when the button is clicked (via
`InvokeWidgetActionOperation`). It is called with the editor when it accepts one
argument, otherwise with none, so it can mutate `editor.document` / projection
state. A `nothing` action makes the button inert on click.

`enabled` (default `true`) is a shared interactivity flag alongside `visible`:
when `false` the button renders muted, ignores hover/press, and its reader
refuses to invoke the action.

`hovered` and `pressed` are **transient UI state** holding the pointer
interaction: `hovered` is `true` while the pointer is inside the button,
`pressed` is `true` while the left button is held down on it. The printer reads
them to pick the surface fill, so changing them re-renders only this button.
They are written by the `WidgetButton` reader (a `ReplaceReferencedValue` into the
`hovered` / `pressed` cell) and are not part of the document's content — they
are not meant to be serialised.
"""
@document struct WidgetButton <: WidgetDocument
    position::Point2D
    size::Point2D
    content::Any
    action::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
    hovered::Bool
    pressed::Bool
end

function WidgetButton(position::Point2D, size::Point2D, content;
                      action=nothing,
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
    action_cell = Cell(nothing); setval!(action_cell, action)
    WidgetButton(Cell(position), Cell(size), Cell(content), action_cell,
                 Cell(visible), Cell(enabled), Cell(margin), Cell(margin_color),
                 Cell(border), Cell(border_color),
                 Cell(padding), Cell(padding_color),
                 Cell(nothing), Cell(false), Cell(false))
end

setfn!(w::WidgetButton, f::Function) = (setfn!(getfield(w, :content), f); w)

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
    selection::Reference
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

setfn!(w::WidgetTooltip, f::Function) = (setfn!(getfield(w, :content), f); w)

# ── WidgetMenu ─────────────────────────────────────────────────────────────

"""
    WidgetMenu(elements; <base kwargs>)

A menu containing a sequence of `WidgetMenuItem`s..
"""
@document struct WidgetMenu <: WidgetDocument
    elements::CellVector
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
end

function WidgetMenu(elements::Vector;
                    visible::Bool=true,
                    margin::Inset=inset_default,
                    margin_color=nothing,
                    border::Inset=inset_default,
                    border_color=nothing,
                    padding::Inset=inset_default,
                    padding_color=nothing)
    WidgetMenu(CellVector(Cell[Cell(x) for x in elements]),
               Cell(visible), Cell(margin), Cell(margin_color),
               Cell(border), Cell(border_color),
               Cell(padding), Cell(padding_color),
               Cell(nothing))
end

WidgetMenu(; kwargs...) = WidgetMenu(Any[]; kwargs...)

setfn!(w::WidgetMenu, f::Function) = (setfn!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetMenuItem ─────────────────────────────────────────────────────────

"""
    WidgetMenuItem(content; action=nothing, submenu=nothing, <base kwargs>)

A single item inside a `WidgetMenu`. `action` is an optional callback (same
contract as `WidgetButton.action`: called with the editor when it accepts one
argument, else with none) invoked via `InvokeWidgetActionOperation` on a left
click. `submenu` is an optional `WidgetMenu` opened as a popup just below the item
on a left click; an item with a submenu opens it **instead of** running its
action, so the one item type serves a menu-bar entry, a nested submenu, and a leaf
command. A click on an enabled leaf item also closes the enclosing popup (a no-op
when the menu is rendered inline). A disabled item is inert.
"""
@document struct WidgetMenuItem <: WidgetDocument
    content::Any
    action::Any
    submenu::Any
    visible::Bool
    enabled::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
end

function WidgetMenuItem(content;
                        action=nothing,
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
    action_cell = Cell(nothing); setval!(action_cell, action)
    WidgetMenuItem(Cell(content), action_cell, Cell(submenu),
                   Cell(visible), Cell(enabled), Cell(margin), Cell(margin_color),
                   Cell(border), Cell(border_color),
                   Cell(padding), Cell(padding_color),
                   Cell(nothing))
end

setfn!(w::WidgetMenuItem, f::Function) = (setfn!(getfield(w, :content), f); w)

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
    selection::Reference
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

setfn!(w::WidgetComposite, f::Function) = (setfn!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetToolbar ──────────────────────────────────────────────────────────

"""
    WidgetToolbar(elements; <base kwargs>)

A horizontal strip of tool items (buttons, labels, separators) placed
below the menu bar in a `WidgetShell`.
"""
@document struct WidgetToolbar <: WidgetDocument
    elements::CellVector
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
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

WidgetToolbar(; kwargs...) = WidgetToolbar(Any[]; kwargs...)

setfn!(w::WidgetToolbar, f::Function) =
    (setfn!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

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
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
end

function WidgetShell(content;
                     content_fill_color=nothing,
                     size=nothing,
                     tooltip=nothing,
                     menu_bar=nothing,
                     toolbar=nothing,
                     context_menu=nothing,
                     visible::Bool=true,
                     margin::Inset=inset_default,
                     margin_color=nothing,
                     border::Inset=inset_default,
                     border_color=nothing,
                     padding::Inset=inset_default,
                     padding_color=nothing)
    WidgetShell(Cell(content), Cell(content_fill_color), Cell(size),
                Cell(tooltip), Cell(menu_bar), Cell(toolbar), Cell(context_menu),
                Cell(visible), Cell(margin), Cell(margin_color),
                Cell(border), Cell(border_color),
                Cell(padding), Cell(padding_color),
                Cell(nothing))
end

setfn!(w::WidgetShell, f::Function) = (setfn!(getfield(w, :content), f); w)

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
    selection::Reference
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

setfn!(w::WidgetTitlePane, f::Function) = (setfn!(getfield(w, :content), f); w)

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
    selection::Reference
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
                    Cell(nothing), Cell(0), Cell(nothing), CellVector())
end

WidgetSplitPane(elements::Vector; kwargs...) =
    WidgetSplitPane(:horizontal, elements; kwargs...)

setfn!(w::WidgetSplitPane, f::Function) = (setfn!(getfield(w.elements, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetTabbedPane ───────────────────────────────────────────────────────

"""
    WidgetTabbedPane(selector_element_pairs; <base kwargs>)

A tabbed container.  `selector_element_pairs` is a `Vector` of
`(selector, element)` tuples..
"""
@document struct WidgetTabbedPane <: WidgetDocument
    selector_element_pairs::CellVector
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
end

function WidgetTabbedPane(selector_element_pairs::Vector;
                          visible::Bool=true,
                          margin::Inset=inset_default,
                          margin_color=nothing,
                          border::Inset=inset_default,
                          border_color=nothing,
                          padding::Inset=inset_default,
                          padding_color=nothing)
    WidgetTabbedPane(CellVector(Cell[Cell(p) for p in selector_element_pairs]),
                     Cell(visible), Cell(margin), Cell(margin_color),
                     Cell(border), Cell(border_color),
                     Cell(padding), Cell(padding_color),
                     Cell(nothing))
end

WidgetTabbedPane(; kwargs...) = WidgetTabbedPane(Any[]; kwargs...)

setfn!(w::WidgetTabbedPane, f::Function) = (setfn!(getfield(w.selector_element_pairs, :elements), () -> Cell[Cell(x) for x in f()]); w)

# ── WidgetScrollPane ───────────────────────────────────────────────────────

"""
    WidgetScrollPane(content; content_fill_color, position, size,
                     scroll_position, <base kwargs>)

A scrollable viewport..
"""
@document struct WidgetScrollPane <: WidgetDocument
    content::Any
    content_fill_color::StyleColor
    position::Point2D
    size::Point2D
    scroll_position::Point2D
    visible::Bool
    margin::Inset
    margin_color::StyleColor
    border::Inset
    border_color::StyleColor
    padding::Inset
    padding_color::StyleColor
    selection::Reference
end

function WidgetScrollPane(content;
                          content_fill_color=nothing,
                          position=nothing,
                          size=nothing,
                          scroll_position::Point2D=Point2D(0, 0),
                          visible::Bool=true,
                          margin::Inset=inset_default,
                          margin_color=nothing,
                          border::Inset=inset_default,
                          border_color=nothing,
                          padding::Inset=inset_default,
                          padding_color=nothing)
    WidgetScrollPane(Cell(content), Cell(content_fill_color),
                     Cell(position), Cell(size), Cell(scroll_position),
                     Cell(visible), Cell(margin), Cell(margin_color),
                     Cell(border), Cell(border_color),
                     Cell(padding), Cell(padding_color),
                     Cell(nothing))
end

setfn!(w::WidgetScrollPane, f::Function) = (setfn!(getfield(w, :content), f); w)

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
    selection::Reference
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
    selection::Reference
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
    selection::Reference
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
reactive `title`/`content` they build (chevron glyph, empty body when collapsed),
the way `SyntaxToWidget` drives collapse from `node.collapsed`. Cards left at the
default `collapsed=false` render exactly as before.
"""
@document struct WidgetCard <: WidgetDocument
    position::Point2D
    title::Any
    description::Any
    content::Any
    footer::Any
    width::Int
    visible::Bool
    collapsed::Bool
    selection::Reference
end
WidgetCard(position::Point2D; title=nothing, description=nothing, content=nothing,
           footer=nothing, width::Integer=320, visible::Bool=true, collapsed::Bool=false) =
    WidgetCard(Cell(position), Cell(title), Cell(description), Cell(content),
               Cell(footer), Cell(Int(width)), Cell(visible), Cell(collapsed), Cell(nothing))

# ── WidgetSwitch ────────────────────────────────────────────────────────────

"""
    WidgetSwitch(position, checked)

An on/off toggle switch (rounded track + knob).
"""
@document struct WidgetSwitch <: WidgetDocument
    position::Point2D
    checked::Bool
    visible::Bool
    enabled::Bool
    selection::Reference
end
WidgetSwitch(position::Point2D, checked::Bool=false; visible::Bool=true, enabled::Bool=true) =
    WidgetSwitch(Cell(position), Cell(checked), Cell(visible), Cell(enabled), Cell(nothing))

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
    selection::Reference
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
    selection::Reference
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
    selection::Reference
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
    selection::Reference
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
    selection::Reference
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
    selection::Reference
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
    selection::Reference
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
    selection::Reference
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
    selection::Reference
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
window-route close is unpacked by `WindowManagerProjection`, the value write bubbles
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
    selection::Reference
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
    selection::Reference
end
WidgetTextarea(position::Point2D, content; width::Integer=320, rows::Integer=4, visible::Bool=true, enabled::Bool=true) =
    WidgetTextarea(Cell(position), Cell(content), Cell(Int(width)), Cell(Int(rows)),
                   Cell(visible), Cell(enabled), Cell(nothing))

# ── WidgetAccordion ─────────────────────────────────────────────────────────

"""
    WidgetAccordion(position, items; expanded=1, width=360)

A vertical accordion. `items` is a `Vector` of `(title, body)` tuples;
`expanded` is the 1-based index of the open item (0 = all collapsed).
"""
@document struct WidgetAccordion <: WidgetDocument
    position::Point2D
    items::CellVector
    expanded::Int
    width::Int
    visible::Bool
    selection::Reference
end
WidgetAccordion(position::Point2D, items::Vector; expanded::Integer=1, width::Integer=360, visible::Bool=true) =
    WidgetAccordion(Cell(position), CellVector(Cell[Cell(it) for it in items]),
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
  public reference vocabulary for selection (mirroring the old `TableToGraphics`
  `rows[r]` / `columns[c]` bands).
- `column_count::Int` — number of columns.
- `padding::Int` — inner padding (px) between a cell's border and its content.
- `border_width::Int` — hairline rule / border width (px).
- `visible::Bool`, `selection::Reference` — standard Document fields.

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
    selection::Reference
end

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
legacy `(label, children)` tuple); an empty vector marks a leaf.
"""
struct WidgetTreeNode
    icon::Any
    label::Any
    children::Vector
end
WidgetTreeNode(icon, label) = WidgetTreeNode(icon, label, Any[])

"""
    WidgetTree(position, roots)

A tree / outline view. `roots` is a `Vector` of nodes. A node is a
[`WidgetTreeNode`](@ref) (icon + label + children), or — for icon-less trees —
a leaf label (`String`) or a `(label, children::Vector)` tuple. Parent nodes get
an expand chevron; an icon (when present) is drawn in its own column before the
label; children are indented. (A widget-styled counterpart to the file-system /
navigator trees.)
"""
@document struct WidgetTree <: WidgetDocument
    position::Point2D
    roots::CellVector
    visible::Bool
    selection::Reference
end
WidgetTree(position::Point2D, roots::Vector; visible::Bool=true) =
    WidgetTree(Cell(position), CellVector(Cell[Cell(n) for n in roots]), Cell(visible), Cell(nothing))

# ── Operations ─────────────────────────────────────────────────────────────

# HideWidgetOperation / ShowWidgetOperation / ScrollWidgetOperation /
# SetScrollBarValueOperation were folded into ReplaceReferencedValue — a carried
# widget + a single-field write (`visible` / `scroll_position` / `value`). The
# producing readers (ProjectionConfiguring, WidgetScrollPane/ScrollBar readers in
# WidgetToGraphics) now emit `ReplaceReferencedValue(widget, "field", value)` and
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

"""
    InvokeWidgetActionOperation(widget)

Invoke `widget`'s `action` callable (e.g. a `WidgetButton` click). The action is
called with the editor when it accepts one argument, otherwise with none, so it
can mutate `editor.document` or projection state. A `nothing` action is a no-op.
"""
struct InvokeWidgetActionOperation <: Operation
    widget::WidgetDocument
end

# SetWidgetHoverOperation / SetWidgetPressedOperation were folded into
# ReplaceReferencedValue: the WidgetButton reader emits
# `ReplaceReferencedValue(widget, "hovered"/"pressed", bool)`. See
# plan/done/consolidate-operations-replace.md (step 2).

# ── Operation evaluation ───────────────────────────────────────────────────

"""
    evaluate_operation(op)

Apply a widget operation.
"""
function evaluate_operation(editor, op::SelectTabOperation)
    op.widget.selection = ConcreteReferencePath(ElementReference(op.tab_index), EmptyReferencePath())
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

# ── Focus traversal (Stage 2): finding focusable leaves ─────────────────────
#
# Focus is selection. These pure helpers locate the *first* / *last* focusable
# leaf in a subtree as a relative whole-element (∅) path, mirroring the generic
# field/element descent the selection machinery uses so the produced path matches
# the projection readers' re-rooting (`elements[i]` / `children[i]`, with
# `RangeReference(i-1, i)` for the i-th element). They live in this document-layer
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
            push!(refs, ((RangeReference(i - 1, i),), node[i]))
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
                push!(refs, ((FieldReference(string(fname)), RangeReference(i - 1, i)), v[i]))
            end
        elseif v isa Document
            push!(refs, ((FieldReference(string(fname)),), v))
        end
    end
    refs
end

# Prepend `steps` (outermost-first tuple) onto `path`.
function _prepend_steps(steps::Tuple, path::ReferencePath)
    for s in Base.reverse(steps)
        path = ConcreteReferencePath(s, path)
    end
    path
end

# Relative ∅-path to the first (last, when `reverse`) enabled interactive leaf in
# `node`'s subtree, or `nothing` if it holds no focusable widget.
function _focusable_path(node, reverse::Bool)
    node === nothing && return nothing
    _is_focusable_widget(node) && return EmptyReferencePath()
    refs = _child_document_refs(node)
    for (steps, child) in (reverse ? Base.reverse(refs) : refs)
        sub = _focusable_path(child, reverse)
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
