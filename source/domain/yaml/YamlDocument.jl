# Fragment of `YamlModule` — the YAML document types, the document each
# insertion starts from, and the gestures that edit them.
#
# `@domain Yaml` declares the abstract `YamlDocument` type that every type below
# subtypes, and generates `YamlNothing` and `YamlInsertion`.

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

@forward_vector_protocol on YamlSequence to elements

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

@adapt_map_protocol on YamlMapping to entries with YamlMappingEntry(key, value)

YamlMapping(pairs::Pair{<:AbstractString}...) =
    YamlMapping([YamlMappingEntry(String(k), v) for (k, v) in pairs])

# A mapping entry must stay a key/value pair — it is retyped through its value.
_yaml_replaceable(doc, sel) =
    !(try_evaluate_reference(doc, normalize_named_node_reference(sel)) isa Union{Nothing, YamlMappingEntry})

# ── Insertion factories ─────────────────────────────────────────────────────

@insertion YamlBool         = @selected YamlBool(false)
@insertion YamlNumber       = @selected YamlNumber(nothing)
@insertion YamlString       = @selected YamlString("") value{0}
@insertion YamlSequence     = @selected YamlSequence([YamlInsertion()]) elements[1]
@insertion YamlMappingEntry = @selected YamlMappingEntry("", YamlInsertion()) key{0}
@insertion YamlMapping      = @selected YamlMapping([YamlMappingEntry("", YamlInsertion())]) entries[1].key{0}

@gestures YamlDocument begin
    when(_yaml_replaceable(doc, sel))
    KeyPress('n') => "Replace with null"   => replace_selected_document(doc, @selected YamlNull())
    KeyPress('f') => "Replace with false"  => replace_selected_document(doc, make_insertion_document(YamlBool))
    KeyPress('t') => "Replace with true"   => replace_selected_document(doc, @selected YamlBool(true))
    KeyPress('"') => "Replace with a string" => replace_selected_document(doc, make_insertion_document(YamlString))
    KeyPress('-') => "Replace with a sequence" => replace_selected_document(doc, make_insertion_document(YamlSequence))
    KeyPress(':') => "Replace with a mapping entry" => replace_selected_document(doc, make_insertion_document(YamlMappingEntry))
    KeyPress('{') => "Replace with a mapping" => replace_selected_document(doc, make_insertion_document(YamlMapping))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" =>
        replace_selected_document(doc, @selected YamlNumber(parse(Int, string(c))) value{1})
end

@gestures YamlSequence begin
    KeyPress(',') => "Insert a new element" => append_insertion_operation(doc, :elements, YamlInsertion)
end

@gestures YamlMapping begin
    KeyPress(',') => "Insert a new entry" => append_insertion_operation(doc, :entries, YamlMappingEntry)
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc; from = :key, to = :value)
end
