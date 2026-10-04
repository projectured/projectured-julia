# Fragment of `RstModule`.
#
# `RstRoot` / `RstSection` → `VerticalLayout` — the structural rewrap that
# makes an RST page a **stack of blocks** instead of one syntax tree, so
# each block renders in its own domain.
#
# It exists for the same reason markdown's page layout does: an embedded
# document may belong to a domain that is *not* syntax-producible. A card
# around an embed is a widget, and a widget squeezed through a syntax tree
# would arrive as reflected text and would never see a click.
#
# RST needs one more rule than markdown does. A markdown page is flat — its
# headings are elements of the root — so rewrapping the root is enough. An
# RST section **owns** its blocks, so a root rewrap alone would leave every
# embed below the first title inside a syntax tree. `RstSectionToVerticalLayout`
# therefore stacks a section too: its title over its blocks.
#
# The rewrap does not transform the blocks (the subtrees are identical on
# both sides, just moved), so the reference maps only relocate the head.
#
# **The title is flat.** A section's title renders as one prose line in the
# title font, with whatever inline markup it carries flattened to its text.
# A selection therefore maps through a section's *blocks* but not into its
# title — which is what the syntax rule offers as well, and strictly less
# than the source view, where the whole section maps.
# ── RstRootToVerticalLayout ────────────────────────────────────────────────

@projection UntrackedCell struct RstRootToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int = get_rst_style(nothing, :block_gap)
end

function print_document(p::RstRootToVerticalLayout, recursion, root::RstRoot, ctx)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(root, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    # The page's blocks, each in its own domain; an embedded file stands in a
    # card, built once for the block (see `_rst_block`).
    elements = root.elements::CellVector
    cards = IdDict{Any,Any}()
    children = CellVector(@computation Any[_rst_block(element, cards) for element in elements])
    out = VerticalLayout(children,
                         Cell(p.horizontal_align), Cell(p.gap),
                         Cell(nothing), Cell(nothing), paths.selection, paths.mouse_target)
    iomap = SimpleIoMap(p, root, out)
    iomap_cell[] = iomap
    iomap
end

map_reference_forward(::RstRootToVerticalLayout, iomap, reference) =
    _relocate_head(reference, "elements", "children";
                   carded = i -> _is_rst_carded(iomap.input, i))
map_reference_backward(::RstRootToVerticalLayout, iomap, reference) =
    _relocate_head(reference, "children", "elements";
                   carded = i -> _is_rst_carded(iomap.input, i))

# ── RstSectionToVerticalLayout ─────────────────────────────────────────────

@projection UntrackedCell struct RstSectionToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int                 = get_rst_style(nothing, :block_gap)
    title_1_font::StyleFont  = get_rst_style(nothing, :title_1_font)
    title_2_font::StyleFont  = get_rst_style(nothing, :title_2_font)
    title_3_font::StyleFont  = get_rst_style(nothing, :title_3_font)
    title_font::StyleFont    = get_rst_style(nothing, :title_font)
    title_color::StyleColor  = get_rst_style(nothing, :title_color)
end

function print_document(p::RstSectionToVerticalLayout, recursion, section::RstSection, ctx)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(section, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    # The title line, then the section's own blocks — which keep their cells, so
    # each block renders in its own domain and an embed reaches the widget
    # renderer. The title is rebuilt reactively: editing it re-renders the line.
    cards = IdDict{Any,Any}()
    children = CellVector(@computation begin
        stack = Any[_title_block(p, section)]
        append!(stack, [_rst_block(element, cards) for element in section.elements])
        stack
    end)
    out = VerticalLayout(children, Cell(p.horizontal_align), Cell(p.gap),
                         Cell(nothing), Cell(nothing), paths.selection, paths.mouse_target)
    iomap = SimpleIoMap(p, section, out)
    iomap_cell[] = iomap
    iomap
end

# The title as one prose line in the level's font, read from the projection's
# own fields.
_title_block(p, section::RstSection) =
    TextBlock([TextString(_title_text(section), StyleText(_title_font(p, section.level), unwrap_cell(p.title_color)))])

function _title_text(section::RstSection)
    buffer = IOBuffer()
    _title_runs!(buffer, section.title)
    String(take!(buffer))
end

_title_runs!(buffer::IO, nodes) = (foreach(n -> _title_run!(buffer, n), nodes); nothing)
_title_run!(buffer::IO, node::RstText)     = (print(buffer, node.content); nothing)
_title_run!(buffer::IO, node::RstLiteral)  = (print(buffer, node.content); nothing)
_title_run!(buffer::IO, node::RstRole)     = (print(buffer, node.content); nothing)
_title_run!(buffer::IO, node::RstStrong)   = _title_runs!(buffer, node.content)
_title_run!(buffer::IO, node::RstEmphasis) = _title_runs!(buffer, node.content)
_title_run!(::IO, ::Any) = nothing

# The title takes the first slot, so a block sits one further along than it does
# in the section. A path into the title itself has no image: the line is flat.
map_reference_forward(::RstSectionToVerticalLayout, iomap, reference) =
    _relocate_head(reference, "elements", "children"; shift = 1,
                   carded = i -> _is_rst_carded(iomap.input, i))
map_reference_backward(::RstSectionToVerticalLayout, iomap, reference) =
    _relocate_head(reference, "children", "elements"; shift = -1,
                   carded = i -> _is_rst_carded(iomap.input, i))

# ── An embedded file wears a card ──────────────────────────────────────────
#
# A block that is a file of another domain stands in a card titled with the
# file's name, as it does on a markdown page (`make_embed_card`). A block that
# is not a file draws what it draws.

_is_rst_carded_block(element) = is_file_document(element) && !(element isa RstDocument)

_rst_block(element, cards::IdDict) = _is_rst_carded_block(element) ?
    get!(() -> make_embed_card(element, get_filename(element)), cards, element) : element

# Whether block `i` (1-based, of the root's or the section's own elements)
# stands in a card.
function _is_rst_carded(container, i::Int)
    elements = container.elements
    1 <= i <= length(elements) || return false
    _is_rst_carded_block(elements[i])
end

# ── The shared head relocation ─────────────────────────────────────────────

# `from[i] + rest` → `to[i + shift] + rest`. Everything below the head is
# carried unchanged, because the rewrap moves the blocks without touching them —
# except the one step of a card a block stands in, which `carded` says of the
# block by its own 1-based index, and which is added going to the layout and
# dropped coming back.
function _relocate_head(reference, from::String, to::String; shift::Int = 0,
                        carded = i -> false)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    head = reference.head
    (head isa FieldReferenceStep && head.name == from) || return nothing
    tail = reference.tail
    tail isa ConcreteReference || return nothing
    step = tail.head
    (step isa RangeReferenceStep && is_element_reference_step(step)) || return nothing
    index = step.start + shift
    index >= 0 || return nothing
    rest = tail.tail
    block = from == "elements" ? step.start + 1 : index + 1
    if carded(block)
        rest = from == "elements" ? make_embed_card_path(rest) : find_embed_card_path_inside(rest)
        rest === nothing && return nothing
    end
    ConcreteReference(FieldReferenceStep(to),
                      ConcreteReference(RangeReferenceStep(index, index + 1), rest))
end

# A card inside a page is a real widget whose header and controls can be pressed,
# so these two rules have to pass an activation on. An `InvokeActionOperation`
# names its own `Action` and needs no re-rooting, but the generic reader answers
# nothing for an operation type it does not recognise, which is where a card's
# button would die.
read_intent(::RstRootToVerticalLayout, iomap, op::InvokeActionOperation) = op
read_intent(::RstSectionToVerticalLayout, iomap, op::InvokeActionOperation) = op
# A press on an embedded file's card header folds the card, and the operation
# names the card it folds.
read_intent(::RstRootToVerticalLayout, iomap, op::ToggleCollapseOperation) = op
read_intent(::RstSectionToVerticalLayout, iomap, op::ToggleCollapseOperation) = op

# ── Natural-projection registration ─────────────────────────────────────────
# An RST page is a stack of blocks, for the reason a markdown page is. It takes
# two rows where markdown takes one: an RST section OWNS its blocks, so a root
# rewrap alone would leave every embed below the first title inside a syntax
# tree, where a card could not go.
