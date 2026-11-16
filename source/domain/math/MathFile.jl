# Fragment of `MathModule` — `MathFile`, the `.math` file on disk: one formula
# in its linear form, and `MathFileFormat`, its format.
#
# Neither the linear form nor the tree can hold a reference to another file,
# so a node of a `.math` file belongs to that file alone, as a node of a NED
# file does.

"""
    MathFileFormat()

The format of a `.math` file: its string is one formula, a `MathDocument`, in its
linear form, and its file is a `MathFile`. The parse ignores the white space
around the formula. A plain number in a formula is a node of the file too, and
the file holds no reference to another file.
"""
struct MathFileFormat <: FileFormat end

get_file_format_extensions(::MathFileFormat) = (".math",)
get_file_format_domain(::MathFileFormat) = MathDocument
# A number in a formula is a primitive, and the file writes it as its own.
is_file_domain_node(::MathFileFormat, node) =
    node isa MathDocument || node isa PrimitiveNumber
parse_document_string(::MathFileFormat, string::AbstractString) =
    parse_math(strip(string))
find_natural_file_format(::MathDocument) = MathFileFormat()
# A new file starts as the insertion of a formula.
make_document_seed(::Type{MathDocument}) = MathInsertion()

"""
    MathFile(filename, content)

A file of [`MathFileFormat`](@ref), whose `content` is a `MathDocument`, written
as its linear form.
"""
const MathFile = File{MathFileFormat}
