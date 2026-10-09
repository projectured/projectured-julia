# Fragment of `WorkflowModule` — the catalog of the workflows of a folder: one row
# for each `.pred` file that holds a workflow, the last worked on first.

"""
    WorkflowCatalogToWidget(; styles…)

Draw a [`WorkflowCatalog`](@ref): a button that reads the folder again, and a
table with one row for each `.pred` file of the folder whose document is a
`WorkflowStep`. A row says the goal of the workflow, the state of its root, its
active steps, the time of its last entry, the count of its open decisions and the
name of its file. The rows with the latest entry come first. A press on the goal
of a row answers `OpenFileOperation` of the file, so the workflow opens in a tab
and continues there.

The view reads the folder when it is built: a press on "Read again" counts up the
`version` of the catalog, and the view reads the folder again. The count is the
state of the view, so a history does not record it.
"""
@projection UntrackedCell struct WorkflowCatalogToWidget <: Projection
    muted_text::StyleText = get_workflow_style(nothing, :muted_text)
    gap::Int = get_workflow_style(nothing, :gap)
end

"""
    collect_workflow_files(folder) -> Vector{Pair{String, WorkflowStep}}

Every `.pred` file directly in `folder` whose document is a `WorkflowStep`, as
`path => workflow`, the one with the latest entry first. A file that does not
parse, or that holds another document, is left out.
"""
function collect_workflow_files(folder::AbstractString)
    found = Pair{String, WorkflowStep}[]
    isdir(folder) || return found
    for name in readdir(folder)
        endswith(lowercase(name), ".pred") || continue
        path = joinpath(folder, name)
        document = try
            parse_pred_text(read(path, String))
        catch
            nothing
        end
        document isa WorkflowStep && push!(found, path => document)
    end
    sort!(found; by = pair -> _get_last_entry_time(last(pair)), rev = true)
end

# The text of the time of the latest entry of the tree under `workflow`, or an
# empty text for a workflow with no entry.
function _get_last_entry_time(workflow)
    entries = collect_workflow_entries(workflow)
    isempty(entries) ? "" : last(last(entries)).time
end

# The steps under `workflow` that are active, the root too, in the order of the tree.
function _collect_active_steps(node, found = Any[])
    node isa WorkflowStep && node.state === :active && push!(found, node)
    is_workflow_node(node) || return found
    for child in get_workflow_node_children(node)
        _collect_active_steps(child, found)
    end
    found
end

# The count of the decisions under `workflow` that have no chosen option.
function _count_open_decisions(node)
    is_workflow_node(node) || return 0
    own = node isa WorkflowDecision && !any(option -> option.state === :chosen, node.options) ? 1 : 0
    own + sum((_count_open_decisions(child) for child in get_workflow_node_children(node)); init = 0)
end

print_document(p::WorkflowCatalogToWidget, recursion, catalog::WorkflowCatalog, ctx) =
    SimpleIoMap(p, catalog, Cell(@computation _build_catalog_view(p, catalog)))

function _build_catalog_view(p::WorkflowCatalogToWidget, catalog::WorkflowCatalog)
    version = catalog.version
    again = _make_workflow_button("Read again", "Read the folder again",
        () -> ReplaceViewStateOperation(ReplaceReferencedValueOperation(catalog, "version", version + 1)))
    headers = Any[WidgetLabel(text) for text in ("workflow", "state", "active", "last entry",
                                                 "open decisions", "file")]
    rows = Any[_make_catalog_row(p, path, workflow) for (path, workflow) in collect_workflow_files(catalog.folder)]
    isempty(rows) && push!(rows, Any[WidgetLabel("no workflow in " * catalog.folder; text_style = p.muted_text),
                                    WidgetLabel(""), WidgetLabel(""), WidgetLabel(""), WidgetLabel(""), WidgetLabel("")])
    VerticalLayout(Any[HorizontalLayout(Any[again]), WidgetTable(headers, rows)]; gap = p.gap, child_width = Fill)
end

function _make_catalog_row(p::WorkflowCatalogToWidget, path::AbstractString, workflow::WorkflowStep)
    goal = workflow.title.value
    open = _make_workflow_button(isempty(goal) ? basename(path) : goal, "Open the workflow in a tab",
                                 () -> OpenFileOperation(path))
    Any[open,
        WidgetLabel(string(workflow.state)),
        WidgetLabel(join((step.title.value for step in _collect_active_steps(workflow)), ", ")),
        WidgetLabel(_format_readable_time(_get_last_entry_time(workflow)); text_style = p.muted_text),
        WidgetLabel(string(_count_open_decisions(workflow))),
        WidgetLabel(basename(path); text_style = p.muted_text)]
end

map_reference_forward(p::WorkflowCatalogToWidget, iomap, reference) = find_introduced_path(p, reference)
