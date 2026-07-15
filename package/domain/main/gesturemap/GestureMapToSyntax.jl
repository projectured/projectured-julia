"""
    GestureMapToSyntaxModule

Projects a [`GestureMap`](../../document/GestureMap.jl) onto a `SyntaxNode` for
display: one line per gesture row, grouped under a heading per domain, reusing the
existing `SyntaxToText → TextToGraphics` pipeline. Read-only — there are no
authoring gestures to invert — so it is a plain leaf printer with no reader or
reference mappers.

Greyed (not-applicable) rows are styled muted and tagged, the v1 of the Lisp
`accessible` colouring: a row that cannot fire for the current selection is shown
but dimmed.
"""
module GestureMapToSyntaxModule

import ..CellModule: Cell
import ..ProjectionApiModule: print_document, Projection
import ..ProjectionModule: var"@projection"
import ..IoMapModule: SimpleIoMap
import ..GestureMapModule: GestureMap, GestureRow
import ..TextModule: TextString
import ..FontModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: color_solarized_blue, color_solarized_green, color_solarized_gray, color_default
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..PrinterContextModule: PrinterContext

export GestureMapToSyntax

@projection struct GestureMapToSyntax
    header::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    gesture::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_green)
    description::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_default)
    muted::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# One leaf per row ("<gesture> — <description>"), preceded by a domain heading
# whenever the domain changes; joined by newlines so the Syntax→Text layer lays it
# out as a vertical list.
function print_document(p::GestureMapToSyntax, recursion, doc::GestureMap, ctx::PrinterContext)
    children = SyntaxDocument[]
    last_domain = nothing
    for row in doc.rows
        if row.domain != last_domain
            push!(children, SyntaxLeaf(TextString(row.domain, p.header)))
            last_domain = row.domain
        end
        gesture_style = row.applicable ? p.gesture : p.muted
        desc_style = row.applicable ? p.description : p.muted
        suffix = row.applicable ? "" : "  (n/a)"
        # gesture cell + connective + description cell, all in one leaf's value.
        text = string("  ", row.gesture, " — ", row.description, suffix)
        push!(children, SyntaxLeaf(TextString(text, desc_style)))
    end
    out = SyntaxNode(children; sep=TextString("\n"))
    return SimpleIoMap(p, doc, out)
end

end # module
