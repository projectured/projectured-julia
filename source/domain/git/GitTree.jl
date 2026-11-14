# Fragment of `GitModule` — the tree of the changed files of a commit: a folder as a
# node, a changed file as a leaf, and the top node, which the page of the commit
# shows beside the diffs.

"""
    GitChangedFolder

A folder of the changed files of a commit, a node of the tree of its page. `path`
is its path from the top folder of the repository, `""` for that folder. `name` is
its label: its name, or the joined path of a chain of folders that each hold one
folder and no file, or the path of the top node. `children` holds the folders under
it, then its changed files, each a [`GitFileChange`](@ref), each in the order of
their names. `added_count` and `removed_count` are the sums of the lines of the
files under it.
"""
@document struct GitChangedFolder <: Document
    path::String
    name::String
    children::Any
    added_count::Int
    removed_count::Int
end

# The folders and the files below one folder, as the build of a tree collects them.
struct _FolderEntries
    folders::Dict{String,_FolderEntries}
    files::Vector{Any}
end

_FolderEntries() = _FolderEntries(Dict{String,_FolderEntries}(), Any[])

# The path under which the tree puts a change: the new path, and the old path of a
# deleted file.
_get_change_tree_path(change) = something(change.new_path, change.old_path)

# The top node of the tree of `changes`, the changes of a commit in the repository in
# the folder `repository`: the deepest folder that holds every changed file. When
# the files are in more than one folder at the top of the repository, or at its top,
# it is the folder of the repository, named by the name of its folder.
function _make_changed_folder(changes, repository::AbstractString)
    root = _FolderEntries()
    for change in changes
        parts = split(_get_change_tree_path(change), '/')
        entries = root
        for part in parts[1:(end - 1)]
            entries = get!(_FolderEntries, entries.folders, String(part))
        end
        push!(entries.files, change)
    end
    path = String[]
    entries = root
    while isempty(entries.files) && length(entries.folders) == 1
        (name, inner) = only(entries.folders)
        push!(path, name)
        entries = inner
    end
    top = isempty(path) ? basename(rstrip(repository, '/')) : join(path, '/')
    _make_folder_node(join(path, '/'), top, entries)
end

# The node of the folder at `path` with the label `name`, whose entries are
# `entries`: each folder under it joins the chain of folders that each hold one
# folder and no file.
function _make_folder_node(path::String, name::String, entries::_FolderEntries)
    children = Any[]
    for folder in sort!(collect(keys(entries.folders)))
        inner = entries.folders[folder]
        label = folder
        while isempty(inner.files) && length(inner.folders) == 1
            (next, deeper) = only(inner.folders)
            label = string(label, '/', next)
            inner = deeper
        end
        push!(children, _make_folder_node(isempty(path) ? label : string(path, '/', label), label, inner))
    end
    append!(children, sort(entries.files; by = change -> basename(_get_change_tree_path(change))))
    added = sum(child -> child.added_count, children; init = 0)
    removed = sum(child -> child.removed_count, children; init = 0)
    GitChangedFolder(path, name, CellVector(children), added, removed)
end

# The changes under a node of the tree, in the order of the tree.
_collect_node_changes(change::GitFileChange) = Any[change]
_collect_node_changes(folder::GitChangedFolder) =
    reduce(vcat, (_collect_node_changes(child) for child in folder.children); init = Any[])

# A node of the tree: a folder has its children, and a change is a leaf. Its line is
# its name and the counts of its lines, and the icon of a change is its kind.
get_tree_children_steps(::GitChangedFolder) = ((FieldReferenceStep("children"),),)

format_tree_node_label(folder::GitChangedFolder) =
    string(folder.name, "  ", _format_change_counts(folder.added_count, folder.removed_count, false))

format_tree_node_label(change::GitFileChange) =
    string(_format_change_name(change), "  ",
           _format_change_counts(change.added_count, change.removed_count, change.is_binary))

# The name of a change in its folder: the name of its file, and for a rename or a copy
# the old name in the same folder, or the old path from another folder.
function _format_change_name(change::GitFileChange)
    name = basename(_get_change_tree_path(change))
    change.kind in (:renamed, :copied) || return name
    old = change.old_path
    dirname(old) == dirname(change.new_path) ? string(basename(old), " → ", name) : string(name, " ← ", old)
end

get_document_decoration(::GitChangedFolder) = DocumentDecoration(; icon = :folder)
get_document_decoration(change::GitFileChange) =
    DocumentDecoration(; icon = change.kind === :added ? :file_plus : change.kind === :deleted ? :file_minus : :file_diff)
