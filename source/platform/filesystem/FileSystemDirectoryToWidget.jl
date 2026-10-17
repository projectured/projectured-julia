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
# from `owner`, then its place among the entries.
function _print_folder_page(p::FileSystemDirectoryToWidget, owner, directory::FileSystemDirectory, steps::Tuple,
                            context)
    bounded = context !== nothing && get_exact_height(context) !== nothing
    heading = WidgetLabel(() -> _format_folder_heading(directory))
    table = _build_folder_table(owner, directory, steps, bounded)
    root = VerticalLayout(Any[heading, LayoutConstraint(table; width = Fill, height = bounded ? Fill : Content)];
                          horizontal_align = :left, gap = p.gap)
    iomap = ChildrenIoMap(p, owner, root, Cell(Any[]))
    # The part under the pointer, so a link lights and takes a press.
    follow_output_mouse_target!(root, () ->
        map_mouse_target_forward(owner, path -> map_reference_forward(p, iomap, path)))
    iomap
end

# The path of the folder, and the state of its read or the count of its entries.
function _format_folder_heading(folder::FileSystemDirectory)
    state = folder.state
    state === :reading && return folder.pathname * " · reading"
    state === :unread && return folder.pathname * " · not read yet"
    state === :failed && return folder.pathname * " · can not read: " * first(split(sprint(showerror, folder.failure), '\n'))
    count = length(folder.elements)
    string(folder.pathname, " · ", count, count == 1 ? " entry" : " entries")
end

const _FOLDER_COLUMNS = ("name" => 3, "kind" => 1)

# The table of the entries. With an offered height its rows are a list built one
# node at a time as the viewport reaches it; with none, every row.
function _build_folder_table(owner, directory::FileSystemDirectory, steps::Tuple, bounded::Bool)
    headers = Any[name for (name, _) in _FOLDER_COLUMNS]
    columns = Any[WidgetTableColumn(; policy = Relative(Float64(share))) for (_, share) in _FOLDER_COLUMNS]
    if !bounded
        rows = Any[_build_folder_row(owner, directory, steps, k) for k in eachindex(directory.elements)]
        return WidgetTable(headers, rows; columns)
    end
    table = WidgetTable(; column_headers = headers, cells = ListNode(make_widget_table_row(Any["", ""])), columns)
    set_cell_computation!(getfield(table, :cells), () -> begin
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
    open(place) = (_, _) -> OpenPageOperation(owner, reference, place)
    link = WidgetButton(format_tree_node_label(entry); icon = get_document_decoration(entry).icon,
                        gestures = GestureBinding[
                            GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), open(:here);
                                           description = "Open as a page", domain = "filesystem"),
                            GestureBinding(MouseClickPattern(:left; modifiers = [:ctrl]), open(:new_tab);
                                           description = "Open in a new tab", domain = "filesystem")])
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
