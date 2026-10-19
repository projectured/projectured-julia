# Fragment of `ExplorerModule` — the page of a search below a node: its title, the
# line that says how far it is, and its matches, each a link to the page of its
# node, with the place of the node below the node of the search.

"""
    ExplorerSearchToWidget(; gap)

Draw an [`ExplorerSearch`](@ref) as its page: its title, the line that says how
many nodes it waits for and what it found, and a table of its matches with the
place of each below the node of the search. A match is a link: a press opens its
page in the navigator around the page, which in an explorer also opens its node in
the tree, and Ctrl+press opens it in a new tab. The page reads the result, so the
search goes on while the page shows.
"""
@projection UntrackedCell struct ExplorerSearchToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
end

function print_document(p::ExplorerSearchToWidget, recursion, search::ExplorerSearch, context)
    line = WidgetLabel(() -> _format_search_line(search, search.result))
    body = VerticalLayout(Any[]; gap = p.gap, child_width = Fill)
    set_cell_computation!(getfield(body.children, :elements), () -> begin
        matches = search.result.matches
        isempty(matches) &&
            return Cell[Cell(WidgetLabel(is_cell_provisional(getfield(search, :result)) ? "No match yet." : "No match."))]
        rows = Any[_make_search_match_row(search, match) for match in matches]
        Cell[Cell(WidgetTable(Any["match", "place"], rows))]
    end)
    root = VerticalLayout(Any[WidgetLabel(get_document_title(search)), line,
                              LayoutConstraint(WidgetScrollPane(body); width = Fill, height = Fill)];
                          horizontal_align = :left, gap = p.gap)
    iomap = ChildrenIoMap(p, search, root, Cell(Any[]))
    # The part under the pointer, so a link lights and takes a press.
    set_output_path_computations!(root, search, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# The row of a match: its label as a link to its page, from the root section of the
# search, and the labels of the nodes above it.
function _make_search_match_row(search::ExplorerSearch, match)
    address = extend_reference(EmptyReference(), search.steps..., match.steps...)
    Any[_make_section_link(search.root, format_tree_node_label(match.document), address),
        WidgetLabel(join(match.labels, " / "))]
end

# A search draws as its page inside any document that a renderer draws.
make_graphics_projection(::Type{<:ExplorerSearch}; measure, appearance) =
    ChainingProjection(
        ExplorerSearchToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        VerticalLayoutToGraphicsCanvas())
