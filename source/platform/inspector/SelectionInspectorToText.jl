# Fragment of `InspectorModule`.
#
# `SelectionInspectorToText` — projects a `SelectionInspector` into the same
# two-section `TextBlock` that `ReferenceInspectorToText` builds, over whichever
# selection the inspector's `source` names.
#
# The whole rendering is delegated: this projection decides **which** reference
# to show and against which document, and hands both to the reference inspector
# it holds. Nothing about how a step is worded lives here twice.
#
# The thunk is what keeps the view live. It reads `input.source`, and reading a
# reactive field that holds a function re-runs that function; reading a document
# form reaches that document's own selection cell. Either way the block
# re-derives when the selection it follows moves.
#
# The editor's own document arrives through the printer context, under `:root`.
# A `nothing` source shows that document's selection, which is what a person who
# opens a selection view by name expects to see.
"""
    SelectionInspectorToText(; theme=nothing, reference_theme=nothing,
                               font=…, header_font=…, header_color=…)

Projection over [`SelectionInspector`](@ref). Output is a `TextBlock` stacking
the compact and human-readable renderings of the selection its input names.

`theme`, `reference_theme`, `font`, `header_font` and `header_color` are the
keywords of [`make_reference_inspector_projection`](@ref), which builds the
`ReferenceInspectorToText` that this projection delegates to.
"""
@projection struct SelectionInspectorToText <: Projection
    inner::ImmutableCell{ReferenceInspectorToText}
end
SelectionInspectorToText(; theme = nothing, reference_theme = nothing,
                           font = get_inspector_style(theme, :font),
                           header_font = get_inspector_style(theme, :header_font),
                           header_color = get_inspector_style(theme, :header_color)) =
    SelectionInspectorToText(make_reference_inspector_projection(; theme, reference_theme,
                                                                 font, header_font, header_color))

function print_document(p::SelectionInspectorToText, recursion,
                        input::SelectionInspector, ctx)
    root = get_property(ctx, :root)
    # The inner print keeps the clock and the properties of the editor, and has a
    # free range on each axis.
    inner_ctx = with_exact_size(make_child_context(ctx, EmptyReference());
                                width = nothing, height = nothing)
    out = TextBlock(() -> begin
        source = input.source          # tracked: a value, or a thunk that re-runs
        probe = ReferenceInspector(reference = find_inspected_selection(source, root),
                                   target = get_inspected_document(source, root))
        block = print_document(p.inner, nothing, probe, inner_ctx).output
        TextDocument[block.elements[i] for i in 1:length(block.elements)]
    end)
    SimpleIoMap(p, input, out)
end

# Display-only, as the reference inspector is: a click in the panel names a
# place in the rendering, not a place in the document the rendering describes.
map_reference_forward(::SelectionInspectorToText, ::SimpleIoMap, _) = nothing
map_reference_backward(::SelectionInspectorToText, ::SimpleIoMap, _) = nothing
