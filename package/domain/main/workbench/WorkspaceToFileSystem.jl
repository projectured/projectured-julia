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

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, print_child, read_intent,
                               map_reference_forward, map_reference_backward, Projection
import ..OperationApiModule: Operation
import ..WorkspaceModule: WorkspaceDocument, Workspace, WorkspaceFolder
import ..FileSystemModule: FileSystemDocument, FileSystemFile, FileSystemDirectory, make_filesystem_pathname
import ..IoMapModule: SimpleIoMap, ChildrenIoMap, reconcile_child_iomaps
import ..IoMapModule: IoMap
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, FieldReferenceStep
import ..PrinterContextModule: make_child_context
export WorkspaceFolderToFileSystemDirectory, WorkspaceToFileSystem

# ── WorkspaceFolderToFileSystemDirectory ─────────────────────────────────────

struct WorkspaceFolderToFileSystemDirectory <: Projection end

function print_document(p::WorkspaceFolderToFileSystemDirectory,
                           recursion, folder::WorkspaceFolder, ctx)
    # Reactive output so a pathname change re-derives through the held iomap.
    SimpleIoMap(p, folder, Cell(() -> make_filesystem_pathname(folder.pathname)))
end

function map_reference_forward(::WorkspaceFolderToFileSystemDirectory, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkspaceFolderToFileSystemDirectory, iomap, reference)
    return nothing
end

# Identity on references: this projection renames no reference steps, so an
# operation threaded back from below passes through unchanged. But it must NOT
# pass a *raw gesture* through as if it were an operation — the ChainingProjection
# reader gives the input-domain stage first say on the bare gesture, and returning
# the gesture there would short-circuit the whole read with a non-operation
# "operation" (the navigator's clicks/hover/collapse all die that way). Decline
# anything that is not an Operation so the normal output→input threading runs.
function read_intent(::WorkspaceFolderToFileSystemDirectory, iomap, op)
    op isa Operation ? op : nothing
end

# ── WorkspaceWorkspaceToSyntax (projects children via recursion) ─────────────

struct WorkspaceWorkspaceProjection <: Projection end

function print_document(p::WorkspaceWorkspaceProjection,
                           recursion, w::Workspace, ctx)
    # Reconcile folders by identity, and forward the single-root output reactively
    # so a structural edit propagates through the held iomap (AR-STABLE-IOMAP-IDENTITY).
    child_iomaps = reconcile_child_iomaps(
        () -> w.folders,
        (i, elem) -> print_child(recursion, elem,
            make_child_context(ctx, FieldReferenceStep("folders"), ElementReferenceStep(i))))
    # The output is the first folder's output for single-root workspaces.
    # Multi-root rendering can be refined later with a composite output.
    output = Cell(() -> (ims = child_iomaps[]; isempty(ims) ? nothing : ims[1].output))
    ChildrenIoMap(p, w, output, child_iomaps)
end

function map_reference_forward(::WorkspaceWorkspaceProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkspaceWorkspaceProjection, iomap, reference)
    return nothing
end

# Identity on references (see WorkspaceFolderToFileSystemDirectory above): pass
# operations through unchanged, but decline raw gestures so the sequential
# reader's input-domain "first say" does not short-circuit with a bare event.
function read_intent(::WorkspaceWorkspaceProjection, iomap, op)
    op isa Operation ? op : nothing
end


# ── Compound constructor ─────────────────────────────────────────────────────

function WorkspaceToFileSystem()
    TypeDispatchingProjection(
        Workspace       => WorkspaceWorkspaceProjection(),
        WorkspaceFolder => WorkspaceFolderToFileSystemDirectory(),
    )
end

end # module
