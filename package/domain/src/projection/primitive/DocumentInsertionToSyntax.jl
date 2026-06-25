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
import ..DocumentApiModule: Document
import ..DocumentCoreModule: DocumentInsertion, DocumentNothing
import ..JuliaModule: JuliaInsertion, JuliaDocument
import ..JsonModule: JsonInsertion
import ..XmlModule: XmlInsertion
import ..TextModule: TextText, TextString
import ..JuliaParserModule: juliaparse
import ..SyntaxModule: SyntaxLeaf
import ..OperationModule: replace_document, ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference,
                          EmptyReferencePath, ProjectionReference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..GestureBindingModule: GestureBinding, KeyDownPattern, KeyPressPattern,
                              projection_gestures, read_projection_gesture
import ..FontModule: font_ubuntu_monospace_regular_24, StyleFont
import ..ColorModule: color_solarized_gray, color_default, StyleColor
import ..StyleTextModule: StyleText
import ..IoMapModule: SimpleIoMap
import ..ReactiveModule: Cell

export InsertionToSyntaxLeaf, DocumentInsertionToSyntaxLeaf, JuliaInsertionToSyntaxLeaf,
       default_factory, default_completion

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
                      label = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray),
                      value = StyleText(font_ubuntu_monospace_regular_24, color_default)) =
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

# Commit Julia source by parsing it; partial / invalid source can't commit.
function _julia_commit(value::AbstractString)
    isempty(strip(value)) && return nothing
    try
        juliaparse(value)
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
    JuliaInsertionToSyntaxLeaf()

A Julia source insertion, committing `value` via `juliaparse`.
"""
JuliaInsertionToSyntaxLeaf() = InsertionToSyntaxLeaf(_julia_commit)

end # module
