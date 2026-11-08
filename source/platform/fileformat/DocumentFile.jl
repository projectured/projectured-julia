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

For the assistant.
"""
function write_document_file end

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

For the assistant.
"""
function read_document_file end

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

For the assistant.
"""
function make_file_tab end

function make_file_tab(path::AbstractString, wrap = identity)
    file_type = get_file_document_type(path)
    content = read_document_file(path)
    if !is_own_content(content)
        file = file_type(abspath(path), wrap(content))
        _record_read_file_hash!(file)
        return file
    end
    # The read built the file with the name that its parser gives, which is not the
    # absolute path.
    file = make_file(file_type, abspath(path), read(path, String))
    _record_read_file_hash!(file)
    wrap(file)
end

# The file keeps the time and the size of its file on disk now, and the hash of its
# text, as the file was just read. A file that a person does not edit is not read for
# a hash: a save never writes it, and its file can be large.
function _record_read_file_hash!(file::FileDocument)
    isempty(get_filename(file)) && return nothing
    path = abspath(get_filename(file))
    state = get_file_disk_state(file)
    state.file_stamp = compute_file_stamp(path)
    is_editable_file_type(typeof(file)) && (state.file_hash = compute_file_text_hash(path))
    nothing
end

"""
    make_unread_file(path, wrap = identity) -> FileDocument

The file document of the file at `path` that reads nothing: it holds the seed of its
extension, with `wrap` applied to the seed as [`make_file_tab`](@ref) applies it to
the content, and it reads the file when a view of it is drawn. Until that read it
knows no hash, holds no edit that the read would lose, and refuses a save.

Use it to open a file whose read can wait until it shows, such as a file that a
saved window names.
"""
function make_unread_file(path::AbstractString, wrap = identity)
    seed = make_document_for(path)
    is_own_content(seed) &&
        throw(ArgumentError("The file at $path is its own content, so it can not be made unread."))
    file = get_file_document_type(path)(abspath(path), wrap(seed))
    get_file_disk_state(file).loaded_count = -1
    ensure_file_text_cell!(file)
    file
end

"""
    make_file_tab_content(path, wrap = identity) -> FileView

The content of a tab that shows the file at `path`: the view ([`FileView`](@ref))
of the file document of [`make_file_tab`](@ref). The view keeps a scroll pane, so a
file longer than its tab scrolls, and the band of the file stays above it. The file
grows down on its height, as a view of a file does, so a table on a Markdown page is
as tall as its rows and the tab scrolls it. The file knows the hash of the text that
it read ([`make_file_tab`](@ref)). The scroll is made here, where a file tab is made,
and not by the tab, because a tab page gets no scroll of its own: a page can hold two
parts that each scroll.

Use it to open a file in a tab.

# Example

    content_1 = make_file_tab_content("notes.json")
    open_pane!(content_1; title = "notes.json")

See also `make_file_tab` and `open_pane!`.

For the assistant.
"""
function make_file_tab_content end

function make_file_tab_content(path::AbstractString, wrap = identity)
    file = make_file_tab(path, wrap)
    # A file that is its own content has no content inside it to hold a history, so
    # `wrap` goes around the file, and the tab shows that part.
    file isa FileDocument ? make_file_view(file) : file
end

# ── What a file is called ────────────────────────────────────────────────────

# A tab with no name of its own is called after what it holds, and a file holds
# its own name. The base name is what a person reads: the directory is context,
# and a tab strip has no room for it.
get_document_title(file::FileDocument) = basename(String(get_filename(file)))

# ── Ctrl+S / F5 on a FileDocument ───────────────────────────────────────────
#
# **Ctrl+S** saves the document's own `content` to its own `filename`,
# **F5** reloads it.

"""
    SaveFileOperation(file; force = false)

Write `file`'s current content to its own name, when the file on disk still holds
the text of the last load or save of `file`, and keep the hash of the text that it
wrote. A pure side effect; the document is not mutated.

When another program changed the file on disk since, the file shows its band and
nothing is written: "Load it" reads the file ([`ReloadFileOperation`](@ref)), and
"Keep mine" answers this save with `force = true`, which writes with no check. A file
that knows no hash writes with no check too. A history inside the file adds no step
for a save, because it changes no document.

Ctrl+S answers it; code saves a file with `save_file_to_disk!`.

See also `ReloadFileOperation` and `write_document_file`.
"""
struct SaveFileOperation <: Operation
    file::FileDocument
    force::Bool
end

SaveFileOperation(file::FileDocument; force::Bool = false) = SaveFileOperation(file, force)

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
    state = get_file_disk_state(file)
    # A file that is not read yet holds the seed of its extension, and a save would
    # write that over the file.
    state.loaded_count < 0 && return false
    is_named = !isempty(get_filename(file))
    if is_named && !op.force && state.file_hash !== nothing &&
       compute_file_text_hash(abspath(get_filename(file))) != state.file_hash
        state.band = _make_changed_file_band(file, "Load it" => ReloadFileOperation(file),
                                             "Keep mine" => SaveFileOperation(file; force = true))
        return false
    end
    text = _write_file_text!(file)
    text === nothing && return false
    if is_named
        state.file_hash = hash(text)
        state.file_stamp = compute_file_stamp(abspath(get_filename(file)))
        state.band = nothing
    end
    true
end

# Write the text of `file` to its name, and answer that text, or `nothing` when
# nothing was written. The history of the file notes that the file holds what the
# history holds now.
function _write_file_text!(file::FileDocument)
    text = save_file_text!(_make_plain_file(file), dirname(abspath(get_filename(file))))
    text === nothing || record_saved_state!(get_file_content(file))
    text
end

# The band that says that the file changed on disk, with its two choices.
_make_changed_file_band(file, load, keep) =
    FileBand(; message = string(get_document_title(file), " changed on disk."),
               choices = Pair{String,Any}[load, keep])

"""
    record_saved_state!(content) -> nothing

Note that the file that holds `content` holds what `content` is now, as after a
save, so [`has_unsaved_edits`](@ref) answers `false` until the next edit. A
history answers it by keeping its newest step. The default does nothing, for a
content that keeps no history.
"""
function record_saved_state! end

record_saved_state!(content) = nothing

"""
    has_unsaved_edits(content) -> Union{Bool, Nothing}

Whether `content`, what a file holds, has edits since its file was read or saved.
A history answers it from its steps. The default answers `nothing`, for a content
that keeps no history and so can not say.

Use it to tell whether the file that holds a content differs from what the content is now.

# Example

    has_unsaved_edits(content_1)

See also `compute_file_text`.

For the assistant.
"""
function has_unsaved_edits end

has_unsaved_edits(content) = nothing

"""
    compute_file_stamp(path) -> Union{Tuple, Nothing}

The time and the size of the file at `path` on disk now, or `nothing` when there is
no file. It reads no text. A watch of a file compares stamps to tell that the file
changed, and a file document keeps the stamp of its last read in its
[`FileDiskState`](@ref).
"""
compute_file_stamp(path::AbstractString) = isfile(path) ? (mtime(path), filesize(path)) : nothing

# How long the time and the size of a file stay the same before a read takes it, and
# the longest wait for that, in seconds. A program writes a file in more than one
# step.
const FILE_SETTLE_SECONDS = 0.05
const FILE_SETTLE_LIMIT_SECONDS = 2.0

# Wait until the time and the size of the file at `path` stay the same for
# `FILE_SETTLE_SECONDS`, at most `FILE_SETTLE_LIMIT_SECONDS`.
function _wait_for_settled_file(path::AbstractString)
    deadline = time() + FILE_SETTLE_LIMIT_SECONDS
    stamp = compute_file_stamp(path)
    while time() < deadline
        sleep(FILE_SETTLE_SECONDS)
        next = compute_file_stamp(path)
        next == stamp && return nothing
        stamp = next
    end
    nothing
end

"""
    compute_file_text_hash(path) -> UInt64

The hash of the text of the file at `path` on disk now, or the hash of `nothing`
when there is no file. A file document keeps the hash of the text of its last
load or save ([`FileDiskState`](@ref)) and compares it with this one, and the read
of a changed file computes it.
"""
compute_file_text_hash(path::AbstractString) = isfile(path) ? hash(read(path, String)) : hash(nothing)

# The facets of a file document, which a roster of files shows, filters and sorts
# by. The folder is the folder of the file name as the file gives it.
get_item_facets(::Type{FileDocument}) = [
    "name" => "the name of the file, without its folder",
    "folder" => "the folder of the file, as its file name gives it",
    "has_edits" => "whether the document has edits since its file was read or saved; nothing for a file " *
                   "that keeps no history",
    "state" => "the conditions of the file in words, such as \"unsaved edits\", \"changed on disk\" or " *
               "\"read only\"; empty for a file with none"]
compute_item_facet(file::FileDocument, ::Val{:name}) = basename(String(get_filename(file)))
compute_item_facet(file::FileDocument, ::Val{:folder}) = dirname(String(get_filename(file)))
compute_item_facet(file::FileDocument, ::Val{:has_edits}) = has_unsaved_edits(get_file_content(file))
compute_item_facet(file::FileDocument, ::Val{:state}) = _format_file_state(get_document_decoration(file))

# The conditions of a file in words, in the order that a tooltip says them, with
# commas between them; empty for a file with none.
_format_file_state(decoration::DocumentDecoration) =
    join((get_condition_look(Val(condition.name)).words for condition in collect_decoration_conditions(decoration)),
         ", ")

"""
    get_file_icon(path) -> Symbol

The icon of the kind of the file at `path`, by its extension: Julia code, JSON,
text and Markdown, a `.pred` document, a NED network, an INI configuration, a
`.math` formula, and `:file` for any other file.

Use it to show what kind of file a name names, as a file tree and a tab do.

# Example

    get_file_icon("notes.md")

See also `get_document_decoration`.
"""
function get_file_icon end

function get_file_icon(path::AbstractString)
    extension = lowercase(splitext(path)[2])
    extension == ".jl"            ? :lambda       :
    extension == ".json"          ? :braces       :
    extension in (".md", ".txt")  ? :pilcrow      :
    extension == ".pred"          ? :diamond      :   # a document written as its constructor
    extension == ".ned"           ? :hexagon      :   # a network: nodes and the links between them
    extension == ".ini"           ? :file_sliders :   # a configuration: lines of keys and values
    extension == ".math"          ? :sigma        :
    :file
end

# A file says the kind of its name, the edits that no save wrote, and that it
# takes no edit, with its folder as its detail. While its band shows, it says also
# that it changed on disk: a conflict when it has edits that no save wrote.
function get_document_decoration(file::FileDocument)
    name = String(get_filename(file))
    conditions = DocumentCondition[]
    has_unsaved_edits(get_file_content(file)) === true && push!(conditions, DocumentCondition(:unsaved))
    is_editable_file_type(typeof(file)) || push!(conditions, DocumentCondition(:read_only))
    if get_file_disk_state(file).band !== nothing
        is_unsaved = any(condition -> condition.name === :unsaved, conditions)
        filter!(condition -> condition.name !== :unsaved, conditions)
        push!(conditions, DocumentCondition(is_unsaved ? :conflict : :changed_on_disk))
    end
    folder = dirname(name)
    DocumentDecoration(; icon = get_file_icon(name), conditions,
                       detail = folder in ("", ".") ? "" : replace(folder, homedir() => "~"),
                       tooltip = () -> make_file_note(name; lines = _count_file_lines(file)))
end

# The lines of a file that holds plain text, and `nothing` for a file whose
# content is a document.
function _count_file_lines(file::FileDocument)
    content = get_wrapped_document(get_file_content(file))
    text = content isa PrimitiveString ? content.value : content
    text isa AbstractString || return nothing
    isempty(text) ? 0 : count(==('\n'), text) + (endswith(text, '\n') ? 0 : 1)
end

"""
    make_file_note(path; lines = nothing) -> TooltipNote

What a row of the file `path` says when the pointer rests on it: its name, its
full path, its format by its extension, and its lines when they are known. It
reads no disk.
"""
function make_file_note(path::AbstractString; lines::Union{Integer,Nothing} = nothing)
    extension = uppercase(lstrip(splitext(path)[2], '.'))
    facts = Pair{String,Any}["Path" => replace(String(path), homedir() => "~")]
    isempty(extension) || push!(facts, "Format" => extension)
    lines === nothing || push!(facts, "Lines" => string(lines))
    TooltipNote(; title = basename(path), facts)
end

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
type. It writes nothing.

Use it to compare a file document with its file on disk.

# Example

    text_1 = compute_file_text(file_1)

See also `has_unsaved_edits` and `save_file_to_disk!`.

For the assistant.
"""
function compute_file_text end

compute_file_text(file::FileDocument) =
    cut_file_text(_make_plain_file(file), dirname(abspath(get_filename(file))))
compute_file_text(file::ReferencedDocument) = compute_file_text(get_document(file))

# The text of a file is the text of what it holds, so a caller with a tab in
# hand asks the file itself. The history a file carries stays out of the answer,
# as it does for a save, and a content that is already a string is its own text.
NaturalModule.print_natural_text(file::FileDocument) =
    let content = get_wrapped_document(get_file_content(file))
        content isa AbstractString ? String(content) : print_natural_text(content)
    end

"""
    ReloadFileOperation(file; content = nothing, file_hash = nothing)

Swap the document of the file of `file` into its `content`, a reactive write, so
the projection renders it again: `content` when it is given, such as a document
that a task read off the loop with [`read_file_content_again`](@ref), or else the file read again from disk now. A
non-existent file seeds the insertion placeholder of its extension again.

In an editor, each `file("…")` of the new document gets the file document that the
editor holds for that file, else a new one that reads nothing
([`open_file_document!`](@ref)); the reload reads no held file. With no editor, each
reference stays a leaf.

The file keeps the hash of the text that it read and takes its band away.
`file_hash` is the hash that the task computed for `content`; with none, the
file on disk is hashed now ([`compute_file_text_hash`](@ref)). The file counts every
change that was reported so far as read.

A selection of the editor that names a part which the new document lacks becomes the
longest start of its path that names a part; a selection that still names a part
stays where it is. F5 answers it together with a selection of the whole file, which
every reader above makes a path from the root.

F5 answers it; code reads a file again with `reload_file_from_disk!`.

See also `SaveFileOperation` and `make_file_tab`.
"""
struct ReloadFileOperation <: Operation
    file::FileDocument
    content::Any
    file_hash::Any
end

ReloadFileOperation(file::FileDocument; content = nothing, file_hash = nothing) =
    ReloadFileOperation(file, content, file_hash)

function evaluate_operation(editor, op::ReloadFileOperation)
    file = op.file
    content = op.content === nothing ? _read_file_again(file) : op.content
    content = _splice_open_files(editor, file, content)
    # A wrapper around the content — a history — keeps its place and takes the
    # new document; a plain content is replaced outright.
    file.content = replace_wrapped_document!(get_file_content(file), content)
    open_shown_files!(editor, file)
    state = get_file_disk_state(file)
    if op.file_hash !== nothing
        state.file_hash = op.file_hash
    elseif !isempty(get_filename(file))
        state.file_hash = compute_file_text_hash(abspath(get_filename(file)))
    end
    op.content === nothing && !isempty(get_filename(file)) &&
        (state.file_stamp = compute_file_stamp(abspath(get_filename(file))))
    state.loaded_count = max(state.loaded_count, state.read_count)
    state.band = nothing
    _repair_selection!(editor)
    nothing
end

# `content`, loaded for `file`, with each `file("…")` in it given the file document
# that `editor` holds for that file, else a new one that reads nothing
# ([`open_file_document!`](@ref)). The names of the files are against the folder of
# `file`, as a save writes them. With no editor, or no name, each reference stays.
function _splice_open_files(editor, file::FileDocument, content)
    (editor isa Editor && !isempty(get_filename(file))) || return content
    splice_held_files!(content, dirname(abspath(get_filename(file))),
                       path -> open_file_document!(editor, path))
end

"""
    collect_shown_file_paths(document) -> Vector{String}

The paths that `document` writes for the files that it shows, such as the images of a
Markdown page, in the order that it writes them and as it writes them: a relative path
is against the folder of the file that holds the document. A domain adds a method for
its root document. It reads no disk. The default answers none.

Use it to name the files that a document shows, so that the file which holds it keeps
the editor's one file document of each ([`open_shown_files!`](@ref)).

# Example

    collect_shown_file_paths(markdown_root_1)    # ["images/chart.png"]

See also `find_shown_file`.
"""
function collect_shown_file_paths end

collect_shown_file_paths(document) = String[]

"""
    open_shown_files!(editor, file) -> nothing

Give `file` the file document of each path that its document shows
([`collect_shown_file_paths`](@ref)), against the folder of `file`: the one that
`editor` holds open for the path, else a new one that reads nothing
([`open_file_document!`](@ref)). They are the `shown_files` of its
[`FileDiskState`](@ref). While `file` is held, it holds the files that it shows now and
no longer those that it does not show; a path whose extension names no file type has
no file. With no editor, or no name, it does nothing. A load calls it
([`ReloadFileOperation`](@ref)), and so does the open of a file.
"""
function open_shown_files!(editor, file::FileDocument)
    (editor isa Editor && !isempty(get_filename(file))) || return nothing
    folder = dirname(abspath(get_filename(file)))
    shown = Dict{String,Any}()
    for path in collect_shown_file_paths(get_wrapped_document(get_file_content(file)))
        full_path = normpath(joinpath(folder, path))
        (haskey(shown, path) || !has_file_document_type(full_path)) && continue
        picture = open_file_document!(editor, full_path)
        picture === nothing || (shown[path] = picture)
    end
    state = get_file_disk_state(file)
    before = collect(values(state.shown_files))
    after = collect(values(shown))
    state.shown_files = shown
    released = Any[picture for picture in before if !any(other -> other === picture, after)]
    acquired = Any[picture for picture in after if !any(other -> other === picture, before)]
    (isempty(released) && isempty(acquired)) ||
        evaluate_operation(editor, ChangeHeldDocumentsOperation(file, released, acquired))
    nothing
end

"""
    find_shown_file(context, path) -> FileDocument or nothing

The file document that the file being printed keeps for `path`, a path as
[`collect_shown_file_paths`](@ref) answers it, or `nothing` when it keeps none. A printer
below [`FileToContent`](@ref) calls it inside a computation, which reads the shown files of
the file, so the print follows a load that changes them. It reads no disk.

Use it to draw a file that the document shows, such as the picture of an image.

# Example

    picture_1 = find_shown_file(context_1, "images/chart.png")
"""
function find_shown_file(context, path::AbstractString)
    shown = get_property(context, _SHOWN_FILES_PROPERTY, nothing)
    shown === nothing ? nothing : get(shown[], String(path), nothing)
end

# The selection of the editor after a load: it stays where it is, or when the new
# document lacks the part that it names, it becomes the longest start of its path that
# names a part. A selection that names no part can make a printer fail at each frame.
function _repair_selection!(editor)
    editor isa Editor || return nothing
    root = editor.document
    selection = get_selection(root)
    (selection isa ConcreteReference && !is_valid_reference(root, selection)) || return nothing
    evaluate_operation(editor, ReplaceSelectionOperation(get_valid_reference_prefix(root, selection)))
    nothing
end

"""
    KeepFileEditsOperation(file, file_hash)

Keep what `file` holds over a file that another program changed: `file_hash`, the
hash of the file on disk, becomes the hash of `file`, so the next save writes over
that file, and the band goes. "Keep mine" of the band of a change answers it. A
history inside the file adds no step for it.
"""
struct KeepFileEditsOperation <: Operation
    file::FileDocument
    file_hash::Any
end

function evaluate_operation(editor, op::KeepFileEditsOperation)
    state = get_file_disk_state(op.file)
    state.file_hash = op.file_hash
    state.band = nothing
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
    KeyDown(:f5) => "Reload file from disk" => _reload_file(doc)
end

# Each carries its own subject and names no reference, so every reader
# between the gesture and the editor passes it up unchanged.
OperationModule.is_self_contained_operation(::Union{SaveFileOperation, ReloadFileOperation,
                                                    KeepFileEditsOperation}) = true

# A save and a keep change no document that a person edits. A reload replaces the
# document and has no way back.
OperationModule.make_inverse_operation(document, ::Union{SaveFileOperation, KeepFileEditsOperation}) =
    DoNothingOperation()

# ── The keys of a file, as verbs ─────────────────────────────────────────────

"""
    save_file_to_disk!(file; editor = get_evaluation_editor()) -> Bool

Write what the open file holds to the file of its own name, as Ctrl+S does, and
answer whether it wrote. `file` is the tab of the file, as `open_file!` answers
it, or the file itself. When another program changed the file on disk since the
tab read it, nothing is written, the answer is `false`, and the tab shows a band
that asks the person what to keep. A file that a person does not edit, such as a
result file, is not written.

Use it to keep the edits of an open file on the disk.

# Example

    notes_tab_1 = open_file!("notes.json")
    save_file_to_disk!(notes_tab_1)

See also `reload_file_from_disk!`, `has_unsaved_edits`, `open_file!`.

For the assistant.
"""
function save_file_to_disk! end

save_file_to_disk!(file; editor = get_evaluation_editor()) =
    run_on_editor_task!(editor; description = "save_file_to_disk!") do
        evaluate_operation(editor, SaveFileOperation(_get_shown_file(get_document(file), "save"))) === true
    end

"""
    reload_file_from_disk!(file; editor = get_evaluation_editor()) -> file

Read the open file again from the disk, as F5 does, so it holds what the disk
holds now, and answer `file`. `file` is the tab of the file, as `open_file!`
answers it, or the file itself. The edits that were not saved are lost. A file that
is not on the disk any more holds the empty document of its extension.

Use it to see what another program wrote to an open file.

# Example

    notes_tab_1 = open_file!("notes.json")
    reload_file_from_disk!(notes_tab_1)

See also `save_file_to_disk!`, `has_unsaved_edits`, `open_file!`.

For the assistant.
"""
function reload_file_from_disk! end

function reload_file_from_disk!(file; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "reload_file_from_disk!") do
        evaluate_operation(editor, ReloadFileOperation(_get_shown_file(get_document(file), "read again")))
        file
    end
end

# The file that `document` shows: `document` itself, or the first file document on
# the walk from it through the fields that a person edits, as a tab shows its file;
# or `nothing`.
function _find_shown_file(document)
    node = document
    for _ in 1:16
        is_file_document(node) && return node
        field = get_edited_field(node)
        field === nothing && return nothing
        node = getproperty(node, field)
    end
    nothing
end

# The verbs that save and read a file again name no part that shows none.
function _get_shown_file(document, purpose::AbstractString)
    file = _find_shown_file(document)
    file === nothing && throw(ArgumentError("That part shows no file, so there is nothing to $purpose."))
    file
end

# ── A change of the file on disk ─────────────────────────────────────────────

"""
    receive_file_change!(editor, receiver) -> Bool

Tell `receiver` that its file changed on disk, and answer whether it took the
change. The drain of the file change store calls it on the editor task. The watch
that noted the change read nothing of the file and knows nothing of what the change
means: the receiver decides. A [`FileDocument`](@ref) adds one to the count of
changes in its [`FileDiskState`](@ref), and reads the file when a view of it is
drawn ([`demand_file_text`](@ref)); the answer of that read is stored by
[`ApplyFileTextOperation`](@ref). The default takes none, and so does a file with no
name.
"""
function receive_file_change! end

receive_file_change!(editor, receiver) = false

function receive_file_change!(editor, file::FileDocument)
    isempty(get_filename(file)) && return false
    state = get_file_disk_state(file)
    state.read_count += 1
    true
end

# The answer of the read of a file: the hash of its text, the new document, the time
# and the size of the file at the read, and the exception of a parse that failed. A
# file that is gone gives no hash and no document.
struct _FileTextAnswer
    file_hash::Any
    content::Any
    stamp::Any
    failure::Any
end

# The read that runs on a task after a frame, for each file that a frame asked for:
# it waits until the file is whole and reads it. It reads no document of the editor.
function _read_file_text_answer(path::String, type::Type, is_editable::Bool)
    try
        _wait_for_settled_file(path)
        stamp = compute_file_stamp(path)
        isfile(path) || return _FileTextAnswer(nothing, nothing, stamp, nothing)
        file_hash = is_editable ? compute_file_text_hash(path) : hash(stamp)
        _FileTextAnswer(file_hash, read_file_content_again(type, path), stamp, nothing)
    catch exception
        _FileTextAnswer(nothing, nothing, nothing, CapturedException(exception, catch_backtrace()))
    end
end

# The box that keeps the background cell of the text in the `text` field of a
# [`FileDiskState`](@ref): a field can not hold a cell as its value.
struct _FileTextCell
    cell::Cell
end

# The background cell of the text of `file`, with a source of its own, so the files
# of a frame read in parallel. Its inputs name the file and the count of the changes,
# so it has no answer for a count that came after the last read.
function _make_file_text_cell(file::FileDocument)
    source = BackgroundSource(inputs -> Any[_read_file_text_answer(path, type, is_editable)
                                           for (path, type, is_editable, _) in inputs];
                              description = "the text of a file")
    inputs = () -> (abspath(get_filename(file)), Base.typename(typeof(file)).wrapper,
                    is_editable_file_type(typeof(file)), get_file_disk_state(file).read_count)
    make_background_cell(source, inputs;
                         apply = (inputs, answer) -> ApplyFileTextOperation(file, last(inputs), answer))
end

"""
    ensure_file_text_cell!(file) -> nothing

Give `file` the background cell of its text, when it has none and has a name. Call it
where the file is made or enters the window, never in a print: a cell that a
computation makes is new at each run.
"""
function ensure_file_text_cell!(file::FileDocument)
    state = get_file_disk_state(file)
    (state.text !== nothing || isempty(get_filename(file))) && return nothing
    state.text = _FileTextCell(_make_file_text_cell(file))
    nothing
end

"""
    demand_file_text(file) -> nothing

Ask for the text of `file` when a change is to be read: a read of its background
cell, which records a demand, so a task reads the file after the frame. A file whose
changes are all read, and a file with no such cell, ask for nothing. A view of the
file calls it in what it draws, so a file that nothing draws reads nothing; a holder
that shows what the file says without a view, such as a count in a page, calls it too.
"""
function demand_file_text(file::FileDocument)
    state = get_file_disk_state(file)
    box = state.text
    box === nothing && return nothing
    state.read_count > state.loaded_count && box.cell[]
    nothing
end

"""
    is_file_stale(file) -> Bool

Whether the file on disk has another time or size than at the last read of `file`,
so a file that was not watched while it changed knows it. A file that knows no stamp
claims nothing.
"""
function is_file_stale(file::FileDocument)
    state = get_file_disk_state(file)
    (isempty(get_filename(file)) || state.file_stamp === nothing) && return false
    compute_file_stamp(abspath(get_filename(file))) != state.file_stamp
end

"""
    ApplyFileTextOperation(file, read_count, answer)

Store what the read of the file of `file` found for the change `read_count`. An
answer that a newer change follows is dropped. The hash of the new text equals the
hash of the file after its own save or load, and nothing happens. A file that was not
read yet, a file that a person does not edit, and a file with no edits since its
last load or save take the new document ([`ReloadFileOperation`](@ref)). A file with
edits that are not saved, or with no history that says, keeps what it holds and
shows its band: "Load it" takes the new document, and "Keep mine" keeps the edits
([`KeepFileEditsOperation`](@ref)). A read that failed logs its exception and
changes nothing.

The background cell of the text makes it. A history inside the file adds no step for
it.
"""
struct ApplyFileTextOperation <: Operation
    file::FileDocument
    read_count::Int
    answer::Any
end

OperationModule.is_self_contained_operation(::ApplyFileTextOperation) = true
OperationModule.make_inverse_operation(document, ::ApplyFileTextOperation) = DoNothingOperation()

function evaluate_operation(editor, op::ApplyFileTextOperation)
    file = op.file
    state = get_file_disk_state(file)
    op.read_count == state.read_count || return nothing
    answer = op.answer
    if !(answer isa _FileTextAnswer) || answer.failure !== nothing
        failure = answer isa _FileTextAnswer ? answer.failure : answer
        @warn string("The file ", get_document_title(file), " could not be read, so it keeps what it holds.") exception = failure
        state.loaded_count = op.read_count
        return nothing
    end
    was_unread = state.loaded_count < 0
    state.loaded_count = op.read_count
    answer.content === nothing && return nothing
    state.file_stamp = answer.stamp
    (!was_unread && answer.file_hash == state.file_hash) && return nothing
    load = ReloadFileOperation(file; content = answer.content, file_hash = answer.file_hash)
    if was_unread || !is_editable_file_type(typeof(file)) || has_unsaved_edits(get_file_content(file)) === false
        evaluate_operation(editor, load)
    else
        state.band = _make_changed_file_band(file, "Load it" => load,
                                             "Keep mine" => KeepFileEditsOperation(file, answer.file_hash))
    end
    nothing
end
