# Fragment of `LinkModule` — the view of a link: a `WidgetLink`, whose face and
# target the functions of a link give.

"""
    LinkToWidget()

The view of any link: a `WidgetLink`. Its face is the content of the link, or the
name and the icon of its target (`format_link_label`); its tooltip says where it
leads (`describe_link`); its target is the target of the link; and it draws muted
and opens nothing while the target is gone (`is_link_broken`). Each part follows
the link and its target, so a rename of the target renames the face.

Use it to draw a link type of a domain as a link of the platform.

# Example

    make_graphics_projection(::Type{MyLink}; measure, appearance) =
        ChainingProjection(LinkToWidget(), WidgetLinkToGraphicsCanvas(get_scaled_theme!(appearance, WidgetTheme); measure))
"""
struct LinkToWidget <: Projection end

function print_document(p::LinkToWidget, recursion, link, context)
    content = get_link_content(link)
    face = content isa Document ? content : () -> format_link_label(link)
    widget = WidgetLink(face, EmptyReference(); tooltip = () -> describe_link(link),
                        enabled = () -> !is_link_broken(link))
    set_cell_computation!(getfield(widget, :target), () -> _make_widget_target(get_link_target(link)))
    set_cell_computation!(getfield(widget, :icon), () ->
        get_link_content(link) === nothing ? _get_target_icon(get_link_target(link)) : nothing)
    iomap = SimpleIoMap(p, link, widget)
    # The link holds its part of the selection and of the part under the pointer,
    # so it lights while the pointer is on it.
    set_output_path_computations!(widget, link, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# The target of the widget of a link: a document as a locator of it, as the
# widget keeps it, and any other target as it is.
_make_widget_target(target::Document) = DocumentLocator(target, EmptyReference())
_make_widget_target(target) = target

# A link draws as one part: the link is the widget, and no path goes inside it.
map_reference_forward(::LinkToWidget, iomap, reference) = reference isa EmptyReference ? reference : nothing
map_reference_backward(::LinkToWidget, iomap, reference) = reference isa EmptyReference ? reference : nothing

# A general link draws as a link inside any document that a renderer draws.
make_graphics_projection(::Type{<:Link}; measure, appearance) =
    ChainingProjection(LinkToWidget(),
                       WidgetLinkToGraphicsCanvas(get_scaled_theme!(appearance, WidgetTheme); measure))
