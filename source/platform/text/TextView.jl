# Fragment of `TextModule`.
#
# A view of a text, and the projection that draws it. The text is content: it says
# what is written, and every view of it shows the same lines. The view keeps the
# state of one view: its caret and the part under the pointer. Two views of one text
# keep two carets; two places that show one view show its one caret.

"""
    TextView(content::TextBlock)

A view of the text `content`. Its `selection` is the caret of this view: a flat
place in `content`, a `TextRangeReferenceStep` caret or range, or a whole-element
`TextSpanReferenceStep`. The path ends at the view and never enters `content`, so
another view of the same text keeps a caret of its own. A place that shows the
view shows its caret, so two places of one view share it. The view keeps its caret
while the focus is elsewhere, as a dormant selection.

`closed_folds` are the folds of the text that this view closes, or `nothing`:
`TextFolding` hides their lines in this view only. The view of the text of a node
of syntax computes them from the folds of the views of the nodes.

`TextViewToGraphicsCanvas` draws the view over the drawing of its content.
"""
@document struct TextView <: ContentView
    content::TextBlock
    closed_folds::Any = nothing
end

# The view of a text that a viewing step prints.
make_content_view(content::TextBlock) = TextView(content)

_find_edited_text(view::TextView) = view.content

# The keys of a view: the keys of a text, read against the lines of its content and
# the caret of the view. Each edit and each motion is a flat place of the view, so
# its caret stays on the view.
@gestures TextView begin
    when(KeyPress(_, t), !any(iscntrl, t)) => "Insert character" => _text_insert(doc.content, t, doc.selection)
    KeyPress('\n';)        => "Break the line"       => _text_break(doc.content, doc.selection)
    KeyDown(:backspace;)   => "Delete backward"      => _text_delete(doc.content, :backspace, doc.selection)
    KeyDown(:delete;)      => "Delete forward"       => _text_delete(doc.content, :delete, doc.selection)
    KeyDown(:home; ctrl)   => "Cursor to text start" => _text_jump(doc.content, :start)
    KeyDown(:end; ctrl)    => "Cursor to text end"   => _text_jump(doc.content, :end)
    KeyDown(:period; ctrl) => "Toggle collapse"      => ToggleCollapseOperation()
    KeyDown(:left; ctrl)   => "Word left"            => _text_word_motion(doc.content, :left, doc.selection)
    KeyDown(:right; ctrl)  => "Word right"           => _text_word_motion(doc.content, :right, doc.selection)
    KeyDown(:left;)        => "Cursor left"          => _text_char_motion(doc.content, :left, doc.selection)
    KeyDown(:right;)       => "Cursor right"         => _text_char_motion(doc.content, :right, doc.selection)
    KeyDown(:left; shift)        => "Extend the selection left"         => _text_extend(doc.content, :left, doc.selection)
    KeyDown(:right; shift)       => "Extend the selection right"        => _text_extend(doc.content, :right, doc.selection)
    KeyDown(:left; ctrl, shift)  => "Extend the selection a word left"  => _text_extend(doc.content, :word_left, doc.selection)
    KeyDown(:right; ctrl, shift) => "Extend the selection a word right" => _text_extend(doc.content, :word_right, doc.selection)
    KeyDown(:home; ctrl, shift)  => "Extend the selection to the start" => _text_extend(doc.content, :start, doc.selection)
    KeyDown(:end; ctrl, shift)   => "Extend the selection to the end"   => _text_extend(doc.content, :end, doc.selection)
end

"""
    TextViewToGraphicsCanvas(; theme = nothing)

Draw a `TextView`: the drawing of its content, which the recursion prints with the
row of `TextBlock` (`TextBlockToGraphicsCanvas`), and over it the band under the
selection of the view and its caret. `theme` is a `TextTheme`, scaled or not, whose
caret and band it draws; with `nothing`, those of the default theme. A dormant
caret is drawn muted.

The caret of the view maps forward through the IO map of the content, and a point
maps back through it to a caret of the view. The keys are the keys of the view
(`@gestures TextView`); Up, Down, Home and End read the segments of the content.
"""
@projection UntrackedCell struct TextViewToGraphicsCanvas
    caret_color::StyleColor
    dormant_caret_color::StyleColor
    caret_width::Int
    highlight_color::StyleColor
    dormant_highlight_color::StyleColor
    highlight_radius::Int
end

TextViewToGraphicsCanvas(; theme = nothing) =
    TextViewToGraphicsCanvas(get_text_style(theme, :caret),
                             get_text_style(theme, :dormant_caret),
                             get_text_style(theme, :caret_width),
                             get_text_style(theme, :highlight),
                             get_text_style(theme, :dormant_highlight),
                             get_text_style(theme, :highlight_radius))

"""
    TextViewToGraphicsCanvasIoMap

IoMap for `TextViewToGraphicsCanvas`: `content` is the IO map of the print of the
content of the view.
"""
@iomap struct TextViewToGraphicsCanvasIoMap
    projection::Any
    input::TextView
    output::GraphicsCanvas
    content::Any
end

find_first_baseline(iomap::TextViewToGraphicsCanvasIoMap) = find_first_baseline(iomap.content)

# The output is the band, the drawing of the content and the caret, in this order,
# so the content is its second element, at the place of the view.
const _TEXT_VIEW_CONTENT_STEP =
    ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(1, 2), EmptyReference()))

function print_document(p::TextViewToGraphicsCanvas, recursion, view::TextView, ctx)
    content = print_child(recursion, view.content, make_child_context(ctx, FieldReferenceStep("content")))
    content isa TextBlockToGraphicsCanvasIoMap || throw(ArgumentError(
        "TextViewToGraphicsCanvas draws its caret over a content that TextBlockToGraphicsCanvas " *
        "prints; the recursion printed it with $(typeof(content.projection))"))
    # The marks read the stored selection, live or dormant, so a dormant caret has a
    # place on the screen too; `is_live` decides how it is painted.
    selection_cell = getfield(view, :selection)
    overlay = Cell(@computation _compute_selection_marks(content, _get_stored_path(selection_cell[])))
    is_live = Cell(@computation _is_live_selection(selection_cell[]))
    marks = _make_selection_marks(p, overlay, is_live)
    drawing = content.output
    elements = CellVector(Cell[Cell(marks.band), Cell(drawing), Cell(marks.caret)])
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), getfield(drawing, :w), getfield(drawing, :h),
                            elements, layout_none, true, Cell(nothing))
    TextViewToGraphicsCanvasIoMap(p, view, canvas, content)
end

# A place of the view: its own caret, range or box, or a place in its content, maps
# through the IO map of the content to the drawing of the content.
function map_reference_forward(::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, reference)
    place = _find_text_view_place(reference)
    place isa EmptyReference && return place
    place === nothing && return nothing
    image = map_reference_forward(iomap.content.projection, iomap.content, place)
    image === nothing ? nothing : concat_references(_TEXT_VIEW_CONTENT_STEP, image)
end

# A point, or a path into the drawing of the content, maps back through the IO map
# of the content to a place of the text, which is the caret of the view.
function map_reference_backward(::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, reference)
    point = find_reference_point(reference)
    inner = point !== nothing ? reference : _find_content_drawing_path(reference)
    inner === nothing && return nothing
    place = map_reference_backward(iomap.content.projection, iomap.content, inner)
    place === nothing ? nothing : strip_reference_types(place)
end

read_intent(::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, evt::KeyPress) =
    read_gesture(iomap.input, evt)

function read_intent(p::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, evt::KeyDown)
    operation = read_gesture(iomap.input, evt)
    operation === nothing || return operation
    content = iomap.content
    _read_geometry_key(content.projection, content, content.input, iomap.input.selection, evt)
end

# A click puts the caret of the view at the point.
function read_intent(p::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, evt::MouseClick)
    evt.button === :left || return nothing
    path = map_reference_backward(p, iomap, PointReferenceStep(evt.x, evt.y))
    path === nothing ? nothing : ReplaceSelectionOperation(path)
end

# The place in the content that a reference of the view names: its own caret, range
# or box, or the tail of a path through `content`.
function _find_text_view_place(reference)
    plain = strip_reference_types(reference)
    (plain isa EmptyReference || _is_flat_text_place(plain)) && return plain
    (plain isa ConcreteReference && plain.head isa FieldReferenceStep &&
     plain.head.name == "content") ? plain.tail : nothing
end

# The path in the drawing of the content that a path of the output names, or
# `nothing` when it does not go into that drawing.
function _find_content_drawing_path(reference)
    plain = strip_reference_types(reference)
    plain isa ConcreteReference && plain.head isa FieldReferenceStep && plain.head.name == "elements" || return nothing
    rest = plain.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep && rest.head.start == 1 &&
     rest.head.stop == 2) ? rest.tail : nothing
end

# Whether `reference` is one flat step of a text: a caret, a range or a box.
_is_flat_text_place(reference) =
    reference isa ConcreteReference && reference.tail isa EmptyReference &&
    reference.head isa Union{TextRangeReferenceStep, TextSpanReferenceStep}
