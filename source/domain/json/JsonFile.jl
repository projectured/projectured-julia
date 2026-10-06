# Fragment of `JsonModule` — `JsonFile`, the `.json` file on disk.
#
# A cross-file reference is written in JSON as a string whose whole value is a
# marker. The file writes one where the save cuts, and the load splices the node
# it names into its place; neither direction mutates the tree before it walks
# it. What this file contributes is the four lines every format owes: its
# domain, its parser, how it spells a reference leaf, and how it recognises one.
"""
    JsonFile(filename, content)

A file document whose `content` is a `JsonDocument`.
"""
@document struct JsonFile <: FileDocument
    filename::String
    content::Document = JsonNothing()
end

# What the file writes itself, and how it spells a reference to what it does
# not: a string whose whole value is the marker.
get_file_domain(::Type{<:JsonFile}) = JsonDocument
make_reference_leaf(::JsonFile, marker::AbstractString) = JsonString(make_marker_text(marker))
find_reference_marker(leaf::JsonString) = parse_marker_text(leaf.value)
parse_file_content(::Type{<:JsonFile}, text::AbstractString) = parse_json(text)

# Emit runs the `JsonToSyntax → SyntaxToText → TextToString` chain.
emit_text(f::JsonFile) = print_natural_text(get_file_content(f))
