# Fragment of `MathModule` — `MathFile`, the `.math` file on disk: one formula
# in its linear form, and `MathFileFormat`, its format.
#
# Neither the linear form nor the tree can hold a reference to another file,
# so a node of a `.math` file belongs to that file alone, as a node of a NED
# file does.

"""
    MathFile(filename, content)

A file document whose `content` is a `MathDocument`, written as its linear
form.
"""
@document struct MathFile <: FileDocument
    filename::String
    content::Document = MathInsertion()
    disk::FileDiskState = FileDiskState()
end

get_file_domain(::Type{<:MathFile}) = MathDocument
# A number in a formula is a primitive, and the file writes it as its own.
is_file_domain_node(::MathFile, node) = node isa MathDocument || node isa PrimitiveNumber
parse_file_content(::Type{<:MathFile}, text::AbstractString) = parse_math(strip(text))
emit_text(f::MathFile) = print_natural_text(get_file_content(f)) * "\n"

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
is_file_domain_node(::MathFileFormat, node) =
    node isa MathDocument || node isa PrimitiveNumber
parse_document_string(::MathFileFormat, string::AbstractString) =
    parse_math(strip(string))
get_file_type(::MathFileFormat) = MathFile
get_file_format(::MathFile) = MathFileFormat()
find_natural_file_format(::MathDocument) = MathFileFormat()
