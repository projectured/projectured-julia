"""
    WorkspaceModule

The workspace document domain. A workspace groups one or more named folder
roots (WorkspaceFolder) into a single container (Workspace). Each folder
carries a display name and a filesystem pathname; the actual directory
contents are produced by projection (WorkspaceFolderToFileSystemDirectory),
not stored in the document.
"""
module WorkspaceModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export WorkspaceDocument, WorkspaceFolder, Workspace,
       IWorkspaceFolder, IWorkspace

abstract type WorkspaceDocument <: Document end

# ── WorkspaceFolder ──────────────────────────────────────────────────────────

@document struct WorkspaceFolder <: WorkspaceDocument
    name::String
    pathname::String
    selection::Reference
end

WorkspaceFolder(name::AbstractString, pathname::AbstractString) =
    WorkspaceFolder(Cell(String(name)), Cell(String(pathname)), Cell(nothing))

# ── Workspace ────────────────────────────────────────────────────────────────

@document struct Workspace <: WorkspaceDocument
    folders::CellVector
    selection::Reference
end

Workspace(folders::Vector{WorkspaceFolder}) =
    Workspace(CellVector(Cell[Cell(f) for f in folders]), Cell(nothing))

Workspace() = Workspace(WorkspaceFolder[])

# ── Children access ──────────────────────────────────────────────────────────

Base.length(w::Workspace)               = length(w.folders)
Base.isempty(w::Workspace)              = isempty(w.folders)
Base.getindex(w::Workspace, i::Integer) = w.folders[i]
Base.firstindex(::Workspace)            = 1
Base.lastindex(w::Workspace)            = length(w)
Base.iterate(w::Workspace, state...)    = iterate(w.folders, state...)
Base.eachindex(w::Workspace)            = eachindex(w.folders)

end # module
