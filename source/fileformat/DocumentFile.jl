# ──────────────────────────────────────────────────────────────────────────
# Folded in from DocumentFile.jl.
const _BINARY_EXT = ".pdoc"

_ext(path::AbstractString) = lowercase(splitext(path)[2])

"""
    make_document_seed(::Val{ext}) -> Document

The empty seed a non-existent file of extension `ext` opens as. Each source
domain registers its insertion placeholder (`make_document_seed(::Val{:json}) =
JsonInsertion()`); the default is a `DocumentNothing`.
"""
make_document_seed(::Val) = DocumentNothing()

"""
    write_document_file(document, path) -> path

Write `document` to `path`, choosing the format by extension: the binary snapshot
format for `.pdoc`, otherwise the natural (printer/parser) text format.
"""
write_document_file(document::Document, path::AbstractString) =
    _ext(path) == _BINARY_EXT ? save_document(document, path) :
                                export_document(document, path)

"""
    read_document_file(path) -> Document

Read `path` into a document. When the file exists the format is chosen by
extension (binary for `.pdoc`, natural otherwise). When it does not exist, return
a fresh extension-appropriate seed (see [`make_document_for`](@ref)) so a new file
opens as an editable placeholder.
"""
read_document_file(path::AbstractString) =
    !isfile(path)             ? make_document_for(path) :
    _ext(path) == _BINARY_EXT ? load_document(path)    :
                                import_document(path)

"""
    make_document_for(path) -> Document

The empty seed a *non-existent* file of `path`'s extension should open as: the
domain's insertion placeholder for a registered natural format, or a
`DocumentNothing` otherwise (see [`make_document_seed`](@ref)). Typing into the
seed and saving creates the file.
"""
make_document_for(path::AbstractString) = make_document_seed(Val(_ext_symbol(_ext(path))))
