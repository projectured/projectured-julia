# Fragment of `SerializationModule`.
#
# The simplest concrete `FileDocument`: `TextFile`, whose `content` is a
# raw `String`. Emit is the identity (write `content` unchanged); load
# reads the file as a `String`. No parser, no printer, no projection —
# this is the fallback for a file the driver doesn't know a format for,
# and the smallest possible test target for the `save_project!` /
# `load_project` driver.
"""
    TextFile(filename, content)

A file document whose `content` is a plain `String` — no parser
runs, no projection is invoked. Used both as the driver's simplest
test target and as the fallback for any file whose extension the
higher formats don't claim (registered as `""` so an unknown
extension routes here).
"""
@document struct TextFile <: FileDocument
    filename::String
    content::String = ""
end

emit_text(f::TextFile) = get_file_content(f)

# A text file holds no document, so nothing is its domain and nothing in it is a
# reference; a document held by one has no file to be written into.
get_file_domain(::Type{<:TextFile}) = Union{}
parse_file_content(::Type{<:TextFile}, text::AbstractString) = String(text)

# Fallback: any extension nothing else claims (including "") loads
# as a raw text file. A concrete format that wants an unknown
# extension registers itself on top. Registered in `__init__` so the
# mutation survives precompilation (Julia does not preserve state
# built up by top-level statements across the precompile boundary).

