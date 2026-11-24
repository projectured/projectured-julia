# Fragment of `FileSystemModule` — a chooser drawn as the tree it looks in and
# the name a person types.
#
# The tree is the tree of an explorer: the folders as the chooser holds them open,
# with the rows, the chevrons and the reading row of the Files tab. The name is a
# `WidgetText` whose text is the name of the chooser, and an edit of the field is
# an edit of the name. **A row of a file types its path from the directory into
# the field**, so a person may press a file or type a name, and the chooser says
# one path either way.

"""
    FileSystemChooserToWidget(; position = Point2D(0, 0), gap)

Draw a [`FileSystemChooser`](@ref): the tree of its directory, open where the
chooser holds its folders open, and the field of its name under it. A chevron
opens or closes a folder and changes what the chooser holds, so a folder that
opens reads; a double press, or Return, on a file writes its path from the
directory of the chooser into the field, so a file in an open folder names the
folder too.

    children[1].roots[1].children[a]…   directory.elements[a]…
    children[2].content<rest>           name<rest>

The tree and the field stand `gap` apart: the `section_gap` of the widget theme.
"""
@projection UntrackedCell struct FileSystemChooserToWidget <: Projection
    position::Point2D = Point2D(0, 0)
    gap::Int = get_widget_style(nothing, :section_gap)
end

const _CHOOSER_FIELD_WIDTH = 240

function print_document(p::FileSystemChooserToWidget, recursion,
                        chooser::FileSystemChooser, ctx)
    # A row names a file, and naming a file is what typing the name does, so the
    # row writes the path of the file from the directory of the chooser rather
    # than opening anything. A file in an open folder writes the folder too. The
    # chooser chooses; it does not act.
    write_name = path -> WriteChosenNameOperation(chooser, relpath(path, chooser.directory.pathname))
    roots = CellVector(@computation Any[_fs_node(chooser.directory, write_name)])
    expanded = Cell(@computation _compute_open_folder_paths(Any[chooser.directory], chooser.open))
    tree_paths = make_output_path_cells(chooser, path -> _map_chooser_tree_part(p, path))
    tree = WidgetTree(Cell(Point2D(0, 0)), roots, Cell(true),
                      Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                      expanded,
                      Cell(GestureBinding[]), Cell(Point2D(0, 0)), Cell(:auto), Cell(:auto),
                      Cell(nothing), Cell(nothing), Cell(Set{Vector{Int}}()), Cell(nothing),
                      tree_paths.selection, tree_paths.mouse_target)
    field = WidgetText(""; width = _CHOOSER_FIELD_WIDTH)
    set_cell_computation!(getfield(field, :content), () -> String(chooser.name))
    set_output_path_computations!(field, chooser, path -> _map_chooser_field_path(path))
    layout = GridLayout(Any[tree, field], 1; column_policy = Fill, row_policies = Any[Fill, Content],
                        vertical_gap = p.gap)
    iomap = SimpleIoMap(p, chooser, layout)
    set_output_path_computations!(layout, chooser, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# The node of the tree that a path of the chooser names: `directory.elements[a]…`
# is `roots[1].children[a]…`.
function _map_chooser_tree_path(reference)
    reference isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    steps[1] == FieldReferenceStep("directory") || return nothing
    indices = _fs_ref_indices(extend_reference(EmptyReference(), steps[2:end]...))
    indices === nothing ? nothing : _tree_build(vcat(1, indices), 1)
end

# The place in the field that a path of the chooser names: `name<rest>` is
# `content<rest>`.
function _map_chooser_field_path(reference)
    reference isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    steps[1] == FieldReferenceStep("name") || return nothing
    extend_reference(EmptyReference(), FieldReferenceStep("content"), steps[2:end]...)
end

_make_chooser_child_path(k, rest) =
    concat_references(extend_reference(EmptyReference(), FieldReferenceStep("children"), RangeReferenceStep(k - 1, k)),
                      rest)

# The place in the tree that a path of the chooser names: the node of a file, and a
# part that the view drew in the row of a file, which is the path of the file and
# then the step of the view, that part in the node of the file.
_map_chooser_tree_part(p::FileSystemChooserToWidget, reference) =
    something(_map_row_part_forward(p, reference, _map_chooser_tree_path, 2), Some(_map_chooser_tree_path(reference)))

function map_reference_forward(p::FileSystemChooserToWidget, iomap, reference)
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return something(introduced)
    tree_path = _map_chooser_tree_part(p, reference)
    tree_path === nothing || return _make_chooser_child_path(1, tree_path)
    field_path = _map_chooser_field_path(reference)
    field_path === nothing ? nothing : _make_chooser_child_path(2, field_path)
end

# A node of the tree is the path of its entry in the directory, a part in the row
# of a node, as its label, that path and then the step of the view, a place in the
# field the same place in the name, and any other part of the view, such as a
# scroll bar of the tree, a part that the view drew.
function map_reference_backward(p::FileSystemChooserToWidget, iomap::SimpleIoMap, reference)
    reference isa ConcreteReference || return nothing
    path = strip_reference_types(reference)
    steps = collect(get_reference_steps(path))
    is_child(k) = length(steps) >= 2 && steps[1] == FieldReferenceStep("children") &&
                  steps[2] isa RangeReferenceStep && steps[2].start + 1 == k
    if is_child(2) && length(steps) >= 3 && steps[3] == FieldReferenceStep("content")
        return extend_reference(EmptyReference(), FieldReferenceStep("name"), steps[4:end]...)
    end
    if is_child(1)
        rest = steps[3:end]
        count = _count_tree_node_steps(rest)
        indices = _tree_ref_path_indices(extend_reference(EmptyReference(), rest[1:count]...))
        if indices !== nothing && indices[1] == 1
            file = concat_references(extend_reference(EmptyReference(), FieldReferenceStep("directory")),
                                     _fs_ref_from_indices(indices[2:end]))
            return count == length(rest) ? file : _make_row_part_reference(p, iomap, file, path)
        end
    end
    make_introduced_reference(p, iomap, path)
end

# A chevron writes the open folders of the chooser and changes what it holds;
# every other answer maps back as through any projection.
function map_operation_backward(p::FileSystemChooserToWidget, iomap::SimpleIoMap, operation)
    chooser = iomap.input
    read = _read_open_folder_write(chooser, Any[chooser.directory], nothing, operation)
    _map_open_folder_answer(p, iomap, operation, read)
end

# The renderer draws a chooser with this view and draws the layout of the view
# with its children, each of which is a widget.
make_graphics_projection(::Type{<:FileSystemChooser}; measure, appearance) =
    ChainingProjection(FileSystemChooserToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
                       GridLayoutToGraphicsCanvas())

"""
    WriteChosenNameOperation(chooser, name)

Put `name` in the chooser's name field. It is what a row of the tree answers: a
row names a file, and this is the chooser's way of holding a name.
"""
struct WriteChosenNameOperation <: Operation
    chooser::FileSystemChooser
    name::String
end

WriteChosenNameOperation(chooser::FileSystemChooser, name::AbstractString) =
    WriteChosenNameOperation(chooser, String(name))

OperationModule.is_self_contained_operation(::WriteChosenNameOperation) = true

function evaluate_operation(editor, operation::WriteChosenNameOperation)
    operation.chooser.name = operation.name
    nothing
end
