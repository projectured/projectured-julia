"""
    WorkspaceModule

The workspace document domain. A workspace groups one or more named folder
roots (WorkspaceFolder) into a single container (Workspace). Each folder
carries a display name and a filesystem pathname; the actual directory
contents are produced by projection (WorkspaceFolderToFileSystemDirectory),
not stored in the document.
"""
module WorkspaceModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export WorkspaceDocument

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
    folders::CellVector = CellVector()
    selection::Reference = nothing
end

Workspace(folders::Vector{WorkspaceFolder}) =
    Workspace(CellVector(Cell[Cell(f) for f in folders]), Cell(nothing))

end # module
