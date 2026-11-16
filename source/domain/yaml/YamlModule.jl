"""
    YamlModule

YAML documents: scalars, sequences and ordered mappings, read from a file and
written back as text. YAML is a JSON superset; the value model mirrors it — scalars,
block/flow sequences, ordered mappings.
"""
module YamlModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: emit_text, get_file_domain, make_reference_leaf,
                              find_reference_marker, parse_file_content,
                              get_file_format_extensions, get_file_format_domain,
                              parse_document_string, get_file_type, get_file_format
import ..NaturalModule: make_syntax_projection, find_natural_file_format
import ..DisplayModule: make_workload_file

export parse_yaml, parse_yaml_file
export YamlTheme, ScaledYamlTheme
export YamlInsertionToSyntaxLeaf, YamlNullToSyntaxLeaf, YamlBoolToSyntaxLeaf, YamlNumberToSyntaxLeaf,
       YamlStringToSyntaxLeaf, YamlSequenceToSyntaxNode, YamlSequenceToBlockSyntaxNode, YamlMappingToSyntaxNode,
       YamlToSyntax
export YamlDocument, YamlNull, YamlBool, YamlNumber, YamlString, YamlNothing, YamlInsertion, YamlSequence, YamlMapping, YamlMappingEntry
export YamlFile, YamlFileFormat


include("YamlDocument.jl")
include("YamlParser.jl")
include("YamlTheme.jl")
include("YamlToSyntax.jl")
include("YamlFile.jl")

# The file that a workload of the window opens (`run_file_workload`).
make_workload_file(::Type{YamlFile}) =
    (; name = "a.yaml", text = "name: Alice\nage: 7\n", shown = r"Alice")

end # module
