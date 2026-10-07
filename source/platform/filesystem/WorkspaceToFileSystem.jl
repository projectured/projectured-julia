# Fragment of `FileSystemModule`.
#
# Workspace → FileSystem projection. Maps workspace documents to file-system
# documents:
#
#     Workspace       → the output of its first folder
#     WorkspaceFolder → FileSystemDirectory, read from the folder's pathname
#
# A folder holds a name and a path, and the tree below it is computed from the
# path. So a node of the tree is a place that the projection introduces, and a
# selection of one is a `ProjectionReferenceStep` on the folder:
#
#     .folders[1].proj(<WorkspaceFolderToFileSystemDirectory>, .elements[2].elements[1])
#
# The root of the tree is the folder itself, so the folder as a whole is the root
# row. The selection of the computed directory is the image of the folder's
# selection, and no reader writes it.
# ── WorkspaceFolderToFileSystemDirectory ─────────────────────────────────────

struct WorkspaceFolderToFileSystemDirectory <: Projection end

function print_document(p::WorkspaceFolderToFileSystemDirectory,
                           recursion, folder::WorkspaceFolder, ctx)
    # Reactive output so a pathname change re-derives through the held iomap. The
    # paths (the selection, the mouse target) are computed on their first read, so
    # this computation depends on the pathname alone, and a path that moves reads
    # the disk again never.
    SimpleIoMap(p, folder, Cell(@computation begin
        directory = make_filesystem_pathname(folder.pathname)
        set_output_path_computations!(directory, folder, path -> map_reference_forward(p, nothing, path))
        directory
    end))
end

# The reference maps are the defaults of `Projection`: a path in the tree maps
# back to `proj(p, path)` on the folder, and forward by unwrapping it; `∅` maps to
# `∅` both ways.

# A path from the tree maps back onto the folder, also each path in a compound.
# Anything else that is an operation passes as it is, but a raw gesture does not:
# the ChainingProjection reader gives the input-domain stage first say on the
# bare gesture, and returning the gesture there would short-circuit the whole
# read with a non-operation "operation".
function read_intent(p::WorkspaceFolderToFileSystemDirectory, iomap, op)
    op isa Operation || return nothing
    op isa CompoundOperation && return _read_compound_answer(o -> read_intent(p, iomap, o), op)
    op isa ReplacePathOperation || return op
    path = map_reference_backward(p, iomap, get_operation_path(op))
    path === nothing ? nothing : make_path_operation(op, path)
end

# A compound maps member by member, as the default reader of a projection maps
# it: the answer to a move keeps each member that maps, and any other compound,
# such as the start of a drag with its writes, goes back whole or not at all.
function _read_compound_answer(read_member, operation::CompoundOperation)
    mapped = Any[read_member(o) for o in operation.operations]
    has_mouse_target(operation) && return join_move_answers(mapped...)
    any(isnothing, mapped) && return nothing
    CompoundOperation(mapped)
end

# ── WorkspaceToFileSystemDirectory (projects children via recursion) ─────────

struct WorkspaceToFileSystemDirectory <: Projection end

function print_document(p::WorkspaceToFileSystemDirectory,
                           recursion, w::Workspace, ctx)
    # Reconcile folders by identity, and forward the single-root output reactively
    # so a structural edit propagates through the held iomap (PAR-STABLE-IOMAP-IDENTITY).
    child_iomaps = make_reconciled_child_iomaps_cell(
        () -> w.folders,
        (i, elem) -> print_child(recursion, elem,
            make_child_context(ctx, FieldReferenceStep("folders"), ElementReferenceStep(i))))
    # The output is the first folder's output for single-root workspaces.
    # Multi-root rendering can be refined later with a composite output.
    output = Cell(@computation (ims = child_iomaps[]; isempty(ims) ? nothing : ims[1].output))
    ChildrenIoMap(p, w, output, child_iomaps)
end

# `.folders[1].rest` maps forward through the first folder, which is the one the
# view shows. The workspace as a whole maps to nothing: the pane that holds it
# draws that selection, and no row of the tree stands for it.
function map_reference_forward(::WorkspaceToFileSystemDirectory, iomap, reference)
    @reference_case reference begin
        ::Workspace.folders{s:e}.rest... => begin
            s == 0 || return nothing
            iomaps = iomap.child_iomaps
            isempty(iomaps) && return nothing
            child = iomaps[1]
            map_reference_forward(child.projection, child, rest)
        end
    end
end

# A path in the output is a path in the first folder's output.
function map_reference_backward(::WorkspaceToFileSystemDirectory, iomap, reference)
    reference === nothing && return nothing
    iomaps = iomap.child_iomaps
    isempty(iomaps) && return nothing
    child = iomaps[1]
    inner = map_reference_backward(child.projection, child, reference)
    inner === nothing && return nothing
    @reference ::Workspace.folders::CellVector[1].^(inner)
end

# A path from the view (the selection, or any other kind) maps back onto the workspace,
# also each path in a compound. Anything else that is an operation passes as it is,
# and a raw gesture is declined, as for a folder.
function read_intent(p::WorkspaceToFileSystemDirectory, iomap, op)
    op isa Operation || return nothing
    op isa CompoundOperation && return _read_compound_answer(o -> read_intent(p, iomap, o), op)
    op isa ReplacePathOperation || return op
    path = map_reference_backward(p, iomap, get_operation_path(op))
    path === nothing ? nothing : make_path_operation(op, path)
end

# An Alt+press selects the workspace as a whole. The row under the pointer is a
# place the projection introduced, and the rule for such a place selects the
# folder it was printed for; but the folder draws as the whole view, so the
# workspace, whose page shows the selection, is the object a person selects.
function read_intent(p::WorkspaceToFileSystemDirectory, recursion, change::Intent, iomap)
    is_whole_selection_press(change.gesture) &&
        return Intent(change.gesture, ReplaceSelectionOperation(EmptyReference()))
    payload = change.operation === nothing ? change.gesture : change.operation
    Intent(change.gesture, read_intent(p, iomap, payload))
end


# ── Compound constructor ─────────────────────────────────────────────────────

function WorkspaceToFileSystem()
    TypeDispatchingProjection(
        Workspace       => WorkspaceToFileSystemDirectory(),
        WorkspaceFolder => WorkspaceFolderToFileSystemDirectory(),
    )
end
