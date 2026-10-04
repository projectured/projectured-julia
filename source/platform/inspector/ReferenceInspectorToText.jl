# Fragment of `InspectorModule`.
#
# `ReferenceInspectorToText` — projects a `ReferenceInspector` document into a
# two-section `TextBlock`:
#
# 1. a bold, colored **Compact** header, then the Julia-printed reference on one
#    colored line (delegated to `ReferenceToText`);
# 2. a bold, colored **Human-readable** header, then the reverse-order English
#    narrative (delegated to `ReferenceToHumanReadableText`).
#
# Before rendering, the reference is annotated against the inspector's `target`
# document (`annotate_reference_types`), so each node records its type. Both
# sections render from that canonical reference: the compact form shows the
# `::Type` of each node, and the human-readable form names the parent type of each
# step.
#
# The two delegate projections own all per-step rendering; this projection stacks
# their outputs with section headers and blank lines, inside a reactive thunk so
# it refreshes when the inspector's `reference` cell changes.
#
# Display-only: `map_reference_forward`/`map_reference_backward` return `nothing`,
# so a click landing inside the rendered panel produces no operation.
"""
    ReferenceInspectorToText(; font=…, header_font=…, header_color=…, reference_style=…)

Projection over `ReferenceInspector`. Output is a `TextBlock` stacking the
compact and human-readable renderings of `inspector.reference` under bold
section headers.

`font`, `header_font` and `header_color` are its styles, which default to the
default [`InspectorTheme`](@ref); `reference_style` holds the values of the
[`ReferenceTheme`](@ref) that the delegate `ReferenceToText` and
`ReferenceToHumanReadableText` take. [`make_reference_inspector_projection`](@ref)
fills them from two themes.
"""
@projection UntrackedCell struct ReferenceInspectorToText <: Projection
    font::StyleFont = get_inspector_style(nothing, :font)
    header_font::StyleFont = get_inspector_style(nothing, :header_font)
    header_color::StyleColor = get_inspector_style(nothing, :header_color)
    reference_style::NamedTuple = get_theme_defaults(ReferenceTheme)
end

"""
    make_reference_inspector_projection(; theme = nothing, reference_theme = nothing,
                                        font, header_font, header_color)
        -> ReferenceInspectorToText

A `ReferenceInspectorToText` whose styles follow `theme`, an `InspectorTheme`,
and `reference_theme`, a `ReferenceTheme`; each scaled or not, or `nothing` for
the default values. A style given as a keyword stays fixed.
"""
make_reference_inspector_projection(; theme = nothing, reference_theme = nothing,
                                    font = get_inspector_style(theme, :font),
                                    header_font = get_inspector_style(theme, :header_font),
                                    header_color = get_inspector_style(theme, :header_color)) =
    ReferenceInspectorToText(; font, header_font, header_color,
                             reference_style = make_theme_values_field(ReferenceTheme, reference_theme))

_header(text::AbstractString, p::ReferenceInspectorToText) =
    TextString(text, p.header_font, p.header_color)

# Copy the spans of `tt` (a TextBlock) onto `spans`.
function _append_spans!(spans::Vector{TextDocument}, tt::TextBlock)
    for i in 1:length(tt.elements)
        push!(spans, tt.elements[i])
    end
    spans
end

function print_document(p::ReferenceInspectorToText, recursion, input::ReferenceInspector, ctx)
    short_proj = ReferenceToText(font = p.font, style = p.reference_style)
    # The two renderings keep the clock and the properties of the editor, and have a
    # free range on each axis.
    ictx = with_exact_size(make_child_context(ctx, EmptyReference());
                           width = nothing, height = nothing)
    out = TextBlock(() -> begin
        ref    = input.reference        # tracked: Reference or nothing
        target = input.target
        # Annotate the node types, so both forms show them.
        canonical = (ref isa ConcreteReference && target !== nothing) ?
                    annotate_reference_types(target, ref) : ref
        long_proj = ReferenceToHumanReadableText(document = target, font = p.font,
                                                 style = p.reference_style)
        short = print_document(short_proj, nothing, canonical, ictx).output
        long  = print_document(long_proj,  nothing, canonical, ictx).output

        spans = TextDocument[]
        push!(spans, _header("Compact", p))
        push!(spans, TextNewline(font = p.header_font))
        _append_spans!(spans, short)
        push!(spans, TextNewline(font = p.font))
        push!(spans, TextNewline(font = p.font))
        push!(spans, _header("Human-readable", p))
        push!(spans, TextNewline(font = p.header_font))
        _append_spans!(spans, long)
        spans
    end)
    SimpleIoMap(p, input, out)
end

map_reference_forward(::ReferenceInspectorToText, ::SimpleIoMap, _) = nothing
map_reference_backward(::ReferenceInspectorToText, ::SimpleIoMap, _) = nothing
