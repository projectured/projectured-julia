# Fragment of `SqlModule` — `SqlFile`, the `.sql` file on disk.
#
# A cross-file reference is written in SQL as a string-literal scalar value
# whose whole value is the marker, the same way JSON and YAML use a string. The
# file writes one where the save cuts, and the load splices the node it names
# into its place; neither direction mutates the tree before it walks it. What
# this file contributes is the four lines every format owes: its domain, its
# parser, how it spells a reference leaf, and how it recognises one.
"""
    SqlFile(filename, content)

A file document whose `content` is a `SqlDocument`.
"""
@document struct SqlFile <: FileDocument
    filename::String
    content::Document = SqlNothing()
end

# What the file writes itself, and how it spells a reference to what it does
# not: a string literal whose whole value is the marker. `SqlScalarValue` also
# carries numbers and booleans, so only a `String` value is read back as one.
get_file_domain(::Type{<:SqlFile}) = SqlDocument
make_reference_leaf(::SqlFile, marker::AbstractString) = SqlScalarValue(make_marker_text(marker))
find_reference_marker(leaf::SqlScalarValue) =
    leaf.value isa AbstractString ? parse_marker_text(leaf.value) : nothing
parse_file_content(::Type{<:SqlFile}, text::AbstractString) = parse_sql_text(text)

# Emit runs the `SqlToSyntax → SyntaxToText → TextToString` chain.
emit_text(f::SqlFile) = print_natural_text(get_file_content(f))
