function make_navigator_document_example(; root=abspath(joinpath(@__DIR__, "../..")))
    Workspace([
        WorkspaceFolder(basename(root), root),
    ])
end
