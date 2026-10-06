# Fragment of `YamlModule` — `YamlFile`, the `.yaml` (and `.yml`) file on disk.
#
# A cross-file reference is written in YAML as a string scalar whose whole
# value is the marker, the same way JSON uses a string. The file writes one
# where the save cuts, and the load splices the node it names into its place;
# neither direction mutates the tree before it walks it. What this file
# contributes is the four lines every format owes: its domain, its parser, how
# it spells a reference leaf, and how it recognises one.
"""
    YamlFile(filename, content)

A file document whose `content` is a `YamlDocument`.
"""
@document struct YamlFile <: FileDocument
    filename::String
    content::Document = YamlNothing()
end

# What the file writes itself, and how it spells a reference to what it does
# not: a string whose whole value is the marker.
get_file_domain(::Type{<:YamlFile}) = YamlDocument
make_reference_leaf(::YamlFile, marker::AbstractString) = YamlString(make_marker_text(marker))
find_reference_marker(leaf::YamlString) = parse_marker_text(leaf.value)
parse_file_content(::Type{<:YamlFile}, text::AbstractString) = parse_yaml(text)

# Emit runs the `YamlToSyntax → SyntaxToText → TextToString` chain.
emit_text(f::YamlFile) = print_natural_text(get_file_content(f))
