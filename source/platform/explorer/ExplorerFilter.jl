# Fragment of `ExplorerModule` — the filter of an explorer: the words and the kinds
# that a row keeps, and the tree of the matches, which the explorer shows in the
# place of its tree while the filter keeps rows out.

"""
    ExplorerFilter(; text = "", kinds = Any[])

The filter of an explorer. `text` holds the words that the label of a row holds,
in any case, and `kinds` the types of the documents that stay, or none for every
type. A row stays when it matches both, or when a row below it that the tree read
stays, and the rows above a row that stays show open. The filter reads the labels
of the rows that the tree read, and so it starts no read of a disk or a process.

Use it to find a row of an explorer by a part of its label.

# Example

    filter_1 = ExplorerFilter(; text = "smoke")

See also `Explorer`.
"""
@document struct ExplorerFilter <: Document
    text::String = ""
    kinds::Vector{Any} = Any[]
end

# Whether `filter` keeps some rows out.
_is_filter_active(filter::ExplorerFilter) = !isempty(strip(filter.text)) || !isempty(filter.kinds)

# Whether `document` matches the words and the kinds of `filter`.
function _is_filter_match(filter::ExplorerFilter, words, document)
    isempty(filter.kinds) || any(kind -> document isa kind, filter.kinds) || return false
    label = lowercase(format_tree_node_label(document))
    all(word -> occursin(word, label), words)
end

# A row of the tree of the matches: a document that matches, or that a match is
# below, the steps from the root section to that document, and the rows below it
# that stay.
@document struct _ExplorerMatch <: Document
    document::Any
    steps::Vector{Any}
    children::Vector{Any}
end

get_tree_children_steps(::_ExplorerMatch) = ((FieldReferenceStep("children"),),)
format_tree_node_label(match::_ExplorerMatch) = format_tree_node_label(match.document)
get_document_decoration(match::_ExplorerMatch) = get_document_decoration(match.document)
get_document_title(match::_ExplorerMatch) = get_document_title(match.document)

# The row of `document` at `steps` in the tree of the matches, with the rows below
# it through the open places `places` of the tree, so it looks only at the rows
# that the tree read; `nothing` when no row there stays. A document that is on the
# path to its own row again stays closed there, so a cycle ends.
function _collect_matches(filter::ExplorerFilter, words, document, steps::Vector{Any}, places, above::Vector{Any})
    children = Any[]
    below = places === nothing ? nothing : get(places, document, nothing)
    if below !== nothing && !any(other -> other === document, above)
        push!(above, document)
        for (reference, child) in collect_read_tree_children(document)
            match = _collect_matches(filter, words, child, vcat(steps, collect(get_reference_steps(reference))),
                                     below, above)
            match === nothing || push!(children, match)
        end
        pop!(above)
    end
    (isempty(children) && !_is_filter_match(filter, words, document)) && return nothing
    _ExplorerMatch(document, steps, children)
end

# The kinds of the rows that the tree read, through its open places, each with its
# name, in the order of the names. A kind is the type of a document with no
# parameters, so a type of cells is one kind.
function _collect_read_kinds(tree)
    kinds = IdDict{Any,Nothing}()
    function visit(document, places, above)
        kinds[Base.typename(typeof(document)).wrapper] = nothing
        below = get(places, document, nothing)
        (below === nothing || any(other -> other === document, above)) && return nothing
        push!(above, document)
        foreach(((_, child),) -> visit(child, below, above), collect_read_tree_children(document))
        pop!(above)
        nothing
    end
    visit(tree.root, tree.expanded, Any[])
    sort!(Pair{String,Any}[_format_kind_name(kind) => kind for kind in keys(kinds)]; by = first)
end

# The menu of `▾`: every kind, and each kind of the rows that the tree read, with a
# check on what the filter keeps. A choice of a kind adds it to the kinds of the
# filter, or takes it out, as view state.
function _make_kind_menu_operation(explorer, gesture)
    filter = getfield(explorer, :filter)[]
    chosen = Any[kind for kind in filter.kinds]
    keep(kinds) = ReplaceViewStateOperation(ReplaceReferencedValueOperation(filter, "kinds", kinds))
    items = Any[WidgetMenuItem("Every kind"; icon = isempty(chosen) ? :check : nothing, operation = keep(Any[]))]
    for (name, kind) in _collect_read_kinds(getfield(explorer, :tree)[])
        is_chosen = any(other -> other === kind, chosen)
        kinds = is_chosen ? Any[other for other in chosen if other !== kind] : vcat(chosen, Any[kind])
        push!(items, WidgetMenuItem(name; icon = is_chosen ? :check : nothing, operation = keep(kinds)))
    end
    make_context_menu_operation(explorer, WidgetMenu(items), gesture)
end

# The open places of `match` and of every row below it.
function _make_match_places(match::_ExplorerMatch)
    below = IdDict{Any,Any}()
    foreach(child -> merge!(below, _make_match_places(child)), match.children)
    IdDict{Any,Any}(match => below)
end

# The path from the root of the tree of the matches to the row whose steps are
# `steps`, or `nothing` when no row has them.
function _find_match_path(root::_ExplorerMatch, steps)
    path = ReferenceStep[]
    match = root
    while match.steps != steps
        k = findfirst(child -> length(child.steps) <= length(steps) && steps[1:length(child.steps)] == child.steps,
                      match.children)
        k === nothing && return nothing
        push!(path, FieldReferenceStep("children"), ElementReferenceStep(k))
        match = match.children[k]
    end
    extend_reference(EmptyReference(), path...)
end

# The tree of the matches of the filter of `explorer`, or `nothing` while the
# filter keeps every row. Its rows are all open, and the row of the page of the
# navigator has the mark.
function _make_match_tree(explorer)
    filter = getfield(explorer, :filter)[]
    _is_filter_active(filter) || return nothing
    tree = getfield(explorer, :tree)[]
    navigator = getfield(explorer, :navigator)[]
    root = tree.root
    words = split(lowercase(filter.text))
    match = _collect_matches(filter, words, root, Any[], tree.expanded, Any[])
    match_root = match === nothing ? _ExplorerMatch(root, Any[], Any[]) : match
    current = () -> _find_match_path(match_root,
                                     collect(get_reference_steps(strip_reference_types(get_navigator_page_address(navigator)))))
    DocumentTree(Cell(match_root), Cell("Matches"), Cell(_make_match_places(match_root)), Cell(IdDict{Any,Nothing}()),
                 Cell(@computation current()), Cell(nothing))
end
