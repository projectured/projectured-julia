# ═══════════════════════════════════════════════════════════════════════════
# test/editor/TypeinTest.jl
#
# Type-in round-trip test.  Walks the document graph and, at every string,
# exercises the full keyboard-editing cycle:
#
#   1. Walk every field (with a circularity guard), building a ReferencePath
#      to each String the walk reaches; keep that reference.
#   2. Replace the selection so the cursor points into that string.
#   3. Print the projection and check that a cursor is present in the
#      Graphics-domain image (a thin GraphicsRect).
#   4. Simulate a keypress through the reader; it must yield a
#      ReplaceStringRangeOperation.
#   5. Evaluate that operation against the document.
#   6. Check that the string in the original input document changed exactly
#      as the keypress dictates (the typed character inserted at the cursor).
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedKernel.CellModule: Cell
using ProjecturedBase.CollectionModule: CellVector
using ProjecturedVisual.FontModule: StyleFont
using ProjecturedVisual.TextModule: TextString, TextText
using ProjecturedVisual.SyntaxModule: SyntaxNode, SyntaxLeaf

# ── Document-graph walk ──────────────────────────────────────────────────────
#
# `_collect_string_refs` returns one *cursor target* for every editable String
# reachable in the input/document domain.  The walk descends every field via
# FieldReference, indexes CellVector / Vector elements via RangeReference, and
# skips `selection` fields (they hold reference paths, not document content).
# An objectid set guards against cycles.
#
# A cursor target is `(cursor, kind)`:
#   * `cursor` is the ReferencePath the **cursor convention** anchors at —
#     appending a PositionReference turns it into a cursor selection.
#   * `kind` says where the editable characters live relative to `cursor`,
#     so the test can read the string before/after the edit:
#       :plain      — `cursor` resolves to the String itself.
#       :textstring — `cursor` resolves to a `TextString`; the characters are
#                     its `.content`. This is the document-domain `TextString`
#                     case (e.g. `SyntaxLeaf.value`): the cursor convention is
#                     `.value{k}`, one level above the raw `.content` String.
#       :texttext   — `cursor` resolves to a `TextText`; the characters are the
#                     flattened concatenation of its `TextString` spans, and the
#                     cursor convention is a flat `.content{k}` offset across
#                     them (e.g. `BookParagraph.content`).
#
# `StyleFont` is skipped: a font's `filename` is a String, but it is
# presentation metadata attached to text spans, not editable document content,
# so typing into it has no cursor to render.

function _collect_string_refs(document)
    refs = NamedTuple{(:cursor, :kind)}[]
    _walk_strings!(document, EmptyReferencePath(), Set{UInt64}(), refs)
    refs
end

function _walk_strings!(node, path, visited, refs)
    node === nothing      && return
    node isa Bool         && return
    node isa Number       && return
    node isa Symbol       && return
    node isa AbstractString && return   # recorded by the caller at field level
    node isa Function     && return
    node isa ReferencePath && return
    node isa StyleFont    && return     # font metadata, not editable content

    id = objectid(node)
    id in visited && return
    push!(visited, id)

    if node isa CellVector
        for i in 1:length(node)
            child = node[i]
            _walk_strings!(child, append_reference(path, RangeReference(i - 1, i)), visited, refs)
        end
        return
    end
    if node isa AbstractVector
        for (i, child) in enumerate(node)
            _walk_strings!(child, append_reference(path, RangeReference(i - 1, i)), visited, refs)
        end
        return
    end

    isstructtype(typeof(node)) || return
    for fname in fieldnames(typeof(node))
        fname === :selection && continue
        # open/close/sep on a SyntaxLeaf/SyntaxNode are projection-rendered
        # delimiters (chrome derived from the node), not editable document
        # content: editing the open/close span is explicitly deferred at the
        # SyntaxLeafToText reader, so there is no edit op to type into them.
        (node isa Union{SyntaxLeaf, SyntaxNode} &&
         fname in (:open, :close, :sep)) && continue
        fval = getfield(node, fname)
        val  = fval isa Cell ? fval[] : fval
        field_path = append_reference(path, FieldReference(string(fname)))
        if val isa TextString
            # Document-domain TextString: cursor anchors at the field, the
            # characters are its `.content`. Do not descend further.
            push!(refs, (cursor=field_path, kind=:textstring))
        elseif val isa TextText
            # Document-domain TextText: cursor is a flat offset across spans,
            # anchored at the field. Do not descend into the spans.
            push!(refs, (cursor=field_path, kind=:texttext))
        elseif val isa AbstractString
            push!(refs, (cursor=field_path, kind=:plain))
        else
            _walk_strings!(val, field_path, visited, refs)
        end
    end
end

# Read the current editable String for a cursor target, given its `kind`.
function _read_target_string(document, target)
    v = evaluate_reference(document, target.cursor)
    if target.kind == :textstring
        v isa TextString || return nothing
        return v.content
    elseif target.kind == :texttext
        v isa TextText || return nothing
        buf = IOBuffer()
        for span in v.elements
            span isa TextString && print(buf, span.content)
        end
        return String(take!(buf))
    else
        return v
    end
end

# ── Cursor detection in the Graphics image ───────────────────────────────────
#
# The text cursor is rendered as a thin (1 ≤ width ≤ 5px) GraphicsRect somewhere in
# the projected canvas.  Search the iomap's output recursively for one.
#
# The lower bound matters: TextToGraphics always emits the caret rect and gives it
# width 0 when there is no cursor, so a `w <= 5` test alone matches the *absence* of
# a cursor just as happily as its presence.

function _find_cursor_rect(x)
    x = x isa Cell ? x[] : x
    if x isa GraphicsRect
        return 1 <= Int(x.w) <= 5 ? x : nothing
    elseif x isa GraphicsCanvas
        for elem in x.elements
            r = _find_cursor_rect(elem)
            r === nothing || return r
        end
    elseif x isa GraphicsViewport
        for fname in fieldnames(typeof(x))
            r = _find_cursor_rect(getfield(x, fname))
            r === nothing || return r
        end
    end
    nothing
end

_cursor_present(iomap) =
    hasproperty(iomap, :output) && _find_cursor_rect(iomap.output) !== nothing

# Expected value after inserting `ch` at 0-based character boundary `k`.
function _expected_insert(old::AbstractString, k::Int, ch::AbstractString)
    n = length(old)
    left  = k <= 0 ? "" : first(old, k)
    right = k >= n ? "" : last(old, n - k)
    String(left) * ch * String(right)
end

# ── Positions ────────────────────────────────────────────────────────────────
#
# Which character boundaries of a string of length `n` to type at. A string has
# `n + 1` of them (`0` … `n`) — the cursor positions `collect_position_selections`
# calls the carets. The boundary carets are where a typed character is at risk of
# landing in the neighbouring chrome (a quote, a delimiter, the next token) instead
# of the string, so `:all` is the policy that earns its keep; the other two exist to
# buy back time when a caller is sweeping every example.
#
#   :all   — every boundary.
#   :ends  — both boundary carets plus one interior one.
#   :first — one character in; the cheapest probe that still edits a string.
function _typein_positions(n::Int, policy::Symbol)
    policy === :all   && return collect(0:n)
    policy === :ends  && return unique([0, min(1, n), n])
    policy === :first && return [min(1, n)]
    error("unknown type-in positions policy: $(repr(policy))")
end

# ── Walker ───────────────────────────────────────────────────────────────────

# Run the full type-in cycle for the cursor target `target` at character boundary
# `k`. Returns (ok, message); `message` is empty on success and describes the first
# failed step otherwise.
function _typein_at(document, projection, target, k::Int, ch)
    old = try
        _read_target_string(document, target)
    catch e
        return (false, "reading target string threw: $e")
    end
    old isa AbstractString || return (false, "reference did not resolve to a string: $(old === nothing ? "nothing" : typeof(old))")
    sel = append_reference(target.cursor, PositionReference(k))

    # 1. Point the selection into this string.
    clear_selection!(document)
    try
        set_selection!(document, sel)
    catch e
        return (false, "set_selection! threw: $e")
    end

    # 2. Project and confirm the cursor shows up in the Graphics image.
    # The printer is lazy, so the projection's cells are forced by the cursor
    # search, not by `print_document` — a printer error surfaces here, and it must
    # fail this one target rather than abort the whole walk.
    iomap = try
        print_document(projection, document)
    catch e
        return (false, "print_document threw: $e")
    end
    present = try
        _cursor_present(iomap)
    catch e
        return (false, "searching the Graphics image for the cursor threw: $e")
    end
    present || return (false, "no cursor in Graphics image for string $(repr(old))")

    # 3. Type a character through the reader.
    op = try
        read_intent(projection, iomap, KeyPress(first(ch)))
    catch e
        return (false, "read_intent(KeyPress) threw: $e")
    end
    op isa ReplaceStringRangeOperation ||
        return (false, "KeyPress produced $(op === nothing ? "nothing" : string(typeof(op))), not ReplaceStringRangeOperation")

    # 4. Evaluate the operation and 5. verify the input string changed.
    before = try
        _read_target_string(document, target)
    catch e
        return (false, "re-read before edit threw: $e")
    end
    try
        evaluate_operation((document=document,), op)
    catch e
        return (false, "evaluate_operation threw: $e")
    end
    after = try
        _read_target_string(document, target)
    catch e
        return (false, "re-read after edit threw: $e")
    end
    expected = _expected_insert(before, k, ch)
    after == expected || return (false, "expected $(repr(expected)) got $(repr(after))")
    (true, "")
end

# Run the type-in cycle at each of `target`'s positions, restoring the document
# between them so every position is typed into the same pristine string. Returns one
# (position, ok, message) per position tried.
function _typein_target(document, projection, target, ch, policy::Symbol)
    results = NamedTuple{(:position, :ok, :message)}[]
    pristine = try
        _read_target_string(document, target)
    catch e
        push!(results, (position=0, ok=false, message="reading target string threw: $e"))
        return results
    end
    if !(pristine isa AbstractString)
        push!(results, (position=0, ok=false,
                        message="reference did not resolve to a string: $(pristine === nothing ? "nothing" : typeof(pristine))"))
        return results
    end
    for k in _typein_positions(length(pristine), policy)
        ok, message = _typein_at(document, projection, target, k, ch)
        push!(results, (position=k, ok=ok, message=message))
    end
    results
end

"""
    walk_typein(document, projection; replacement="X", positions=:first) -> Vector

For every string reachable in `document`, and at every character boundary selected
by `positions`, set the cursor there, assert the cursor renders in the Graphics
image, type `replacement`'s first character via the reader, evaluate the resulting
`ReplaceStringRangeOperation`, and verify the string changed accordingly.

`positions` is `:all` (every boundary `0…n` of a string of length `n`), `:ends`
(both boundary carets plus one interior one) or `:first` (one character in).

Returns one `(ref, position, ok, message)` result per (string, position) visited so
callers can assert (and count) each one; `message` is empty on success.
"""
function walk_typein(document, projection; replacement::AbstractString="X",
                     positions::Symbol=:first)
    ch = string(first(replacement))
    clear_selection!(document)
    targets = try
        _collect_string_refs(document)
    catch e
        return [(ref=EmptyReferencePath(), position=0, ok=false,
                 message="collecting string references threw: $e")]
    end
    results = NamedTuple{(:ref, :position, :ok, :message)}[]
    for target in targets
        for r in _typein_target(document, projection, target, ch, positions)
            push!(results, (ref=target.cursor, position=r.position, ok=r.ok, message=r.message))
        end
    end
    results
end

# ── Test helpers ─────────────────────────────────────────────────────────────

# One @test per (string, position), so the test count reflects how many cursor
# positions were verified.
function test_typein(label, document, projection; positions::Symbol=:first)
    @testset "$label" begin
        for r in walk_typein(document, projection; positions=positions)
            r.ok || @warn "[$label] [$(r.ref){$(r.position)}] $(r.message)"
            @test r.ok
        end
    end
end


# The `Example`-typed overload; the sweep (`test_typeins`) stays in the
# umbrella, which owns the example registry.
# Build fresh document / projection instances. `walk_typein` mutates the
# document (it types characters into every string), and in `test_all` this runs
# after the other reader/repl tests which share the global `example.document`;
# starting from a pristine document keeps the exact-string assertions reliable.
function test_typein(example::Example; positions::Symbol=:first)
    test_typein(example.name, example.make_document(), example.make_projection();
                positions=positions)
end
