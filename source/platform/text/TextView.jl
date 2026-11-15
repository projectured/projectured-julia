# Fragment of `TextModule`.
#
# A view of a text, and the projections that draw it. The text is content: it says
# what is written, and every view of it shows the same lines. A view keeps the state
# of one view: its caret and the part under the pointer, the folds that it closes,
# and its look, which is whether its lines wrap at the width they are offered and
# the distance of its lines. Two views of one text keep two carets; two places that
# show one view show its one caret.
#
# Two projections draw a view. `TextViewToGraphicsCanvas` draws a view that keeps
# its caret on itself, over the lines of its content. `TextViewToGraphics` draws the
# text of a widget, a view that `make_text_view` makes: its caret is a place in the
# block that it shows, and its selection is that place with the step `viewed` in
# front.

"""
    TextView(viewed::TextBlock, wrap = false, line_spacing = SingleSpacing(),
             closed_folds = nothing)

A view of the text `viewed`. Its `selection` is the caret of this view: a flat
place in `viewed`, a `TextRangeReferenceStep` caret or range, or a whole-element
`TextSpanReferenceStep`. The path ends at the view and never enters `viewed`, so
another view of the same text keeps a caret of its own. A place that shows the
view shows its caret, so two places of one view share it; the caret is live at the
place that the live selection reaches, and dormant at any other. The view keeps
its caret while the focus is elsewhere, as a dormant selection.

`wrap` says whether its lines break at the width that the view is offered (`true`),
or keep each line whole (`false`). `line_spacing` is the `LineSpacing` of its
lines. A table of rules chooses by the type of a document and so gives the same
look to every document of that type; a view gives the look to one text.

`closed_folds` are the folds of the text that this view closes, or `nothing`:
`TextFolding` hides their lines in this view only. The view of the text of a node
of syntax computes them from the folds of the views of the nodes.

`TextViewToGraphicsCanvas` draws the view over the drawing of its content.
`make_text_view` makes the view of the text of a widget, which `TextViewToGraphics`
draws.

# Example

    view = TextView(TextBlock(TextLine(TextString("alpha beta"))))
"""
@document struct TextView <: ContentView
    viewed::TextBlock
    wrap::Bool = false
    line_spacing::Any = SingleSpacing()
    closed_folds::Any = nothing
end

# The view of a text that a viewing step prints.
make_content_view(content::TextBlock) = TextView(content)

_find_edited_text(view::TextView) = view.viewed

"""
    make_text_view(viewed; wrap = false, line_spacing = SingleSpacing()) -> TextView

A [`TextView`](@ref) of the block `viewed` for the text of a widget: its selection
and its part under the pointer are the paths of `viewed` with the step `viewed` in
front, so the caret stays in the block and a move of the caret changes only the
cell of the block. `wrap` and `line_spacing` may be cells, so a field that follows
another document keeps the view in step with it. `TextViewToGraphics` draws it.
"""
function make_text_view(viewed::TextBlock; wrap = false, line_spacing = SingleSpacing())
    view = TextView(viewed, wrap, line_spacing)
    set_output_path_computations!(view, viewed, path -> ConcreteReference(FieldReferenceStep("viewed"), path))
    view
end

# The keys of a view: the keys of a text, read against the lines of its content and
# the caret of the view. Each edit and each motion is a flat place of the view, so
# its caret stays on the view.
@gestures TextView begin
    when(KeyPress(_, t), !any(iscntrl, t)) => "Insert character" => _text_insert(doc.viewed, t, doc.selection)
    KeyPress('\n';)        => "Break the line"       => _text_break(doc.viewed, doc.selection)
    KeyPress('\t';)        => "Indent"               => _text_indent(doc.viewed, doc.selection)
    KeyPress('\t'; shift)  => "Outdent"              => _text_outdent(doc.viewed, doc.selection)
    KeyDown(:period; ctrl) => "Toggle collapse"      => ToggleCollapseOperation()
    KeyDown(:backspace;)   => "Delete backward"      => _text_delete(doc.viewed, :backspace, doc.selection)
    KeyDown(:delete;)      => "Delete forward"       => _text_delete(doc.viewed, :delete, doc.selection)
    KeyDown(:backspace; ctrl) => "Delete a word backward" => _text_word_delete(doc.viewed, :backspace, doc.selection)
    KeyDown(:delete; ctrl)    => "Delete a word forward"  => _text_word_delete(doc.viewed, :delete, doc.selection)
    KeyDown(:home; ctrl)   => "Cursor to text start" => _text_jump(doc.viewed, :start)
    KeyDown(:end; ctrl)    => "Cursor to text end"   => _text_jump(doc.viewed, :end)
    KeyDown(:a; ctrl)      => "Select all"           => _text_select_all(doc.viewed)
    KeyDown(:left; ctrl)   => "Word left"            => _text_word_motion(doc.viewed, :left, doc.selection)
    KeyDown(:right; ctrl)  => "Word right"           => _text_word_motion(doc.viewed, :right, doc.selection)
    KeyDown(:left;)        => "Cursor left"          => _text_char_motion(doc.viewed, :left, doc.selection)
    KeyDown(:right;)       => "Cursor right"         => _text_char_motion(doc.viewed, :right, doc.selection)
    KeyDown(:left; shift)        => "Extend the selection left"         => _text_extend(doc.viewed, :left, doc.selection)
    KeyDown(:right; shift)       => "Extend the selection right"        => _text_extend(doc.viewed, :right, doc.selection)
    KeyDown(:left; ctrl, shift)  => "Extend the selection a word left"  => _text_extend(doc.viewed, :word_left, doc.selection)
    KeyDown(:right; ctrl, shift) => "Extend the selection a word right" => _text_extend(doc.viewed, :word_right, doc.selection)
    KeyDown(:home; ctrl, shift)  => "Extend the selection to the start" => _text_extend(doc.viewed, :start, doc.selection)
    KeyDown(:end; ctrl, shift)   => "Extend the selection to the end"   => _text_extend(doc.viewed, :end, doc.selection)
end

# ── A view that keeps its caret ─────────────────────────────────────────────

"""
    TextViewToGraphicsCanvas(; theme = nothing)

Draw a `TextView`: the drawing of its content, which the recursion prints with the
row of `TextBlock` (`TextBlockToGraphicsCanvas`), and over it the band under the
selection of the view and its caret. `theme` is a `TextTheme`, scaled or not, whose
caret and band it draws; with `nothing`, those of the default theme. A dormant
caret is drawn muted, and so is the caret of a view at a place that the live
selection does not reach (`is_live_place`).

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
    content = print_child(recursion, view.viewed, make_child_context(ctx, FieldReferenceStep("viewed")))
    content isa TextBlockToGraphicsCanvasIoMap || throw(ArgumentError(
        "TextViewToGraphicsCanvas draws its caret over a content that TextBlockToGraphicsCanvas " *
        "prints; the recursion printed it with $(typeof(content.projection))"))
    # The marks read the stored selection, live or dormant, so a dormant caret has a
    # place on the screen too; `is_live` decides how it is painted.
    selection_cell = getfield(view, :selection)
    overlay = Cell(@computation _compute_selection_marks(content, _get_stored_path(selection_cell[])))
    is_live = Cell(@computation _is_live_selection(selection_cell[]) && is_live_place(ctx))
    marks = _make_selection_marks(p, overlay, is_live, content.space)
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
# or box, or the tail of a path through `viewed`.
function _find_text_view_place(reference)
    plain = strip_reference_types(reference)
    (plain isa EmptyReference || _is_flat_text_place(plain)) && return plain
    (plain isa ConcreteReference && plain.head isa FieldReferenceStep &&
     plain.head.name == "viewed") ? plain.tail : nothing
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

# ── The text of a widget ────────────────────────────────────────────────────

"""
    TextViewToGraphics()

Draw a [`TextView`](@ref) that `make_text_view` made, the text of a widget: the
graphics of the block that it shows, which the recursion prints with the caret of
the block, in a context that holds the look of the view. The context sets the line
spacing of the view, and a free width when the view does not wrap, so a text
printer that breaks lines where the context gives a width keeps each line whole.
The projection holds no text printer; the table that draws the view gives one to
the recursion.

A reference of the view starts with the step `viewed`. On the way forward the
step comes off, and the rest maps through the IO map of the block; on the way back
the other way, and the step goes on again. A key and a gesture go to the IO map of
the block, and what they answer names the block through the step `viewed`.
"""
struct TextViewToGraphics <: Projection end

"""
    TextViewToGraphicsIoMap(projection, input, output, content_iomap)

`input` is the `TextView`. `content_iomap` is the IO map of the block that it
shows, printed through the recursion; `output` is the graphics of that IO map.
"""
@iomap struct TextViewToGraphicsIoMap
    projection::Any
    input::TextView
    output::Any
    content_iomap::Any
end

function print_document(p::TextViewToGraphics, recursion, view::TextView, ctx)
    # The look is read inside the cell, so a change of it prints the block again.
    content_iomap = Cell(@computation begin
        wrap = view.wrap
        line_spacing = view.line_spacing
        content = view.viewed
        run_without_cell_tracking(() -> print_child(recursion, content,
                                                    _make_look_context(ctx, wrap, line_spacing)))
    end)
    TextViewToGraphicsIoMap(p, view, Cell(@computation content_iomap[].output), content_iomap)
end

# The context of the block of a view: the step `viewed`, the line spacing of the
# view, and a free width when the lines do not wrap. The space of the context stays.
function _make_look_context(ctx, wrap::Bool, line_spacing)
    look = make_child_context(ctx === nothing ? PrinterContext() : ctx, FieldReferenceStep("viewed"))
    wrap || (look = with_free_axis(look, :x; space = look.space))
    with_property(look, :line_spacing, line_spacing === nothing ? SingleSpacing() : line_spacing)
end

# ── The step `viewed` ───────────────────────────────────────────────────────

# The rest of a reference of the view after its step `viewed`, or `nothing`.
function _strip_viewed_step(reference)
    reference isa Reference || return nothing
    stripped = strip_reference_types(reference)
    stripped isa ConcreteReference || return nothing
    head = get_reference_head(stripped)
    (head isa FieldReferenceStep && head.name == "viewed") || return nothing
    get_reference_tail(stripped)
end

function map_reference_forward(p::TextViewToGraphics, iomap::TextViewToGraphicsIoMap, reference)
    inner = _strip_viewed_step(reference)
    inner === nothing && return nothing
    content_iomap = iomap.content_iomap
    map_reference_forward(content_iomap.projection, content_iomap, inner)
end

function map_reference_backward(p::TextViewToGraphics, iomap::TextViewToGraphicsIoMap, reference)
    reference === nothing && return nothing
    content_iomap = iomap.content_iomap
    inner = map_reference_backward(content_iomap.projection, content_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("viewed"), inner)
end

# ── Readers ─────────────────────────────────────────────────────────────────

# A key or a gesture goes to the IO map of the block, which reads it against the
# lines and the caret of the block; the answer names the block, so it gets the step
# `viewed`.
function read_intent(::TextViewToGraphics, iomap::TextViewToGraphicsIoMap,
                     event::Union{Event, Gesture, CollectIntents})
    content_iomap = iomap.content_iomap
    answer = read_intent(content_iomap.projection, content_iomap, event)
    answer === nothing ? nothing : reroot_operation(answer, (FieldReferenceStep("viewed"),))
end
