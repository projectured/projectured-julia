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

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export BookDocument
export BookTheme, ScaledBookTheme
export BookInsertionToSyntaxLeaf, BookBookToSyntaxNode, BookChapterToSyntaxNode, BookParagraphToSyntaxLeaf,
       BookListToSyntaxNode, BookPictureToSyntaxLeaf, BookToSyntax
export BookInsertion, BookBook, BookChapter, BookParagraph, BookList, BookPicture


include("BookDocument.jl")
include("BookTheme.jl")
include("BookToSyntax.jl")

end # module
