# Fragment of `FileFormatModule`.
#
# Format-by-extension file I/O — the single "read/write a document file" seam that
# bridges the two serializers and the domain insertion seeds:
#
# | extension | write | read (exists) | read (missing) |
# |-----------|-------|---------------|----------------|
# | `.pdoc`   | binary `save_document` | `load_document` | `DocumentNothing` |
# | natural   | `export_document`      | `import_document` | the domain's seed |
# | a file type without a natural format (`.pred`, `.txt`, none) | `save_file!` | `load_file` | the extension's seed |
#
# The natural formats are the ones a domain registered a parser for:
# `.json`, `.xml`, `.yaml`, `.md`, `.rst`, `.math`, `.jl` and `.sql`. The third
# row takes the file type that `register_file_document_type!` names for the
# extension. A text file holds a `String`, and an editor edits a
# `PrimitiveString`, so a text file reads into one and writes from one.
#
# Opening a *non-existent* file yields the extension's seed — the domain insertion
# placeholder registered on `make_document_seed` (`.json` → `JsonInsertion`, …), an
# empty `PrimitiveString` for a text file, or a `DocumentNothing` otherwise — so a
# new file starts as an editable seed that can be typed into and then saved. Used
# by the `WorkbenchEditor` save/reload keybindings and the file-editor registry.
#
# The binary half and the file types call down to
# [`SerializationModule`](@ref); the natural half needs the text printers.
const _BINARY_EXT = ".pdoc"

_ext(path::AbstractString) = lowercase(splitext(path)[2])

"""
    make_document_seed(::Val{ext}) -> Document

The empty seed a non-existent file of extension `ext` opens as. Each source
domain registers its insertion placeholder (`make_document_seed(::Val{:json}) =
JsonInsertion()`); the default is a `DocumentNothing`.
"""
make_document_seed(::Val) = DocumentNothing()
make_document_seed(::Val{:txt}) = PrimitiveString("")
make_document_seed(::Val{Symbol("")}) = PrimitiveString("")

# Whether a domain registered a parser for the extension of `path`.
_is_natural_path(path::AbstractString) = has_natural_parser(_ext_symbol(_ext(path)))

# Whether `path` goes through a file type rather than a natural format.
_is_registered_file_path(path::AbstractString) =
    !_is_natural_path(path) && has_file_document_type(path)

"""
    write_document_file(document, path) -> path

Write `document` to `path`, choosing the format by extension: the binary snapshot
format for `.pdoc`, the natural text format for an extension a domain parses,
and the registered file type for any other extension that has one (`.pred`,
`.txt`, no extension). An extension with neither is written as natural text.
"""
function write_document_file(document::Document, path::AbstractString)
    _ext(path) == _BINARY_EXT && return save_document(document, path)
    _is_registered_file_path(path) && return _write_registered_file(document, path)
    export_document(document, path)
end

"""
    read_document_file(path) -> Document

Read `path` into a document. When the file exists the format is chosen by
extension, as [`write_document_file`](@ref) chooses it. When it does not exist,
return a fresh extension-appropriate seed (see [`make_document_for`](@ref)) so a
new file opens as an editable placeholder.
"""
function read_document_file(path::AbstractString)
    isfile(path) || return make_document_for(path)
    _ext(path) == _BINARY_EXT && return load_document(path)
    _is_registered_file_path(path) && return _read_registered_file(path)
    import_document(path)
end

# One file of a registered type, read with no other file around it: a reference
# in it stays a leaf. A text file's `String` becomes a `PrimitiveString`.
function _read_registered_file(path::AbstractString)
    file = load_file(dirname(abspath(path)), basename(path))
    content = get_file_content(file)
    content isa AbstractString ? PrimitiveString(String(content)) : content
end

# The same file type, written alone: `save_file!` refuses a document that would
# need a reference to another file, and logs why.
function _write_registered_file(document::Document, path::AbstractString)
    file_type = get_file_document_type(path)
    content = document isa PrimitiveString ? something(document.value, "") : document
    file = file_type(basename(path), content)
    save_file!(file, dirname(abspath(path))) ||
        error("write_document_file: could not write $(repr(path)); the log says why")
    path
end

"""
    make_document_for(path) -> Document

The empty seed a *non-existent* file of `path`'s extension should open as: the
domain's insertion placeholder for a registered natural format, or a
`DocumentNothing` otherwise (see [`make_document_seed`](@ref)). Typing into the
seed and saving creates the file.
"""
make_document_for(path::AbstractString) = make_document_seed(Val(_ext_symbol(_ext(path))))
