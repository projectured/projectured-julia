"""
    CommandPaletteToSyntaxModule

Projects a [`CommandPalette`](CommandPalette.jl) onto a `SyntaxNode` for display:
the type-in line, then one line per matching command, reusing the existing
`SyntaxToText → TextToGraphics` pipeline the help window already uses.

Read-only. The palette's own decorator owns every key, so there is no reader here
and no reference mapping — a palette line is a label, not a place a selection can
land.

The children are a reactive thunk, not a fixed vector: `print_document` runs once,
and the palette re-derives on every keystroke. A captured list would freeze the
render at the moment the palette opened.
"""
module CommandPaletteToSyntaxModule

import ..ProjectionApiModule: print_document, Projection
import ..ProjectionModule: var"@projection"
import ..IoMapModule: SimpleIoMap
import ..CommandPaletteModule: CommandPalette, get_command_palette_matches,
                               get_command_palette_selected
import ..TextModule: TextString
import ..StyleModule: font_dejavu_monospace_regular_20, font_dejavu_monospace_bold_20
import ..StyleModule: color_solarized_blue, color_solarized_green, color_solarized_gray,
                      color_solarized_violet, color_default
import ..StyleModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..PrinterContextModule: PrinterContext

export CommandPaletteToSyntax

# DejaVu, not Ubuntu: the palette writes the caret and the row marker as chevron
# glyphs, and SDL draws a tofu box for a glyph the font lacks — it does no
# fallback. Ubuntu Mono lacks both.
@projection struct CommandPaletteToSyntax
    query::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_bold_20, color_solarized_blue)
    # A group heading is not the text the user typed, so it must not look like it.
    # Violet reads as structure beside the blue query, and stays clear of the green
    # of the chosen row and the gray of a row that cannot run.
    header::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_bold_20, color_solarized_violet)
    selected::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_bold_20, color_solarized_green)
    command::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_20, color_default)
    muted::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
end

# The caret sits at the end of the query: the palette has one selection and it names
# the chosen row, so there is no caret to move inside the text.
_query_line(doc) = string("> ", doc.query, "▏")

# "<marker><what it does>   [<gesture>]   (not now)". A row the palette cannot run
# still earns its line: it names what exists and shows the key that reaches it. The
# domain is not repeated per line — it is the heading above the group.
function _command_line(row, marked::Bool)
    # The marker occupies the indent rather than replacing it, so the chosen row's
    # text starts in the same column as every other row's.
    string(marked ? "  ▸ " : "    ", row.description,
           isempty(row.gesture) ? "" : string("   [", row.gesture, "]"),
           row.operation === nothing ? "   (not now)" : "")
end

# The heading that opens a domain's group. An unlabelled reader has no name to show,
# so its rows gather under one honest heading rather than under someone else's.
_domain_line(domain) = isempty(domain) ? "  (unlabelled)" : string("  ", domain)

function print_document(p::CommandPaletteToSyntax, recursion, doc::CommandPalette, ctx::PrinterContext)
    children = () -> begin
        lines = SyntaxDocument[SyntaxLeaf(TextString(_query_line(doc), p.query))]
        matches = get_command_palette_matches(doc)
        if isempty(matches)
            push!(lines, SyntaxLeaf(TextString("  no command matches", p.muted)))
        end
        selected = get_command_palette_selected(doc)
        # `get_command_palette_matches` returns the rows grouped by domain, so a heading
        # goes in wherever the domain changes — the same shape the help window has.
        # A heading is display only: the selection names a row of `rows`, and a step
        # walks the matching rows, so headings never take a turn.
        last_domain = nothing
        for i in matches
            row = doc.rows[i]
            if row.domain != last_domain
                push!(lines, SyntaxLeaf(TextString(_domain_line(row.domain), p.header)))
                last_domain = row.domain
            end
            marked = i == selected
            style = row.operation === nothing ? p.muted : marked ? p.selected : p.command
            push!(lines, SyntaxLeaf(TextString(_command_line(row, marked), style)))
        end
        lines
    end
    SimpleIoMap(p, doc, SyntaxNode(children; sep=TextString("\n")))
end

end # module
