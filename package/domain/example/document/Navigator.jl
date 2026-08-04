function make_navigator_document_example(; root=abspath(joinpath(@__DIR__, "..")))
    Workspace([
        WorkspaceFolder(basename(root), root),
    ])
end

# Atomic documents for the catalog.
make_workspace_folder_document_example(; root=abspath(joinpath(@__DIR__, ".."))) =
    WorkspaceFolder(basename(root), root)
make_workspace_document_example() = Workspace([make_workspace_folder_document_example()])
