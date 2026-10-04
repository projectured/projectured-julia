# Fragment of `SyntaxModule`.
#
# The insert-by-typing mechanism, ported from the Common Lisp ProjecturEd
# `document-to-syntax.lisp` — now with the live completion hint and green/red
# commitability colouring.
#
# `InsertionToSyntaxLeaf(commit; prefix, suffix, completion)` projects any
# document with an editable `value::String` to a `SyntaxDelimitation` rendered
# as `prefix · value · ⟨continuation⟩ · suffix`. The reader edits `value`
# character-by-character; the value's colour and the pale continuation are
# computed cells driven by the `completion` policy (see `name_completion`):
#
# - **green** typed text — the buffer names a candidate (or parses, for source
#   insertions); with an **unambiguous** prefix the rest of the name renders as
#   the **pale-green continuation**;
# - **red** — no completion is possible;
# - **Tab** accepts the continuation (the longest-common-prefix *partial*
#   completion when ambiguous);
# - **Enter** calls `commit(insertion, text)` — for name insertions that is
#   `resolve_insertion` + `make_insertion_document` over the insertion's domain
#   root, so an unambiguous prefix commits too;
# - **Escape** aborts to the domain's own placeholder (`get_nothing_document`), the
#   inverse of the placeholder's Insert gesture, or to what the option `cancel`
#   gives;
# - with the option `commit_at_key`, a key whose text names a document replaces
#   the insertion with it at once, with the caret where the key left it.
#
# The candidates, names (`JsonString` / `json string`, prefix-free inside a
# domain scope), and constructors all come from `DomainModule`'s
# reflection — nothing here is a table. The chain is *domain-independent
# insertion (`DocumentInsertion`) → domain-specific insertion
# (`DomainInsertionToSyntaxLeaf(root)`) → the domain's values*, exactly as in
# the Lisp editor.
#
# Nothing here names a domain. A domain that wants a *source* insertion — one
# that commits by parsing rather than by naming a type — builds its own leaf from
# `InsertionToSyntaxLeaf` and `parse_completion`, in a file it already has.
# `SqlInsertionToSyntaxLeaf` is such an example. `JuliaInsertionToSyntaxLeaf` is
# not: it is a hand-written `@projection` of its own, with its own
# `print_document` and reference mapping.
# ── Projection ────────────────────────────────────────────────────────────────

struct InsertionToSyntaxLeaf <: Projection
    prefix::String
    suffix::String
    commit::Any            # (ins, text::String) -> Union{Document,Nothing}
    completion::Any        # (ins) -> (state::Symbol, continuation::String)
    # `nothing`, or (ins, text::String, caret::Int) -> Union{Document,Nothing}:
    # the document that replaces the insertion at the key that makes `text`, with
    # its caret at `caret`, or `nothing` to keep the insertion.
    commit_at_key::Any
    # `nothing`, or (ins) -> Document: what Escape puts in place of the insertion;
    # `nothing` puts the empty document of its domain.
    cancel::Any
    # The label (prefix/suffix), the editable value, and the completion hint
    # share a font but are coloured distinctly, so each is its own StyleText.
    # The value's colour is only the *neutral* (`:empty`) colour — a non-empty
    # buffer is coloured live by its completion state (`found_color` when it
    # names one thing, `wrong_color` when it names none). Each style field holds a
    # value, or a cell that reads the scaled `SyntaxTheme` (`unwrap_cell`).
    label::Any
    value::Any
    hint::Any
    wrong_color::Any
    found_color::Any
    # What an empty buffer shows in place of `prefix · suffix`, in the colour of the
    # label, as the other empty fields of a domain show a hint; `nothing` keeps the
    # frame around the empty name.
    # The text of an empty buffer, a function of the insertion that gives it, or
    # `nothing` for none.
    placeholder::Any
end

function InsertionToSyntaxLeaf(commit; prefix::AbstractString = "", suffix::AbstractString = "",
                               completion = name_completion, commit_at_key = nothing,
                               cancel = nothing, theme = nothing,
                               label = nothing, value = nothing, hint = nothing,
                               placeholder::Union{Nothing,AbstractString,Function} = nothing)
    InsertionToSyntaxLeaf(String(prefix), String(suffix), commit, completion, commit_at_key, cancel,
                          something(label, get_syntax_style(theme, :label_text)),
                          something(value, get_syntax_style(theme, :typed_text)),
                          something(hint, get_syntax_style(theme, :hint_text)),
                          get_syntax_style(theme, :wrong_color),
                          get_syntax_style(theme, :found_color),
                          placeholder isa AbstractString ? String(placeholder) : placeholder)
end

# ── Completion policies ───────────────────────────────────────────────────────
#
# A policy maps the insertion to `(; state, hint, extension)`:
#   state     — :empty (neutral) / :invalid (red) / :ambiguous / :unambiguous (green);
#   hint      — the pale continuation rendered after the typed text (per spec
#               only when the prefix is unambiguous);
#   extension — what Tab appends: the matching names' common remainder, which
#               on an ambiguous prefix is the *partial* completion the hint
#               doesn't show.


# Source insertions (SQL) are committable when the buffer parses: green =
# complete source, red = not (yet) parseable; there is nothing to Tab-extend.
parse_completion(parser) = ins -> begin
    value = something(ins.value, "")
    isempty(strip(value)) && return (state = :empty, hint = "", extension = "")
    parsed = try parser(value); true catch; false end
    (state = parsed ? :unambiguous : :invalid, hint = "", extension = "")
end

# state → typed-text colour; the neutral colour comes from the projection.
_typed_color(p, state::Symbol) =
    state === :invalid ? unwrap_cell(p.wrong_color) :
    state === :empty   ? unwrap_cell(p.value).color : unwrap_cell(p.found_color)

# ── Selection mapping ─────────────────────────────────────────────────────────
#
# The output is a SyntaxDelimitation (the label's prefix/suffix) around one SyntaxLeaf
# (typed value + hint), so a `value{s:e}` range maps through `.content` — a wrapper
# addresses its single child there, not at `.children[1]`. The pattern is the range and
# not the caret `value{k}`: a caret is the range `{k:k}`, and Backspace or Delete reaches
# this leaf as an edit of the one-character range it removes.

function map_reference_forward(p::InsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        # Whole insertion → whole delimitation, typed against the output (as the
        # generic `Projection` fallback does) so a parent that splices it — e.g.
        # `YamlSequence`'s `.content.^(inner)` — keeps a fully-typed reference.
        ∅        => EmptyReference(get_reference_node_type(iomap.output))
        # A caret on the label or the hint, which this projection printed.
        proj(^(p), inner) => inner
        value{s:e} => begin
            inner = @reference ::SyntaxLeaf.value::TextString{s:e}::Position
            @reference ::SyntaxDelimitation.content.^(inner)
        end
    end
end

function map_reference_backward(::InsertionToSyntaxLeaf, iomap, reference)
    # The value buffer's end sits at the same flat as the suffix (closing delimiter)
    # starts, and for an *empty* buffer (a fresh `JsonInsertion`) that is the buffer's
    # only caret — otherwise unreachable, since the zero-width value span is shadowed
    # by the suffix when the flat resolves. Redirect `closing_delimiter{0}` into
    # `value{len}` so the insertion buffer is always navigable (type there to fill it),
    # mirroring SyntaxLeafToText's value/close-seam redirect one layer down.
    n = length(something(iomap.input.value, ""))
    whole = EmptyReference(get_reference_node_type(iomap.input))   # typed whole insertion
    @reference_case reference begin
        ∅ => whole                                     # whole delimitation → whole insertion
        ::SyntaxDelimitation.content.leaf_path... => @reference_case leaf_path begin
            ∅ => whole                                 # whole content leaf → whole insertion
            ::SyntaxLeaf.value{s:e} => @reference ::DocumentInsertion.value::String{s:e}::Position
            # The hint, and a placeholder in its place, is no text of the name: a
            # caret on it is the caret at the end of the name.
            ::SyntaxLeaf.close{k} => ConcreteReference(DocumentInsertion, FieldReferenceStep("value"),
                ConcreteReference(String, RangeReferenceStep(n, n), EmptyReference(Position)))
        end
        ::SyntaxDelimitation.closing_delimiter{k} => (k == 0 ?
            ConcreteReference(DocumentInsertion, FieldReferenceStep("value"),
                ConcreteReference(String, RangeReferenceStep(n, n), EmptyReference(Position))) :
            nothing)
    end
end

# ── Printer ──────────────────────────────────────────────────────────────────
#
# `prefix · value · ⟨continuation⟩ · suffix` — the value's colour and the
# continuation's content are computed cells over `ins.value`, so the
# commitability feedback updates per keystroke with no re-print.

function print_document(p::InsertionToSyntaxLeaf, recursion, ins, ctx)
    iomap_cell = Cell(nothing)
    label_style = unwrap_cell(p.label)
    hint_style = unwrap_cell(p.hint)
    typed = TextString(Cell(@computation something(ins.value, "")),
                       Cell(unwrap_cell(p.value).font),
                       Cell(@computation _typed_color(p, p.completion(ins).state)),
                       Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    # An empty buffer with a placeholder shows the placeholder alone: it stands in
    # the span of the completion hint, and the frame of the label is empty.
    placeholder_of() = p.placeholder isa Function ? p.placeholder(ins) : p.placeholder
    shows_placeholder() = placeholder_of() !== nothing && isempty(something(ins.value, ""))
    hint = TextString(Cell(@computation shows_placeholder() ? placeholder_of() : p.completion(ins).hint),
                      Cell(hint_style.font),
                      Cell(@computation shows_placeholder() ? label_style.color : hint_style.color),
                      Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    frame(text) = TextString(Cell(@computation shows_placeholder() ? "" : text),
                             Cell(label_style.font), Cell(label_style.color),
                             Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    # **The rendered selection is the FORWARD IMAGE of the insertion's own, not a
    # copy of it.** The buffer's cursor is `value{k}` in the insertion's grammar,
    # and the same place is `content::SyntaxLeaf.value::TextString{k}` in the
    # output's. The layer below lowers a keystroke against what it sees, so a
    # cursor left in the input's vocabulary comes back as a path this projection's
    # backward map does not recognize, and the keystroke is dropped: the buffer
    # draws a caret nobody can type at.
    #
    # The wrapper takes the whole image, and the leaf inside it takes the image
    # without the `content` step that leads to the leaf.
    node_paths = make_output_path_cells(ins, path ->
        path isa ConcreteReference ? map_reference_forward(p, iomap_cell[], path) : nothing)
    leaf_path(node_cell) = Cell(@computation begin
        whole = node_cell[]
        whole isa ConcreteReference || return nothing
        @reference_case whole begin
            content.rest... => rest
        end
    end)
    leaf = SyntaxLeaf(typed; close=hint, selection=leaf_path(node_paths.selection),
                      mouse_target=leaf_path(node_paths.mouse_target))
    io = SimpleIoMap(p, ins, SyntaxDelimitation(leaf;
        opening_delimiter=frame(p.prefix),
        closing_delimiter=frame(p.suffix),
        node_paths...))
    iomap_cell[] = io
    io
end

# ── Value-edit helpers (mirror PrimitiveStringToSyntaxLeaf) ────────────────────

function _value_range(ins)
    sel = getfield(ins, :selection)[]
    sel = sel
    sel isa ConcreteReference || return nothing
    h = sel.head
    (h isa FieldReferenceStep && h.name == "value") || return nothing
    t = sel.tail
    t isa ConcreteReference || return nothing
    t.head isa RangeReferenceStep || return nothing
    t.head
end

_value_path(range::RangeReferenceStep) =
    ConcreteReference(FieldReferenceStep("value"),
        ConcreteReference(range, EmptyReference()))

# ── Reader ───────────────────────────────────────────────────────────────────

function read_intent(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplacePathOperation)
    # A caret in the rendered value span backward-maps to the value cursor; a
    # caret on the label/hint spans becomes an introduced caret on the whole
    # insertion; a raw input-vocabulary `value{k}` op passes through.
    mapped = map_reference_backward(p, iomap, op.path)
    mapped !== nothing && return make_path_operation(op, mapped)
    path = op.path
    path isa ConcreteReference || return nothing
    h = path.head
    h isa FieldReferenceStep || return nothing
    h.name == "value" ? op :
        make_path_operation(op, make_introduced_reference(p, iomap, path))
end

# A text edit lowered onto the buffer's rendered value span (the pipeline turns a
# keystroke into a `ReplaceStringRangeOperation` before it reaches here) backward-maps
# to the buffer's own `value[range]` — the same value the `Insert character` gesture
# edits. An edit on a label/hint span has no value pre-image and declines. Without this
# the generic leaf reader has no `ReplaceStringRangeOperation` method and typing into the
# buffer through the full projection throws.
function read_intent(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceStringRangeOperation)
    mapped = map_reference_backward(p, iomap, op.reference)
    mapped === nothing && return nothing
    _make_insertion_key_operation(p, iomap.input, ReplaceStringRangeOperation(mapped, op.replacement))
end

# Own gestures, reified as a `get_projection_gesture_bindings` table fired through
# `read_projection_gesture` -- so the same set that fires is what a listing
# shows. Value char-editing (insert / Backspace / Delete) mirrors PrimitiveString;
# Commit / Cancel are projection-specific (they call `p.commit` / abort to a
# `DocumentNothing`), which is why this stays a projection table rather than a
# document-level `@gestures`. ModifierKeys are matched loosely (`mods=nothing`) to
# preserve the old bare `@gesture_case` patterns exactly. Operations capture `p`/`ins`
# and return `nothing` to decline (no value cursor / commit refused).
function get_projection_gesture_bindings(p::InsertionToSyntaxLeaf, iomap)
    ins = iomap.input
    GestureBinding[
        GestureBinding(KeyDownPattern(:return),
                       (doc, event) -> _insertion_commit(p, ins);
                       description = "Commit insertion", domain = "insertion"),
        # Escape aborts to the domain's own placeholder (`get_nothing_document`, a
        # `@domain` trait) — `JsonInsertion` → `JsonNothing`, … — closing the
        # Insert ⇄ Escape loop within each domain.
        GestureBinding(KeyDownPattern(:escape),
                       (doc, event) -> _make_insertion_cancel_operation(p, ins);
                       description = "Cancel insertion", domain = "insertion"),
        # Tab accepts the completion: the full remainder when unambiguous, the
        # longest-common-prefix *partial* completion when ambiguous; declines
        # (keeps propagating) when there is nothing to extend.
        GestureBinding(KeyDownPattern(:tab),
                       (doc, event) -> _insertion_tab(p, ins);
                       description = "Accept completion", domain = "insertion"),
        GestureBinding(KeyDownPattern(:backspace),
                       (doc, event) -> _make_insertion_key_operation(p, ins,
                                           delete_insertion_text_operation(ins, :backspace));
                       description = "Delete backward", domain = "insertion"),
        GestureBinding(KeyDownPattern(:delete),
                       (doc, event) -> _make_insertion_key_operation(p, ins,
                                           delete_insertion_text_operation(ins, :delete));
                       description = "Delete forward", domain = "insertion"),
        GestureBinding(KeyPressPattern(nothing),
                       (doc, event) -> _make_insertion_key_operation(p, ins,
                                           insert_insertion_text_operation(ins, event.text));
                       description = "Insert character", domain = "insertion"),
    ]
end

# Insert printable text at the value cursor; nothing without a value[range] cursor.
function insert_insertion_text_operation(ins, text)
    range = _value_range(ins)
    range === nothing ? nothing : ReplaceStringRangeOperation(_value_path(range), text)
end

# Commit the typed value through the projection's `commit` callback; nothing when
# the callback refuses (unknown/incomplete value).
function _insertion_commit(p::InsertionToSyntaxLeaf, ins)
    doc = p.commit(ins, something(ins.value, ""))
    doc === nothing ? nothing : make_replace_document_operation(EmptyReference(), doc)
end

# Escape: the document of the option `cancel`, or the empty document of the
# domain of the insertion.
_make_insertion_cancel_operation(p::InsertionToSyntaxLeaf, ins) =
    make_replace_document_operation(EmptyReference(),
                     p.cancel === nothing ? get_nothing_document(typeof(ins))() : p.cancel(ins))

# A key that edits the text of `ins`: `operation`, a range replace at `value{s:e}`,
# or a replace of the insertion with the document that the option `commit_at_key`
# gives for the text after the key.
function _make_insertion_key_operation(p::InsertionToSyntaxLeaf, ins, operation)
    (p.commit_at_key === nothing || operation === nothing) && return operation
    range = find_value_range(operation.reference)
    range === nothing && return operation
    text = splice_string(something(ins.value, ""), range.start, range.stop, operation.replacement)
    document = p.commit_at_key(ins, text, range.start + length(operation.replacement))
    document === nothing ? operation :
        make_replace_document_operation(EmptyReference(), document)
end

# Append the completion policy's Tab extension at the end of the buffer, caret
# after it; nothing without a value cursor or with nothing to extend.
function _insertion_tab(p::InsertionToSyntaxLeaf, ins)
    _value_range(ins) === nothing && return nothing
    extension = p.completion(ins).extension
    isempty(extension) && return nothing
    n = length(something(ins.value, ""))
    ReplaceStringRangeOperation(_value_path(RangeReferenceStep(n, n)), extension)
end

# Backspace/Delete range computation; nothing at the value boundary.
function delete_insertion_text_operation(ins, dir::Symbol)
    range = _value_range(ins)
    range === nothing && return nothing
    n = length(something(ins.value, ""))
    new_range = if range.start != range.stop
        range
    elseif dir === :backspace
        range.start > 0 ? RangeReferenceStep(range.start - 1, range.start) : nothing
    else  # :delete
        range.stop < n ? RangeReferenceStep(range.stop, range.stop + 1) : nothing
    end
    new_range === nothing ? nothing : ReplaceStringRangeOperation(_value_path(new_range), "")
end

# The projection's own table first (buffer editing / commit / cancel / Tab);
# when every binding declines — e.g. a printable char with no value cursor —
# fall through to the input document's own gesture table, exactly like the
# generic `read_intent` leaf default this method shadows. That keeps the
# whole-selection authoring gestures firing on the domain insertions
# (`@gestures JsonDocument`'s `"`/`[`/`{`/digit type-to-replace, …).
function read_intent(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, event)
    op = read_projection_gesture(p, iomap, event)
    op !== nothing && return op
    event isa Union{KeyPress, KeyDown, MouseClick} && iomap.input isa Document ?
        read_gesture(iomap.input, event) : nothing
end

# ── Name → document: reflection over the type tree ────────────────────────────
#
# No factory table: the candidates are `get_insertion_candidates(Document)` (every
# insertable concrete document type, computed by reflection and memoized on the
# world counter), the accepted names are derived from the type names
# (`"JsonString"` / `"json string"`), and construction goes through
# `make_insertion_document` dispatch. The historic short names (`"julia"`,
# `"json"`, …) live on as `get_insertion_aliases` emitted by each `@domain`.

"""
    default_factory(name) -> Document | nothing

Map a typed name to a fresh document — an exact name/alias match or an
unambiguous prefix of the reflected top-level candidates (`resolve_insertion`
over `Document`), or `nothing` when `name` doesn't name a committable type.
"""
function default_factory(name::AbstractString)
    T = resolve_insertion(Document, name)
    T === nothing ? nothing : make_insertion_document(T)
end

"""
    default_completion(name) -> String

The completion continuation for a partially-typed name (e.g. `"jso"` → `"n"`,
the matching candidates' common remainder), or `""`.
"""
default_completion(name::AbstractString) =
    complete_insertion(Document, name).continuation


# ── Convenience constructors ───────────────────────────────────────────────────

"""
    DocumentInsertionToSyntaxLeaf(; theme = nothing)

The domain-independent insertion: `"Insert a new <name> here"`, committing via
`default_factory` (type a domain name + Enter). `theme` is a `SyntaxTheme`, a
scaled one, or `nothing` for the default styles.
"""
DocumentInsertionToSyntaxLeaf(; theme = nothing) =
    InsertionToSyntaxLeaf((ins, text) -> default_factory(text); prefix = "Insert a new ", suffix = " here",
                          theme)

"""
    DomainInsertionToSyntaxLeaf(root; prefix = "insert a new ", suffix = " here", placeholder = nothing,
                                theme = nothing)

A domain-constrained insertion: the shared typed-name buffer completing over
`root`'s reflected candidates **prefix-free** (inside a `JsonInsertion`,
`string`/`String` names `JsonString`), committing the resolved type's
`make_insertion_document`. The default completion policy already scopes to
`get_insertion_root(typeof(ins))`, so the leaf only needs the matching commit.
`theme` styles it as for `InsertionToSyntaxLeaf`.
"""
DomainInsertionToSyntaxLeaf(root::Type;
                            prefix::AbstractString = "insert a new ",
                            suffix::AbstractString = " here",
                            placeholder::Union{Nothing,AbstractString} = nothing,
                            theme = nothing) =
    InsertionToSyntaxLeaf((ins, value) -> begin
            T = resolve_insertion(root, value)
            T === nothing ? nothing : make_insertion_document(T)
        end; prefix, suffix, placeholder, theme)

# ── InsertionNothingToSyntaxLeaf: the *Nothing placeholder rendering ───────────────────

# "JsonNothing" → "empty json"; the universal `DocumentNothing` → "empty document".
function _nothing_label(doc)
    n = String(nameof(typeof(doc)))
    base = endswith(n, "Nothing") ? n[1:end-length("Nothing")] : n
    isempty(base) ? "empty document" : "empty " * lowercase(base)
end

"""
    InsertionNothingToSyntaxLeaf(; theme = nothing)

The shared leaf for the `@domain` `*Nothing` placeholders: a muted italic
`empty json` / `empty xml` label. Printer-only — raw input falls through the
generic gesture fallback, so the placeholder's Insert binding (turn into the
domain's insertion) fires from the document-level table.
"""
@projection UntrackedCell struct InsertionNothingToSyntaxLeaf <: Projection
    style::StyleText
end

InsertionNothingToSyntaxLeaf(; theme = nothing) =
    InsertionNothingToSyntaxLeaf(get_syntax_style(theme, :note_text))

# The rendered leaf's selection is the *forward image* of the document's own — not
# the raw path. A cursor on the label is carried on the placeholder as a
# projection-introduced caret (`proj(p, value{k})`, from the generic backward
# below); forward-mapping unwraps it to the leaf's own `value{k}`, so the label is
# char-navigable via `ProjectionReferenceStep` steps (like every literal leaf). Copying
# the raw path instead left the leaf holding a `proj(p, …)` cursor that
# `SyntaxLeafToText` cannot place, so navigation stalled at the label. The forward
# ref-break (fill `iomap_cell` after) mirrors the compound printers.
function print_document(p::InsertionNothingToSyntaxLeaf, recursion, doc, ctx)
    iomap_cell = Cell(nothing)
    leaf = SyntaxLeaf(TextString(_nothing_label(doc), p.style);
        selection = Cell(@computation begin
            s = getfield(doc, :selection)[]
            s === nothing ? nothing : map_reference_forward(p, iomap_cell[], s)
        end))
    io = SimpleIoMap(p, doc, leaf)
    iomap_cell[] = io
    io
end

# No reference maps of our own: the generic `Projection` fallback already round-trips
# a whole-element (∅) selection — typed against the document — and wraps a cursor on
# the display-only label as a projection-introduced caret (unwrapped by the forward
# map above). A bespoke map here would only shadow that.

# A printable key typed on the placeholder is a *create* gesture, not a text edit —
# the label ("empty json") is a prompt, not content. The text layer, seeing a caret,
# turned the key into an insert on the (non-editable) label, which arrives here as a
# `ReplaceStringRangeOperation`; re-interpret it as the underlying document's own
# gesture so `{` on an `empty json` makes a JsonObject, `[` an array, a digit a
# number, and so on — from any caret, no ∅ selection required. This is what lets a
# `*Nothing` placeholder be filled by typing directly. Non-empty text only (a
# deletion has nothing to create); a key the document defines no create for
# (`read_gesture` → `nothing`) is simply dropped, exactly as on a ∅ selection.
function read_intent(::InsertionNothingToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceStringRangeOperation)
    text = op.replacement
    isempty(text) && return nothing
    read_gesture(iomap.input, KeyPress(first(text), text, ModifierKeys(); time = time()))
end
