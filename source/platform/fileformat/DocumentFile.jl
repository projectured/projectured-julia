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

Use it to save a document to a file, in the format of the extension of the file.

# Example

    notes_1 = read_document_file("notes.json")
    write_document_file(notes_1, "notes_copy.json")

See also `read_document_file` and `export_document`.
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

Use it to read a file of any supported format into a document.

# Example

    notes_1 = read_document_file("notes.json")

See also `write_document_file` and `import_document`.
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
    make_file_tab(path, wrap = identity) -> file document, or what `wrap` makes of it

The file document a tab opens for `path`: the type its extension is registered
under, holding the absolute path and [`read_document_file`](@ref)'s content. A
path that does not exist opens as the empty seed of its extension, which
`read_document_file` already gives. The absolute path is what `SaveFileOperation`
and `ReloadFileOperation` read the file back through, and what
[`get_document_title`](@ref) takes its base name from; a tab opened from outside
the working directory still saves and reloads through the file it was opened
from.

A file that is its own content ([`is_own_content`](@ref)) holds no content apart
from itself. The tab then holds the file that
[`make_file`](@ref) builds from the text under the absolute path.

`wrap` is applied to the content before the file holds it. It is how an
application gives every file it opens an overlay of its own — a history, say —
without this layer naming one. A file that is its own content is its content, so
`wrap` is applied to the file, and the result is what `wrap` makes.

Use it to make the document of a file, with the content that the file holds on the disk.

# Example

    file_1 = make_file_tab("notes.json")

See also `make_file_tab_content` and `read_document_file`.
"""
function make_file_tab(path::AbstractString, wrap = identity)
    file_type = get_file_document_type(path)
    content = read_document_file(path)
    is_own_content(content) || return file_type(abspath(path), wrap(content))
    # The read built the file with the name that its parser gives, which is not the
    # absolute path.
    wrap(make_file(file_type, abspath(path), read(path, String)))
end

"""
    make_file_tab_content(path, wrap = identity) -> WidgetScrollPane

The content of a tab that shows the file at `path`: the file document of
[`make_file_tab`](@ref) in a scroll pane, so a file longer than its tab scrolls.
The scroll is made here, where a file tab is made, and not by the tab: a tab page
gets no scroll of its own, because a page can hold two parts that each scroll.

Use it to open a file in a tab.

# Example

    content_1 = make_file_tab_content("notes.json")
    open_pane!(content_1; title = "notes.json")

See also `make_file_tab` and `open_pane!`.
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

Use it to write an open file to the disk, as Ctrl+S does.

# Example

    file_1 = make_file_tab("notes.json")
    evaluate_operation(editor, SaveFileOperation(file_1))

See also `ReloadFileOperation` and `write_document_file`.
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
    # A file that a person does not edit has nothing of a person to write.
    is_editable_file_type(typeof(file)) || return nothing
    text = save_file_text!(_make_plain_file(file), dirname(abspath(get_filename(file))))
    text === nothing && return false
    # The history of the file notes that the file holds what the history holds now,
    # and the hash of that text, which tells a watcher of the file that this save
    # wrote it.
    record_saved_state!(get_file_content(file); text_hash = hash(text))
    true
end

"""
    record_saved_state!(content; text_hash = nothing) -> nothing

Note that the file that holds `content` holds what `content` is now, as after a
save, so [`has_unsaved_edits`](@ref) answers `false` until the next edit.
`text_hash` is the hash of the text that the save wrote, which
[`get_saved_text_hash`](@ref) answers. A history answers both by keeping its
newest step and the hash. The default does nothing, for a content that keeps no
history.
"""
function record_saved_state! end

record_saved_state!(content; text_hash = nothing) = nothing

"""
    has_unsaved_edits(content) -> Union{Bool, Nothing}

Whether `content`, what a file holds, has edits since its file was read or saved.
A history answers it from its steps. The default answers `nothing`, for a content
that keeps no history and so can not say.
"""
function has_unsaved_edits end

has_unsaved_edits(content) = nothing

"""
    get_saved_text_hash(content) -> Union{UInt64, Nothing}

The hash of the text that the last save of the file that holds `content` wrote,
while no load replaced the document since; `nothing` before the first save, and
for a content that keeps no history. A watcher of the file compares it with the
hash of the file on disk: an equal hash is the save, and not a change of another
program.
"""
function get_saved_text_hash end

get_saved_text_hash(content) = nothing

# The facets of a file document, which a roster of files shows, filters and sorts
# by. The folder is the folder of the file name as the file gives it.
get_item_facets(::Type{FileDocument}) = [
    "name" => "the name of the file, without its folder",
    "folder" => "the folder of the file, as its file name gives it",
    "has_edits" => "whether the document has edits since its file was read or saved; nothing for a file " *
                   "that keeps no history"]
compute_item_facet(file::FileDocument, ::Val{:name}) = basename(String(get_filename(file)))
compute_item_facet(file::FileDocument, ::Val{:folder}) = dirname(String(get_filename(file)))
compute_item_facet(file::FileDocument, ::Val{:has_edits}) = has_unsaved_edits(get_file_content(file))

# The file with the document that it holds and not a wrapper around it: a content
# that carries a history writes what the history is about. The save walks the
# content for nodes of the file's own domain, and a wrapper is not one. A file
# that holds no document, such as a text file, holds a `String`, which the
# editor edits as a `PrimitiveString` (`_read_registered_file`); the save takes
# the string back out.
function _make_plain_file(file::FileDocument)
    content = get_wrapped_document(get_file_content(file))
    (content isa PrimitiveString && get_file_domain(typeof(file)) === Union{}) &&
        (content = something(content.value, ""))
    Base.typename(typeof(file)).wrapper(get_filename(file), content)
end

"""
    compute_file_text(file) -> String

The text that `SaveFileOperation` writes for `file` now: the document that the
file holds, without a wrapper such as a history, in the notation of the file
type. It writes nothing. Use it to compare a file document with its file on
disk.
"""
compute_file_text(file::FileDocument) =
    cut_file_text(_make_plain_file(file), dirname(abspath(get_filename(file))))

# The text of a file is the text of what it holds, so a caller with a tab in
# hand asks the file itself. The history a file carries stays out of the answer,
# as it does for a save, and a content that is already a string is its own text.
NaturalModule.print_natural_text(file::FileDocument) =
    let content = get_wrapped_document(get_file_content(file))
        content isa AbstractString ? String(content) : print_natural_text(content)
    end

"""
    ReloadFileOperation(file; content = nothing)

Swap the document of the file of `file` into its `content`, a reactive write, so
the projection renders it again: `content` when it is given, such as a document
that a watcher of the file read off the loop with
[`read_file_content_again`](@ref), or else the file read again from disk now. A
non-existent file seeds the insertion placeholder of its extension again.

It writes no selection. Ctrl+O answers it together with a selection of the whole
file, which every reader above makes a path from the root, because the old
selection pointed into the replaced content.

Use it to read an open file again from the disk, as Ctrl+O does.

# Example

    file_1 = make_file_tab("notes.json")
    evaluate_operation(editor, ReloadFileOperation(file_1))

See also `SaveFileOperation` and `make_file_tab`.
"""
struct ReloadFileOperation <: Operation
    file::FileDocument
    content::Any
end

ReloadFileOperation(file::FileDocument; content = nothing) = ReloadFileOperation(file, content)

function evaluate_operation(editor, op::ReloadFileOperation)
    file = op.file
    content = op.content === nothing ? _read_file_again(file) : op.content
    # A wrapper around the content — a history — keeps its place and takes the
    # new document; a plain content is replaced outright.
    file.content = replace_wrapped_document!(get_file_content(file), content)
    nothing
end

"""
    read_file_content_again(type, path) -> document

The document that the file at `path` holds, read as the file type `type` reads
it. An opener can choose a file type that its extension does not name, such as a
store in a `.json` file, and the read does not hand that file to the parser of
the extension. Any task can call it: it reads the file and makes a new document,
which no computation reads yet.
"""
function read_file_content_again(type::Type, path::AbstractString)
    is_extension_type = has_file_document_type(path) && get_file_document_type(path) === type
    (isfile(path) && !is_extension_type) ? _read_own_file(type, path) : read_document_file(path)
end

# The document of the file of `file`, read again as its own file type reads it.
_read_file_again(file::FileDocument) =
    read_file_content_again(Base.typename(typeof(file)).wrapper, get_filename(file))

function _read_own_file(type, path::AbstractString)
    content = is_editable_file_type(type) ? get_file_content(make_file(type, basename(path), read(path, String))) :
                                            read_file_content(type, path)
    content isa AbstractString ? PrimitiveString(String(content)) : content
end

# Both commands need a name; decline (no binding fires) when the file has
# none — a "Save As" path picker for unnamed files is future work. A save also
# declines for a file that a person does not edit.
_save_file(doc::FileDocument)   =
    (isempty(get_filename(doc)) || !is_editable_file_type(typeof(doc))) ? nothing : SaveFileOperation(doc)
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
