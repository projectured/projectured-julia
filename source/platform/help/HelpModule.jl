"""
    HelpModule

What the Help menu of a window opens: the tree of the document types, the tree
of the projections, and the page about the program.

A tree groups its types by package, and by module in a package of many modules.
It stores its groups, and its acquire builds them from the modules that are
loaded then ([`HelpTree.jl`](HelpTree.jl)), so the tree shows every type the
program has, and a saved window has nothing to save for it. The description of a
type is the first paragraph of its docstring, from `compute_docstring_summary`
of the kernel tool layer.

An [`AboutPage`](HelpDocument.jl) says what the program is. The window that
shows the Help menu gives the page of its own program.
"""
module HelpModule

using ..CellModule
using ..CollectionModule
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
using ..TooltipModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, get_document_decoration, insertable, acquire_document!
import ..ProjectionModule: print_document
import ..SerializationModule: pred_arguments
import ..TreeModule: get_tree_children_steps, has_tree_children

export make_help_list_projection, compute_help_entries
export HelpGroup, HelpEntry, update_help_groups!
export make_about_page_projection

include("HelpDocument.jl")
include("HelpTheme.jl")
include("HelpTree.jl")
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
