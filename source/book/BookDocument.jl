"""
    BookModule

The book document domain. Models structured prose: books, chapters,
paragraphs, lists, and pictures.

The domain includes:
- **Structure**: `BookBook`, `BookChapter`
- **Content**: `BookParagraph`, `BookList`, `BookPicture`
- **Utility types**: `BookInsertion` for cursor positioning
"""
module BookModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector, ComputedCellVector
import ..ReferenceModule: Reference
export BookDocument
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..StyleModule: ImageFile
import ..BackendModule: decode_image
import ..GraphicsModule: GraphicsDocument
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..TextModule: TextDocument, TextString, TextBlock, TextGraphics
import ..StyleModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20, font_ubuntu_monospace_italic_20,
                     font_ubuntu_bold_36, font_ubuntu_bold_24, font_ubuntu_italic_20
import ..StyleModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode, SyntaxDelimitation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..IoMapModule: ChildrenIoMap
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, RangeReferenceStep, FieldReferenceStep,
                         Reference, EmptyReference, extend_reference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep, make_introduced_reference,
                                        is_introduced_reference
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference", var"@reference_step"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..SyntaxModule: SyntaxCompoundToText, _syntax_to_flat
import ..PrinterContextModule: make_child_context
import ..ProjectionTemplateModule: var"@projection_template", bound, RuleIoMap
export BookInsertionToSyntaxLeaf, BookBookToSyntaxNode, BookChapterToSyntaxNode, BookParagraphToSyntaxLeaf,
       BookListToSyntaxNode, BookPictureToSyntaxLeaf, BookToSyntax
import ..NaturalModule: register_natural_syntax!
export BookInsertion, BookBook, BookChapter, BookParagraph, BookList, BookPicture



abstract type BookDocument <: Document end

# ── Insertion cursor ─────────────────────────────────────────────────────

"""
A placeholder for a book node being entered (the insert-by-typing cursor);
type-to-replace swaps it for concrete content.
"""
@document struct BookInsertion <: BookDocument
    value::Any = nothing
end

# ── Structure ────────────────────────────────────────────────────────────

"""
The top-level book document — a `title`, an optional `author`, and a sequence
of child nodes (typically `BookChapter`s). `collapsed` hides them behind a
marker in the projection.
"""
@document struct BookBook <: BookDocument
    title::String
    author::Any = nothing
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

"""
A chapter grouping child nodes under a `title` and optional `numbering` (e.g.
`"1"`). `collapsed` hides them in the projection.
"""
@document struct BookChapter <: BookDocument
    title::String
    numbering::String = ""
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

# ── Content ──────────────────────────────────────────────────────────────

"""
A prose paragraph. `content` is typically a `TextBlock`; `alignment` is one of
`:left`, `:center`, `:right`, or `:justified`.
"""
@document struct BookParagraph <: BookDocument
    content::Any
    alignment::Symbol = :left
    collapsed::Bool = false
end

"""
An unordered list of child nodes. `collapsed` hides them in the projection.
"""
@document struct BookList <: BookDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

"""
A figure with an optional `title`. `content` is an image value or path;
`alignment` is one of `:left`, `:center`, `:right`, or `:justified`.
"""
@document struct BookPicture <: BookDocument
    content::Any
    title::String = ""
    alignment::Symbol = :left
    collapsed::Bool = false
end

# Text-replace edits need no per-type method: `title`/`author`/`numbering` are
# plain strings, and a paragraph's `content` is a `TextBlock` whose representation
# locates and splices the right span.


include("BookToSyntax.jl")

end # module
