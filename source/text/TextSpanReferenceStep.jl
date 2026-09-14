"""
    TextModule

The text domain: a block of styled spans, the reference steps that address a
character range inside it, the projections that render it to graphics and to a
string, and the decorating projections that wrap, filter, highlight, number and
invert it.

This file holds `TextSpanReferenceStep`, because the rest of the slice is
written in terms of the reference steps.

The `TextSpanReferenceStep` step type — a reference step representing a
flat character-range box in the text domain (`start` / `stop` are 0-based
character offsets into the concatenated text of a `TextBlock`). Used by the
syntax-to-text stage to communicate a nested child's whole-element
selection as a character range to the text-to-graphics stage, which renders
it as a translucent rectangle.

Lives with the text slice because the concept is text-domain vocabulary;
the kernel reference layer never names it. Registered as a `:terminal` step
type — it identifies a range but does not descend into a child. No DSL
entry (`.rect` / equivalent) is exposed today; when one is added it goes
here alongside the type.
"""
module TextModule

export TextSpanReferenceStep
export TextColumnReferenceStep
export TextRangeReferenceStep, is_text_caret
import ..CellModule: set_cell_function!
using ..DocumentModule
using ..DomainModule
using ..SelectionModule
using ..CollectionModule
using ..StyleModule
using ..OperationModule
import ..OperationModule: splice_value!, evaluate_operation, reroot_operation
using ..PrimitiveModule
using ..GestureBindingModule
export set_cell_function!, get_flat_length, get_flat_offsets, get_flat_selection, make_hinted_text,
       get_selection_substring, make_text_insert_operation, ReplaceTextRangeOperation,
       convert_flat_offset_to_element, convert_element_to_flat_offset, get_flat_caret, _lower_text_range
export SpanPath, get_flat_base, make_flat_caret_reference,
       get_flat_cursor_coordinate, is_structural_selection
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..GraphicsModule
using ..EventModule
using ..EventPatternModule
using ..IoMapModule
export TextToGraphics, TextToGraphicsIoMap
using ..ProjectionAlgebraModule
using ..PrinterContextModule
export TextBlockToString, TextStringToString, TextNewlineToString, TextLineToString, TextToString
using ..ProjectionModule
export TextLineNumbering, LineNumbering
export WordWrapping, WordWrappingIoMap, WrapSegment
export TextFiltering, TextFilteringIoMap
export TextFirstLine, TextFirstLineIoMap
export TextHighlighting, TextHighlightingIoMap, HighlightSegment
export SelectionInverting, SelectionInvertingIoMap, SelectionSegment
export PrimitiveBoolToText, PrimitiveNumberToText, PrimitiveStringToTextBlock, PrimitiveToText
using ..ProjectionReferenceStepModule
export ReferenceToText, ReferenceToHumanReadableText
export TextBlock, TextLine, TextString, TextNewline, TextGraphics, TextDocument


using ..CellModule
using ..CellStructModule
using ..ReferenceModule


"""
    TextSpanReferenceStep(start, stop)

A reference step representing an axis-aligned bounding-box highlight in the
text domain. `start` and `stop` are flat 0-based character offsets into the
concatenated text of a `TextBlock`. Evaluates to the offset pair
`(start, stop)` — every reference in the tree is evaluatable, and the
box's value is its character range independent of what characters happen
to sit in the current text.
"""
@cell_struct struct TextSpanReferenceStep <: ReferenceStep
    start::Int
    stop::Int
end

ReferenceModule.get_reference_step_kind(::TextSpanReferenceStep) = :structural

# A rectangular text range's descended value is the range itself.
ReferenceModule.evaluate_reference_step(step::TextSpanReferenceStep, document) = (step.start, step.stop)

Base.:(==)(a::TextSpanReferenceStep, b::TextSpanReferenceStep) =
    a.start == b.start && a.stop == b.stop

function Base.show(io::IO, s::TextSpanReferenceStep)
    print(io, "▢(", s.start, ":", s.stop, ")")
end


include("TextColumnReferenceStep.jl")
include("TextRangeReferenceStep.jl")
include("TextDocument.jl")
include("TextToGraphics.jl")
include("TextToString.jl")
include("TextLineNumbering.jl")
include("WordWrapping.jl")
include("TextFiltering.jl")
include("TextFirstLine.jl")
include("TextHighlighting.jl")
include("SelectionInverting.jl")
include("PrimitiveToText.jl")
include("ReferenceToText.jl")

end # module
