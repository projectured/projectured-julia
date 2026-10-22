# Fragment of `BackgroundWorkModule` — the page of the log of the background
# work: a line that counts the works, and under it the table of the log, which the
# grid prints through the recursion, so a path in it is a path of the log.
#
#     table.<rest>    children[2].<rest>

"""
    BackgroundWorkLogToWidget(; gap)

Draw a [`BackgroundWorkLog`](@ref): a line that says how many works run and how
many of the shown ones failed, and under it the table of the log, which fills the
rest of the height. A row of the table shows a work: its number, its source, its
count of values, its start, its time or "running", its state, its first failure
and its first inputs. A person filters and sorts the table in its bar.
"""
@projection UntrackedCell struct BackgroundWorkLogToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
end

const _LINE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
const _TABLE_PLACE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))
const _TABLE_STEP = FieldReferenceStep("table")

# The line above the table: the works that run and the works that failed, among the
# rows that the log shows.
function _format_log_line(log::BackgroundWorkLog)
    rows = collect(log.rows)
    isempty(rows) && return "No background work yet."
    running = count(row -> row.state == "running", rows)
    failed = count(row -> row.state == "failed", rows)
    parts = String[string(length(rows), length(rows) == 1 ? " work" : " works")]
    running > 0 && push!(parts, string(running, " running"))
    failed > 0 && push!(parts, string(failed, " failed"))
    join(parts, " · ")
end

function print_document(p::BackgroundWorkLogToWidget, recursion, log::BackgroundWorkLog, ctx)
    line = WidgetLabel("")
    set_cell_computation!(line, () -> _format_log_line(log))
    output = GridLayout(Any[line, getfield(log, :table)[]], 1; vertical_gap = p.gap, column_policy = Fill,
                        row_policies = Any[Content, Fill])
    iomap = SimpleIoMap(p, log, output)
    # The grid passes a key by its own selection, so it carries the path of the log
    # below it. The table is a document of the log, which holds its own.
    set_output_path_computations!(output, log, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# The rest of `path` after `steps`, or `nothing` when it does not start with them.
function _find_path_below(path, steps)
    for step in steps
        (path isa ConcreteReference && get_reference_head(path) == step) || return nothing
        path = get_reference_tail(path)
    end
    path
end

# `table.<rest>` ↔ the table in the grid.
function map_reference_forward(::BackgroundWorkLogToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    rest = _find_path_below(reference, (_TABLE_STEP,))
    rest === nothing && return nothing
    is_fully_typed_reference(rest) ||
        (rest = annotate_reference_types(getfield(iomap.input, :table)[], strip_reference_types(rest)))
    concat_references(annotate_reference_types(output, extend_reference(EmptyReference(), _TABLE_PLACE_STEPS...)),
                      rest)
end

# A path into the line names nothing, so a press on it leaves the selection where
# it is; a path into the grid itself names the whole log.
function map_reference_backward(::BackgroundWorkLogToWidget, iomap::SimpleIoMap, reference)
    _find_path_below(reference, _LINE_STEPS) === nothing || return nothing
    rest = _find_path_below(reference, _TABLE_PLACE_STEPS)
    rest === nothing ? EmptyReference() : ConcreteReference(_TABLE_STEP, rest)
end

# The generic bridge maps the answer of the grid back. The removal of the last
# entry of the arrangement of the table answers the roster in the place of the
# arrangement; the page keeps the arrangement with no entry instead, so the next
# filter or sort of the table has an arrangement to go to. The page opens the
# record of a row at its place in the log, `rows[j]`.
function read_intent(p::BackgroundWorkLogToWidget, recursion, change::Intent, iomap::SimpleIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    answer isa Intent || return answer
    log = iomap.input
    operation = keep_held_arrangement(answer.operation, getfield(log, :table)[], _TABLE_STEP)
    operation = retarget_held_row_open(operation, log, _TABLE_STEP)
    operation === answer.operation ? answer : Intent(answer.gesture, operation, answer.description, answer.domain)
end

# The log draws as its page inside any document that a renderer draws; the table
# comes back through the recursion of the renderer.
make_graphics_projection(::Type{<:BackgroundWorkLog}; measure, appearance) =
    ChainingProjection(
        BackgroundWorkLogToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        GridLayoutToGraphicsCanvas())
