# The Files pane over the file-system fixture. It shares the fixture with the
# file-system examples rather than pointing at a source directory of its own: a
# workspace folder is a real path, and a path inside the repository makes the
# example change whenever the repository does.

make_files_document_example(; root = filesystem_example_root()) =
    Workspace([
        make_workspace_folder_document_example(; root),
    ])

# Atomic documents for the catalog. An example shows its folder with no editor, so
# the folder reads the whole fixture at once, which no print does.
function make_workspace_folder_document_example(; root = filesystem_example_root())
    folder = WorkspaceFolder(basename(root), root)
    read_filesystem_folder!(folder.directory; depth = typemax(Int))
    folder
end
make_workspace_document_example() = Workspace([make_workspace_folder_document_example()])
