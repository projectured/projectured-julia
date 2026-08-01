"""
    TextFileModule

The simplest concrete `FileDocument`: `TextFile`, whose `content` is a
raw `String`. Emit is the identity (write `content` unchanged); load
reads the file as a `String`. No parser, no printer, no projection —
this is the fallback for a file the driver doesn't know a format for,
and the smallest possible test target for the `save_project!` /
`load_project` driver.
"""
module TextFileModule

import ..CellModule: Cell
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..FileProjectModule: FileDocument, emit_text, load_file, content

export TextFile

"""
    TextFile(filename, content)

A file document whose `content` is a plain `String` — no parser
runs, no projection is invoked. Used both as the S2 driver's test
target and as the ultimate fallback for any file whose extension
the higher formats don't claim.
"""
@document struct TextFile <: FileDocument
    filename::String
    content::String = ""
end

emit_text(f::TextFile) = content(f)

load_file(::Type{TextFile}, filename::AbstractString, base_dir::AbstractString) =
    TextFile(String(filename), read(joinpath(base_dir, filename), String))

end # module
