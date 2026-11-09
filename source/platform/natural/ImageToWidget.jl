# Fragment of `NaturalModule` — the natural drawing of a picture.

"""
    ImageToWidget()

An [`ImageDocument`](@ref) as the widget that shows it: a label draws the pixels, at
their natural size or smaller in their shape to fit the slot that the place gives
(`WidgetLabel`). The slot decides the size, and a place that gives no limit, such as a
scroll pane at its natural size, shows the pixels as they are.

An [`Image`](@ref) whose size is not known yet draws a box with its path under it. After a
failed read it draws the path and the reason. Both read `failure` and
[`get_image_natural_size`](@ref) of the picture, which asks a task for the size in the
head of the file, never its pixels, so the print asks for no decode: only the paint of a
backend does.

The picture has no part of its own, so the projection maps no reference and reads
the gestures of the widget that it draws.
"""
struct ImageToWidget <: Projection end

function print_document(p::ImageToWidget, recursion, image::ImageDocument, ctx)
    label = WidgetLabel(image)
    # The slot is the edge of the picture and no extent that it must fill: a picture
    # smaller than its slot keeps its size.
    bounded = with_bounded_size(ctx; width = ctx.maximum_width, height = ctx.maximum_height)
    child = make_reconciled_child_iomap_cell(() -> _make_shown_image_widget(image, label),
                                             widget -> print_child(recursion, widget, bounded))
    ContentIoMap(p, image, Cell(@computation child[].output), Cell(@computation child[]))
end

# The widget that shows `image`, whose pixels `label` draws.
_make_shown_image_widget(::ImageDocument, label) = label

function _make_shown_image_widget(image::Image, label)
    failure = image.failure
    failure === nothing || return WidgetLabel(string(image.filename, ": ", sprint(showerror, failure)))
    get_image_natural_size(image) === nothing || return label
    VerticalLayout(Any[label, WidgetLabel(image.filename)])
end

function map_reference_forward(::ImageToWidget, iomap::ContentIoMap, reference)
    inner = iomap.inner_iomap
    map_reference_forward(inner.projection, inner, reference)
end

function map_reference_backward(::ImageToWidget, iomap::ContentIoMap, reference)
    inner = iomap.inner_iomap
    map_reference_backward(inner.projection, inner, reference)
end

function read_intent(::ImageToWidget, iomap::ContentIoMap, evt)
    inner = iomap.inner_iomap
    read_intent(inner.projection, inner, evt)
end
