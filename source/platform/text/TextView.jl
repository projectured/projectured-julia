# Fragment of `TextModule`.
#
# A view of a text, and the projection that gives the text that the view shows. The
# text is content: it says what is written, and every view of it shows the same
# lines. The view keeps the state of one view: its caret and the part under the
# pointer. Two views of one text keep two carets; two places that show one view
# show its one caret.

"""
    TextView(content::TextBlock)

A view of the text `content`. Its `selection` is the caret of this view: a flat
place in `content`, a `TextRangeReferenceStep` caret or range, or a whole-element
`TextSpanReferenceStep`. The path ends at the view and never enters `content`, so
another view of the same text keeps a caret of its own. A place that shows the
view shows its caret, so two places of one view share it.

`TextViewToText` prints the view as the text that it shows.
"""
@document struct TextView
    content::TextBlock
end

# A person edits the text that a view shows.
DocumentModule.get_edited_field(::TextView) = :content

"""
    TextViewToText()

`TextView → TextBlock`: the text of the view, with the caret of the view. The output
holds the lines of the content, the same `CellVector`, so it draws what every other
view of the text draws, and its selection is the caret of this view. A place of the
view in the content, a path that starts with `content`, maps to the same place in
the output.

Backward, a caret, a range or a box of the output is the same place of the view. An
edit of a run of the output is an edit of the same run of the content: it goes back
as a flat `ReplaceTextRangeOperation` on the view, which edits the content and puts
the caret on the view.
"""
struct TextViewToText <: Projection end

@iomap struct TextViewToTextIoMap
    projection::Any
    input::TextView
    output::TextBlock
end

function print_document(p::TextViewToText, recursion, view::TextView, ctx)
    content = view.content
    paths = make_output_path_cells(view, path -> _map_text_view_forward(path))
    TextViewToTextIoMap(p, view, TextBlock(content.elements, paths.selection, paths.mouse_target))
end

map_reference_forward(::TextViewToText, ::TextViewToTextIoMap, reference) =
    _map_text_view_forward(reference)

function map_reference_backward(::TextViewToText, iomap::TextViewToTextIoMap, reference)
    plain = strip_reference_types(reference)
    (plain isa EmptyReference || _is_flat_text_place(plain)) && return plain
    range = get_flat_range(iomap.output, plain)
    range === nothing ? nothing : make_flat_range_reference(range...)
end

# The lowered edit of one run names the run in the lines that the output shares
# with the content. It goes back flat, so its caret stays on the view.
function read_intent(::TextViewToText, iomap::TextViewToTextIoMap, op::ReplaceStringRangeOperation)
    range = get_flat_range(iomap.output, op.reference)
    range === nothing && return nothing
    ReplaceTextRangeOperation(make_flat_range_reference(range...), op.replacement)
end

# A place of the view: its own caret, range or box, or a place in its content.
function _map_text_view_forward(reference)
    plain = strip_reference_types(reference)
    (plain isa EmptyReference || _is_flat_text_place(plain)) && return plain
    (plain isa ConcreteReference && plain.head isa FieldReferenceStep &&
     plain.head.name == "content") ? plain.tail : nothing
end

# Whether `reference` is one flat step of a text: a caret, a range or a box.
_is_flat_text_place(reference) =
    reference isa ConcreteReference && reference.tail isa EmptyReference &&
    reference.head isa Union{TextRangeReferenceStep, TextSpanReferenceStep}

_find_edited_text(view::TextView) = view.content
