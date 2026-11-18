# Fragment of `TextModule`.
#
# A view of a text, and the projection that draws it. The text is content: it says
# what is written, and every view of it shows the same lines. A view keeps the state
# of one view: its caret and the part under the pointer, the folds that it closes,
# and its look, which is whether its lines wrap at the width they are offered and
# the distance of its lines. Two views of one text keep two carets; two places that
# show one view show its one caret.

"""
    TextView(viewed::TextBlock, wrap = false, line_spacing = nothing, closed_folds = nothing)

A view of the text `viewed`. Its `selection` is the caret of this view: a flat
place in `viewed`, a `TextRangeReferenceStep` caret or range, or a whole-element
`TextSpanReferenceStep`. The path ends at the view and never enters `viewed`, so
another view of the same text keeps a caret of its own. A place that shows the
view shows its caret, so two places of one view share it; the caret is live at the
place that the live selection reaches, and dormant at any other. The view keeps
its caret while the focus is elsewhere, as a dormant selection.

`wrap` says whether its lines break at the width that the view is offered (`true`),
or keep each line whole (`false`). `line_spacing` is the `LineSpacing` of its
lines, or `nothing` for the spacing that the printer of the lines gives. A table of
rules chooses by the type of a document and so gives the same look to every
document of that type; a view gives the look to one text. `wrap` and `line_spacing`
may be cells, so a field that follows another document keeps the view in step with
it.

`closed_folds` are the folds of the text that this view closes, or `nothing`:
`TextFolding` hides their lines in this view only. The view of the text of a node
of syntax computes them from the folds of the views of the nodes.

`TextViewToGraphicsCanvas` draws the view over the drawing of its content.

# Example

    view = TextView(TextBlock(TextLine(TextString("alpha beta"))), true)
"""
@content_view TextBlock struct TextView <: ContentView
    wrap::Bool = false
    line_spacing::Any = nothing
    closed_folds::Any = nothing
end

_find_edited_text(view::TextView) = view.viewed

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

"""
    TextViewToGraphicsCanvas(; theme = nothing)

Draw a `TextView`: the drawing of its content, which the recursion prints, and over
it the band under the selection of the view and its caret. `theme` is a
`TextTheme`, scaled or not, whose caret and band it draws; with `nothing`, those of
the default theme. A dormant caret is drawn muted, and so is the caret of a view at
a place that the live selection does not reach (`is_live_place`).

The content prints in a context that holds the look of the view: the line spacing
of the view where it sets one, and a free width when the view does not wrap, so a
stage that breaks lines where the context gives a width keeps each line whole. The
last stage of the print of the content is `TextBlockToGraphicsCanvas`, which lays
out the lines; a stage before it, such as `WordWrapping`, maps a place of the text
to a place of the lines that it gives. The projection holds no projection: the
table that draws the view gives the stages to the recursion.

The caret of the view maps forward through the IO map of the content, and a point
maps back through it to a caret of the view. The keys are the keys of the view
(`@gestures TextView`); Up, Down, Home, End and the page keys read the layout of
the lines. A press puts the caret at its point and starts a drag, which moves the
moving end of the selection; a double click selects a word, and a triple click a
line.
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
content of the view, which the look of the view makes again when it changes.
"""
@iomap struct TextViewToGraphicsCanvasIoMap
    projection::Any
    input::TextView
    output::GraphicsCanvas
    content::Any
end

find_first_baseline(iomap::TextViewToGraphicsCanvasIoMap) =
    find_first_baseline(_find_text_layout(iomap.content).lines)

# The output is the band, the drawing of the content and the caret, in this order,
# so the content is its second element, at the place of the view.
const _TEXT_VIEW_CONTENT_STEP =
    ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(1, 2), EmptyReference()))

function print_document(p::TextViewToGraphicsCanvas, recursion, view::TextView, ctx)
    # The look is read inside the cell, so a change of it prints the content again.
    content = Cell(@computation begin
        wrap = view.wrap
        line_spacing = view.line_spacing
        viewed = view.viewed
        run_without_cell_tracking(() -> print_child(recursion, viewed, _make_look_context(ctx, wrap, line_spacing)))
    end)
    # The marks read the stored selection, live or dormant, so a dormant caret has a
    # place on the screen too; `is_live` decides how it is painted.
    selection_cell = getfield(view, :selection)
    overlay = Cell(Computation(function ()
        layout = _find_text_layout(content[])
        _compute_selection_marks(layout.lines, _map_to_layout(layout, _get_stored_path(selection_cell[])))
    end))
    is_live = Cell(@computation _is_live_selection(selection_cell[]) && is_live_place(ctx))
    marks = _make_selection_marks(p, overlay, is_live, ctx === nothing ? (0, 0, 0, 0) : ctx.space)
    drawing = Cell(@computation content[].output)
    elements = CellVector(Cell[Cell(marks.band), drawing, Cell(marks.caret)])
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            Cell(@computation Int32(drawing[].w)), Cell(@computation Int32(drawing[].h)),
                            elements, layout_none, true, Cell(nothing))
    TextViewToGraphicsCanvasIoMap(p, view, canvas, content)
end

# The context of the content of a view: the step `viewed`, the line spacing of the
# view where it sets one, and a free width when the lines do not wrap. The space of
# the context stays.
function _make_look_context(ctx, wrap::Bool, line_spacing)
    look = make_child_context(ctx === nothing ? PrinterContext() : ctx, FieldReferenceStep("viewed"))
    wrap || (look = with_free_axis(look, :x; space = look.space))
    line_spacing === nothing ? look : with_property(look, :line_spacing, line_spacing)
end

# ── The layout of the lines ─────────────────────────────────────────────────

# The IO maps of the stages that print the content of a view, the first first: a
# chain gives the IO map of each of its stages, and a nesting those of what it
# nests.
_collect_text_stages(iomap::ChainingIoMap) =
    reduce(vcat, Any[_collect_text_stages(unwrap_cell(stage)) for stage in iomap.step_iomaps]; init = Any[])
_collect_text_stages(iomap::NestingIoMap) = _collect_text_stages(iomap.child_iomap)
_collect_text_stages(iomap) = Any[iomap]

# The layout of the lines in `content`, the IO map of the print of the content of a
# view: `lines`, the IO map of its last stage, which `TextBlockToGraphicsCanvas`
# prints, and `before`, the IO maps of the stages before it.
function _find_text_layout(content)
    stages = _collect_text_stages(content)
    lines = last(stages)
    lines isa TextBlockToGraphicsCanvasIoMap || throw(ArgumentError(
        "TextViewToGraphicsCanvas draws its caret over a content that TextBlockToGraphicsCanvas " *
        "prints; the recursion printed it with $(typeof(lines.projection))"))
    (lines = lines, before = stages[1:(end - 1)])
end

# A place of the content of a view, as a place of the lines that `layout` laid out:
# each stage before the layout maps it forward.
function _map_to_layout(layout, place)
    for stage in layout.before
        place isa Reference || return nothing
        place = map_reference_forward(stage.projection, stage, place)
    end
    place
end

# An operation on the lines that `layout` laid out, as an operation on the content
# of the view: each stage before the layout reads it, the last first.
function _read_from_layout(layout, operation)
    for stage in Iterators.reverse(layout.before)
        operation isa Operation || return nothing
        operation = read_intent(stage.projection, nothing, Intent(operation), stage).operation
    end
    operation
end

# ── Maps ────────────────────────────────────────────────────────────────────

# A place of the view: its own caret, range or box, or a place in its content, maps
# through the IO map of the content to the drawing of the content.
function map_reference_forward(::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, reference)
    place = _find_text_view_place(reference)
    place isa EmptyReference && return place
    place === nothing && return nothing
    content = iomap.content
    image = map_reference_forward(content.projection, content, place)
    image === nothing ? nothing : concat_references(_TEXT_VIEW_CONTENT_STEP, image)
end

# A point, or a path into the drawing of the content, maps back through the IO map
# of the content to a place of the text, which is the caret of the view.
function map_reference_backward(::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, reference)
    point = find_reference_point(reference)
    inner = point !== nothing ? reference : _find_content_drawing_path(reference)
    inner === nothing && return nothing
    content = iomap.content
    place = map_reference_backward(content.projection, content, inner)
    place === nothing ? nothing : strip_reference_types(place)
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

# ── Readers ─────────────────────────────────────────────────────────────────

read_gesture(::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, evt::KeyPress; answer = nothing) =
    answer === nothing ? (read_gesture(iomap.input, evt)) : nothing

# A key of the table of the view, and else a key that the layout of the lines
# answers, read against the caret of the view.
function read_gesture(p::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, evt::KeyDown; answer = nothing)
    answer === nothing || return nothing
    view = iomap.input
    operation = read_gesture(view, evt)
    operation === nothing || return operation
    layout = _find_text_layout(iomap.content)
    lines = layout.lines
    _read_from_layout(layout, _read_geometry_key(lines.projection, lines, lines.input,
                                                 _map_to_layout(layout, view.selection), evt))
end

# A single click is the caret of the view at its point, as the press before it put
# it; with Shift, the moving end of the selection goes to the point. A double click
# selects the word at the point, and a triple click the line. An Alt+click is the
# caret at the point too.
function read_gesture(p::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, evt::MouseClick; answer = nothing)
    answer === nothing || return nothing
    evt.button === :left || return nothing
    if evt.count >= 2 && !evt.modifiers.alt
        layout = _find_text_layout(iomap.content)
        lines = layout.lines
        return _read_from_layout(layout, _make_unit_selection(lines.projection, lines, evt.x, evt.y, evt.count))
    end
    _read_pointer_selection(iomap, evt.x, evt.y, evt.modifiers.shift && !evt.modifiers.alt)
end

# A left press with no Alt and no Ctrl: the caret at the point, or with Shift the
# moving end of the selection there, and the view takes the pointer for a drag, so
# each move of the drag goes to the view wherever the pointer is. The drag names
# the view as a whole, which each projection above maps back to its input.
function read_gesture(p::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, evt::MouseDown; answer = nothing)
    answer === nothing || return nothing
    evt.button === :left || return nothing
    (evt.modifiers.alt || evt.modifiers.ctrl || evt.modifiers.meta) && return nothing
    selection = _read_pointer_selection(iomap, evt.x, evt.y, evt.modifiers.shift)
    selection === nothing && return nothing
    CompoundOperation(Any[selection, StartDragOperation(EmptyReference(), nothing)])
end

# A move and the end of a drag that a press on the view started: the moving end of
# the selection goes to the character nearest to the point, and the anchor stays
# where the press put it.
read_gesture(p::TextViewToGraphicsCanvas, iomap::TextViewToGraphicsCanvasIoMap, evt::Union{DragMove,DragEnd}; answer = nothing) =
    answer === nothing ? (_read_pointer_selection(iomap, evt.x, evt.y, true)) : nothing

# The selection of the view that a pointer at `(x, y)` makes: the caret there, or
# with `extend` the range from the anchor of the selection of the view to the caret
# there.
function _read_pointer_selection(iomap::TextViewToGraphicsCanvasIoMap, x::Int, y::Int, extend::Bool)
    layout = _find_text_layout(iomap.content)
    lines = layout.lines
    path = _find_pointer_selection(lines.projection, lines, x, y, extend,
                                   _map_to_layout(layout, iomap.input.selection))
    path === nothing ? nothing : _read_from_layout(layout, ReplaceSelectionOperation(path))
end
