# Fragment of `MessageLogModule`.
#
# Projects a [`MessageLog`](MessageLogDocument.jl) onto a `SyntaxNode` for
# display: one line per entry, newest line first, so the newest line always
# sits at the same place and the panel does not move under the eye of the
# user.
#
# Each line holds two parts with their own style: the level and the message.
#
# The panel uses the DejaVu monospace font, which has a glyph for every
# character a log message needs. The Ubuntu font falls back for some of them,
# and a glyph drawn by a fallback font has a width of its own, so the columns
# would not line up.
#
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.
@projection struct MessageLogToSyntax
    level::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    message::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_16, color_gray223)
    empty::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_16, color_solarized_gray)
end

# The width of the level column, in characters. The font is monospaced, so a
# padded string aligns the messages of every line.
const _LEVEL_WIDTH = 7

"""
    print_document(p::MessageLogToSyntax, recursion, log::MessageLog, ctx)

One `SyntaxNode` per entry, joined by newlines. The children are derived, not
copied: the outer node reads `log.entries` inside a `ComputedCellVector`, so an
append rebuilds the lines and the panel that shows them.
"""
function print_document(p::MessageLogToSyntax, recursion, log::MessageLog, ctx::PrinterContext)
    children = ComputedCellVector(function ()
        entries = log.entries
        isempty(entries) && return SyntaxDocument[SyntaxLeaf(TextString("no message yet", p.empty))]
        lines = SyntaxDocument[]
        for index in length(entries):-1:1
            push!(lines, _line(p, entries[index]))
        end
        lines
    end)
    SimpleIoMap(p, log, SyntaxNode(children; sep=TextString("\n")))
end

# One line: "Info     hello from the log view".
function _line(p::MessageLogToSyntax, entry::MessageLogEntry)
    SyntaxNode(SyntaxDocument[
        SyntaxLeaf(TextString(rpad(entry.level, _LEVEL_WIDTH) * "  ", p.level)),
        SyntaxLeaf(TextString(entry.message, p.message)),
    ])
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw a message log. The factory form, so every
# renderer builds its own projection instance.

function __init__()
    register_natural_syntax!(:messagelog, () -> Pair{Type,Any}[MessageLog => MessageLogToSyntax()])
end
