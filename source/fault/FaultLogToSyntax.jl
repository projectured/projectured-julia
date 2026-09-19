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
# The panel uses the DejaVu monospace font, which has a glyph for the warning
# sign. A glyph drawn by a fallback font has a width of its own, so the columns
# would not line up.
#
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.

"""
    FaultLogToSyntax(; count, site, origin, message, empty)

One `FaultLog` as a `SyntaxNode`, one line per fault.

See also `FaultLogOverlayProjection`, which puts it on the screen.
"""
@projection struct FaultLogToSyntax
    count::ImmutableCell{StyleText} =
        StyleText(font_dejavu_monospace_regular_16, color_gray159)
    site::ImmutableCell{StyleText} =
        StyleText(font_dejavu_monospace_regular_16, color_solarized_gray)
    origin::ImmutableCell{StyleText} =
        StyleText(font_dejavu_monospace_bold_16, color_solarized_red)
    message::ImmutableCell{StyleText} =
        StyleText(font_dejavu_monospace_regular_16, color_gray223)
    empty::ImmutableCell{StyleText} =
        StyleText(font_dejavu_monospace_regular_16, color_solarized_gray)
end

# The width of the two fixed columns, in characters. The font is monospaced, so
# a padded string aligns the message of every line.
const _COUNT_WIDTH = 6
const _SITE_WIDTH = 9

function print_document(p::FaultLogToSyntax, recursion, log::FaultLog,
                        ctx::PrinterContext)
    children = ComputedCellVector(function ()
        entries = log.entries
        isempty(entries) &&
            return SyntaxDocument[SyntaxLeaf(TextString("no fault", p.empty))]
        lines = SyntaxDocument[]
        for index in length(entries):-1:1
            push!(lines, _fault_line(p, entries[index]))
        end
        lines
    end)
    SimpleIoMap(p, log, SyntaxNode(children; sep = TextString("\n")))
end

# One line: "  3000  print    SyntaxToText  BoundsError: …".
function _fault_line(p::FaultLogToSyntax, entry::FaultLogEntry)
    SyntaxNode(SyntaxDocument[
        SyntaxLeaf(TextString(lpad(string(entry.count), _COUNT_WIDTH) * "  ", p.count)),
        SyntaxLeaf(TextString(rpad(String(entry.site), _SITE_WIDTH), p.site)),
        SyntaxLeaf(TextString(String(entry.origin) * "  ", p.origin)),
        SyntaxLeaf(TextString(entry.message, p.message)),
    ])
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw a fault log. The factory form, so every renderer
# builds its own projection instance.

# A fault log is not saved to a file, so it registers no `.pred` schema. It is
# runtime state that a person reads and then fixes what it points at.
function __init__()
    register_natural_syntax!(:fault, () -> Pair{Type,Any}[FaultLog => FaultLogToSyntax()])
end
