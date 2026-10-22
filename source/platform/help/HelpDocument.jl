# Fragment of `HelpModule` — the documents the Help menu opens: the two trees of
# the types and the page about the program, and the groups and the entries of a
# tree.

"""
    DocumentTypeList()

The tree of every document type that an empty tab can make: the types that
`get_insertion_candidates(Document)` finds in the loaded modules, grouped by
package, and by module in a package of many modules. `children` holds the
[`HelpGroup`](@ref)s of the packages. A new list holds none: its acquire builds
them, and builds them again after a change of the loaded program
([`update_help_groups!`](@ref)). `world` is the world counter at the last build,
and `table` the roster of the groups, which the page draws; the first build makes
it.
"""
@document struct DocumentTypeList
    children::CellVector = CellVector()
    world::UInt = UInt(0)
    table::Any = nothing
end

"""
    ProjectionList()

The tree of every concrete projection in the loaded modules: the views a window
can draw a document with, and the projections that combine other projections,
grouped as in a [`DocumentTypeList`](@ref).
"""
@document struct ProjectionList
    children::CellVector = CellVector()
    world::UInt = UInt(0)
    table::Any = nothing
end

"""
    HelpGroup(name, count, description, children, table)

A package or a module in a tree of the help: `name` is the name of the package
without `Projectured`, or the name of the module without `Module`; `count` is
the count of the types below it; `description` is the first paragraph of the
docstring of the package or the module. `children` holds the groups of the
modules of a package, or the [`HelpEntry`](@ref)s of its types, and `table` the
roster of the children, which the page draws.
"""
@document struct HelpGroup
    name::String
    count::Int
    description::String
    children::CellVector
    table::Any
end

"""
    HelpEntry(name, type, typed, description, text)

One type in a tree of the help: `name` is its name, `type` the type; `typed`
holds the names that a person types into an empty tab to make a document of the
type, joined by ", ", and is empty for a projection. `description` is the first
paragraph of its docstring, and `text` the whole docstring, or `""` for a type
with none.
"""
@document struct HelpEntry
    name::String
    type::Any
    typed::String
    description::String
    text::String
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
get_document_title(group::HelpGroup) = group.name
get_document_title(entry::HelpEntry) = entry.name
get_insertion_aliases(::Type{DocumentTypeList}) = ["documents"]
get_insertion_aliases(::Type{ProjectionList}) = ["projections"]
get_insertion_aliases(::Type{AboutPage}) = ["about"]

# A tree holds what the loaded program gives, so a save writes nothing and the
# acquire after a load builds the groups again.
pred_arguments(::DocumentTypeList) = (), Pair{Symbol,Any}[]
pred_arguments(::ProjectionList) = (), Pair{Symbol,Any}[]

# A group and an entry are parts of a tree, which an empty tab does not make.
insertable(::Type{<:HelpGroup}) = false
insertable(::Type{<:HelpEntry}) = false

# The count of the types of a tree, as the detail of its row; empty before the
# first build.
_format_help_count(children) = isempty(children) ? "" : string(sum(group -> group.count, children))

get_document_decoration(list::DocumentTypeList) =
    DocumentDecoration(; icon = :circle_help, detail = _format_help_count(list.children),
                       tooltip = () -> TooltipNote(; title = "Documents",
                           text = "Every document type that an empty tab can make, by package and by slice."))
get_document_decoration(list::ProjectionList) =
    DocumentDecoration(; icon = :circle_help, detail = _format_help_count(list.children),
                       tooltip = () -> TooltipNote(; title = "Projections",
                           text = "Every projection, by package and by slice: the views of a document, and the projections that combine them."))
get_document_decoration(group::HelpGroup) =
    DocumentDecoration(; icon = :layers, detail = string(group.count),
                       tooltip = () -> TooltipNote(; title = group.name, text = group.description))
# A projection draws a document, so its entry has the icon of a function.
get_document_decoration(entry::HelpEntry) =
    DocumentDecoration(; icon = entry.type isa Type && entry.type <: Projection ? :lambda : :file,
                       tooltip = () -> TooltipNote(; title = entry.name, text = entry.description))
get_document_decoration(::AboutPage) =
    DocumentDecoration(; icon = :circle_help, tooltip = () -> TooltipNote(; title = "About",
        text = "What this program is, and its version."))
