"""
    JsonModule

The JSON document domain.

The domain includes:
- **Primitive types**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`
- **Compound types**: `JsonArray`, `JsonObject`, `JsonObjectEntry`
- **Utility types**: `JsonInsertion` for cursor positioning
"""
module JsonModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document, @forward_vector, @forward_map
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ReferencePath, ConcreteReferencePath, PositionReference, RangeReference, FieldReference, EmptyReferencePath, evaluate_reference, Position
import ..ProjectionReferenceModule: ProjectionReference
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..OperationModule: replace_document, insert_elements, ReplaceSelectionOperation
import ..SelectionApiModule: with_selection
import ..KeyboardModule: KeyPress, KeyDown
import ..GestureBindingModule: var"@gestures"
import ..DomainSupportModule: var"@domain", make_insertion_document
export JsonDocument, entries

# The domain kit: `JsonDocument` (abstract root), `JsonNothing` (empty
# placeholder, Insert turns it into the insertion), `JsonInsertion` (typed-name
# buffer completing over the JSON candidates), the Insert gesture and the
# insertion traits — all generated from the domain name.
@domain Json

# ── Primitives ───────────────────────────────────────────────────────────

"""
The JSON `null` literal.
"""
@document struct JsonNull <: JsonDocument
    selection::Reference = nothing
end

"""
A JSON boolean literal (`true` or `false`).
"""
@document struct JsonBool <: JsonDocument
    value::Bool
    selection::Reference = nothing
end

"""
A JSON number literal. `value` may be `nothing` while its text has been fully deleted.
"""
@document struct JsonNumber <: JsonDocument
    value::Union{Real, Nothing}
    selection::Reference = nothing
end

"""
A JSON string literal.
"""
@document struct JsonString <: JsonDocument
    value::String
    selection::Reference = nothing
end

# ── Compounds ────────────────────────────────────────────────────────────

"""
A JSON array `[…]`. `collapsed` hides its elements behind a marker in the projection.
"""
@document struct JsonArray <: JsonDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

@forward_vector JsonArray elements

"""
One `"key": value` member of a JSON object.
"""
@document struct JsonObjectEntry <: JsonDocument
    key::String
    value::Document
    collapsed::Bool = false
    selection::Reference = nothing
end    

"""
A JSON object `{…}` — an ordered sequence of `JsonObjectEntry` members.
`collapsed` hides them in the projection.
"""
@document struct JsonObject <: JsonDocument
    entries::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end    

@forward_map JsonObject entries key value JsonObjectEntry

# build an object from `key => value` pairs
function JsonObject(pairs::Pair{<:AbstractString}...)
    cv = CellVector()
    for (k, v) in pairs
        push!(cv, Cell(JsonObjectEntry(String(k), v)))
    end    
    JsonObject(cv, Cell(false), Cell(nothing))
end    

# Text/number replace edits need no per-type method: `JsonString.value` and
# `JsonObjectEntry.key` are plain strings, and `JsonNumber.value` is a number
# reparsed from its text representation.

# ── Authoring gestures ──────────────────────────────────────────────────────
#
# The JSON authoring command set: type a printable key on a whole JSON value to
# replace it, `,` to insert an element/entry, Tab to move from a key to its value.
# Gestures are root-relative: each reads `doc`'s own selection and emits a
# `doc`-relative operation that resolves to the actual (possibly nested) target.

# A projection-introduced caret: the cursor sits on a part the projection added
# (a delimiter, separator, or the `JsonInsertion` placeholder), so its head is a
# `ProjectionReference` with no document pre-image (`evaluate_reference` throws).
# Structural gestures treat such a caret as naming the whole focused node.
_is_introduced(sel) = sel isa ConcreteReferencePath && sel.head isa ProjectionReference

# Replace the currently-selected value with `newdoc` (whose cursor is pre-placed
# via `with_selection`). An introduced caret targets the whole focused node, so
# normalize it to `∅` (the proj-wrapped ref does not resolve for replacement).
_replace(doc, newdoc) =
    replace_document(_is_introduced(getfield(doc, :selection)[]) ?
                     EmptyReferencePath() : getfield(doc, :selection)[], newdoc)

# A character cursor: a path ending in value{k} or key{k} (a RangeReference after a
# value/key field). A whole-element selection ends in ∅.
function _is_char_cursor(sel)
    prev = nothing
    cur = sel
    while cur isa ConcreteReferencePath
        if cur.tail isa EmptyReferencePath
            return cur.head isa RangeReference && prev isa FieldReference &&
                   (prev.name == "value" || prev.name == "key")
        end
        prev = cur.head
        cur = cur.tail
    end
    return false
end

# The node whose `.value` / `.key` a char cursor edits, as `(owner_ref, field)`
# (the path with the trailing `<field>{k}` stripped), or `nothing` when `sel` is
# not a char cursor. Used to tell a string-text caret from a number caret.
function _char_cursor_owner(sel)
    steps = Any[]
    cur = sel
    while cur isa ConcreteReferencePath
        if cur.tail isa EmptyReferencePath && cur.head isa RangeReference
            isempty(steps) && return nothing
            field = steps[end]
            (field isa FieldReference && (field.name == "value" || field.name == "key")) || return nothing
            owner = EmptyReferencePath()
            for i in (length(steps) - 1):-1:1
                owner = ConcreteReferencePath(steps[i], owner)
            end
            return (owner, field.name)
        end
        push!(steps, cur.head)
        cur = cur.tail
    end
    return nothing
end

# True when the caret is editing *string* text: an object key (keys are strings),
# or a `value{k}` cursor whose owning node is a `JsonString`. A `value{k}` cursor
# in a `JsonNumber` is not a string context. Keeps `,` a literal comma while
# typing inside a string/key (everywhere else `,` is a structural insert).
function _in_string_context(doc, sel)
    oc = _char_cursor_owner(sel)
    oc === nothing && return false
    owner_ref, field = oc
    field == "key" && return true
    target = try evaluate_reference(doc, owner_ref) catch; nothing end
    return target isa JsonString
end

# Block precondition for the type-to-replace set: a whole JSON value (not a
# character cursor) whose target exists and is replaceable (values / array
# elements / root — not a key/value entry wrapper). An introduced caret names the
# whole focused node, so it is replaceable too.
function _json_replaceable(doc, sel)
    sel === nothing && return false
    _is_char_cursor(sel) && return false
    # An introduced caret (on a delimiter / placeholder) names the focused node.
    # Enable type-to-replace there for a `JsonInsertion` placeholder or a container
    # (you are on its bracket / brace), but not on a concrete scalar's own quotes /
    # keyword — a whole-element selection is the way to retype an existing value.
    if _is_introduced(sel)
        return doc isa JsonInsertion || doc isa JsonArray || doc isa JsonObject
    end
    target = try evaluate_reference(doc, sel) catch; nothing end
    target === nothing && return false
    target isa JsonObjectEntry && return false
    return true
end

# A digit builds a fresh number, unless a whole number is already selected (that
# edit belongs to the typein path, which appends digits to the existing value).
function _replace_number(doc, c)
    target = try evaluate_reference(doc, getfield(doc, :selection)[]) catch; nothing end
    target isa JsonNumber && return nothing
    _replace(doc, with_selection(JsonNumber(parse(Int, string(c))), @reference ::JsonNumber.value::Int{1}::Position))
end

# Append a JsonInsertion and select it whole, ready to type-to-replace. Declines
# (`,` stays a literal comma) while the caret is editing string text, so a comma
# can be typed into a string element / key; structural everywhere else.
function _array_insert(doc::JsonArray)
    _in_string_context(doc, getfield(doc, :selection)[]) && return nothing
    n = length(doc.elements)
    insert_elements(@reference(::JsonArray.elements::CellVector), n, Any[JsonInsertion()],
                    @reference ::JsonArray.elements::CellVector[n + 1]::JsonInsertion)
end

# Append an empty entry and select its key for typing. Declines in a string
# context (see `_array_insert`).
function _object_insert(doc::JsonObject)
    _in_string_context(doc, getfield(doc, :selection)[]) && return nothing
    n = length(doc.entries)
    insert_elements(@reference(::JsonObject.entries::CellVector), n,
                    Any[JsonObjectEntry("", JsonInsertion())],
                    @reference ::JsonObject.entries::CellVector[n + 1]::JsonObjectEntry.key::String{0}::Position)
end

# Tab moves the cursor from an entry's key to its value, selected whole.
function _object_tab(doc::JsonObject)
    sel = getfield(doc, :selection)[]
    sel === nothing && return nothing
    @reference_case sel begin
        ::JsonObject.entries{s:e}.rest... => begin
            i = s + 1
            @reference_case rest begin
                ::JsonObjectEntry.key.inner... => ReplaceSelectionOperation(@reference ::JsonObject.entries::CellVector[i]::JsonObjectEntry.value::Document)
            end
        end
    end
end

# ── Insertion factories ─────────────────────────────────────────────────────
#
# One construction per committable JSON value, with its cursor pre-placed —
# shared by the char type-to-replace gestures below and by the typed-name
# commit of a `JsonInsertion` / `DocumentInsertion` (the completion machinery
# resolves a name to the type, `make_insertion_document` builds the value).
# `JsonNull` needs no method: the zero-arg fallback already covers it.
# Each factory builds the document, then selects into it with the two-arg
# `@reference(doc, path)` form — the document fills the node types, so the
# selection is fully typed by construction with no hand-spelled `::T`.
make_insertion_document(::Type{<:JsonBool}) =
    with_selection(JsonBool(false), EmptyReferencePath(JsonBool))
# An empty number's value is `nothing`, which has no text position — so it is
# selected *whole* (like `JsonBool`), not with a caret into nothing. An empty
# string, by contrast, is `""` and does have position 0.
make_insertion_document(::Type{<:JsonNumber}) =
    with_selection(JsonNumber(nothing), EmptyReferencePath(JsonNumber))
make_insertion_document(::Type{<:JsonString}) =
    let d = JsonString(""); with_selection(d, @reference(d, value{0})) end
make_insertion_document(::Type{<:JsonArray}) =
    let d = JsonArray([JsonInsertion()]); with_selection(d, @reference(d, elements[1])) end
make_insertion_document(::Type{<:JsonObjectEntry}) =
    let d = JsonObjectEntry("", JsonInsertion()); with_selection(d, @reference(d, key{0})) end
make_insertion_document(::Type{<:JsonObject}) =
    let d = JsonObject([JsonObjectEntry("", JsonInsertion())]); with_selection(d, @reference(d, entries[1].key{0})) end

@gestures JsonDocument begin
    when(_json_replaceable(doc, sel))
    KeyPress('n') => "Replace with null"   => _replace(doc, with_selection(JsonNull(), EmptyReferencePath()))
    KeyPress('f') => "Replace with false"  => _replace(doc, make_insertion_document(JsonBool))
    KeyPress('t') => "Replace with true"   => _replace(doc, with_selection(JsonBool(true), EmptyReferencePath()))
    KeyPress('"') => "Replace with a string" => _replace(doc, make_insertion_document(JsonString))
    KeyPress('[') => "Replace with an array" => _replace(doc, make_insertion_document(JsonArray))
    KeyPress(':') => "Replace with an object entry" => _replace(doc, make_insertion_document(JsonObjectEntry))
    KeyPress('{') => "Replace with an object" => _replace(doc, make_insertion_document(JsonObject))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" => _replace_number(doc, c)
end

@gestures JsonArray begin
    KeyPress(',') => "Insert a new element" => _array_insert(doc)
end

@gestures JsonObject begin
    KeyPress(',') => "Insert a new entry" => _object_insert(doc)
    KeyDown(:tab) => "Move from key to value" => _object_tab(doc)
end

end # module
