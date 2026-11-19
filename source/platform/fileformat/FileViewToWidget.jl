# Fragment of `FileFormatModule` — the view of a file as a vertical layout: a row
# above the scroll pane of the view while the file holds a band or reads its first
# text, and the scroll pane alone otherwise:
#
#     with a row     children[1]                   the band or the reading row, which names no place
#                    children[2].content.<rest>    the file, in the scroll pane
#     no row         children[1].content.<rest>    the file, in the scroll pane
#
# A view that shows its file through views has the view of what the file holds in the
# scroll pane, at its field `content`, where another view has the file at `file`.
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
each of its choices. A click on a button answers the operation of its choice. A file
that is not read yet ([`make_unread_file`](@ref)) has a row that says
"<name> · reading", as the heading of a folder says it, in the place of the band. The
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
# The field of a scroll pane that holds what it shows. The field of a file view that
# holds the view of what its file holds has the same name.
const _FILE_VIEW_CONTENT_STEP = FieldReferenceStep("content")

# The step from `view` to what its scroll pane shows now: the view of what the file
# holds, or the file.
_get_shown_step(view::FileView) = view.content === nothing ? _FILE_VIEW_FILE_STEP : _FILE_VIEW_CONTENT_STEP
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

# The children of the layout: the row of the band or the reading row above the scroll
# pane, or the scroll pane. Drawing the view asks for the text of its file when a
# change is unread.
function _arrange_file_view(p::FileViewToWidget, view::FileView)
    # A file whose changes are not all read reads its text after this frame.
    demand_file_text(view.file)
    state = get_file_disk_state(view.file)
    state.band !== nothing && return Any[_make_file_band_row(p, state.band), view.scroll]
    _is_file_unread(state) && return Any[_make_file_reading_row(view), view.scroll]
    Any[view.scroll]
end

# Whether the file has not read its text yet, so the view shows the reading row.
_is_file_unread(state) = state.loaded_count < 0

# Whether a row stands above the scroll pane: the row of the band, or the reading row.
_has_file_row(state) = state.band !== nothing || _is_file_unread(state)

# The row of a file that is not read yet: its name and that it reads, in the words of
# the heading of a folder that reads. The row takes the height of its content.
_make_file_reading_row(view::FileView) =
    LayoutConstraint(WidgetLabel(string(get_document_title(view.file), " · reading")); height = Content)

# The row of `band`: its sentence, and a button for each choice, whose click answers
# the operation of the choice. The row takes the height of its content.
function _make_file_band_row(p::FileViewToWidget, band::FileBand)
    sentence = WidgetLabel(band.message; style = WidgetStyle(; label_text_color = p.text))
    buttons = Any[WidgetButton(label; gestures = GestureBinding[
                      GestureBinding(MouseClickPattern(:left), (button, gesture, _) -> operation;
                                     description = label, domain = "file")])
                  for (label, operation) in band.choices]
    row = HorizontalLayout(Any[sentence, buttons...]; gap = p.button_gap, vertical_align = :center)
    band_widget = WidgetComposite(Any[row]; padding = p.padding,
                                  style = WidgetStyle(; content_color = p.surface, padding_color = p.surface))
    LayoutConstraint(band_widget; height = Content)
end

# The steps from the layout to the scroll pane, for the arrangement that the file of
# the view shows now: the scroll pane is second below a row of the band or of the
# first read, and first otherwise.
function _get_file_view_scroll_steps(view::FileView)
    state = get_file_disk_state(view.file)
    _has_file_row(state) ? _FILE_VIEW_SECOND_STEPS : _FILE_VIEW_FIRST_STEPS
end

# `file.<rest>` ↔ `<scroll pane>.content.<rest>` in the layout: the file is the
# content of the scroll pane. For a view that shows its file through views, the path
# of the view is `content.<rest>`, and the content of the scroll pane is the view of
# what the file holds. A path of such a view through `file` maps forward as the path
# of the views of the same place, and no path maps back to it. `scroll.<rest>` is a part that the pane introduced,
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
    # A view that shows its file through views draws a place of the file with the view
    # of that place, so a path through the field `file` takes the path of the views:
    # a change for a part of the file goes to the view that shows the part.
    if head == _FILE_VIEW_FILE_STEP && view.content !== nothing
        shown = get_view_path(view, tail)
        shown isa ConcreteReference || return EmptyReference(get_reference_node_type(output))
        head = get_reference_head(shown)
        tail = get_reference_tail(shown)
    end
    head == _get_shown_step(view) || return nothing
    # The rest keeps the checkpoints that it came with; the steps of the layout take
    # their types.
    is_fully_typed_reference(tail) ||
        (tail = annotate_reference_types(_get_shown_document(view), strip_reference_types(tail)))
    concat_references(annotate_reference_types(output,
                                               extend_reference(EmptyReference(), scroll_steps...,
                                                                _FILE_VIEW_CONTENT_STEP)),
                      tail)
end

# A path into the file takes the step of the file, and a path to the scroll pane
# names the file; a part that the pane introduced keeps its path below the field of
# the pane. A path into the band or the reading row names nothing, so a click on a
# button leaves the selection where it is; a path to the layout itself names the whole
# view.
function map_reference_backward(::FileViewToWidget, iomap::SimpleIoMap, reference)
    prefix = _get_file_view_scroll_steps(iomap.input)
    steps = get_reference_steps(strip_reference_types(reference))
    if length(steps) >= 2 && steps[1] == prefix[1] && steps[2] == prefix[2]
        rest = get_reference_tail(get_reference_tail(reference))
        file = ConcreteReference(_get_shown_step(iomap.input), EmptyReference())
        rest isa EmptyReference && return file
        if get_reference_head(rest) == _FILE_VIEW_CONTENT_STEP
            return concat_references(file, get_reference_tail(rest))
        end
        return ConcreteReference(_FILE_VIEW_SCROLL_STEP, rest)
    end
    isempty(steps) ? EmptyReference() : nothing
end

# With views in the scroll pane, the printer of the file is not on the path of a key,
# so the view reads for its file what that printer reads: the key table of the file,
# such as Ctrl+S and F5. It reads by the rule of a level, after the rules of the view:
# with no answer of what the pane shows, a rule of the file that matches answers, and
# with an answer, only a rule whose `override` condition holds for it. A list of rows
# takes the rows of the file too. With the file in the pane, the printer of the file
# reads them, and this method adds nothing.
function read_gesture(p::FileViewToWidget, iomap::SimpleIoMap, gesture; answer = nothing)
    own = invoke(read_gesture, Tuple{Projection, Any, Any}, p, iomap, gesture; answer)
    view = iomap.input
    view.content === nothing && return own
    table = read_gesture(view.file, gesture; answer)
    gesture isa CollectIntents || return own === nothing ? table : own
    merge_collected_intents(own isa CollectedIntentsOperation ? own : nothing,
                            table isa CollectedIntentsOperation ? table : nothing)
end
