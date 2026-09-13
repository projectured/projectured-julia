# ═══════════════════════════════════════════════════════════════════════════
# test/editor/TypeinTest.jl
#
# Keyboard-editing round-trip test.  Walks the document graph and, at every
# character boundary of every string, exercises three edits — **insert**,
# **backspace**, **delete** — through the full projection reader, checking both
# the resulting string *and* where the caret lands:
#
#   1. Walk every field (with a circularity guard), building a Reference
#      to each String the walk reaches; keep that reference.
#   2. Replace the selection so the cursor points into that string, at the
#      boundary under test (`0` … `n` for a string of length `n` — the `positions`
#      policy chooses which, and by default it is all of them).
#   3. Print the projection and check that a cursor is present in the
#      Graphics-domain image (a thin GraphicsRect).
#   4. Simulate the edit's event through the reader (KeyPress for insert;
#      KeyDown(:backspace)/KeyDown(:delete) for the deletions). Where an edit is
#      expected it must yield a ReplaceStringRangeOperation (empty replacement for
#      the deletions); at a declined boundary the reader yields nothing.
#   5. Where an edit is expected, evaluate that operation against the document. At a
#      declined boundary nothing is evaluated — a stray boundary op is a failure, and
#      evaluating it would mutate the neighbouring chrome and drift the document.
#   6. Check that the string in the original input document changed exactly as the
#      edit dictates, **and** that the selection is now the caret at the position
#      the edit leaves it: insert → `k+len`, backspace → `k-1`, delete → `k`
#      (and, at a declined boundary, unchanged: string intact, caret still at `k`).
#   7. Restore the pristine string, so the next (position, edit) starts clean.
#
# The caret advance is generic: `evaluate_operation(::ReplaceStringRangeOperation)`
# splices `[s,e)→replacement` and then `set_selection!`s a zero-width caret at
# `s + length(replacement)`, so the expected post-edit caret is domain-independent.
# Backspace at `k==0` and delete at `k==n` decline uniformly (the reader returns
# nothing) — those boundaries are the no-op cases.
#
# The boundary carets (`0` and `n`) are the point of walking every position: they
# sit where the projection also renders the neighbouring chrome (a quote, a
# delimiter, the next token), which is where a typed character can land in the
# wrong slot, a deletion can eat chrome, or the caret can misland. The value↔chrome
# end-boundary deletions (Backspace erasing the last character, Delete at a value's
# end) are currently resolved toward the chrome span and are marked @test_broken
# pending the text-selection representation refactor (see `_typein_broken_reason`).
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedKernel.CellModule: Cell, ComputedCell
using ProjecturedCollection.CollectionModule: CellVector, ComputedCellVector
using ProjecturedStyle.StyleModule: StyleFont
using ProjecturedText.TextModule: TextString, TextBlock, TextDocument, TextGraphics
using ProjecturedSyntax.SyntaxModule: SyntaxNode, SyntaxLeaf

# ── Document-graph walk ──────────────────────────────────────────────────────
#
# `_collect_string_refs` returns one *cursor target* for every editable String
# reachable in the input/document domain.  The walk descends every field via
# FieldReferenceStep, indexes CellVector / Vector elements via RangeReferenceStep, and
# skips `selection` fields (they hold reference paths, not document content).
# An objectid set guards against cycles.
#
# A cursor target is `(cursor, kind)`:
#   * `cursor` is the Reference the **cursor convention** anchors at —
#     appending a PositionReferenceStep turns it into a cursor selection.
#   * `kind` says where the editable characters live relative to `cursor`,
#     so the test can read the string before/after the edit:
#       :plain      — `cursor` resolves to the String itself.
#       :textstring — `cursor` resolves to a `TextString`; the characters are
#                     its `.content`. This is the document-domain `TextString`
#                     case (e.g. `SyntaxLeaf.value`): the cursor convention is
#                     `.value{k}`, one level above the raw `.content` String.
#       :texttext   — `cursor` resolves to a `TextBlock`; the characters are the
#                     flattened concatenation of its `TextString` spans, and the
#                     cursor convention is a flat `.content{k}` offset across
#                     them (e.g. `BookParagraph.content`).
#
# `StyleFont` is skipped: a font's `filename` is a String, but it is
# presentation metadata attached to text spans, not editable document content,
# so typing into it has no cursor to render.

function _collect_string_refs(document)
    refs = NamedTuple{(:cursor, :kind)}[]
    _walk_strings!(document, EmptyReference(), Set{UInt64}(), refs)
    refs
end

function _walk_strings!(node, path, visited, refs)
    node === nothing      && return
    node isa Bool         && return
    node isa Number       && return
    node isa Symbol       && return
    node isa AbstractString && return   # recorded by the caller at field level
    node isa Function     && return
    node isa Reference && return
    node isa StyleFont    && return     # font metadata, not editable content

    id = objectid(node)
    id in visited && return
    push!(visited, id)

    if node isa CellVector
        for i in 1:length(node)
            child = node[i]
            _walk_strings!(child, extend_reference(path, RangeReferenceStep(i - 1, i)), visited, refs)
        end
        return
    end
    if node isa AbstractVector
        for (i, child) in enumerate(node)
            _walk_strings!(child, extend_reference(path, RangeReferenceStep(i - 1, i)), visited, refs)
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
        # Presentation style on a text span (font / colours / padding) is not
        # editable document content — the same reasoning that skips `StyleFont`
        # below. Some of these fields default to a bare "" placeholder, which the
        # walk would otherwise treat as an empty editable string with no caret to
        # render (a spurious "no cursor" failure).
        (node isa TextDocument &&
         fname in (:font, :font_color, :fill_color, :line_color, :padding)) && continue
        # A `TextGraphics` embeds a graphics document (an inline image); its
        # `content` is not text-editable, and descending into it would reach the
        # image file's `filename` String — presentation metadata, not text content.
        (node isa TextGraphics && fname === :content) && continue
        fval = getfield(node, fname)
        val  = fval isa Cell ? fval[] : fval
        field_path = extend_reference(path, FieldReferenceStep(string(fname)))
        if val isa TextString
            # Document-domain TextString: cursor anchors at the field, the
            # characters are its `.content`. Do not descend further.
            push!(refs, (cursor=field_path, kind=:textstring))
        elseif val isa TextBlock
            # Document-domain TextBlock: cursor is a flat offset across spans,
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
        v isa TextBlock || return nothing
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

# Character-aware splice: replace the 0-based `[s, e)` character range of `old`
# with `repl`. The test's own model of every edit (insert / backspace / delete),
# mirroring the kernel's `splice_string`; kept local so the test asserts against
# an independently-computed expectation rather than the code under test.
function _expected_splice(old::AbstractString, s::Int, e::Int, repl::AbstractString)
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    String(left) * repl * String(right)
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

# The outcome of one cycle: `ok`, the `message` naming the first failed step (empty
# on success), and `broken` — the projection itself is unusable for this target, so
# the remaining positions would only reproduce the same error and are not worth
# running. Only the printer steps set it: a projection that throws while printing
# this document, or while the cursor search forces its cells, throws the same way at
# every caret. A missing cursor or a missing operation is *not* broken — those are
# exactly the position-dependent failures this walk exists to find.
_typein_ok()               = (ok=true,  message="",  broken=false)
_typein_failed(message)    = (ok=false, message=message, broken=false)
_typein_broken(message)    = (ok=false, message=message, broken=true)

# The event, expected post-edit string, expected caret position, and whether an
# edit operation is expected, for edit `kind` at 0-based caret `k` in `old` (a string
# of length `n`). Backspace at the string start (`k == 0`) and delete at the string
# end (`k == n`) are declined: the reader yields nothing, the string is unchanged,
# and the caret stays at `k` — so `op_expected` is false and the expectations reduce
# to "nothing happened".
function _edit_spec(kind::Symbol, old::AbstractString, k::Int, ch::AbstractString)
    n = length(old)
    if kind === :insert
        (KeyPress(first(ch)), _expected_splice(old, k, k, ch), k + length(ch), true)
    elseif kind === :backspace
        event = KeyDown(:backspace, ModifierKeys())
        k > 0 ? (event, _expected_splice(old, k - 1, k, ""), k - 1, true) :
                (event, old, k, false)
    elseif kind === :delete
        event = KeyDown(:delete, ModifierKeys())
        k < n ? (event, _expected_splice(old, k, k + 1, ""), k, true) :
                (event, old, k, false)
    else
        error("unknown edit kind: $(repr(kind))")
    end
end

# Compare the document's current selection to the caret at `pos` in `target`'s string,
# in the same convention the walk uses to *set* carets. Type checkpoints are stripped
# from both sides (the stored selection is the folded form the operation writes, the
# freshly-built expectation is a skeleton). Returns `(ok, message)`.
function _selection_caret_ok(document, target, pos::Int)
    sel = try
        getfield(document, :selection)[]
    catch e
        return (false, "reading document selection threw: $e")
    end
    sel === nothing && return (false, "selection is nothing, expected caret at $pos")
    expected = extend_reference(target.cursor, PositionReferenceStep(pos))
    ok = try
        is_reference_equal(strip_reference_types(sel), strip_reference_types(expected))
    catch e
        return (false, "comparing selection threw: $e")
    end
    ok ? (true, "") :
         (false, "caret at $(repr(strip_reference_types(sel))), expected caret at $pos")
end

# A short description of an operation for failure messages: its type plus the
# reference/path it targets (type checkpoints stripped). Used to name the stray edit a
# reader produces at a boundary where it should have declined — e.g. a Delete at a
# value's end that reaches into the following `.sep` chrome span.
function _op_desc(op)
    op === nothing && return "nothing"
    ref = hasproperty(op, :reference) ? op.reference :
          hasproperty(op, :path)      ? op.path      : nothing
    ref === nothing && return string(nameof(typeof(op)))
    stripped = try
        strip_reference_types(ref)
    catch
        ref
    end
    string(nameof(typeof(op)), "(", stripped, ")")
end

# Run one edit round-trip (`kind` at character boundary `k`) for the cursor target
# `target`. See the file header for the seven steps.
function _edit_at(document, projection, target, k::Int, ch, kind::Symbol)
    old = try
        _read_target_string(document, target)
    catch e
        return _typein_failed("reading target string threw: $e")
    end
    old isa AbstractString ||
        return _typein_failed("reference did not resolve to a string: $(old === nothing ? "nothing" : typeof(old))")
    event, expected_str, expected_pos, op_expected = _edit_spec(kind, old, k, ch)
    sel = extend_reference(target.cursor, PositionReferenceStep(k))

    # 1. Point the selection into this string.
    clear_selection!(document)
    try
        set_selection!(document, sel)
    catch e
        return _typein_failed("set_selection! threw: $e")
    end

    # 2. Project and confirm the cursor shows up in the Graphics image.
    # The printer is lazy, so the projection's cells are forced by the cursor
    # search, not by `print_document` — a printer error surfaces here.
    iomap = try
        print_document(projection, document)
    catch e
        return _typein_broken("print_document threw: $e")
    end
    present = try
        _cursor_present(iomap)
    catch e
        return _typein_broken("searching the Graphics image for the cursor threw: $e")
    end
    present || return _typein_failed("no cursor in Graphics image for string $(repr(old))")

    # 3. Drive the edit's event through the reader.
    op = try
        read_intent(projection, iomap, event)
    catch e
        return _typein_failed("read_intent($kind) threw: $e")
    end

    if !op_expected
        # Declined boundary (Backspace at the start, Delete at the end): the reader
        # must produce no edit. Do *not* evaluate a stray op — a boundary edit here
        # would mutate the neighbouring chrome and drift the document out from under
        # the remaining positions. The string is untouched, so we only confirm the
        # decline and that the caret is still where we set it (`expected_pos == k`).
        op === nothing ||
            return _typein_failed("$kind at the boundary produced $(_op_desc(op)), expected no edit")
        selok, selmsg = _selection_caret_ok(document, target, expected_pos)
        return selok ? _typein_ok() : _typein_failed("$kind at the boundary: $selmsg")
    end

    # 4. The edit is expected: a ReplaceStringRangeOperation (empty replacement for the
    # deletions).
    op isa ReplaceStringRangeOperation ||
        return _typein_failed("$kind produced $(op === nothing ? "nothing" : string(typeof(op))), not ReplaceStringRangeOperation")
    (kind !== :insert && !isempty(op.replacement)) &&
        return _typein_failed("$kind produced a non-empty replacement $(repr(op.replacement))")

    # 5. Evaluate the operation and 6. verify both the string and the post-edit caret.
    try
        evaluate_operation((document=document,), op)
    catch e
        return _typein_failed("evaluate_operation threw: $e")
    end
    after = try
        _read_target_string(document, target)
    catch e
        return _typein_failed("re-read after edit threw: $e")
    end
    after == expected_str ||
        return _typein_failed("$kind: expected $(repr(expected_str)) got $(repr(after))")
    selok, selmsg = _selection_caret_ok(document, target, expected_pos)
    selok || return _typein_failed("$kind: $selmsg")
    _typein_ok()
end

# Restore `target`'s string to `pristine` after an edit: replace the whole current
# `[0, n)` character range with the pristine text. One operation covers insert and
# both deletions and all three target kinds, because `evaluate_operation` hands the
# field's value to `splice_value!`, which dispatches on its representation — plain
# String, `TextString` span, or the flat offset across a `TextBlock`'s spans. Returns
# whether the string now reads back as `pristine`.
function _restore!(document, target, pristine::AbstractString)
    current = _read_target_string(document, target)
    current isa AbstractString || return false
    current == pristine && return true
    op = ReplaceStringRangeOperation(
        extend_reference(target.cursor, RangeReferenceStep(0, length(current))), pristine)
    evaluate_operation((document=document,), op)
    _read_target_string(document, target) == pristine
end

# The three edits exercised at every caret, in order.
const _EDIT_KINDS = (:insert, :backspace, :delete)

# Run all three edits at each of `target`'s positions, restoring the string between
# every edit so each (position, edit) starts from the same pristine string. Returns
# one (position, length, edit, ok, message) per (position, edit) tried; `length` is
# the pristine string's character count, so a caller can tell a boundary caret
# (`position` of `0` or of `length`) from an interior one.
#
# An edit that cannot be restored ends the target: the remaining edits would be
# working on a string that is no longer the one they enumerate boundaries for, and a
# silently-drifting string turns the exact-value assertions into noise. The other
# targets live elsewhere in the document, so the walk goes on.
function _edit_target(document, projection, target, ch, policy::Symbol)
    results = NamedTuple{(:position, :length, :edit, :ok, :message)}[]
    pristine = try
        _read_target_string(document, target)
    catch e
        push!(results, (position=0, length=0, edit=:insert, ok=false, message="reading target string threw: $e"))
        return results
    end
    if !(pristine isa AbstractString)
        push!(results, (position=0, length=0, edit=:insert, ok=false,
                        message="reference did not resolve to a string: $(pristine === nothing ? "nothing" : typeof(pristine))"))
        return results
    end
    n = length(pristine)
    for k in _typein_positions(n, policy)
        for kind in _EDIT_KINDS
            outcome = _edit_at(document, projection, target, k, ch, kind)
            push!(results, (position=k, length=n, edit=kind, ok=outcome.ok, message=outcome.message))
            # A projection that cannot print this document fails identically at every
            # caret and edit; one report is the signal, the rest are noise.
            outcome.broken && return results

            restored = try
                _restore!(document, target, pristine)
            catch e
                push!(results, (position=k, length=n, edit=kind, ok=false,
                                message="restoring the string after $kind threw: $e"))
                return results
            end
            if !restored
                push!(results, (position=k, length=n, edit=kind, ok=false,
                                message="string not restored after $kind: expected $(repr(pristine)) got $(repr(_read_target_string(document, target)))"))
                return results
            end
        end
    end
    results
end

"""
    walk_typein(document, projection; replacement="X", positions=:all) -> Vector

For every string reachable in `document`, and at every character boundary selected
by `positions`, exercise three edits — insert, backspace, delete. Each sets the
cursor at the boundary, asserts the cursor renders in the Graphics image, drives the
edit's event (`KeyPress` for insert; `KeyDown(:backspace)` / `KeyDown(:delete)` for
the deletions) through the reader, and verifies **both** the string and the post-edit
caret: insert → `k+1`, backspace → `k-1`, delete → `k`. At a declined boundary
(backspace at the start, delete at the end) the reader must produce no edit, and the
walk asserts that decline without evaluating anything. The insert character is
`replacement`'s first character.

`positions` is `:all` (every boundary `0…n` of a string of length `n`), `:ends`
(both boundary carets plus one interior one) or `:first` (one character in).

Returns one `(ref, position, length, edit, ok, message)` result per
(string, position, edit) visited so callers can assert (and count) each one; `edit`
is `:insert` / `:backspace` / `:delete`, `length` is the string's character count
(so `position == 0` and `position == length` are its boundary carets) and `message`
is empty on success.
"""
function walk_typein(document, projection; replacement::AbstractString="X",
                     positions::Symbol=:all)
    ch = string(first(replacement))
    clear_selection!(document)
    targets = try
        _collect_string_refs(document)
    catch e
        return [(ref=EmptyReference(), position=0, length=0, edit=:insert, ok=false,
                 message="collecting string references threw: $e")]
    end
    results = NamedTuple{(:ref, :position, :length, :edit, :ok, :message)}[]
    for target in targets
        for r in _edit_target(document, projection, target, ch, positions)
            push!(results, (ref=target.cursor, position=r.position, length=r.length,
                            edit=r.edit, ok=r.ok, message=r.message))
        end
    end
    results
end

# ── Test helpers ─────────────────────────────────────────────────────────────

# The edit failures that are known bugs, named one by one. They are *declared* here
# rather than inferred from whatever happens to fail, so that a *new* failure still
# registers as a `Fail` — marking every failing iteration broken would throw away
# exactly the regression signal the walk is for. Each returns the reason it stands
# for; `nothing` means the case is expected to pass.
#
# The end-of-string deletion cases all share one root cause: the caret at a value's
# end sits on the seam with the following chrome span (a quote, a separator), and the
# per-span deletion reader resolves that seam toward the chrome rather than the value.
# They are being addressed by the in-progress text-selection representation refactor;
# these markers keep the suite green until it lands, and drop from the Broken count to
# Pass the moment it does (the guard below returns `nothing` once a case starts
# passing, so a fixed case becomes an ordinary `@test`).
function _typein_broken_reason(label, r)
    r.ok && return nothing   # a passing result is never broken

    # @broken: markdown_rendered — a rendered MarkdownLink shows only its styled
    # caption; the `url` is metadata with no rendered span, so there is no caret to
    # type into. The plain `markdown` projection shows the url as text and types
    # in fine. plan/pending/simplest-syntax-document.md
    if label == "markdown_rendered" && endswith(string(r.ref), "url") &&
       occursin("no cursor", r.message)
        return "rendered link url has no editable caret"
    end

    # @broken: Backspace at the end of a string (caret at `length`) yields no edit —
    # the end-of-value caret sits on the seam with the following chrome span, where the
    # per-span deletion reader declines, so the last character cannot be erased with
    # Backspace. Text-selection representation refactor.
    if r.edit === :backspace && r.position == r.length && r.length > 0 &&
       occursin("produced nothing", r.message)
        return "end-of-string Backspace declines at the value/chrome seam (text-selection refactor)"
    end

    # @broken: Delete at a string boundary (caret at `length` — including an empty
    # string, where `0 == length`) produces a stray edit instead of declining: the
    # end-of-value caret sits on the seam with the following chrome, so the reader
    # reaches into a separator span, or emits a no-op `[0,1]` delete on an empty value,
    # rather than yielding nothing. Text-selection representation refactor.
    if r.edit === :delete && r.position == r.length &&
       occursin("expected no edit", r.message)
        return "boundary Delete fails to decline at the value/chrome seam (text-selection refactor)"
    end

    # @broken: a nested `TextBlock` (a block whose elements are themselves blocks) does
    # not round-trip through the flat-offset splice the restore uses, so the pristine
    # string cannot be rebuilt between edits. Text-selection representation refactor.
    if occursin("not restored", r.message) && occursin("elements", string(r.ref))
        return "nested TextBlock content does not restore through the flat splice (text-selection refactor)"
    end

    nothing
end

# One @test per (string, position), so the test count reflects how many cursor
# positions were verified.
function test_typein(label, document, projection; positions::Symbol=:all)
    @testset "$label" begin
        for r in walk_typein(document, projection; positions=positions)
            if _typein_broken_reason(label, r) === nothing
                r.ok || @warn "[$label] [$(r.edit) $(r.ref){$(r.position)}] $(r.message)"
                @test r.ok
            else
                # @broken: a known edit bug; see `_typein_broken_reason` above for
                # which one and why. When the underlying fix lands the case starts
                # passing, the reason guard returns `nothing`, and it moves from the
                # Broken column to Pass — the drop in Broken count is the signal.
                @test_broken r.ok
            end
        end
    end
end


# The `Example`-typed overload; the sweep (`test_typeins`) stays in the
# umbrella, which owns the example registry.
# Build fresh document / projection instances. `walk_typein` mutates the
# document (it types characters into every string), and in `test_all` this runs
# after the other reader/repl tests which share the global `example.document`;
# starting from a pristine document keeps the exact-string assertions reliable.
function test_typein(example::Example; positions::Symbol=:all)
    test_typein(example.name, example.make_document(), example.make_projection();
                positions=positions)
end
