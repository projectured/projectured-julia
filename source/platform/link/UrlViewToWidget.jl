# Fragment of `LinkModule` — the page of an address: the address, and the command
# that opens it.

"""
    UrlViewToWidget(; gap)

The page of an address: its address, and a button that opens it, "Open in the
browser" or "Open the file". The button is off for a relative address, which only
the page of a link resolves.
"""
@projection UntrackedCell struct UrlViewToWidget <: Projection
    gap::Int = get_widget_style(nothing, :label_gap)
end

function print_document(p::UrlViewToWidget, recursion, view::UrlView, context)
    url = view.url
    open(_, _) = OpenUrlOperation(view.url)
    button = WidgetButton(find_url_file_path(url) === nothing ? "Open in the browser" : "Open the file";
                          enabled = is_absolute_url(url),
                          gestures = GestureBinding[
                              GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), open;
                                             description = "Open the address", domain = "link"),
                              GestureBinding(KeyPressPattern('\n'; modifiers = Symbol[]), open;
                                             description = "Open the address", domain = "link")])
    root = VerticalLayout(Any[WidgetLabel(() -> format_url(view.url)), button];
                          horizontal_align = :left, gap = p.gap)
    iomap = ChildrenIoMap(p, view, root, Cell(Any[]))
    set_output_path_computations!(root, view, path -> map_reference_forward(p, iomap, path); dormant = false)
    set_output_tree_path_computations!(root)
    iomap
end

# The page names no part of the address: each part is one that the page drew.
map_reference_forward(p::UrlViewToWidget, iomap, reference) =
    reference isa EmptyReference ? reference : find_introduced_path(p, reference)

make_graphics_projection(::Type{<:UrlView}; measure, appearance) =
    ChainingProjection(UrlViewToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :label_gap)),
                       VerticalLayoutToGraphicsCanvas())

# An address draws as a link inside any document that a renderer draws.
make_graphics_projection(::Type{<:Url}; measure, appearance) =
    ChainingProjection(LinkToWidget(),
                       WidgetLinkToGraphicsCanvas(get_scaled_theme!(appearance, WidgetTheme); measure))
