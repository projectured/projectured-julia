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
import ..CommandPaletteModule: CommandPalette, command_palette_matches,
                               command_palette_selected
import ..TextModule: TextString
import ..FontModule: font_dejavu_monospace_regular_20, font_dejavu_monospace_bold_20
import ..ColorModule: color_solarized_blue, color_solarized_green, color_solarized_gray,
                      color_default
import ..StyleTextModule: StyleText, DStyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..PrinterContextModule: PrinterContext

export CommandPaletteToSyntax

# DejaVu, not Ubuntu: the palette writes the caret and the row marker as chevron
# glyphs, and SDL draws a tofu box for a glyph the font lacks — it does no
# fallback. Ubuntu Mono lacks both.
@projection struct CommandPaletteToSyntax
    query::ImmutableCell{DStyleText} = StyleText(font_dejavu_monospace_bold_20, color_solarized_blue)
    selected::ImmutableCell{DStyleText} = StyleText(font_dejavu_monospace_bold_20, color_solarized_green)
    command::ImmutableCell{DStyleText} = StyleText(font_dejavu_monospace_regular_20, color_default)
    muted::ImmutableCell{DStyleText} = StyleText(font_dejavu_monospace_regular_20, color_solarized_gray)
end

# The caret sits at the end of the query: the palette has one selection and it names
# the chosen row, so there is no caret to move inside the text.
_query_line(doc) = string("> ", doc.query, "▏")

# "<marker><what it does>   [<gesture>]   (key only)". A row the palette cannot run
# still earns its line: it tells the user which key does the job.
function _command_line(row, marked::Bool)
    string(marked ? "▸ " : "  ", row.description,
           isempty(row.gesture) ? "" : string("   [", row.gesture, "]"),
           row.runnable ? "" : "   (key only)")
end

function print_document(p::CommandPaletteToSyntax, recursion, doc::CommandPalette, ctx::PrinterContext)
    children = () -> begin
        lines = SyntaxDocument[SyntaxLeaf(TextString(_query_line(doc), p.query))]
        matches = command_palette_matches(doc)
        if isempty(matches)
            push!(lines, SyntaxLeaf(TextString("  no command matches", p.muted)))
        end
        selected = command_palette_selected(doc)
        for i in matches
            row = doc.rows[i]
            marked = i == selected
            style = !row.runnable ? p.muted : marked ? p.selected : p.command
            push!(lines, SyntaxLeaf(TextString(_command_line(row, marked), style)))
        end
        lines
    end
    SimpleIoMap(p, doc, SyntaxNode(children; sep=TextString("\n")))
end

end # module
