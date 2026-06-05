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
       HideWidgetOperation, ShowWidgetOperation, ScrollWidgetOperation, SelectTabOperation,
       SetScrollBarValueOperation,
       evaluate_operation,
       inset_default, inset_size, inset_width, inset_height,
       inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right,
       setfn!,
       IWidgetInsertion,
       IWidgetLabel, IWidgetText, IWidgetCheckbox, IWidgetButton,
       IWidgetTooltip, IWidgetMenu, IWidgetMenuItem, IWidgetComposite,
       IWidgetShell, IWidgetTitlePane, IWidgetSplitPane, IWidgetTabbedPane,
       IWidgetScrollPane, IWidgetToolbar, IWidgetScrollBar

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
                    Cell(nothing))
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

end # module
