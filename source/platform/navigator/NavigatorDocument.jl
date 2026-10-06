# Fragment of `NavigatorModule` — the navigator document: the content that it
# shows a part of, the address of that part, and the visits before and after it.

"""
    NavigatorVisit(content, address, selection)

One page that a person saw in a navigator: the `content`, the `address` of the
page in it, and the `selection` when the person left the page, as a path from
the content, or `nothing`. A visit is a value and not a document, as a
`DocumentLocator` is: Back and Forward replace one, and nothing edits it.
"""
struct NavigatorVisit
    content::Any
    address::Reference
    selection::Union{Reference, Nothing}
end

"""
    ReferenceInsertion(value = "")

A step of an address that a person types and that names no step yet, as
`JsonInsertion` is a JSON value that names no value yet: `value` is the text that
was typed, such as `na` of a field or `4` of an element. It becomes a
`FieldReferenceStep` or an element `RangeReferenceStep` when its text names one.
"""
@document struct ReferenceInsertion
    value::String = ""
end

"""
    NavigatorAddress(steps = CellVector(); view = :titles, edited = false,
                     view_before = :titles, unreached_step = 0)

The address of a navigator as its bar shows it and a person edits it: an editable
copy beside the committed `address` of the [`Navigator`](@ref).

- `steps` holds `FieldReferenceStep`s, element `RangeReferenceStep`s and
  [`ReferenceInsertion`](@ref)s, while the copy is edited.
- `view` is `:titles`, `:path` or `:types`: the names of the documents on the
  address, the path, or the path with the type of each node.
- `edited` is `false` while the copy is the address: the views then show the
  steps of the address, and an edit writes them here. A visit makes it `false`
  again.
- `view_before` is the view that the end of an edit shows again.
- `unreached_step` is the first step that reaches no node, after Enter read a
  path that does not reach to its end, or `0`.

It is view state: an undo records no change of it, and a save does not keep it.
"""
@document struct NavigatorAddress
    steps::CellVector = CellVector()
    view::Symbol = :titles
    edited::Bool = false
    view_before::Symbol = :titles
    unreached_step::Int = 0
end

"""
    NavigatorChoiceList(; query = "", row = 1, current, find, choose)

The list of the choices at one step of the address of a navigator, which the
context menu window shows: a field of the typed text over the choices that the
text narrows to.

- `query` is the typed text, and `row` the row that Return chooses.
- `current` is the step of the address.
- `find(query)` gives the choices, `label => step` pairs
  ([`find_navigator_choices`](@ref)).
- `choose(step)` gives the operation that opens a choice
  ([`make_navigator_choice_operation`](@ref)), or `nothing` for the page that the
  navigator shows.

It is view state of a popup: an undo records no change of it, no file keeps it,
and a walk of the documents does not go into it.
"""
@document struct NavigatorChoiceList
    query::String = ""
    row::Int = 1
    current::Any = nothing
    find::Any = query -> Pair{String,ReferenceStep}[]
    choose::Any = step -> nothing
end

is_walk_opaque(::NavigatorChoiceList) = true

"""
    Navigator(content[, address])

A document that shows one part of `content`, its page, as a tab of a browser
shows one page of a site.

- `content` is the root that the pages are parts of: a document of any domain.
- `address` is the path of the page from `content`. The empty path shows the
  whole content.
- `back` holds the visits before the current one, the newest last, and
  `forward` the visits after it, the nearest last.
- `address_draft` is the address as the bar shows it and a person edits it
  ([`NavigatorAddress`](@ref)).

The address is state of the document, not of a projection, so it is saved with
the document and a program or the assistant reads it as any field. A move to
another page writes it as view state, so undo records none of it. See
[`make_navigator_open_operation`](@ref), [`make_navigator_back_operation`](@ref),
[`make_navigator_forward_operation`](@ref) and
[`make_navigator_parent_operation`](@ref).

# Example

    navigator = Navigator(frame_view, @reference(frame_view, rows[42]))
"""
@document struct Navigator <: Document
    content::Any
    address::Reference = EmptyReference()
    back::Vector{NavigatorVisit} = NavigatorVisit[]
    forward::Vector{NavigatorVisit} = NavigatorVisit[]
    address_draft::NavigatorAddress = NavigatorAddress()
end

# A navigator shows a part of its content, so the document that a person edits in
# it is the content.
get_edited_field(::Navigator) = :content

# A navigator is called by its page, as a tab of a browser is called by the page
# that it shows.
function get_document_title(navigator::Navigator)
    title = get_document_title(get_navigator_page(navigator))
    title === nothing ? get_document_title(navigator.content) : title
end

# A duplicate of a navigator tab has its own address and its own visits, and
# reads the same content, as a duplicate of a tab of a browser does: the copy
# descends into a navigator and shares a content that declares no duplicate.
has_document_duplicate(::Navigator) = true

# The copy of the address belongs to its tab, as the address does.
has_document_duplicate(::NavigatorAddress) = true

# A file keeps the content and the address, as the text of a path, and not the
# visits: a window that opens again shows the same page, with empty lists.
pred_arguments(navigator::Navigator) =
    (), Pair{Symbol,Any}[:content => navigator.content, :address => print_path_text(navigator.address)]

function make_pred_document(::Type{Navigator}, positional, keywords)
    values = Dict{Symbol,Any}(keywords)
    content = values[:content]
    Navigator(content, annotate_reference_types(content, parse_path_text(values[:address])))
end

# A tab of a navigator keeps its name, as every tab does, and its tooltip says the
# address of the page that it shows now.
make_pane_tab_title(navigator::Navigator, name::AbstractString) =
    PaneTabTitle(name; tooltip = () -> join(first.(_get_address_parts(navigator)), " › "))
