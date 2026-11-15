# Fragment of `SyntaxModule`.
#
# MarkedText → SyntaxLeaf projection. It draws a `MarkedText` as one leaf of a
# syntax tree, so a document that holds a marked text, such as a section of C++ in
# a test file, shows it in the colours of its marks among its other parts.

"""
    MarkedTextToSyntaxLeaf(; theme = nothing, style, appearance = nothing)

The projection of a `MarkedText` to a `SyntaxLeaf`: the value of the leaf is a
block with a line for each line of the string, each line split at the marks, and
each piece that a mark covers in the colour of the mark, as `MarkedTextToText`
draws it. The value is bound to the field `text`, so a key, Enter and a paste in
the block edit the string.

`style` is the font and the colour of a piece that no mark covers; its default
is the `plain_text` of the `TextTheme` `theme`. `appearance` resolves a mark that
names a role or a colour of the palette; with `nothing`, the default
`Appearance()` resolves it.

# Example

    TypeDispatchingProjection(Pair{Type,Any}[MarkedText => MarkedTextToSyntaxLeaf()])

See also `make_marked_text_lines`, which gives the lines of the block.
"""
@projection UntrackedCell struct MarkedTextToSyntaxLeaf
    style::StyleText
    appearance::Any
end

MarkedTextToSyntaxLeaf(; theme = nothing, style = get_text_style(theme, :plain_text),
                       appearance = nothing) =
    MarkedTextToSyntaxLeaf(style, appearance === nothing ? Appearance() : appearance)

@projection_template MarkedTextToSyntaxLeaf MarkedText (p, document) ->
    SyntaxLeaf(bound(:text, String, TextBlock(make_marked_text_lines(document, p.style, p.appearance))))
