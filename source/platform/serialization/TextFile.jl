# Fragment of `SerializationModule`.
#
# The simplest concrete `FileDocument`: `TextFile`, whose `content` is a
# raw `String`. Emit is the identity (write `content` unchanged); load
# reads the file as a `String`. No parser, no printer, no projection —
# this is what a file with no extension or a `.txt` extension loads as,
# and the smallest possible test target for the `save_project!` /
# `load_project` driver.
"""
    TextFile(filename, content)

A file document whose `content` is a plain `String` — no parser
runs, no projection is invoked. Used both as the driver's simplest
test target and as what a `""` (no extension) or a `.txt` path
loads as.
"""
@document struct TextFile <: FileDocument
    filename::String
    content::Union{String, Document} = ""
end

emit_text(f::TextFile) = get_file_content(f)

# A text file holds no document, so nothing is its domain and nothing in it is a
# reference; a document held by one has no file to be written into.
get_file_domain(::Type{<:TextFile}) = Union{}
parse_file_content(::Type{<:TextFile}, text::AbstractString) = String(text)

# Registered for `""` (no extension) and `.txt`, both of which load as a raw
# text file. A concrete format that wants either extension registers itself
# on top. Registered in `__init__` so the mutation survives precompilation
# (Julia does not preserve state built up by top-level statements across the
# precompile boundary).

