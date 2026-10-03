# Fragment of `MessageLogModule`.
#
# Projects a [`MessageLog`](MessageLogDocument.jl) onto a `SyntaxNode` for
# display: one line per entry, newest line first, so the newest line always
# sits at the same place and the panel does not move under the eye of the
# user.
#
# Each line holds two parts with their own style: the level and the message.
# The colors suit the light background of a tab.
#
# The panel uses the DejaVu monospace font, which has a glyph for every
# character a log message needs. The Ubuntu font falls back for some of them,
# and a glyph drawn by a fallback font has a width of its own, so the columns
# would not line up.
#
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.
@projection UntrackedCell struct MessageLogToSyntax
    theme::Any = nothing
    level_text::StyleText = _get_messagelog_style(theme, :level_text)
    error_level_text::StyleText = _get_messagelog_style(theme, :error_level_text)
    warning_level_text::StyleText = _get_messagelog_style(theme, :warning_level_text)
    debug_level_text::StyleText = _get_messagelog_style(theme, :debug_level_text)
    message_text::StyleText = _get_messagelog_style(theme, :message_text)
    empty_text::StyleText = _get_messagelog_style(theme, :empty_text)
end

# The width of the level column, in characters. The font is monospaced, so a
# padded string aligns the messages of every line.
const _LEVEL_WIDTH = 7

"""
    print_document(p::MessageLogToSyntax, recursion, log::MessageLog, ctx)

One `SyntaxNode` per entry, joined by newlines. The children are derived, not
copied: the outer node reads `log.entries` inside a computed `CellVector`, so an
append rebuilds the lines and the panel that shows them.
"""
function print_document(p::MessageLogToSyntax, recursion, log::MessageLog, ctx::PrinterContext)
    children = CellVector(Computation(function ()
        entries = log.entries
        isempty(entries) && return SyntaxDocument[SyntaxLeaf(TextString("no message yet", p.empty_text))]
        lines = SyntaxDocument[]
        for index in length(entries):-1:1
            push!(lines, _line(p, entries[index]))
        end
        lines
    end))
    SimpleIoMap(p, log, SyntaxNode(children; sep=TextString("\n")))
end

# The style of a level: an error, a warning and a message for debugging each have
# their own, and every other level the one of information.
function _get_level_text(p::MessageLogToSyntax, level::AbstractString)
    name = lowercase(level)
    startswith(name, "error") ? p.error_level_text :
    startswith(name, "warn")  ? p.warning_level_text :
    startswith(name, "debug") ? p.debug_level_text :
                                p.level_text
end

# One line: "Info     hello from the log view".
function _line(p::MessageLogToSyntax, entry::MessageLogEntry)
    SyntaxNode(SyntaxDocument[
        SyntaxLeaf(TextString(rpad(entry.level, _LEVEL_WIDTH) * "  ", _get_level_text(p, entry.level))),
        SyntaxLeaf(TextString(entry.message, p.message_text)),
    ])
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw a message log. The factory form, so every
# renderer builds its own projection instance.

function __init__()
    register_natural_syntax!(:messagelog, (; appearance) -> Pair{Type,Any}[
        MessageLog => MessageLogToSyntax(; theme = get_scaled_theme!(appearance, MessageLogTheme))])
end
