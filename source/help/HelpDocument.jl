# Fragment of `HelpModule` — the documents the Help menu opens: the two lists
# and the page about the program.

"""
    DocumentTypeList()

The list of every document type that an empty tab can make: the types that
`get_insertion_candidates(Document)` finds in the loaded modules. It holds
nothing. [`HelpListToSyntax`](@ref) computes the lines when it prints.
"""
@document struct DocumentTypeList
end

"""
    ProjectionList()

The list of every concrete projection in the loaded modules: the views a window
can draw a document with, and the projections that combine other projections.
It holds nothing. [`HelpListToSyntax`](@ref) computes the lines when it prints.
"""
@document struct ProjectionList
end

# The version every ProjecturEd package carries, read from the project file of
# this package.
_get_package_version() = string(something(pkgversion(parentmodule(@__MODULE__)), ""))

"""
    AboutPage(; name, summary, version, homepage)

What a program says about itself: its name, one sentence, its version and the
address of its home page. The defaults describe ProjecturEd, with the version of
the ProjecturEd packages. A window of another program gives its own page. The
page shows the Julia version too, which is the version that runs and not a
field.
"""
@document struct AboutPage
    name::String = "ProjecturEd"
    summary::String = "A generic-purpose projectional editor: a document is structured data, edited through its views."
    version::String = _get_package_version()
    homepage::String = "https://projectured.org"
end

# The names the tabs call themselves, and the names a person types into an
# empty tab to open one.
get_document_title(::DocumentTypeList) = "Documents"
get_document_title(::ProjectionList) = "Projections"
get_document_title(::AboutPage) = "About"
get_insertion_aliases(::Type{DocumentTypeList}) = ["documents"]
get_insertion_aliases(::Type{ProjectionList}) = ["projections"]
get_insertion_aliases(::Type{AboutPage}) = ["about"]

# A list holds nothing, so a save writes nothing and a load computes the list
# again.
pred_arguments(::DocumentTypeList) = (), Pair{Symbol,Any}[]
pred_arguments(::ProjectionList) = (), Pair{Symbol,Any}[]
