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
- **Escape** aborts to the domain's own placeholder (`nothing_document`), the
  inverse of the placeholder's Insert gesture.

The candidates, names (`JsonString` / `json string`, prefix-free inside a
domain scope), and constructors all come from `DomainModule`'s
reflection — nothing here is a table. The chain is *domain-independent
insertion (`DocumentInsertion`) → domain-specific insertion
(`DomainInsertionToSyntaxLeaf(root)`) → the domain's values*, exactly as in
the Lisp editor; `JuliaInsertion` additionally commits arbitrary source via
`juliaparse` (keyword prefixes expand to hole scaffolds), `SqlInsertion` via
`sqlparse`.
"""
module DocumentInsertionToSyntaxModule

import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..DocumentApiModule: Document
import ..SelectionApiModule: with_selection
import ..GestureBindingModule: read_gesture
import ..EventModule: KeyPress, KeyDown
import ..EventModule: MousePress
import ..DocumentCoreModule: DocumentInsertion, DocumentNothing
import ..DomainModule
import ..DomainModule: var"@insertion", insertion_root, nothing_document, insertion_names,
                       insertion_candidates, complete_insertion, resolve_insertion,
                       make_insertion_document
import ..JuliaModule: JuliaInsertion, JuliaDocument,
                      JuliaFunction, JuliaIf, JuliaWhile, JuliaFor, JuliaForIterator,
                      JuliaBegin, JuliaReturn, JuliaBlock
import ..JsonModule: JsonInsertion
import ..XmlModule: XmlInsertion
import ..SqlDocumentModule: SqlInsertion
import ..TextModule: TextText, TextString
import ..JuliaParserModule: juliaparse
import ..SqlParserModule: sqlparse
import ..SyntaxModule: SyntaxLeaf, SyntaxNode, SyntaxDocument
import ..OperationModule: replace_document, ReplaceSelectionOperation,
                          SelectNextInsertionOperation, CompoundOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference,
                          ElementReference, EmptyReferencePath, Position
import ..ProjectionReferenceModule: ProjectionReference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..GestureBindingModule: GestureBinding, var"@gestures"
import ..EventPatternModule: KeyDownPattern, KeyPressPattern
import ..ProjectionGestureBindingsModule: get_projection_gesture_bindings, read_projection_gesture
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_italic_20, StyleFont
import ..ColorModule: color_solarized_gray, color_solarized_green, color_solarized_red,
                      color_completion_hint, color_default, StyleColor
import ..StyleTextModule: StyleText
import ..CollectionModule: CellVector
import ..IoMapModule: SimpleIoMap
import ..CellModule: Cell

export InsertionToSyntaxLeaf, DocumentInsertionToSyntaxLeaf, DomainInsertionToSyntaxLeaf,
       JuliaInsertionToSyntaxLeaf, SqlInsertionToSyntaxLeaf, InsertionNothingToSyntaxLeaf,
       default_factory, default_completion, name_completion,
       julia_completion, julia_scaffold

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

"""
    name_completion(ins) -> (; state, hint, extension)

The default policy: name completion over the reflected candidates of the
insertion's own domain (`insertion_root(typeof(ins))`).
"""
function name_completion(ins)
    c = complete_insertion(insertion_root(typeof(ins)), something(ins.value, ""))
    (state = c.state,
     hint = c.state === :unambiguous ? c.continuation : "",
     extension = c.continuation)
end

# Source insertions (SQL) are committable when the buffer parses: green =
# complete source, red = not (yet) parseable; there is nothing to Tab-extend.
_parse_completion(parser) = ins -> begin
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
# The output is a SyntaxNode (label delimiters) wrapping one SyntaxLeaf (typed
# value + hint), so the `value{k}` char cursor maps through `children[1]`.

function map_reference_forward(::InsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        value{k} => begin
            inner = @reference ::SyntaxLeaf.value::TextString{k}::Position
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
    end
end

function map_reference_backward(::InsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::SyntaxNode.children[1].leaf_path... => @reference_case leaf_path begin
            ::SyntaxLeaf.value{k} => @reference ::DocumentInsertion.value::String{k}::Position
        end
    end
end

# ── Printer ──────────────────────────────────────────────────────────────────
#
# `prefix · value · ⟨continuation⟩ · suffix` — the value's colour and the
# continuation's content are computed cells over `ins.value`, so the
# commitability feedback updates per keystroke with no re-print.

function print_document(p::InsertionToSyntaxLeaf, recursion, ins, ctx)
    typed = TextString(Cell(() -> something(ins.value, "")),
                       Cell(p.value.font),
                       Cell(() -> _typed_color(p, p.completion(ins).state)),
                       Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    hint = TextString(Cell(() -> p.completion(ins).hint),
                      Cell(p.hint.font), Cell(p.hint.color),
                      Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    # The inner leaf's selection is the insertion's own (`value{k}` is the
    # leaf-local grammar too); the node routes it through `children[1]`.
    leaf = SyntaxLeaf(typed; close=hint, selection=getfield(ins, :selection))
    node_selection = Cell(() -> begin
        path = getfield(ins, :selection)[]
        path isa ConcreteReferencePath || return nothing
        path.head isa ProjectionReference && return path
        ConcreteReferencePath(FieldReference("children"),
            ConcreteReferencePath(ElementReference(1), path))
    end)
    SimpleIoMap(p, ins, SyntaxNode(SyntaxDocument[leaf];
        open=TextString(p.prefix, p.label),
        close=TextString(p.suffix, p.label),
        selection=node_selection))
end

# ── Value-edit helpers (mirror PrimitiveStringToSyntaxLeaf) ────────────────────

function _value_range(ins)
    sel = getfield(ins, :selection)[]
    sel = sel
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    (h isa FieldReference && h.name == "value") || return nothing
    t = sel.tail
    t isa ConcreteReferencePath || return nothing
    t.head isa RangeReference || return nothing
    t.head
end

_value_path(range::RangeReference) =
    ConcreteReferencePath(FieldReference("value"),
        ConcreteReferencePath(range, EmptyReferencePath()))

# ── Reader ───────────────────────────────────────────────────────────────────

function read_intent(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    # A caret in the rendered value span backward-maps to the value cursor; a
    # caret on the label/hint spans becomes an introduced caret on the whole
    # insertion; a raw input-vocabulary `value{k}` op passes through.
    mapped = map_reference_backward(p, iomap, op.path)
    mapped !== nothing && return ReplaceSelectionOperation(mapped)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference || return nothing
    h.name == "value" ? op : ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, path)))
end

# Own gestures, reified as a `get_projection_gesture_bindings` table fired through
# `read_projection_gesture` -- so the same set that fires is what `collect_gesture_bindings`
# shows. Value char-editing (insert / Backspace / Delete) mirrors PrimitiveString;
# Commit / Cancel are projection-specific (they call `p.commit` / abort to a
# `DocumentNothing`), which is why this stays a projection table rather than a
# document-level `@gestures`. Modifiers are matched loosely (`mods=nothing`) to
# preserve the old bare `@event_case` patterns exactly. Operations capture `p`/`ins`
# and return `nothing` to decline (no value cursor / commit refused).
function get_projection_gesture_bindings(p::InsertionToSyntaxLeaf, iomap)
    ins = iomap.input
    GestureBinding[
        GestureBinding(KeyDownPattern(:return, nothing, nothing),
            (doc, event) -> _insertion_commit(p, ins),
            (doc, sel) -> true, "Commit insertion", "insertion"),
        # Escape aborts to the domain's own placeholder (`nothing_document`, a
        # `@domain` trait) — `JsonInsertion` → `JsonNothing`, … — closing the
        # Insert ⇄ Escape loop within each domain.
        GestureBinding(KeyDownPattern(:escape, nothing, nothing),
            (doc, event) -> replace_document(EmptyReferencePath(),
                                             nothing_document(typeof(ins))()),
            (doc, sel) -> true, "Cancel insertion", "insertion"),
        # Tab accepts the completion: the full remainder when unambiguous, the
        # longest-common-prefix *partial* completion when ambiguous; declines
        # (keeps propagating) when there is nothing to extend.
        GestureBinding(KeyDownPattern(:tab, nothing, nothing),
            (doc, event) -> _insertion_tab(p, ins),
            (doc, sel) -> true, "Accept completion", "insertion"),
        GestureBinding(KeyDownPattern(:backspace, nothing, nothing),
            (doc, event) -> _insertion_delete(ins, :backspace),
            (doc, sel) -> true, "Delete backward", "insertion"),
        GestureBinding(KeyDownPattern(:delete, nothing, nothing),
            (doc, event) -> _insertion_delete(ins, :delete),
            (doc, sel) -> true, "Delete forward", "insertion"),
        GestureBinding(KeyPressPattern(nothing),
            (doc, event) -> _insertion_insert(ins, event.text),
            (doc, sel) -> true, "Insert character", "insertion"),
    ]
end

# Insert printable text at the value cursor; nothing without a value[range] cursor.
function _insertion_insert(ins, text)
    range = _value_range(ins)
    range === nothing ? nothing : ReplaceStringRangeOperation(_value_path(range), text)
end

# Commit the typed value through the projection's `commit` callback; nothing when
# the callback refuses (unknown/incomplete value).
function _insertion_commit(p::InsertionToSyntaxLeaf, ins)
    doc = p.commit(something(ins.value, ""))
    doc === nothing ? nothing : replace_document(EmptyReferencePath(), doc)
end

# Append the completion policy's Tab extension at the end of the buffer, caret
# after it; nothing without a value cursor or with nothing to extend.
function _insertion_tab(p::InsertionToSyntaxLeaf, ins)
    _value_range(ins) === nothing && return nothing
    extension = p.completion(ins).extension
    isempty(extension) && return nothing
    n = length(something(ins.value, ""))
    ReplaceStringRangeOperation(_value_path(RangeReference(n, n)), extension)
end

# Backspace/Delete range computation; nothing at the value boundary.
function _insertion_delete(ins, dir::Symbol)
    range = _value_range(ins)
    range === nothing && return nothing
    n = length(something(ins.value, ""))
    new_range = if range.start != range.stop
        range
    elseif dir === :backspace
        range.start > 0 ? RangeReference(range.start - 1, range.start) : nothing
    else  # :delete
        range.stop < n ? RangeReference(range.stop, range.stop + 1) : nothing
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
# No factory table: the candidates are `insertion_candidates(Document)` (every
# insertable concrete document type, computed by reflection and memoized on the
# world counter), the accepted names are derived from the type names
# (`"JsonString"` / `"json string"`), and construction goes through
# `make_insertion_document` dispatch. The historic short names (`"julia"`,
# `"json"`, …) live on as `insertion_aliases` emitted by each `@domain`.

# `TextText` is a plain visual document, not an `@domain` kit, so its historic
# `"text"` short name is a hand-written alias.
DomainModule.insertion_aliases(::Type{<:TextText}) = ["text"]

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

# ── Julia keyword scaffolds + completion ───────────────────────────────────────
#
# Keyword-introduced constructs (`function`, `if`, …) don't parse as complete source
# on their own — typing one and committing expands it into a **scaffold of holes**
# (nested `JuliaInsertion`s) with the first hole's char-cursor pre-selected. A
# partially-typed prefix of a keyword shows a pale-green completion continuation (see
# `julia_completion`), signalling it is committable as that keyword. Everything else
# commits by `juliaparse` (a complete sub-expression such as `n == 0`).

# Each scaffold pre-selects its first hole's own char cursor (`…value{0}`, the buffer
# offset 0), so it is ready to type into the moment the keyword commits.
const _JULIA_KEYWORD_SCAFFOLDS = Tuple{String,Function}[
    ("function", () -> (d = JuliaFunction(JuliaInsertion(), Any[JuliaInsertion()], JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, name.value{0})))),
    ("if", () -> (d = JuliaIf(JuliaInsertion(), JuliaBlock(Any[JuliaInsertion()]), JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, condition.value{0})))),
    ("while", () -> (d = JuliaWhile(JuliaInsertion(), JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, condition.value{0})))),
    ("for", () -> (d = JuliaFor(Any[JuliaForIterator(JuliaInsertion(), JuliaInsertion())], JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, iterators[1].variable.value{0})))),
    ("begin", () -> (d = JuliaBegin(JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, body.statements[1].value{0})))),
    ("return", () -> (d = JuliaReturn(JuliaInsertion());
        with_selection(d, @reference(d, value.value{0})))),
]

"""
    julia_scaffold(text) -> Document | nothing

The keyword scaffold for `text` when it exactly names a keyword-introduced construct
(cursor pre-placed on the first hole), else `nothing`.
"""
function julia_scaffold(text::AbstractString)
    s = strip(text)
    for (kw, make) in _JULIA_KEYWORD_SCAFFOLDS
        s == kw && return make()
    end
    nothing
end

"""
    julia_completion(text) -> String

The pale-green continuation for a partially-typed keyword (`"fun"` → `"ction"`), or
`""` when `text` is empty, already a full keyword, or matches no keyword prefix.
"""
function julia_completion(text::AbstractString)
    s = strip(text)
    isempty(s) && return ""
    for (kw, _) in _JULIA_KEYWORD_SCAFFOLDS
        (kw != s && startswith(kw, s)) && return kw[length(s)+1:end]
    end
    ""
end

# The keyword scaffolds double as insertion *candidates*: `julia function`
# committed from a DocumentInsertion (or `function` by name inside a Julia
# scope) builds the same scaffold-of-holes the keyword commit does.
@insertion JuliaFunction = julia_scaffold("function")
@insertion JuliaIf       = julia_scaffold("if")
@insertion JuliaWhile    = julia_scaffold("while")
@insertion JuliaFor      = julia_scaffold("for")
@insertion JuliaBegin    = julia_scaffold("begin")
@insertion JuliaReturn   = julia_scaffold("return")

# Commit a Julia hole: a keyword prefix expands to its scaffold; otherwise parse the
# buffer as complete source. Partial / invalid non-keyword source can't commit.
function _julia_commit(value::AbstractString)
    isempty(strip(value)) && return nothing
    scaffold = julia_scaffold(value)
    scaffold === nothing || return scaffold
    try
        juliaparse(value)
    catch
        nothing
    end
end

# Commit SQL source by parsing it; partial / invalid source can't commit.
function _sql_commit(value::AbstractString)
    isempty(strip(value)) && return nothing
    try
        sqlparse(value)
    catch
        nothing
    end
end

# ── Convenience constructors ───────────────────────────────────────────────────

"""
    DocumentInsertionToSyntaxLeaf()

The domain-independent insertion: `"Insert a new <name> here"`, committing via
`default_factory` (type a domain name + Enter).
"""
DocumentInsertionToSyntaxLeaf() =
    InsertionToSyntaxLeaf(default_factory; prefix = "Insert a new ", suffix = " here")

"""
    DomainInsertionToSyntaxLeaf(root; prefix = "insert a ", suffix = " here")

A domain-constrained insertion: the shared typed-name buffer completing over
`root`'s reflected candidates **prefix-free** (inside a `JsonInsertion`,
`string`/`String` names `JsonString`), committing the resolved type's
`make_insertion_document`. The default completion policy already scopes to
`insertion_root(typeof(ins))`, so the leaf only needs the matching commit.
"""
DomainInsertionToSyntaxLeaf(root::Type;
                            prefix::AbstractString = "insert a ",
                            suffix::AbstractString = " here") =
    InsertionToSyntaxLeaf(value -> begin
            T = resolve_insertion(root, value)
            T === nothing ? nothing : make_insertion_document(T)
        end; prefix, suffix)

"""
    SqlInsertionToSyntaxLeaf()

A SQL source insertion, committing `value` via `sqlparse`; the buffer is
green when it parses as a complete statement, red otherwise.
"""
SqlInsertionToSyntaxLeaf() =
    InsertionToSyntaxLeaf(_sql_commit; completion = _parse_completion(sqlparse))

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
struct InsertionNothingToSyntaxLeaf <: Projection
    style::StyleText
end

InsertionNothingToSyntaxLeaf() =
    InsertionNothingToSyntaxLeaf(StyleText(font_ubuntu_monospace_italic_20, color_solarized_gray))

print_document(p::InsertionNothingToSyntaxLeaf, recursion, doc, ctx) =
    SimpleIoMap(p, doc, SyntaxLeaf(TextString(_nothing_label(doc), p.style);
        selection=getfield(doc, :selection)))

# ── JuliaInsertion: gesture-driven structural hole ─────────────────────────────
#
# `JuliaInsertion` is a text-buffer hole whose editing, commit, and (step C)
# navigation are reified as document-level `@gestures JuliaInsertion` below — the
# way `@gestures PrimitiveString` reifies string char-editing. `JuliaInsertionToSyntaxLeaf`
# is therefore a **printer-only** leaf (mirroring `PrimitiveStringToSyntaxLeaf`): it
# renders the buffer plus a pale-green completion continuation, maps the `value{k}`
# char cursor, and carries **no key-capturing reader**, so raw input falls through the
# generic `read_gesture` fallback to the gesture table — the single source of truth.

"""
    JuliaInsertionToSyntaxLeaf()

A Julia source-insertion hole. Renders the typed buffer plus a pale-green keyword
completion continuation; all editing/commit is `@gestures JuliaInsertion`.
"""
struct JuliaInsertionToSyntaxLeaf <: Projection
    value::StyleText
    completion::StyleText
end

JuliaInsertionToSyntaxLeaf() = JuliaInsertionToSyntaxLeaf(
    StyleText(font_ubuntu_monospace_regular_20, color_default),
    StyleText(font_ubuntu_monospace_regular_20, color_completion_hint))

# `value{k}` char-cursor ↔ the rendered `SyntaxLeaf`'s value span (identity offset).
function map_reference_forward(::JuliaInsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        value{k} => @reference ::SyntaxLeaf.value::TextString{k}
    end
end

function map_reference_backward(::JuliaInsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference ::JuliaInsertion.value::String{k}::Position
    end
end

# Julia commitability: green when the buffer is a keyword (prefix) or parses as
# complete source, red when it can commit neither way, neutral when empty.
function _julia_state(value::AbstractString)
    isempty(strip(value)) && return :empty
    julia_scaffold(value) === nothing || return :unambiguous
    isempty(julia_completion(value)) || return :unambiguous
    parsed = try juliaparse(value); true catch; false end
    parsed ? :unambiguous : :invalid
end

_julia_typed_color(p::JuliaInsertionToSyntaxLeaf, value::AbstractString) = begin
    state = _julia_state(value)
    state === :invalid ? color_solarized_red :
    state === :empty   ? p.value.color      : color_solarized_green
end

function print_document(p::JuliaInsertionToSyntaxLeaf, recursion, ins::JuliaInsertion, ctx)
    typed = TextString(Cell(() -> something(ins.value, "")),
                       Cell(p.value.font),
                       Cell(() -> _julia_typed_color(p, something(ins.value, ""))),
                       Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    SimpleIoMap(p, ins, SyntaxLeaf(typed;
        close=TextString(() -> julia_completion(something(ins.value, "")), p.completion),
        selection=getfield(ins, :selection)))
end

# Only the structural selection mapping lives here; raw key input has no method and
# falls through to the generic `read_gesture` fallback → `@gestures JuliaInsertion`.
function read_intent(p::JuliaInsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference || return nothing
    h.name == "value" ? op : ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, path)))
end

# Commit the buffer via `_julia_commit` (keyword scaffold or `juliaparse`); the
# rerooted `∅` targets this hole, so a nested hole is replaced in place and the
# cursor lands on the committed value's own selection (a scaffold's first hole).
_julia_ins_commit(ins) =
    (doc = _julia_commit(something(ins.value, ""));
     doc === nothing ? nothing : replace_document(EmptyReferencePath(), doc))

# The Tab navigation predicate + in-hole cursor: land on the next `JuliaInsertion`,
# cursor at its buffer offset 0 so it is ready to type.
_is_julia_hole(node) = node isa JuliaInsertion
const _JULIA_HOLE_CURSOR = @reference ::JuliaInsertion.value::String{0}::Position

# Tab: commit the buffer and jump to the next hole.
#  - empty buffer            → just advance (skip the untouched hole).
#  - keyword prefix          → expand to its scaffold; the scaffold already pre-selects
#                              its own first hole, so do NOT advance past it.
#  - complete parseable expr → commit, then advance to the next hole (the mid
#                              ReplaceSelectionOperation leaves the cursor on the
#                              just-committed node, which `SelectNextInsertion` steps past).
#  - otherwise (unparseable) → decline (stay in the buffer, keep typing).
function _julia_ins_tab(ins)
    value = something(ins.value, "")
    isempty(strip(value)) &&
        return SelectNextInsertionOperation(_is_julia_hole, _JULIA_HOLE_CURSOR)
    scaffold = julia_scaffold(value)
    scaffold === nothing || return replace_document(EmptyReferencePath(), scaffold)
    parsed = try juliaparse(value) catch; nothing end
    parsed === nothing && return nothing
    commit = replace_document(EmptyReferencePath(), parsed)
    CompoundOperation(Any[commit.operations...,
                          SelectNextInsertionOperation(_is_julia_hole, _JULIA_HOLE_CURSOR)])
end

# All `JuliaInsertion` editing, reified. Char insert / Backspace / Delete reuse the
# shared `_insertion_*` helpers (they decline with `nothing` off a `value[range]`
# cursor, so the gesture keeps propagating); Enter commits in place; Tab commits and
# jumps to the next hole.
@gestures JuliaInsertion begin
    KeyPress(_, t)       => "Insert character"  => _insertion_insert(doc, t)
    KeyDown(:backspace;) => "Delete backward"   => _insertion_delete(doc, :backspace)
    KeyDown(:delete;)    => "Delete forward"    => _insertion_delete(doc, :delete)
    KeyDown(:return;)    => "Commit hole"       => _julia_ins_commit(doc)
    KeyDown(:tab;)       => "Commit + next hole" => _julia_ins_tab(doc)
end

end # module
