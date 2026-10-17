# Fragment of `AssistantModule` — the list of the open assistants of the session:
# one document that the Assistants pane shows, whose rows compute from a source
# that reads the tabs of a window, and the wrapper of `build_editor` that links
# the list to the window.

"""
    AssistantList()

The assistants that are open in the session, as one document: `assistants`
computes them from `source`, a function that answers them in the order of the
rows, or `nothing` while nothing linked the list
([`link_assistant_list!`](@ref)). The link gives a source that reads the tabs of
a window, so a tab that opens, closes or comes back with an undo changes the
rows, and an edit inside an assistant does not compute them again. `selected` is the assistant whose detail the pane shows, or `nothing`.
`opener` is what Show does, `opener(editor, assistant)`, or `nothing` while
nothing linked the list.

Every list that a person opens in a window of an editor is the list of the
session of that editor ([`get_session_assistant_list`](@ref)): the toolbar, a
name typed into an empty tab and the load of a file all give it.

The list is opaque to the walk of the documents (`is_walk_opaque`). Its rows are
the assistants of the tabs, which the walk reaches there, and its source and its
opener are functions, which are no documents.

# Example

    list = get_session_assistant_list(; editor)
    [compute_assistant_overview_title(a) for a in list.assistants]
"""
@document struct AssistantList <: Document
    assistants::Any
    selected::Any
    source::Any
    opener::Any
end

# The rows are a `CellVector`, a document, so the selection of the list goes down
# through a row into the description or the comment of its assistant.
function AssistantList()
    list = AssistantList(Cell(CellVector{Assistant}(Assistant[])), Cell(nothing), Cell(nothing),
                         Cell(nothing), Cell(nothing))
    set_cell_computation!(getfield(list, :assistants), () -> begin
        source = getfield(list, :source)[]
        CellVector{Assistant}(source === nothing ? Assistant[] : collect(Assistant, source()))
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

# The list says how many of its assistants work, and how many wait for the person.
function get_document_decoration(list::AssistantList)
    assistants = collect(list.assistants)
    working = count(a -> a.status === :streaming, assistants)
    waiting = count(a -> !isempty(collect_open_assistant_requests(a)), assistants)
    conditions = DocumentCondition[]
    working > 0 && push!(conditions, DocumentCondition(:running))
    waiting > 0 && push!(conditions, DocumentCondition(:waiting; count = waiting))
    counts = working == 0 ? DocumentCount[] : [DocumentCount(string(working, " working"); role = :accent)]
    DocumentDecoration(; icon = :chats, conditions, counts)
end

"""
    get_session_assistant_list(; editor = find_evaluation_editor()) -> AssistantList

The list of the open assistants of the session of `editor`: by default the editor
of the evaluation, or of the loop that runs the calling code. Each editor has its
own, made at the first call. With no editor, such as while a file loads before
its window exists, a new list, which nothing keeps and no window links.
"""
get_session_assistant_list(; editor = find_evaluation_editor()) =
    editor isa Editor ? get_session_document!(AssistantList, editor, AssistantList) : AssistantList()

make_insertion_document(::Type{AssistantList}) = get_session_assistant_list()

# A file keeps that a tab shows the list, not the rows, which belong to a session.
# A file that loads before its window exists gives a new list, which the window
# makes the list of its session.
pred_arguments(::AssistantList) = (), Pair{Symbol,Any}[]
make_pred_document(::Type{<:AssistantList}, positional, keywords) = get_session_assistant_list()

"""
    set_assistant_list_source!(list, source) -> list

Say where the open assistants come from: `source()` answers them, in the order
of the rows. [`link_assistant_list!`](@ref) gives a source that reads the tabs of
a window, with `collect_pane_tab_contents`. A source that reads cells makes the rows
follow those cells. `nothing` empties the list.
"""
function set_assistant_list_source!(list::AssistantList, source)
    list.source = source
    list
end

"""
    set_assistant_list_opener!(list, action) -> list

Say what Show does: `action(editor, assistant)` puts the tab of `assistant` on
the screen of the editor that evaluates the press. [`link_assistant_list!`](@ref)
gives an action that focuses the tab that shows the assistant, or opens it again. It
captures no editor, because no document stores one.
"""
function set_assistant_list_opener!(list::AssistantList, action)
    list.opener = action
    list
end

"""
    open_assistant_tab!(editor, list, assistant)

Put the tab of `assistant` on the screen of `editor`, as the opener of the list
says; `nothing` when the list has no opener.
"""
function open_assistant_tab!(editor, list::AssistantList, assistant::Assistant)
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

# ── The list of a window, as a wrapper of `build_editor` ─────────────────────

"""
    link_assistant_list!(list, tree) -> list

Make the Assistants pane of `list` show the assistants of the tabs of `tree`, and
make its Show focus the tab of an assistant, or open it again. The wrapper
`assistant_list` links the list of the session of its editor to the pane tree of
its window, and every other list that a tab of the tree holds.
"""
function link_assistant_list!(list::AssistantList, tree::PaneTree)
    set_assistant_list_source!(list, () -> collect_pane_tab_contents(tree, Assistant))
    set_assistant_list_opener!(list, (editor, assistant) ->
        show_document!(assistant; title = get_document_title(assistant), editor))
end

"""
    unlink_assistant_list!(list) -> list

Undo [`link_assistant_list!`](@ref): the list reads no tabs, its Show does
nothing, and it shows no detail, so it holds no document of a closed window.
"""
function unlink_assistant_list!(list::AssistantList)
    set_assistant_list_source!(list, nothing)
    set_assistant_list_opener!(list, nothing)
    select_assistant!(list, nothing)
end

"""
    assistant_list = true

The wrapper of `build_editor` that links the Assistants pane to the tabs of the
window. A start step links every list that a tab of the pane tree holds, which a
file gave before the editor existed, and the list of the session of the editor
([`get_session_assistant_list`](@ref)): the first of those lists, or a new one. A
stop step unlinks them, so no list holds a document of a closed window. While it
is on, the `shell` wrapper puts the button of the pane on the toolbar. It is off
by default, and the window needs a pane tree: the root that the caller gives, or
the one that the `tabs` wrapper makes.
"""
function wrap_editor!(::Val{:assistant_list}, layer::Symbol, argument, parts::EditorParts)
    tree = get_window_tree(parts.document)
    lists = AssistantList[]
    push!(parts.start_steps, editor -> (append!(lists, _link_session_assistant_lists!(editor, tree));
                                        nothing))
    push!(parts.stop_steps, _ -> (foreach(unlink_assistant_list!, lists); nothing))
    parts
end

get_wrapper_layers(::Val{:assistant_list}) = (:screen => 40,)

# Link every assistant list that a tab of `tree` shows, and the list of the
# session of `editor`: the first of them, or a new one. Answer the lists, for the
# unlink.
function _link_session_assistant_lists!(editor::Editor, tree::PaneTree)
    lists = collect_pane_tab_contents(tree, AssistantList)
    session = get_session_document!(() -> isempty(lists) ? AssistantList() : first(lists), editor,
                                    AssistantList)
    any(list -> list === session, lists) || push!(lists, session)
    foreach(list -> link_assistant_list!(list, tree), lists)
    lists
end
