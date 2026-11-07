# Fragment of `FileFormatModule` — the view of a file as a vertical layout: the
# band of the file above the scroll pane of the view while the file holds one, and
# the scroll pane alone otherwise:
#
#     with a band    children[1]                   the band, which names no place
#                    children[2].content.<rest>    the file, in the scroll pane
#     no band        children[1].content.<rest>    the file, in the scroll pane
#
# The printer prints no child. The layout stage that follows prints the layout
# through the recursion, which draws the band with the rows of the widgets and the
# scroll pane with the row of its own type. A write of `band` arranges the layout
# again, and the maps put the steps of the arrangement before a path in the file,
# and take them off.

"""
    FileViewToWidget(; surface, text, padding, button_gap)
    FileViewToWidget(theme)

The projection of a [`FileView`](@ref): the [`FileBand`](@ref) of its file
above its scroll pane, as one row with the sentence of the band and a button for
each of its choices. A click on a button answers the operation of its choice. The
file is the content of the scroll pane, so the pane scrolls it and the band stays. `surface` is the color
behind the row, `text` the color of the sentence and `padding` the space inside the
row and `button_gap` the space between the buttons; the default and `theme`, a
widget theme, give the warning colors, the `band_padding` and the `button_gap` of
the theme.

Chain it with `VerticalLayoutToGraphicsCanvas`, in a recursion that draws the
content and the widgets:

    FileView => ChainingProjection(FileViewToWidget(), VerticalLayoutToGraphicsCanvas())
"""
@projection UntrackedCell struct FileViewToWidget
    surface::StyleColor = make_theme_cell(StyleColor, make_scaled_theme(WidgetTheme()), t -> t.warning_surface)
    text::StyleColor = make_theme_cell(StyleColor, make_scaled_theme(WidgetTheme()), t -> t.warning_foreground)
    padding::Inset = make_theme_cell(Inset, make_scaled_theme(WidgetTheme()), t -> t.band_padding)
    button_gap::Int = get_widget_style(nothing, :button_gap)
end

FileViewToWidget(theme) =
    FileViewToWidget(; surface = make_theme_cell(StyleColor, theme, t -> t.warning_surface),
                       text = make_theme_cell(StyleColor, theme, t -> t.warning_foreground),
                       padding = make_theme_cell(Inset, theme, t -> t.band_padding),
                       button_gap = get_widget_style(theme, :button_gap))

const _FILE_VIEW_FILE_STEP = FieldReferenceStep("file")
const _FILE_VIEW_CONTENT_STEP = FieldReferenceStep("content")
const _FILE_VIEW_SCROLL_STEP = FieldReferenceStep("scroll")
const _FILE_VIEW_FIRST_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _FILE_VIEW_SECOND_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))

function print_document(p::FileViewToWidget, recursion, view::FileView, ctx)
    # The scroll pane fills the height that the band leaves, so a long file scrolls in
    # its scroll pane and the band stays.
    output = VerticalLayout(CellVector(@computation _arrange_file_view(p, view)), Cell(:left), Cell(0),
                            Cell(Fill), Cell(Fill), Cell(nothing))
    iomap = SimpleIoMap(p, view, output)
    # The layout passes a key by its own selection, so it carries the part of the
    # path of the view below it. The scroll pane is a document of the view, which
    # holds its own.
    set_output_path_computations!(output, view, path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    iomap
end

# The children of the layout: the row of the band above the scroll pane, or the
# scroll pane. Drawing the view asks for the text of its file when a change is unread.
function _arrange_file_view(p::FileViewToWidget, view::FileView)
    # A file whose changes are not all read reads its text after this frame.
    demand_file_text(view.file)
    band = get_file_disk_state(view.file).band
    band === nothing ? Any[view.scroll] : Any[_make_file_band_row(p, band), view.scroll]
end

# The row of `band`: its sentence, and a button for each choice, whose click answers
# the operation of the choice. The row takes the height of its content.
function _make_file_band_row(p::FileViewToWidget, band::FileBand)
    sentence = WidgetLabel(band.message; style = WidgetStyle(; label_text_color = p.text))
    buttons = Any[WidgetButton(label; gestures = GestureBinding[
                      GestureBinding(MouseClickPattern(:left), (button, gesture) -> operation;
                                     description = label, domain = "file")])
                  for (label, operation) in band.choices]
    row = HorizontalLayout(Any[sentence, buttons...]; gap = p.button_gap, vertical_align = :center)
    band_widget = WidgetComposite(Any[row]; padding = p.padding,
                                  style = WidgetStyle(; content_color = p.surface, padding_color = p.surface))
    LayoutConstraint(band_widget; height = Content)
end

# The steps from the layout to the scroll pane, for the arrangement that the file of
# the view shows now.
_get_file_view_scroll_steps(view::FileView) =
    get_file_disk_state(view.file).band === nothing ? _FILE_VIEW_FIRST_STEPS : _FILE_VIEW_SECOND_STEPS

# `file.<rest>` ↔ `<scroll pane>.content.<rest>` in the layout: the file is the
# content of the scroll pane. `scroll.<rest>` is a part that the pane introduced,
# which the view keeps by its field. The band names no place, and the whole view is
# the layout.
function map_reference_forward(::FileViewToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    view = iomap.input
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    reference isa ConcreteReference || return nothing
    scroll_steps = _get_file_view_scroll_steps(view)
    head = get_reference_head(reference)
    tail = get_reference_tail(reference)
    if head == _FILE_VIEW_SCROLL_STEP
        is_fully_typed_reference(tail) ||
            (tail = annotate_reference_types(view.scroll, strip_reference_types(tail)))
        return concat_references(annotate_reference_types(output, extend_reference(EmptyReference(), scroll_steps...)),
                                 tail)
    end
    head == _FILE_VIEW_FILE_STEP || return nothing
    # The rest keeps the checkpoints that it came with; the steps of the layout take
    # their types.
    is_fully_typed_reference(tail) ||
        (tail = annotate_reference_types(view.file, strip_reference_types(tail)))
    concat_references(annotate_reference_types(output,
                                               extend_reference(EmptyReference(), scroll_steps...,
                                                                _FILE_VIEW_CONTENT_STEP)),
                      tail)
end

# A path into the file takes the step of the file, and a path to the scroll pane
# names the file; a part that the pane introduced keeps its path below the field of
# the pane. A path into the band names nothing, so a click on a button leaves the
# selection where it is; a path to the layout itself names the whole view.
function map_reference_backward(::FileViewToWidget, iomap::SimpleIoMap, reference)
    prefix = _get_file_view_scroll_steps(iomap.input)
    steps = get_reference_steps(strip_reference_types(reference))
    if length(steps) >= 2 && steps[1] == prefix[1] && steps[2] == prefix[2]
        rest = get_reference_tail(get_reference_tail(reference))
        file = ConcreteReference(_FILE_VIEW_FILE_STEP, EmptyReference())
        rest isa EmptyReference && return file
        if get_reference_head(rest) == _FILE_VIEW_CONTENT_STEP
            return concat_references(file, get_reference_tail(rest))
        end
        return ConcreteReference(_FILE_VIEW_SCROLL_STEP, rest)
    end
    isempty(steps) ? EmptyReference() : nothing
end
