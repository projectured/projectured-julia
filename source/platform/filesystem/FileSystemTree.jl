# Fragment of `FileSystemModule` — the documents of the file system as the nodes
# of a tree: the workspace with its folders, a folder with its entries, and a file
# as a leaf. A node of a folder that opens holds the folder, so the folder reads
# on its task and is watched while its node is open.

get_tree_children_steps(::Workspace) = ((FieldReferenceStep("folders"),),)
format_tree_node_label(::Workspace) = "Files"

get_tree_children_steps(::WorkspaceFolder) = ((FieldReferenceStep("directory"), FieldReferenceStep("elements")),)
format_tree_node_label(folder::WorkspaceFolder) = folder.name
# A folder of a workspace is a root: no read of a parent says whether it is
# empty, so it shows a chevron until its own read finds it empty.
has_tree_children(folder::WorkspaceFolder) = has_folder_entries(folder.directory) !== false

# A folder of a workspace holds the folder that it names, so the open of its node
# reads that folder.
acquire_document!(editor, folder::WorkspaceFolder) = hold_documents!(editor, folder, Any[folder.directory])
release_document!(editor, folder::WorkspaceFolder) = release_held_documents!(editor, folder, Any[folder.directory])

get_tree_children_steps(::FileSystemDirectory) = ((FieldReferenceStep("elements"),),)
format_tree_node_label(folder::FileSystemDirectory) = basename(rstrip(folder.pathname, '/'))
has_tree_children(folder::FileSystemDirectory) = has_folder_entries(folder)

format_tree_node_label(file::FileSystemFile) = basename(file.pathname)
has_tree_children(::FileSystemFile) = false
