# Fragment of `MathModule` — `MathFile`, the `.math` file on disk: one formula
# in its linear form.
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
end

get_file_domain(::Type{<:MathFile}) = MathDocument
# A number in a formula is a primitive, and the file writes it as its own.
is_file_domain_node(::MathFile, node) = node isa MathDocument || node isa PrimitiveNumber
parse_file_content(::Type{<:MathFile}, text::AbstractString) = parse_math(strip(text))
emit_text(f::MathFile) = print_natural_text(get_file_content(f)) * "\n"
