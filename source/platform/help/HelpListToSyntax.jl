# Fragment of `HelpModule`.
#
# Projects a `DocumentTypeList` or a `ProjectionList` onto a `SyntaxNode`: a line
# that says what the list holds, then one entry for each type, in the order of
# the names. The first line of an entry has the name of the type and the package
# that defines it, and for a document type the names a person types into an
# empty tab to make one. The second line has the description.
#
# The lines are computed when the list prints, from the modules that are loaded
# then. They read no cell, so they are made once, outside any computation.
#
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.
#
# The projection holds its styles and no theme; `make_help_list_projection`
# fills them from a theme.
@projection UntrackedCell struct HelpListToSyntax
    heading::StyleText = get_help_style(nothing, :heading_text)
    name::StyleText = get_help_style(nothing, :name_text)
    detail::StyleText = get_help_style(nothing, :detail_text)
    description::StyleText = get_help_style(nothing, :description_text)
    muted::StyleText = get_help_style(nothing, :muted_text)
end

"""
    make_help_list_projection(; theme = nothing) -> HelpListToSyntax

The projection of a document type list or a projection list, with the styles of
`theme`: a `HelpTheme`, scaled or not, or the default styles for `nothing`.
"""
function make_help_list_projection(; theme = nothing)
    get_style(name) = get_help_style(theme, name)
    HelpListToSyntax(; heading = get_style(:heading_text), name = get_style(:name_text),
                     detail = get_style(:detail_text), description = get_style(:description_text),
                     muted = get_style(:muted_text))
end

"""
    compute_help_entries(list) -> Vector{NamedTuple}

The entries of a [`DocumentTypeList`](@ref) or a [`ProjectionList`](@ref), one
for each type, sorted by name with no regard to case. An entry is
`(name, package, typed, summary)`: `typed` holds the names a person types into an
empty tab to make a document of the type, and it is empty for a projection.
`summary` is the first paragraph of the docstring, or `""`.
"""
compute_help_entries(::DocumentTypeList) =
    _make_help_entries(get_insertion_candidates(Document); typed = true)
compute_help_entries(::ProjectionList) =
    _make_help_entries(compute_concrete_subtypes(Projection); typed = false)

function _make_help_entries(types; typed::Bool)
    entries = [(name = String(nameof(T)),
                package = String(nameof(Base.moduleroot(parentmodule(T)))),
                typed = typed ? _get_typed_names(T) : String[],
                summary = compute_docstring_summary(T)) for T in types]
    # A permutation of plain strings, because a sort of the entries by a key
    # compiles the sort for their type when the first list prints.
    entries[sortperm([lowercase(entry.name) * " " * entry.package for entry in entries])]
end

# The names a person types into an empty tab to make a `T`, without the name of
# the type itself: the words of the name, and the aliases. `T` is not
# specialized on, so one method serves every type of the list.
function _get_typed_names(@nospecialize(T::Type))
    own = String(nameof(T))
    filter(!=(own), get_insertion_names(T))
end

_get_list_heading(::DocumentTypeList, count) =
    "$count document types. Type one of the names in an empty tab to make a document of that type."
_get_list_heading(::ProjectionList, count) =
    "$count projections. A projection draws a document, and one that takes other projections combines them."

function print_document(p::HelpListToSyntax, recursion,
                        list::Union{DocumentTypeList, ProjectionList}, ctx::PrinterContext)
    entries = compute_help_entries(list)
    lines = SyntaxDocument[SyntaxLeaf(TextString(_get_list_heading(list, length(entries)), p.heading))]
    for entry in entries
        push!(lines, SyntaxLeaf(TextString("", p.detail)))
        push!(lines, _make_name_line(p, entry))
        push!(lines, isempty(entry.summary) ?
                         SyntaxLeaf(TextString("    no description", p.muted)) :
                         SyntaxLeaf(TextString("    " * entry.summary, p.description)))
    end
    SimpleIoMap(p, list, SyntaxNode(lines; sep = TextString("\n")))
end

# "JsonString   ProjecturedJSON   type: json string, string"
function _make_name_line(p::HelpListToSyntax, entry)
    parts = SyntaxDocument[SyntaxLeaf(TextString(entry.name, p.name)),
                           SyntaxLeaf(TextString("   " * entry.package, p.detail))]
    isempty(entry.typed) ||
        push!(parts, SyntaxLeaf(TextString("   type: " * join(entry.typed, ", "), p.detail)))
    SyntaxNode(parts)
end
