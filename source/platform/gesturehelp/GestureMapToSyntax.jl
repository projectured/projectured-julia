# Fragment of `GestureHelpModule`.
#
# Projects a `GestureMap` (`GestureMap.jl`, in this same directory) onto a `SyntaxNode` for
# display: one line per gesture row, grouped under a heading per domain, reusing the
# existing `SyntaxToText → TextToGraphics` pipeline. Read-only — there are no
# authoring gestures to invert — so it is a plain leaf printer with no reader or
# reference mappers.
#
# Greyed (not-applicable) rows are styled muted and tagged, the v1 of the Lisp
# `accessible` colouring: a row that cannot fire for the current selection is shown
# but dimmed.
#
# The projection holds its styles and no theme; `make_gesture_map_syntax_projection`
# fills them from a theme.
@projection UntrackedCell struct GestureMapToSyntax
    header::StyleText = get_gesture_help_style(nothing, :map_header_text)
    gesture::StyleText = get_gesture_help_style(nothing, :map_gesture_text)
    description::StyleText = get_gesture_help_style(nothing, :map_description_text)
    muted::StyleText = get_gesture_help_style(nothing, :map_muted_text)
end

"""
    make_gesture_map_syntax_projection(; theme = nothing) -> GestureMapToSyntax

The projection of a gesture map, with the styles of `theme`: a
`GestureHelpTheme`, scaled or not, or the default styles for `nothing`.
"""
function make_gesture_map_syntax_projection(; theme = nothing)
    get_style(name) = get_gesture_help_style(theme, name)
    GestureMapToSyntax(; header = get_style(:map_header_text), gesture = get_style(:map_gesture_text),
                       description = get_style(:map_description_text), muted = get_style(:map_muted_text))
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
        # A row with no operation cannot fire right now: its precondition failed,
        # or it needs the keystroke that carries its argument. That is the only
        # applicability answer there is, and it is the built operation itself.
        runnable = row.operation !== nothing
        gesture_style = runnable ? p.gesture : p.muted
        desc_style = runnable ? p.description : p.muted
        suffix = runnable ? "" : "  (n/a)"
        # gesture cell + connective + description cell, all in one leaf's value. A row
        # with no gesture reads "by name" in the gesture column: that is how a user
        # reaches it, from the command palette.
        text = string("  ", isempty(row.gesture) ? "by name" : row.gesture,
                      " — ", row.description, suffix)
        push!(children, SyntaxLeaf(TextString(text, desc_style)))
    end
    out = SyntaxNode(children; sep=TextString("\n"))
    return SimpleIoMap(p, doc, out)
end
