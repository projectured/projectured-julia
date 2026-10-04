# Fragment of `GestureLogModule`.
#
# Projects a [`GestureLog`](GestureLogDocument.jl) onto a `SyntaxNode` for display: one
# line per entry, newest line first, so the newest line always sits at the same
# place and the panel does not move under the eye of the user.
#
# Each line holds three parts with their own style: the index, the gesture and the
# operation. A line that records a selection operation is muted, because a
# selection is context and not a change.
#
# The default colors suit the light background of a tab. The overlay panel has a
# dark background, so [`make_gesture_log_panel_syntax_projection`](GestureLogOverlay.jl)
# gives it light colors.
#
# The panel uses the DejaVu monospace font, which has a glyph for the arrow keys
# and for the empty reference. The Ubuntu font has neither, and a glyph drawn by
# a fallback font has a width of its own, so the columns would not line up.
#
# Read-only. There is nothing to author here, so this is a plain leaf printer with
# no reader and no reference mappers.
#
# The projection holds its styles and no theme; `make_gesture_log_projection`
# fills them from a theme.
@projection UntrackedCell struct GestureLogToSyntax
    index_text::StyleText = get_gesture_log_style(nothing, :index_text)
    gesture_text::StyleText = get_gesture_log_style(nothing, :gesture_text)
    operation_text::StyleText = get_gesture_log_style(nothing, :operation_text)
    muted_text::StyleText = get_gesture_log_style(nothing, :muted_text)
    empty_text::StyleText = get_gesture_log_style(nothing, :empty_text)
    # The most characters of an operation that a line shows. A longer operation is
    # cut, and ends in `…`. The font is monospaced, so this bounds the width too.
    operation_width::Int = typemax(Int)
end

"""
    make_gesture_log_projection(; theme = nothing, operation_width = typemax(Int)) -> GestureLogToSyntax

The projection of a gesture log, with the styles of `theme`: a `GestureLogTheme`,
scaled or not, or the default styles for `nothing`. `operation_width` is the most
characters of an operation that a line shows.
"""
function make_gesture_log_projection(; theme = nothing, operation_width::Integer = typemax(Int))
    get_style(name) = get_gesture_log_style(theme, name)
    GestureLogToSyntax(; index_text = get_style(:index_text), gesture_text = get_style(:gesture_text),
                       operation_text = get_style(:operation_text), muted_text = get_style(:muted_text),
                       empty_text = get_style(:empty_text), operation_width = Int(operation_width))
end

# The width of the gesture column, in characters. The font is monospaced, so a
# padded string aligns the operations of every line.
const _GESTURE_WIDTH = 18

"""
    print_document(p::GestureLogToSyntax, recursion, log::GestureLog, ctx)

One `SyntaxNode` per entry, joined by newlines. The children are derived, not
copied: the outer node reads `log.entries` inside a computed `CellVector`, so an
append rebuilds the lines and the panel that shows them.
"""
function print_document(p::GestureLogToSyntax, recursion, log::GestureLog, ctx::PrinterContext)
    children = CellVector(Computation(function ()
        entries = log.entries
        isempty(entries) && return SyntaxDocument[SyntaxLeaf(TextString("no gesture yet", p.empty_text))]
        lines = SyntaxDocument[]
        for index in length(entries):-1:1
            push!(lines, _line(p, entries[index]))
        end
        lines
    end))
    SimpleIoMap(p, log, SyntaxNode(children; sep=TextString("\n")))
end

# One line: "  12  Ctrl+C            set .entries[1].value = 1".
function _line(p::GestureLogToSyntax, entry::GestureLogEntry)
    muted = entry.kind === :ReplaceSelectionOperation
    gesture_style = muted ? p.muted_text : p.gesture_text
    operation_style = muted ? p.muted_text : p.operation_text
    SyntaxNode(SyntaxDocument[
        SyntaxLeaf(TextString(lpad(string(entry.index), 4) * "  ", p.index_text)),
        SyntaxLeaf(TextString(rpad(entry.gesture, _GESTURE_WIDTH) * "  ", gesture_style)),
        SyntaxLeaf(TextString(_cut_text(entry.operation, p.operation_width), operation_style)),
    ])
end

_cut_text(text::AbstractString, width::Integer) =
    length(text) <= width ? String(text) : string(first(text, max(0, width - 1)), "…")

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw a gesture log. The factory form, so every
# renderer builds its own projection instance.

function __init__()
    register_natural_syntax!(:gesturelog, (; appearance) -> Pair{Type,Any}[
        GestureLog => make_gesture_log_projection(; theme = get_scaled_theme!(appearance, GestureLogTheme))])
end
