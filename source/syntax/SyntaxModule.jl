"""
    SyntaxModule

The syntax tree domain provides a generic intermediate representation between
any structured document and flat text. Nodes carry open/close delimiters and
a separator; leaves carry open/value/close spans. This layer decouples the
layout engine from any specific source domain so the same word-wrap and
indentation logic applies to JSON, XML, or any future domain.

The domain includes:
- **Core types**: `SyntaxLeaf` (leaf with delimiters and value), `SyntaxNode` (a compound carrying every span at once)
- **Compounds**: `SyntaxConcatenation`, `SyntaxSeparation` — documents that sequence children and little else
- **Wrapper types**: `SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation` (single-child document wrappers)
- **Base types**: `SyntaxDocument` for every syntax document; `SyntaxCompound` for the ones with children

A document picks whichever type says what it means. A delimited, indented,
collapsible node is a `SyntaxNode`; one that only sequences a fixed child list is a
`SyntaxConcatenation`. They are not alternatives to choose between once and for all
— they are the same five layout jobs in different combinations, and they share one
implementation (the compound contract below, and `SyntaxToText`'s splice core).

Selection semantics (`[i]` = 1-based item, `{k}` = 0-based cursor):
- Leaves: `.open{k}`, `.value{k}`, `.close{k}` — cursor at boundary k in a delimiter or the value
- Compounds: `.children[i]` for the i-th child, plus a cursor in whatever delimiters
  the compound has (`.open{k}` / `.close{k}` on a `SyntaxNode`). A delimiter a
  compound does not have renders no span and offers no cursor.
"""
module SyntaxModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..EventModule
using ..GestureBindingModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..StyleModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!
import ..ProjectionModule: get_projection_gesture_bindings
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export SyntaxDocument, SyntaxCompound, SyntaxSequence, SyntaxWrapper,
       render, set_cell_computation!,
       get_syntax_children, get_opening_delimiter, get_closing_delimiter, get_separator,
       is_on_closing_delimiter,
       get_indentation, is_syntax_collapsed, is_syntax_collapsible,
       build_syntax_child_path, peel_child_step
export SyntaxLeafToText, SyntaxCompoundToText, SyntaxListToText, SyntaxToText,
       SyntaxCompoundToTextIoMap
export NothingToSyntaxLeaf, BoolToSyntaxLeaf, NumberToSyntaxLeaf,
       StringToSyntaxLeaf, SymbolToSyntaxLeaf, CharToSyntaxLeaf,
       ObjectNodeToSyntaxNode, ObjectToSyntax, print_object, CellToSyntax
export ObjectFieldToSyntax
export CollectionCellVectorToSyntax, CollectionListNodeToSyntax, CollectionToSyntax
export PrimitiveBoolToSyntaxLeaf, PrimitiveNumberToSyntaxLeaf, PrimitiveStringToSyntaxLeaf,
       PrimitiveToSyntax
export InsertionToSyntaxLeaf, DocumentInsertionToSyntaxLeaf, DomainInsertionToSyntaxLeaf,
       InsertionNothingToSyntaxLeaf,
       default_factory, default_completion, parse_completion,
       insert_insertion_text_operation, delete_insertion_text_operation
export make_natural_to_syntax_dispatch, make_natural_prose_graphics, register_syntax_fallback!
export SyntaxLeaf, SyntaxNode, SyntaxConcatenation, SyntaxSeparation, SyntaxDelimitation, SyntaxIndentation, SyntaxCollapsible, SyntaxNavigation


include("SyntaxDocument.jl")
include("SyntaxToText.jl")
include("ObjectToSyntax.jl")
include("ObjectFieldToSyntax.jl")
include("CollectionToSyntax.jl")
include("PrimitiveToSyntax.jl")
include("InsertionToSyntax.jl")
include("SyntaxNatural.jl")

end # module
