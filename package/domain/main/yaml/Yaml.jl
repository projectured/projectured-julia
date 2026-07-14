"""
    YamlModule

The YAML document domain. YAML is a JSON superset; the value model mirrors it —
scalars, block/flow sequences, ordered mappings.
"""
module YamlModule

using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..ProjectionReferenceModule
using ..OperationModule
using ..SelectionModule
using ..EventPatternModule
using ..GestureBindingModule
using ..DomainModule

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
end

"""
A YAML boolean literal (`true` or `false`).
"""
@document struct YamlBool <: YamlDocument
    value::Bool
end

"""
A YAML number literal. `value` may be `nothing` while its text has been fully deleted.
"""
@document struct YamlNumber <: YamlDocument
    value::Union{Real, Nothing}
end

"""
A YAML string scalar (plain, single-, or double-quoted — the quoting style is a
projection concern, not part of the value).
"""
@document struct YamlString <: YamlDocument
    value::String
end

# ── Compounds ────────────────────────────────────────────────────────────

"""
A YAML sequence (a `- item` block list or `[…]` flow list). `collapsed` hides its
elements behind a marker in the projection.
"""
@document struct YamlSequence <: YamlDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector YamlSequence elements

"""
One `key: value` member of a YAML mapping.
"""
@document struct YamlMappingEntry <: YamlDocument
    key::String
    value::Document
    collapsed::Bool = false
end

"""
A YAML mapping (a `key: value` block or `{…}` flow map) — an ordered sequence of
`YamlMappingEntry` members. `collapsed` hides them in the projection.
"""
@document struct YamlMapping <: YamlDocument
    entries::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_map YamlMapping entries key value YamlMappingEntry

# build a mapping from `key => value` pairs
YamlMapping(pairs::Pair{<:AbstractString}...) =
    YamlMapping([YamlMappingEntry(String(k), v) for (k, v) in pairs])

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
#
# A gesture here fires only on a key the *output* layers left unclaimed — the
# reader runs last-to-first, so a printable key that the text layer turned into a
# character edit never reaches the domain. That is why nothing below asks whether
# the caret sits inside a string: if it does, `,` was already a comma.

# Replace the currently-selected value with `newdoc` (whose cursor is pre-placed via
# `with_selection`).
_replace(doc, newdoc) =
    replace_document(named_node_reference(getfield(doc, :selection)[]), newdoc)

# Block precondition for the type-to-replace set: the caret names a whole YAML
# value whose target exists and is replaceable (values / sequence elements / root —
# not a mapping entry wrapper).
function _yaml_replaceable(doc, sel)
    sel === nothing && return false
    # An introduced caret names the focused node. Enable type-to-replace there for a
    # `YamlInsertion` placeholder or a container (you are on its marker / brace), but
    # not on a concrete scalar's own quotes / keyword — a whole-element selection is
    # the way to retype an existing value.
    if is_introduced_reference(sel)
        return doc isa YamlInsertion || doc isa YamlSequence || doc isa YamlMapping
    end
    target = try_evaluate_reference(doc, sel)
    target === nothing && return false
    return !(target isa YamlMappingEntry)
end

# Append a YamlInsertion and select it whole, ready to type-to-replace.
function _sequence_insert(doc::YamlSequence)
    n = length(doc.elements)
    insert_elements(@reference(doc, elements), n, Any[YamlInsertion()],
                    @reference ::YamlSequence.elements::CellVector[n + 1]::YamlInsertion)
end

# Append an empty entry and select its key for typing.
function _mapping_insert(doc::YamlMapping)
    n = length(doc.entries)
    insert_elements(@reference(doc, entries), n,
                    Any[YamlMappingEntry("", YamlInsertion())],
                    @reference ::YamlMapping.entries::CellVector[n + 1]::YamlMappingEntry.key::String{0}::Position)
end

# Tab moves the cursor from an entry's key to its value, selected whole.
function _mapping_tab(doc::YamlMapping)
    sel = getfield(doc, :selection)[]
    sel === nothing && return nothing
    @reference_case sel begin
        ::YamlMapping.entries{s:e}.rest... => begin
            i = s + 1
            @reference_case rest begin
                ::YamlMappingEntry.key.inner... => ReplaceSelectionOperation(@reference ::YamlMapping.entries::CellVector[i]::YamlMappingEntry.value::Document)
            end
        end
    end
end

# ── Insertion factories ─────────────────────────────────────────────────────

@insertion YamlBool         = @with_selection YamlBool(false)
# An empty number's value is `nothing`, which has no text position, so it is selected
# whole; an empty string is `""` and does have position 0.
@insertion YamlNumber       = @with_selection YamlNumber(nothing)
@insertion YamlString       = @with_selection YamlString("") value{0}
@insertion YamlSequence     = @with_selection YamlSequence([YamlInsertion()]) elements[1]
@insertion YamlMappingEntry = @with_selection YamlMappingEntry("", YamlInsertion()) key{0}
@insertion YamlMapping      = @with_selection YamlMapping([YamlMappingEntry("", YamlInsertion())]) entries[1].key{0}

@gestures YamlDocument begin
    when(_yaml_replaceable(doc, sel))
    KeyPress('n') => "Replace with null"   => _replace(doc, @with_selection YamlNull())
    KeyPress('f') => "Replace with false"  => _replace(doc, make_insertion_document(YamlBool))
    KeyPress('t') => "Replace with true"   => _replace(doc, @with_selection YamlBool(true))
    KeyPress('"') => "Replace with a string" => _replace(doc, make_insertion_document(YamlString))
    KeyPress('-') => "Replace with a sequence" => _replace(doc, make_insertion_document(YamlSequence))
    KeyPress(':') => "Replace with a mapping entry" => _replace(doc, make_insertion_document(YamlMappingEntry))
    KeyPress('{') => "Replace with a mapping" => _replace(doc, make_insertion_document(YamlMapping))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" =>
        _replace(doc, @with_selection YamlNumber(parse(Int, string(c))) value{1})
end

@gestures YamlSequence begin
    KeyPress(',') => "Insert a new element" => _sequence_insert(doc)
end

@gestures YamlMapping begin
    KeyPress(',') => "Insert a new entry" => _mapping_insert(doc)
    KeyDown(:tab) => "Move from key to value" => _mapping_tab(doc)
end

end # module
