"""
    DocumentFileModule

Format-by-extension file I/O — the single "read/write a document file" seam that
bridges the two serializers and the domain insertion seeds:

| extension | write | read (exists) | read (missing) |
|-----------|-------|---------------|----------------|
| `.pdoc`   | binary `save_document` | `load_document` | `DocumentNothing` |
| natural   | `export_document`      | `import_document` | the domain's seed |

Opening a *non-existent* file yields the extension's seed — the domain insertion
placeholder registered on `new_document_seed` (`.json` → `JsonInsertion`, …), or a
`DocumentNothing` otherwise — so a new file starts as an editable seed that can be
typed into and then saved. Used by the `WorkbenchEditor` save/reload keybindings
and the file-editor registry.

Sits in `visual` beside [`NaturalFormatModule`](@ref) (the natural half needs the
visual text printers); the binary half calls up to `base`'s
[`BinarySerializationModule`](@ref).
"""
module DocumentFileModule

import ..DocumentModule: Document
import ..BinarySerializationModule: save_document, load_document
import ..NaturalFormatModule: export_document, import_document
import ..DocumentCoreModule: DocumentNothing

export write_document_file, read_document_file, new_document_for, new_document_seed

const _BINARY_EXT = ".pdoc"

_ext(path::AbstractString) = lowercase(splitext(path)[2])
_ext_symbol(ext::AbstractString) = isempty(ext) ? Symbol("") : Symbol(SubString(ext, 2))

"""
    new_document_seed(::Val{ext}) -> Document

The empty seed a non-existent file of extension `ext` opens as. Each source
domain registers its insertion placeholder (`new_document_seed(::Val{:json}) =
JsonInsertion()`); the default is a `DocumentNothing`.
"""
new_document_seed(::Val) = DocumentNothing()

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
a fresh extension-appropriate seed (see [`new_document_for`](@ref)) so a new file
opens as an editable placeholder.
"""
read_document_file(path::AbstractString) =
    !isfile(path)             ? new_document_for(path) :
    _ext(path) == _BINARY_EXT ? load_document(path)    :
                                import_document(path)

"""
    new_document_for(path) -> Document

The empty seed a *non-existent* file of `path`'s extension should open as: the
domain's insertion placeholder for a registered natural format, or a
`DocumentNothing` otherwise (see [`new_document_seed`](@ref)). Typing into the
seed and saving creates the file.
"""
new_document_for(path::AbstractString) = new_document_seed(Val(_ext_symbol(_ext(path))))

end # module
