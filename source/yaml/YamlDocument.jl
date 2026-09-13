"""
    YamlModule

The YAML document domain. YAML is a JSON superset; the value model mirrors it —
scalars, block/flow sequences, ordered mappings.
"""
module YamlModule

export parse_yaml, parse_yaml_file
import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..SyntaxModule: DomainInsertionToSyntaxLeaf, InsertionNothingToSyntaxLeaf
import ..TextModule: TextString, make_hinted_text
import ..StyleModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..StyleModule: color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_yellow, color_solarized_gray
import ..StyleModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode, SyntaxDelimitation
import ..ProjectionAlgebraModule: TypeDispatchingProjection
import ..ProjectionAlgebraModule: CopyingProjection
import ..ProjectionTemplateModule: var"@projection_template", bound, project, collection
import ..PrimitiveModule: ReplaceNumberRangeOperation, ReplaceStringRangeOperation
import ..IoMapModule: ChildrenIoMap
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, FieldReferenceStep, RangeReferenceStep, EmptyReference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..PrinterContextModule: make_child_context
import ..OperationModule: ReplaceSelectionOperation
import ..OperationModule: reroot_operation
import ..GestureBindingModule: read_gesture
import ..EventModule: KeyPress, KeyDown
export YamlInsertionToSyntaxLeaf, YamlNullToSyntaxLeaf, YamlBoolToSyntaxLeaf, YamlNumberToSyntaxLeaf,
       YamlStringToSyntaxLeaf, YamlSequenceToSyntaxNode, YamlSequenceToBlockSyntaxNode, YamlMappingToSyntaxNode,
       YamlToSyntax
import ..NaturalModule: register_natural_domain!, register_natural_parser!
export YamlDocument, YamlNull, YamlBool, YamlNumber, YamlString, YamlNothing, YamlInsertion, YamlSequence, YamlMapping, YamlMappingEntry


using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..ProjectionReferenceStepModule
using ..OperationModule
using ..SelectionModule
using ..EventPatternModule
using ..GestureBindingModule
using ..DomainModule

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

@insertion YamlBool         = @with_selection YamlBool(false)
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


include("YamlParser.jl")
include("YamlToSyntax.jl")

end # module
