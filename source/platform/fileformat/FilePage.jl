# Fragment of `FileFormatModule` — the page of a file in a tab: the file in its
# scroll pane, and a band above it while the file and its copy on disk disagree.
# The band is a document of the page, and each of its buttons answers an
# operation.

"""
    FilePage(content)
    FilePage(; content, band = nothing, file_hash = nothing)

What a tab shows for a file: `content`, the file in its scroll pane, and `band`,
a [`FileBand`](@ref) that stands above the content, or `nothing`. The band stays
at the top of the tab while a long file scrolls. `file_hash` is the hash of the
text of the file on disk at the last load or save of the page
([`compute_file_text_hash`](@ref)), or `nothing` when the page does not know it.

The page holds the state of its file against the disk, and the watcher of the
file knows nothing of it. A save of the page checks the disk first
([`SaveFilePageOperation`](@ref)), and the page shows the band when a save would
write over a newer file, and when the file changed on disk under edits that are
not saved.

A walk from the tab reaches the file through `content` (`get_edited_field`),
and the tab takes its title from the file. [`make_file_tab_content`](@ref) makes
the page of a file.

# Example

    page = make_file_page(WidgetScrollPane(make_file_tab("notes.txt")))
"""
@document struct FilePage
    content::Any
    band::Any = nothing
    file_hash::Any = nothing
end

get_edited_field(::FilePage) = :content
get_document_title(page::FilePage) = get_document_title(page.content)

# A page says what its file says, and while its band shows, that the file changed
# on disk: a conflict when the file has edits that no save wrote.
function get_document_decoration(page::FilePage)
    file = find_page_file(page)
    base = get_document_decoration(file === nothing ? page.content : file)
    page.band === nothing && return base
    unsaved = any(condition -> condition.name === :unsaved, base.conditions)
    conditions = DocumentCondition[condition for condition in base.conditions if condition.name !== :unsaved]
    push!(conditions, DocumentCondition(unsaved ? :conflict : :changed_on_disk))
    DocumentDecoration(; icon = base.icon, conditions, counts = base.counts, detail = base.detail,
                       tooltip = base.tooltip, work_item = base.work_item)
end

"""
    find_page_file(page) -> FileDocument or nothing

The file document that `page` shows: the first file document on the walk from its
content through the fields that a person edits, or `nothing`.
"""
function find_page_file(page::FilePage)
    node = page.content
    for _ in 1:16
        is_file_document(node) && return node
        field = get_edited_field(node)
        field === nothing && return nothing
        node = getproperty(node, field)
    end
    nothing
end

"""
    FileBand(; message, choices = Pair{String,Any}[])

A band above a file: `message`, one sentence, and `choices`, each the label of a
button and the operation that a click on it answers. A [`FilePage`](@ref) holds
it, and `FilePageToWidget` draws it.

# Example

    FileBand(; message = "notes.txt changed on disk.",
               choices = ["Load it" => load, "Keep mine" => keep])
"""
@document struct FileBand
    message::String = ""
    choices::Any = Pair{String,Any}[]
end

"""
    make_file_page(content) -> FilePage

The page of `content`, a file in its scroll pane, with the hash of the text of its
file on disk now, as the file was just read. A file that a person does not edit
is not read for a hash: a save never writes it, and its file can be large.
"""
function make_file_page(content)
    page = FilePage(content)
    file = find_page_file(page)
    (file === nothing || isempty(get_filename(file)) || !is_editable_file_type(typeof(file))) ||
        (page.file_hash = compute_file_text_hash(abspath(get_filename(file))))
    page
end

# ── The page against its file on disk ────────────────────────────────────────

"""
    SaveFilePageOperation(page; force = false)

Write the file of `page`, as [`SaveFileOperation`](@ref) writes it, when the file
on disk still holds the text of the last load or save of the page, and keep the
hash of the text that it wrote. When another program changed the file since, the
page shows its band and nothing is written: "Load it" reads the file, and "Keep
mine" answers this save with `force = true`, which writes with no check. A page
that knows no hash writes with no check too.

The reader of the page answers it in place of a `SaveFileOperation` of its own
file, so `Ctrl+S` in a page checks the disk first. A history above the page adds
no step for it, because it changes no document.
"""
struct SaveFilePageOperation <: Operation
    page::FilePage
    force::Bool
end

SaveFilePageOperation(page::FilePage; force::Bool = false) = SaveFilePageOperation(page, force)

"""
    LoadFilePageOperation(page; content = nothing, file_hash = nothing)

Read the file of `page` into it again, as [`ReloadFileOperation`](@ref) does, keep
the hash of the text that it read, and take the band away. `content` and
`file_hash` are a document and its hash that a watcher of the file already read;
with none, the file is read now.

The reader of the page answers it in place of a `ReloadFileOperation` of its own
file that carries no document, so `Ctrl+O` in a page keeps the hash too.
"""
struct LoadFilePageOperation <: Operation
    page::FilePage
    content::Any
    file_hash::Any
end

LoadFilePageOperation(page::FilePage; content = nothing, file_hash = nothing) =
    LoadFilePageOperation(page, content, file_hash)

"""
    KeepFilePageEditsOperation(page, file_hash)

Keep what `page` holds over a file that another program changed: `file_hash`, the
hash of the file on disk, becomes the hash of the page, so the next save writes
over that file, and the band goes. "Keep mine" of the band of a change answers
it. A history above the page adds no step for it.
"""
struct KeepFilePageEditsOperation <: Operation
    page::FilePage
    file_hash::Any
end

# Each carries its page and names no reference, so every reader between the band
# or the file and the editor passes it up unchanged.
OperationModule.is_self_contained_operation(::Union{SaveFilePageOperation, LoadFilePageOperation,
                                                    KeepFilePageEditsOperation}) = true

# A save and a keep change no document that a person edits. A load replaces the
# document, as a reload does, and has no way back.
OperationModule.make_inverse_operation(document, ::Union{SaveFilePageOperation,
                                                         KeepFilePageEditsOperation}) =
    DoNothingOperation()

function evaluate_operation(editor, op::SaveFilePageOperation)
    page = op.page
    file = find_page_file(page)
    (file === nothing || isempty(get_filename(file)) || !is_editable_file_type(typeof(file))) &&
        return nothing
    if !op.force && page.file_hash !== nothing &&
       compute_file_text_hash(abspath(get_filename(file))) != page.file_hash
        page.band = _make_changed_file_band(file, "Load it" => LoadFilePageOperation(page),
                                            "Keep mine" => SaveFilePageOperation(page; force = true))
        return false
    end
    text = _write_file_text!(file)
    text === nothing && return false
    page.file_hash = hash(text)
    page.band = nothing
    true
end

function evaluate_operation(editor, op::LoadFilePageOperation)
    page = op.page
    file = find_page_file(page)
    file === nothing && return nothing
    file_hash = op.file_hash === nothing ? compute_file_text_hash(abspath(get_filename(file))) : op.file_hash
    evaluate_operation(editor, ReloadFileOperation(file; content = op.content))
    page.file_hash = file_hash
    page.band = nothing
    nothing
end

function evaluate_operation(editor, op::KeepFilePageEditsOperation)
    op.page.file_hash = op.file_hash
    op.page.band = nothing
    nothing
end

# ── A change of the file on disk ─────────────────────────────────────────────

"""
    receive_file_change!(editor, receiver, file_hash, content) -> Bool

Tell `receiver` that its file changed on disk, and answer whether it took the new
document. `file_hash` is the hash that the watcher of the file read
([`compute_file_text_hash`](@ref) for a file that a person edits), and `content`
the document that it parsed. The watcher calls it and knows nothing of what the
change means: the receiver decides.

- A [`FilePage`](@ref) whose hash is `file_hash` holds that text already, after
  its own save or load, and nothing happens. A file that a person does not edit,
  or one with no edits since its last load or save, takes the new document. A
  file with edits that are not saved, or with no history that says, keeps what
  it holds, and the page shows its band: "Load it" takes the new document, and
  "Keep mine" keeps the edits.
- A file document with no page takes the new document when a person does not
  edit its type. Otherwise it can not tell its own save from a change of another
  program, so it keeps what it holds, and the log says that its file changed.
"""
function receive_file_change! end

function receive_file_change!(editor, page::FilePage, file_hash, content)
    file = find_page_file(page)
    (file === nothing || file_hash == page.file_hash) && return false
    load = LoadFilePageOperation(page; content, file_hash)
    if !is_editable_file_type(typeof(file)) || has_unsaved_edits(get_file_content(file)) === false
        evaluate_operation(editor, load)
        return true
    end
    page.band = _make_changed_file_band(file, "Load it" => load,
                                        "Keep mine" => KeepFilePageEditsOperation(page, file_hash))
    false
end

function receive_file_change!(editor, file::FileDocument, file_hash, content)
    if !is_editable_file_type(typeof(file))
        evaluate_operation(editor, ReloadFileOperation(file; content))
        return true
    end
    @warn string(get_document_title(file), " changed on disk, and its tab keeps what it shows: a file ",
                 "with no page can not tell its own save from a change. Ctrl+O reads the file again.")
    false
end

# The band that says that the file of a page changed on disk, with its two choices.
_make_changed_file_band(file, load, keep) =
    FileBand(; message = string(get_document_title(file), " changed on disk."),
               choices = Pair{String,Any}[load, keep])
