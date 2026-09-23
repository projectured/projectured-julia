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
@projection struct GestureLogToSyntax
    index::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    gesture::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    operation::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    muted::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    empty::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
end

# The width of the gesture column, in characters. The font is monospaced, so a
# padded string aligns the operations of every line.
const _GESTURE_WIDTH = 18

"""
    print_document(p::GestureLogToSyntax, recursion, log::GestureLog, ctx)

One `SyntaxNode` per entry, joined by newlines. The children are derived, not
copied: the outer node reads `log.entries` inside a `ComputedCellVector`, so an
append rebuilds the lines and the panel that shows them.
"""
function print_document(p::GestureLogToSyntax, recursion, log::GestureLog, ctx::PrinterContext)
    children = ComputedCellVector(function ()
        entries = log.entries
        isempty(entries) && return SyntaxDocument[SyntaxLeaf(TextString("no gesture yet", p.empty))]
        lines = SyntaxDocument[]
        for index in length(entries):-1:1
            push!(lines, _line(p, entries[index]))
        end
        lines
    end)
    SimpleIoMap(p, log, SyntaxNode(children; sep=TextString("\n")))
end

# One line: "  12  Ctrl+C            set .entries[1].value = 1".
function _line(p::GestureLogToSyntax, entry::GestureLogEntry)
    muted = entry.kind === :ReplaceSelectionOperation
    gesture_style = muted ? p.muted : p.gesture
    operation_style = muted ? p.muted : p.operation
    SyntaxNode(SyntaxDocument[
        SyntaxLeaf(TextString(lpad(string(entry.index), 4) * "  ", p.index)),
        SyntaxLeaf(TextString(rpad(entry.gesture, _GESTURE_WIDTH) * "  ", gesture_style)),
        SyntaxLeaf(TextString(entry.operation, operation_style)),
    ])
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw a gesture log. The factory form, so every
# renderer builds its own projection instance.

function __init__()
    register_natural_syntax!(:gesturelog, () -> Pair{Type,Any}[GestureLog => GestureLogToSyntax()])
    register_pred_type!(GestureLog)
end
