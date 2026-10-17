# Fragment of `FileSystemModule` — the workspace document types: the abstract
# `WorkspaceDocument`, and the folder and file nodes a workspace tree holds.

abstract type WorkspaceDocument <: Document end

# A workspace names the folders a person opened, so its duplicate is a copy of
# them. The selected row and the closed folders belong to the view, not to the
# workspace, so a duplicate opens with no row selected and every folder open.
has_document_duplicate(::WorkspaceDocument) = true

# ── WorkspaceFolder ──────────────────────────────────────────────────────────

"""
    WorkspaceFolder(name, pathname)

A folder that a [`Workspace`](@ref) holds. `name` is the text that the explorer
shows, and `pathname` is the place of the folder on the disk. `directory` is the
document of the folder, made unread with it, which holds what the reads of the
folder found; every explorer of the workspace shows that one document.

Use it to add a folder to the explorer.

# Example

    folder_1 = WorkspaceFolder("data", "/home/person/data")
    workspace_1 = Workspace([folder_1])

See also `Workspace` and `OpenFileOperation`.
"""
@document struct WorkspaceFolder <: WorkspaceDocument
    name::String
    pathname::String
    directory::Any                    # the FileSystemDirectory of the folder
end

# The folder of a workspace is a folder also when nothing is at its place yet, so
# its read says that it can not read it.
WorkspaceFolder(name::AbstractString, pathname::AbstractString) =
    WorkspaceFolder(name, pathname, FileSystemDirectory(String(pathname), CellVector(), :unread))

# A file keeps the name and the place of a folder, and not what a read found.
pred_arguments(folder::WorkspaceFolder) = (), Pair{Symbol,Any}[:name => folder.name, :pathname => folder.pathname]

make_pred_document(::Type{WorkspaceFolder}, positional, keywords) =
    isempty(positional) ?
        WorkspaceFolder(Dict(keywords)[:name], Dict(keywords)[:pathname]) :
        WorkspaceFolder(positional...)


# ── Workspace ────────────────────────────────────────────────────────────────

"""
    Workspace(folders = CellVector())

The document of the explorer: the folders that a person opened, each a
[`WorkspaceFolder`](@ref). The explorer shows each folder as a tree of its
sub-folders and its files.

Use it to show the files of a folder in a tab.

# Example

    workspace_1 = Workspace([WorkspaceFolder("data", "/home/person/data")])
    open_pane!(workspace_1; title = "Explorer")

See also `WorkspaceFolder` and `make_file_tab_content`.
"""
@document struct Workspace <: WorkspaceDocument
    folders::CellVector = CellVector()
end

# The name the tab calls itself.
get_document_title(::Workspace) = "Explorer"

# A file opens beside the explorer it was found in, never over it.
accepts_opened_file(::Workspace) = false

# ── WorkspaceExplorer ────────────────────────────────────────────────────────

"""
    WorkspaceExplorer(workspace)

What a person sees of a [`Workspace`](@ref) in a tab: its folders as a tree, with
open folders of its own. Two explorers of one workspace share what the folders
read, and each opens its own folders.

`open` holds the open folders, by their documents; the folder of each
`WorkspaceFolder` is open at the start. It is view state, so undo records no open
or closed folder, and a file keeps the workspace and no open folder. The explorer
holds its open folders, so each one reads and watches itself while the explorer
is shown, and a folder that is open in two explorers is read once. A duplicate
shares the workspace and copies the open folders.

Use it to show the files of a workspace in a tab.

# Example

    explorer_1 = WorkspaceExplorer(Workspace([WorkspaceFolder("data", "/home/person/data")]))
    open_pane!(explorer_1; title = "Files")

See also `Workspace` and `WorkspaceFolder`.
"""
@document struct WorkspaceExplorer <: WorkspaceDocument
    workspace::Any                    # Workspace
    open::IdDict{Any,Nothing}
end

WorkspaceExplorer(workspace::Workspace) =
    WorkspaceExplorer(workspace, IdDict{Any,Nothing}(folder.directory => nothing for folder in workspace.folders))

get_document_title(::WorkspaceExplorer) = "Explorer"

# The names a person types into an empty tab to open the tree of the files. A tree
# of no folder shows nothing, so a person who opens one by its name gets the
# working directory.
get_insertion_aliases(::Type{WorkspaceExplorer}) = ["files", "file explorer"]
make_insertion_document(::Type{WorkspaceExplorer}) =
    WorkspaceExplorer(Workspace([WorkspaceFolder(basename(pwd()), pwd())]))

# A file opens beside the explorer it was found in, never over it.
accepts_opened_file(::WorkspaceExplorer) = false

acquire_document!(editor, explorer::WorkspaceExplorer) = hold_documents!(editor, explorer, collect(keys(explorer.open)))

release_document!(editor, explorer::WorkspaceExplorer) =
    release_held_documents!(editor, explorer, collect(keys(explorer.open)))

copy_document(::DuplicatePolicy, explorer::WorkspaceExplorer) =
    WorkspaceExplorer(explorer.workspace, copy(explorer.open))

pred_arguments(explorer::WorkspaceExplorer) = (explorer.workspace,), Pair{Symbol,Any}[]
make_pred_document(::Type{WorkspaceExplorer}, positional, keywords) = WorkspaceExplorer(only(positional))

get_document_decoration(::Union{Workspace, WorkspaceExplorer}) = DocumentDecoration(; icon = :files)
get_document_decoration(folder::WorkspaceFolder) = get_document_decoration(folder.directory)
