# Fragment of `AssistantModule` — the work page of an assistant: a document that
# holds an assistant and shows the work of the session of its agent, its node in
# the tree of that work, and the verb that shows the page in a tab.

"""
    AssistantWork(assistant)

The work page of `assistant`: a document that holds the assistant and shows the
work of the session of its external agent, its `agent_work`, as a page of a
navigator.

# Fields
- `assistant` — the assistant whose work the page shows.
- `subagents`, `background_tasks`, `plans` and `processes` — the subagents, the
  background tasks, the plans and the tree of the processes of the work of the
  session. They follow the work of a new session. A path from the page names a
  part of the work through them, such as `subagents[1]`, so Parent from the
  page of a subagent comes back to the page.
- `work_tree` — the `DocumentTree` of the page itself: the session, its
  subagents and their background tasks, at every depth.
- `process_tree` — a `DocumentTree` of `processes`, or `nothing` while the agent
  names no process.

The two trees are view state, kept so their open nodes stay when the page draws
again. A walk of the documents does not enter the page, as it does not enter the
list of the assistants: it reaches the work through the tab of the assistant. A
file keeps the assistant of the page and nothing of its work.
"""
@document struct AssistantWork <: Document
    assistant::Any
    subagents::Any
    background_tasks::Any
    plans::Any
    processes::Any
    work_tree::Any
    process_tree::Any
end

function AssistantWork(a::Assistant)
    work = AssistantWork(Cell(a), (Cell(nothing) for _ in 1:7)...)
    for name in (:subagents, :background_tasks, :plans, :processes)
        set_cell_computation!(getfield(work, name), () -> getproperty(a.agent_work, name))
    end
    work.work_tree = DocumentTree(work; title = "Work")
    set_cell_computation!(getfield(work, :process_tree), () -> begin
        processes = a.agent_work.processes
        processes === nothing ? nothing : DocumentTree(processes; title = "Processes")
    end)
    work
end

get_document_title(work::AssistantWork) =
    "Work · " * compute_assistant_overview_title(work.assistant)

# The page shows the work that the tab of its assistant holds, so a walk reaches
# that work there, and the page has no duplicate of its own. A paste does not
# replace it.
is_walk_opaque(::AssistantWork) = true
has_document_duplicate(::AssistantWork) = false
accepts_pasted_document(::AssistantWork) = false

# A file keeps the assistant, and the page draws its work again.
pred_arguments(work::AssistantWork) = (work.assistant,), Pair{Symbol,Any}[]

# The root of the tree of the work is the session: its subagents, then its
# background tasks.
get_tree_children_steps(::AssistantWork) =
    ((FieldReferenceStep("subagents"),), (FieldReferenceStep("background_tasks"),))
format_tree_node_label(::AssistantWork) = "This session"
get_tree_node_icon(work::AssistantWork) =
    is_assistant_turn_running(work.assistant) ? :loader : :bot

# ── The verb ─────────────────────────────────────────────────────────────────

"""
    show_assistant_work!(assistant; editor = get_evaluation_editor())
        -> ReferencedDocument

Show the work page of `assistant` in a tab of the window of `editor`, named
"Work · " and the title of the assistant, and answer the page in its window. A
tab that shows the work of `assistant` already comes to the front. The page
shows the job of the agent, what it does now, its plans, the tree of its work —
the session, its subagents and their background tasks — the tree of its
processes, and its notices. A double click on a node opens its page, and Back
returns.

Use it to see what an external agent works on, how far its plan is, and which
subagents and background tasks run.

# Example

    show_assistant_work!(get_session_assistant_list().assistants[1])

See also `show_document_tree!`, which shows any document as a tree.
"""
function show_assistant_work!(a::Assistant; editor = get_evaluation_editor())
    root = editor.document
    shown = _get_shown_assistant_work(editor, a)
    if shown === nothing
        work = AssistantWork(a)
        title = "Work · " * compute_assistant_overview_title(a)
        tab = open_pane!(Navigator(work); title, editor)
        route = get_reference_steps(strip_reference_types(get_reference(tab)))
    else
        work, route = shown
        # The operation of the focus alone: `focus_pane!` would also print the
        # layout of the window, which walks it.
        tab_path = annotate_reference_types(root, Reference(route...))
        focus = make_focus_pane_operation(tab_path; editor)
        focus === nothing || evaluate_operation(editor, focus)
    end
    # The work is the content of the navigator that the tab holds.
    content = FieldReferenceStep("content")
    reference = Reference(route..., content, content)
    ReferencedDocument(work, annotate_reference_types(root, reference))
end

# The work page of `a` that a tab of a window of `editor` shows, and the steps from
# the root to that tab, or `nothing`. It reads only the windows, their pane trees
# and the content of each tab: a navigator whose content is the work of `a`.
function _get_shown_assistant_work(editor, a::Assistant)
    for (route, tree) in _collect_window_tree_routes(editor.document)
        for group in get_pane_groups(tree), tab in group.tabs
            navigator = tab.content
            navigator isa Navigator || continue
            work = navigator.content
            work isa AssistantWork && work.assistant === a || continue
            path = get_reference_steps(strip_reference_types(get_pane_path(tree, tab)))
            return (work, Any[route..., path...])
        end
    end
    nothing
end

# Each pane tree of the windows of `root`, with the steps from `root` to it: the
# wrappers of the root, the windows of a screen, and the wrappers of the content
# of each window, one field at a time.
function _collect_window_tree_routes(root)
    routes = Tuple{Vector{Any},PaneTree}[]
    _add_window_tree_routes!(routes, root, Any[])
    routes
end

function _add_window_tree_routes!(routes, node, steps::Vector{Any})
    if node isa PaneTree
        push!(routes, (steps, node))
    elseif hasproperty(node, :windows)
        windows = node.windows
        for i in 1:length(windows)
            inside = Any[steps..., FieldReferenceStep("windows"), ElementReferenceStep(i),
                         FieldReferenceStep("content")]
            _add_window_tree_routes!(routes, windows[i].content, inside)
        end
    else
        wrapped = get_wrapped_document(node)
        wrapped === node && return routes
        for name in fieldnames(typeof(node))
            child = getproperty(node, name)
            child !== node && get_wrapped_document(child) === wrapped || continue
            inside = Any[steps..., FieldReferenceStep(String(name))]
            return _add_window_tree_routes!(routes, child, inside)
        end
    end
    routes
end
