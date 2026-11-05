# Fragment of `TextModule`.
#
# A view of a text, and the projection that draws it. The text is content: it says
# what is written. A view holds the look of one showing of it: whether its lines
# wrap at the width they are offered, and the distance of its lines. A table of
# rules chooses by the type of a document and so gives the same look to every
# document of that type; a view gives the look to one text.
#
# The selection stays on the block: the caret of the text is a place in `content`,
# and a move of the caret changes only the cell of the block. The selection of the
# view is that place, with the step `content` in front, so a reference of the view
# reaches the block through the view.

"""
    TextView(content::TextBlock, wrap = false, line_spacing = SingleSpacing())

A view of the text `content`. `wrap` says whether its lines break at the width that
the view is offered (`true`), or keep each line whole (`false`). `line_spacing` is
the `LineSpacing` of its lines. The view draws no caret of its own: its `selection`
and its `mouse_target` are the paths of `content`, with the step `content` in
front. A person edits the text through the view: the keys and the pointer go to
the block, and what they answer names `content`.

`make_text_view` makes a view whose paths follow those of its block.
`TextViewToGraphics` draws it.

# Example

    view = make_text_view(TextBlock(TextLine(TextString("alpha beta"))); wrap = true)
"""
@document struct TextView
    content::TextBlock
    wrap::Bool = false
    line_spacing::Any = SingleSpacing()
end

get_edited_field(::TextView) = :content

"""
    make_text_view(content; wrap = false, line_spacing = SingleSpacing()) -> TextView

A [`TextView`](@ref) of the block `content`, whose selection and part under the
pointer are the paths of `content` with the step `content` in front. `wrap` and
`line_spacing` may be cells, so a field that follows another document keeps the
view in step with it.
"""
function make_text_view(content::TextBlock; wrap = false, line_spacing = SingleSpacing())
    view = TextView(content, wrap, line_spacing)
    set_output_path_computations!(view, content, path -> ConcreteReference(FieldReferenceStep("content"), path))
    view
end

# ── Projection ──────────────────────────────────────────────────────────────

"""
    TextViewToGraphics()

Draw a [`TextView`](@ref): the graphics of its `content`, which the recursion
prints, in a context that holds the look of the view. The context sets the line
spacing of the view, and a free width when the view does not wrap, so a text
printer that breaks lines where the context gives a width keeps each line whole.
The projection holds no text printer; the table that draws the view gives one to
the recursion.

A reference of the view starts with the step `content`. On the way forward the
step comes off, and the rest maps through the IO map of the block; on the way back
the other way, and the step goes on again. A key and a gesture go to the IO map of
the block, and what they answer names the block through the step `content`.
"""
struct TextViewToGraphics <: Projection end

"""
    TextViewToGraphicsIoMap(projection, input, output, content_iomap)

`input` is the `TextView`. `content_iomap` is the IO map of its block, printed
through the recursion; `output` is the graphics of that IO map.
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
        content = view.content
        run_without_cell_tracking(() -> print_child(recursion, content,
                                                    _make_look_context(ctx, wrap, line_spacing)))
    end)
    TextViewToGraphicsIoMap(p, view, Cell(@computation content_iomap[].output), content_iomap)
end

# The context of the block of a view: the step `content`, the line spacing of the
# view, and a free width when the lines do not wrap. The space of the context stays.
function _make_look_context(ctx, wrap::Bool, line_spacing)
    look = make_child_context(ctx === nothing ? PrinterContext() : ctx, FieldReferenceStep("content"))
    wrap || (look = with_free_axis(look, :x; space = look.space))
    with_property(look, :line_spacing, line_spacing === nothing ? SingleSpacing() : line_spacing)
end

# ── The step `content` ──────────────────────────────────────────────────────

# The rest of a reference of the view after its step `content`, or `nothing`.
function _strip_content_step(reference)
    reference isa Reference || return nothing
    stripped = strip_reference_types(reference)
    stripped isa ConcreteReference || return nothing
    head = get_reference_head(stripped)
    (head isa FieldReferenceStep && head.name == "content") || return nothing
    get_reference_tail(stripped)
end

function map_reference_forward(p::TextViewToGraphics, iomap::TextViewToGraphicsIoMap, reference)
    inner = _strip_content_step(reference)
    inner === nothing && return nothing
    content_iomap = iomap.content_iomap
    map_reference_forward(content_iomap.projection, content_iomap, inner)
end

function map_reference_backward(p::TextViewToGraphics, iomap::TextViewToGraphicsIoMap, reference)
    reference === nothing && return nothing
    content_iomap = iomap.content_iomap
    inner = map_reference_backward(content_iomap.projection, content_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end

# ── Readers ─────────────────────────────────────────────────────────────────

# A key or a gesture goes to the IO map of the block, which reads it against the
# lines and the caret of the block; the answer names the block, so it gets the step
# `content`.
function read_intent(::TextViewToGraphics, iomap::TextViewToGraphicsIoMap,
                     event::Union{Event, Gesture, CollectIntents})
    content_iomap = iomap.content_iomap
    answer = read_intent(content_iomap.projection, content_iomap, event)
    answer === nothing ? nothing : reroot_operation(answer, (FieldReferenceStep("content"),))
end
