# The form is a two-stage chain. Stage one walks the authored tree and replaces
# every `ObjectField` with its control, copying everything else; stage two draws
# the result.
#
# `CopyingProjection` is what makes the walk work: it recurses a struct Document
# field by field through `print_child`, so the dispatch meets each `ObjectField`
# wherever the author put it, and the labels pass through untouched.
function make_object_field_form_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_monospace_regular_20
    w2g  = WidgetToGraphics(font; measure=measure)
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            ObjectField => ObjectFieldToWidget(style=StyleText(font, color_default)),
            Any         => CopyingProjection())),
        RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            w2g.dispatch,
            Pair{Type,Any}[
                TextBlock => TextToGraphics(measure=measure),
            ],
        ))),
    )
end

# One field to syntax and on to graphics. The `ObjectField` entry stands in front
# of `ObjectToSyntax`'s own table, so the field is named rather than reflected:
# without it the `Any` row would dispatch to `ObjectNodeToSyntaxNode` and dump the
# whole object and its reference path.
function make_object_field_syntax_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(vcat(
            Pair{Type,Any}[ObjectField => ObjectFieldToSyntax()],
            ObjectToSyntax(open_delimiter="{", close_delimiter="}").dispatch,
        ))),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
