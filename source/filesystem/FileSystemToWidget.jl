# Fragment of `FileSystemModule`.
#
# FileSystem → WidgetDocument projection. Maps a whole file-system tree to a single
# [`WidgetTree`](@ref): the root directory becomes the one root node, each
# directory/file below it a nested [`WidgetTreeNode`](@ref) carrying a **dedicated
# icon** (an extension-derived glyph) plus its basename as the **text** label.
#
#     FileSystemDirectory → WidgetTreeNode(folder-icon, dirname, [child nodes…])
#     FileSystemFile      → WidgetTreeNode(type-icon,   filename)
#
# Selection maps in lockstep with the node layout: the root node is path `roots[1]`
# (file-system reference `∅`), and a node at file-system reference
# `elements[a].elements[b]…` is the tree node `roots[1].children[a].children[b]…`.
# The two reference mappers encode that correspondence and are the single source of
# truth reused by the printer's selection wiring and the generic reader.
# ── Projection ────────────────────────────────────────────────────────────────

"""
    FileSystemToWidgetTree(position = Point2D(0, 0); open_file = OpenFileOperation)

The file-system view. `open_file` is a function that takes the absolute path of
a file and returns the operation that opens it, or `nothing` to disable
opening. Enter on the selected file and a double click on a file row call it
and return that operation. The view does not open anything itself: the editor
evaluates the operation, so the view stays free of side effects.

The default is `OpenFileOperation`, the intent this slice declares — it names
the file and nothing about where it goes. A caller that knows the destination
(the pane tree, a specific pane) passes its own operation instead.
"""
struct FileSystemToWidgetTree <: Projection
    position::Point2D
    open_file::Any
end
FileSystemToWidgetTree(position::Point2D = Point2D(0, 0); open_file = OpenFileOperation) =
    FileSystemToWidgetTree(position, open_file)

# ── Node construction (icon + text per item) ──────────────────────────────────

# The icon of an item: a folder, or the kind of a file by its extension. Each is
# an icon name of the widget layer, so the tree draws it as the glyph of the icon
# font that the rest of the window uses.
_fs_icon(::FileSystemDirectory) = :folder
function _fs_icon(f::FileSystemFile)
    ext = lowercase(splitext(f.pathname)[2])
    ext == ".jl"            ? :lambda       :
    ext == ".json"          ? :braces       :
    ext in (".md", ".txt")  ? :pilcrow      :
    ext == ".pred"          ? :diamond      :   # a document written as its constructor
    ext == ".ned"           ? :hexagon      :   # a network: nodes and the links between them
    ext == ".ini"           ? :file_sliders :   # a configuration: lines of keys and values
    ext == ".math"          ? :sigma        :
    :file
end

_fs_node(f::FileSystemFile, open_file) =
    WidgetTreeNode(_fs_icon(f), basename(f.pathname);
                   gestures = _make_open_file_bindings(f.pathname, open_file))
function _fs_node(d::FileSystemDirectory, open_file)
    children = Any[_fs_node(c, open_file) for c in d.elements]
    WidgetTreeNode(_fs_icon(d), _dir_name(d.pathname), children)
end

# The two gestures that open a file: Enter while its row is selected, and a
# double click on its row. A first click still selects the row, because only a
# press with a count of two matches.
_make_open_file_bindings(pathname, ::Nothing) = GestureBinding[]
function _make_open_file_bindings(pathname, open_file)
    make_operation = (node, event) -> open_file(pathname)
    is_applicable = (node, selection) -> true
    GestureBinding[
        GestureBinding(KeyDownPattern(:return, nothing, nothing),
                       make_operation, is_applicable, "Open the file", "file system"),
        GestureBinding(MousePressPattern(:left, nothing, event -> event.count == 2,
                                         "double click"),
                       make_operation, is_applicable, "Open the file", "file system"),
    ]
end


# ── Printer ───────────────────────────────────────────────────────────────────

function print_document(p::FileSystemToWidgetTree, recursion, doc::FileSystemDocument, ctx)
    # Wire the tree's selection forward from the document selection through this
    # projection's own forward map (deferred-iomap trick, as in FileSystemToSyntax).
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    # The roots are a reactive thunk so structural file-system changes rebuild the
    # node tree without re-running `print_document`.
    roots = ComputedCellVector(() -> Any[_fs_node(doc, p.open_file)])
    # Positional, so every declared field is named here in order and the
    # selection comes last: position, roots, visible, margin, border, padding,
    # style, hovered, collapsed, gestures, tooltip, selection.
    tree = WidgetTree(Cell(p.position), roots, Cell(true),
                      Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                      Cell(nothing), Cell(Set{Vector{Int}}()),
                      Cell(GestureBinding[]), Cell(nothing), sel)
    iomap = SimpleIoMap(p, doc, tree)
    iomap_cell[] = iomap
    return iomap
end

# ── Reference mapping (file-system ⇄ WidgetTree node-path) ─────────────────────

# Forward: a file-system selection (`elements[a].elements[b]…` or `∅`) → the tree
# node `roots[1].children[a].children[b]…`.
function map_reference_forward(p::FileSystemToWidgetTree, iomap::SimpleIoMap, reference)
    idxs = _fs_ref_indices(reference)
    idxs === nothing && return nothing
    _tree_ref_from_indices(idxs)
end

# Backward: a tree node-path (`roots[1].children[a].children[b]…`) → the
# file-system reference `elements[a].elements[b]…` (or `∅` for the root node).
function map_reference_backward(p::FileSystemToWidgetTree, iomap::SimpleIoMap, reference)
    idxs = _tree_ref_indices(reference)
    idxs === nothing && return nothing
    _fs_ref_from_indices(idxs)
end

# Decode a file-system reference into a list of element indices ([] = root, the
# directory itself), or nothing on an unexpected shape.
function _fs_ref_indices(reference)
    cur = reference
    idxs = Int[]
    while !(cur isa EmptyReference)
        cur isa ConcreteReference || return nothing
        h = cur.head
        (h isa FieldReferenceStep && h.name == "elements") || return nothing
        t = cur.tail
        (t isa ConcreteReference && t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
        push!(idxs, t.head.start + 1)
        cur = t.tail
    end
    idxs
end

# Build `elements[a].elements[b]…` (empty list → `∅`, the root directory).
_fs_ref_from_indices(idxs::Vector{Int}) = isempty(idxs) ? EmptyReference() : _fs_build(idxs, 1)
function _fs_build(idxs::Vector{Int}, k::Int)
    tail = k == length(idxs) ? EmptyReference() : _fs_build(idxs, k + 1)
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(RangeReferenceStep(idxs[k] - 1, idxs[k]), tail))
end

# Build `roots[1].children[a].children[b]…` from element indices.
function _tree_ref_from_indices(idxs::Vector{Int})
    path = vcat(1, idxs)               # leading 1 = the single root node
    _tree_build(path, 1)
end
function _tree_build(path::Vector{Int}, k::Int)
    field = k == 1 ? "roots" : "children"
    tail = k == length(path) ? EmptyReference() : _tree_build(path, k + 1)
    ConcreteReference(FieldReferenceStep(field),
        ConcreteReference(RangeReferenceStep(path[k] - 1, path[k]), tail))
end

# Decode `roots[1].children[a].children[b]…` into the element indices [a, b, …]
# ([] = the root node), or nothing on an unexpected shape.
function _tree_ref_indices(reference)
    cur = reference
    cur isa ConcreteReference || return nothing
    (cur.head isa FieldReferenceStep && cur.head.name == "roots") || return nothing
    t = cur.tail
    (t isa ConcreteReference && t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
    (t.head.start + 1 == 1) || return nothing      # only one root node
    cur = t.tail
    idxs = Int[]
    while !(cur isa EmptyReference)
        cur isa ConcreteReference || return nothing
        (cur.head isa FieldReferenceStep && cur.head.name == "children") || return nothing
        t = cur.tail
        (t isa ConcreteReference && t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
        push!(idxs, t.head.start + 1)
        cur = t.tail
    end
    idxs
end

# ── Factory ───────────────────────────────────────────────────────────────────

"""
    FileSystemToWidget(; open_file = OpenFileOperation)

Projection mapping a file-system document to a single [`WidgetTree`](@ref) with a
dedicated icon + text per item. Wrap in `RecursiveProjection` at the call site.
`open_file` is as in [`FileSystemToWidgetTree`](@ref).
"""
FileSystemToWidget(; open_file = OpenFileOperation) = FileSystemToWidgetTree(; open_file = open_file)
