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
state of the view, so a history does not record it. A press on "New workflow"
answers `CreateWorkflowFileOperation`, which writes a new workflow into the folder
and opens it.
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

"""
    create_workflow_file!(folder) -> String

Write a new workflow into `folder`, a `.pred` file whose goal is "New workflow",
named `workflow.pred`, or `workflow-2.pred` and on when that name is taken, and
answer its path.

Use it to start a workflow beside the others of a folder.

# Example

    path_1 = create_workflow_file!("work")
"""
function create_workflow_file!(folder::AbstractString)
    mkpath(folder)
    name = "workflow.pred"
    count = 1
    while isfile(joinpath(folder, name))
        count += 1
        name = "workflow-" * string(count) * ".pred"
    end
    save_file!(PredFile(name, make_insertion_document(WorkflowStep)), folder)
    joinpath(folder, name)
end

"""
    CreateWorkflowFileOperation(catalog)

The request to write a new workflow into the folder of `catalog`, a
[`WorkflowCatalog`](@ref), open it in a tab, and read the folder again. A press on
"New workflow" of the catalog answers it. The file is outside every document, so
the way back does nothing.
"""
struct CreateWorkflowFileOperation <: Operation
    catalog::Any
end

is_self_contained_operation(::CreateWorkflowFileOperation) = true
make_inverse_operation(document, ::CreateWorkflowFileOperation) = DoNothingOperation()

function evaluate_operation(editor, operation::CreateWorkflowFileOperation)
    catalog = operation.catalog
    path = create_workflow_file!(catalog.folder)
    catalog.version = catalog.version + 1
    evaluate_operation(editor, OpenFileOperation(path))
end

# A button of the catalog, which a press answers with `make()`; `name` says what
# the press does.
_make_workflow_button(text::AbstractString, name::AbstractString, make) =
    WidgetButton(text; tooltip = TooltipNote(; title = name),
                 gestures = GestureBinding[
                     GestureBinding(MouseClickPattern(:left), (_, _) -> make();
                                    description = name, domain = "workflow")])
print_document(p::WorkflowCatalogToWidget, recursion, catalog::WorkflowCatalog, ctx) =
    SimpleIoMap(p, catalog, Cell(@computation _build_catalog_view(p, catalog)))

function _build_catalog_view(p::WorkflowCatalogToWidget, catalog::WorkflowCatalog)
    version = catalog.version
    again = _make_workflow_button("Read again", "Read the folder again",
        () -> ReplaceViewStateOperation(ReplaceReferencedValueOperation(catalog, "version", version + 1)))
    create = _make_workflow_button("New workflow", "Write a new workflow into the folder and open it",
                                   () -> CreateWorkflowFileOperation(catalog))
    headers = Any[WidgetLabel(text) for text in ("workflow", "progress", "state", "active", "last entry",
                                                 "open decisions", "file")]
    rows = Any[_make_catalog_row(p, path, workflow) for (path, workflow) in collect_workflow_files(catalog.folder)]
    isempty(rows) && push!(rows, Any[WidgetLabel("no workflow in " * catalog.folder; text_style = p.muted_text),
                                    (WidgetLabel("") for _ in 2:length(headers))...])
    VerticalLayout(Any[HorizontalLayout(Any[create, again]; gap = p.gap), WidgetTable(headers, rows)];
                   gap = p.gap, child_width = Fill)
end

function _make_catalog_row(p::WorkflowCatalogToWidget, path::AbstractString, workflow::WorkflowStep)
    goal = workflow.title.value
    open = _make_workflow_button(isempty(goal) ? basename(path) : goal, "Open the workflow in a tab",
                                 () -> OpenFileOperation(path))
    Any[open,
        _make_catalog_progress(p, workflow),
        WidgetLabel(string(workflow.state)),
        WidgetLabel(join((step.title.value for step in _collect_active_steps(workflow)), ", ")),
        WidgetLabel(_format_readable_time(_get_last_entry_time(workflow)); text_style = p.muted_text),
        WidgetLabel(string(_count_open_decisions(workflow))),
        WidgetLabel(basename(path); text_style = p.muted_text)]
end

# The progress of `workflow` in the catalog: a bar of the share of its steps that are
# done, and the count beside it, such as "1 of 3".
function _make_catalog_progress(p::WorkflowCatalogToWidget, workflow::WorkflowStep)
    (; steps, done) = _count_workflow_progress(workflow)
    HorizontalLayout(Any[WidgetProgressBar(steps == 0 ? 0.0 : done / steps; width = _CATALOG_BAR_WIDTH),
                         WidgetLabel(string(done, " of ", steps); text_style = p.muted_text)];
                     gap = p.gap, vertical_align = :center)
end

"The length of the bar of the progress of a workflow in the catalog, in pixels."
const _CATALOG_BAR_WIDTH = 80

map_reference_forward(p::WorkflowCatalogToWidget, iomap, reference) = find_introduced_path(p, reference)
