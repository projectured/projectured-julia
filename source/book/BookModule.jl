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

using ..BackendModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..GraphicsModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export BookDocument
export BookInsertionToSyntaxLeaf, BookBookToSyntaxNode, BookChapterToSyntaxNode, BookParagraphToSyntaxLeaf,
       BookListToSyntaxNode, BookPictureToSyntaxLeaf, BookToSyntax
export BookInsertion, BookBook, BookChapter, BookParagraph, BookList, BookPicture


include("BookDocument.jl")
include("BookToSyntax.jl")

end # module
