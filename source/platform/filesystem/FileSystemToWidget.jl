# Fragment of `FileSystemModule`.
#
# FileSystem → WidgetDocument projection. Maps a whole file-system tree to a single
# [`WidgetTree`](@ref) inside a [`WidgetScrollPane`](@ref): the root directory
# becomes the one root node, each directory/file below it a nested
# [`WidgetTreeNode`](@ref) carrying a **dedicated icon** (an extension-derived
# glyph) plus its basename as the **text** label.
#
#     FileSystemDirectory → WidgetTreeNode(folder-icon, dirname, [child nodes…])
#     FileSystemFile      → WidgetTreeNode(type-icon,   filename)
#
# The tree scrolls itself when it is taller than the slot that it is given. A tab
# puts nothing around what it holds, so the view scrolls itself.
#
# Selection maps in lockstep with the node layout: the root node is path `roots[1]`
# (file-system reference `∅`), and a node at file-system reference
# `elements[a].elements[b]…` is the tree node `roots[1].children[a].children[b]…`.
# The two reference mappers are that path. The printer wires the tree's own
# selection with the node path alone.
# ── Projection ────────────────────────────────────────────────────────────────

"""
    FileSystemToWidgetTree(position = Point2D(0, 0); open_file = OpenFileOperation)

The file-system view. `open_file` is a function that takes the absolute path of
a file and returns the operation that opens it, or `nothing` to disable
opening. Enter on the selected file and a double click on a file row call it
and return that operation. The view does not open anything itself: the editor
evaluates the operation, so the view stays free of side effects.

The default is `OpenFileOperation`, which names the file and nothing about
where it goes. A caller that knows the destination (the pane tree, a specific
pane) passes its own operation instead.
"""
struct FileSystemToWidgetTree <: Projection
    position::Point2D
    open_file::Any
end
# @optional: the position stands first, as the content of the view; the rest is
# its chrome.
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

# The node of an entry: a file, or a folder with its rows. A folder answers from
# what it holds whether it has rows, so a closed row reads nothing of it; a folder
# that reads shows its chevron too.
_fs_node(f::FileSystemFile, open_file; label = basename(f.pathname)) =
    WidgetTreeNode(_fs_icon(f), label; gestures = _make_open_file_bindings(f.pathname, open_file))
function _fs_node(d::FileSystemDirectory, open_file; label = _dir_name(d.pathname))
    rows = CellVector(@computation(1:_count_folder_rows(d)); element = i -> _make_folder_row(d, i, open_file))
    WidgetTreeNode(_fs_icon(d), label, rows;
                   has_children = () -> has_folder_entries(d) === true || d.state === :reading)
end

# The rows under a folder: its entries, or one row that says that it reads, or
# that it can not be read.
_count_folder_rows(d::FileSystemDirectory) =
    (n = length(d.elements); n > 0 || d.state === :read ? n : 1)

function _make_folder_row(d::FileSystemDirectory, i, open_file)
    i <= length(d.elements) && return _fs_node(d.elements[i], open_file)
    d.state === :failed && return WidgetTreeNode(:warning, "can not read: " * _format_read_failure(d.failure))
    WidgetTreeNode(:loader, "reading")
end

_format_read_failure(failure) = first(split(sprint(showerror, failure), '\n'))

# The two gestures that open a file: Enter while its row is selected, and a
# double click on its row. A first click still selects the row, because only a
# press with a count of two matches.
_make_open_file_bindings(pathname, ::Nothing) = GestureBinding[]
function _make_open_file_bindings(pathname, open_file)
    make_operation = (node, event) -> open_file(pathname)
    is_applicable = (node, selection) -> true
    GestureBinding[
        GestureBinding(KeyPressPattern('\n'), make_operation;
                       applicable = is_applicable, description = "Open the file",
                       domain = "file system"),
        GestureBinding(MouseClickPattern(:left; guard = event -> event.count == 2, label = "double click"),
                       make_operation; applicable = is_applicable,
                       description = "Open the file", domain = "file system"),
    ]
end


# ── Printer ───────────────────────────────────────────────────────────────────

function print_document(p::FileSystemToWidgetTree, recursion, doc::FileSystemDocument, ctx)
    # The tree's paths (its selection, its mouse target) are the forward images of
    # the document's: a node path, or a part that the view drew.
    paths = make_output_path_cells(doc, path -> map_reference_forward(p, nothing, path))
    # The roots are a reactive thunk so structural file-system changes rebuild the
    # node tree without re-running `print_document`.
    roots = CellVector(@computation Any[_fs_node(doc, p.open_file)])
    # Positional, so every declared field is named here in order and the paths
    # come last: position, roots, visible, margin, border, padding, style,
    # expanded, gestures, scroll_position, vertical_scroll_bar,
    # horizontal_scroll_bar, tooltip, anchor, selection, mouse target. The root row is
    # open, and each folder under it is closed until a person opens it. The tree
    # scrolls itself in the slot that its parent offers.
    tree = WidgetTree(Cell(p.position), roots, Cell(true),
                      Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                      Cell(Set([[1]])),
                      Cell(GestureBinding[]), Cell(Point2D(0, 0)), Cell(:auto), Cell(:auto),
                      Cell(nothing), Cell(nothing), paths.selection, paths.mouse_target)
    SimpleIoMap(p, doc, tree)
end

# ── The tree of an explorer ───────────────────────────────────────────────────

# A workspace explorer is a tree with a root for each folder of its workspace,
# named as the folder; its open folders are the folders that the explorer holds
# open, by their documents, so a new entry above an open folder keeps that folder
# open. A chevron writes the open folders of the explorer and changes what it
# holds, so a folder that opens reads and watches itself.
function print_document(p::FileSystemToWidgetTree, recursion, explorer::WorkspaceExplorer, ctx)
    paths = make_output_path_cells(explorer, path -> _map_explorer_path_forward(p, path))
    roots = CellVector(@computation Any[_fs_node(folder.directory, p.open_file; label = folder.name)
                                        for folder in explorer.workspace.folders])
    expanded = Cell(@computation _compute_open_folder_paths(_get_explorer_folders(explorer), explorer.open))
    tree = WidgetTree(Cell(p.position), roots, Cell(true),
                      Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                      expanded,
                      Cell(GestureBinding[]), Cell(Point2D(0, 0)), Cell(:auto), Cell(:auto),
                      Cell(nothing), Cell(nothing), paths.selection, paths.mouse_target)
    SimpleIoMap(p, explorer, tree)
end

_get_explorer_folders(explorer::WorkspaceExplorer) = Any[folder.directory for folder in explorer.workspace.folders]

# The open folders as paths of the widget: a root at its place, and an open
# folder under an open folder at its place among the rows. A folder under a closed
# folder is not open.
function _compute_open_folder_paths(folders::Vector, open)
    paths = Set{Vector{Int}}()
    for (k, folder) in enumerate(folders)
        _collect_open_folder_paths!(paths, folder, [k], open)
    end
    paths
end

function _collect_open_folder_paths!(paths, folder, path, open)
    (folder isa FileSystemDirectory && haskey(open, folder)) || return nothing
    push!(paths, path)
    for (i, entry) in enumerate(folder.elements)
        _collect_open_folder_paths!(paths, entry, vcat(path, i), open)
    end
    nothing
end

# The document at a path of the widget: a root, then an entry of each folder on
# the way; `nothing` for a row that names no entry, such as the reading row.
function _find_folder_entry(folders::Vector, path::Vector{Int})
    1 <= path[1] <= length(folders) || return nothing
    entry = folders[path[1]]
    for i in path[2:end]
        (entry isa FileSystemDirectory && 1 <= i <= length(entry.elements)) || return nothing
        entry = entry.elements[i]
    end
    entry
end

# The answer to a write of the open nodes of the widget: the write of the open
# folders of `holder` and the change of what it holds, together as view state, so
# undo records neither. `widget` is the tree whose write it takes, or `nothing`
# for the one tree of a view that draws only one. `nothing` for any other answer.
function _read_open_folder_write(holder, folders::Vector, widget, operation)
    operation isa ReplaceViewStateOperation || return nothing
    write = get_wrapped_operation(operation)
    write isa ReplaceReferencedValueOperation || return nothing
    (widget === nothing ? write.document isa WidgetTree : write.document === widget) || return nothing
    steps = get_reference_steps(strip_reference_types(write.reference))
    (length(steps) == 1 && steps[1] == FieldReferenceStep("expanded")) || return nothing
    open = IdDict{Any,Nothing}()
    for path in write.value
        entry = _find_folder_entry(folders, path)
        entry isa FileSystemDirectory && (open[entry] = nothing)
    end
    before = holder.open
    opened = Any[folder for folder in keys(open) if !haskey(before, folder)]
    closed = Any[folder for folder in keys(before) if !haskey(open, folder)]
    open_write = ReplaceReferencedValueOperation(holder, "open", open)
    isempty(opened) && isempty(closed) && return ReplaceViewStateOperation(open_write)
    ReplaceViewStateOperation(CompoundOperation(Any[open_write, ChangeHeldDocumentsOperation(holder, closed, opened)]))
end

function read_intent(p::FileSystemToWidgetTree, recursion, change::Intent, iomap::SimpleIoMap)
    (change.route === nothing && iomap.input isa WorkspaceExplorer) ||
        return invoke(read_intent, Tuple{Projection,Any,Intent,Any}, p, recursion, change, iomap)
    payload = change.operation === nothing ? change.gesture : change.operation
    answer = _read_open_folder_write(iomap.input, _get_explorer_folders(iomap.input), iomap.output, payload)
    answer === nothing && (answer = invoke(read_intent, Tuple{Projection,Any,Any}, p, iomap, payload))
    Intent(change.gesture, answer, change.description, change.domain)
end

# The path of the explorer `workspace.folders[k].directory.elements[a]…` is the
# node `roots[k].children[a]…`; `workspace.folders[k]` is its root too.
function _map_explorer_path_forward(p::FileSystemToWidgetTree, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return something(introduced)
    reference isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    (length(steps) >= 3 && steps[1] == FieldReferenceStep("workspace") && steps[2] == FieldReferenceStep("folders") &&
     steps[3] isa RangeReferenceStep && is_element_reference_step(steps[3])) || return nothing
    length(steps) == 3 && return _tree_build([steps[3].start + 1], 1)
    steps[4] == FieldReferenceStep("directory") || return nothing
    indices = _fs_ref_indices(extend_reference(EmptyReference(), steps[5:end]...))
    indices === nothing ? nothing : _tree_build(vcat(steps[3].start + 1, indices), 1)
end

# A node `roots[k].children[a]…` of the widget is the path
# `workspace.folders[k].directory.elements[a]…` of the explorer.
function _map_explorer_path_backward(p::FileSystemToWidgetTree, iomap, reference)
    indices = _tree_ref_path_indices(reference)
    indices === nothing && return make_introduced_reference(p, iomap, strip_reference_types(reference))
    concat_references(extend_reference(EmptyReference(), FieldReferenceStep("workspace"), FieldReferenceStep("folders"),
                                       RangeReferenceStep(indices[1] - 1, indices[1]), FieldReferenceStep("directory")),
                      _fs_ref_from_indices(indices[2:end]))
end

# ── Reference mapping (file-system ⇄ WidgetTree node-path) ─────────────────────

# Forward: a file-system selection (`elements[a].elements[b]…` or `∅`) → the tree
# node `roots[1].children[a].children[b]…`. A part that the view drew, such as the
# tree itself or its bar, is the path in the tree that its introduced reference
# holds.
map_reference_forward(p::FileSystemToWidgetTree, iomap, reference) =
    iomap isa SimpleIoMap && iomap.input isa WorkspaceExplorer ? _map_explorer_path_forward(p, reference) :
    something(find_introduced_path(p, reference), Some(_map_tree_reference_forward(reference)))

# Backward: a node path of the tree (`roots[1].children[a].children[b]…`) → the
# file-system reference `elements[a].elements[b]…` (or `∅` for the root node). Any
# other part of the tree, the tree itself as well, is a part that the view drew:
# an introduced reference names it. The empty path of the file system names the
# folder, whose row is the root row, so the tree itself needs the reference of a
# part of the view.
function map_reference_backward(p::FileSystemToWidgetTree, iomap::SimpleIoMap, reference)
    reference isa Reference || return nothing
    iomap.input isa WorkspaceExplorer && return _map_explorer_path_backward(p, iomap, reference)
    idxs = _tree_ref_indices(reference)
    idxs === nothing && return make_introduced_reference(p, iomap, strip_reference_types(reference))
    _fs_ref_from_indices(idxs)
end

# The tree node `roots[1].children[a]…` of a file-system reference, or nothing on
# an unexpected shape.
function _map_tree_reference_forward(reference)
    idxs = _fs_ref_indices(reference)
    idxs === nothing && return nothing
    _tree_ref_from_indices(idxs)
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

# Decode `roots[k].children[a].children[b]…` into the indices [k, a, b, …], or
# nothing on an unexpected shape.
function _tree_ref_path_indices(reference)
    reference isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    (length(steps) >= 2 && iseven(length(steps)) && steps[1] == FieldReferenceStep("roots")) || return nothing
    indices = Int[]
    for k in 1:2:length(steps)
        steps[k] == FieldReferenceStep(k == 1 ? "roots" : "children") || return nothing
        (steps[k + 1] isa RangeReferenceStep && is_element_reference_step(steps[k + 1])) || return nothing
        push!(indices, steps[k + 1].start + 1)
    end
    indices
end

# ── Factory ───────────────────────────────────────────────────────────────────

"""
    FileSystemToWidget(; open_file = OpenFileOperation)

Projection mapping a file-system document to a single [`WidgetTree`](@ref) with a
dedicated icon + text per item. Wrap in `RecursiveProjection` at the call site.
`open_file` is as in [`FileSystemToWidgetTree`](@ref).
"""
FileSystemToWidget(; open_file = OpenFileOperation) = FileSystemToWidgetTree(; open_file = open_file)
