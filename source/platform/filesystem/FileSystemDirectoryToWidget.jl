# Fragment of `FileSystemModule` — the page of a folder: a line that says where it
# is and how far its read is, and a table of its entries, each a link to its page.
# The page shows the folder as its last read found it, and reads no disk.

"""
    FileSystemDirectoryToWidget(; gap)

Draw a [`FileSystemDirectory`](@ref), or the folder of a `WorkspaceFolder`, as its page: a line with its path and the
state of its read, and a table of its entries with their kind. The name of each
entry is a link: a press opens its page in the navigator around the page, and
Ctrl+press opens it in a new tab. With an offered height the table makes the rows
that its viewport reaches, so a folder of thousands of entries costs what a small
one costs.
"""
@projection UntrackedCell struct FileSystemDirectoryToWidget <: Projection
    gap::Int = get_widget_style(nothing, :label_gap)
end

print_document(p::FileSystemDirectoryToWidget, recursion, folder::FileSystemDirectory, context) =
    _print_folder_page(p, folder, folder, (), context)

# A folder of a workspace shows its folder, and its links name the entries from it.
print_document(p::FileSystemDirectoryToWidget, recursion, folder::WorkspaceFolder, context) =
    _print_folder_page(p, folder, folder.directory, (FieldReferenceStep("directory"),), context)

# The page of `directory` as `owner` shows it: a link names an entry by `steps`
# from `owner`, then its place among the entries. A folder of a workspace with no
# place asks for its place first.
function _print_folder_page(p::FileSystemDirectoryToWidget, owner, directory::FileSystemDirectory, steps::Tuple,
                            context)
    bounded = context !== nothing && get_exact_height(context) !== nothing
    heading = WidgetLabel(() -> _format_folder_heading(directory))
    table = LayoutConstraint(_build_folder_table(owner, directory, steps, bounded);
                             width = Fill, height = bounded ? Fill : Content)
    root = VerticalLayout(Any[heading, table]; horizontal_align = :left, gap = p.gap)
    if owner isa WorkspaceFolder
        asked = _build_place_widgets(owner)
        set_cell_computation!(getfield(root.children, :elements), () ->
            Cell[Cell(widget) for widget in (_has_folder_place(owner) ? Any[heading, table] : asked)])
    end
    iomap = ChildrenIoMap(p, owner, root, Cell(Any[]))
    # The part under the pointer, so a link lights and takes a press. A folder of a
    # workspace gives the page its selection too, so a key goes to the field of the
    # place that holds the caret.
    owner isa WorkspaceFolder ?
        set_output_path_computations!(root, owner, path -> map_reference_forward(p, iomap, path); dormant = false) :
        follow_output_mouse_target!(root, () ->
            map_mouse_target_forward(owner, path -> map_reference_forward(p, iomap, path)))
    iomap
end

# The widgets that ask for the place of `folder`: a line that says so, the field of
# the place, the third child of the page, and Open. Return in the field opens too.
function _build_place_widgets(folder::WorkspaceFolder)
    field = WidgetText(""; width = _PLACE_FIELD_WIDTH, placeholder = "/home/person/data")
    set_cell_computation!(getfield(field, :content), () -> String(folder.pathname))
    set_output_path_computations!(field, folder, path -> _map_place_field_path(path))
    button = WidgetButton("Open"; gestures = GestureBinding[
        GestureBinding(MouseClickPattern(:left), (_, _) -> _make_folder_place_operation(folder);
                       description = "Open the folder at this place", domain = "filesystem")])
    Any[WidgetLabel("The place of the folder on the disk:"), field, button]
end

const _PLACE_FIELD_WIDTH = 320
const _PLACE_FIELD_INDEX = 2

# The place in the field of the place that a path of the folder names:
# `pathname<rest>` is `content<rest>`.
function _map_place_field_path(reference)
    reference isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    steps[1] == FieldReferenceStep("pathname") || return nothing
    extend_reference(EmptyReference(), FieldReferenceStep("content"), steps[2:end]...)
end

# While a folder of a workspace has no place, its `pathname` is the text of the
# field of the place, so the caret and a key in the field are the caret and an
# edit of the place. Any other path maps as through any projection.
function map_reference_forward(p::FileSystemDirectoryToWidget, iomap, reference)
    folder = iomap === nothing ? nothing : iomap.input
    if folder isa WorkspaceFolder && !_has_folder_place(folder)
        field = _map_place_field_path(reference)
        field === nothing ||
            return annotate_reference_types(iomap.output, extend_reference(EmptyReference(),
                FieldReferenceStep("children"), RangeReferenceStep(_PLACE_FIELD_INDEX - 1, _PLACE_FIELD_INDEX),
                get_reference_steps(field)...))
    end
    invoke(map_reference_forward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

function map_reference_backward(p::FileSystemDirectoryToWidget, iomap, reference)
    folder = iomap === nothing ? nothing : iomap.input
    if folder isa WorkspaceFolder && !_has_folder_place(folder) && reference isa ConcreteReference
        steps = get_reference_steps(strip_reference_types(reference))
        length(steps) >= 3 && steps[1] == FieldReferenceStep("children") &&
            steps[2] == RangeReferenceStep(_PLACE_FIELD_INDEX - 1, _PLACE_FIELD_INDEX) &&
            steps[3] == FieldReferenceStep("content") &&
            return extend_reference(EmptyReference(), FieldReferenceStep("pathname"), steps[4:end]...)
    end
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# Return in the field of the place opens the folder there.
@gestures WorkspaceFolder begin
    when(!_has_folder_place(doc) && !isempty(strip(doc.pathname)))
    KeyPress('\n') => "Open the folder at this place" => _make_folder_place_operation(doc)
end

# The path of the folder, and the state of its read or the count of its entries.
function _format_folder_heading(folder::FileSystemDirectory)
    state = folder.state
    folder.reading && return folder.pathname * " · reading"
    state === :unread && return folder.pathname * " · not read yet"
    state === :failed && return folder.pathname * " · can not read: " * first(split(sprint(showerror, folder.failure), '\n'))
    count = length(folder.elements)
    string(folder.pathname, " · ", count, count == 1 ? " entry" : " entries")
end

const _FOLDER_COLUMNS = ("name" => 3, "kind" => 1)

# The table of the entries, which asks for them. With an offered height its rows
# are a list built one node at a time as the viewport reaches it; with none, every
# row.
function _build_folder_table(owner, directory::FileSystemDirectory, steps::Tuple, bounded::Bool)
    headers = Any[name for (name, _) in _FOLDER_COLUMNS]
    columns = Any[WidgetTableColumn(; policy = Relative(Float64(share))) for (_, share) in _FOLDER_COLUMNS]
    if !bounded
        demand_tree_children(directory)
        rows = Any[_build_folder_row(owner, directory, steps, k) for k in eachindex(directory.elements)]
        return WidgetTable(headers, rows; columns)
    end
    table = WidgetTable(; column_headers = headers, cells = ListNode(make_widget_table_row(Any["", ""])), columns)
    set_cell_computation!(getfield(table, :cells), () -> begin
        demand_tree_children(directory)
        count = length(directory.elements)
        count == 0 && return CellVector()
        make_index_list(count, 1, k -> make_widget_table_row(_build_folder_row(owner, directory, steps, k)))
    end)
    table
end

# The cells of the row of the entry `k`: a link with its icon and its name, and its
# kind.
function _build_folder_row(owner, directory::FileSystemDirectory, steps::Tuple, k::Int)
    entry = directory.elements[k]
    reference = extend_reference(EmptyReference(), steps..., FieldReferenceStep("elements"), ElementReferenceStep(k))
    link = WidgetButton(format_tree_node_label(entry); icon = get_document_decoration(entry).icon,
                        gestures = make_open_page_gestures(owner, reference; domain = "filesystem"))
    Any[link, WidgetLabel(_format_entry_kind(entry))]
end

_format_entry_kind(::FileSystemDirectory) = "folder"
function _format_entry_kind(file::FileSystemFile)
    extension = splitext(file.pathname)[2]
    isempty(extension) ? "file" : lstrip(extension, '.') * " file"
end

_make_folder_page_projection(appearance) =
    ChainingProjection(
        FileSystemDirectoryToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :label_gap)),
        VerticalLayoutToGraphicsCanvas())

make_graphics_projection(::Type{FileSystemDirectory}; measure, appearance) = _make_folder_page_projection(appearance)
make_graphics_projection(::Type{WorkspaceFolder}; measure, appearance) = _make_folder_page_projection(appearance)
