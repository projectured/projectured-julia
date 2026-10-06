# Fragment of `MarkdownModule`.
#
# `MarkdownRoot → VerticalLayout` — the structural rewrap that makes a
# markdown page a **stack of blocks** instead of one syntax tree, so each
# block renders in its own domain.
#
# That distinction only matters because of embeds. A page's elements are
# mostly markdown, which renders through the to-syntax fabric either way;
# but an embedded document may belong to a domain that is *not*
# syntax-producible — a live simulation card is a widget, and a widget
# squeezed through a syntax tree would arrive as reflected text, and (the
# part that matters) would never see a click. Stacking the page's elements
# as layout children lets the surrounding renderer recurse each one by
# type: prose to prose, JSON to JSON, a widget to the widget renderer.
#
# The rewrap does not transform its children (the element subtrees are
# identical on both sides, just moved), so the reference maps only
# relocate the head: `elements[i] + rest ↔ children[i] + rest`. This
# mirrors `CellVectorToVerticalLayout`, which does the same for a bare
# collection.
@projection UntrackedCell struct MarkdownRootToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int = get_markdown_style(nothing, :block_gap)
end

function print_document(p::MarkdownRootToVerticalLayout, recursion, root::MarkdownRoot, ctx)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(root, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    # The page's own element cells are reused, not copied: the layout's
    # children share the root's element storage (only the path cells are
    # the layout's own), and the layout renderer recurses each element.
    #
    # Every block fills the width of the page (`child_width = Fill`), which is
    # what makes a paragraph break its lines at the edge of the page rather
    # than at the length of its longest sentence. A block that authored a width
    # of its own keeps it: an offer is a promise about space, not a constraint.
    #
    # An embedded file stands in a card of its own (below), and a table in a
    # widget table (further below). Each is built once for the element and found
    # again by it, so a fold survives a block added above.
    elements = root.elements::CellVector
    cards = IdDict{Any,Any}()
    block_of(element) =
        _is_carded_block(element)  ? get!(() -> make_embed_card(element, get_filename(element)), cards, element) :
        element isa MarkdownTable ? get!(() -> _make_page_table(element), cards, element) :
        element
    children = CellVector(@computation Any[block_of(element) for element in elements])
    out = VerticalLayout(children,
                         Cell(p.horizontal_align), Cell(p.gap),
                         Cell(Fill), Cell(nothing), paths.selection, paths.mouse_target)
    iomap = SimpleIoMap(p, root, out)
    iomap_cell[] = iomap
    iomap
end

# ── An embedded file wears a card ────────────────────────────────────────────
#
# A page element that is a file of another domain — a NED network, an INI
# configuration, a JSON value — is where the page stops and the file starts. It
# stands in a card titled with the file's name (`make_embed_card`), which a
# person can fold, and both maps add and drop the card's one step.
#
# A block that is not a file draws what it draws. A run card or a table is a
# card already, and a second one around it would say the same thing twice.

_is_carded_block(element) = is_file_document(element) && !(element isa MarkdownDocument)

_get_page_element(root::MarkdownRoot, i::Int) =
    1 <= i <= length(root.elements) ? root.elements[i] : nothing

# elements[i] + rest  →  children[i] + rest, and children[i].content + rest
# for a block in a card. The whole block is the whole card.
function map_reference_forward(::MarkdownRootToVerticalLayout, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    h = reference.head
    (h isa FieldReferenceStep && h.name == "elements") || return nothing
    t = reference.tail
    t isa ConcreteReference || return nothing
    (t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
    rest = t.tail
    element = _get_page_element(iomap.input, t.head.start + 1)
    if _is_carded_block(element)
        rest = make_embed_card_path(rest)
    elseif element isa MarkdownTable
        rest = _map_table_path_forward(rest)
        rest === nothing && return nothing
    end
    ConcreteReference(FieldReferenceStep("children"), ConcreteReference(t.head, rest))
end

# children[i] + rest  →  elements[i] + rest. Through a card, the body's path
# loses the card's `content` step, and a path into the card's header — its
# title — names the whole block.
function map_reference_backward(::MarkdownRootToVerticalLayout, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    h = reference.head
    (h isa FieldReferenceStep && h.name == "children") || return nothing
    t = reference.tail
    t isa ConcreteReference || return nothing
    (t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
    rest = t.tail
    element = _get_page_element(iomap.input, t.head.start + 1)
    if _is_carded_block(element)
        rest = find_embed_card_path_inside(rest)
    elseif element isa MarkdownTable
        rest = _map_table_path_backward(rest)
    end
    rest === nothing && return nothing
    ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(t.head, rest))
end

# ── A table is a widget table ────────────────────────────────────────────────
#
# A table on the page is drawn as a `WidgetTable`, the one table of the widget
# layer: a header strip, lines between the entries, and entries that break their
# lines at the edge of their column. The columns share the width of the page,
# and each sits where the delimiter row of the table says.
# The entries are the paragraphs of the table, not copies, so the page draws
# each one as prose.
function _make_page_table(table::MarkdownTable)
    column_headers = CellVector(@computation Any[entry for entry in table.header.elements])
    rows = CellVector(@computation Any[CellVector(Cell[Cell(entry) for entry in row.elements])
                                       for row in table.rows])
    # Each column sits where the delimiter row says.
    columns = Cell(@computation Any[WidgetTableColumn(; align) for align in _make_column_align(table.alignments)])
    widget = WidgetTable(Cell(Point2D(0, 0)), column_headers, CellVector(), Cell(nothing), rows,
                         Cell(:row_major), Cell(@computation WidgetTableRows(length(rows))), columns,
                         Cell(1),                          # border_width
                         Cell(Fill), Cell(Content),        # the columns share the width
                         Cell(:wrap),                      # an entry breaks its lines at its column
                         Cell(true),                       # visible
                         Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing), # margin, border, padding, style
                         Cell(Point2D(0, 0)),              # scroll_position
                         Cell(1),                          # top_row
                         Cell(nothing),                    # column_drag
                         Cell(:auto), Cell(:auto),         # vertical_scroll_bar, horizontal_scroll_bar
                         Cell(nothing),                    # open_cells
                         Cell(nothing))                    # tooltip
    set_output_path_computations!(widget, table, _map_table_path_forward)
    widget
end

# Where the entries of each column sit, from the delimiter row: a column that
# names no side sits at the left.
_make_column_align(alignments) =
    Symbol[alignment === :default ? :left : alignment for alignment in alignments]

# A path inside a table, as a path inside its widget table: `header.elements[j]`
# is `column_headers[j]`, `rows[k]` is `rows[k]`, and `rows[k].elements[j]` is
# `cells[k][j]`. The rest of
# the path is inside the entry, which the two share. A path to what the widget
# does not draw, such as `alignments`, maps to nothing.
function _map_table_path_forward(reference)
    reference isa EmptyReference && return reference
    reference isa ConcreteReference || return nothing
    h, t = reference.head, reference.tail
    h isa FieldReferenceStep || return nothing
    if h.name == "header"
        t isa EmptyReference && return ConcreteReference(FieldReferenceStep("column_headers"), t)
        (t isa ConcreteReference && t.head isa FieldReferenceStep && t.head.name == "elements") ||
            return nothing
        return ConcreteReference(FieldReferenceStep("column_headers"), t.tail)
    elseif h.name == "rows"
        (t isa ConcreteReference && t.head isa RangeReferenceStep && is_element_reference_step(t.head)) ||
            return nothing
        entries = t.tail
        entries isa EmptyReference && return reference
        (entries isa ConcreteReference && entries.head isa FieldReferenceStep && entries.head.name == "elements") ||
            return nothing
        return ConcreteReference(FieldReferenceStep("cells"), ConcreteReference(t.head, entries.tail))
    end
    nothing
end

# A path inside a widget table, as a path inside its table: the inverse of
# `_map_table_path_forward`.
function _map_table_path_backward(reference)
    reference isa EmptyReference && return reference
    reference isa ConcreteReference || return nothing
    h, t = reference.head, reference.tail
    h isa FieldReferenceStep || return nothing
    if h.name == "column_headers"
        return ConcreteReference(FieldReferenceStep("header"),
                                 ConcreteReference(FieldReferenceStep("elements"), t))
    elseif h.name == "rows"
        (t isa ConcreteReference && t.head isa RangeReferenceStep && is_element_reference_step(t.head) &&
         t.tail isa EmptyReference) || return nothing
        return reference
    elseif h.name == "cells"
        (t isa ConcreteReference && t.head isa RangeReferenceStep && is_element_reference_step(t.head)) ||
            return nothing
        t.tail isa EmptyReference && return nothing
        return ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(t.head,
                                     ConcreteReference(FieldReferenceStep("elements"), t.tail)))
    end
    nothing
end

# The whole point of the rewrap is that a page's embedded card is a real widget
# whose controls can be clicked — so this projection is the one that has to pass
# their activations on. An `InvokeActionOperation` names its own `Action` and
# needs no re-rooting, but the generic reader returns `nothing` for every
# operation type it does not recognise, which is where a card's Run button used
# to die: it rendered, took the press, answered, and the answer stopped here.
read_intent(::MarkdownRootToVerticalLayout, iomap, op::InvokeActionOperation) = op

# A press on an embedded file's card header folds the card. The operation names
# the card it folds, so it needs no re-rooting either.
read_intent(::MarkdownRootToVerticalLayout, iomap, op::ToggleCollapseOperation) = op

# And the same for a click that lands IN an embedded card rather than on one of
# its buttons. A card that takes the keyboard — a conversation, a form — needs
# the caret to arrive, and the caret arrives as a selection naming a child of
# this layout. Re-rooted here into the page's own elements, exactly as
# `map_reference_backward` does for any other reference; without this a click on
# the card lands on nothing and every key goes to the prose above.
function read_intent(p::MarkdownRootToVerticalLayout, iomap, op::ReplacePathOperation)
    inner = map_reference_backward(p, iomap, op.path)
    inner === nothing ? nothing : make_path_operation(op, inner)
end

# ── Natural-projection registration ─────────────────────────────────────────
# A markdown page is a stack of blocks, not one syntax tree, so each element
# re-enters the natural renderer in its own domain. Prose still goes to the
# syntax fabric; an embed whose document is a widget (a live simulation card)
# reaches the widget renderer and can be clicked, which a syntax tree could
# never offer it.
