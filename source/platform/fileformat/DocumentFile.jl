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
# by `make_file_tab` and the `FileDocument` save/reload keybindings below.
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

write_document_file(document::ReferencedDocument, path::AbstractString) =
    write_document_file(get_document(document), path)

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

"""
    make_file_tab(path, wrap = identity) -> FileDocument

The file document a tab opens for `path`: the type its extension is registered
under, holding the absolute path and [`read_document_file`](@ref)'s content. A
path that does not exist opens as the empty seed of its extension, which
`read_document_file` already gives. The absolute path is what `SaveFileOperation`
and `ReloadFileOperation` read the file back through, and what
[`get_document_title`](@ref) takes its base name from; a tab opened from outside
the working directory still saves and reloads through the file it was opened
from.

`wrap` is applied to the content before the file holds it. It is how an
application gives every file it opens an overlay of its own — a history, say —
without this layer naming one.
"""
make_file_tab(path::AbstractString, wrap = identity) =
    get_file_document_type(path)(abspath(path), wrap(read_document_file(path)))

"""
    make_file_tab_content(path, wrap = identity) -> WidgetScrollPane

The content of a tab that shows the file at `path`: the file document of
[`make_file_tab`](@ref) in a scroll pane, so a file longer than its tab scrolls.
The scroll is made here, where a file tab is made, and not by the tab: a tab page
gets no scroll of its own, because a page can hold two parts that each scroll.

Use it to open a file in a tab.
"""
make_file_tab_content(path::AbstractString, wrap = identity) =
    WidgetScrollPane(make_file_tab(path, wrap))

# ── What a file is called ────────────────────────────────────────────────────

# A tab with no name of its own is called after what it holds, and a file holds
# its own name. The base name is what a person reads: the directory is context,
# and a tab strip has no room for it.
get_document_title(file::FileDocument) = basename(String(get_filename(file)))

# ── Ctrl+S / Ctrl+O on a FileDocument ───────────────────────────────────────
#
# **Ctrl+S** saves the document's own `content` to its own `filename`,
# **Ctrl+O** reloads it.

"""
    SaveFileOperation(file)

Write `file`'s current content to its own name. A pure side effect; the
document is not mutated.
"""
struct SaveFileOperation <: Operation
    file::FileDocument
end

# `save_file!` dispatches on the file object and goes through each format's
# own `emit_text`, so it writes a `TextFile`'s raw `String` content and a
# `JsonFile`'s parsed tree alike. `write_document_file` takes a `::Document`
# and would reject a `TextFile`, whose `content` field is a plain `String`,
# not a `Document` — so it is not the uniform choice across every
# `FileDocument`.
function evaluate_operation(editor, op::SaveFileOperation)
    file = op.file
    # The file writes the document, not a wrapper around it: a content that
    # carries a history writes what the history is about. The save walks the
    # content for nodes of the file's own domain, and a wrapper is not one.
    content = get_wrapped_document(get_file_content(file))
    plain = Base.typename(typeof(file)).wrapper(get_filename(file), content)
    save_file!(plain, dirname(abspath(get_filename(file))))
end

# The text of a file is the text of what it holds, so a caller with a tab in
# hand asks the file itself. The history a file carries stays out of the answer,
# as it does for a save, and a content that is already a string is its own text.
NaturalModule.print_natural_text(file::FileDocument) =
    let content = get_wrapped_document(get_file_content(file))
        content isa AbstractString ? String(content) : print_natural_text(content)
    end

"""
    ReloadFileOperation(file)

Re-read `file`'s own name from disk and swap the result into its `content` (a
reactive write, so the projection re-renders). A non-existent file re-seeds
the extension's insertion placeholder.

It writes no selection. Ctrl+O answers it together with a selection of the whole
file, which every reader above makes a path from the root, because the old
selection pointed into the replaced content.
"""
struct ReloadFileOperation <: Operation
    file::FileDocument
end

function evaluate_operation(editor, op::ReloadFileOperation)
    file = op.file
    # A wrapper around the content — a history — keeps its place and takes the
    # new document; a plain content is replaced outright.
    file.content = replace_wrapped_document!(get_file_content(file),
                                             read_document_file(get_filename(file)))
    nothing
end

# Both commands need a name; decline (no binding fires) when the file has
# none — a "Save As" path picker for unnamed files is future work.
_save_file(doc::FileDocument)   = isempty(get_filename(doc)) ? nothing : SaveFileOperation(doc)
_reload_file(doc::FileDocument) =
    isempty(get_filename(doc)) ? nothing :
        CompoundOperation(Any[ReloadFileOperation(doc), ReplaceSelectionOperation(EmptyReference())])

@gestures FileDocument begin
    KeyDown(:s; ctrl) => "Save file to disk"     => _save_file(doc)
    KeyDown(:o; ctrl) => "Reload file from disk" => _reload_file(doc)
end

# Each carries its own subject and names no reference, so every reader
# between the gesture and the editor passes it up unchanged.
OperationModule.is_self_contained_operation(::Union{SaveFileOperation,
                                                    ReloadFileOperation}) = true

# ── What a model may write about a file ─────────────────────────────────────

"""
    make_file_api() -> Vector

The file verbs a model may call, as [`declare_api!`](@ref) takes them.

A host concatenates this with the other vocabularies it offers. It names only
this slice's own verbs: opening a path as a tab, reading and writing a document,
and the two operations a key answers. Where a file comes FROM — a workspace, a
file list, a dialog — belongs to the host, because a host knows what it holds.
"""
make_file_api() = Any[
    FileFormatModule => (
        # A path becomes a tab, and a tab becomes a file again.
        :make_file_tab, :make_file_tab_content, :read_document_file, :write_document_file,
        # What Ctrl+S and Ctrl+O answer with.
        :SaveFileOperation, :ReloadFileOperation,
        # Text in, document out, and back.
        :import_document, :export_document),
]
