"""
    ReferenceInspectorToTextModule

`ReferenceInspectorToText` — projects a `ReferenceInspector` document into a
two-section `TextText`:

1. a gray "compact" label, then the Julia-printed reference on one colored
   line (delegated to `ReferenceToText`);
2. a gray "human-readable" label, then the reverse-order English narrative
   (delegated to `ReferenceToHumanReadableText`, which names the parent type
   of each step against the inspector's `target` document).

The two delegate projections already exist and own all per-step rendering;
this projection only stacks their outputs with section labels and blank
lines. The span list is built inside a reactive thunk so it refreshes when
the inspector's `reference` cell changes.

Display-only: `map_reference_forward`/`map_reference_backward` return
`nothing`, so a click landing inside the rendered panel produces no
operation (v1 does not map panel spans back to the source reference).
"""
module ReferenceInspectorToTextModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: projection_print, map_reference_forward,
                              map_reference_backward, Projection
import ..ReferenceInspectorDocumentModule: ReferenceInspector
import ..ReferenceToTextModule: ReferenceToText, ReferenceToHumanReadableText
import ..TextModule: TextDocument, TextText, TextString, TextNewline
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_solarized_gray
import ..PrinterContextModule: PrinterContext
import ..IoMapModule: SimpleIoMap

export ReferenceInspectorToText

"""
    ReferenceInspectorToText(; font=font_ubuntu_monospace_regular_24)

Projection over `ReferenceInspector`. Output is a `TextText` stacking the
compact and human-readable renderings of `inspector.reference`.
"""
struct ReferenceInspectorToText <: Projection
    font::StyleFont
end
ReferenceInspectorToText(; font = font_ubuntu_monospace_regular_24) =
    ReferenceInspectorToText(font)

_label(text::AbstractString, font::StyleFont) =
    TextString(text, font, color_solarized_gray)

# Copy the spans of `tt` (a TextText) onto `spans`.
function _append_spans!(spans::Vector{TextDocument}, tt::TextText)
    for i in 1:length(tt.elements)
        push!(spans, tt.elements[i])
    end
    spans
end

function projection_print(p::ReferenceInspectorToText, recursion, input::ReferenceInspector, ctx)
    short_proj = ReferenceToText(font = p.font)
    out = TextText(() -> begin
        ref    = input.reference        # tracked: ReferencePath or nothing
        target = input.target
        long_proj = ReferenceToHumanReadableText(target; font = p.font)
        ictx = PrinterContext()
        short = projection_print(short_proj, nothing, ref, ictx).output
        long  = projection_print(long_proj,  nothing, ref, ictx).output

        spans = TextDocument[]
        push!(spans, _label("compact", p.font))
        push!(spans, TextNewline(font = p.font))
        _append_spans!(spans, short)
        push!(spans, TextNewline(font = p.font))
        push!(spans, TextNewline(font = p.font))
        push!(spans, _label("human-readable", p.font))
        push!(spans, TextNewline(font = p.font))
        _append_spans!(spans, long)
        spans
    end)
    SimpleIoMap(p, input, out)
end

map_reference_forward(::ReferenceInspectorToText, ::SimpleIoMap, _) = nothing
map_reference_backward(::ReferenceInspectorToText, ::SimpleIoMap, _) = nothing

end # module
