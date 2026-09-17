# Fragment of `WorkbenchModule`.
#
# Workspace → FileSystem projection. Maps workspace documents to file-system
# documents:
#
#     Workspace       → projects each WorkspaceFolder child via recursion
#     WorkspaceFolder → FileSystemDirectory (shallow, one level)
#
# The WorkspaceFolderToFileSystemDirectory projection reads the folder's
# pathname and constructs a FileSystemDirectory with one level of children.
# Deeper levels are expanded by the downstream FileSystemToSyntax projection
# when the user expands directory nodes.
# ── WorkspaceFolderToFileSystemDirectory ─────────────────────────────────────

struct WorkspaceFolderToFileSystemDirectory <: Projection end

function print_document(p::WorkspaceFolderToFileSystemDirectory,
                           recursion, folder::WorkspaceFolder, ctx)
    # Reactive output so a pathname change re-derives through the held iomap.
    SimpleIoMap(p, folder, ComputedCell(() -> make_filesystem_pathname(folder.pathname)))
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

struct WorkspaceToFileSystemDirectory <: Projection end

function print_document(p::WorkspaceToFileSystemDirectory,
                           recursion, w::Workspace, ctx)
    # Reconcile folders by identity, and forward the single-root output reactively
    # so a structural edit propagates through the held iomap (PAR-STABLE-IOMAP-IDENTITY).
    child_iomaps = reconcile_child_iomaps(
        () -> w.folders,
        (i, elem) -> print_child(recursion, elem,
            make_child_context(ctx, FieldReferenceStep("folders"), ElementReferenceStep(i))))
    # The output is the first folder's output for single-root workspaces.
    # Multi-root rendering can be refined later with a composite output.
    output = ComputedCell(() -> (ims = child_iomaps[]; isempty(ims) ? nothing : ims[1].output))
    ChildrenIoMap(p, w, output, child_iomaps)
end

function map_reference_forward(::WorkspaceToFileSystemDirectory, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkspaceToFileSystemDirectory, iomap, reference)
    return nothing
end

# Pass operations through unchanged, but decline raw gestures so the sequential
# reader's input-domain "first say" does not short-circuit with a bare event.
#
# A selection is the exception. A path from the file-system view names a node of
# the computed file-system document, not of the workspace, so it can not travel
# up as a workspace path. The reader writes it on the computed document instead,
# where the tree shows it and where Enter reads it, and it selects the workspace
# as a whole, so the window's focus moves to the navigator.
function read_intent(::WorkspaceToFileSystemDirectory, iomap, op)
    op isa Operation || return nothing
    op isa ReplaceSelectionOperation || return op
    directory = iomap.output
    directory === nothing && return nothing
    CompoundOperation(Any[
        ReplaceReferencedValueOperation(directory, "selection", op.path),
        ReplaceSelectionOperation(EmptyReference()),
    ])
end


# ── Compound constructor ─────────────────────────────────────────────────────

function WorkspaceToFileSystem()
    TypeDispatchingProjection(
        Workspace       => WorkspaceToFileSystemDirectory(),
        WorkspaceFolder => WorkspaceFolderToFileSystemDirectory(),
    )
end
