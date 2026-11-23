# Fragment of `SerializationModule` — `TextFileFormat`, the format of a plain text
# file, and `TextFile`, its file.
#
# The simplest format: the content of a `TextFile` is a raw `String`, and the
# string of the file is that content as it is. No parser, no printer, no
# projection — this is what a file with no extension, a `.txt` or a `.log` extension
# loads as, and the smallest possible test target for the `save_project!` /
# `load_project` driver.

"""
    TextFileFormat()

The format of a plain text file, `.txt`, `.log` or a name with no extension: its
string is the content of its file, a `TextFile`, as it is. A new file takes `.txt`. The
format has no domain: a text file holds no document, and nothing in its text is
a reference.
"""
struct TextFileFormat <: FileFormat end

get_file_format_extensions(::TextFileFormat) = (".txt", ".log", "")
get_file_format_domain(::TextFileFormat) = Union{}
parse_document_string(::TextFileFormat, string::AbstractString) = String(string)
make_document_string(::TextFileFormat, string::AbstractString) = String(string)

"""
    TextFile(filename, content = "")

A file of [`TextFileFormat`](@ref), whose `content` is a plain `String` — no
parser runs, no projection is invoked. Used both as the driver's simplest test
target and as what a `""` (no extension) or a `.txt` path loads as.
"""
const TextFile = File{TextFileFormat}
