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
@projection struct MarkdownRootToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int = 8
end

function print_document(p::MarkdownRootToVerticalLayout, recursion, root::MarkdownRoot, ctx)
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        iomap = iomap_cell[]
        iomap === nothing && return nothing
        map_reference_forward(p, iomap, root.selection)
    end)
    # The page's own element cells are reused, not copied: the layout's
    # children share the root's element storage (only the selection cell is
    # the layout's own), and the layout renderer recurses each element.
    #
    # Every block fills the width of the page (`child_width = Fill`), which is
    # what makes a paragraph break its lines at the edge of the page rather
    # than at the length of its longest sentence. A block that authored a width
    # of its own keeps it: an offer is a promise about space, not a constraint.
    #
    # An embedded file stands in a card of its own (below), built once for the
    # element and found again by it, so a fold survives a block added above.
    elements = root.elements::CellVector
    cards = IdDict{Any,Any}()
    block_of(element) = _is_carded_block(element) ?
        get!(() -> make_embed_card(element, get_filename(element)), cards, element) : element
    children = ComputedCellVector(() -> Any[block_of(element) for element in elements])
    out = VerticalLayout(children,
                         Cell(p.horizontal_align), Cell(p.gap),
                         Cell(Fill), Cell(nothing), sel)
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
    _is_carded_block(_get_page_element(iomap.input, t.head.start + 1)) &&
        (rest = make_embed_card_path(rest))
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
    if _is_carded_block(_get_page_element(iomap.input, t.head.start + 1))
        rest = find_embed_card_path_inside(rest)
        rest === nothing && return nothing
    end
    ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(t.head, rest))
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
function read_intent(p::MarkdownRootToVerticalLayout, iomap, op::ReplaceSelectionOperation)
    inner = map_reference_backward(p, iomap, op.path)
    inner === nothing ? nothing : ReplaceSelectionOperation(inner)
end

# ── Natural-projection registration ─────────────────────────────────────────
# A markdown page is a stack of blocks, not one syntax tree, so each element
# re-enters the natural renderer in its own domain. Prose still goes to the
# syntax fabric; an embed whose document is a widget (a live simulation card)
# reaches the widget renderer and can be clicked, which a syntax tree could
# never offer it.
