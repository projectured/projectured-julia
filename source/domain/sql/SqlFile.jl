# Fragment of `SqlModule` — `SqlFile`, the `.sql` file on disk, and
# `SqlFileFormat`, its format.
#
# A cross-file reference is written in SQL as a string-literal scalar value
# whose whole value is the marker, the same way JSON and YAML use a string. The
# file writes one where the save cuts, and the load splices the node it names
# into its place; neither direction mutates the tree before it walks it. What
# this file contributes is the lines every format owes: its extension, its
# domain, its parser, how it spells a reference leaf, and how it recognises one;
# and the empty document of a new file of the domain.

"""
    SqlFileFormat()

The format of a `.sql` file: its string is the SQL text of one `SqlDocument`,
and its file is a `SqlFile`. A reference to another file is a string literal
whose whole value is the marker.
"""
struct SqlFileFormat <: FileFormat end

get_file_format_extensions(::SqlFileFormat) = (".sql",)
get_file_format_domain(::SqlFileFormat) = SqlDocument
parse_document_string(::SqlFileFormat, string::AbstractString) = parse_sql_text(string)
# What the file writes itself, and how it spells a reference to what it does
# not: a string literal whose whole value is the marker. `SqlScalarValue` also
# carries numbers and booleans, so only a `String` value is read back as one.
make_reference_leaf(::SqlFileFormat, marker::AbstractString) =
    SqlScalarValue(make_marker_text(marker))
find_reference_marker(leaf::SqlScalarValue) =
    leaf.value isa AbstractString ? parse_marker_text(leaf.value) : nothing
find_natural_file_format(::SqlDocument) = SqlFileFormat()
# A new file starts as the insertion of a first statement.
make_document_seed(::Type{SqlDocument}) = SqlInsertion()

"""
    SqlFile(filename, content)

A file of [`SqlFileFormat`](@ref), whose `content` is a `SqlDocument`.
"""
const SqlFile = File{SqlFileFormat}
