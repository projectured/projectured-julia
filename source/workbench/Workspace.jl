# Fragment of `WorkbenchModule` — the workspace document types: the abstract
# `WorkspaceDocument`, and the folder and file nodes a workspace tree holds.

abstract type WorkspaceDocument <: Document end

# ── WorkspaceFolder ──────────────────────────────────────────────────────────

@document struct WorkspaceFolder <: WorkspaceDocument
    name::String
    pathname::String
end


# ── Workspace ────────────────────────────────────────────────────────────────

@document struct Workspace <: WorkspaceDocument
    folders::CellVector = CellVector()
end
