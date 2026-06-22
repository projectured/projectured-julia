# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/TypeinTest.jl
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
#      StringReplaceRangeOperation.
#   5. Evaluate that operation against the document.
#   6. Check that the string in the original input document changed exactly
#      as the keypress dictates (the typed character inserted at the cursor).
# ═══════════════════════════════════════════════════════════════════════════

using Projectured
using ProjecturedExample
using Projectured: StringReplaceRangeOperation, evaluate_operation,
                   clear_selection!, set_selection!, evaluate_reference, append_reference,
                   ReferencePath, EmptyReferencePath,
                   FieldReference, RangeReference, PositionReference,
                   GraphicsCanvas, GraphicsRect, GraphicsViewport, KeyPress
using Projectured.ReactiveModule: Cell
using Projectured.CollectionModule: CellVector
using Projectured.FontModule: StyleFont
using Projectured.TextModule: TextString, TextText
using Projectured.SyntaxModule: SyntaxNode

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
        # A SyntaxNode with fewer than two children renders no separator, so its
        # `sep` field has no on-screen cursor position — there is nothing to
        # separate, hence nothing to type into.
        (node isa SyntaxNode && fname === :sep && length(node.children) < 2) && continue
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
# The text cursor is rendered as a thin (width ≤ 5px) GraphicsRect somewhere in
# the projected canvas.  Search the iomap's output recursively for one.

function _find_cursor_rect(x)
    x = x isa Cell ? x[] : x
    if x isa GraphicsRect
        return Int(x.w) <= 5 ? x : nothing
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

# ── Walker ───────────────────────────────────────────────────────────────────

# Run the full type-in cycle for the cursor target `target`. Returns
# (ok, message); `message` is empty on success and describes the first failed
# step otherwise.
function _typein_one(document, projection, target, ch)
    old = try
        _read_target_string(document, target)
    catch e
        return (false, "reading target string threw: $e")
    end
    old isa AbstractString || return (false, "reference did not resolve to a string: $(old === nothing ? "nothing" : typeof(old))")
    n = length(old)
    k = min(1, n)                           # cursor one char into the string
    sel = append_reference(target.cursor, PositionReference(k))

    # 1. Point the selection into this string.
    clear_selection!(document)
    try
        set_selection!(document, sel)
    catch e
        return (false, "set_selection! threw: $e")
    end

    # 2. Project and confirm the cursor shows up in the Graphics image.
    iomap = try
        projection_print(projection, document)
    catch e
        return (false, "projection_print threw: $e")
    end
    _cursor_present(iomap) || return (false, "no cursor in Graphics image for string $(repr(old))")

    # 3. Type a character through the reader.
    op = try
        projection_read(projection, iomap, KeyPress(first(ch)))
    catch e
        return (false, "projection_read(KeyPress) threw: $e")
    end
    op isa StringReplaceRangeOperation ||
        return (false, "KeyPress produced $(op === nothing ? "nothing" : string(typeof(op))), not StringReplaceRangeOperation")

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

"""
    walk_typein(document, projection; replacement="X") -> Vector

For every string reachable in `document`, set the cursor into it, assert the
cursor renders in the Graphics image, type `replacement`'s first character via
the reader, evaluate the resulting `StringReplaceRangeOperation`, and verify
the string changed accordingly.  Returns one `(ref, ok, message)` result per
string visited so callers can assert (and count) each one; `message` is empty
on success.
"""
function walk_typein(document, projection; replacement::AbstractString="X")
    ch = string(first(replacement))
    clear_selection!(document)
    targets = try
        _collect_string_refs(document)
    catch e
        return [(ref=EmptyReferencePath(), ok=false, message="collecting string references threw: $e")]
    end
    results = NamedTuple{(:ref, :ok, :message)}[]
    for target in targets
        ok, message = _typein_one(document, projection, target, ch)
        push!(results, (ref=target.cursor, ok=ok, message=message))
    end
    results
end

# ── Test helpers ─────────────────────────────────────────────────────────────

# One @test per string, so the test count reflects how many strings were
# verified.
function test_typein(label, document, projection)
    @testset "$label" begin
        for r in walk_typein(document, projection)
            r.ok || @warn "[$label] [$(r.ref)] $(r.message)"
            @test r.ok
        end
    end
end

# Build fresh document / projection instances. `walk_typein` mutates the
# document (it types characters into every string), and in `test_all` this runs
# after the other reader/repl tests which share the global `example.document`;
# starting from a pristine document keeps the exact-string assertions reliable.
function test_typein(example::Example)
    test_typein(example.name, example.make_document(), example.make_projection())
end

function test_typeins()
    @testset "Typeins" begin
        # The walk builds input-domain cursor targets by field/index name and
        # anchors them at the right slot for each domain's selection convention,
        # including document-domain `TextString` (e.g. `SyntaxLeaf.value`) and
        # `TextText` (e.g. `BookParagraph.content`). Domains whose projection has
        # no string-edit reader (sorting/primitive/object) are covered elsewhere.
        for name in ("json", "json_string", "text", "xml", "book", "syntax")
            idx = findfirst(e -> e.name == name, examples)
            idx === nothing && continue
            ex = examples[idx]
            @testset "$(ex.name)" begin
                test_typein(ex)
            end
        end
    end
end
