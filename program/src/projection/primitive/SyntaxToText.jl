"""
    SyntaxToTextModule

Syntax → Text projection. Word-wrapping layout engine that converts a tree
of delimited spans into a flat sequence of styled strings. Character ranges
for each child subtree are recorded in the IoMap so the reader can map a
flat cursor offset back to the correct subtree and local position within it.
"""
module SyntaxToTextModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..CollectionModule: CellVector, ListNode
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TextModule: TextText, TextString, TextNewline, TextDocument
import ..FontModule: font_ubuntu_monospace_regular_24
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, EmptyReferencePath, ReferencePath
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..IoMapModule: SimpleIoMap
import ..IoMapApiModule: IoMap
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown
export SyntaxLeafToText, SyntaxNodeToText, SyntaxListToText, SyntaxToText,
       SyntaxNodeToTextIoMap, _syntax_to_flat

# ── SyntaxLeafToText ───────────────────────────────────────────────────
# Three spans: open delimiter, value, close delimiter.
# The TextStrings are extracted directly from the leaf, preserving
# whatever font/color was set by the upstream projection.

struct SyntaxLeafToText <: Projection end

function map_reference_forward(::SyntaxLeafToText, iomap, reference)
    @reference_case reference begin
        open{s:_}                  => _text_elem_path(1, s)
        value{s:_}                 => _text_elem_path(2, s)
        close{s:_}                 => _text_elem_path(3, s)
        proj(_, open{s:_})         => _text_elem_path(1, s)
        proj(_, close{s:_})        => _text_elem_path(3, s)
    end
end

function map_reference_backward(::SyntaxLeafToText, iomap, reference)
    span_idx, char_idx = _parse_text_elem_path(reference)
    span_idx === nothing && return nothing
    span_idx == 1 && return @reference open{char_idx}
    span_idx == 2 && return @reference value{char_idx}
    span_idx == 3 && return @reference close{char_idx}
    return nothing
end

# Selection mapping (SyntaxLeaf → TextText, three spans: [open, value, close]):
# leaf.selection[] is translated to a TextText span cursor:
#   .open[k]       →  .elements[1]  (char k within the open span)
#   .value[k]      →  .elements[2]  (char k within the value span)
#   .close[k]      →  .elements[3]  (char k within the close span)
#   PS(p).open[k]  →  .elements[1]
#   PS(p).close[k] →  .elements[3]
#   anything else  →  no cursor
function projection_print(p::SyntaxLeafToText, leaf::SyntaxLeaf, recursion, ctx)
    sel = Cell(() -> begin
        c = _leaf_cursor(leaf)
        c < 0 ? nothing : _flat_to_text_elem_path([leaf.open, leaf.value, leaf.close], c)
    end)
    SimpleIoMap(p, leaf, TextText(CellVector(() -> TextDocument[leaf.open, leaf.value, leaf.close]), sel))
end

function projection_read(p::SyntaxLeafToText, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    return ReplaceSelectionOperation(input_path)
end

# Pass KeyDown events through so upstream projections (e.g.
# PrimitiveStringToSyntaxLeaf) can react to Backspace/Delete. TextToGraphics
# returns the raw KeyDown for keys it doesn't consume.
projection_read(::SyntaxLeafToText, iomap::SimpleIoMap, evt::KeyDown) = evt

# ── SyntaxNodeToText ───────────────────────────────────────────────────
# For nodes with non-empty open/close delimiters (like { } or [ ]):
#   open_delim \n indent child₁ sep \n indent child₂ … \n dedent close_delim
# For inline nodes (empty open delimiter, like key: value pairs):
#   child₁ sep child₂ …
# Reading node.children[] registers it as a dependency of the
# TextText's spans cell, so structural changes trigger a rebuild.
# Children are projected recursively via projection_print(recursion, ...).

struct SyntaxNodeToText <: Projection
    indent_size::Int
end

SyntaxNodeToText(; indent_size::Int = 2) =
    SyntaxNodeToText(indent_size)

struct SyntaxNodeToTextIoMap <: IoMap
    projection::Any
    input::SyntaxNode
    output::TextText
    child_char_ranges::Cell
end

function map_reference_forward(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, reference)
    flat_pos = _syntax_to_flat(iomap.input, reference, p, 0)
    flat_pos < 0 && return nothing
    _flat_to_text_elem_path(iomap.output.elements, flat_pos)
end

function map_reference_backward(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, reference)
    # Also accept bare flat char index: ConcreteReferencePath(PositionReference(n))
    if reference isa ConcreteReferencePath
        h = reference.head
        if h isa RangeReference && reference.tail isa EmptyReferencePath
            return _pos_to_selection(iomap.input, h.start::Int, p, 0)
        end
    end
    span_idx, char_idx = _parse_text_elem_path(reference)
    span_idx === nothing && return nothing
    flat_pos = _text_elem_path_to_flat(iomap.output.elements, span_idx, char_idx)
    flat_pos < 0 && return nothing
    _pos_to_selection(iomap.input, flat_pos, p, 0)
end

# Selection mapping (SyntaxNode → TextText):
# Renders open, children interleaved with sep (plus \n+indent when indentation>0),
# then close.  The output TextText cursor comes from two sources; structural wins:
#   1. First child whose selection cell yields a valid cursor via _leaf_cursor.
#   2. node.selection[] translated by _syntax_to_flat:
#        .open[k]      →  .elements at char k of the open span
#        .close[k]     →  .elements at char k of the close span
#        .children[i]  →  .elements at offset of child i + child's cursor
function projection_print(p::SyntaxNodeToText, node::SyntaxNode, recursion, ctx)
    both = Cell(() -> _collect_spans(node, p, 0, recursion))
    output = TextText(
        CellVector(() -> both[][1]),
        Cell(() -> begin
            cursor = both[][2]
            cursor < 0 && return nothing
            _flat_to_text_elem_path(both[][1], cursor)
        end))
    child_ranges = Cell(() -> both[][3])
    SyntaxNodeToTextIoMap(p, node, output, child_ranges)
end

function projection_read(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    return ReplaceSelectionOperation(input_path)
end

# ── SyntaxListToText ──────────────────────────────────────────────────
# ListNode(SyntaxDocument) → TextText with ListNode elements.
# Each SyntaxLeaf/Node is rendered to spans, with TextNewline separators
# between elements. The ListNode structure is preserved lazily.

struct SyntaxListToText <: Projection end

function map_reference_forward(::SyntaxListToText, iomap, reference)
    return nothing
end

function map_reference_backward(::SyntaxListToText, iomap, reference)
    return nothing
end

"""
    projection_print(::SyntaxListToText, ln::ListNode, recursion, ctx)

Convert a `ListNode(SyntaxDocument)` to a `TextText` with `ListNode` elements.
Each syntax element becomes its text spans (open, value, close for leaves),
with `TextNewline` separators between elements.
"""
function projection_print(p::SyntaxListToText, ln::ListNode, recursion, ctx)
    cache = IdDict{ListNode, ListNode}()
    out_head = _syntax_list_to_text_node(ln, recursion, cache)
    SimpleIoMap(p, ln, TextText(out_head, Cell(nothing)))
end

# `cache` maps each input ListNode to the first output node of its rendered
# span chain.  This makes the projection idempotent under repeated traversal:
# walking next then prev returns to the same object instead of materialising
# a fresh prev-chain on every call.
function _syntax_list_to_text_node(input_node::ListNode, recursion, cache::IdDict)
    haskey(cache, input_node) && return cache[input_node]

    elem = input_node.value
    spans = _render_syntax_to_spans(elem)

    first_out = ListNode(spans[1])
    cache[input_node] = first_out

    cur_out = first_out
    for i in 2:length(spans)
        next_out = ListNode(spans[i])
        setval!(getfield(cur_out, :next), next_out)
        setval!(getfield(next_out, :prev), cur_out)
        cur_out = next_out
    end

    nl_node = ListNode(TextNewline(font=font_ubuntu_monospace_regular_24))
    setval!(getfield(cur_out, :next), nl_node)
    setval!(getfield(nl_node, :prev), cur_out)

    setfn!(getfield(nl_node, :next), () -> begin
        input_next = input_node.next
        input_next === nothing && return nothing
        next_first = _syntax_list_to_text_node(input_next, recursion, cache)
        setval!(getfield(next_first, :prev), nl_node)
        next_first
    end)

    setfn!(getfield(first_out, :prev), () -> begin
        input_prev = input_node.prev
        input_prev === nothing && return nothing
        prev_first = _syntax_list_to_text_node(input_prev, recursion, cache)
        # Walk forward through this paragraph's span chain to its trailing
        # nl_node. Stop at the TextNewline rather than reading `cur.next`
        # past it — nl_node.next is a lazy thunk that materialises the
        # *next* paragraph, which for an infinite stream never terminates.
        cur = prev_first
        while !(cur.value isa TextNewline)
            nxt = cur.next
            nxt === nothing && break
            cur = nxt
        end
        setval!(getfield(cur, :next), first_out)
        cur
    end)

    first_out
end

function _render_syntax_to_spans(leaf::SyntaxLeaf)
    TextDocument[leaf.open, leaf.value, leaf.close]
end

function _render_syntax_to_spans(node::SyntaxNode)
    # Simple flat rendering for ListNode context
    spans = TextDocument[]
    push!(spans, node.open)
    for (i, child) in enumerate(node.children)
        i > 1 && push!(spans, node.sep)
        append!(spans, _render_syntax_to_spans(child))
    end
    push!(spans, node.close)
    spans
end

function _render_syntax_to_spans(other)
    # Fallback: convert to string
    TextDocument[TextString(string(other))]
end

# ── Compound convenience constructor ────────────────────────────────────────

function SyntaxToText(; indent_size::Int = 2)
    TypeDispatchingProjection(
        SyntaxLeaf => SyntaxLeafToText(),
        SyntaxNode => SyntaxNodeToText(indent_size=indent_size),
        ListNode   => SyntaxListToText(),
    )
end

# ── Utility ──────────────────────────────────────────────────────────────────

function _indent_span(p::SyntaxNodeToText, depth::Int)
    TextString(" " ^ (depth * p.indent_size))
end

function _newline_span()
    TextString("\n")
end

# Reads leaf.selection[] (.open[k], .value[k], .close[k], or PS variants) and
# converts it to a flat character offset within open ++ value ++ close.
# Returns -1 if the selection does not point to a cursor position inside this leaf.
function _leaf_cursor(leaf::SyntaxLeaf)
    sel = leaf.selection
    sel isa EmptyReferencePath && return -1
    sel isa ConcreteReferencePath || return -1
    h = sel.head
    if h isa FieldReference
        rest = sel.tail
        rest isa ConcreteReferencePath || return -1
        inner = rest.head
        inner isa RangeReference || return -1
        k = inner.start::Int
        fname = h.name
        if fname == "value"
            return length(leaf.open.content) + k
        elseif fname == "open"
            return k
        elseif fname == "close"
            return length(leaf.open.content) + length(leaf.value.content) + k
        end
    elseif h isa ProjectionReference
        inner = h.output_path
        inner isa ConcreteReferencePath || return -1
        field = inner.head
        field isa FieldReference || return -1
        fname = field.name
        rest = inner.tail
        rest isa ConcreteReferencePath || return -1
        idx = rest.head
        idx isa RangeReference || return -1
        k = idx.start::Int
        if fname == "open"
            return k
        elseif fname == "close"
            return length(leaf.open.content) + length(leaf.value.content) + k
        end
    end
    return -1
end

# Maps a SyntaxLeaf-domain path to the flat character offset within the leaf.
# .open[k] → k,  .value[k] → L_o+k,  .close[k] → L_o+L_v+k.  Returns -1 on mismatch.
function _syntax_to_flat(leaf::SyntaxLeaf, path::ReferencePath, ::SyntaxNodeToText, _depth::Int)
    path isa ConcreteReferencePath || return -1
    h = path.head
    h isa FieldReference || return -1
    fname = h.name
    rest = path.tail
    rest isa ConcreteReferencePath || return -1
    k = begin idx = rest.head; idx isa RangeReference ? idx.start::Int : return -1 end
    fname == "open"  && return k
    fname == "value" && return length(leaf.open.content) + k
    fname == "close" && return length(leaf.open.content) + length(leaf.value.content) + k
    return -1
end

# Maps a SyntaxNode-domain path to the flat character offset within the
# rendered node.  Handles .open[k], .close[k], PS (flat pass-through),
# and .children[i] descent (accumulating open + sep/indent offsets).
function _syntax_to_flat(node::SyntaxNode, path::ReferencePath, p::SyntaxNodeToText, depth::Int)
    path isa ConcreteReferencePath || return -1
    h = path.head
    if h isa FieldReference
        fname = h.name
        rest = path.tail
        rest isa ConcreteReferencePath || return -1
        if fname == "open" || fname == "close"
            idx = rest.head
            idx isa RangeReference || return -1
            k = idx.start::Int
            fname == "open"  && return k
            return _subtree_len(node, p, depth) - length(node.close.content) + k
        elseif fname == "children"
            h2 = rest.head
            h2 isa RangeReference || return -1
            child_i = h2.start + 1
            children = node.children
            (1 <= child_i <= length(children)) || return -1
            rest2 = rest.tail
            char_count = length(node.open.content)
            if node.indentation > 0
                child_depth = depth + 1
                for i in 1:child_i
                    i > 1 && (char_count += length(node.sep.content))
                    char_count += 1 + child_depth * p.indent_size
                    if i == child_i
                        f = _syntax_to_flat(children[i], rest2, p, child_depth)
                        f < 0 && return -1
                        return char_count + f
                    end
                    char_count += _subtree_len(children[i], p, child_depth)
                end
            else
                for i in 1:child_i
                    i > 1 && (char_count += length(node.sep.content))
                    if i == child_i
                        f = _syntax_to_flat(children[i], rest2, p, depth)
                        f < 0 && return -1
                        return char_count + f
                    end
                    char_count += _subtree_len(children[i], p, depth)
                end
            end
            return -1
        end
        return -1
    end
    if h isa ProjectionReference
        inner = h.output_path
        inner isa ConcreteReferencePath || return -1
        idx = inner.head
        idx isa RangeReference || return -1
        return idx.start::Int
    end
    return -1
end

function _structural_cursor(node::SyntaxNode, p::SyntaxNodeToText, depth::Int)
    sel = node.selection
    sel === nothing && return -1
    _syntax_to_flat(node, sel, p, depth)
end

function _collect_child_spans(leaf::SyntaxLeaf, p::SyntaxNodeToText, depth::Int, recursion)
    (TextDocument[leaf.open, leaf.value, leaf.close], _leaf_cursor(leaf))
end

function _collect_child_spans(node::SyntaxNode, p::SyntaxNodeToText, depth::Int, recursion)
    spans, cursor, _ = _collect_spans(node, p, depth, recursion)
    (spans, cursor)
end

function _span_len(s::TextString)
    length(s.content::AbstractString)
end

function _collect_spans(node::SyntaxNode, p::SyntaxNodeToText, depth::Int, recursion)
    spans = TextDocument[]
    cursor_offset = -1
    char_count = 0
    children = node.children
    open_str = node.open.content
    indent = node.indentation > 0

    # open delimiter
    push!(spans, node.open)
    char_count += length(open_str)

    child_ranges = UnitRange{Int}[]

    if indent
        child_depth = depth + 1
        for (i, child) in enumerate(children)
            if i > 1
                push!(spans, node.sep)
                char_count += _span_len(node.sep)
            end
            nl = _newline_span()
            push!(spans, nl)
            char_count += 1
            ind = _indent_span(p, child_depth)
            push!(spans, ind)
            char_count += _span_len(ind)

            child_start = char_count
            child_spans, child_cursor = _collect_child_spans(child, p, child_depth, recursion)
            if child_cursor >= 0 && cursor_offset < 0
                cursor_offset = char_count + child_cursor
            end
            for s in child_spans
                push!(spans, s)
                char_count += _span_len(s)
            end
            push!(child_ranges, child_start:char_count-1)
        end
        push!(spans, _newline_span())
        char_count += 1
        ind = _indent_span(p, depth)
        push!(spans, ind)
        char_count += _span_len(ind)
    else
        for (i, child) in enumerate(children)
            if i > 1
                push!(spans, node.sep)
                char_count += _span_len(node.sep)
            end
            child_start = char_count
            child_spans, child_cursor = _collect_child_spans(child, p, depth, recursion)
            if child_cursor >= 0 && cursor_offset < 0
                cursor_offset = char_count + child_cursor
            end
            for s in child_spans
                push!(spans, s)
                char_count += _span_len(s)
            end
            push!(child_ranges, child_start:char_count-1)
        end
    end

    # structural cursor always wins over stale leaf cursors
    sc = _structural_cursor(node, p, depth)
    if sc >= 0
        cursor_offset = sc
    end

    # close delimiter
    push!(spans, node.close)
    return (spans, cursor_offset, child_ranges)
end

function _subtree_len(leaf::SyntaxLeaf, ::SyntaxNodeToText, _depth::Int)
    length(leaf.open.content) + length(leaf.value.content) + length(leaf.close.content)
end

function _subtree_len(node::SyntaxNode, p::SyntaxNodeToText, depth::Int)
    children = node.children
    n = length(node.open.content)
    if node.indentation > 0
        child_depth = depth + 1
        for (i, child) in enumerate(children)
            i > 1 && (n += length(node.sep.content))
            n += 1 + child_depth * p.indent_size          # \n + indent
            n += _subtree_len(child, p, child_depth)
        end
        # Trailing \n + indent emitted by the printer before the close
        # delimiter, regardless of whether children was empty.
        n += 1 + depth * p.indent_size
    else
        for (i, child) in enumerate(children)
            i > 1 && (n += length(node.sep.content))
            n += _subtree_len(child, p, depth)
        end
    end
    n += length(node.close.content)
    return n
end

function _pos_to_selection(leaf::SyntaxLeaf, local_pos::Int, ::SyntaxNodeToText, _depth::Int)
    open_len    = length(leaf.open.content::AbstractString)
    value_len   = length(leaf.value.content::AbstractString)
    close_start = open_len + value_len
    if local_pos < open_len
        @reference open{local_pos}
    elseif local_pos <= close_start
        @reference value{local_pos - open_len}
    else
        @reference close{local_pos - close_start}
    end
end

function _pos_to_selection(node::SyntaxNode, local_pos::Int, p::SyntaxNodeToText, depth::Int)
    _proj(k) = @reference proj(p, {k})

    open_len = length(node.open.content)
    local_pos < open_len && return @reference open{local_pos}

    children = node.children
    char_count = open_len

    if node.indentation > 0
        child_depth = depth + 1
        for (i, child) in enumerate(children)
            if i > 1
                sep_len = length(node.sep.content)
                local_pos < char_count + sep_len && return _proj(local_pos)
                char_count += sep_len
            end
            struct_len = 1 + child_depth * p.indent_size   # \n + indent
            local_pos < char_count + struct_len && return _proj(local_pos)
            char_count += struct_len
            child_len = _subtree_len(child, p, child_depth)
            if char_count <= local_pos <= char_count + child_len
                sel = _pos_to_selection(child, local_pos - char_count, p, child_depth)
                return @reference children[i].^(sel)
            end
            char_count += child_len
        end
        # Trailing \n + indent before close. Always emitted by _collect_spans
        # when indent=true, regardless of whether children was empty.
        trail_len = 1 + depth * p.indent_size
        local_pos < char_count + trail_len && return _proj(local_pos)
        char_count += trail_len
    else
        for (i, child) in enumerate(children)
            if i > 1
                sep_len = length(node.sep.content)
                local_pos < char_count + sep_len && return _proj(local_pos)
                char_count += sep_len
            end
            child_len = _subtree_len(child, p, depth)
            if char_count <= local_pos <= char_count + child_len
                sel = _pos_to_selection(child, local_pos - char_count, p, depth)
                return @reference children[i].^(sel)
            end
            char_count += child_len
        end
    end

    close_len = length(node.close.content)
    local_pos < char_count + close_len && return @reference close{local_pos - char_count}
    return _proj(local_pos)
end

_text_elem_path(span_idx::Int, char_idx::Int) =
    @reference elements[span_idx].content{char_idx}

function _parse_text_elem_path(path)
    path isa ConcreteReferencePath || return (nothing, nothing)
    h1 = path.head
    h1 isa FieldReference && h1.name == "elements" || return (nothing, nothing)
    t1 = path.tail
    t1 isa ConcreteReferencePath || return (nothing, nothing)
    h2 = t1.head
    h2 isa RangeReference || return (nothing, nothing)
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return (nothing, nothing)
    h3 = t2.head
    h3 isa FieldReference && h3.name == "content" || return (nothing, nothing)
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return (nothing, nothing)
    h4 = t3.head
    h4 isa RangeReference || return (nothing, nothing)
    return (span_idx, h4.start::Int)
end

function _flat_to_text_elem_path(spans, flat_pos::Int)
    cumulative = 0
    last_nonempty = nothing  # (span_idx, cumulative_at_start)
    for (i, s) in enumerate(spans)
        len = length((s::TextString).content::AbstractString)
        if len > 0
            last_nonempty = (i, cumulative)
        end
        if flat_pos < cumulative + len
            return _text_elem_path(i, flat_pos - cumulative)
        end
        cumulative += len
    end
    # flat_pos sits at the end of the concatenated content. Anchor it at
    # the end of the last non-empty span so the cursor renderer (which only
    # emits SegCoords for non-empty spans) can place the caret.
    if last_nonempty !== nothing
        i, c = last_nonempty
        return _text_elem_path(i, flat_pos - c)
    end
    return nothing
end

function _text_elem_path_to_flat(spans, span_idx::Int, char_idx::Int)
    span_idx > length(spans) && return -1
    flat = char_idx
    for i in 1:(span_idx - 1)
        flat += length((spans[i]::TextString).content::AbstractString)
    end
    return flat
end

end # module
