"""
    DocumentInsertionToSyntaxModule

The insert-by-typing mechanism, ported from the Common Lisp ProjecturEd
`document-to-syntax.lisp`.

`InsertionToSyntaxLeaf(commit; prefix, suffix)` projects any document with an
editable `value::String` (e.g. `DocumentInsertion`, `JuliaInsertion`) to a
`SyntaxLeaf` rendered as `prefix · value · suffix`. The reader edits `value`
character-by-character and, on **Enter**, calls `commit(value)`:

- `DocumentInsertion` uses `default_factory` — typing a domain name
  (`julia`, `json`, `xml`, `text`) + Enter commits to that domain's document /
  insertion.
- `JuliaInsertion` commits Julia source via `juliaparse` → a `JuliaDocument`.

So the chain is *domain-independent insertion → domain-specific insertion →
enter the domain's source*, exactly as in the Lisp editor. Commit emits a
`ReplaceDocumentOperation` rooted at the insertion (enclosing projections reroot
it); **Escape** aborts to `DocumentNothing`.

Not yet ported: the live completion hint + green/red commitability colouring
(`default_completion` computes the suffix; wiring it into the rendered leaf is a
follow-up).
"""
module DocumentInsertionToSyntaxModule

import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..DocumentApiModule: Document, with_selection
import ..DocumentCoreModule: DocumentInsertion, DocumentNothing
import ..JuliaModule: JuliaInsertion, JuliaDocument,
                      JuliaFunction, JuliaIf, JuliaWhile, JuliaFor, JuliaForIterator,
                      JuliaBegin, JuliaReturn, JuliaBlock
import ..JsonModule: JsonInsertion
import ..XmlModule: XmlInsertion
import ..SqlDocumentModule: SqlInsertion
import ..TextModule: TextText, TextString
import ..JuliaParserModule: juliaparse
import ..SqlParserModule: sqlparse
import ..SyntaxModule: SyntaxLeaf
import ..OperationModule: replace_document, ReplaceSelectionOperation,
                          SelectNextInsertionOperation, CompoundOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference,
                          EmptyReferencePath, ProjectionReference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..GestureBindingModule: GestureBinding, KeyDownPattern, KeyPressPattern,
                              projection_gestures, read_projection_gesture, var"@gestures"
import ..FontModule: font_ubuntu_monospace_regular_20, StyleFont
import ..ColorModule: color_solarized_gray, color_solarized_green, color_default, StyleColor
import ..StyleTextModule: StyleText
import ..IoMapModule: SimpleIoMap
import ..ReactiveModule: Cell

export InsertionToSyntaxLeaf, DocumentInsertionToSyntaxLeaf, JuliaInsertionToSyntaxLeaf,
       SqlInsertionToSyntaxLeaf, default_factory, default_completion,
       julia_completion, julia_scaffold

# ── Projection ────────────────────────────────────────────────────────────────

struct InsertionToSyntaxLeaf <: Projection
    prefix::String
    suffix::String
    commit::Any            # (value::String) -> Union{Document,Nothing}
    # The label (prefix/suffix) and the editable value share a font but are
    # coloured distinctly, so each is its own StyleText.
    label::StyleText
    value::StyleText
end

InsertionToSyntaxLeaf(commit; prefix::AbstractString = "", suffix::AbstractString = "",
                      label = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray),
                      value = StyleText(font_ubuntu_monospace_regular_20, color_default)) =
    InsertionToSyntaxLeaf(String(prefix), String(suffix), commit, label, value)

# ── Selection mapping (value{k} identity, mirrors PrimitiveStringToSyntaxLeaf) ─

function map_reference_forward(::InsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        value{k} => @reference ::SyntaxLeaf.value::TextString{k}
    end
end

function map_reference_backward(::InsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference value{k}
    end
end

# ── Printer ──────────────────────────────────────────────────────────────────

function projection_print(p::InsertionToSyntaxLeaf, recursion, ins, ctx)
    SimpleIoMap(p, ins, SyntaxLeaf(
        TextString(() -> something(ins.value, ""), p.value);
        open=TextString(p.prefix, p.label),
        close=TextString(p.suffix, p.label),
        selection=getfield(ins, :selection)))
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

function projection_read(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path = path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference || return nothing
    h.name == "value" ? op : ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, path)))
end

# Own gestures, reified as a `projection_gestures` table fired through
# `read_projection_gesture` -- so the same set that fires is what `collect_gestures`
# shows. Value char-editing (insert / Backspace / Delete) mirrors PrimitiveString;
# Commit / Cancel are projection-specific (they call `p.commit` / abort to a
# `DocumentNothing`), which is why this stays a projection table rather than a
# document-level `@gestures`. Modifiers are matched loosely (`mods=nothing`) to
# preserve the old bare `@event_case` patterns exactly. Operations capture `p`/`ins`
# and return `nothing` to decline (no value cursor / commit refused).
function projection_gestures(p::InsertionToSyntaxLeaf, iomap)
    ins = iomap.input
    GestureBinding[
        GestureBinding(KeyDownPattern(:return, nothing, nothing),
            (doc, event) -> _insertion_commit(p, ins),
            (doc, sel) -> true, "Commit insertion", "insertion"),
        GestureBinding(KeyDownPattern(:escape, nothing, nothing),
            (doc, event) -> replace_document(EmptyReferencePath(), DocumentNothing()),
            (doc, sel) -> true, "Cancel insertion", "insertion"),
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
    range === nothing ? nothing : StringReplaceRangeOperation(_value_path(range), text)
end

# Commit the typed value through the projection's `commit` callback; nothing when
# the callback refuses (unknown/incomplete value).
function _insertion_commit(p::InsertionToSyntaxLeaf, ins)
    doc = p.commit(something(ins.value, ""))
    doc === nothing ? nothing : replace_document(EmptyReferencePath(), doc)
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
    new_range === nothing ? nothing : StringReplaceRangeOperation(_value_path(new_range), "")
end

projection_read(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, event) =
    read_projection_gesture(p, iomap, event)

# ── Factory: name → domain document / insertion ───────────────────────────────

const _FACTORY = Tuple{String,Function}[
    ("julia", () -> JuliaInsertion("")),
    ("json",  () -> JsonInsertion()),
    ("xml",   () -> XmlInsertion()),
    ("sql",   () -> SqlInsertion("")),
    ("text",  () -> TextText()),
]

"""
    default_factory(name) -> Document | nothing

Map a typed domain name to a fresh domain document / insertion, or `nothing`
when `name` doesn't (yet) name a committable type.
"""
function default_factory(name::AbstractString)
    key = lowercase(strip(name))
    for (k, make) in _FACTORY
        k == key && return make()
    end
    nothing
end

"""
    default_completion(name) -> String

The completion suffix for a partially-typed name (e.g. `"jso"` → `"n"`), or `""`.
"""
function default_completion(name::AbstractString)
    key = lowercase(strip(name))
    isempty(key) && return ""
    for (k, _) in _FACTORY
        (k != key && startswith(k, key)) && return k[length(key)+1:end]
    end
    ""
end

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
    ("function", () -> with_selection(
        JuliaFunction(JuliaInsertion(), Any[JuliaInsertion()], JuliaBlock(Any[JuliaInsertion()])),
        @reference name.value{0})),
    ("if", () -> with_selection(
        JuliaIf(JuliaInsertion(), JuliaBlock(Any[JuliaInsertion()]), JuliaBlock(Any[JuliaInsertion()])),
        @reference condition.value{0})),
    ("while", () -> with_selection(
        JuliaWhile(JuliaInsertion(), JuliaBlock(Any[JuliaInsertion()])),
        @reference condition.value{0})),
    ("for", () -> with_selection(
        JuliaFor(Any[JuliaForIterator(JuliaInsertion(), JuliaInsertion())], JuliaBlock(Any[JuliaInsertion()])),
        @reference iterators[1].variable.value{0})),
    ("begin", () -> with_selection(
        JuliaBegin(JuliaBlock(Any[JuliaInsertion()])),
        @reference body.statements[1].value{0})),
    ("return", () -> with_selection(
        JuliaReturn(JuliaInsertion()),
        @reference value.value{0})),
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
    SqlInsertionToSyntaxLeaf()

A SQL source insertion, committing `value` via `sqlparse`.
"""
SqlInsertionToSyntaxLeaf() = InsertionToSyntaxLeaf(_sql_commit)

# ── JuliaInsertion: gesture-driven structural hole ─────────────────────────────
#
# `JuliaInsertion` is a text-buffer hole whose editing, commit, and (step C)
# navigation are reified as document-level `@gestures JuliaInsertion` below — the
# way `@gestures PrimitiveString` reifies string char-editing. `JuliaInsertionToSyntaxLeaf`
# is therefore a **printer-only** leaf (mirroring `PrimitiveStringToSyntaxLeaf`): it
# renders the buffer plus a pale-green completion continuation, maps the `value{k}`
# char cursor, and carries **no key-capturing reader**, so raw input falls through the
# generic `document_read` fallback to the gesture table — the single source of truth.

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
    StyleText(font_ubuntu_monospace_regular_20, color_solarized_green))

# `value{k}` char-cursor ↔ the rendered `SyntaxLeaf`'s value span (identity offset).
function map_reference_forward(::JuliaInsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        value{k} => @reference ::SyntaxLeaf.value::TextString{k}
    end
end

function map_reference_backward(::JuliaInsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference value{k}
    end
end

function projection_print(p::JuliaInsertionToSyntaxLeaf, recursion, ins::JuliaInsertion, ctx)
    SimpleIoMap(p, ins, SyntaxLeaf(
        TextString(() -> something(ins.value, ""), p.value);
        close=TextString(() -> julia_completion(something(ins.value, "")), p.completion),
        selection=getfield(ins, :selection)))
end

# Only the structural selection mapping lives here; raw key input has no method and
# falls through to the generic `document_read` fallback → `@gestures JuliaInsertion`.
function projection_read(p::JuliaInsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
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
const _JULIA_HOLE_CURSOR = @reference value{0}

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
