# Fragment of `InspectorModule` — `SelectionInspector`, the document that shows
# a selection in a form a person can read.

"""
    SelectionInspector(source = nothing)

A view of one selection. `source` says **which** selection it shows, and the
type of what the field holds picks the form:

| Written as | Shows |
|---|---|
| `SelectionInspector()` | the selection of the editor |
| `SelectionInspector(reference)` | that reference, fixed |
| `SelectionInspector(() -> get_selection(other))` | what the function answers, re-derived |
| `SelectionInspector(other)` | the selection of that document |

The third form is the reason `source` is an ordinary reactive field. A function
given to such a field becomes the cell's own thunk, so reading `source` re-runs
it whenever anything it read changed. That is what makes the view follow another
document without a cell of its own, and it is the form's whole purpose: to
follow a selection, not to run an arbitrary computation.

A computed `source` does not survive a save. The file holds the reference the
cell last produced, because the notation cannot write a computation. Use the
document form for a view that must keep following after a load.

# Example

    SelectionInspector(other_document)

See also [`ReferenceInspector`](@ref), which shows a reference the hover probe
found rather than a selection.
"""
@document struct SelectionInspector
    source::Any = nothing
end

# The macro's keyword form takes the field; these are the positional spellings
# the docstring promises.
#
# A function goes into a **computed cell**, whose thunk it becomes. Reading
# `source` then re-runs it whenever anything it read changed, which is what makes
# the view follow another document's selection with no cell in the printer. A
# plain `Cell` would store the function as a value, and the view would show
# nothing at all, because a function is not a reference.
SelectionInspector(source::Function) = SelectionInspector(; source = ComputedCell(source))
SelectionInspector(source) = SelectionInspector(; source = source)

# The name the tab calls itself, and the name a person types into an empty tab
# to open one.
get_document_title(::SelectionInspector) = "Selection"
get_insertion_aliases(::Type{SelectionInspector}) = ["selection"]

# A source is a live document or a computation, and neither is notation: a
# restored view follows the editor's own selection instead, which is what a
# `SelectionInspector` shows with no source at all. So a save writes nothing,
# and a load gets that same default.
pred_arguments(::SelectionInspector) = (), Pair{Symbol,Any}[]

"""
    find_inspected_selection(source, root) -> Reference or Nothing

The selection `source` names, or `nothing` when there is none to show. `root` is
the document the editor holds, which a `nothing` source falls back to.

Three forms answer, because a function never reaches here: a reactive field
holding one answers the reference the function produced.
"""
find_inspected_selection(source::Reference, root) = source
find_inspected_selection(source::Document, root) = get_selection(source)
find_inspected_selection(::Nothing, root) = root === nothing ? nothing : get_selection(root)
find_inspected_selection(source, root) = nothing

"""
    get_inspected_document(source, root) -> Document or Nothing

The document the shown selection points into. A reference is read against the
editor's own document, because a reference alone does not say what it is a
reference to.
"""
get_inspected_document(source::Document, root) = source
get_inspected_document(source, root) = root
