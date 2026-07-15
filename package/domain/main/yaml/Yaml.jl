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
# The command set mirrors JSON's — YAML is a JSON superset. As there, nothing asks
# whether the caret sits inside a string: the reader runs last-to-first, so a key the
# text layer turned into a character edit never reaches the domain.

# Replace the named node — unless it is a mapping entry, which is retyped through its
# value. Every other "meaningful type-in" is caught a layer up: a keystroke that maps to
# editable text is consumed there and only *falls through* to us when it can't be (a
# projection-introduced token, or a whole-node selection), so any key reaching here is a
# replace command. `named_node_reference` normalizes an introduced caret to ∅ (the whole
# node) and subsumes the `sel === nothing` / unresolvable guards.
function _yaml_replaceable(doc, sel)
    node = try_evaluate_reference(doc, named_node_reference(sel))
    return node !== nothing && !(node isa YamlMappingEntry)
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
    KeyPress('n') => "Replace with null"   => replace_selected_document(doc, @with_selection YamlNull())
    KeyPress('f') => "Replace with false"  => replace_selected_document(doc, make_insertion_document(YamlBool))
    KeyPress('t') => "Replace with true"   => replace_selected_document(doc, @with_selection YamlBool(true))
    KeyPress('"') => "Replace with a string" => replace_selected_document(doc, make_insertion_document(YamlString))
    KeyPress('-') => "Replace with a sequence" => replace_selected_document(doc, make_insertion_document(YamlSequence))
    KeyPress(':') => "Replace with a mapping entry" => replace_selected_document(doc, make_insertion_document(YamlMappingEntry))
    KeyPress('{') => "Replace with a mapping" => replace_selected_document(doc, make_insertion_document(YamlMapping))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" =>
        replace_selected_document(doc, @with_selection YamlNumber(parse(Int, string(c))) value{1})
end

@gestures YamlSequence begin
    KeyPress(',') => "Insert a new element" => append_insertion_operation(doc, :elements, YamlInsertion)
end

@gestures YamlMapping begin
    KeyPress(',') => "Insert a new entry" => append_insertion_operation(doc, :entries, YamlMappingEntry)
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc, :key, :value)
end

end # module
