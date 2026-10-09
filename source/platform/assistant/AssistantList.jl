# Fragment of `AssistantModule` — the list of the open assistants of the session:
# one document that the Assistants pane shows, whose rows compute from a source
# that the application gives.

"""
    AssistantList()

The assistants that are open in the session, as one document: `assistants`
computes them from `source`, a function that answers them in the order of the
rows, or `nothing` while no application gave one
([`set_assistant_list_source!`](@ref)). The application gives a source that
reads the tabs of its window, so a tab that opens, closes or comes back with an
undo changes the rows, and an edit inside an assistant does not compute them
again. `selected` is the assistant whose detail the pane shows, or `nothing`.
`opener` is what Show does, `opener(editor, assistant)`, or `nothing` while no
application gave one ([`set_assistant_list_opener!`](@ref)).

Every list that a person opens is the list of the session
([`get_session_assistant_list`](@ref)): the toolbar, a name typed into an empty
tab and the load of a file all give it.

The list is opaque to the walk of the documents (`is_walk_opaque`). Its rows are
the assistants of the tabs, which the walk reaches there, and its source and its
opener are functions, which are no documents.

# Example

    list = get_session_assistant_list()
    [compute_assistant_overview_title(a) for a in list.assistants]
"""
@document struct AssistantList <: Document
    assistants::Any
    selected::Any
    source::Any
    opener::Any
end

function AssistantList()
    list = AssistantList(Cell(Assistant[]), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    set_cell_computation!(getfield(list, :assistants), () -> begin
        source = getfield(list, :source)[]
        source === nothing ? Assistant[] : collect(Assistant, source())
    end)
    list
end

get_document_title(::AssistantList) = "Assistants"
get_insertion_aliases(::Type{AssistantList}) = ["assistants"]

# The list is a tool pane of the session: a paste does not replace it, and a
# duplicate would be the same list.
accepts_pasted_document(::AssistantList) = false
has_document_duplicate(::AssistantList) = false
is_walk_opaque(::AssistantList) = true

# Made at the first use, so no cell is made when the package loads.
const _SESSION_ASSISTANT_LIST = Ref{Any}(nothing)

"""
    get_session_assistant_list() -> AssistantList

The one list of the open assistants of the session, made at the first call.
"""
function get_session_assistant_list()
    list = _SESSION_ASSISTANT_LIST[]
    list === nothing || return list
    _SESSION_ASSISTANT_LIST[] = AssistantList()
end

make_insertion_document(::Type{AssistantList}) = get_session_assistant_list()

# A file keeps that a tab shows the list, not the rows, which belong to a session.
pred_arguments(::AssistantList) = (), Pair{Symbol,Any}[]
make_pred_document(::Type{<:AssistantList}, positional, keywords) = get_session_assistant_list()

"""
    set_assistant_list_source!(list, source) -> list

Say where the open assistants come from: `source()` answers them, in the order
of the rows. The application gives a source that reads the tabs of its window,
with `collect_pane_tab_contents`. A source that reads cells makes the rows
follow those cells. `nothing` empties the list.
"""
function set_assistant_list_source!(list::AssistantList, source)
    list.source = source
    list
end

"""
    set_assistant_list_opener!(list, action) -> list

Say what Show does: `action(editor, assistant)` puts the tab of `assistant` on
the screen of the editor that evaluates the press. The application gives an
action that focuses the tab that shows the assistant, or opens it again. It
captures no editor, because no document stores one.
"""
function set_assistant_list_opener!(list::AssistantList, action)
    list.opener = action
    list
end

"""
    open_assistant_tab(editor, list, assistant)

Put the tab of `assistant` on the screen of `editor`, as the application said;
`nothing` when no application gave an opener.
"""
function open_assistant_tab(editor, list::AssistantList, assistant::Assistant)
    action = list.opener
    action === nothing ? nothing : action(editor, assistant)
end

"""
    select_assistant!(list, assistant) -> list

Show the detail of `assistant` in the pane of `list`; `nothing` shows none.
"""
function select_assistant!(list::AssistantList, assistant)
    list.selected = assistant
    list
end
