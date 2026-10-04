# Fragment of `UndoModule`.
#
# Projects the history of an [`UndoBuffer`](UndoDocument.jl) onto a `SyntaxNode`
# for a person to read. One line per step, newest at the top, with a marker line
# for where the document stands now: what is above the marker can be put back,
# what is below it can be taken back. The colors suit the light background of
# a tab.
#
# This is the projection of the buffer's OWN state, not of what it holds.
# [`UndoBufferToAnyProjection`](UndoBufferToAny.jl) is the transparent one that
# draws the document; this one draws the history beside it.
#
# The panel uses the DejaVu monospace font, which has a glyph for the empty
# reference. A glyph drawn by a fallback font has a width of its own, so the
# columns would not line up.
#
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.
#
# The projection holds its styles and no theme; `make_undo_projection` fills
# them from a theme.
@projection UntrackedCell struct UndoBufferToSyntax
    index_text::StyleText = get_undo_style(nothing, :index_text)
    step_text::StyleText = get_undo_style(nothing, :step_text)
    ahead_text::StyleText = get_undo_style(nothing, :ahead_text)
    marker_text::StyleText = get_undo_style(nothing, :marker_text)
    barrier_text::StyleText = get_undo_style(nothing, :barrier_text)
    empty_text::StyleText = get_undo_style(nothing, :empty_text)
end

"""
    make_undo_projection(; theme = nothing) -> UndoBufferToSyntax

The projection of the undo history, with the styles of `theme`: an `UndoTheme`,
scaled or not, or the default styles for `nothing`.
"""
function make_undo_projection(; theme = nothing)
    get_style(name) = get_undo_style(theme, name)
    UndoBufferToSyntax(; index_text = get_style(:index_text), step_text = get_style(:step_text),
                       ahead_text = get_style(:ahead_text), marker_text = get_style(:marker_text),
                       barrier_text = get_style(:barrier_text), empty_text = get_style(:empty_text))
end

# The width of the column that says what a line is, in characters. The font is
# monospaced, so a padded string aligns the labels of every line.
const _UNDO_KIND_WIDTH = 6

"""
    print_document(p::UndoBufferToSyntax, recursion, buffer::UndoBuffer, ctx)

One `SyntaxNode` per step, joined by newlines, with a marker line between what
can be put back and what can be taken back.

The children are derived, not copied: the outer node reads both lists inside a
computed `CellVector`, so a step that is recorded, taken back or put back rebuilds
the lines and the panel that shows them.
"""
function print_document(p::UndoBufferToSyntax, recursion, buffer::UndoBuffer, ctx::PrinterContext)
    children = CellVector(Computation(function ()
        undone = buffer.undo_entries
        redone = buffer.redo_entries
        lines = SyntaxDocument[]
        # Oldest first down to the one nearest the marker, so the next step to be
        # put back sits directly above where the document stands now.
        for index in 1:length(redone)
            push!(lines, _undo_line(p, redone[index], index, p.ahead_text, "redo"))
        end
        push!(lines, SyntaxLeaf(TextString(rpad("here", _UNDO_KIND_WIDTH) * "  " *
                                           "── the document stands here ──", p.marker_text)))
        # Newest first, so the next step to be taken back sits directly below.
        for index in length(undone):-1:1
            push!(lines, _undo_line(p, undone[index], index, p.step_text, "undo"))
        end
        isempty(undone) && isempty(redone) &&
            push!(lines, SyntaxLeaf(TextString("nothing to take back yet", p.empty_text)))
        lines
    end))
    SimpleIoMap(p, buffer, SyntaxNode(children; sep = TextString("\n")))
end

# One line: `undo    2  set .entries[1].value = "b"`. A barrier says so, and says
# it in its own colour, because the history stops there.
function _undo_line(p::UndoBufferToSyntax, entry::UndoEntry, index::Integer, style, kind)
    label = is_undo_barrier(entry) ? "stop" : kind
    text_style = is_undo_barrier(entry) ? p.barrier_text : style
    SyntaxNode(SyntaxDocument[
        SyntaxLeaf(TextString(rpad(label, _UNDO_KIND_WIDTH) * "  ", p.index_text)),
        SyntaxLeaf(TextString(lpad(string(index), 3) * "  ", p.index_text)),
        SyntaxLeaf(TextString(entry.label, text_style)),
    ])
end
