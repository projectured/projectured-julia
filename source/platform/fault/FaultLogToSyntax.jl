# Fragment of `FaultViewModule`.
#
# A [`FaultLog`](FaultDocument.jl) as a syntax node for display: one line per
# fault, newest first, so the newest line sits at the same place and the panel
# does not move under the eye of the user.
#
# Each line holds the count, where it was caught, what failed and what it said.
# The count is the column that matters: one bug across a large document is one
# line saying three thousand, not three thousand lines.
#
# The default colors suit a light background: a tab and the safe mode. The
# overlay panel has a dark background, so
# [`make_fault_log_panel_syntax_projection`](FaultLogOverlay.jl) gives it light
# colors.
#
# The panel uses the DejaVu monospace font, which has a glyph for the warning
# sign. A glyph drawn by a fallback font has a width of its own, so the columns
# would not line up.
#
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.

"""
    FaultLogToSyntax()

One `FaultLog` as a `SyntaxNode`, one line per fault. The projection holds its
styles and no theme; `make_fault_log_projection` fills them from a theme.

See also `FaultLogOverlayProjection`, which puts it on the screen.
"""
@projection UntrackedCell struct FaultLogToSyntax
    count_text::StyleText = get_fault_style(nothing, :count_text)
    site_text::StyleText = get_fault_style(nothing, :site_text)
    origin_text::StyleText = get_fault_style(nothing, :origin_text)
    message_text::StyleText = get_fault_style(nothing, :message_text)
    empty_text::StyleText = get_fault_style(nothing, :empty_text)
end

"""
    make_fault_log_projection(; theme = nothing) -> FaultLogToSyntax

The projection of a fault log, with the styles of `theme`: a `FaultTheme`,
scaled or not, or the default styles for `nothing`.
"""
function make_fault_log_projection(; theme = nothing)
    get_style(name) = get_fault_style(theme, name)
    FaultLogToSyntax(; count_text = get_style(:count_text), site_text = get_style(:site_text),
                     origin_text = get_style(:origin_text), message_text = get_style(:message_text),
                     empty_text = get_style(:empty_text))
end

# The width of the two fixed columns, in characters. The font is monospaced, so
# a padded string aligns the message of every line.
const _COUNT_WIDTH = 6
const _SITE_WIDTH = 9

function print_document(p::FaultLogToSyntax, recursion, log::FaultLog,
                        ctx::PrinterContext)
    children = CellVector(Computation(function ()
        entries = log.entries
        isempty(entries) &&
            return SyntaxDocument[SyntaxLeaf(TextString("no fault", p.empty_text))]
        lines = SyntaxDocument[]
        for index in length(entries):-1:1
            push!(lines, _fault_line(p, entries[index]))
        end
        lines
    end))
    SimpleIoMap(p, log, SyntaxNode(children; sep = TextString("\n")))
end

# One line: "  3000  print    SyntaxToText  BoundsError: …".
function _fault_line(p::FaultLogToSyntax, entry::FaultLogEntry)
    SyntaxNode(SyntaxDocument[
        SyntaxLeaf(TextString(lpad(string(entry.count), _COUNT_WIDTH) * "  ", p.count_text)),
        SyntaxLeaf(TextString(rpad(String(entry.site), _SITE_WIDTH), p.site_text)),
        SyntaxLeaf(TextString(String(entry.origin) * "  ", p.origin_text)),
        SyntaxLeaf(TextString(entry.message, p.message_text)),
    ])
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw a fault log. The factory form, so every renderer
# builds its own projection instance.

# A fault log is not saved to a file, so it registers no `.pred` schema. It is
# runtime state that a person reads and then fixes what it points at.
function __init__()
    register_natural_syntax!(:fault, (; appearance) -> Pair{Type,Any}[
        FaultLog => make_fault_log_projection(; theme = get_scaled_theme!(appearance, FaultTheme))])
end
