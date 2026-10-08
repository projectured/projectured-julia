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

using ..CellModule
using ..CellStructModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..EventModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
import ..GraphicsModule: find_first_baseline
using ..IoMapModule
using ..LayoutModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..StyleModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!
import ..OperationModule: splice_value!, evaluate_operation, operation_reference,
                          retarget_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export TextSpanReferenceStep
export TextColumnReferenceStep
export TextRangeReferenceStep, is_text_caret
export set_cell_computation!, get_flat_length, get_flat_offsets, get_flat_string, get_flat_selection, make_hinted_text,
       get_selection_substring, make_text_insert_operation, ReplaceTextRangeOperation,
       convert_flat_offset_to_element, convert_element_to_flat_offset, get_flat_caret, _lower_text_range
export SpanPath, get_flat_base, make_flat_caret_reference, make_flat_range_reference,
       get_flat_cursor_coordinate, is_structural_selection, is_text_element_write
export TextTheme, ScaledTextTheme
export ReferenceTheme, ScaledReferenceTheme
export TextToGraphics, TextToGraphicsIoMap
export TextGutter, TextGutterToGraphics, TextBlockToScrollLayout, TextBlockToScrollLayoutIoMap
export TextFold, TextFolding, TextFoldingIoMap
export TextBlockToString, TextStringToString, TextNewlineToString, TextSpacingToString, TextGraphicsToString,
       TextLineToString, TextToString
export TextLineNumbering, LineNumbering
export WordWrapping, WordWrappingIoMap, WrapSegment
export make_text_pattern
export TextFiltering, TextFilteringIoMap
export TextFirstLine, TextFirstLineIoMap
export TextHighlighting, TextHighlightingIoMap, HighlightSegment
export SelectionInverting, SelectionInvertingIoMap, SelectionSegment
export PrimitiveBoolToText, PrimitiveNumberToText, PrimitiveStringToTextBlock, PrimitiveInsertionToText, PrimitiveToText
export ReferenceToText, ReferenceToHumanReadableText
export TextBlock, TextLine, TextString, TextNewline, TextGraphics, TextDocument, UNSTYLED_TEXT_FONT
export FaultToText


include("TextSpanReferenceStep.jl")
include("TextColumnReferenceStep.jl")
include("TextRangeReferenceStep.jl")
include("TextDocument.jl")
include("TextTheme.jl")
include("TextToGraphics.jl")
include("TextGutterToGraphics.jl")
include("TextBlockToScrollLayout.jl")
include("TextToString.jl")
include("FaultToText.jl")
include("TextLineNumbering.jl")
include("TextFolding.jl")
include("WordWrapping.jl")
include("TextPattern.jl")
include("TextFiltering.jl")
include("TextFirstLine.jl")
include("TextHighlighting.jl")
include("SelectionInverting.jl")
include("PrimitiveToText.jl")
include("ReferenceTheme.jl")
include("ReferenceToText.jl")

end # module
