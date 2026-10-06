# Fragment of `PaneModule` — saving and opening the whole editor as one
# `.pred` file plus the files its open tabs already name.
#
# The pane reaches `document.windows` by `hasproperty` in `get_window_tree`,
# and nothing here names a screen type either: an editor with no screen (a
# headless one, holding its `PaneTree` directly) saves and opens exactly the
# same way as one with a `ScreenDocument` of windows.

"""
    save_user_interface(path; editor = get_evaluation_editor()) -> Bool

Save `editor`'s whole document — every window, pane, split and tab — to `path`
as a `.pred` file, so a person gets their windows, panes and tabs back.

Use it to save the editor's layout, the way `save_project!` saves any file
project: `path` names the `.pred` file, and every open file tab is written
beside it, each to the name it already carries.

# Example

    save_user_interface("session.pred")

See also [`load_user_interface`](@ref), `save_project!`.

An open file tab holds a [`FileDocument`](@ref) — a `JsonFile`, an `XmlFile`,
another `.pred` file — and the cut in `FileCut.jl` writes a `FileDocument`
child as `file("a.json")`, a reference rather than a copy, **only when that
file is itself one of the project's files**; a `FileDocument` reachable from
no file of the project is an orphan, and the save aborts naming it. So every
file tab reachable in the document is found with [`search_documents`](@ref)
and added to the project here, beside the `.pred` file that holds the
document itself.
"""
function save_user_interface(path::AbstractString; editor = get_evaluation_editor())
    document = getfield(editor, :document)
    directory = dirname(abspath(path))
    files = Any[PredFile(basename(path), document)]
    for file in search_documents(document, is_file_document)
        push!(files, file)
    end
    save_project!(FileProject(directory, files))
end

"""
    load_user_interface(path) -> Document

The document [`save_user_interface`](@ref) saved at `path`: every window,
pane, split and tab, with every file tab read back from the file it names.

Use it to restore an editor's layout — hand the result to the editor as its
document.

# Example

    document = load_user_interface("session.pred")

See also [`save_user_interface`](@ref), `load_project`.
"""
function load_user_interface(path::AbstractString)
    project = load_project(dirname(abspath(path)), [basename(path)]; follow = true)
    get_file_content(project.files[1])
end
