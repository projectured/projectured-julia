# Fragment of `ExplorerModule` — the search below a node of an explorer: the nodes
# below it whose label holds a text, as deep as a depth and as many as a limit. A
# node whose children are still to come asks for them, so the search reads a
# folder that nobody opened, and its matches grow as the answers come. A search is
# a work item of the task list of the session, and Return in the field of the
# filter starts one.

"""
    ExplorerSearch(root, steps, text; depth = 10, limit = 100, identifier = "")

The search for `text` below the node at `steps` from `root`, the root section of
an explorer: each node below it whose label holds every word of the text, in any
case, at most `depth` levels down and at most `limit` of them, in the order of the
tree. A node whose children a task reads asks for them (`demand_tree_children`),
so the matches are provisional while a node below waits, and they grow as the
answers come. A node on the path to itself is not entered again, and a lazy list
of children gives its first `limit` nodes.

It is a work item of the task list: its row and its page say how many nodes it
waits for and what it found, and the search goes on while one of them shows. A
stop keeps the matches, and the search reads nothing more.

# Fields

- `root` — the root section of the explorer, where the steps of a match start.
- `steps` — the steps from `root` to the node below which it searches.
- `text` — the words that a label holds.
- `depth`, `limit` — how many levels down it looks, and how many matches it keeps.
- `identifier` — `S1`, `S2`, …: its name in the task list of its session.
- `started` — the time of its start, in seconds.
- `stopped` — whether a stop ended it, and `kept`, the result at the stop.
- `result` — computed: the matches, each a document with its steps from the node
  and the labels of the nodes above it, the count of the nodes that it waits for,
  whether a limit stopped it, and the time from the start to a final result.

Use it to find a node of an explorer that nobody opened yet.

# Example

    search_1 = ExplorerSearch(get_session_explorer_content(), Any[], "smoke")
    [format_tree_node_label(match.document) for match in search_1.result.matches]

See also `Explorer` and `ExplorerFilter`.
"""
@document struct ExplorerSearch <: Document
    root::Any
    steps::Any                        # Vector of the reference steps from `root` to the node
    text::String
    depth::Int
    limit::Int
    identifier::String
    started::Float64
    stopped::Bool
    kept::Any
    result::Any
end

# The entry of the walk of a search for one node: its steps from the node of the
# search, the labels of the nodes from that node down to it, its level below that
# node, the documents above it, the cell that asks for its children, the cell of
# its matches, and the entries of its children, which the walk makes once.
struct _SearchEntry
    document::Any
    steps::Vector{Any}
    labels::Vector{String}
    level::Int
    above::Vector{Any}
    demand::Cell
    matches::Cell
    children::IdDict{Any,_SearchEntry}
end

function ExplorerSearch(root, steps::AbstractVector, text::AbstractString;
                        depth::Integer = 10, limit::Integer = 100, identifier::AbstractString = "")
    search = ExplorerSearch(Cell(root), Cell(Any[steps...]), Cell(String(text)), Cell(Int(depth)), Cell(Int(limit)),
                            Cell(String(identifier)), Cell(time()), Cell(false), Cell(nothing), Cell(nothing))
    node = evaluate_reference(root, extend_reference(EmptyReference(), steps...))
    words = split(lowercase(text))
    top = _make_search_entry(search, words, node, Any[], String[format_tree_node_label(node)], 0, Any[])
    set_cell_computation!(getfield(search, :result), () -> _compute_search_result(search, top))
    search
end

function _make_search_entry(search, words, document, steps, labels, level, above)
    demand = Cell(@computation (demand_tree_children(document); nothing))
    entry = _SearchEntry(document, steps, labels, level, above, demand, Cell(nothing), IdDict{Any,_SearchEntry}())
    set_cell_computation!(entry.matches, () -> _compute_entry_matches(search, words, entry))
    entry
end

_is_search_match(words, document) =
    (label = lowercase(format_tree_node_label(document)); all(word -> occursin(word, label), words))

# The matches below `entry`, in the order of the tree, at most the limit of the
# search: each child whose label matches, then the matches below the child. A
# child below the depth is not entered, and the search says that the depth
# stopped it there; a child on the path to itself is not entered either.
function _compute_entry_matches(search, words, entry::_SearchEntry)
    entry.demand[]
    waiting = is_cell_provisional(entry.demand) ? 1 : 0
    limit = search.limit
    matches = Any[]
    (is_limited, is_deep) = (false, false)
    above = vcat(entry.above, Any[entry.document])
    seen = IdDict{Any,Nothing}()
    for (reference, child) in collect_tree_children(entry.document; limit = typemax(Int), list_limit = limit)
        steps = vcat(entry.steps, collect(get_reference_steps(reference)))
        if _is_search_match(words, child)
            push!(matches, (document = child, steps = steps, labels = entry.labels))
            length(matches) >= limit && (is_limited = true; break)
        end
        (any(other -> other === child, above) || has_tree_children(child) === false) && continue
        if entry.level + 1 >= search.depth
            is_deep = true
            continue
        end
        seen[child] = nothing
        below = get!(entry.children, child) do
            _make_search_entry(search, words, child, steps, vcat(entry.labels, format_tree_node_label(child)),
                               entry.level + 1, above)
        end
        found = below.matches[]
        append!(matches, first(found.matches, limit - length(matches)))
        waiting += found.waiting
        is_deep |= found.is_deep
        (found.is_limited || length(matches) >= limit) && (is_limited = true; break)
    end
    for child in collect(keys(entry.children))
        haskey(seen, child) || delete!(entry.children, child)
    end
    (; matches, waiting, is_limited, is_deep)
end

# The result of `search`: the matches below its node, and the time that it took
# once no node waits. A stopped search answers what it kept and reads nothing.
function _compute_search_result(search::ExplorerSearch, top::_SearchEntry)
    search.stopped && return search.kept
    found = top.matches[]
    elapsed = is_cell_provisional(top.matches) ? nothing : time() - search.started
    (; found.matches, found.waiting, found.is_limited, found.is_deep, elapsed)
end

# A search is no content that a walk of the documents enters: it holds the root
# section again, and its result reads the tree below its node.
is_walk_opaque(::ExplorerSearch) = true

_get_search_node_label(search::ExplorerSearch) =
    format_tree_node_label(evaluate_reference(search.root, extend_reference(EmptyReference(), search.steps...)))

get_document_title(search::ExplorerSearch) =
    string("Find \"", search.text, "\" below ", _get_search_node_label(search))
format_tree_node_label(search::ExplorerSearch) = string(search.identifier, " ", get_document_title(search))

# The line of a search: while nodes wait, how many, and what it found; then the
# count of its matches, whether a limit stopped it, and the time that it took.
function _format_search_line(search::ExplorerSearch, result)
    total = length(result.matches)
    found = string(total, total == 1 ? " match" : " matches")
    parts = String[]
    result.waiting > 0 && push!(parts, string("waiting for ", result.waiting, result.waiting == 1 ? " node" : " nodes"))
    push!(parts, found)
    result.is_limited && push!(parts, string("stopped at ", search.limit, " matches"))
    result.is_deep && push!(parts, string("not below a depth of ", search.depth))
    search.stopped && push!(parts, "stopped")
    result.elapsed === nothing || search.stopped || push!(parts, format_elapsed_time(result.elapsed; precision = 1))
    join(parts, " · ")
end

# A search is a work item: it runs while a node below waits, and is done when none
# does. Its decoration reads its result, so a row that shows the search keeps it
# going: that is what the person asked for.
function get_document_decoration(search::ExplorerSearch)
    result = search.result
    condition = search.stopped ? :stopped : is_cell_provisional(getfield(search, :result)) ? :running : :done
    DocumentDecoration(; icon = :search, conditions = [DocumentCondition(condition)],
                       detail = _format_search_line(search, result), work_item = true)
end

get_work_item_identifier(search::ExplorerSearch) = search.identifier
describe_work_item_kind(::ExplorerSearch, count::Integer) = count == 1 ? "search" : "searches"

# A stop keeps the result as it is, and the search reads nothing more.
function stop_work_item!(search::ExplorerSearch)
    search.stopped && return nothing
    search.kept = run_without_cell_tracking(() -> search.result)
    search.stopped = true
    nothing
end

function describe_work_item(search::ExplorerSearch; limit::Integer = 20)
    result = search.result
    lines = String[get_document_title(search), _format_search_line(search, result)]
    for match in first(result.matches, limit)
        push!(lines, string(format_tree_node_label(match.document), " — ", join(match.labels, " / ")))
    end
    length(result.matches) > limit && push!(lines, string("… and ", length(result.matches) - limit, " more"))
    Text(join(lines, "\n"))
end

"""
    StartExplorerSearchOperation(explorer, text)

Start a search for `text` below the node of the page of the navigator of
`explorer`, or below its root when the page is not in its tree: a new
[`ExplorerSearch`](@ref) joins the task list of the session, and the navigator
shows its page. The keys stay where they are. It is no edit, so undo records
none.
"""
struct StartExplorerSearchOperation <: Operation
    explorer::Any
    text::String
end

function evaluate_operation(editor, operation::StartExplorerSearchOperation)
    explorer = operation.explorer
    tree = getfield(explorer, :tree)[]
    navigator = getfield(explorer, :navigator)[]
    root = tree.root
    steps = navigator.content === root ?
            collect(Any, get_reference_steps(strip_reference_types(get_navigator_page_address(navigator)))) : Any[]
    list = get_session_task_group_list(; editor)
    number = count(item -> startswith(get_work_item_identifier(item), "S"), collect(list.groups)) + 1
    search = ExplorerSearch(root, steps, operation.text; identifier = string("S", number))
    add_task_group!(list, search)
    visit = make_navigator_open_operation(navigator, search, EmptyReference())
    visit === nothing || evaluate_operation(editor, _get_visit_writes(visit))
    nothing
end

make_inverse_operation(document, ::StartExplorerSearchOperation) = DoNothingOperation()

# It names its explorer, so it goes up through every projection as it is.
is_self_contained_operation(::StartExplorerSearchOperation) = true

describe_operation(operation::StartExplorerSearchOperation) = string("Find \"", operation.text, "\"")
