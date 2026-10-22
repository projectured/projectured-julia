# Fragment of `SyntaxModule`.
#
# Syntax → Text projection. Each `SyntaxNode` transforms only its own single level —
# marker, delimiters, separators, lines and indentation — and projects every child
# one level down through `recursion` (`print_child`), joining the child's output
# lines into its own (School A; see the recursion contract in
# package/kernel/doc/projection-system.md). The output is a block of `TextLine`s. The
# per-child entry ranges and the child IoMaps are recorded in the IoMap so the
# mappers and reader can peel the one `.children[i]` step this node owns and
# delegate the rest to the child's own mapper.
# ── SyntaxLeafToText ───────────────────────────────────────────────────
# The texts of the fields the leaf actually has, in order: a delimited leaf
# renders open, value and close, a bare one just its value. An absent delimiter
# (`nothing`) emits no span, so it offers no cursor position either — `.open{k}` on
# a leaf without an opening delimiter addresses nothing and the mappers decline it.
#
# A `TextString` is one run, so the leaf never reads its content to find a break,
# and an edit of the run leaves the line valid. A `TextBlock` is lines: its first
# line joins the line before it, and each other line starts a line of the output,
# a line of the chrome, so a value of many lines follows the indentation of the code
# around it.
#
# The mappers count in the flat text of the fields, open ++ value ++ close, whose
# offsets are the flat offsets of the output: the break between two lines of a
# block counts one, as it does in the output.
#
# The TextStrings are extracted directly from the leaf, preserving
# whatever font/color was set by the upstream projection.

struct SyntaxLeafToText <: Projection end

# The leaf's rendered spans, in order, skipping absent delimiters.
_leaf_spans(leaf::SyntaxLeaf) =
    TextDocument[s for s in (leaf.open, leaf.value, leaf.close) if s !== nothing]

# The leaf's rendered fields, in span order — the index of a field in this list
# is the index of its span on the line.
_leaf_fields(leaf::SyntaxLeaf) =
    Symbol[f for (f, s) in ((:open, leaf.open), (:value, leaf.value), (:close, leaf.close))
           if s !== nothing]

# The index of the span of a leaf field on the line, or 0 when that delimiter is
# absent.
function _leaf_span_index(leaf::SyntaxLeaf, field::Symbol)
    i = findfirst(==(field), _leaf_fields(leaf))
    i === nothing ? 0 : i
end

# The field rendered at span index `idx`, or `nothing` when out of range.
function _leaf_field_at(leaf::SyntaxLeaf, idx::Int)
    fields = _leaf_fields(leaf)
    (1 <= idx <= length(fields)) ? fields[idx] : nothing
end

# A cursor into a leaf field, or `nothing` when the leaf has no such delimiter.
function _leaf_elem_path(leaf::SyntaxLeaf, field::Symbol, char_idx::Int)
    i = _leaf_span_index(leaf, field)
    i == 0 && return nothing
    flat = _text_elem_path_to_flat(_leaf_spans(leaf), i, char_idx)
    flat < 0 ? nothing : _flat_text_path(flat)
end

function map_reference_forward(::SyntaxLeafToText, iomap, reference)
    leaf = iomap.input
    @reference_case reference begin
        ∅                          => @reference()
        ::SyntaxLeaf.open{s:_}     => _leaf_elem_path(leaf, :open, s)
        ::SyntaxLeaf.value{s:_}    => _leaf_elem_path(leaf, :value, s)
        ::SyntaxLeaf.close{s:_}    => _leaf_elem_path(leaf, :close, s)
    end
end

function map_reference_backward(::SyntaxLeafToText, iomap, reference)
    reference = strip_reference_types(reference)   # selections are canonical (checkpointed)
    reference isa EmptyReference && return @reference()
    _is_flat_text_range(reference) && return nothing
    # A whole span of a line selects the whole leaf.
    _parse_tree_span_path(reference) !== nothing && return @reference()
    spans = _leaf_spans(iomap.input)
    flat = _compute_output_flat(iomap.output, reference)
    flat === nothing && return nothing
    loc = _flat_to_span_char(spans, flat)
    loc === nothing && return nothing
    span_idx, char_idx = loc
    leaf = iomap.input
    field = _leaf_field_at(leaf, span_idx)
    # Prefer content over the projection's own closing delimiter at the value/close
    # seam: a caret at the *start* of the close span is the same visual position as
    # the *end* of the value, and the editable one is the value (typing there extends
    # the string). Without this a delimited leaf's value-end caret — every string's
    # last cursor, and an empty `""`'s only one — is unreachable, shadowed by
    # `close{0}`. Mirrors the open→value redirect in the `ReplaceStringRangeOperation`
    # reader below.
    if field === :close && char_idx == 0 && leaf.value !== nothing
        field = :value
        char_idx = _span_len(leaf.value)
    end
    field === :open  && return @reference(leaf, open{char_idx})
    field === :value && return @reference(leaf, value{char_idx})
    field === :close && return @reference(leaf, close{char_idx})
    return nothing
end

# The lines of a leaf: the lines of the texts of its fields in order, the first
# line of each text joined to the line before it.
function _make_leaf_lines(leaf::SyntaxLeaf)
    lines = [TextDocument[]]
    for text in _leaf_spans(leaf)
        for (k, runs) in enumerate(_get_text_lines(text))
            k > 1 && push!(lines, TextDocument[])
            append!(lines[end], runs)
        end
    end
    TextLine[TextLine(runs) for runs in lines]
end

# The field of the leaf and the flat offset in it of span `k` of line `i` of the
# output, or `nothing`.
function _find_leaf_piece(leaf::SyntaxLeaf, i::Int, k::Int)
    line, position = 1, 0
    for (field, text) in zip(_leaf_fields(leaf), _leaf_spans(leaf))
        offset = 0
        for (n, runs) in enumerate(_get_text_lines(text))
            if n > 1
                line += 1
                position = 0
                offset += 1
            end
            for run in runs
                position += 1
                (line == i && position == k) && return (field, offset)
                offset += get_flat_length(run)
            end
        end
    end
    nothing
end

# Selection mapping (SyntaxLeaf → TextBlock of lines): leaf.selection[] is
# translated to a flat caret over the text of the fields the leaf renders, in order
# (an absent delimiter renders nothing):
#   .open[k]       →  the open span   (only if the leaf has an opening delimiter)
#   .value[k]      →  the value span
#   .close[k]      →  the close span  (only if the leaf has a closing delimiter)
#   anything else  →  no cursor
function print_document(p::SyntaxLeafToText, recursion, leaf::SyntaxLeaf, ctx)
    # The state travels with the image: a dormant selection maps forward as a
    # dormant one, so the painter downstream can draw it pale.
    paths = make_output_path_cells(leaf, path -> begin
        leaf_path = strip_reference_types(path)            # canonical → plain skeleton
        leaf_path isa EmptyReference && return @reference()
        c = _leaf_cursor(leaf, leaf_path)
        c < 0 ? nothing : _flat_text_path(c)
    end)
    SimpleIoMap(p, leaf, TextBlock(CellVector(@computation _make_leaf_lines(leaf)),
                                   paths.selection, paths.mouse_target))
end

function read_intent(p::SyntaxLeafToText, iomap::SimpleIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    return make_path_operation(op, input_path)
end

# Gesture-aware reader, the leaf half of what `SyntaxCompoundToText` does for a
# node. Alt+click promotes the click to a whole-element (tree) selection on the
# leaf — the same rule `_resolve_click` applies to a leaf child of a compound.
#
# A leaf needs its own copy of the rule, because a leaf is not always printed
# under a compound. A tab holding one placeholder, a scalar example, any
# single-leaf projection: there the compound resolver never runs, and without
# this method nothing resolved the leaf's clicks at all. Alt+click was silently
# ignored and the click stayed a character cursor.
#
# Everything else falls through exactly as the generic 4-arg bridge does, so
# keyboard navigation that lands on the same glyph still places the cursor.
function read_intent(p::SyntaxLeafToText, recursion, change::Intent, iomap::SimpleIoMap)
    op = change.operation
    gesture = change.gesture
    # The edit beside an inline image writes the element list of the output, which
    # has no pre-image in the syntax: decline it.
    is_text_element_write(op) && return Intent(gesture, nothing)
    if op isa ReplaceSelectionOperation && gesture isa MouseClick && gesture.modifiers.alt
        return Intent(gesture,
                      ReplaceSelectionOperation(EmptyReference(get_reference_node_type(iomap.input))))
    end
    payload = op === nothing ? gesture : op
    Intent(gesture, read_intent(p, iomap, payload))
end

# Translate a TextBlock-domain `ReplaceStringRangeOperation` (referencing
# `.elements[i].elements[k].content[s:e]`, characters of span `k` of line `i`) back
# to a SyntaxLeaf-domain op on the edited span's field. An edit on ANY present span
# — `.open` / `.value` / `.close` — maps to that field: the syntax domain owns all of
# its own text. The `.value` edit maps on through to the input document; an `.open` /
# `.close` edit is a projection-introduced delimiter, which the downstream domain
# projection defers (no document pre-image; see the introduced-output branch in
# `ReaderDefaults`), so the key falls through to the structural gesture. Which field
# a span of a line shows, and where in it, depends on the delimiters and the breaks
# of the leaf, so ask the leaf.
function read_intent(p::SyntaxLeafToText, iomap::SimpleIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_span_range(op.reference)
    parsed === nothing && return nothing
    span_path, char_start, char_stop = parsed
    length(span_path) == 2 || return nothing
    leaf = iomap.input
    piece = _find_leaf_piece(leaf, span_path[1], span_path[2])
    piece === nothing && return nothing
    field, offset = piece
    char_start += offset
    char_stop += offset
    # Prefer content over the projection's own delimiters. An insertion (a zero-width
    # edit) sitting on the boundary between the opening delimiter and the value belongs
    # to the value, even when the value is empty. The lowering counts a boundary offset
    # to the earlier span's end, so a caret at `value{0}` arrives here as an insert at
    # the end of the `open` span; mapping that to the introduced `open` delimiter would
    # decline it, and an empty delimited leaf (a fresh `""` string) offers *only* that
    # caret — so its first character could never be typed. Redirect it into `value{0}`.
    if field === :open && char_start == char_stop && leaf.value !== nothing &&
       char_start == _span_len(leaf.open)
        field = :value
        char_start = char_stop = 0
    end
    # A char range over the text of the field lands on no document node (a text
    # selection, like a cursor) — spell the node types so the reference is fully typed:
    # `::SyntaxLeaf.<field>::TextString[s:e]::Position`, or `::TextBlock` for a field
    # of lines, whose range is a range of its flat text.
    new_ref = ConcreteReference(SyntaxLeaf, FieldReferenceStep(String(field)),
                  ConcreteReference(_get_text_type(getproperty(leaf, field)),
                      RangeReferenceStep(char_start, char_stop),
                      EmptyReference(Position)))
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# A flat text edit: an edit of a break, which a text stage leaves flat, or any edit
# in a pipeline with no `TextToGraphics` (the console). Its range in the flat text of
# the fields, whose offsets are those of the output, names the field that holds it:
# the value first at a seam, as the redirect above does. A field that holds an
# image takes no string edit, and a field of one run takes no break (rule 1 of the
# text domain), so Enter there falls to the key bindings around the text.
function read_intent(p::SyntaxLeafToText, iomap::SimpleIoMap, op::ReplaceTextRangeOperation)
    r = strip_reference_types(op.reference)
    (r isa ConcreteReference && r.head isa TextRangeReferenceStep && r.tail isa EmptyReference) ||
        return nothing
    leaf = iomap.input
    place = _find_leaf_field_range(leaf, r.head.start::Int, r.head.stop::Int)
    place === nothing && return nothing
    field, start, stop = place
    value = getproperty(leaf, field)
    value isa TextGraphics && return nothing
    (value isa TextString && occursin('\n', op.replacement)) && return nothing
    ReplaceStringRangeOperation(
        ConcreteReference(SyntaxLeaf, FieldReferenceStep(String(field)),
            ConcreteReference(_get_text_type(value), RangeReferenceStep(start, stop), EmptyReference(Position))),
        op.replacement)
end

# The field of `leaf` whose flat text holds the range `start:stop` of the flat text
# of the fields, with the range in it, the value first at a seam; or `nothing`.
function _find_leaf_field_range(leaf::SyntaxLeaf, start::Int, stop::Int)
    places = Tuple{Symbol,Int,Int}[]
    base = 0
    for (field, text) in zip(_leaf_fields(leaf), _leaf_spans(leaf))
        len = _span_len(text)
        (base <= start && stop <= base + len) && push!(places, (field, start - base, stop - base))
        base += len
    end
    isempty(places) && return nothing
    places[something(findfirst(place -> place[1] === :value, places), 1)]
end

# A KeyDown on a leaf first offers itself to the Syntax domain's reified leaf gesture
# table (`@gestures SyntaxLeaf` — Ctrl+Space toggles text⇄structural selection, Ctrl+Alt+Home
# selects the whole leaf). Whatever the table declines falls back to the raw event, so
# upstream projections (e.g. PrimitiveStringToSyntaxLeaf) still see Backspace/Delete and
# TextToGraphics still gets the untouched KeyDown for keys nothing consumes. This mirrors
# `SyntaxCompoundToText`'s KeyDown reader and is what gives every domain the selection-mode
# toggle for free through the backward selection map.
function read_intent(p::SyntaxLeafToText, iomap::SimpleIoMap, evt::KeyDown)
    op = read_gesture(iomap.input, evt)
    op === nothing ? evt : op
end

# ── SyntaxCompoundToText ───────────────────────────────────────────────
# A node renders `open child₁ sep child₂ … close`. A break is in the texts: with
# `open = "[\n"`, `sep = ",\n"`, `close = "\n]"` and `indentation = 1`, each child is
# on a line of its own one level in, and the `]` is on a line at the level of the
# node. A node whose texts hold no break is inline; its `indentation` still moves
# the lines that breaks inside its children start.
# Each child is projected one level down via `print_child(recursion, child, …)`
# and its output lines are joined in — this node never walks the subtree by
# type (School A). Reading node.children registers it as a dependency of the
# `child_iomaps` cell, so structural changes trigger a re-splice.

# Default rule for which nodes may carry an inline expand/collapse marker:
# any node with at least one child. Projection instances can pass a custom
# `marker_eligible` predicate to restrict this further (e.g. the filesystem
# pipeline marks only directory header nodes, not the indented body wrapper).
_default_marker_eligible(node) = length(get_syntax_children(node)) > 0

# One projection prints every compound. What varies between compounds is what the
# *document* has — delimiters, a separator, indentation, a collapsed flag — and the
# document answers that itself (the compound contract, in `Syntax.jl`). What the
# projection supplies is only *configuration*: how wide an indent is, which glyphs
# mark a fold, what stands in for a collapsed body. None of that differs per
# compound type, so none of it justifies a projection per compound type — that
# would be this file's mappers and readers copied out once per wrapper.
struct SyntaxCompoundToText <: Projection
    indent_size::Int
    expanded_marker::TextString
    collapsed_marker::TextString
    marker_eligible::Any
    # The style of the ellipsis that stands in for a folded node's children: a
    # value, or a cell that reads the scaled `SyntaxTheme` (`unwrap_cell`).
    ellipsis_style::Any
    # The font of the indentation and the line breaks of a node with no delimiter
    # of its own: a value, or a cell that reads the scaled `SyntaxTheme`.
    decoration_font::Any
    # The kind of fold of the view. `false`: a collapsed node prints no children and
    # an ellipsis stands for them. `true`: a node always prints its children, and a
    # collapsible node that indents and takes more than one line gives its first
    # line a `TextFold`, which shares the `collapsed` cell of the node, so
    # `TextFolding` hides its lines and the numbers still count them.
    text_folds::Bool
end

SyntaxCompoundToText(; indent_size::Int = 2,
                       expanded_marker::TextString = TextString(""),
                       collapsed_marker::TextString = TextString(""),
                       marker_eligible = _default_marker_eligible,
                       theme = nothing,
                       ellipsis_style = get_syntax_style(theme, :ellipsis_text),
                       decoration_font = get_syntax_style(theme, :font),
                       text_folds::Bool = false) =
    SyntaxCompoundToText(indent_size, expanded_marker, collapsed_marker, marker_eligible,
                         ellipsis_style, decoration_font, text_folds)

# Whether the syntax folds `node`: it is collapsed and the view has no text folds.
# Such a node prints no children.
_is_folded_by_syntax(p::SyntaxCompoundToText, node::SyntaxCompound) =
    !p.text_folds && is_syntax_collapsed(node)

# One IoMap for every compound, and it must be one: a parent reads the lines of
# the chrome and the flat list of its child off the child's IoMap
# (`_splice_child!`). A compound with an IoMap of its own type would be invisible
# to that read, and no line beneath it would be widened.
#
# Every index below is an entry of `flat_elements`, the flat list of the output:
# each span of each line in order, with the break and the indentation of each line
# after the first. Its offsets are the flat offsets of the output.
@iomap struct SyntaxCompoundToTextIoMap
    projection::Any
    input::SyntaxCompound
    output::TextBlock
    # Cell{Vector{IoMap}}: one IoMap per (expanded) child, in order — the result
    # of `print_child`-ing each `node.children[i]`. Empty when collapsed. Storing
    # them lets the mappers/reader peel the one `.children[i]` step this projection
    # owns and delegate the tail to the child's own mapper (School A).
    child_iomaps::Cell
    # Cell{Vector{Any}}: the flat list of the output.
    flat_elements::Cell
    # Cell{Vector{UnitRange{Int}}}: 1-based inclusive range of entries that each
    # child's lines occupy (parallel to child_iomaps).
    child_elem_ranges::Cell
    # Cell{Vector{Bool}}: for each line of the output, whether its indentation is of
    # the chrome of a compound, this one or one below it. A compound that indents
    # widens exactly these lines of its children.
    chrome_lines::Cell
    # Cell{Int}: the entry of the inline expand/collapse marker (always entry 1
    # when present), or 0 when no marker was emitted. Recorded so the reader can
    # recognise clicks on the marker.
    marker_index::Cell
    # Cell{Int}: the entry of the ellipsis of a collapsed node, or 0.
    ellipsis_index::Cell
    # Cell{Vector{Pair{Int,Tuple{Symbol,Int}}}}: each entry of a delimiter span that
    # this compound emitted, a piece or a break, as entry => (the DOCUMENT FIELD it
    # came from, the offset of the entry in the span). Recorded by the printer rather
    # than inferred, because with optional delimiters no position identifies them
    # (the open span is not necessarily `marker_index + 1`, the close span not
    # necessarily the last entry) — and because the field name is the compound's
    # own: `SyntaxNode` says `open`, another compound may say something else. A
    # caret in one of these maps straight back to `.<field>{k}`.
    own_spans::Cell
    # Cell{Vector{Pair{Int,Int}}}: each entry of each separator span, in order, as
    # entry => the offset of the entry in the span (empty when the compound has no
    # separator, or fewer than two children). Kept apart from `own_spans` because a
    # separator is NOT backward-addressable — see `_push_separator!`.
    sep_indices::Cell
end

# ── Reference mapping (School A: own level + child delegation) ────────────
# Both directions own exactly the one level this node lays out — marker/open/
# close/sep/break/indentation/ellipsis chrome — and delegate anything inside a
# child to that child's *own* mapper via the stored `child_iomaps`, shifting between
# the flat list of the child's output and the flat list of this node's output. A
# parent speaks to a child in the language of the child's output: a flat caret, a
# whole span of a line, or characters of such a span. No projection ever
# re-walks the input subtree by type.

_rr_start(x) = x isa RangeReferenceStep ? x.start::Int : nothing

# Shift a child's forward *cursor* image into this node's flat space: map the
# entry of the child's flat list to its entry in this node's list, and take the
# flat offset there. It reads *this* node's entries, whose indentations of the
# chrome are widened, so the widening is accounted for. Whole-element (∅) images
# are handled separately via entry ranges (`_child_elem_range`), never by adding a
# child-local flat.
function _shift_child_cursor(inner, child_elements, elements, range::UnitRange{Int})
    child_flat = _text_side_flat(inner)
    child_flat === nothing && return nothing
    loc = _flat_to_span_char(child_elements, child_flat)
    loc === nothing && return nothing
    span_idx, char_idx = loc
    pf = _text_elem_path_to_flat(elements, range.start + span_idx - 1, char_idx)
    pf < 0 && return nothing
    _flat_text_path(pf)
end

# Entry range (in `iomap.flat_elements`) covered by a whole-element
# (∅-terminating, children-only) sub-path under child `child_i`. Recurses through
# nested `.children[j]` steps, shifting each level's child range by its splice
# base — so the final flat, taken from *this* node's entries (with widened
# indentations), is correct even for indented descendants. `nothing` when the tail is a cursor
# path (ends in a field position) rather than a whole element, or descends into a
# non-node child.
function _child_elem_range(iomap::SyntaxCompoundToTextIoMap, child_i::Int, tail)
    ranges = iomap.child_elem_ranges
    (1 <= child_i <= length(ranges)) || return nothing
    base = ranges[child_i]
    tail isa EmptyReference && return base
    step = peel_child_step(tail)
    step === nothing && return nothing
    gj, gtail = step
    cim = get_content_iomap(iomap.child_iomaps[child_i])
    cim isa SyntaxCompoundToTextIoMap || return nothing
    sub = _child_elem_range(cim, gj, gtail)
    sub === nothing && return nothing
    offset = base.start - 1
    return (sub.start + offset):(sub.stop + offset)
end

# The entries of the delimiter the compound rendered for field `fname`, each with its
# offset in the flat text of the delimiter, or none when it has no such delimiter —
# in which case that field addresses no span, and so offers no cursor position.
_find_own_places(iomap::SyntaxCompoundToTextIoMap, fname::AbstractString) =
    Pair{Int,Int}[i => offset for (i, (field, offset)) in iomap.own_spans if String(field) == fname]

# The entries of the first separator, after child 1: the separator renders the same
# entries between each pair of children.
function _find_first_separator_places(iomap::SyntaxCompoundToTextIoMap)
    seps = iomap.sep_indices
    gaps = max(1, length(iomap.child_iomaps) - 1)
    seps[1:(length(seps) ÷ gaps)]
end

# The flat caret at offset `k` of a text of the compound whose entries are `places`:
# in the last entry that starts at or before `k`. Just after a break the caret stands
# after the indentation of the line, at the first character of the line.
function _anchor_text_offset(elements, places, k::Int)
    isempty(places) && return nothing
    j, offset = first(places)
    for (entry, entry_offset) in places
        entry_offset <= k || break
        j, offset = entry, entry_offset
    end
    # An offset in a line that the node does not print stands at the nearest end of
    # the entry. Past the end of the output an offset is kept, as the backward map
    # gives it there.
    char = max(k - offset, 0)
    length_of_entry = _span_len(elements[j])
    (char > length_of_entry && any(n -> _span_len(elements[n]) > 0, (j + 1):length(elements))) &&
        (char = length_of_entry)
    flat = _text_elem_path_to_flat(elements, j, char)
    flat < 0 && return nothing
    (elements[j] isa _LineBreak && char >= 1 && j < length(elements) &&
     elements[j + 1] isa _LineIndentation) && (flat += _span_len(elements[j + 1]))
    _flat_text_path(flat)
end

# The document field the delimiter entry `j` came from and the offset of the entry
# in the span, or `nothing` when `j` is not an entry of this compound's delimiters.
function _own_field(iomap::SyntaxCompoundToTextIoMap, j::Int)
    for (i, own) in iomap.own_spans
        i == j && return own
    end
    nothing
end

function map_reference_forward(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, reference)
    reference = strip_reference_types(reference)   # selections are canonical (checkpointed)
    reference isa EmptyReference && return @reference()     # whole node
    reference isa ConcreteReference || return nothing
    elements = iomap.flat_elements
    node = iomap.input
    h = reference.head
    if h isa ProjectionReferenceStep
        # A part that this projection printed: its step holds a flat offset in this
        # node's own text. The step of another projection is for that projection to
        # take off before the path reaches here. The check is by type, because each
        # instance of this projection holds text markers of its own.
        h.projection isa SyntaxCompoundToText || return nothing
        inner = h.output_path
        (inner isa ConcreteReference && inner.head isa RangeReferenceStep &&
         inner.tail isa EmptyReference) || return nothing
        return _flat_text_path(inner.head.start::Int)
    end
    h isa FieldReferenceStep || return nothing
    # A step into a child — `.children[i]` or `.content`, whichever this compound uses.
    step = peel_child_step(reference)
    if step !== nothing
        _is_folded_by_syntax(p, node) && return nothing   # a node that the syntax folds lays out no children
        child_i, ctail = step
        cims = iomap.child_iomaps
        (1 <= child_i <= length(cims)) || return nothing
        # Whole-element (∅-terminating) selection → a parent-flat rectangle over
        # the child subtree's spliced (widened) spans.
        rng = _child_elem_range(iomap, child_i, ctail)
        if rng !== nothing
            s = _text_elem_path_to_flat(elements, rng.start, 0)
            s < 0 && return nothing
            e = s + sum(_span_len(elements[j]) for j in rng; init = 0)
            return ConcreteReference(TextSpanReferenceStep(s, e), EmptyReference())
        end
        # Cursor → delegate to the child's own mapper, then re-anchor at parent flat.
        child = cims[child_i]
        inner = map_reference_forward(child.projection, child, ctail)
        inner === nothing && return nothing
        return _shift_child_cursor(inner, _compute_flat_entries(child), elements, iomap.child_elem_ranges[child_i])
    end
    rest = reference.tail
    rest isa ConcreteReference || return nothing
    fname = h.name
    k = _rr_start(rest.head); k === nothing && return nothing
    # The separator renders between every pair of children; a cursor on it is placed
    # at the first occurrence (right after child 1).
    separator = get_separator(node)
    if separator !== nothing && fname == String(separator.first)
        return _anchor_text_offset(elements, _find_first_separator_places(iomap), k)
    end
    # A delimiter, wherever the printer put it. A compound that has no such
    # delimiter rendered no span for it, so the field addresses nothing.
    return _anchor_text_offset(elements, _find_own_places(iomap, fname), k)
end

# The step from `doc` into its `i`-th child — `.children[i]` for a sequence, `.content`
# for a wrapper. The compound answers; this file does not care which it is.
_prepend_child(doc::SyntaxCompound, i::Int, inner) = build_syntax_child_path(doc, i, inner)

# A cursor in one of this compound's own delimiter spans: `.<field>{c}`.
_own_span_path(doc::SyntaxCompound, field::Symbol, c::Int) =
    ConcreteReference(get_reference_node_type(doc), FieldReferenceStep(String(field)),
        ConcreteReference(_get_text_type(getproperty(doc, field)), RangeReferenceStep(c, c),
                          EmptyReference(Position)))

# The type that a range of the text of a field names: `TextBlock` for lines, whose
# range is a range of its flat text.
_get_text_type(::TextBlock) = TextBlock
_get_text_type(_) = TextString

function map_reference_backward(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, reference)
    reference = strip_reference_types(reference)   # selections are canonical (checkpointed)
    reference isa EmptyReference && return @reference()     # whole node
    _is_flat_text_range(reference) && return nothing
    elements = iomap.flat_elements
    # Whole span of a line (tree) selection `.elements[i].elements[k]∅`.
    tree_path = _parse_tree_span_path(reference)
    if tree_path !== nothing
        tree_j = _find_span_entry(elements, tree_path[1], tree_path[2])
        return tree_j === nothing ? nothing : _backward_zone(p, iomap, tree_j, nothing)
    end
    # Flat text caret (`TextRangeReferenceStep{f}`, bare `{f}`, or a caret in a span
    # of a line) → the entry `(span, char)` it lands on, then classify by zone.
    flat = _compute_output_flat(iomap.output, reference)
    flat === nothing && return nothing
    loc = _flat_to_span_char(elements, flat)
    loc === nothing && return nothing
    _backward_zone(p, iomap, loc[1], loc[2])
end

# Classify entry `j` of the flat list into a zone and produce the source-domain
# selection.
# `char === nothing` means a whole-element (∅) query; otherwise a cursor at `char`.
#   child zone i → delegate the (shifted) sub-reference to child i's mapper and
#                  prepend `.children[i]`;
#   open / close → `.open{c}` / `.close{c}` (whole element on own chrome → ∅);
#   any other own chrome (marker, break, indentation, sep, ellipsis) → a
#                  projection-introduced position `proj(p, {node-local flat})`.
function _backward_zone(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, j::Int, char)
    elements = iomap.flat_elements
    node = iomap.input
    (1 <= j <= length(elements)) || return nothing
    ranges = iomap.child_elem_ranges
    for (i, r) in enumerate(ranges)
        if j in r
            # An indentation is pure whitespace chrome, at *this* level's widened
            # width. Its interior carets have no counterpart in the child's own,
            # narrower indentation — the widening is chrome this level added — so
            # delegating there re-flattens over the un-widened entries and collapses
            # the caret onto the following delimiter. Let a caret in an indentation
            # fall through to a projection-introduced position here instead, which
            # round-trips (its forward image is just this flat). ∅ (whole-element)
            # queries still delegate: they select the child subtree, not a caret in
            # the chrome.
            char !== nothing && elements[j] isa _LineIndentation && break
            cim = iomap.child_iomaps[i]
            child_local = j - r.start + 1
            child_elements = _compute_flat_entries(cim)
            if char === nothing
                span_path = _find_entry_span_path(child_elements, child_local)
                span_path === nothing && return nothing
                sub = _make_span_path(span_path, EmptyReference())
            else
                sub = _flat_text_path(_text_elem_path_to_flat(child_elements, child_local, char::Int))
            end
            inner = map_reference_backward(cim.projection, cim, sub)
            inner === nothing && return nothing
            return _prepend_child(node, i, inner)
        end
    end
    char === nothing && return @reference()        # whole element on own chrome → whole node
    c = char::Int
    # A delimiter span, wherever the printer recorded it and whatever the compound
    # calls it — a compound may have neither, in which case no element maps back to a
    # delimiter at all. Separators are deliberately absent from `own_spans` and fall
    # through to the projection-introduced position below (see `_push_separator!`).
    own = _own_field(iomap, j)
    own !== nothing && return _own_span_path(node, own[1], own[2] + c)
    flat = _text_elem_path_to_flat(elements, j, c)
    return make_introduced_reference(p, node,
               ConcreteReference(Position, PositionReferenceStep(flat), EmptyReference(Position)))
end

# Renders `marker? open`, children interleaved with `sep`, then `close`, joining
# the lines of each child; the breaks are in the texts. The
# output selection is composed by `_compose_node_selection` (forward-mapping
# node.selection, then a first-descendant-cursor fallback). See those functions.
function print_document(p::SyntaxCompoundToText, recursion, node::SyntaxCompound, ctx)
    # Per-projection decorative cache (no module-global state): reused across
    # re-layouts so a structural edit keeps the identity of every unchanged ellipsis,
    # lit delimiter and line. Evict slots not seen this pass so the cache cannot grow
    # unbounded.
    deco = _DecoCache()

    # Delegate every child one level down through `recursion` (never re-walk the
    # subtree by type). An identity cache keyed on the child *object* reuses a
    # child's IoMap across sibling inserts — the input nodes are identity-stable
    # (the template engine reconciles them), so an unchanged subtree keeps its
    # output objects for downstream reuse (printer locality). A collapsed node
    # projects no children (its reactive subtree is pruned).
    child_cache = IdDict{Any, IoMap}()
    child_iomaps = Cell(@computation begin
        _is_folded_by_syntax(p, node) && return IoMap[]
        kids = get_syntax_children(node)
        result = IoMap[]
        for (i, child) in enumerate(kids)
            child_ctx = make_child_context(ctx, node, (@reference_step children), (@reference_step [i]))
            push!(result, get!(() -> print_child(recursion, child, child_ctx), child_cache, child))
        end
        seen = Set{UInt}(objectid(c) for c in kids)
        for k in collect(keys(child_cache))
            objectid(k) in seen || delete!(child_cache, k)
        end
        result
    end)

    # Own chrome interleaved with the lines of each child. Returns the lines and the
    # tables of `_splice_result`. This cell reads only syntax content and
    # `child_iomaps` — never any selection cell — so the output element vector is
    # stable across caret moves (spans-stability property); the separate selection
    # cell below is what recomputes on a caret move.
    # With text folds, the fold of a collapsible node, made once: the splice puts it
    # on the first line, and its count of lines and its placeholder read the splice.
    fold = Ref{Any}(nothing)
    spans = Cell(@computation begin
        empty!(deco.seen)
        res = _splice_compound(node, p, deco, child_iomaps[], fold[])
        for k in collect(keys(deco.spans))
            k in deco.seen || delete!(deco.spans, k)
        end
        res
    end)
    (p.text_folds && is_syntax_collapsible(node)) && (fold[] = _make_node_fold(p, node, spans))

    # The selection cell forward-maps through this projection's own mapper, so it
    # needs the finished IoMap. Build the IoMap after the output but let the
    # selection thunk close over a cell that is filled in below (the standard
    # forward-reference break, as in CollectionToSyntax/BookToSyntax).
    iomap_cell = Cell(nothing)
    output = TextBlock(
        CellVector(@computation spans[].elements),
        # The bit rides from input to output. `map_selection_forward` hands the
        # stored path to the composer and gives the image back carrying the node's
        # own live/dormant state, so a dormant caret stays dormant all the way to
        # the Text domain, where the painter turns it into a pale colour.
        # `map_missing`: case 4 of the composer promotes a *child's* caret when the
        # node holds no selection of its own, so this hop must map an absent one too.
        Cell(@computation(map_selection_forward(node,
            path -> _compose_node_selection(node, p, iomap_cell[], child_iomaps[], path);
            map_missing = true))),
        # The part under the pointer needs no promotion from a child: the chain write
        # gives this node the whole path, so the forward map alone places it.
        Cell(@computation(map_mouse_target_forward(node,
            path -> _map_node_path_forward(p, iomap_cell[], path)))))

    iomap = SyntaxCompoundToTextIoMap(p, node, output,
        child_iomaps,
        Cell(@computation spans[].flat_elements),
        Cell(@computation spans[].child_elem_ranges),
        Cell(@computation spans[].chrome_lines),
        Cell(@computation spans[].marker_index),
        Cell(@computation spans[].ellipsis_index),
        Cell(@computation spans[].own_spans),
        Cell(@computation spans[].sep_indices))
    iomap_cell[] = iomap
    iomap
end

# ── Lines ─────────────────────────────────────────────────────────────────────
#
# Syntax text is a block of `TextLine`s. A text of a field that is a block of lines
# gives its lines, and a run is one run: no run holds a break. The break before a
# line counts one flat offset, as the `'\n'` does, so the flat offsets of the lines
# are the offsets of the flat text of the fields.

# One line under construction: its spans, its indentation, and whether the
# indentation is of the chrome. A compound widens such a line of a child by its own
# `indentation × indent_size`. Each line of a leaf after its first is of the chrome,
# so a value of many lines follows the code around it.
mutable struct _LineRecord
    spans::Vector{TextDocument}
    indentation::Int
    is_chrome::Bool
    fold::Any      # the `TextFold` that starts at the line, or `nothing`
end

_LineRecord(spans::Vector{TextDocument}, indentation::Int, is_chrome::Bool) =
    _LineRecord(spans, indentation, is_chrome, nothing)

_make_first_line_record() = _LineRecord(TextDocument[], 0, false)

# An entry of the flat list of an output that is no span: the break before a line
# after the first, and the indentation of such a line. The flat list of an output
# holds each span of each line in order, and before each line after the first its
# break and its indentation, so its offsets are the flat offsets of the output.
struct _LineBreak end
struct _LineIndentation
    width::Int
end

const _LINE_BREAK = _LineBreak()

_span_len(::_LineBreak) = 1
_span_len(indentation::_LineIndentation) = indentation.width

_is_empty_run(run) = run isa TextString && isempty(run.content::AbstractString)

# The lines of an output, one record for each `TextLine`. `chrome_lines`, when
# given, tells which lines are of the chrome.
function _compute_output_lines(block::TextBlock, chrome_lines = nothing)
    lines = _LineRecord[]
    for (k, line) in enumerate(block.elements)
        is_chrome = chrome_lines !== nothing && k <= length(chrome_lines) && chrome_lines[k]
        push!(lines, _LineRecord(collect(TextDocument, line.elements), line.indentation, is_chrome, line.fold))
    end
    isempty(lines) && push!(lines, _make_first_line_record())
    lines
end

# The flat list of `lines`.
function _build_flat_entries(lines::Vector{_LineRecord})
    entries = Any[]
    for (i, line) in enumerate(lines)
        if i > 1
            push!(entries, _LINE_BREAK)
            push!(entries, _LineIndentation(line.indentation))
        end
        append!(entries, line.spans)
    end
    entries
end

# The flat list of the output of a child: the one its IO map keeps, or the one of
# its output lines.
function _compute_flat_entries(iomap)
    content = get_content_iomap(iomap)
    content isa SyntaxCompoundToTextIoMap && return content.flat_elements
    _build_flat_entries(_compute_output_lines(iomap.output))
end

# The lines of the output of a child, with the lines of the chrome marked: those
# that a compound recorded, or each line of a leaf after its first.
function _compute_child_lines(iomap)
    content = get_content_iomap(iomap)
    chrome_lines = content isa SyntaxCompoundToTextIoMap ? content.chrome_lines :
                   content.projection isa SyntaxLeafToText ? _make_leaf_chrome_lines(iomap.output) :
                   nothing
    _compute_output_lines(iomap.output, chrome_lines)
end

_make_leaf_chrome_lines(output::TextBlock) = Bool[k > 1 for k in eachindex(output.elements)]

# The `TextLine` of `line`, the same object as the last layout when its spans and
# its indentation are the same.
function _make_output_line(deco, line::_LineRecord)
    key = (:line, line.indentation, objectid(line.fold), map(objectid, line.spans)...)
    _deco_span(deco, key, () -> TextLine(line.spans; indentation = line.indentation, fold = line.fold))
end

# The entry of span `k` of line `i` in the flat list `entries`, or `nothing`.
function _find_span_entry(entries, i::Int, k::Int)
    line, position = 1, 0
    for (j, entry) in enumerate(entries)
        if entry isa _LineBreak
            line += 1
            position = 0
        elseif !(entry isa _LineIndentation) && line == i
            position += 1
            position == k && return j
        end
        line > i && return nothing
    end
    nothing
end

# The span path `[i, k]` of entry `j` of `entries`, or `nothing` for a break or an
# indentation.
function _find_entry_span_path(entries, j::Int)
    (1 <= j <= length(entries)) || return nothing
    entries[j] isa Union{_LineBreak, _LineIndentation} && return nothing
    line, position = 1, 0
    for n in 1:j
        entry = entries[n]
        if entry isa _LineBreak
            line += 1
            position = 0
        elseif !(entry isa _LineIndentation)
            position += 1
        end
    end
    Int[line, position]
end

# ── The shared splice core ───────────────────────────────────────────────────
#
# Own chrome (marker, open, sep, line breaks and indentation, ellipsis, close) is
# emitted at **relative depth 0**; the lines of each child are joined in: the first
# line of the child joins the open line, the last line of the child is the open
# line after it, and a parent widens every line of the chrome of the child by its
# `indentation × indent_size`. Summed over ancestors this gives each line the
# indentation of the nodes around it.
#
# A compound lays out up to five separable things at once: a collapse marker, a
# pair of delimiters, a separator between children, lines and indentation, and the
# children's own lines joined in. Those five are exactly what the `Syntax` wrapper
# documents (`SyntaxCollapsible`, `SyntaxDelimitation`, `SyntaxSeparation`,
# `SyntaxIndentation`, `SyntaxConcatenation`) each own on their own.
#
# So the layout is written once, here, as operations on a `SpliceBuffer`: the
# lines under construction plus everything the reference mappers need to know
# about where each span ended up in the flat list of the output. A `SyntaxNode`
# composes all five; a `SyntaxConcatenation` composes none of them. Nothing is
# inferred from a span's position — with optional delimiters no position
# identifies the open span (it is not necessarily `marker_index + 1`) or the close
# span (not necessarily the last entry), so every operation *records* what it
# appended.

mutable struct SpliceBuffer
    lines::Vector{_LineRecord}            # the last line is the open line
    count::Int                            # the entries of the flat list so far
    child_elem_ranges::Vector{UnitRange{Int}}
    own_spans::Vector{Pair{Int,Tuple{Symbol,Int}}}  # entry => (document field, offset in the span)
    sep_indices::Vector{Pair{Int,Int}}    # each entry of each separator => its offset in the span
    marker_index::Int
    ellipsis_index::Int
    deco::Any                             # decorative reuse cache (see _DecoCache)
    nid::UInt                             # structural-slot key prefix for deco objects
    deco_font::StyleFont                  # the ellipsis tracks the content font
    indent_size::Int
end

SpliceBuffer(deco; nid::UInt, deco_font::StyleFont, indent_size::Int) =
    SpliceBuffer([_make_first_line_record()], 0, UnitRange{Int}[], Pair{Int,Tuple{Symbol,Int}}[],
                 Pair{Int,Int}[], 0, 0, deco, nid, deco_font, indent_size)

# Append one span to the open line, and return its entry.
function _push_entry_span!(buf::SpliceBuffer, span)
    push!(buf.lines[end].spans, span)
    buf.count += 1
end

# Open a new line, and return the entry of its break; the entry of its indentation
# follows.
function _start_line!(buf::SpliceBuffer, indentation::Int, is_chrome::Bool)
    push!(buf.lines, _LineRecord(TextDocument[], indentation, is_chrome))
    buf.count += 2
    buf.count - 1
end

# Append a text, and return each of its entries with the offset of the entry in the
# flat text, a run or a break. A block appends its lines: the runs of its first line
# join the open line, and each break starts a line of the chrome at
# `break_indentation`. An empty run of a block is not appended: chrome that draws
# no character offers no caret of its own. An absent text appends nothing and has no entry, so it
# carries no cursor position either.
#
# `part` is `:all`, or `:first` or `:last` for only the runs of the first or of the
# last line of the text, with no break.
function _push_span!(buf::SpliceBuffer, span, break_indentation::Int = 0, part::Symbol = :all)
    span === nothing && return Pair{Int,Int}[]
    places = Pair{Int,Int}[]
    if span isa TextBlock
        lines = _get_text_lines(span)
        offset = 0
        for (n, runs) in enumerate(lines)
            if n > 1
                part === :all && push!(places, _start_line!(buf, break_indentation, true) => offset)
                offset += 1
            end
            shown = _is_line_shown(part, n, length(lines))
            for run in runs
                (shown && !_is_empty_run(run)) && push!(places, _push_entry_span!(buf, run) => offset)
                offset += get_flat_length(run)
            end
        end
        return places
    end
    # A run is one entry on the open line.
    push!(places, _push_entry_span!(buf, span) => 0)
    places
end

# Whether line `n` of a text of `count` lines is in `part`.
_is_line_shown(part::Symbol, n::Int, count::Int) =
    part === :all || (part === :first && n == 1) || (part === :last && n == count)

# A delimiter, given as the `field => span` pair the compound answered. Recorded
# against its DOCUMENT FIELD, not its position, so the mappers can hand a caret in
# it straight back as `.<field>{k}` without knowing what this compound calls its
# delimiters. A compound with no such delimiter answers `nothing` and emits nothing.
_push_delimiter!(::SpliceBuffer, ::Nothing, ::Int, ::Symbol) = nothing
function _push_delimiter!(buf::SpliceBuffer, pair::Pair{Symbol,<:Any}, break_indentation::Int, part::Symbol)
    for (j, offset) in _push_span!(buf, pair.second, break_indentation, part)
        push!(buf.own_spans, j => (pair.first, offset))
    end
end

# The separator, between two children (never before the first).
#
# Deliberately NOT recorded in `own_spans`: one `sep` field renders n-1 spans, so a
# caret in one of them names no single document position and must not map back to
# `.sep{k}` — an edit there would change every separator at once, which the document
# cannot express. Separators map backward as projection-introduced chrome; the
# forward direction still resolves `.sep{k}` onto the first of them (see the mapper).
_push_separator!(::SpliceBuffer, ::Nothing, ::Int) = nothing
function _push_separator!(buf::SpliceBuffer, pair::Pair{Symbol,<:Any}, break_indentation::Int)
    append!(buf.sep_indices, _push_span!(buf, pair.second, break_indentation))
end

# The collapse marker, ahead of everything else.
function _push_marker!(buf::SpliceBuffer, marker)
    places = _push_span!(buf, marker)
    isempty(places) || (buf.marker_index = first(places[1]))
end

# The glyph that stands in for a collapsed node's (un-projected) children. The
# printer and the offset count read it both, so they agree on its length.
const _ELLIPSIS = "…"

# The ellipsis standing in for a collapsed node's (un-projected) children.
function _push_ellipsis!(buf::SpliceBuffer, style::StyleText)
    size = buf.deco_font.size
    places = _push_span!(buf, _deco_span(buf.deco, (buf.nid, 0, :ellipsis),
        () -> TextString(_ELLIPSIS, with_font_size(style.font, size), style.color)))
    buf.ellipsis_index = first(places[1])
end

# Join one child's lines into this buffer: its first line joins the open line, and
# each other line follows, widened by `widen` when it is of the chrome. The open line
# keeps its fold, and takes the fold of the first line of the child when it has
# none. Records the entry range the child occupies.
function _splice_child!(buf::SpliceBuffer, cim, widen::Int)
    base = buf.count + 1
    for (k, line) in enumerate(_compute_child_lines(cim))
        if k > 1
            indentation = line.is_chrome ? line.indentation + widen : line.indentation
            _start_line!(buf, indentation, line.is_chrome)
        end
        open_line = buf.lines[end]
        open_line.fold === nothing && (open_line.fold = line.fold)
        for span in line.spans
            _push_entry_span!(buf, span)
        end
    end
    rng = base:buf.count
    push!(buf.child_elem_ranges, rng)
    rng
end

# What the printer hands to the IoMap.
function _splice_result(buf::SpliceBuffer)
    lines = buf.lines
    (elements = TextLine[_make_output_line(buf.deco, line) for line in lines],
     flat_elements = _build_flat_entries(lines),
     chrome_lines = Bool[line.is_chrome for line in lines],
     child_elem_ranges = buf.child_elem_ranges, own_spans = buf.own_spans,
     sep_indices = buf.sep_indices, marker_index = buf.marker_index,
     ellipsis_index = buf.ellipsis_index)
end

# Every compound is laid out by this one function, because every compound *is*
# some subset of the same five jobs. It asks the document what it has — an opening
# delimiter? a separator? indentation? — and emits exactly that. A `SyntaxNode`
# answers all five; a `SyntaxConcatenation` answers only "children", and so renders
# as its children, end to end, with no chrome and no caret that is not a child's.
#
# A break of the layout is text: a delimiter or the separator that is a block of
# lines. A line that a break in the opening delimiter or in the separator starts is
# inside the node, at `indentation × indent_size` from the line of the node; a line
# that a break in the closing delimiter starts is at the line of the node. These are
# lines of the chrome, and the node moves each line of the chrome that a break
# inside a child starts by `indentation × indent_size` too, as the `nest` of a
# pretty printer does. The line a child starts on stays where the break before it
# put it, so a node with no break of its own, such as `SyntaxIndentation`, indents
# only the lines inside its content.
#
# The breaks frame the children. A node that shows no child, because it has none or
# the syntax folds it, prints only the first line of its opening delimiter and the
# last line of its closing delimiter, so it reads `[]` or `[…]` on one line.
function _splice_compound(doc::SyntaxCompound, p::SyntaxCompoundToText, deco, cims, fold)
    buf = SpliceBuffer(deco; nid = objectid(doc), deco_font = _deco_font(doc, unwrap_cell(p.decoration_font)),
                       indent_size = p.indent_size)
    indent = get_indentation(doc)
    separator = get_separator(doc)
    inside = indent * buf.indent_size
    shows_child = !isempty(cims)

    _push_marker!(buf, _active_marker(p, doc))       # collapse marker, before the open delimiter
    _push_delimiter!(buf, get_opening_delimiter(doc), inside, shows_child ? :all : :first)

    if _is_folded_by_syntax(p, doc)
        # A collapsed node projects no children; a single ellipsis stands in for
        # them. A childless node gets none.
        length(get_syntax_children(doc)) > 0 && _push_ellipsis!(buf, unwrap_cell(p.ellipsis_style))
    else
        for (i, cim) in enumerate(cims)
            i > 1 && _push_separator!(buf, separator, inside)
            _splice_child!(buf, cim, inside)
        end
    end

    _push_delimiter!(buf, get_closing_delimiter(doc), 0, shows_child ? :all : :last)
    # The fold of the node on its first line, in place of a fold of a child that
    # starts there: the region of the outer node wins. Only a node that puts its
    # children on lines of their own is a region of lines; an inline node, such as
    # the entry of an object, leaves the line to the fold of its value.
    (fold !== nothing && length(buf.lines) > 1 && indent != 0 && p.marker_eligible(doc)) &&
        (buf.lines[1].fold = fold)
    _splice_result(buf)
end

# The `TextFold` of a collapsible node with text folds: it shares the `collapsed`
# cell of the node, which a `ToggleCollapseOperation` flips; it holds the lines of
# the node after the first; and its placeholder is the ellipsis and the closing
# delimiter of the node, so a closed node shows `{…}` on its first line.
function _make_node_fold(p::SyntaxCompoundToText, node::SyntaxCompound, spans::Cell)
    style = unwrap_cell(p.ellipsis_style)
    size = _deco_font(node, unwrap_cell(p.decoration_font)).size
    ellipsis = TextString(_ELLIPSIS, with_font_size(style.font, size), style.color)
    line_count = Cell(@computation length(spans[].elements) - 1)
    placeholder = Cell(@computation CellVector{TextDocument}(TextDocument[ellipsis, _find_closing_spans(node, spans[])...]))
    TextFold(line_count, getfield(node, :collapsed), placeholder, Cell(nothing))
end

# The spans that draw the closing delimiter of `node` in the result of its splice.
function _find_closing_spans(node::SyntaxCompound, result)
    closing = get_closing_delimiter(node)
    closing === nothing && return TextDocument[]
    TextDocument[result.flat_elements[j] for (j, (field, _)) in result.own_spans
                 if field === closing.first && result.flat_elements[j] isa TextDocument]
end

# Whitespace decorations track the content's font, because TextToGraphics measures
# every span and takes the line's max — a decoration carrying a stale default font
# would pin the line height when the content font shrinks. A node's own delimiter
# is the source; a node with none takes `fallback`, the decoration font of the
# syntax theme.
#
# Deliberately does NOT consult the children: reading a child's spans here would
# force its output cells during the parent's splice, making the printer eager
# where it is meant to be lazy.
function _deco_font(node::SyntaxCompound, fallback::StyleFont)
    for d in (get_opening_delimiter(node), get_separator(node), get_closing_delimiter(node))
        d === nothing && continue
        font = _find_text_font(d.second)
        font === nothing || return font
    end
    fallback
end

# The font of a text: of a run, or of the first run of a block that draws a
# character, or `nothing`. A break alone gives no font.
_find_text_font(text::TextString) = text.font
function _find_text_font(text::TextBlock)
    for runs in _get_text_lines(text), run in runs
        (run isa TextString && !_is_empty_run(run)) && return run.font
    end
    nothing
end
_find_text_font(_) = nothing

# The output TextBlock cursor, composed from this node's own selection and its
# children's composed selections (Settled decision 5). Precedence, structural
# wins: (1) node.selection ∅ → whole-node highlight; (2)/(3) forward-map
# node.selection through this projection's own mapper — a path ending in ∅ under
# `.children[i]…` becomes a `TextSpanReferenceStep`, a cursor path an element
# path; (4) otherwise the first child whose composed selection is a plain cursor
# element path, shifted by its splice base — a child returning ∅ or a TextRect is
# skipped, not promoted; (5) none.
# The image of a path of the node itself: the whole node, or the forward map. These
# are cases 1 to 3 of `_compose_node_selection`, without the promotion of a child's
# caret.
function _map_node_path_forward(p::SyntaxCompoundToText, iomap, path)
    iomap === nothing && return nothing
    node_path = strip_reference_types(path)
    node_path isa EmptyReference && return @reference()
    node_path isa Reference ? map_reference_forward(p, iomap, node_path) : nothing
end

function _compose_node_selection(node::SyntaxCompound, p::SyntaxCompoundToText, iomap, cims,
                                selection = node.selection)
    iomap === nothing && return nothing
    node_sel = strip_reference_types(selection)          # canonical → plain skeleton
    node_sel isa EmptyReference && return @reference()                    # case 1
    if node_sel isa Reference
        fwd = map_reference_forward(p, iomap, node_sel)                        # cases 2 & 3
        fwd !== nothing && return fwd
    end
    ranges = iomap.child_elem_ranges                                         # case 4
    for (i, cim) in enumerate(cims)
        # The stored path: a dormant child answers `nothing` through the property,
        # and case 4 is exactly where that child's caret has to be found.
        csel = get_stored_selection(cim.output)
        csel === nothing && continue
        cf = _text_side_flat(csel)
        cf === nothing && continue                 # skip ∅ / TextRect / non-cursor
        loc = _flat_to_span_char(_compute_flat_entries(cim), cf)
        loc === nothing && continue
        pf = _text_elem_path_to_flat(iomap.flat_elements, ranges[i].start + loc[1] - 1, loc[2])
        pf < 0 && continue
        image = _flat_text_path(pf)
        # The promoted caret belongs to the child, so it carries the child's state.
        # The node holds no selection of its own in this case, so the caller has
        # none to give it.
        return is_live_selection(cim.output) ? image :
               SelectionDocument(; primary = image, live = false)
    end
    return nothing                                                            # case 5
end

# Gesture-aware reader. With the originating gesture in hand, all pointer-driven
# tree behaviour is resolved here — the text/graphics layers below stay dumb and
# emit only a plain character cursor. Click reinterpretations are keyed off
# `change.gesture isa MouseClick`, so keyboard navigation that lands on the same
# glyph still places the cursor:
#   1. A click on a node's inline marker (either state) or its collapsed ellipsis
#      is a fold gesture → toggle that specific node.
#   2. Alt+click promotes the click to a whole-element (tree) selection on the
#      enclosing node — the mouse half of tree navigation.
# Both are resolved by `_resolve_click`, which classifies the click's element into
# a zone and delegates a child-zone click to that child's own click resolution —
# never re-walking the input subtree.
function read_intent(p::SyntaxCompoundToText, recursion, change::Intent, iomap::SyntaxCompoundToTextIoMap)
    op = change.operation
    gesture = change.gesture
    # The edit beside an inline image writes the element list of the output, which
    # has no pre-image in the syntax: decline it.
    is_text_element_write(op) && return Intent(gesture, nothing)
    if op isa ReplaceSelectionOperation && gesture isa MouseClick
        resolved = _resolve_click(p, iomap, gesture, op.path)
        resolved !== nothing && return Intent(gesture, resolved)
    end
    # Everything else (keyboard, plain clicks, other operations) falls through to
    # the operation-typed readers below.
    payload = op === nothing ? gesture : op
    result = read_intent(p, iomap, payload)

    # Console fallback. In the SDL pipeline `TextToGraphics` (downstream) has
    # already filled the operation slot via its own `read_gesture` delegation, so
    # `op !== nothing` and we never reach here for a gesture. In the console
    # pipeline (`… → SyntaxToText → WindowInputUnwrapping`) there is no
    # `TextToGraphics`, so the operation slot is still empty: `payload` is the raw
    # gesture and `read_intent(p, iomap, gesture)` only handled the syntax
    # (tree-navigation) subset. When that yields nothing, the gesture may still be
    # a geometry-free Text-domain edit/navigation (character insert/delete,
    # left/right cursor, …). Ask the *output* TextBlock's `read_gesture` for a
    # text-domain operation and route it back through this projection's existing
    # operation-typed readers, which map the `.elements[i].content[…]` reference
    # to the enclosing syntax leaf.
    if result === nothing && op === nothing
        text_op = read_gesture(iomap.output, gesture)
        text_op === nothing || return Intent(gesture, read_intent(p, iomap, text_op))
    end

    return Intent(gesture, result)
end

# Resolve a click (given as an output reference `path`) to a tree Operation, or
# `nothing` to fall through to a plain character cursor. Classifies the click's
# element into a zone over this node's own output and delegates a child-zone click
# to that child's own `_resolve_click` (recursion in lockstep with the printer):
#   - own inline marker (incl. the right-edge boundary pixel) or collapsed ellipsis
#     → `ToggleCollapseOperation(this node)` — any modifier;
#   - a child node zone → recurse with the child-local flat caret; a returned
#     `ToggleCollapseOperation` (object target) propagates up unchanged, a returned
#     tree `ReplaceSelectionOperation` gets `.children[i]` prepended;
#   - a leaf child zone → Alt: whole-leaf `.children[i]∅`; else cursor (`nothing`);
#   - own delimiters/decoration → Alt: whole-node `∅`; else cursor (`nothing`).
function _resolve_click(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, gesture, path)
    elements = iomap.flat_elements
    # Locate the clicked entry through the flat offset, which the marker
    # boundary-pixel test reads too.
    flat = _compute_output_flat(iomap.output, path)
    flat === nothing && return nothing
    loc = _flat_to_span_char(elements, flat)
    loc === nothing && return nothing
    j, c = loc
    node = iomap.input
    mi = iomap.marker_index

    # Own inline marker: [0, marker_len] inclusive of the boundary pixel (the
    # right edge of the glyph maps to the open delimiter's first column).
    mi > 0 && flat <= length(elements[mi].content::AbstractString) &&
        return ToggleCollapseOperation(node)
    # Own collapsed-body ellipsis.
    iomap.ellipsis_index > 0 && j == iomap.ellipsis_index && return ToggleCollapseOperation(node)

    for (i, r) in enumerate(iomap.child_elem_ranges)
        if j in r
            cim = get_content_iomap(iomap.child_iomaps[i])
            if cim isa SyntaxCompoundToTextIoMap
                # Delegate the child-local click to the child's resolver.
                child_flat = _text_elem_path_to_flat(cim.flat_elements, j - r.start + 1, c)
                inner = _resolve_click(cim.projection, cim, gesture, _flat_text_path(child_flat))
                inner === nothing && return nothing
                inner isa ToggleCollapseOperation && return inner   # object target, unchanged
                inner isa ReplaceSelectionOperation &&
                    return ReplaceSelectionOperation(_prepend_child(node, i, inner.path))
                return inner
            end
            # Leaf child: Alt selects the whole leaf; a plain click places a cursor.
            return gesture.modifiers.alt ?
                ReplaceSelectionOperation(_prepend_child(node, i, EmptyReference(get_reference_node_type(cim.input)))) : nothing
        end
    end
    # Own delimiters / decoration: Alt selects this whole node.
    gesture.modifiers.alt ? ReplaceSelectionOperation(EmptyReference()) : nothing
end

function read_intent(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, op::ReplacePathOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    return make_path_operation(op, input_path)
end

# Keyboard fold (`Ctrl+.`): the operation arrives from below carrying no
# target. Resolve it here — where both the syntax tree and its selection are
# in hand — to the innermost collapsible node containing the cursor, then let
# it propagate up unchanged. An already-targeted operation (e.g. a click
# resolved above) passes through untouched.
function read_intent(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, op::ToggleCollapseOperation)
    op.target === nothing || return op
    target = _resolve_collapsible(iomap.input, iomap.input.selection)
    return ToggleCollapseOperation(target)
end

# Tree-selection navigation by keyboard. The whole keyboard mapping for a syntax
# tree is geometry-free — it walks the input `SyntaxNode` and its selection paths
# — so it lives on the Syntax domain as `read_gesture(::SyntaxNode, gesture)` (in
# `SyntaxModule`). Delegate to it; the operation it returns (a
# `ReplaceSelectionOperation` on the syntax tree) is mapped backward to the source
# domain by the rest of the chain, exactly as before. The mouse hit-testing for
# collapse glyphs / Alt+click stays in the 4-arg `Intent` reader above (geometry).
function read_intent(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, evt::KeyDown)
    return read_gesture(iomap.input, evt)
end

# Translate a flat-text `ReplaceStringRangeOperation` to a SyntaxNode-domain op.
# The reference is single-span (`.elements[i].elements[k].content{s:e}`, span `k`
# of line `i`). Classify its entry `j` into a zone: a child zone delegates the read,
# as characters of a span of a line of the child, to that child's own reader (the
# leaf `.value{s:e}` rewrite lives in `SyntaxLeafToText`) and prepends
# `.children[i]`; own chrome is not editable. The zero-width input-selection
# disambiguation is preserved.
function read_intent(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_span_range(op.reference)
    parsed === nothing && return nothing
    span_path, char_start, char_stop = parsed
    length(span_path) == 2 || return nothing
    elements = iomap.flat_elements
    span_idx = _find_span_entry(elements, span_path[1], span_path[2])
    span_idx === nothing && return nothing
    flat_start = _text_elem_path_to_flat(elements, span_idx, char_start)
    flat_stop  = _text_elem_path_to_flat(elements, span_idx, char_stop)
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
        if sel isa ConcreteReference && _ends_in_field_range(sel)
            image = map_reference_forward(p, iomap, sel)
            (image !== nothing && _text_side_flat(image) == flat_start) &&
                return ReplaceStringRangeOperation(sel, op.replacement)
        end
    end

    # Both endpoints share entry `span_idx`; delegate its child zone.
    for (i, r) in enumerate(iomap.child_elem_ranges)
        if span_idx in r
            cim = iomap.child_iomaps[i]
            child_path = _find_entry_span_path(_compute_flat_entries(cim), span_idx - r.start + 1)
            child_path === nothing && return nothing
            child_op = ReplaceStringRangeOperation(
                _make_span_range_path(child_path, char_start, char_stop), op.replacement)
            result = read_intent(cim.projection, cim, child_op)
            (result isa ReplaceStringRangeOperation) || return nothing
            return ReplaceStringRangeOperation(_prepend_child(iomap.input, i, result.reference), result.replacement)
        end
    end
    # A separator span. One `separator` field renders n−1 spans, so an edit on any
    # occurrence collapses onto that single shared field — the document has exactly one
    # separator, and editing it changes every gap. This is deliberately NOT symmetric
    # with the mapper: a separator *selection* stays per-occurrence introduced chrome
    # (see `_backward_zone` / `_push_separator!`), only the *edit* collapses onto the
    # field. For a domain-projected node the separator is projection-introduced, so the
    # domain's own reader defers this `.<field>` edit and the key falls through to a
    # structural gesture; for a standalone syntax document it edits the separator in place.
    k = findfirst(place -> first(place) == span_idx, iomap.sep_indices)
    if k !== nothing
        separator = get_separator(iomap.input)
        if separator !== nothing
            offset = last(iomap.sep_indices[k])
            new_ref = ConcreteReference(get_reference_node_type(iomap.input),
                          FieldReferenceStep(String(separator.first)),
                          ConcreteReference(_get_text_type(separator.second),
                              RangeReferenceStep(char_start + offset, char_stop + offset),
                              EmptyReference(Position)))
            return ReplaceStringRangeOperation(new_ref, op.replacement)
        end
    end
    return nothing   # own chrome (open/close/decoration) is not string-editable
end

# Flat text edit in a `TextToGraphics`-less pipeline (the console): lower the flat
# `ReplaceTextRangeOperation` against this node's own output block, then re-dispatch
# through the `ReplaceStringRangeOperation` handler above (which finds the child
# span the range lands in). In the SDL pipeline `TextToGraphics` lowers it first, so
# this method is reached only by the console path.
function read_intent(p::SyntaxCompoundToText, iomap::SyntaxCompoundToTextIoMap, op::ReplaceTextRangeOperation)
    r = strip_reference_types(op.reference)
    (r isa ConcreteReference && r.head isa TextRangeReferenceStep && r.tail isa EmptyReference) ||
        return nothing
    # An edit with no break lowers to one run.
    if !occursin('\n', op.replacement)
        lowered = _lower_text_range(iomap.output, op)
        lowered !== nothing && return is_text_element_write(lowered) ? nothing : read_intent(p, iomap, lowered)
    end
    # An edit of a break goes to the child that holds its whole range, in the flat
    # offsets of the output of the child. Chrome takes no edit.
    for i in eachindex(iomap.child_elem_ranges)
        start = _find_child_flat(iomap, i, r.head.start::Int)
        stop = _find_child_flat(iomap, i, r.head.stop::Int)
        (start === nothing || stop === nothing) && continue
        cim = iomap.child_iomaps[i]
        result = read_intent(cim.projection, cim,
                             ReplaceTextRangeOperation(make_flat_range_reference(start, stop), op.replacement))
        result isa Union{ReplaceStringRangeOperation, ReplaceTextRangeOperation} || return nothing
        return retarget_operation(result, _prepend_child(iomap.input, i, operation_reference(result)))
    end
    nothing
end

# The flat offset in the output of child `i` of the flat offset `flat` of this
# output, or `nothing` when `flat` is not in the entries of the child. An offset in
# an indentation that this node widened stands at most at the end of the narrower
# indentation of the child.
function _find_child_flat(iomap::SyntaxCompoundToTextIoMap, i::Int, flat::Int)
    elements = iomap.flat_elements
    range = iomap.child_elem_ranges[i]
    isempty(range) && return nothing
    child_elements = _compute_flat_entries(iomap.child_iomaps[i])
    offset = _text_elem_path_to_flat(elements, range.start, 0)
    flat < offset && return nothing
    for j in range
        len = _span_len(elements[j])
        if flat <= offset + len
            local_j = j - range.start + 1
            return _text_elem_path_to_flat(child_elements, local_j, min(flat - offset, _span_len(child_elements[local_j])))
        end
        offset += len
    end
    nothing
end

# True iff `path` ends in `.<field>[range]` — the shape a
# ReplaceStringRangeOperation reference must have for `_split_replace_reference`.
function _ends_in_field_range(path)
    path isa ConcreteReference || return false
    penult = nothing
    cur = path
    while cur.tail isa ConcreteReference
        penult = cur.head
        cur = cur.tail
    end
    penult isa FieldReferenceStep && cur.head isa RangeReferenceStep
end

# ── SyntaxListToText ──────────────────────────────────────────────────
# ListNode(SyntaxDocument) → TextBlock whose elements are a ListNode of lines.
# Each element is projected one level down via `print_child(recursion, …)`, and its
# output lines follow each other in the lazy list; a line implies its break, so no
# element separates two elements. The ListNode structure is preserved lazily.

struct SyntaxListToText <: Projection end

# The IO map of a lazy list of syntax: for each input node that the printer
# printed, the entry of its lines, `(first, last, count, iomap)`: the first and the
# last node of its lines in the output list, their number, and the IO map of the
# element.
@iomap struct SyntaxListToTextIoMap
    projection::Any
    input::ListNode
    output::TextBlock
    element_lines::IdDict{ListNode, Any}
end

# Element `k` of the input list maps to its lines in the output list,
# `elements{i-1:j}`. A line counts from the head of the output list, as an element
# counts from the head of the input list, and the head line is the first line of
# the head element. A part inside the element maps through the forward map of the
# element, moved to the first line of the element.
function map_reference_forward(::SyntaxListToText, iomap::SyntaxListToTextIoMap, reference)
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    step = get_reference_head(reference)
    (step isa ARangeReferenceStep && is_element_reference_step(step)) || return nothing
    place = _find_element_lines(iomap, step.start + 1)
    place === nothing && return nothing
    first, entry = place
    rest = get_reference_tail(reference)
    inner = rest isa EmptyReference ? EmptyReference() :
            map_reference_forward(entry.iomap.projection, entry.iomap, rest)
    inner === nothing ? nothing : _move_line_reference(inner, first, entry)
end

# The index of the first line of element `index` in the output list, and the entry
# of its lines; `nothing` when the input list has no such element. The output list
# is read from its head towards the element, which prints the elements on the way.
function _find_element_lines(iomap::SyntaxListToTextIoMap, index::Int)
    input_node = find_list_node(iomap.input, index)
    input_node === nothing && return nothing
    link, direction = index >= 1 ? (:next, 1) : (:prev, -1)
    node, position = iomap.output.elements, 1
    while node !== nothing
        entry = get(iomap.element_lines, input_node, nothing)
        entry !== nothing && entry.first === node && return (position, entry)
        node = getproperty(node, link)
        position += direction
    end
    nothing
end

# The line `i`, the span `j` and the character `c` of the flat offset `flat` in a
# block of lines; an offset at the boundary of two spans is the end of the earlier
# one. `nothing` in a break or an indentation.
function _find_line_place(block::TextBlock, flat::Int)
    offsets = get_flat_offsets(block)
    for (i, line) in enumerate(block.elements)
        line isa TextLine || continue
        base = offsets[i] + line.indentation
        for (j, span) in enumerate(line.elements)
            span_length = get_flat_length(span)
            base <= flat <= base + span_length && return (i, j, flat - base)
            base += span_length
        end
    end
    nothing
end

# A reference into the output of one element, moved into the output list, whose
# line `first` is the first line of the element. The whole element is all its
# lines; a caret or characters inside one span are those characters of it; a range
# across spans of one line is those spans; a range across lines is those lines.
function _move_line_reference(inner, first::Int, entry)
    lines_of(start, stop, rest = EmptyReference()) =
        ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(start, stop), rest))
    inner isa EmptyReference && return lines_of(first - 1, first - 1 + entry.count)
    inner isa ConcreteReference || return nothing
    head = get_reference_head(inner)
    if (head isa TextRangeReferenceStep || head isa TextSpanReferenceStep) &&
       get_reference_tail(inner) isa EmptyReference
        block = entry.iomap.output
        start = _find_line_place(block, head.start)
        stop = _find_line_place(block, head.stop)
        (start === nothing || stop === nothing) && return nothing
        i, j, c = start
        i2, j2, c2 = stop
        line = first - 1 + i
        if (i, j) == (i2, j2)
            return lines_of(line - 1, line, ConcreteReference(FieldReferenceStep("elements"),
                       ConcreteReference(RangeReferenceStep(j - 1, j),
                           ConcreteReference(FieldReferenceStep("content"),
                               ConcreteReference(RangeReferenceStep(c, c2), EmptyReference())))))
        end
        i == i2 && return lines_of(line - 1, line, ConcreteReference(FieldReferenceStep("elements"),
                                       ConcreteReference(RangeReferenceStep(j - 1, j2), EmptyReference())))
        return lines_of(line - 1, first - 1 + i2)
    end
    if head isa FieldReferenceStep && head.name == "elements"
        range = get_reference_tail(inner)
        range isa ConcreteReference || return nothing
        step = get_reference_head(range)
        step isa ARangeReferenceStep || return nothing
        return lines_of(first - 1 + step.start, first - 1 + step.stop, get_reference_tail(range))
    end
    nothing
end

function map_reference_backward(::SyntaxListToText, iomap, reference)
    return nothing
end

"""
    print_document(::SyntaxListToText, recursion, ln::ListNode, ctx)

Convert a `ListNode(SyntaxDocument)` to a `TextBlock` whose elements are a
`ListNode` of `TextLine`s. Each syntax element is projected through `recursion`
(so a nested `SyntaxNode` renders exactly as it would standalone — with its own
lines and indentation), and its lines follow each other in the list.
"""
function print_document(p::SyntaxListToText, recursion, ln::ListNode, ctx)
    cache = IdDict{ListNode, Any}()
    out_head = _syntax_list_to_text_node(ln, recursion, ctx, cache)
    SyntaxListToTextIoMap(p, ln, TextBlock(out_head, Cell(nothing)), cache)
end

# The lines of the output of an element: its `TextLine`s, or the lines that its
# spans make.
function _make_element_lines(block::TextBlock)
    elements = block.elements
    (length(elements) > 0 && all(element -> element isa TextLine, elements)) &&
        return collect(TextLine, elements)
    TextLine[TextLine(line.spans; indentation = line.indentation) for line in _compute_output_lines(block)]
end

# `cache` maps each input ListNode to the entry of its lines, whose `first` is the
# first output node of its lines and `last` the last. This makes the projection
# idempotent under repeated traversal: walking next then prev returns to the same
# object instead of materialising a fresh prev-chain on every call.
function _syntax_list_to_text_node(input_node::ListNode, recursion, ctx, cache::IdDict)
    haskey(cache, input_node) && return cache[input_node].first

    # Delegate this element one level down; its output lines (a leaf's one line,
    # or a whole node's lines) follow each other in the list.
    child_iomap = print_child(recursion, input_node.value, ctx)
    lines = _make_element_lines(child_iomap.output)

    first_out = ListNode(lines[1])
    last_out = first_out
    for k in 2:length(lines)
        next_out = ListNode(lines[k])
        set_cell_value!(getfield(last_out, :next), next_out)
        set_cell_value!(getfield(next_out, :prev), last_out)
        last_out = next_out
    end
    cache[input_node] = (first = first_out, last = last_out, count = length(lines), iomap = child_iomap)

    set_lazy_link!(last_out, :next, () -> begin
        input_next = input_node.next
        input_next === nothing && return nothing
        _syntax_list_to_text_node(input_next, recursion, ctx, cache)
    end)

    set_lazy_link!(first_out, :prev, () -> begin
        input_prev = input_node.prev
        input_prev === nothing && return nothing
        _syntax_list_to_text_node(input_prev, recursion, ctx, cache)
        cache[input_prev].last
    end)

    first_out
end

# ── Compound convenience constructor ────────────────────────────────────────

function SyntaxToText(; indent_size::Int = 2,
                        expanded_marker::TextString = TextString(""),
                        collapsed_marker::TextString = TextString(""),
                        marker_eligible = _default_marker_eligible,
                        theme = nothing,
                        text_folds::Bool = false)
    # Every compound is printed by the same projection instance — the configuration
    # is the projection's, the structure is the document's. `theme`, a
    # `SyntaxTheme` scaled or not, gives the ellipsis and the font of the
    # decorations of a node with no delimiter. `text_folds`
    # chooses the kind of fold of the view (see `SyntaxCompoundToText`).
    compound = SyntaxCompoundToText(theme=theme,
                                    indent_size=indent_size,
                                    expanded_marker=expanded_marker,
                                    collapsed_marker=collapsed_marker,
                                    marker_eligible=marker_eligible,
                                    text_folds=text_folds)
    TypeDispatchingProjection(
        SyntaxLeaf          => SyntaxLeafToText(),
        SyntaxNode          => compound,
        SyntaxConcatenation => compound,
        SyntaxSeparation    => compound,
        SyntaxDelimitation  => compound,
        SyntaxIndentation   => compound,
        SyntaxCollapsible   => compound,
        SyntaxNavigation    => compound,
        ListNode            => SyntaxListToText(),
    )
end

# ── Utility ──────────────────────────────────────────────────────────────────

# `_splice_compound` runs the whole layout of a node again on any structural
# change, which would allocate a fresh ellipsis, lit delimiter and line each pass,
# so a structural edit would orphan all of them (printer locality, dimension C).
# `_DecoCache` keeps one of each across layouts: a cache of one invocation of the
# projection (it lives in the closure of the `spans` cell, never in module-global
# state), keyed by the structural slot of the object, such as `(node objectid,
# child index, role)`, which is stable across edits because the syntax nodes are
# themselves identity-stable (the template engine reconciles them). A line is keyed
# by its indentation and the identity of its spans. `seen` records the slots
# touched in the current pass so the caller can evict the rest.
struct _DecoCache
    spans::Dict{Any,Any}
    seen::Set{Any}
end
_DecoCache() = _DecoCache(Dict{Any,Any}(), Set{Any}())

# Reuse the decorative object for `key`, or make and cache it. With no cache just
# make a fresh one.
function _deco_span(deco, key, make)
    deco === nothing && return make()
    push!(deco.seen, key)
    get!(make, deco.spans, key)
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
function _active_marker(p::SyntaxCompoundToText, node::SyntaxCompound)
    # A compound that cannot collapse gets no fold marker — the glyph would be dead.
    is_syntax_collapsible(node) || return nothing
    p.marker_eligible(node) || return nothing
    m = is_syntax_collapsed(node) ? p.collapsed_marker : p.expanded_marker
    isempty(m.content::AbstractString) ? nothing : m
end

# Reads a path of the leaf (.open[k], .value[k], .close[k]), such as its selection
# or its mouse target, and converts it to a flat character offset within open ++
# value ++ close. Returns -1 if the path does not point to a cursor position inside
# this leaf.
function _leaf_cursor(leaf::SyntaxLeaf, path)
    # Paths are canonical: each node records its type. Strip the types, so the
    # raw .open/.value/.close{k} structural match below reads the plain skeleton.
    sel = strip_reference_types(path)
    sel isa EmptyReference && return -1
    sel isa ConcreteReference || return -1
    h = sel.head
    if h isa FieldReferenceStep
        rest = sel.tail
        rest isa ConcreteReference || return -1
        inner = rest.head
        inner isa RangeReferenceStep || return -1
        k = inner.start::Int
        fname = h.name
        if fname == "value"
            return _delimiter_len(leaf.open) + k
        elseif fname == "open"
            leaf.open === nothing && return -1   # no opening delimiter: no cursor there
            return k
        elseif fname == "close"
            leaf.close === nothing && return -1  # no closing delimiter: no cursor there
            return _delimiter_len(leaf.open) + _span_len(leaf.value) + k
        end
    end
    return -1
end

# The flat character length a delimiter contributes: zero when it is absent.
_delimiter_len(::Nothing) = 0
_delimiter_len(text) = _span_len(text)

# ── The flat length of a text ─────────────────────────────────────────────────

# A run counts its characters.
function _span_len(s::TextString)
    length(s.content::AbstractString)
end
# An embedded graphic (e.g. a `BookPicture` image placed in a leaf's value) is one
# position of the flat character space, as it is in the text domain
# (`get_flat_length`).
_span_len(::TextGraphics) = 1
# A text of lines counts its flat text, a break one.
_span_len(text::TextBlock) = get_flat_length(text)

# The lines of a text of a field, each the runs of one line: a run is one line, and
# a block gives the runs of each of its lines. The indentation of a line of a block
# is not read: a text in a field is lines of runs.
_get_text_lines(text::TextBlock) = [collect(TextDocument, line.elements) for line in text.elements]
_get_text_lines(text) = [TextDocument[text]]


# ── Collapse resolution ───────────────────────────────────────────────────────

# Innermost SyntaxNode along `path` (a selection rooted at `node`). Descends
# through `.children[i]` steps as long as the child is itself a SyntaxNode,
# stopping at the first leaf or non-child step. With no usable path the root
# node is returned. This is the keyboard fold target: the most deeply nested
# node that still contains the cursor — matching every editor's fold gesture.
function _resolve_collapsible(node::SyntaxCompound, path)
    # Only a collapsible compound can be a fold target; a non-collapsible one on the
    # way down is stepped over, not selected.
    best = is_syntax_collapsible(node) ? node : nothing
    cur = node
    # Selections are canonical: each node records its type. Strip the types, so the
    # walk below reads the plain structural skeleton (.children[i]...).
    p = strip_reference_types(path)
    while true
        step = peel_child_step(p)
        step === nothing && break
        i, tail = step
        children = get_syntax_children(cur)
        children === nothing && break
        (1 <= i <= length(children)) || break
        child = children[i]
        child isa SyntaxCompound || break
        is_syntax_collapsible(child) && (best = child)
        cur = child
        p = strip_reference_types(tail)
    end
    best
end

# ── Paths in an output ────────────────────────────────────────────────────────

# The span path that `path` names in an output, and what follows it:
# `.elements[i].elements[k]` is span `[i, k]` of a block of lines, and `.elements[i]`
# is span `[i]` of a block of spans. `nothing` when `path` starts in no span.
function _split_span_path(path)
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep &&
     path.head.name == "elements") || return nothing
    outer = path.tail
    (outer isa ConcreteReference && outer.head isa RangeReferenceStep) || return nothing
    i = outer.head.start + 1
    rest = outer.tail
    if rest isa ConcreteReference && rest.head isa FieldReferenceStep && rest.head.name == "elements"
        inner = rest.tail
        (inner isa ConcreteReference && inner.head isa RangeReferenceStep) || return nothing
        return (Int[i, inner.head.start + 1], inner.tail)
    end
    (Int[i], rest)
end

# The characters `(start, stop)` that `.content[start:stop]` names, or `nothing`.
function _parse_content_range(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep &&
     path.head.name == "content") || return nothing
    range = path.tail
    (range isa ConcreteReference && range.head isa RangeReferenceStep) || return nothing
    (range.head.start::Int, range.head.stop::Int)
end

# A whole span of a line of an output, `.elements[i].elements[k]∅`: its span path,
# or `nothing`.
function _parse_tree_span_path(path)
    parts = _split_span_path(path)
    (parts !== nothing && length(parts[1]) == 2 && parts[2] isa EmptyReference) ? parts[1] : nothing
end

# Characters of a span of an output, `….content[start:stop]`: `(span path, start,
# stop)`, or `nothing`.
function _parse_span_range(path)
    parts = _split_span_path(path)
    parts === nothing && return nothing
    range = _parse_content_range(parts[2])
    range === nothing ? nothing : (parts[1], range[1], range[2])
end

# The path of span `span_path` of an output, with `tail` after it.
function _make_span_path(span_path::Vector{Int}, tail)
    for index in reverse(span_path)
        tail = ConcreteReference(FieldReferenceStep("elements"),
                                 ConcreteReference(RangeReferenceStep(index - 1, index), tail))
    end
    tail
end

# `.elements[i].elements[k].content[start:stop]`: characters of span `k` of line `i`.
_make_span_range_path(span_path::Vector{Int}, start::Int, stop::Int) =
    _make_span_path(span_path, ConcreteReference(FieldReferenceStep("content"),
                                                 ConcreteReference(RangeReferenceStep(start, stop), EmptyReference())))

# The flat offset of a caret in the output `block`: a flat caret, or a caret in a
# span of it. `nothing` for any other path.
function _compute_output_flat(block::TextBlock, path)
    flat = _text_side_flat(path)
    flat === nothing || return flat
    parsed = _parse_span_range(path)
    parsed === nothing && return nothing
    span_path, start, _ = parsed
    base = get_flat_base(block, span_path)
    base === nothing ? nothing : base + start
end

# The canonical flat caret path, rooted at the output TextBlock.
_flat_text_path(flat::Int) =
    ConcreteReference(TextRangeReferenceStep(flat, flat), EmptyReference())

# A non-empty flat text range. The syntax chain maps a caret as one flat offset,
# so a range has no image in it and its backward map declines: a `Shift` key
# leaves the selection where it was.
function _is_flat_text_range(path)
    p = strip_reference_types(path)
    p isa ConcreteReference && p.head isa TextRangeReferenceStep &&
        p.tail isa EmptyReference && p.head.start != p.head.stop
end

# The flat offset of a flat caret path, `TextRangeReferenceStep{f}` or a bare block
# cursor `{f}`, or `nothing` when it is no such caret.
function _text_side_flat(path)
    p = strip_reference_types(path)
    p isa ConcreteReference || return nothing
    h = p.head
    (h isa TextRangeReferenceStep || h isa RangeReferenceStep) && p.tail isa EmptyReference || return nothing
    h.start::Int
end

# Inverse of `_text_elem_path_to_flat`: the `(span_idx, char)` a flat offset lands
# on over span-content lengths (end-of-content anchors on the last non-empty
# span). `nothing` when there is no span.
function _flat_to_span_char(spans, flat_pos::Int)
    cumulative = 0
    last_nonempty = nothing
    first_span = nothing
    for (i, s) in enumerate(spans)
        len = _span_len(s)
        first_span === nothing && (first_span = (i, cumulative))
        len > 0 && (last_nonempty = (i, cumulative))
        flat_pos < cumulative + len && return (i, flat_pos - cumulative)
        cumulative += len
    end
    # End of content: anchor on the last non-empty span (renderable); when every
    # span is empty (an empty leaf, e.g. an undelimited `""`), anchor on the first
    # so the caret still resolves rather than vanishing.
    anchor = last_nonempty !== nothing ? last_nonempty : first_span
    anchor === nothing ? nothing : (anchor[1], flat_pos - anchor[2])
end

function _text_elem_path_to_flat(spans, span_idx::Int, char_idx::Int)
    span_idx > length(spans) && return -1
    flat = char_idx
    for i in 1:(span_idx - 1)
        flat += _span_len(spans[i])
    end
    return flat
end
