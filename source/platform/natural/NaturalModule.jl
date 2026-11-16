"""
    NaturalModule

The natural notation of a document: the form in which it prints as text and as
graphics, and how two notations combine.

A notation is a rung on one ladder:

    domain ──▶ syntax ──▶ text ──▶ graphics
                              └──▶ string

A domain declares the projection of its documents to syntax, and everything
above it is composition. The composition is a `ChainingProjection`, which is
what every caller that wants a document as text would otherwise build by hand.

# The two starting rungs

- `:syntax` — the domain has a `*ToSyntax`, which it declares with
  `make_syntax_projection`, and reaches text and graphics through the fixed
  steps. Most domains.
- `:text` — the document is prose, a `TextDocument`. It reaches graphics through
  the text renderer and **needs no syntax package at all**.

A domain that draws itself, because a page of blocks or a diagram is not a
syntax tree, gives the renderer a row of its own.

# Which steps live where

This module owns `text → graphics` and `text → string`, because the natural
slice already names the text slice. It must not name the syntax slice — the
syntax slice names this one, and the arrow cannot turn — so this module declares
`make_syntax_to_text_projection` and the syntax slice adds its one method.

# What a domain writes

    make_syntax_projection(::Type{<:JsonDocument}; appearance) =
        JsonToSyntax(; theme = get_scaled_theme!(appearance, JsonTheme),
                     syntax_theme = get_scaled_theme!(appearance, SyntaxTheme))
    find_natural_file_format(::JsonDocument) = JsonFileFormat()

The format, `JsonFileFormat`, declares its extensions and its parser in the
serialization slice, so `parse_natural_text(:json, text)` reads the text and
`print_natural_text(document)` writes it.
"""
module NaturalModule

using ..ArrangementModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..GraphicsModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..StyleModule
using ..TextModule
using ..TooltipModule
using ..GestureModule
using ..WidgetModule
using ..ReferenceModule
using ..SerializationModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..GestureBindingModule: get_document_gesture_bindings_own
import ..EditorModule: make_document_projection
import ..SerializationModule: make_document_string

export make_syntax_projection, make_syntax_to_text_projection, find_natural_file_format,
       make_document_expression, get_natural_entries, has_natural_parser, parse_natural_text,
       describe_natural_formats, make_prose_document, make_natural_projection, print_natural_text
export register_natural_syntax!, register_natural_graphics!, register_natural_fallback!,
       get_natural_syntax_entries, get_natural_graphics_entries, get_natural_fallback_entries
export ArrangementChipsToGraphics, ArrangementChipsToGraphicsIoMap, ArrangementGroupRowsToWidget,
       ArrangementGroupRowsToWidgetIoMap
export NaturalToGraphics, make_natural_primitive_row,
       register_natural_syntax!, register_natural_graphics!, register_natural_fallback!
export ImageToWidget, TooltipContentToVerticalLayout, TooltipNoteToVerticalLayout, make_natural_tooltip_row


include("NaturalNotation.jl")
include("NaturalRegistry.jl")
include("NaturalArrangement.jl")
include("NaturalProjection.jl")
include("TooltipContentToLayout.jl")
include("TooltipNoteToLayout.jl")
include("ImageToWidget.jl")

end # module
