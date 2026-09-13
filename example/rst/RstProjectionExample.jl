# The source view: colourised raw reStructuredText, every marker on the page.
function make_rst_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(RstToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The natural notation: marker-free RST — large bold titles, real bold and
# italic, a role as a coloured chip, a figure as the picture itself. Word-wrapped
# like prose, because a rendered paragraph is one long line until it is wrapped.
function make_rst_rendered_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(RstToSyntax(; style=:rendered)),
        RecursiveProjection(SyntaxToText()),
        WordWrapping(measure=measure),
        TextToGraphics(measure=measure),
    )
end
