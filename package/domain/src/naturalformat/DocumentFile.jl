"""
    DocumentFileModule

Format-by-extension file I/O — the single "read/write a document file" seam that
bridges the two serializers and the domain insertion seeds:

| extension | write | read (exists) | read (missing) |
|-----------|-------|---------------|----------------|
| `.pdoc`   | binary `save_document` | `load_document` | `DocumentNothing` |
| `.json`   | natural `export_document` | `import_document` | `JsonInsertion` |
| `.xml`    | natural `export_document` | `import_document` | `XmlInsertion` |
| `.sql`    | natural `export_document` | `import_document` | `SqlInsertion` |
| `.jl`     | natural `export_document` | `import_document` | `JuliaInsertion` |

Opening a *non-existent* file yields the extension's insertion placeholder, so a
new file starts as an editable seed that can be typed into and then saved. Used
by the `WorkbenchEditor` save/reload keybindings and the file-editor registry.
"""
module DocumentFileModule

import ..DocumentApiModule: Document
import ..BinarySerializationModule: save_document, load_document
import ..NaturalFormatModule: export_document, import_document
import ..JsonModule: JsonInsertion
import ..XmlModule: XmlInsertion
import ..SqlDocumentModule: SqlInsertion
import ..JuliaModule: JuliaInsertion
import ..DocumentCoreModule: DocumentNothing

export write_document_file, read_document_file, new_document_for

const _BINARY_EXT = ".pdoc"

_ext(path::AbstractString) = lowercase(splitext(path)[2])

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
    !isfile(path)                ? new_document_for(path) :
    _ext(path) == _BINARY_EXT    ? load_document(path)    :
                                   import_document(path)

"""
    new_document_for(path) -> Document

The empty seed a *non-existent* file of `path`'s extension should open as: the
domain's insertion placeholder for the natural formats, or a `DocumentNothing`
otherwise. Typing into the seed and saving creates the file.
"""
function new_document_for(path::AbstractString)
    ext = _ext(path)
    ext == ".json" ? JsonInsertion()  :
    ext == ".xml"  ? XmlInsertion()   :
    ext == ".sql"  ? SqlInsertion()   :
    ext == ".jl"   ? JuliaInsertion() :
                     DocumentNothing()
end

end # module
