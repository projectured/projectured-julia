"""
    DocumentInsertionToSyntaxModule

The insert-by-typing mechanism, ported from the Common Lisp ProjecturEd
`document-to-syntax.lisp` — now with the live completion hint and green/red
commitability colouring.

`InsertionToSyntaxLeaf(commit; prefix, suffix, completion)` projects any
document with an editable `value::String` to a `SyntaxNode` rendered as
`prefix · value · ⟨continuation⟩ · suffix`. The reader edits `value`
character-by-character; the value's colour and the pale continuation are
computed cells driven by the `completion` policy (see `name_completion`):

- **green** typed text — the buffer names a candidate (or parses, for source
  insertions); with an **unambiguous** prefix the rest of the name renders as
  the **pale-green continuation**;
- **red** — no completion is possible;
- **Tab** accepts the continuation (the longest-common-prefix *partial*
  completion when ambiguous);
- **Enter** calls `commit(value)` — for name insertions that is
  `resolve_insertion` + `make_insertion_document` over the insertion's domain
  root, so an unambiguous prefix commits too;
- **Escape** aborts to the domain's own placeholder (`get_nothing_document`), the
  inverse of the placeholder's Insert gesture.

The candidates, names (`JsonString` / `json string`, prefix-free inside a
domain scope), and constructors all come from `DomainModule`'s
reflection — nothing here is a table. The chain is *domain-independent
insertion (`DocumentInsertion`) → domain-specific insertion
(`DomainInsertionToSyntaxLeaf(root)`) → the domain's values*, exactly as in
the Lisp editor.

Nothing here names a domain. A domain that wants a *source* insertion — one
that commits by parsing rather than by naming a type — builds its own leaf from
`InsertionToSyntaxLeaf` and `parse_completion`, in a file it already has.
`SqlInsertionToSyntaxLeaf` and `JuliaInsertionToSyntaxLeaf` are the two
examples.
"""
module DocumentInsertionToSyntaxModule

import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..DocumentModule: Document
import ..GestureBindingModule: read_gesture
import ..EventModule: KeyPress, KeyDown, ModifierKeys
import ..EventModule: MousePress
import ..DomainModule: DocumentInsertion, DocumentNothing
import ..DomainModule: get_insertion_root, get_nothing_document, get_insertion_names,
                       get_insertion_candidates, complete_insertion, name_completion,
                       resolve_insertion,
                       make_insertion_document
import ..TextModule: TextString
import ..SyntaxModule: SyntaxLeaf, SyntaxNode, SyntaxDocument, SyntaxDelimitation
import ..OperationModule: replace_document, ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep,
                          ElementReferenceStep, EmptyReference, Position, get_reference_node_type
import ..ProjectionReferenceStepModule: make_introduced_reference, is_introduced_reference
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..GestureBindingModule: GestureBinding
import ..EventPatternModule: KeyDownPattern, KeyPressPattern
import ..ProjectionGestureBindingsModule: get_projection_gesture_bindings, read_projection_gesture
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_italic_20, StyleFont
import ..ColorModule: color_solarized_gray, color_solarized_green, color_solarized_red,
                      color_completion_hint, color_default, StyleColor
import ..StyleTextModule: StyleText
import ..CollectionModule: CellVector, ComputedCellVector
import ..IoMapModule: SimpleIoMap
import ..CellModule: Cell, ComputedCell

export InsertionToSyntaxLeaf, DocumentInsertionToSyntaxLeaf, DomainInsertionToSyntaxLeaf,
       InsertionNothingToSyntaxLeaf,
       default_factory, default_completion, parse_completion,
       insert_insertion_text_operation, delete_insertion_text_operation

# ── Projection ────────────────────────────────────────────────────────────────

struct InsertionToSyntaxLeaf <: Projection
    prefix::String
    suffix::String
    commit::Any            # (value::String) -> Union{Document,Nothing}
    completion::Any        # (ins) -> (state::Symbol, continuation::String)
    # The label (prefix/suffix), the editable value, and the completion hint
    # share a font but are coloured distinctly, so each is its own StyleText.
    # The value's colour is only the *neutral* (`:empty`) colour — a non-empty
    # buffer is coloured live by its completion state (green/red).
    label::StyleText
    value::StyleText
    hint::StyleText
end

InsertionToSyntaxLeaf(commit; prefix::AbstractString = "", suffix::AbstractString = "",
                      completion = name_completion,
                      label = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray),
                      value = StyleText(font_ubuntu_monospace_regular_20, color_default),
                      hint  = StyleText(font_ubuntu_monospace_regular_20, color_completion_hint)) =
    InsertionToSyntaxLeaf(String(prefix), String(suffix), commit, completion, label, value, hint)

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
    state === :invalid ? color_solarized_red :
    state === :empty   ? p.value.color      : color_solarized_green

# ── Selection mapping ─────────────────────────────────────────────────────────
#
# The output is a SyntaxDelimitation (the label's prefix/suffix) around one SyntaxLeaf
# (typed value + hint), so the `value{k}` char cursor maps through `.content` — a wrapper
# addresses its single child there, not at `.children[1]`.

function map_reference_forward(::InsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        # Whole insertion → whole delimitation, typed against the output (as the
        # generic `Projection` fallback does) so a parent that splices it — e.g.
        # `YamlSequence`'s `.content.^(inner)` — keeps a fully-typed reference.
        ∅        => EmptyReference(get_reference_node_type(iomap.output))
        value{k} => begin
            inner = @reference ::SyntaxLeaf.value::TextString{k}::Position
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
            ::SyntaxLeaf.value{k} => @reference ::DocumentInsertion.value::String{k}::Position
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
    typed = TextString(ComputedCell(() -> something(ins.value, "")),
                       Cell(p.value.font),
                       ComputedCell(() -> _typed_color(p, p.completion(ins).state)),
                       Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    hint = TextString(ComputedCell(() -> p.completion(ins).hint),
                      Cell(p.hint.font), Cell(p.hint.color),
                      Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    # The inner leaf's selection is the insertion's own (`value{k}` is the
    # leaf-local grammar too); the wrapper routes it through `.content`.
    leaf = SyntaxLeaf(typed; close=hint, selection=getfield(ins, :selection))
    node_selection = ComputedCell(() -> begin
        path = getfield(ins, :selection)[]
        path isa ConcreteReference || return nothing
        is_introduced_reference(path) && return path
        ConcreteReference(FieldReferenceStep("content"), path)
    end)
    SimpleIoMap(p, ins, SyntaxDelimitation(leaf;
        opening_delimiter=TextString(p.prefix, p.label),
        closing_delimiter=TextString(p.suffix, p.label),
        selection=node_selection))
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

function read_intent(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    # A caret in the rendered value span backward-maps to the value cursor; a
    # caret on the label/hint spans becomes an introduced caret on the whole
    # insertion; a raw input-vocabulary `value{k}` op passes through.
    mapped = map_reference_backward(p, iomap, op.path)
    mapped !== nothing && return ReplaceSelectionOperation(mapped)
    path = op.path
    path isa ConcreteReference || return nothing
    h = path.head
    h isa FieldReferenceStep || return nothing
    h.name == "value" ? op :
        ReplaceSelectionOperation(make_introduced_reference(p, iomap.input, path))
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
    ReplaceStringRangeOperation(mapped, op.replacement)
end

# Own gestures, reified as a `get_projection_gesture_bindings` table fired through
# `read_projection_gesture` -- so the same set that fires is what a listing
# shows. Value char-editing (insert / Backspace / Delete) mirrors PrimitiveString;
# Commit / Cancel are projection-specific (they call `p.commit` / abort to a
# `DocumentNothing`), which is why this stays a projection table rather than a
# document-level `@gestures`. ModifierKeys are matched loosely (`mods=nothing`) to
# preserve the old bare `@event_case` patterns exactly. Operations capture `p`/`ins`
# and return `nothing` to decline (no value cursor / commit refused).
function get_projection_gesture_bindings(p::InsertionToSyntaxLeaf, iomap)
    ins = iomap.input
    GestureBinding[
        GestureBinding(KeyDownPattern(:return, nothing, nothing),
            (doc, event) -> _insertion_commit(p, ins),
            (doc, sel) -> true, "Commit insertion", "insertion"),
        # Escape aborts to the domain's own placeholder (`get_nothing_document`, a
        # `@domain` trait) — `JsonInsertion` → `JsonNothing`, … — closing the
        # Insert ⇄ Escape loop within each domain.
        GestureBinding(KeyDownPattern(:escape, nothing, nothing),
            (doc, event) -> replace_document(EmptyReference(),
                                             get_nothing_document(typeof(ins))()),
            (doc, sel) -> true, "Cancel insertion", "insertion"),
        # Tab accepts the completion: the full remainder when unambiguous, the
        # longest-common-prefix *partial* completion when ambiguous; declines
        # (keeps propagating) when there is nothing to extend.
        GestureBinding(KeyDownPattern(:tab, nothing, nothing),
            (doc, event) -> _insertion_tab(p, ins),
            (doc, sel) -> true, "Accept completion", "insertion"),
        GestureBinding(KeyDownPattern(:backspace, nothing, nothing),
            (doc, event) -> delete_insertion_text_operation(ins, :backspace),
            (doc, sel) -> true, "Delete backward", "insertion"),
        GestureBinding(KeyDownPattern(:delete, nothing, nothing),
            (doc, event) -> delete_insertion_text_operation(ins, :delete),
            (doc, sel) -> true, "Delete forward", "insertion"),
        GestureBinding(KeyPressPattern(nothing),
            (doc, event) -> insert_insertion_text_operation(ins, event.text),
            (doc, sel) -> true, "Insert character", "insertion"),
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
    doc = p.commit(something(ins.value, ""))
    doc === nothing ? nothing : replace_document(EmptyReference(), doc)
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
    event isa Union{KeyPress, KeyDown, MousePress} && iomap.input isa Document ?
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
    DocumentInsertionToSyntaxLeaf()

The domain-independent insertion: `"Insert a new <name> here"`, committing via
`default_factory` (type a domain name + Enter).
"""
DocumentInsertionToSyntaxLeaf() =
    InsertionToSyntaxLeaf(default_factory; prefix = "Insert a new ", suffix = " here")

"""
    DomainInsertionToSyntaxLeaf(root; prefix = "insert a new ", suffix = " here")

A domain-constrained insertion: the shared typed-name buffer completing over
`root`'s reflected candidates **prefix-free** (inside a `JsonInsertion`,
`string`/`String` names `JsonString`), committing the resolved type's
`make_insertion_document`. The default completion policy already scopes to
`get_insertion_root(typeof(ins))`, so the leaf only needs the matching commit.
"""
DomainInsertionToSyntaxLeaf(root::Type;
                            prefix::AbstractString = "insert a new ",
                            suffix::AbstractString = " here") =
    InsertionToSyntaxLeaf(value -> begin
            T = resolve_insertion(root, value)
            T === nothing ? nothing : make_insertion_document(T)
        end; prefix, suffix)

# ── InsertionNothingToSyntaxLeaf: the *Nothing placeholder rendering ───────────────────

# "JsonNothing" → "empty json"; the universal `DocumentNothing` → "empty document".
function _nothing_label(doc)
    n = String(nameof(typeof(doc)))
    base = endswith(n, "Nothing") ? n[1:end-length("Nothing")] : n
    isempty(base) ? "empty document" : "empty " * lowercase(base)
end

"""
    InsertionNothingToSyntaxLeaf()

The shared leaf for the `@domain` `*Nothing` placeholders: a muted italic
`empty json` / `empty xml` label. Printer-only — raw input falls through the
generic gesture fallback, so the placeholder's Insert binding (turn into the
domain's insertion) fires from the document-level table.
"""
@projection struct InsertionNothingToSyntaxLeaf <: Projection
    style::ImmutableCell{StyleText}
end

InsertionNothingToSyntaxLeaf() =
    InsertionNothingToSyntaxLeaf(StyleText(font_ubuntu_monospace_italic_20, color_solarized_gray))

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
        selection = ComputedCell(() -> begin
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
    read_gesture(iomap.input, KeyPress(first(text), text, ModifierKeys()))
end

end # module
