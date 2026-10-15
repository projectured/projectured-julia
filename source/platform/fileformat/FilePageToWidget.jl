# Fragment of `FileFormatModule` — the page of a file as a vertical layout: the
# band above the content while the page holds one, and the content alone
# otherwise:
#
#     with a band    children[1]            the band, which names no place
#                    children[2].<rest>     the content
#     no band        children[1].<rest>     the content
#
# The printer prints no child. The layout stage that follows prints the layout
# through the recursion, which draws the band with the rows of the widgets and the
# content with the row of its own type. A write of `band` arranges the layout
# again, and the maps put the steps of the arrangement before a path in the
# content, and take them off.

"""
    FilePageToWidget(; surface, text)
    FilePageToWidget(theme)

The projection of a [`FilePage`](@ref): its [`FileBand`](@ref) above its content,
as one row with the sentence of the band and a button for each of its choices. A
click on a button answers the operation of its choice. `surface` is the color
behind the row and `text` the color of the sentence; the default and `theme`, a
widget theme, give the warning colors of the theme.

Chain it with `VerticalLayoutToGraphicsCanvas`, in a recursion that draws the
content and the widgets:

    FilePage => ChainingProjection(FilePageToWidget(), VerticalLayoutToGraphicsCanvas())
"""
@projection UntrackedCell struct FilePageToWidget
    surface::StyleColor = make_theme_cell(StyleColor, make_scaled_theme(WidgetTheme()), t -> t.warning_surface)
    text::StyleColor = make_theme_cell(StyleColor, make_scaled_theme(WidgetTheme()), t -> t.warning_foreground)
end

FilePageToWidget(theme) =
    FilePageToWidget(; surface = make_theme_cell(StyleColor, theme, t -> t.warning_surface),
                       text = make_theme_cell(StyleColor, theme, t -> t.warning_foreground))

const _FILE_PAGE_CONTENT_STEP = FieldReferenceStep("content")
const _FILE_PAGE_FIRST_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _FILE_PAGE_SECOND_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))

function print_document(p::FilePageToWidget, recursion, page::FilePage, ctx)
    # The content fills the height that the band leaves, so a long file scrolls in
    # its scroll pane and the band stays.
    output = VerticalLayout(CellVector(@computation _arrange_file_page(p, page)), Cell(:left), Cell(0),
                            Cell(Fill), Cell(Fill), Cell(nothing))
    iomap = SimpleIoMap(p, page, output)
    # The layout passes a key by its own selection, so it carries the part of the
    # path of the page below it. The content is a document of the page, which
    # holds its own.
    set_output_path_computations!(output, page, path -> map_reference_forward(p, iomap, path);
                                  dormant = false)
    iomap
end

# The children of the layout: the row of the band above the content, or the content.
function _arrange_file_page(p::FilePageToWidget, page::FilePage)
    band = page.band
    band === nothing ? Any[page.content] : Any[_make_file_band_row(p, band), page.content]
end

# The row of `band`: its sentence, and a button for each choice, whose click answers
# the operation of the choice. The row takes the height of its content.
function _make_file_band_row(p::FilePageToWidget, band::FileBand)
    sentence = WidgetLabel(band.message; style = WidgetStyle(; label_text_color = p.text))
    buttons = Any[WidgetButton(label; gestures = GestureBinding[
                      GestureBinding(MouseClickPattern(:left), (button, gesture) -> operation;
                                     description = label, domain = "file")])
                  for (label, operation) in band.choices]
    row = HorizontalLayout(Any[sentence, buttons...]; gap = 12, vertical_align = :center)
    band_widget = WidgetComposite(Any[row]; padding = Inset(6, 10, 6, 10),
                                  style = WidgetStyle(; content_color = p.surface, padding_color = p.surface))
    LayoutConstraint(band_widget; height = Content)
end

# The steps from the layout to the content, for the arrangement that the page
# shows now.
_get_file_page_content_steps(page::FilePage) =
    page.band === nothing ? _FILE_PAGE_FIRST_STEPS : _FILE_PAGE_SECOND_STEPS

# `content.<rest>` ↔ the content in the layout. The band names no place.
function map_reference_forward(::FilePageToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    reference isa ConcreteReference || return nothing
    get_reference_head(reference) == _FILE_PAGE_CONTENT_STEP || return nothing
    page = iomap.input
    # The rest keeps the checkpoints that it came with; the steps of the layout take
    # their types.
    rest = get_reference_tail(reference)
    is_fully_typed_reference(rest) ||
        (rest = annotate_reference_types(page.content, strip_reference_types(rest)))
    concat_references(annotate_reference_types(output,
                                               extend_reference(EmptyReference(),
                                                                _get_file_page_content_steps(page)...)),
                      rest)
end

# A path into the content takes the step of the content; a path into the band names
# nothing, so a click on a button leaves the selection where it is; a path to the
# layout itself names the whole page.
function map_reference_backward(::FilePageToWidget, iomap::SimpleIoMap, reference)
    prefix = _get_file_page_content_steps(iomap.input)
    steps = get_reference_steps(strip_reference_types(reference))
    if length(steps) >= 2 && steps[1] == prefix[1] && steps[2] == prefix[2]
        rest = get_reference_tail(get_reference_tail(reference))
        return concat_references(ConcreteReference(_FILE_PAGE_CONTENT_STEP, EmptyReference()), rest)
    end
    isempty(steps) ? EmptyReference() : nothing
end

# The save and the load of the file of the page come back as the page's own, so the
# page checks the disk before a save and keeps the hash of the text of each load
# and save. A reader of a compound reaches each member here.
read_intent(::FilePageToWidget, iomap::SimpleIoMap, op::SaveFileOperation) =
    op.file === find_page_file(iomap.input) ? SaveFilePageOperation(iomap.input) : op

read_intent(::FilePageToWidget, iomap::SimpleIoMap, op::ReloadFileOperation) =
    (op.content === nothing && op.file === find_page_file(iomap.input)) ?
        LoadFilePageOperation(iomap.input) : op
