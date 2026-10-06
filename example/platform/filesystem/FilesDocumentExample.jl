# The Files pane over the file-system fixture. It shares the fixture with the
# file-system examples rather than pointing at a source directory of its own: a
# workspace folder is a real path, and a path inside the repository makes the
# example change whenever the repository does.

make_files_document_example(; root = filesystem_example_root()) =
    Workspace([
        WorkspaceFolder(basename(root), root),
    ])

# Atomic documents for the catalog.
make_workspace_folder_document_example(; root = filesystem_example_root()) =
    WorkspaceFolder(basename(root), root)
make_workspace_document_example() = Workspace([make_workspace_folder_document_example()])
