"""
    WorkspaceModule

The workspace document domain. A workspace groups one or more named folder
roots (WorkspaceFolder) into a single container (Workspace). Each folder
carries a display name and a filesystem pathname; the actual directory
contents are produced by projection (WorkspaceFolderToFileSystemDirectory),
not stored in the document.
"""
module WorkspaceModule

import ..CellModule: Cell, ComputedCell
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
end


# ── Workspace ────────────────────────────────────────────────────────────────

@document struct Workspace <: WorkspaceDocument
    folders::CellVector = CellVector()
end


end # module
