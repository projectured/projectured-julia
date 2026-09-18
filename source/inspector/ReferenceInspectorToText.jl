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
# document with `TypeReferenceStep` checkpoints (`annotate_reference_types`). Both
# sections render from that canonical reference, so the compact form shows the
# `::Type` steps and the human-readable form names each step's parent type from
# the embedded checkpoints.
#
# The two delegate projections own all per-step rendering; this projection stacks
# their outputs with section headers and blank lines, inside a reactive thunk so
# it refreshes when the inspector's `reference` cell changes.
#
# Display-only: `map_reference_forward`/`map_reference_backward` return `nothing`,
# so a click landing inside the rendered panel produces no operation.
"""
    ReferenceInspectorToText(; font=font_ubuntu_monospace_regular_20,
                               header_font=font_liberation_sans_bold_30,
                               header_color=color_solarized_blue)

Projection over `ReferenceInspector`. Output is a `TextBlock` stacking the
compact and human-readable renderings of `inspector.reference` under bold
section headers.
"""
@projection struct ReferenceInspectorToText <: Projection
    font::ImmutableCell{StyleFont}
    header_font::ImmutableCell{StyleFont}
    header_color::ImmutableCell{StyleColor}
end
ReferenceInspectorToText(; font = font_ubuntu_monospace_regular_20,
                           header_font = font_liberation_sans_bold_30,
                           header_color = color_solarized_blue) =
    ReferenceInspectorToText(font, header_font, header_color)

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
    short_proj = ReferenceToText(font = p.font)
    out = TextBlock(() -> begin
        ref    = input.reference        # tracked: Reference or nothing
        target = input.target
        # Annotate with TypeReferenceStep checkpoints so both forms show types.
        canonical = (ref isa ConcreteReference && target !== nothing) ?
                    annotate_reference_types(target, ref) : ref
        long_proj = ReferenceToHumanReadableText(document = target, font = p.font)
        ictx = PrinterContext()
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

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw a reference inspector. The factory form, so
# every renderer builds its own projection instance.

function __init__()
    register_natural_graphics!(:inspector,
        (; measure) -> Pair{Type,Any}[
            ReferenceInspector => ChainingProjection(ReferenceInspectorToText(),
                                                      WordWrapping(measure = measure),
                                                      TextToGraphics(measure = measure)),
        ])
end
