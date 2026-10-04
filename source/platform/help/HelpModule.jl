"""
    HelpModule

What the Help menu of a window opens: the list of the document types, the list
of the projections, and the page about the program.

A list is a document with no field. [`HelpListToSyntax`](HelpListToSyntax.jl)
computes its lines from the modules that are loaded when it prints, so the list
shows every type the program has at that moment, and a saved window has
nothing to save for it. The description of a type is the first paragraph of its
docstring, from `compute_docstring_summary` of the kernel tool layer.

An [`AboutPage`](HelpDocument.jl) says what the program is. The window that
shows the Help menu gives the page of its own program.
"""
module HelpModule

using ..CellModule
using ..DocumentModule
using ..DomainModule
using ..IoMapModule
using ..NaturalModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..ToolModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases
import ..ProjectionModule: print_document
import ..SerializationModule: pred_arguments

export compute_help_entries
export HelpTheme, ScaledHelpTheme
export HelpListToSyntax, make_help_list_projection
export AboutPageToSyntax, make_about_page_projection

include("HelpDocument.jl")
include("HelpTheme.jl")
include("HelpListToSyntax.jl")
include("AboutPageToSyntax.jl")

# The rows that let a tab draw what the Help menu opens.
function __init__()
    register_natural_syntax!(:help, (; appearance) -> begin
        theme = get_scaled_theme!(appearance, HelpTheme)
        Pair{Type,Any}[
            DocumentTypeList => make_help_list_projection(; theme),
            ProjectionList   => make_help_list_projection(; theme),
            AboutPage        => make_about_page_projection(; theme),
        ]
    end)
end

end # module
