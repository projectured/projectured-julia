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
import ..OperationModule: ReplaceDocumentOperation, ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference,
                          EmptyReferencePath, ProjectionReference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..KeyboardModule: KeyDown, KeyPress
import ..EventCaseModule: var"@event_case"
import ..FontModule: font_ubuntu_monospace_regular_24, StyleFont
import ..ColorModule: color_solarized_gray, color_default, StyleColor
import ..IoMapModule: SimpleIoMap
import ..ReactiveModule: Cell

export InsertionToSyntaxLeaf, DocumentInsertionToSyntaxLeaf, JuliaInsertionToSyntaxLeaf,
       default_factory, default_completion

# ── Projection ────────────────────────────────────────────────────────────────

struct InsertionToSyntaxLeaf <: Projection
    prefix::String
    suffix::String
    commit::Any            # (value::String) -> Union{Document,Nothing}
    font::StyleFont
    label_color::StyleColor
    value_color::StyleColor
end

InsertionToSyntaxLeaf(commit; prefix::AbstractString = "", suffix::AbstractString = "",
                      font = font_ubuntu_monospace_regular_24,
                      label_color = color_solarized_gray,
                      value_color = color_default) =
    InsertionToSyntaxLeaf(String(prefix), String(suffix), commit, font, label_color, value_color)

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
        TextString(p.prefix, p.font, p.label_color),
        TextString(p.suffix, p.font, p.label_color),
        TextString(() -> something(ins.value, ""), p.font, p.value_color),
        getfield(ins, :selection)))
end

# ── Value-edit helpers (mirror PrimitiveStringToSyntaxLeaf) ────────────────────

function _value_range(ins)
    sel = getfield(ins, :selection)[]
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
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference || return nothing
    h.name == "value" ? op : ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, path)))
end

function projection_read(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, evt::KeyPress)
    evt.modifiers.ctrl && return nothing
    ins = iomap.input
    range = _value_range(ins)
    range === nothing && return nothing
    StringReplaceRangeOperation(_value_path(range), evt.text)
end

function projection_read(p::InsertionToSyntaxLeaf, iomap::SimpleIoMap, evt::KeyDown)
    ins = iomap.input
    action = @event_case evt begin
        KeyDown(:return) => :commit
        KeyDown(:escape) => :abort
    end
    if action === :commit
        doc = p.commit(something(ins.value, ""))
        doc === nothing && return nothing
        return ReplaceDocumentOperation(EmptyReferencePath(), doc)
    elseif action === :abort
        return ReplaceDocumentOperation(EmptyReferencePath(), DocumentNothing())
    end
    range = _value_range(ins)
    range === nothing && return nothing
    text = something(ins.value, "")
    n = length(text)
    new_range = @event_case evt begin
        KeyDown(:backspace) => begin
            if range.start != range.stop
                range
            elseif range.start > 0
                RangeReference(range.start - 1, range.start)
            else
                return nothing
            end
        end
        KeyDown(:delete) => begin
            if range.start != range.stop
                range
            elseif range.stop < n
                RangeReference(range.stop, range.stop + 1)
            else
                return nothing
            end
        end
    end
    new_range === nothing && return nothing
    StringReplaceRangeOperation(_value_path(new_range), "")
end

projection_read(::InsertionToSyntaxLeaf, ::SimpleIoMap, evt) = nothing

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
