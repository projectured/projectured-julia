"""
    YamlModule

The YAML document domain. YAML is a JSON superset; the value model mirrors it —
scalars, block/flow sequences, ordered mappings.
"""
module YamlModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..EventPatternModule
using ..GestureBindingModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export parse_yaml, parse_yaml_file
export YamlInsertionToSyntaxLeaf, YamlNullToSyntaxLeaf, YamlBoolToSyntaxLeaf, YamlNumberToSyntaxLeaf,
       YamlStringToSyntaxLeaf, YamlSequenceToSyntaxNode, YamlSequenceToBlockSyntaxNode, YamlMappingToSyntaxNode,
       YamlToSyntax
export YamlDocument, YamlNull, YamlBool, YamlNumber, YamlString, YamlNothing, YamlInsertion, YamlSequence, YamlMapping, YamlMappingEntry


include("YamlDocument.jl")
include("YamlParser.jl")
include("YamlToSyntax.jl")

end # module
