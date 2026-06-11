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
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection, Change
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TextModule: TextText, TextString, TextNewline, TextDocument
import ..FontModule: font_ubuntu_monospace_regular_24, font_dejavu_monospace_regular_24
import ..ColorModule: color_solarized_gray
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, EmptyReferencePath, ReferencePath, TextRectangularReference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..IoMapModule: SimpleIoMap
import ..IoMapApiModule: IoMap
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..KeyboardModule: KeyDown
import ..MouseModule: MousePress
export SyntaxLeafToText, SyntaxNodeToText, SyntaxListToText, SyntaxToText,
       SyntaxNodeToTextIoMap, _syntax_to_flat

# ── SyntaxLeafToText ───────────────────────────────────────────────────
# Three spans: open delimiter, value, close delimiter.
# The TextStrings are extracted directly from the leaf, preserving
# whatever font/color was set by the upstream projection.

struct SyntaxLeafToText <: Projection end

function map_reference_forward(::SyntaxLeafToText, iomap, reference)
    @reference_case reference begin
        ∅                          => @reference()
        open{s:_}                  => _text_elem_path(1, s)
        value{s:_}                 => _text_elem_path(2, s)
        close{s:_}                 => _text_elem_path(3, s)
        proj(_, open{s:_})         => _text_elem_path(1, s)
        proj(_, close{s:_})        => _text_elem_path(3, s)
    end
end

function map_reference_backward(::SyntaxLeafToText, iomap, reference)
    reference isa EmptyReferencePath && return @reference()
    # Tree selection path: .elements[i]∅ → select the whole leaf
    _parse_tree_elem_path(reference) !== nothing && return @reference()
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
function projection_print(p::SyntaxLeafToText, recursion, leaf::SyntaxLeaf, ctx)
    sel = Cell(() -> begin
        leaf_sel = leaf.selection
        leaf_sel isa EmptyReferencePath && return @reference()
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

# Translate a TextText-domain `StringReplaceRangeOperation` (referencing
# `.elements[i].content[s:e]`) back to a SyntaxLeaf-domain op (`.value[s:e]`).
# For now only spans the value span (i == 2); editing into the open/close
# delimiter span is deferred — those are typically projection-introduced
# characters that need a different kind of structural edit.
function projection_read(p::SyntaxLeafToText, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    span_idx, char_start, char_stop = parsed
    span_idx == 2 || return nothing
    new_ref = ConcreteReferencePath(FieldReference("value"),
                  ConcreteReferencePath(RangeReference(char_start, char_stop), EmptyReferencePath()))
    StringReplaceRangeOperation(new_ref, op.replacement)
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

# Default rule for which nodes may carry an inline expand/collapse marker:
# any node with at least one child. Projection instances can pass a custom
# `marker_eligible` predicate to restrict this further (e.g. the filesystem
# pipeline marks only directory header nodes, not the indented body wrapper).
_default_marker_eligible(node) = length(node.children) > 0

# Default ellipsis glyph for a collapsed node's body. Uses the DejaVu mono
# font (which carries the … glyph) and a muted gray so the placeholder reads
# as projection chrome rather than content.
_default_ellipsis() = TextString("…", font_dejavu_monospace_regular_24, color_solarized_gray)

struct SyntaxNodeToText <: Projection
    indent_size::Int
    expanded_marker::TextString
    collapsed_marker::TextString
    marker_eligible::Any
    ellipsis_text::TextString
end

SyntaxNodeToText(; indent_size::Int = 2,
                   expanded_marker::TextString = TextString(""),
                   collapsed_marker::TextString = TextString(""),
                   marker_eligible = _default_marker_eligible,
                   ellipsis_text::TextString = _default_ellipsis()) =
    SyntaxNodeToText(indent_size, expanded_marker, collapsed_marker, marker_eligible, ellipsis_text)

struct SyntaxNodeToTextIoMap <: IoMap
    projection::Any
    input::SyntaxNode
    output::TextText
    child_char_ranges::Cell
    # Cell{Int}: index of the inline expand/collapse marker span in
    # `output.elements` (always element 1 when present), or 0 when no marker
    # was emitted. Recorded so the reader can recognise clicks on the marker.
    marker_index::Cell
end

function map_reference_forward(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, reference)
    reference isa EmptyReferencePath && return @reference()
    flat_pos = _syntax_to_flat(iomap.input, reference, p, 0)
    flat_pos < 0 && return nothing
    _flat_to_text_elem_path(iomap.output.elements, flat_pos)
end

function map_reference_backward(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, reference)
    reference isa EmptyReferencePath && return @reference()
    # Also accept bare flat char index: ConcreteReferencePath(PositionReference(n))
    if reference isa ConcreteReferencePath
        h = reference.head
        if h isa RangeReference && reference.tail isa EmptyReferencePath
            return _pos_to_selection(iomap.input, h.start::Int, p, 0)
        end
    end
    # Tree selection path: .elements[i]∅ (no .content{k})
    tree_span = _parse_tree_elem_path(reference)
    if tree_span !== nothing
        flat_pos = _text_elem_path_to_flat(iomap.output.elements, tree_span, 0)
        flat_pos < 0 && return nothing
        return _pos_to_tree_selection(iomap.input, flat_pos, p, 0)
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
function projection_print(p::SyntaxNodeToText, recursion, node::SyntaxNode, ctx)
    both = Cell(() -> _collect_spans(node, p, 0, recursion))
    output = TextText(
        CellVector(() -> both[][1]),
        Cell(() -> begin
            node_sel = node.selection
            node_sel isa EmptyReferencePath && return @reference()
            # Detect nested child whole-element selection (.children[i]…∅)
            # and emit a TextRectangularReference carrying the child's flat range.
            flat_range = node_sel isa ReferencePath ? _syntax_to_flat_range(node, node_sel, p, 0) : nothing
            if flat_range !== nothing
                return ConcreteReferencePath(
                    TextRectangularReference(flat_range[1], flat_range[2]),
                    EmptyReferencePath())
            end
            cursor = both[][2]
            cursor < 0 && return nothing
            _flat_to_text_elem_path(both[][1], cursor)
        end))
    child_ranges = Cell(() -> both[][3])
    marker_idx = Cell(() -> _active_marker(p, node) === nothing ? 0 : 1)
    SyntaxNodeToTextIoMap(p, node, output, child_ranges, marker_idx)
end

# Gesture-aware reader. With the originating gesture in hand, all pointer-driven
# tree behaviour is resolved here — the text/graphics layers below stay dumb and
# emit only a plain character cursor. Two click reinterpretations, keyed off
# `change.gesture isa MousePress` (the Lisp `(typep -gesture- 'gesture/mouse/click)`)
# so keyboard navigation that lands on the same glyph still places the cursor:
#   1. A click on a node's inline marker (either state) or its collapsed ellipsis
#      is a fold gesture → toggle that specific node.
#   2. Alt+click promotes the mapped position to a whole-element (tree) selection
#      on the enclosing node — the mouse half of tree navigation.
function projection_read(p::SyntaxNodeToText, recursion, change::Change, iomap::SyntaxNodeToTextIoMap)
    op = change.operation
    gesture = change.gesture
    if op isa ReplaceSelectionOperation && gesture isa MousePress
        flat = _click_flat_pos(iomap, op.path)
        if flat >= 0
            node = _node_at_collapse_glyph(iomap.input, flat, p, 0)
            node !== nothing && return Change(gesture, ToggleCollapseOperation(node))
            if gesture.modifiers.alt
                tree_sel = _pos_to_tree_selection(iomap.input, flat, p, 0)
                return Change(gesture, ReplaceSelectionOperation(tree_sel))
            end
        end
    end
    # Everything else (keyboard, plain clicks, other operations) falls through to
    # the operation-typed readers below.
    payload = op === nothing ? gesture : op
    return Change(gesture, projection_read(p, iomap, payload))
end

function projection_read(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    return ReplaceSelectionOperation(input_path)
end

# Keyboard fold (`Ctrl+.`): the operation arrives from below carrying no
# target. Resolve it here — where both the syntax tree and its selection are
# in hand — to the innermost collapsible node containing the cursor, then let
# it propagate up unchanged. An already-targeted operation (e.g. a click
# resolved above) passes through untouched.
function projection_read(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, op::ToggleCollapseOperation)
    op.target === nothing || return op
    target = _resolve_collapsible(iomap.input, iomap.input.selection)
    return ToggleCollapseOperation(target)
end

# Tree-selection navigation by keyboard. The raw key event falls through the
# graphics/text layers (TextToGraphics declines alt-modified navigation keys,
# and plain arrows whenever the selection is already structural) and is
# recognised here, where the syntax tree and its selection are in hand — so
# recognition and resolution live in one place and no courier operation is
# needed. The selection on the root node is a path like `.children[i].children[j]…∅`.
# - Ctrl+Alt+Home → select the root node (∅)
# - Ctrl+Space    → toggle structural ⇄ text (character-cursor) mode
# - :up    → drop the last `.children[k]` step (select parent)
# - :down  → append `.children[1]` (select first child)
# - :left  → decrement the last child index
# - :right → increment the last child index
# Arrows require Alt only to *enter* structural mode from a character cursor;
# once a whole element is selected, plain arrows continue node-to-node movement.
function projection_read(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, evt::KeyDown)
    if evt.key === :home && evt.modifiers.ctrl && evt.modifiers.alt
        return ReplaceSelectionOperation(EmptyReferencePath())
    end
    sel = iomap.input.selection
    if evt.key === :space && evt.modifiers.ctrl
        new_path = _is_tree_selection(sel) ? _descend_to_text_cursor(iomap.input, sel) :
                                             _promote_to_structural(sel)
        new_path === nothing && return nothing
        return ReplaceSelectionOperation(new_path)
    end
    evt.key in (:up, :down, :left, :right) || return nothing
    (evt.modifiers.alt || _is_tree_selection(sel)) || return nothing
    new_path = _tree_navigate(iomap.input, sel, evt.key)
    new_path === nothing && return nothing
    ReplaceSelectionOperation(new_path)
end

function _tree_navigate(node::SyntaxNode, sel, direction::Symbol)
    # sel must be a tree selection (path of .children[i] steps ending in ∅)
    sel === nothing && return nothing

    # ∅ on the root node: this node is wholly selected
    if sel isa EmptyReferencePath
        if direction === :up
            return nothing  # no parent at this level; propagate up
        elseif direction === :down
            children = node.children
            length(children) > 0 || return EmptyReferencePath()
            return @reference children[1]
        else
            return nothing  # left/right need a parent; propagate up
        end
    end

    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    h isa FieldReference && h.name == "children" || return nothing
    rest = sel.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    child_idx = h2.start + 1  # 1-based
    children = node.children
    (1 <= child_idx <= length(children)) || return nothing
    child_rest = rest.tail

    if child_rest isa EmptyReferencePath
        # The selected node is children[child_idx]
        if direction === :up
            return EmptyReferencePath()  # select the current node
        elseif direction === :down
            child = children[child_idx]
            if child isa SyntaxNode && length(child.children) > 0
                return @reference children[child_idx].children[1]
            end
            return sel  # leaf or no children — stay
        elseif direction === :left
            child_idx > 1 || return sel  # already first
            return @reference children[child_idx - 1]
        elseif direction === :right
            child_idx < length(children) || return sel  # already last
            return @reference children[child_idx + 1]
        end
    else
        # Recurse into the child
        child = children[child_idx]
        child isa SyntaxNode || return sel
        inner = _tree_navigate(child, child_rest, direction)
        inner === nothing && return nothing
        return ConcreteReferencePath(FieldReference("children"),
                   ConcreteReferencePath(RangeReference(child_idx - 1, child_idx), inner))
    end
    return nothing
end

# A selection is "structural" (a whole-element / tree selection) when it is `∅`
# on the root, or a chain of `.children[i]` steps ending in `∅`. A character
# cursor differs by terminating in a leaf field step (`.value{k}` / `.open{k}`
# / `.close{k}`), which breaks the all-`children` requirement here.
_is_tree_selection(::EmptyReferencePath) = true
function _is_tree_selection(sel)
    sel isa ConcreteReferencePath || return false
    h = sel.head
    h isa FieldReference && h.name == "children" || return false
    t = sel.tail
    t isa ConcreteReferencePath || return false
    t.head isa RangeReference || return false
    _is_tree_selection(t.tail)
end

# Text → structural (Ctrl+Space): promote a character cursor to the whole
# element that contains it. Keep every leading `.children[i]` step and drop the
# trailing leaf-field cursor (`.value{k}` …), appending `∅`. A cursor on the
# root node's own delimiter (no `.children` prefix) promotes to the root (`∅`).
function _promote_to_structural(sel)
    pairs = RangeReference[]
    cur = sel
    while cur isa ConcreteReferencePath
        h = cur.head
        (h isa FieldReference && h.name == "children") || break
        t = cur.tail
        t isa ConcreteReferencePath || break
        h2 = t.head
        h2 isa RangeReference || break
        push!(pairs, h2)
        cur = t.tail
    end
    path = EmptyReferencePath()
    for h2 in Iterators.reverse(pairs)
        path = ConcreteReferencePath(FieldReference("children"),
                   ConcreteReferencePath(h2, path))
    end
    return path
end

# Structural → text (Ctrl+Space): from a whole-element tree selection, walk the
# `.children[i]` path to the selected element, then descend to its first leaf
# and place a character cursor at the start of that leaf's value (`…value{0}`).
# Returns nothing if a node along the way has no children (no leaf to land on).
function _descend_to_text_cursor(node::SyntaxNode, sel)
    indices = Int[]
    cur = node
    p = sel
    while p isa ConcreteReferencePath
        h = p.head
        (h isa FieldReference && h.name == "children") || return nothing
        t = p.tail
        t isa ConcreteReferencePath || return nothing
        h2 = t.head
        h2 isa RangeReference || return nothing
        i = h2.start + 1
        children = cur.children
        (1 <= i <= length(children)) || return nothing
        push!(indices, i)
        cur = children[i]
        p = t.tail
    end
    while cur isa SyntaxNode
        isempty(cur.children) && return nothing
        push!(indices, 1)
        cur = cur.children[1]
    end
    cur isa SyntaxLeaf || return nothing
    path = ConcreteReferencePath(FieldReference("value"),
               ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
    for i in Iterators.reverse(indices)
        path = ConcreteReferencePath(FieldReference("children"),
                   ConcreteReferencePath(RangeReference(i - 1, i), path))
    end
    return path
end

# Translate a flat-text `StringReplaceRangeOperation` to a SyntaxNode-domain
# op rooted at the enclosing leaf. The start and stop offsets are mapped via
# `_text_elem_path_to_flat` and `_pos_to_selection`; if both endpoints don't
# resolve to the same leaf's `.value` field, the op is rejected.
function projection_read(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, op::StringReplaceRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    span_idx, char_start, char_stop = parsed
    spans = iomap.output.elements
    flat_start = _text_elem_path_to_flat(spans, span_idx, char_start)
    flat_stop  = _text_elem_path_to_flat(spans, span_idx, char_stop)
    (flat_start < 0 || flat_stop < 0) && return nothing

    # Input-selection disambiguation. The collision between, say, an empty
    # opening delimiter and the start of the content is a real layout ambiguity
    # that the flat offset cannot resolve (and must not be resolved by carrying
    # span identity downstream — a later projection may coalesce the spans). But
    # for a zero-width insert the edit target is exactly wherever the cursor sits,
    # and the cursor's source-of-truth is the *input-domain* selection that was
    # set. When that selection names a concrete string slot
    # (`.open`/`.value`/`.close`/`.sep`, possibly under `.children[i]`) whose flat
    # position matches the edit, edit that slot directly. The on-screen caret may
    # still sit at the visually-identical collapsed pixel; only the edit is
    # disambiguated. This costs nothing in the unambiguous case (the input
    # selection then already equals what the flat mapping would produce).
    if flat_start == flat_stop
        sel = iomap.input.selection
        if sel isa ConcreteReferencePath && _ends_in_field_range(sel) &&
           _syntax_to_flat(iomap.input, sel, p, 0) == flat_start
            return StringReplaceRangeOperation(sel, op.replacement)
        end
    end

    start_sel = _pos_to_selection(iomap.input, flat_start, p, 0)
    stop_sel  = _pos_to_selection(iomap.input, flat_stop,  p, 0)
    new_ref = _join_leaf_range(start_sel, stop_sel)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# True iff `path` ends in `.<field>[range]` — the shape a
# StringReplaceRangeOperation reference must have for `_split_replace_reference`.
function _ends_in_field_range(path)
    path isa ConcreteReferencePath || return false
    penult = nothing
    cur = path
    while cur.tail isa ConcreteReferencePath
        penult = cur.head
        cur = cur.tail
    end
    penult isa FieldReference && cur.head isa RangeReference
end

# Given two SyntaxNode-domain selection paths whose tails are `.value[k]`
# inside the same leaf, build a single replace-range path whose tail is
# `.value[s:e]`. Returns `nothing` if they don't share the same leaf or the
# terminal field isn't `value`.
function _join_leaf_range(start_path, stop_path)
    (start_path === nothing || stop_path === nothing) && return nothing
    start_path isa ConcreteReferencePath || return nothing
    stop_path  isa ConcreteReferencePath || return nothing
    h_start = start_path.head
    h_stop  = stop_path.head
    if h_start isa FieldReference && h_stop isa FieldReference
        h_start.name == h_stop.name || return nothing
        if h_start.name == "value"
            t_start = start_path.tail
            t_stop  = stop_path.tail
            t_start isa ConcreteReferencePath || return nothing
            t_stop  isa ConcreteReferencePath || return nothing
            r_start = t_start.head
            r_stop  = t_stop.head
            (r_start isa RangeReference && r_stop isa RangeReference) || return nothing
            return ConcreteReferencePath(FieldReference("value"),
                ConcreteReferencePath(RangeReference(r_start.start::Int, r_stop.start::Int), EmptyReferencePath()))
        else
            # `children` field: recurse into the matching child index.
            inner = _join_leaf_range(start_path.tail, stop_path.tail)
            inner === nothing && return nothing
            return ConcreteReferencePath(h_start, inner)
        end
    elseif h_start isa RangeReference && h_stop isa RangeReference
        h_start == h_stop || return nothing
        inner = _join_leaf_range(start_path.tail, stop_path.tail)
        inner === nothing && return nothing
        return ConcreteReferencePath(h_start, inner)
    end
    nothing
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
    projection_print(::SyntaxListToText, recursion, ln::ListNode, ctx)

Convert a `ListNode(SyntaxDocument)` to a `TextText` with `ListNode` elements.
Each syntax element becomes its text spans (open, value, close for leaves),
with `TextNewline` separators between elements.
"""
function projection_print(p::SyntaxListToText, recursion, ln::ListNode, ctx)
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

function SyntaxToText(; indent_size::Int = 2,
                        expanded_marker::TextString = TextString(""),
                        collapsed_marker::TextString = TextString(""),
                        marker_eligible = _default_marker_eligible,
                        ellipsis_text::TextString = _default_ellipsis())
    TypeDispatchingProjection(
        SyntaxLeaf => SyntaxLeafToText(),
        SyntaxNode => SyntaxNodeToText(indent_size=indent_size,
                                       expanded_marker=expanded_marker,
                                       collapsed_marker=collapsed_marker,
                                       marker_eligible=marker_eligible,
                                       ellipsis_text=ellipsis_text),
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

# The optional inline expand/collapse marker rendered immediately before the
# open delimiter, in BOTH the expanded and collapsed states. Which glyph is
# shown depends on `node.collapsed`:
#   !collapsed → p.expanded_marker   (e.g. "▾")
#    collapsed → p.collapsed_marker  (e.g. "▸")
# An empty configured marker (the default `TextString("")`) means "no marker":
# no span is emitted and no offset is introduced, so callers that don't opt in
# see byte-for-byte identical output. Nodes the projection's `marker_eligible`
# predicate rejects (by default, empty nodes) never get a marker — the fold
# gesture would have nothing to act on.
function _active_marker(p::SyntaxNodeToText, node::SyntaxNode)
    p.marker_eligible(node) || return nothing
    m = node.collapsed ? p.collapsed_marker : p.expanded_marker
    isempty(m.content::AbstractString) ? nothing : m
end

# Character length of the active marker, or 0 when none is emitted. Every
# offset in the rendered node is shifted right by this amount.
function _marker_len(p::SyntaxNodeToText, node::SyntaxNode)
    m = _active_marker(p, node)
    m === nothing ? 0 : length(m.content::AbstractString)
end

# Character length of the collapsed-body placeholder (the ellipsis), or 0 for
# a childless node — there is nothing to stand in for, so a collapsed empty
# node renders as bare `<open><close>`. Only meaningful when `node.collapsed`.
function _ellipsis_len(p::SyntaxNodeToText, node::SyntaxNode)
    length(node.children) > 0 ? length(p.ellipsis_text.content::AbstractString) : 0
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
            fname == "open"  && return _marker_len(p, node) + k
            return _subtree_len(node, p, depth) - length(node.close.content) + k
        elseif fname == "sep"
            # The separator renders between every pair of children; the cursor is
            # placed at its first occurrence (after child 1, before child 2).
            idx = rest.head
            idx isa RangeReference || return -1
            k = idx.start::Int
            node.collapsed && return -1
            children = node.children
            length(children) >= 2 || return -1
            char_count = _marker_len(p, node) + length(node.open.content)
            if node.indentation > 0
                child_depth = depth + 1
                char_count += 1 + child_depth * p.indent_size
                char_count += _subtree_len(children[1], p, child_depth)
            else
                char_count += _subtree_len(children[1], p, depth)
            end
            return char_count + k
        elseif fname == "children"
            # A collapsed node lays out no children, so a `.children[i]…`
            # input reference has no image in the rendered text.
            node.collapsed && return -1
            h2 = rest.head
            h2 isa RangeReference || return -1
            child_i = h2.start + 1
            children = node.children
            (1 <= child_i <= length(children)) || return -1
            rest2 = rest.tail
            char_count = _marker_len(p, node) + length(node.open.content)
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

# ── Flat range for whole-element selections ──────────────────────────────
# Like _syntax_to_flat but returns the (start, stop) character range when
# the path terminates in ∅ (a whole-element selection). Returns nothing
# when the path is a normal cursor or doesn't match.

function _syntax_to_flat_range(leaf::SyntaxLeaf, ::EmptyReferencePath, p::SyntaxNodeToText, depth::Int)
    (0, _subtree_len(leaf, p, depth))
end

function _syntax_to_flat_range(leaf::SyntaxLeaf, ::ConcreteReferencePath, ::SyntaxNodeToText, ::Int)
    nothing
end

function _syntax_to_flat_range(node::SyntaxNode, ::EmptyReferencePath, p::SyntaxNodeToText, depth::Int)
    (0, _subtree_len(node, p, depth))
end

function _syntax_to_flat_range(node::SyntaxNode, path::ConcreteReferencePath, p::SyntaxNodeToText, depth::Int)
    h = path.head
    h isa FieldReference || return nothing
    h.name == "children" || return nothing
    node.collapsed && return nothing
    rest = path.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    child_i = h2.start + 1
    children = node.children
    (1 <= child_i <= length(children)) || return nothing
    rest2 = rest.tail

    # Accumulate the flat offset up to child_i
    char_count = _marker_len(p, node) + length(node.open.content)
    if node.indentation > 0
        child_depth = depth + 1
        for i in 1:child_i
            i > 1 && (char_count += length(node.sep.content))
            char_count += 1 + child_depth * p.indent_size
            if i == child_i
                inner = _syntax_to_flat_range(children[i], rest2, p, child_depth)
                inner === nothing && return nothing
                return (char_count + inner[1], char_count + inner[2])
            end
            char_count += _subtree_len(children[i], p, child_depth)
        end
    else
        for i in 1:child_i
            i > 1 && (char_count += length(node.sep.content))
            if i == child_i
                inner = _syntax_to_flat_range(children[i], rest2, p, depth)
                inner === nothing && return nothing
                return (char_count + inner[1], char_count + inner[2])
            end
            char_count += _subtree_len(children[i], p, depth)
        end
    end
    return nothing
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

    # optional inline expand/collapse marker, before the open delimiter
    marker = _active_marker(p, node)
    if marker !== nothing
        push!(spans, marker)
        char_count += _span_len(marker)
    end

    # open delimiter
    push!(spans, node.open)
    char_count += length(open_str)

    child_ranges = UnitRange{Int}[]

    if node.collapsed
        # Collapsed body: a single ellipsis glyph stands in for the children,
        # which are not laid out at all (their reactive subtree is pruned —
        # editing inside a collapsed node triggers no re-render here). A
        # childless node gets no ellipsis (nothing to fold).
        if length(children) > 0
            push!(spans, p.ellipsis_text)
            char_count += _span_len(p.ellipsis_text)
        end
    elseif node.indentation > 0
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
    n = _marker_len(p, node) + length(node.open.content)
    if node.collapsed
        n += _ellipsis_len(p, node)
    elseif node.indentation > 0
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

# ── Tree selection (Alt+click) ─────────────────────────────────────────────
# Like _pos_to_selection but returns ∅ at leaves (whole-element selection on
# the innermost node). Structural positions (newlines, indentation, sep)
# select the nearest child.

_pos_to_tree_selection(::SyntaxLeaf, _pos::Int, ::SyntaxNodeToText, _depth::Int) = EmptyReferencePath()

function _pos_to_tree_selection(node::SyntaxNode, local_pos::Int, p::SyntaxNodeToText, depth::Int)
    marker_len = _marker_len(p, node)
    local_pos < marker_len && return EmptyReferencePath()

    open_len = length(node.open.content)
    local_pos < marker_len + open_len && return EmptyReferencePath()

    children = node.children
    char_count = marker_len + open_len

    if node.collapsed
        return EmptyReferencePath()
    end

    if node.indentation > 0
        child_depth = depth + 1
        for (i, child) in enumerate(children)
            if i > 1
                sep_len = length(node.sep.content)
                char_count += sep_len
            end
            struct_len = 1 + child_depth * p.indent_size
            char_count += struct_len
            child_len = _subtree_len(child, p, child_depth)
            if char_count <= local_pos < char_count + child_len
                sel = _pos_to_tree_selection(child, local_pos - char_count, p, child_depth)
                return @reference children[i].^(sel)
            end
            char_count += child_len
        end
    else
        for (i, child) in enumerate(children)
            if i > 1
                sep_len = length(node.sep.content)
                char_count += sep_len
            end
            child_len = _subtree_len(child, p, depth)
            if char_count <= local_pos < char_count + child_len
                sel = _pos_to_tree_selection(child, local_pos - char_count, p, depth)
                return @reference children[i].^(sel)
            end
            char_count += child_len
        end
    end

    # close delimiter or trailing structural — select the node itself
    return EmptyReferencePath()
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

    # A position inside the leading marker has no source-domain coordinate;
    # report it as a projection-introduced position. Everything from the open
    # delimiter onwards is the existing layout shifted right by the marker.
    marker_len = _marker_len(p, node)
    local_pos < marker_len && return _proj(local_pos)

    open_len = length(node.open.content)
    local_pos < marker_len + open_len && return @reference open{local_pos - marker_len}

    children = node.children
    char_count = marker_len + open_len

    if node.collapsed
        # Collapsed layout: marker, open, ellipsis, close. The ellipsis is a
        # projection-introduced glyph with no source-domain coordinate.
        ell_len = _ellipsis_len(p, node)
        local_pos < char_count + ell_len && return _proj(local_pos)
        char_count += ell_len
        close_len = length(node.close.content)
        local_pos < char_count + close_len && return @reference close{local_pos - char_count}
        return _proj(local_pos)
    end

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

# ── Collapse hit-testing and resolution ──────────────────────────────────────

# Walk the rendered layout to the SyntaxNode whose inline expand/collapse
# marker — or, when that node is collapsed, its ellipsis glyph — occupies the
# flat character offset `local_pos`. Returns `nothing` when the position is on
# ordinary content/delimiters. The offset arithmetic mirrors `_pos_to_selection`.
_node_at_collapse_glyph(::SyntaxLeaf, _local_pos::Int, ::SyntaxNodeToText, _depth::Int) = nothing

function _node_at_collapse_glyph(node::SyntaxNode, local_pos::Int, p::SyntaxNodeToText, depth::Int)
    marker_len = _marker_len(p, node)
    # The marker occupies [0, marker_len) and toggles this node in either state.
    local_pos < marker_len && return node

    open_len = length(node.open.content)
    char_count = marker_len + open_len

    if node.collapsed
        # Clicking the ellipsis expands the node; no children are rendered to
        # descend into.
        ell_len = _ellipsis_len(p, node)
        (char_count <= local_pos < char_count + ell_len) && return node
        return nothing
    end

    children = node.children
    if node.indentation > 0
        child_depth = depth + 1
        for (i, child) in enumerate(children)
            i > 1 && (char_count += length(node.sep.content))
            char_count += 1 + child_depth * p.indent_size   # \n + indent
            child_len = _subtree_len(child, p, child_depth)
            if char_count <= local_pos <= char_count + child_len
                return _node_at_collapse_glyph(child, local_pos - char_count, p, child_depth)
            end
            char_count += child_len
        end
    else
        for (i, child) in enumerate(children)
            i > 1 && (char_count += length(node.sep.content))
            child_len = _subtree_len(child, p, depth)
            if char_count <= local_pos <= char_count + child_len
                return _node_at_collapse_glyph(child, local_pos - char_count, p, depth)
            end
            char_count += child_len
        end
    end
    return nothing
end

# Innermost SyntaxNode along `path` (a selection rooted at `node`). Descends
# through `.children[i]` steps as long as the child is itself a SyntaxNode,
# stopping at the first leaf or non-child step. With no usable path the root
# node is returned. This is the keyboard fold target: the most deeply nested
# node that still contains the cursor — matching every editor's fold gesture.
function _resolve_collapsible(node::SyntaxNode, path)
    best = node
    cur = node
    p = path
    while p isa ConcreteReferencePath
        h = p.head
        (h isa FieldReference && h.name == "children") || break
        t = p.tail
        t isa ConcreteReferencePath || break
        idx = t.head
        idx isa RangeReference || break
        i = idx.start + 1
        children = cur.children
        (1 <= i <= length(children)) || break
        child = children[i]
        child isa SyntaxNode || break
        best = child
        cur = child
        p = t.tail
    end
    best
end

# Flat character offset a click resolved to, or -1. Accepts the
# `.elements[i].content{c}` shape produced by `TextToGraphics` and the bare
# flat `{n}` shape, mirroring `map_reference_backward`.
function _click_flat_pos(iomap::SyntaxNodeToTextIoMap, path)
    if path isa ConcreteReferencePath
        h = path.head
        if h isa RangeReference && path.tail isa EmptyReferencePath
            return h.start::Int
        end
    end
    span_idx, char_idx = _parse_text_elem_path(path)
    span_idx === nothing && return -1
    _text_elem_path_to_flat(iomap.output.elements, span_idx, char_idx)
end

_text_elem_path(span_idx::Int, char_idx::Int) =
    @reference elements[span_idx].content{char_idx}

# Parse a tree selection path: .elements[i]∅  (element ref without .content{k}).
# Returns span_idx (1-based) or nothing.
function _parse_tree_elem_path(path)
    path isa ConcreteReferencePath || return nothing
    h1 = path.head
    h1 isa FieldReference && h1.name == "elements" || return nothing
    t1 = path.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    t1.tail isa EmptyReferencePath || return nothing
    return h2.start + 1
end

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

# Like `_parse_text_elem_path` but returns the full `(span_idx, char_start,
# char_stop)` of the terminal `RangeReference`. Returns `nothing` on mismatch.
function _parse_text_elem_range(path)
    path isa ConcreteReferencePath || return nothing
    h1 = path.head
    (h1 isa FieldReference && h1.name == "elements") || return nothing
    t1 = path.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return nothing
    h3 = t2.head
    (h3 isa FieldReference && h3.name == "content") || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return nothing
    h4 = t3.head
    h4 isa RangeReference || return nothing
    return (span_idx, h4.start::Int, h4.stop::Int)
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
