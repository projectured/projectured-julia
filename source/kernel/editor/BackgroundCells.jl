# Fragment of `EditorModule` — the background cell: a cell whose value a task
# computes off the loop. A read never waits: a cell whose answer does not belong to
# its inputs now answers its last answer, or its default, is provisional, and
# records a demand at its source. After the print of a frame, the editor starts the
# work of each source with demands on a task, and the answers come back through
# the inbox, so only the editor task writes a cell.

"""
    BackgroundSource(work; description = "")

The work that computes the values of background cells off the loop, and the
batch of cells that one task computes together: in each frame, one task for each
source computes every value that its cells demanded in that frame.

`work(inputs)` takes the inputs of the demanded cells, a vector of the values
that the loop read for them, and answers a vector of their values in the same
order. It runs on a task of its own and reads no document. An exception that it
throws is the answer of each cell of the batch, and so is an answer that is no
vector of that count; a read of such a cell throws it. A source is one object: two
sources with the same work are two batches.

# Example

    # One source for each folder: one task reads the heads of the demanded files.
    records = BackgroundSource(inputs -> [read_run_record(path) for (path, _, _) in inputs];
                               description = "the records of a folder")

See also [`make_background_cell`](@ref).
"""
mutable struct BackgroundSource
    const work::Function
    const description::String
end

BackgroundSource(work::Function; description::AbstractString = "") = BackgroundSource(work, String(description))

# A source holds a function, whose closure can reach the editor, so a walk of the
# documents, such as the search of a roster, does not enter it.
DocumentModule.is_walk_opaque(::BackgroundSource) = true

# The answer of a work that threw, which a read of its cell throws.
struct _BackgroundFailure
    exception::Any
end

# What a background cell keeps outside the graph: its source, the cell of its last
# answer, which only the write of an answer changes, the inputs of the demand that
# waits or runs, and the numbers of the last demand and of the demand that the
# answer belongs to, so an answer that comes after a newer one is dropped; and the
# cell that says that its work runs, and the function that stores an answer in the
# document that owns the cell, each `nothing` when the cell has none.
mutable struct _BackgroundCellState
    source::BackgroundSource
    answer::Cell                      # (inputs = ..., value = ...), or nothing
    has_demand::Bool
    demanded::Any                     # the inputs of the demand, while `has_demand`
    demand_count::Int                 # the number of the last demand
    answered_demand::Int              # the number of the demand of the answer
    working::Any                      # Cell{Bool}, or nothing
    apply::Any                        # (inputs, value) -> Operation or nothing, or nothing
end

"""
    BackgroundDemands()

The demands of the frames of one editor, a session document of the editor: each
background cell whose value a computation asked for, with its inputs, in the
order of the asks. [`start_background_cell_work!`](@ref) takes them after the
print of a frame. A computation adds to it, as to a collector outside the graph,
which no computation reads.
"""
mutable struct BackgroundDemands
    lock::ReentrantLock
    entries::Vector{Tuple{_BackgroundCellState,Any,Int}}
end

BackgroundDemands() = BackgroundDemands(ReentrantLock(), Tuple{_BackgroundCellState,Any,Int}[])

"""
    make_background_cell(source, inputs; default = nothing, working = nothing, apply = nothing) -> Cell

A cell whose value `source` computes off the loop, from the values that
`inputs()` reads on the loop. `inputs` is a function of no argument, a
computation of cells, such as the path, the size and the time of a file; its
answer is the input of the work, as a value.

A read never waits. When the cell has an answer for its inputs now, it answers
it. Else it answers its last answer, or `default` when it has none, it is
provisional (`is_cell_provisional`), and it records a demand: after the print of
the frame, the editor starts the work of `source`, and the answer makes the cell
final. A provisional cell computes again at each read by a computation, so it asks
wherever a computation uses it, also when it computed before where it asked
nobody. A cell whose inputs are provisional records no demand, so a work never
runs on values that are still to come, and neither does a read inside a walk of
the documents that starts no background work (`is_background_work_allowed`). A
change of an input makes the cell provisional again, and it answers its last
answer until the new one comes.

`working`, when given, is a cell of a `Bool` that the editor makes `true` when it
starts the work of the cell, after the print of a frame, and `false` when it writes
the answer. A part that says that a value is still read, such as the mark of a
row, reads it as a plain cell, so it asks for nothing.

`apply`, when given, stores an answer in the document that owns the cell as well:
`apply(inputs, value)` answers an operation, or `nothing`, which the editor
evaluates right after it writes the answer for `inputs`. A work that threw passes
its exception as `value`. With no editor, as in a script that calls
[`wait_for_cell!`](@ref) with `editor = nothing`, the operation is evaluated with
`nothing` as its editor. So a value whose answer is documents that a person sees,
such as the entries of a folder, keeps them where they are, and changes them by
the operation, as an edit does.

# Example

    records = BackgroundSource(inputs -> [read_run_record(path) for (path, _, _) in inputs])
    record = make_background_cell(records, () -> (entry.path, entry.size, entry.modified);
                                  default = EMPTY_RUN_RECORD)

Outside an editor, a read records no demand; [`wait_for_cell!`](@ref) computes the
final value. Make the cell where a document is built, never inside a computation:
a cell that a computation makes is new at each run, so it would ask again at each
answer. See also [`BackgroundSource`](@ref).
"""
function make_background_cell(source::BackgroundSource, inputs::Function; default = nothing,
                              working = nothing, apply = nothing)
    state = _BackgroundCellState(source, Cell(nothing), false, nothing, 0, 0, working, apply)
    inputs_cell = Cell(Computation(inputs))
    Cell(@computation _compute_background_value(state, inputs_cell, default))
end

function _compute_background_value(state::_BackgroundCellState, inputs_cell::Cell, default)
    # A provisional input makes this computation provisional by the read.
    inputs = inputs_cell[]
    is_waiting = is_cell_provisional(inputs_cell)
    answer = state.answer[]
    if answer !== nothing && isequal(answer.inputs, inputs)
        answer.value isa _BackgroundFailure && throw(answer.value.exception)
        return answer.value
    end
    is_waiting || _record_background_demand!(state, inputs)
    mark_computation_provisional!()
    (answer === nothing || answer.value isa _BackgroundFailure) ? default : answer.value
end

# Record the demand of `state` for `inputs`, unless a demand for them waits or runs:
# in the collector of `wait_for_cell!` on this task, or else in the one of the editor
# of the evaluation, which it wakes, so a frame follows and starts the work. Outside
# both, and inside a walk that starts no background work, a read records nothing.
function _record_background_demand!(state::_BackgroundCellState, inputs)
    is_background_work_allowed() || return nothing
    local_demands = get(task_local_storage(), :projectured_background_demands, nothing)
    if local_demands !== nothing
        state.demand_count += 1
        lock(() -> push!(local_demands.entries, (state, inputs, state.demand_count)), local_demands.lock)
        return nothing
    end
    editor = find_evaluation_editor()
    editor isa Editor || return nothing
    state.has_demand && isequal(state.demanded, inputs) && return nothing
    state.has_demand = true
    state.demanded = inputs
    state.demand_count += 1
    demands = get_session_document!(BackgroundDemands, editor, BackgroundDemands)
    lock(() -> push!(demands.entries, (state, inputs, state.demand_count)), demands.lock)
    wake_editor!(editor)
    nothing
end

# Take the demands of `demands`, grouped by their source, in the order of the asks.
function _take_background_demands!(demands::BackgroundDemands)
    entries = lock(demands.lock) do
        taken = demands.entries
        demands.entries = Tuple{_BackgroundCellState,Any,Int}[]
        taken
    end
    batches = IdDict{BackgroundSource,Vector{Tuple{_BackgroundCellState,Any,Int}}}()
    sources = BackgroundSource[]
    for entry in entries
        source = first(entry).source
        haskey(batches, source) || push!(sources, source)
        push!(get!(() -> Tuple{_BackgroundCellState,Any,Int}[], batches, source), entry)
    end
    [(source, batches[source]) for source in sources]
end

# The answers of the work of `source` for `inputs`, one for each, or a failure for
# each when the work threw, also at a stop, or answered no vector of that count. So
# every demand gets an answer, and no cell waits for one that never comes. The work
# gets a copy of the inputs, which it can change.
function _run_background_work(source::BackgroundSource, inputs::Vector{Any})
    answers = try
        source.work(copy(inputs))
    catch exception
        return Any[_BackgroundFailure(exception) for _ in inputs]
    end
    answers isa AbstractVector && length(answers) == length(inputs) && return collect(Any, answers)
    failure = _BackgroundFailure(ArgumentError(string("the work of ", repr(source.description), " answered ",
                                                      summary(answers), " for ", length(inputs), " inputs")))
    Any[failure for _ in inputs]
end

"""
    start_background_cell_work!(editor) -> nothing

Start the work of each source whose background cells a computation of `editor`
asked for since the last call: one task for each source, with the inputs of all
its demands, and the answers come back through the inbox
([`WriteBackgroundAnswersOperation`](@ref)). The frame calls it after its print,
when the reads of the frame are done. A test that drives frames by hand calls
`run_frame!`, which calls it.
"""
function start_background_cell_work!(editor::Editor)
    demands = get_session_document!(BackgroundDemands, editor, BackgroundDemands)
    for (source, batch) in _take_background_demands!(demands)
        states = Any[state for (state, _, _) in batch]
        foreach(_mark_background_work!, states)
        inputs = Any[input for (_, input, _) in batch]
        numbers = Int[number for (_, _, number) in batch]
        description = isempty(source.description) ? "the work of background cells" : source.description
        start_background_work(; description, editor, parent = nothing) do
            answers = _run_background_work(source, inputs)
            _post_background_answers!(editor, WriteBackgroundAnswersOperation(states, inputs, numbers, answers))
        end
    end
    nothing
end

# Say that the work of the cell of `state` runs, for a part that shows it.
function _mark_background_work!(state::_BackgroundCellState)
    working = state.working
    working === nothing || working[] === true || (working[] = true)
    nothing
end

# Hand the answers to the editor; an editor whose loop ended takes none.
function _post_background_answers!(editor::Editor, operation)
    try
        post_operation!(editor, ReplaceViewStateOperation(operation))
    catch exception
        exception isa InvalidStateException || rethrow()
    end
    nothing
end

"""
    WriteBackgroundAnswersOperation(states, inputs, numbers, answers)

Write the answers of one work of a source into its background cells: the answer
for `inputs[i]` of the cell of `states[i]`, which demand `numbers[i]` asked for.
An answer to a demand older than the demand of the answer that the cell holds is
dropped, so a slow work does not overwrite the answer of a newer one. The write of
an answer invalidates the readers of the cell, as any write does, so the next read
computes them again, and a cell whose inputs did not change since its demand is
final. It ends the mark of the work of a cell (`working`), and it stores each
answer in the document of its cell (`apply`). It is a write of view state, so undo
records none.
"""
struct WriteBackgroundAnswersOperation <: Operation
    states::Vector{Any}
    inputs::Vector{Any}
    numbers::Vector{Int}
    answers::Vector{Any}
end

function OperationModule.evaluate_operation(editor::Editor, operation::WriteBackgroundAnswersOperation)
    _write_background_answers!(editor, operation.states, operation.inputs, operation.numbers, operation.answers)
    nothing
end

# Write each answer that is not older than the one that its cell holds, end the
# mark of a work for which no newer demand waits, and store the answer in the
# document of the cell, with `editor`, which can be `nothing`.
function _write_background_answers!(editor, states, inputs, numbers, answers)
    for (state, input, number, value) in zip(states, inputs, numbers, answers)
        number > state.answered_demand || continue
        state.answered_demand = number
        state.answer[] = (inputs = input, value = value)
        if number == state.demand_count
            state.has_demand = false
            state.demanded = nothing
            working = state.working
            working === nothing || working[] === false || (working[] = false)
        end
        apply = state.apply
        apply === nothing && continue
        operation = apply(input, value isa _BackgroundFailure ? value.exception : value)
        operation === nothing || evaluate_operation(editor, operation)
    end
    nothing
end

"""
    wait_for_cell!(cell; editor = find_evaluation_editor(), timeout = 60) -> value

The final value of `cell`: a value that is not provisional. A cell whose value
background cells give waits until their work is done, and the call writes their
answers.

On the task that owns the documents of `editor`, the task of its loop or of its
running code unit, and with no editor or no loop, the call computes the demanded
values itself, on the calling task, and writes them. From another task, it reads
the cell through the loop of `editor` until the value is final, and the frames
of the editor start the work. It throws an `ErrorException` when the value is still
provisional after `timeout` seconds, and at once on the task that owns the
documents when nothing below the cell asks for a value.

Use it in a script, a verb or a test that needs the final value, such as the
records of a folder for a table that it writes to a file. A computation can not
call it, because a computation never waits: there it throws an `ArgumentError`.
"""
function wait_for_cell!(cell::AbstractCell; editor = find_evaluation_editor(), timeout::Real = 60)
    is_computation_running() && throw(ArgumentError(
        "wait_for_cell! waits and writes cells, so a computation can not call it"))
    deadline = time() + timeout
    if !(editor isa Editor) || editor.loop_task === nothing || _is_editor_owner(editor)
        return _wait_for_cell_here(editor isa Editor ? editor : nothing, cell, deadline, timeout)
    end
    while true
        remaining = max(1.0, deadline - time())
        (value, is_provisional) = run_on_editor_task!(editor; description = "wait for a cell",
                                                      timeout = remaining) do
            _read_through_computation(cell)
        end
        is_provisional || return value
        time() < deadline || _throw_wait_timeout(timeout)
        sleep(0.05)
    end
end

# The value of `cell` and whether it is provisional, as a computation reads it: a
# provisional cell below it computes again at that read, so each background cell
# below it records its demand where this read runs.
function _read_through_computation(cell::AbstractCell)
    probe = Cell(@computation cell[])
    value = probe[]
    (value, is_cell_provisional(probe))
end

# Read `cell` with a collector of this task, compute what it demanded, and read
# it again, until it is final.
function _wait_for_cell_here(editor, cell::AbstractCell, deadline::Real, timeout::Real)
    while true
        # The collector of this call records each demand, also one that a task of
        # the editor computes already: its answer would come through the inbox,
        # which nothing drains while this call waits.
        demands = BackgroundDemands()
        (value, is_provisional) = task_local_storage(:projectured_background_demands, demands) do
            _read_through_computation(cell)
        end
        is_provisional || return value
        batches = _take_background_demands!(demands)
        # On this task nothing else computes a value, so a provisional cell that
        # asks for nothing stays as it is.
        isempty(batches) && error("wait_for_cell!: the value of the cell is provisional, and no background ",
                                  "cell below it asks for a value")
        time() < deadline || _throw_wait_timeout(timeout)
        for (source, batch) in batches
            inputs = Any[input for (_, input, _) in batch]
            _write_background_answers!(editor, Any[state for (state, _, _) in batch], inputs,
                                       Int[number for (_, _, number) in batch],
                                       _run_background_work(source, inputs))
        end
    end
end

_throw_wait_timeout(timeout) =
    error("wait_for_cell!: the value of the cell is still provisional after ", timeout, " seconds")

# A walk of the documents that starts background work waits for the final value
# of each provisional cell that it reads. Inside a computation, or when nothing
# below the cell asks, it takes the value as it is.
function DocumentModule.complete_walked_cell(cell::ReactiveCell)
    value = cell[]
    (is_computation_running() || !is_cell_provisional(cell)) && return value
    try
        wait_for_cell!(cell)
    catch exception
        is_fault_exception(exception) || rethrow()
        value
    end
end
