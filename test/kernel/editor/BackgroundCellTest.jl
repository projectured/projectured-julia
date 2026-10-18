# The background cell: a cell whose value a task computes off the loop. A read
# answers the last answer or the default, and is provisional; after the frame, one
# task for each source computes the demanded values, and the answer comes back
# through the inbox and makes the cell final. A demand that waits or runs is not
# asked again, a cell whose inputs are provisional asks for nothing, and a work
# that throws makes a read of its cells throw. A cell that computed where it asked
# nobody asks when a computation of the editor reads it, and the first print of an
# editor asks that editor. A search starts no background work by default, and
# waits for it when it is asked to. `wait_for_cell!` computes the final value. A
# cell can say that its work runs, and store its answer in its document.

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IoMapModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, BackgroundSource, BackgroundDemands, make_background_cell,
                                       wait_for_cell!, start_background_cell_work!, drain_operations!,
                                       make_editor
import ProjecturedKernel.ToolModule: run_with_evaluation_editor
import ProjecturedKernel.OperationModule: ReplaceReferencedValueOperation
using ProjecturedKernelExample

@document struct BackgroundCellProbe
    value::Int = 0
end

struct BackgroundCellProjection <: Projection end

ProjectionModule.print_document(::BackgroundCellProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)

# A document whose field holds a background cell, and a projection whose print
# reads it, as a page reads a record.
@document struct BackgroundRecordProbe
    record::Any
end

struct BackgroundRecordProjection <: Projection end

function ProjectionModule.print_document(::BackgroundRecordProjection, recursion, input, ctx)
    input.record
    SimpleIoMap(nothing, input, input)
end

# An editor that draws nothing, with an IoMap, so a frame can run.
function _make_background_editor()
    editor = Editor(BackgroundCellProbe(), BackgroundCellProjection(); backend = HeadlessBackend(),
                    devices = Device[])
    EditorModule.run_print_stage!(editor)
    editor
end

# A source that multiplies each input by ten, and records the inputs of each call
# of its work, which runs on another task. `gate`, when given, holds the work until
# a value is put into it.
function _make_counting_source(calls; gate = nothing)
    calls_lock = ReentrantLock()
    BackgroundSource(; description = "times ten") do inputs
        gate === nothing || take!(gate)
        lock(() -> push!(calls, copy(inputs)), calls_lock)
        Any[10 * input for input in inputs]
    end
end

# Read `cell` as a computation of a frame of `editor` reads it.
_read_in_editor(editor, cell) = run_with_evaluation_editor(() -> cell[], editor)

# Apply what the tasks posted to `editor`, until `cell` is final, for at most ten
# seconds.
function _wait_until_final(editor, cell)
    deadline = time() + 10
    while time() < deadline
        drain_operations!(editor)
        cell[]
        is_cell_provisional(cell) || return true
        sleep(0.01)
    end
    false
end

_count_waiting_demands(editor) =
    length(get(editor.session_documents, BackgroundDemands, BackgroundDemands()).entries)

function test_editor_background_cell()
@testset "background cell" begin

    @testset "a read answers the default and is provisional, and the answer makes it final" begin
        calls = Vector{Any}[]
        input = Cell(1)
        value = make_background_cell(_make_counting_source(calls), () -> input[]; default = 0)
        reader = Cell(@computation value[] + 1)
        editor = _make_background_editor()
        @test _read_in_editor(editor, reader) == 1 && is_cell_provisional(reader)
        # The read starts no work; the frame does, after its print.
        @test isempty(calls) && _count_waiting_demands(editor) == 1
        EditorModule.run_frame!(editor)
        @test _count_waiting_demands(editor) == 0
        @test _wait_until_final(editor, reader)
        @test reader[] == 11 && calls == [[1]]
        # A change of an input makes the cell provisional, with its last answer.
        input[] = 2
        @test _read_in_editor(editor, reader) == 11 && is_cell_provisional(reader)
        start_background_cell_work!(editor)
        @test _wait_until_final(editor, reader)
        @test reader[] == 21 && calls == [[1], [2]]
    end

    @testset "the demands of one frame are one work for each source" begin
        calls = Vector{Any}[]
        source = _make_counting_source(calls)
        parts = [make_background_cell(source, () -> i; default = 0) for i in 1:1970]
        total = Cell(@computation sum(part[] for part in parts))
        editor = _make_background_editor()
        @test _read_in_editor(editor, total) == 0 && is_cell_provisional(total)
        start_background_cell_work!(editor)
        @test _wait_until_final(editor, total)
        @test total[] == 10 * sum(1:1970) && length(calls) == 1 && only(calls) == collect(1:1970)
    end

    @testset "a cell says that its work runs, and stores its answer in its document" begin
        calls = Vector{Any}[]
        gate = Channel{Bool}(1)
        working = Cell(false)
        probe = BackgroundCellProbe()
        applied = Any[]
        store(inputs, answer) = (push!(applied, (inputs, answer)); ReplaceReferencedValueOperation(probe, "value", answer))
        value = make_background_cell(_make_counting_source(calls; gate), () -> 3; default = 0, working, apply = store)
        editor = _make_background_editor()
        @test _read_in_editor(editor, value) == 0 && working[] == false
        start_background_cell_work!(editor)
        @test working[] == true
        put!(gate, true)
        @test _wait_until_final(editor, value)
        @test working[] == false && applied == [(3, 30)] && probe.value == 30
        # A work that throws passes its exception.
        failures = Any[]
        broken = make_background_cell(BackgroundSource(inputs -> error("no disk")), () -> 1;
                                      apply = (inputs, answer) -> (push!(failures, answer); nothing))
        @test _read_in_editor(editor, broken) === nothing
        start_background_cell_work!(editor)
        deadline = time() + 10
        while isempty(failures) && time() < deadline
            drain_operations!(editor)
            sleep(0.01)
        end
        @test only(failures) isa ErrorException
        # With no editor, wait_for_cell! evaluates the operation with none.
        other = BackgroundCellProbe()
        alone = make_background_cell(_make_counting_source(Vector{Any}[]), () -> 4; default = 0,
                                     apply = (inputs, answer) -> ReplaceReferencedValueOperation(other, "value", answer))
        @test wait_for_cell!(alone; editor = nothing) == 40 && other.value == 40
    end

    @testset "a demand that waits or runs is not asked again" begin
        calls = Vector{Any}[]
        gate = Channel{Bool}(1)
        input = Cell(5)
        value = make_background_cell(_make_counting_source(calls; gate), () -> input[]; default = 0)
        editor = _make_background_editor()
        @test _read_in_editor(editor, value) == 0
        start_background_cell_work!(editor)
        # The work waits at its gate. A new computation of the cell for the same
        # inputs asks for nothing.
        invalidate_cell!(value)
        @test _read_in_editor(editor, value) == 0 && _count_waiting_demands(editor) == 0
        put!(gate, true)
        @test _wait_until_final(editor, value)
        @test value[] == 50 && calls == [[5]]
    end

    @testset "a cell whose inputs are provisional asks for nothing until they are final" begin
        inner_calls = Vector{Any}[]
        outer_calls = Vector{Any}[]
        inner = make_background_cell(_make_counting_source(inner_calls), () -> 1; default = 0)
        outer = make_background_cell(_make_counting_source(outer_calls), () -> inner[]; default = -1)
        editor = _make_background_editor()
        @test _read_in_editor(editor, outer) == -1 && is_cell_provisional(outer)
        start_background_cell_work!(editor)
        @test _wait_until_final(editor, inner)
        @test inner_calls == [[1]] && isempty(outer_calls)
        # With its input final, the outer cell asks, with the final value only.
        @test _read_in_editor(editor, outer) == -1 && is_cell_provisional(outer)
        start_background_cell_work!(editor)
        @test _wait_until_final(editor, outer)
        @test outer[] == 100 && outer_calls == [[10]]
    end

    @testset "a work that throws makes a read of its cells throw" begin
        failing = make_background_cell(BackgroundSource(inputs -> error("no file")), () -> 1; default = 0)
        shown = Cell(@computation try string(failing[]) catch exception
                                      exception isa ErrorException ? "failed" : "other" end)
        editor = _make_background_editor()
        @test _read_in_editor(editor, shown) == "0" && is_cell_provisional(shown)
        start_background_cell_work!(editor)
        @test _wait_until_final(editor, shown)
        @test shown[] == "failed"
        # A work that answers another count of values fails each cell of the batch.
        short = make_background_cell(BackgroundSource(inputs -> Any[]), () -> 1; default = 0)
        short_shown = Cell(@computation try string(short[]) catch exception
                                            exception isa ArgumentError ? "short" : "other" end)
        @test _read_in_editor(editor, short_shown) == "0"
        start_background_cell_work!(editor)
        @test _wait_until_final(editor, short_shown)
        @test short_shown[] == "short"
        @test_throws ArgumentError short[]
    end

    @testset "a cell that computed where it asked nobody asks when the editor uses it" begin
        calls = Vector{Any}[]
        value = make_background_cell(_make_counting_source(calls), () -> 7; default = 0)
        # A read with no editor asks nobody, and the cell keeps its default.
        @test value[] == 0 && is_cell_provisional(value)
        editor = _make_background_editor()
        reader = Cell(@computation value[] + 1)
        @test _read_in_editor(editor, reader) == 1 && _count_waiting_demands(editor) == 1
        start_background_cell_work!(editor)
        @test _wait_until_final(editor, reader)
        @test reader[] == 71 && calls == [[7]]
    end

    @testset "the first print of an editor asks that editor" begin
        calls = Vector{Any}[]
        document = BackgroundRecordProbe(make_background_cell(_make_counting_source(calls), () -> 3; default = 0))
        editor = make_editor(document, BackgroundRecordProjection(); backend = HeadlessBackend(),
                             devices = Device[])
        @test _count_waiting_demands(editor) == 1
        start_background_cell_work!(editor)
        record = getfield(document, :record)
        @test _wait_until_final(editor, record)
        @test record[] == 30
    end

    @testset "a search starts no background work, unless it is asked to" begin
        calls = Vector{Any}[]
        document = BackgroundRecordProbe(make_background_cell(_make_counting_source(calls), () -> 4; default = 0))
        editor = _make_background_editor()
        search(; kwargs...) =
            run_with_evaluation_editor(() -> search_documents(document, value -> value == 40; kwargs...), editor)
        @test isempty(search()) && isempty(calls) && _count_waiting_demands(editor) == 0
        # A search that starts background work waits for the value, and finds it.
        @test search(; background = true) == Any[document]
        @test calls == [[4]] && !is_cell_provisional(getfield(document, :record))
    end

    @testset "wait_for_cell! computes the final value on the calling task" begin
        calls = Vector{Any}[]
        source = _make_counting_source(calls)
        input = Cell(3)
        value = make_background_cell(source, () -> input[]; default = 0)
        reader = Cell(@computation value[] + 1)
        # Outside an editor a read records no demand.
        @test reader[] == 1 && is_cell_provisional(reader)
        @test wait_for_cell!(reader; editor = nothing) == 31 && !is_cell_provisional(reader)
        @test calls == [[3]]
        # A background cell whose input is another one waits for both.
        inner = make_background_cell(source, () -> 2; default = 0)
        outer = make_background_cell(source, () -> inner[]; default = 0)
        @test wait_for_cell!(outer; editor = nothing) == 200
        @test calls == [[3], [2], [20]]
        # An editor with no loop computes the same way, on the calling task.
        editor = _make_background_editor()
        input[] = 4
        @test run_with_evaluation_editor(() -> wait_for_cell!(reader), editor) == 41
        # A computation can not wait.
        @test_throws ArgumentError Cell(@computation wait_for_cell!(reader; editor = nothing))[]
    end
end
end
