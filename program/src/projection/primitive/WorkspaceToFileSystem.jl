"""
    WorkspaceToFileSystemModule

Workspace → FileSystem projection. Maps workspace documents to file-system
documents:

    Workspace       → projects each WorkspaceFolder child via recursion
    WorkspaceFolder → FileSystemDirectory (shallow, one level)

The WorkspaceFolderToFileSystemDirectory projection reads the folder's
pathname and constructs a FileSystemDirectory with one level of children.
Deeper levels are expanded by the downstream FileSystemToSyntax projection
when the user expands directory nodes.
"""
module WorkspaceToFileSystemModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read,
                               map_reference_forward, map_reference_backward, Projection
import ..WorkspaceModule: WorkspaceDocument, Workspace, WorkspaceFolder
import ..FileSystemModule: FileSystemDocument, FileSystemFile, FileSystemDirectory, make_filesystem_pathname
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..ReferenceModule: ConcreteReferencePath, ElementReference, FieldReference
import ..ProjectionContextModule: child_context
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem

# ── WorkspaceFolderToFileSystemDirectory ─────────────────────────────────────

struct WorkspaceFolderToFileSystemDirectory <: Projection end

function projection_print(p::WorkspaceFolderToFileSystemDirectory,
                           folder::WorkspaceFolder, recursion, ctx)
    dir = make_filesystem_pathname(folder.pathname)
    SimpleIoMap(p, folder, dir)
end

function map_reference_forward(::WorkspaceFolderToFileSystemDirectory, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkspaceFolderToFileSystemDirectory, iomap, reference)
    return nothing
end

function projection_read(::WorkspaceFolderToFileSystemDirectory, iomap, op)
    op
end

# ── WorkspaceWorkspaceToSyntax (projects children via recursion) ─────────────

struct WorkspaceWorkspaceProjection <: Projection end

function projection_print(p::WorkspaceWorkspaceProjection,
                           w::Workspace, recursion, ctx)
    child_iomaps = [projection_print(recursion, elem, recursion,
                                   child_context(ctx, FieldReference("folders"), ElementReference(i)))
                    for (i, elem) in enumerate(w)]
    # The output is the first folder's output for single-root workspaces.
    # Multi-root rendering can be refined later with a composite output.
    output = isempty(child_iomaps) ? nothing : child_iomaps[1].output
    ChildrenIoMap(p, w, output, Cell(child_iomaps))
end

function map_reference_forward(::WorkspaceWorkspaceProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkspaceWorkspaceProjection, iomap, reference)
    return nothing
end

function projection_read(::WorkspaceWorkspaceProjection, iomap, op)
    op
end


# ── Compound constructor ─────────────────────────────────────────────────────

function WorkspaceToFileSystem()
    TypeDispatchingProjection(
        Workspace       => WorkspaceWorkspaceProjection(),
        WorkspaceFolder => WorkspaceFolderToFileSystemDirectory(),
    )
end

end # module
