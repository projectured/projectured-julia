# Fragment of `FileSystemModule` — the workspace document types: the abstract
# `WorkspaceDocument`, and the folder and file nodes a workspace tree holds.

abstract type WorkspaceDocument <: Document end

# ── WorkspaceFolder ──────────────────────────────────────────────────────────

@document struct WorkspaceFolder <: WorkspaceDocument
    name::String
    pathname::String
end

# Neither field has a default, so the macro gives the bare name no keyword
# constructor — `pred_arguments` always writes a document's fields as
# keywords, so the file format needs this one.
make_pred_document(::Type{WorkspaceFolder}, positional, keywords) =
    isempty(positional) ?
        WorkspaceFolder(Dict(keywords)[:name], Dict(keywords)[:pathname]) :
        WorkspaceFolder(positional...)


# ── Workspace ────────────────────────────────────────────────────────────────

@document struct Workspace <: WorkspaceDocument
    folders::CellVector = CellVector()
end

# The name the tab calls itself, and the names a person types into an empty
# tab to open one.
get_document_title(::Workspace) = "Explorer"
get_insertion_aliases(::Type{Workspace}) = ["explorer", "file explorer"]

# `Workspace()` holds no folder, and an empty explorer shows nothing — so a
# person who opens one by typing its name gets the working directory instead.
make_insertion_document(::Type{Workspace}) = Workspace([WorkspaceFolder(basename(pwd()), pwd())])
