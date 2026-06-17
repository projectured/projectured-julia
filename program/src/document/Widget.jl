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
import ..ReferenceModule: Reference, ConcreteReferencePath, ElementReference, EmptyReferencePath
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
       WidgetToggle, WidgetToggleGroup, WidgetSelect, WidgetTextarea, WidgetAccordion,
       WidgetTable, WidgetTree,
       HideWidgetOperation, ShowWidgetOperation, ScrollWidgetOperation, SelectTabOperation,
       SetScrollBarValueOperation,
       StartSplitterDragOperation, ResizeSplitPaneOperation, EndSplitterDragOperation,
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
       IWidgetToggle, IWidgetToggleGroup, IWidgetSelect, IWidgetTextarea, IWidgetAccordion,
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
    value::Any
    selection::Reference
end
WidgetInsertion() = WidgetInsertion(Cell(nothing), Cell(nothing))

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

function Base.show(io::IO, w::WidgetLabel)
    print(io, "WidgetLabel(pos=", w.position, ", content=", w.content, ")")
end

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
                    margin::Inset=inset_default,
                    margin_color=nothing,
                    border::Inset=inset_default,
                    border_color=nothing,
                    padding::Inset=inset_default,
                    padding_color=nothing)
    WidgetText(Cell(position), Cell(content), Cell(content_fill_color),
               Cell(visible), Cell(margin), Cell(margin_color),
               Cell(border), Cell(border_color),
               Cell(padding), Cell(padding_color),
               Cell(nothing))
end

setfn!(w::WidgetText, f::Function) = (setfn!(getfield(w, :content), f); w)

function Base.show(io::IO, w::WidgetText)
    print(io, "WidgetText(pos=", w.position, ", content=", w.content, ")")
end

# ── WidgetCheckbox ─────────────────────────────────────────────────────────

"""
    WidgetCheckbox(position, content; <base kwargs>)

A checkbox widget..
"""
@document struct WidgetCheckbox <: WidgetDocument
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

function WidgetCheckbox(position::Point2D, content;
                        visible::Bool=true,
                        margin::Inset=inset_default,
                        margin_color=nothing,
                        border::Inset=inset_default,
                        border_color=nothing,
                        padding::Inset=inset_default,
                        padding_color=nothing)
    WidgetCheckbox(Cell(position), Cell(content),
                   Cell(visible), Cell(margin), Cell(margin_color),
                   Cell(border), Cell(border_color),
                   Cell(padding), Cell(padding_color),
                   Cell(nothing))
end

setfn!(w::WidgetCheckbox, f::Function) = (setfn!(getfield(w, :content), f); w)

function Base.show(io::IO, w::WidgetCheckbox)
    print(io, "WidgetCheckbox(pos=", w.position, ", content=", w.content, ")")
end

# ── WidgetButton ───────────────────────────────────────────────────────────

"""
    WidgetButton(position, size, content; <base kwargs>)

A clickable button..
"""
@document struct WidgetButton <: WidgetDocument
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

function WidgetButton(position::Point2D, size::Point2D, content;
                      visible::Bool=true,
                      margin::Inset=inset_default,
                      margin_color=nothing,
                      border::Inset=inset_default,
                      border_color=nothing,
                      padding::Inset=inset_default,
                      padding_color=nothing)
    WidgetButton(Cell(position), Cell(size), Cell(content),
                 Cell(visible), Cell(margin), Cell(margin_color),
                 Cell(border), Cell(border_color),
                 Cell(padding), Cell(padding_color),
                 Cell(nothing))
end

setfn!(w::WidgetButton, f::Function) = (setfn!(getfield(w, :content), f); w)

function Base.show(io::IO, w::WidgetButton)
    print(io, "WidgetButton(pos=", w.position,
          ", size=", w.size, ", content=", w.content, ")")
end

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

function Base.show(io::IO, w::WidgetTooltip)
    print(io, "WidgetTooltip(pos=", w.position,
          ", size=", w.size, ", content=", w.content, ")")
end

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

function Base.show(io::IO, w::WidgetMenu)
    print(io, "WidgetMenu(elements=", length(w.elements), ")")
end

# ── WidgetMenuItem ─────────────────────────────────────────────────────────

"""
    WidgetMenuItem(content; <base kwargs>)

A single item inside a `WidgetMenu`..
"""
@document struct WidgetMenuItem <: WidgetDocument
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

function WidgetMenuItem(content;
                        visible::Bool=true,
                        margin::Inset=inset_default,
                        margin_color=nothing,
                        border::Inset=inset_default,
                        border_color=nothing,
                        padding::Inset=inset_default,
                        padding_color=nothing)
    WidgetMenuItem(Cell(content),
                   Cell(visible), Cell(margin), Cell(margin_color),
                   Cell(border), Cell(border_color),
                   Cell(padding), Cell(padding_color),
                   Cell(nothing))
end

setfn!(w::WidgetMenuItem, f::Function) = (setfn!(getfield(w, :content), f); w)

function Base.show(io::IO, w::WidgetMenuItem)
    print(io, "WidgetMenuItem(content=", w.content, ")")
end

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

function Base.show(io::IO, w::WidgetComposite)
    print(io, "WidgetComposite(pos=", w.position,
          ", elements=", length(w.elements), ")")
end

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

function Base.show(io::IO, w::WidgetToolbar)
    print(io, "WidgetToolbar(elements=", length(w.elements), ")")
end

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

function Base.show(io::IO, w::WidgetShell)
    print(io, "WidgetShell(content=", w.content, ")")
end

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

function Base.show(io::IO, w::WidgetTitlePane)
    print(io, "WidgetTitlePane(title=", w.title, ")")
end

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

function Base.show(io::IO, w::WidgetSplitPane)
    print(io, "WidgetSplitPane(orientation=", w.orientation,
          ", elements=", length(w.elements), ")")
end

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

function Base.show(io::IO, w::WidgetTabbedPane)
    print(io, "WidgetTabbedPane(pairs=", length(w.selector_element_pairs), ")")
end

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

function Base.show(io::IO, w::WidgetScrollPane)
    print(io, "WidgetScrollPane(content=", w.content,
          ", scroll=", w.scroll_position, ")")
end

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

function Base.show(io::IO, w::WidgetScrollBar)
    print(io, "WidgetScrollBar(orientation=", w.orientation,
          ", value=", w.value, ")")
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
Base.show(io::IO, w::WidgetBadge) = print(io, "WidgetBadge(", w.content, ", ", w.variant, ")")

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
Base.show(io::IO, w::WidgetSeparator) = print(io, "WidgetSeparator(", w.orientation, ")")

# ── WidgetCard ──────────────────────────────────────────────────────────────

"""
    WidgetCard(position; title, description, content, footer, width=320)

A rounded, bordered surface with an optional title / description header, a
content body and an optional footer, stacked vertically.
"""
@document struct WidgetCard <: WidgetDocument
    position::Point2D
    title::Any
    description::Any
    content::Any
    footer::Any
    width::Int
    visible::Bool
    selection::Reference
end
WidgetCard(position::Point2D; title=nothing, description=nothing, content=nothing,
           footer=nothing, width::Integer=320, visible::Bool=true) =
    WidgetCard(Cell(position), Cell(title), Cell(description), Cell(content),
               Cell(footer), Cell(Int(width)), Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetCard) = print(io, "WidgetCard(", w.title, ")")

# ── WidgetSwitch ────────────────────────────────────────────────────────────

"""
    WidgetSwitch(position, checked)

An on/off toggle switch (rounded track + knob).
"""
@document struct WidgetSwitch <: WidgetDocument
    position::Point2D
    checked::Bool
    visible::Bool
    selection::Reference
end
WidgetSwitch(position::Point2D, checked::Bool=false; visible::Bool=true) =
    WidgetSwitch(Cell(position), Cell(checked), Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetSwitch) = print(io, "WidgetSwitch(", w.checked, ")")

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
Base.show(io::IO, w::WidgetProgress) = print(io, "WidgetProgress(", w.value, ")")

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
    selection::Reference
end
WidgetSlider(position::Point2D, value::Real=0.5; width::Integer=240, visible::Bool=true) =
    WidgetSlider(Cell(position), Cell(Float64(value)), Cell(Int(width)), Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetSlider) = print(io, "WidgetSlider(", w.value, ")")

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
    selection::Reference
end
WidgetRadioGroup(position::Point2D, options::Vector; selected::Integer=1, visible::Bool=true) =
    WidgetRadioGroup(Cell(position), CellVector(Cell[Cell(o) for o in options]),
                     Cell(Int(selected)), Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetRadioGroup) = print(io, "WidgetRadioGroup(", length(w.options), ")")

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
Base.show(io::IO, w::WidgetAvatar) = print(io, "WidgetAvatar(", w.initials, ")")

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
Base.show(io::IO, w::WidgetAlert) = print(io, "WidgetAlert(", w.title, ")")

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
Base.show(io::IO, w::WidgetSkeleton) = print(io, "WidgetSkeleton(", w.width, "×", w.height, ")")

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
    selection::Reference
end
WidgetToggle(position::Point2D, content; pressed::Bool=false, visible::Bool=true) =
    WidgetToggle(Cell(position), Cell(content), Cell(pressed), Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetToggle) = print(io, "WidgetToggle(", w.content, ", ", w.pressed, ")")

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
    selection::Reference
end
WidgetToggleGroup(position::Point2D, options::Vector; selected::Integer=1, visible::Bool=true) =
    WidgetToggleGroup(Cell(position), CellVector(Cell[Cell(o) for o in options]),
                      Cell(Int(selected)), Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetToggleGroup) = print(io, "WidgetToggleGroup(", length(w.options), ")")

# ── WidgetSelect ────────────────────────────────────────────────────────────

"""
    WidgetSelect(position, value; width=220)

A closed select / combobox: an input-like box showing `value` with a trailing
chevron (the dropdown itself is a reader concern, out of scope here).
"""
@document struct WidgetSelect <: WidgetDocument
    position::Point2D
    value::Any
    width::Int
    visible::Bool
    selection::Reference
end
WidgetSelect(position::Point2D, value; width::Integer=220, visible::Bool=true) =
    WidgetSelect(Cell(position), Cell(value), Cell(Int(width)), Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetSelect) = print(io, "WidgetSelect(", w.value, ")")

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
    selection::Reference
end
WidgetTextarea(position::Point2D, content; width::Integer=320, rows::Integer=4, visible::Bool=true) =
    WidgetTextarea(Cell(position), Cell(content), Cell(Int(width)), Cell(Int(rows)),
                   Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetTextarea) = print(io, "WidgetTextarea(rows=", w.rows, ")")

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
Base.show(io::IO, w::WidgetAccordion) = print(io, "WidgetAccordion(", length(w.items), ")")

# ── WidgetTable ─────────────────────────────────────────────────────────────

"""
    WidgetTable(position, headers, rows)

A data table: a header row over body rows separated by hairline
rules. `headers` is a `Vector` of column titles; `rows` is a `Vector` of rows,
each a `Vector` of cell values. (Compare `TableTable`, the spreadsheet domain —
this is the widget-styled presentation variant.)
"""
@document struct WidgetTable <: WidgetDocument
    position::Point2D
    headers::CellVector
    rows::CellVector
    visible::Bool
    selection::Reference
end
WidgetTable(position::Point2D, headers::Vector, rows::Vector; visible::Bool=true) =
    WidgetTable(Cell(position),
                CellVector(Cell[Cell(h) for h in headers]),
                CellVector(Cell[Cell(r) for r in rows]),
                Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetTable) = print(io, "WidgetTable(", length(w.headers), "×", length(w.rows), ")")

# ── WidgetTree ──────────────────────────────────────────────────────────────

"""
    WidgetTree(position, roots)

A tree / outline view. `roots` is a `Vector` of nodes, where each node is either
a leaf label (`String`) or a `(label, children::Vector)` tuple. Parent nodes get
an expand chevron; children are indented. (A widget-styled counterpart to the
file-system / navigator trees.)
"""
@document struct WidgetTree <: WidgetDocument
    position::Point2D
    roots::CellVector
    visible::Bool
    selection::Reference
end
WidgetTree(position::Point2D, roots::Vector; visible::Bool=true) =
    WidgetTree(Cell(position), CellVector(Cell[Cell(n) for n in roots]), Cell(visible), Cell(nothing))
Base.show(io::IO, w::WidgetTree) = print(io, "WidgetTree(", length(w.roots), ")")

# ── Operations ─────────────────────────────────────────────────────────────

"""
    HideWidgetOperation(widget)

Hides the target widget by setting its `visible` cell to `false`.

"""
struct HideWidgetOperation <: Operation
    widget::WidgetDocument
end

"""
    ShowWidgetOperation(widget)

Shows the target widget by setting its `visible` cell to `true`.

"""
struct ShowWidgetOperation <: Operation
    widget::WidgetDocument
end

"""
    ScrollWidgetOperation(scroll_pane, scroll_delta)

Advances the `scroll_position` of `scroll_pane` by `scroll_delta`.

"""
struct ScrollWidgetOperation <: Operation
    scroll_pane::WidgetScrollPane
    scroll_delta::Point2D
end

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
    SetScrollBarValueOperation(scroll_bar, value)

Sets the `value` of `scroll_bar` to `value`, clamped to [0, 1].
"""
struct SetScrollBarValueOperation <: Operation
    scroll_bar::WidgetScrollBar
    value::Float64
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

# ── Operation evaluation ───────────────────────────────────────────────────

"""
    evaluate_operation(op)

Apply a widget operation.
"""
function evaluate_operation(editor, op::HideWidgetOperation)
    op.widget.visible = false
end

function evaluate_operation(editor, op::ShowWidgetOperation)
    op.widget.visible = true
end

function evaluate_operation(editor, op::ScrollWidgetOperation)
    sp = op.scroll_pane
    old = sp.scroll_position::Point2D
    delta = op.scroll_delta
    sp.scroll_position = Point2D(old.x[] + delta.x[], old.y[] + delta.y[])
end

function evaluate_operation(editor, op::SetScrollBarValueOperation)
    op.scroll_bar.value = clamp(op.value, 0.0, 1.0)
end

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

end # module
