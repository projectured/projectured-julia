"""
    YamlModule

The YAML document domain. YAML is a JSON superset; the value model mirrors it —
scalars, block/flow sequences, ordered mappings.
"""
module YamlModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document, @forward_vector, @forward_map
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ReferencePath, ConcreteReferencePath, PositionReference, RangeReference, FieldReference, EmptyReferencePath, evaluate_reference
import ..ProjectionReferenceModule: ProjectionReference
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..OperationModule: replace_document, insert_elements, ReplaceSelectionOperation
import ..ReferenceApiModule: with_selection
import ..KeyboardModule: KeyPress, KeyDown
import ..GestureBindingModule: var"@gestures"
import ..DomainSupportModule: var"@domain", make_insertion_document
export YamlDocument

# The domain kit: `YamlDocument` (abstract root), `YamlNothing` (empty
# placeholder, Insert turns it into the insertion), `YamlInsertion` (typed-name
# buffer completing over the YAML candidates), the Insert gesture and the
# insertion traits — all generated from the domain name.
@domain Yaml

# ── Scalars ──────────────────────────────────────────────────────────────

"""
The YAML `null` literal (also written `~`).
"""
@document struct YamlNull <: YamlDocument
    selection::Reference = nothing
end

"""
A YAML boolean literal (`true` or `false`).
"""
@document struct YamlBool <: YamlDocument
    value::Bool
    selection::Reference = nothing
end

"""
A YAML number literal. `value` may be `nothing` while its text has been fully deleted.
"""
@document struct YamlNumber <: YamlDocument
    value::Union{Real, Nothing}
    selection::Reference = nothing
end

"""
A YAML string scalar (plain, single-, or double-quoted — the quoting style is a
projection concern, not part of the value).
"""
@document struct YamlString <: YamlDocument
    value::String
    selection::Reference = nothing
end

# ── Compounds ────────────────────────────────────────────────────────────

"""
A YAML sequence (a `- item` block list or `[…]` flow list). `collapsed` hides its
elements behind a marker in the projection.
"""
@document struct YamlSequence <: YamlDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

@forward_vector YamlSequence elements

"""
One `key: value` member of a YAML mapping.
"""
@document struct YamlMappingEntry <: YamlDocument
    key::String
    value::Document
    collapsed::Bool = false
    selection::Reference = nothing
end

"""
A YAML mapping (a `key: value` block or `{…}` flow map) — an ordered sequence of
`YamlMappingEntry` members. `collapsed` hides them in the projection.
"""
@document struct YamlMapping <: YamlDocument
    entries::CellVector = CellVector()
    collapsed::Bool = false
    selection::Reference = nothing
end

@forward_map YamlMapping entries key value YamlMappingEntry

# build a mapping from `key => value` pairs
function YamlMapping(pairs::Pair{<:AbstractString}...)
    cv = CellVector()
    for (k, v) in pairs
        push!(cv, Cell(YamlMappingEntry(String(k), v)))
    end
    YamlMapping(cv, Cell(false), Cell(nothing))
end

# Text/number replace edits need no per-type method: `YamlString.value` and
# `YamlMappingEntry.key` are plain strings, and `YamlNumber.value` is a number
# reparsed from its text representation.

# ── Authoring gestures ──────────────────────────────────────────────────────
#
# The YAML authoring command set mirrors JSON's (YAML is a JSON superset): type a
# printable key on a whole YAML value to replace it, `,` to insert an element/entry,
# Tab to move from a key to its value. Gestures are root-relative: each reads
# `doc`'s own selection and emits a `doc`-relative operation that resolves to the
# actual (possibly nested) target.

# A projection-introduced caret: the cursor sits on a part the projection added
# (a delimiter, separator, or the `YamlInsertion` placeholder), so its head is a
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

# True when the caret is editing *string* text: a mapping key (keys are strings),
# or a `value{k}` cursor whose owning node is a `YamlString`. A `value{k}` cursor
# in a `YamlNumber` is not a string context. Keeps `,` a literal comma while
# typing inside a string/key (everywhere else `,` is a structural insert).
function _in_string_context(doc, sel)
    oc = _char_cursor_owner(sel)
    oc === nothing && return false
    owner_ref, field = oc
    field == "key" && return true
    target = try evaluate_reference(doc, owner_ref) catch; nothing end
    return target isa YamlString
end

# Block precondition for the type-to-replace set: a whole YAML value (not a
# character cursor) whose target exists and is replaceable (values / sequence
# elements / root — not a mapping entry wrapper). An introduced caret names the
# whole focused node, so it is replaceable too.
function _yaml_replaceable(doc, sel)
    sel === nothing && return false
    _is_char_cursor(sel) && return false
    # An introduced caret (on a delimiter / placeholder) names the focused node.
    # Enable type-to-replace there for a `YamlInsertion` placeholder or a container
    # (you are on its marker / brace), but not on a concrete scalar's own quotes /
    # keyword — a whole-element selection is the way to retype an existing value.
    if _is_introduced(sel)
        return doc isa YamlInsertion || doc isa YamlSequence || doc isa YamlMapping
    end
    target = try evaluate_reference(doc, sel) catch; nothing end
    target === nothing && return false
    target isa YamlMappingEntry && return false
    return true
end

# A digit builds a fresh number, unless a whole number is already selected (that
# edit belongs to the typein path, which appends digits to the existing value).
function _replace_number(doc, c)
    target = try evaluate_reference(doc, getfield(doc, :selection)[]) catch; nothing end
    target isa YamlNumber && return nothing
    _replace(doc, with_selection(YamlNumber(parse(Int, string(c))), @reference value{1}))
end

# Append a YamlInsertion and select it whole, ready to type-to-replace. Declines
# (`,` stays a literal comma) while the caret is editing string text, so a comma
# can be typed into a string element / key; structural everywhere else.
function _sequence_insert(doc::YamlSequence)
    _in_string_context(doc, getfield(doc, :selection)[]) && return nothing
    n = length(doc.elements)
    insert_elements(@reference(elements), n, Any[YamlInsertion()],
                    @reference elements[n + 1])
end

# Append an empty entry and select its key for typing. Declines in a string
# context (see `_sequence_insert`).
function _mapping_insert(doc::YamlMapping)
    _in_string_context(doc, getfield(doc, :selection)[]) && return nothing
    n = length(doc.entries)
    insert_elements(@reference(entries), n,
                    Any[YamlMappingEntry("", YamlInsertion())],
                    @reference entries[n + 1].key{0})
end

# Tab moves the cursor from an entry's key to its value, selected whole.
function _mapping_tab(doc::YamlMapping)
    sel = getfield(doc, :selection)[]
    sel === nothing && return nothing
    @reference_case sel begin
        entries{s:e}.rest... => begin
            i = s + 1
            @reference_case rest begin
                key.inner... => ReplaceSelectionOperation(@reference entries[i].value)
            end
        end
    end
end

# ── Insertion factories ─────────────────────────────────────────────────────
#
# One construction per committable YAML value, with its cursor pre-placed —
# shared by the char type-to-replace gestures below and by the typed-name
# commit of a `YamlInsertion` / `DocumentInsertion`. `YamlNull` needs no
# method: the zero-arg fallback already covers it.
make_insertion_document(::Type{<:YamlBool}) =
    with_selection(YamlBool(false), EmptyReferencePath())
make_insertion_document(::Type{<:YamlNumber}) =
    with_selection(YamlNumber(nothing), @reference value{0})
make_insertion_document(::Type{<:YamlString}) =
    with_selection(YamlString(""), @reference value{0})
make_insertion_document(::Type{<:YamlSequence}) =
    with_selection(YamlSequence([YamlInsertion()]), @reference elements[1])
make_insertion_document(::Type{<:YamlMappingEntry}) =
    with_selection(YamlMappingEntry("", YamlInsertion()), @reference key{0})
make_insertion_document(::Type{<:YamlMapping}) =
    with_selection(YamlMapping([YamlMappingEntry("", YamlInsertion())]), @reference entries[1].key{0})

@gestures YamlDocument begin
    when(_yaml_replaceable(doc, sel))
    KeyPress('n') => "Replace with null"   => _replace(doc, with_selection(YamlNull(), EmptyReferencePath()))
    KeyPress('f') => "Replace with false"  => _replace(doc, make_insertion_document(YamlBool))
    KeyPress('t') => "Replace with true"   => _replace(doc, with_selection(YamlBool(true), EmptyReferencePath()))
    KeyPress('"') => "Replace with a string" => _replace(doc, make_insertion_document(YamlString))
    KeyPress('-') => "Replace with a sequence" => _replace(doc, make_insertion_document(YamlSequence))
    KeyPress(':') => "Replace with a mapping entry" => _replace(doc, make_insertion_document(YamlMappingEntry))
    KeyPress('{') => "Replace with a mapping" => _replace(doc, make_insertion_document(YamlMapping))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" => _replace_number(doc, c)
end

@gestures YamlSequence begin
    KeyPress(',') => "Insert a new element" => _sequence_insert(doc)
end

@gestures YamlMapping begin
    KeyPress(',') => "Insert a new entry" => _mapping_insert(doc)
    KeyDown(:tab) => "Move from key to value" => _mapping_tab(doc)
end

end # module
