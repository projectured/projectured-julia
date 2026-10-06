# A fault goes to the barrier of the part that built the bad cell.
#
# The pipeline of this suite has a barrier at each recursion point of its syntax
# and text stages, and a last stage that joins the text into one string. The
# editor reads that string to paint, so a paint reads every cell of the output, as
# a renderer does. A printer throws when such a read reaches a bad cell, which is
# long after `print_document` returned, so this suite drives a real editor frame
# by frame and looks at what each frame painted.

# A document of a type that no rule of `JsonToSyntax` fits, as in take 7 of S2.
@document struct FaultPartProbe
    value::Int = 0
end

# Prints its input as one syntax leaf, and throws while `is_broken[]` holds.
struct BreakableLeafToSyntax <: Projection
    is_broken::Base.RefValue{Bool}
end
ProjectionModule.print_document(p::BreakableLeafToSyntax, recursion, input, ctx) =
    p.is_broken[] ? error("the leaf is broken") :
                    SimpleIoMap(p, input, SyntaxLeaf(TextString("leaf")))
ProjectionModule.read_intent(::BreakableLeafToSyntax, recursion, change::Intent, iomap) = change

# A substitute that can not draw its mark.
struct BrokenMarkToSyntax <: Projection end
ProjectionModule.print_document(::BrokenMarkToSyntax, recursion, report, ctx) =
    error("the mark is broken")

_make_barrier_pipeline(syntax_barrier = FaultCatchingProjection(inner = JsonToSyntax(),
                                                                substitute = FaultToSyntax())) =
    ChainingProjection(
        RecursiveProjection(syntax_barrier),
        RecursiveProjection(FaultCatchingProjection(inner = SyntaxToText(),
                                                    substitute = FaultToText())),
        RecursiveProjection(TextToString()))

# A JSON string whose value throws while `broken[]` holds. `runs` counts how
# often its computation ran.
_make_breakable_string(broken, runs) =
    JsonString(ReactiveCell{String}(@computation begin
        runs[] += 1
        broken[] ? error("the value is broken") : "repaired"
    end))

_make_json_array(elements...) =
    JsonArray(elements = CellVector{Document}(Cell[Cell(element) for element in elements]))

function _make_part_editor(document, pipeline = _make_barrier_pipeline())
    backend = HeadlessBackend()
    editor = Editor(document, pipeline; backend, devices = Device[])
    editor.fault_policy = FaultPolicy(is_console_enabled = false, is_sound_enabled = false)
    (editor, backend)
end

function _run_frames!(editor, count)
    for _ in 1:count
        run_frame!(editor)
    end
end

# What the last frame painted, or `nothing` when no frame painted.
_get_last_paint(backend) =
    isempty(rendered_output(backend)) ? nothing : last(rendered_output(backend))

# The records of the store that a printer made.
_get_print_records(editor) =
    [record for record in get_fault_records(editor.faults) if record.site === :print]

# The one line that the mark of `record` shows.
_get_mark_label(record) = format_fault_label(FaultReport(record))

# What a healthy document of the same shape paints: the bad value repaired.
function _paint_healthy(document)
    editor, backend = _make_part_editor(document)
    run_frame!(editor)
    _get_last_paint(backend)
end

const _HEALTHY_ARRAY = "[\n  \"first\", \n  \"repaired\", \n  \"third\"\n]"

function test_fault_part()
@testset "a fault goes to the barrier of the part that built the bad cell" begin

    @testset "the healthy document paints" begin
        @test _paint_healthy(_make_json_array(JsonString("first"), JsonString("repaired"),
                                              JsonString("third"))) == _HEALTHY_ARRAY
    end

    @testset "a late fault in one leaf costs that leaf" begin
        broken, runs = Cell(true), Ref(0)
        editor, backend = _make_part_editor(_make_json_array(
            JsonString("first"), _make_breakable_string(broken, runs), JsonString("third")))
        _run_frames!(editor, 2)
        records = _get_print_records(editor)
        @test length(records) == 1
        @test _get_last_paint(backend) ==
                     replace(_HEALTHY_ARRAY, "\"repaired\"" => _get_mark_label(only(records)))
        # The fault is the printer's, not the device's.
        @test get_consecutive_fault_count(editor.faults, :device_write) == 0
    end

    @testset "an early fault in one leaf costs that leaf" begin
        editor, backend = _make_part_editor(_make_json_array(
            JsonString("first"), FaultPartProbe(), JsonString("third")))
        run_frame!(editor)
        records = _get_print_records(editor)
        @test length(records) == 1
        @test _get_last_paint(backend) ==
              replace(_HEALTHY_ARRAY, "\"repaired\"" => _get_mark_label(only(records)))
    end

    @testset "two leaves of one kind are two marks and one record" begin
        broken = Cell(true)
        editor, backend = _make_part_editor(_make_json_array(
            _make_breakable_string(broken, Ref(0)), JsonString("first"),
            _make_breakable_string(broken, Ref(0))))
        _run_frames!(editor, 4)
        records = _get_print_records(editor)
        @test length(records) == 1
        @test !isempty(records) && only(records).count == 2
        painted = _get_last_paint(backend)
        @test painted !== nothing && !isempty(records) &&
                     count(_get_mark_label(only(records)), painted) == 2
    end

    @testset "a fault in a nested array costs the leaf" begin
        broken = Cell(true)
        inner = _make_json_array(JsonString("first"), _make_breakable_string(broken, Ref(0)))
        editor, backend = _make_part_editor(_make_json_array(inner, JsonString("third")))
        _run_frames!(editor, 2)
        healthy = _paint_healthy(_make_json_array(
            _make_json_array(JsonString("first"), JsonString("repaired")), JsonString("third")))
        records = _get_print_records(editor)
        @test length(records) == 1
        @test _get_last_paint(backend) ==
                     replace(healthy, "\"repaired\"" => _get_mark_label(only(records)))
    end

    @testset "a cell that failed does not run again" begin
        broken, runs = Cell(true), Ref(0)
        editor, backend = _make_part_editor(_make_json_array(
            JsonString("first"), _make_breakable_string(broken, runs), JsonString("third")))
        _run_frames!(editor, 2)
        before = runs[]
        _run_frames!(editor, 3)
        @test runs[] == before
        @test get_consecutive_fault_count(editor.faults, :device_write) == 0
    end

    @testset "after an operation the editor tries the mark again" begin
        broken, runs = Cell(true), Ref(0)
        editor, backend = _make_part_editor(_make_json_array(
            JsonString("first"), _make_breakable_string(broken, runs), JsonString("third")))
        _run_frames!(editor, 2)
        broken[] = false
        # With no operation the mark stays: nothing pulls the cell that failed.
        run_frame!(editor)
        @test _get_last_paint(backend) != _HEALTHY_ARRAY
        post_operation!(editor, DoNothingOperation())
        drain_operations!(editor)
        run_frame!(editor)
        @test _get_last_paint(backend) == _HEALTHY_ARRAY
    end

    @testset "an operation while the fault stays loses no frame and adds no record" begin
        broken = Cell(true)
        editor, backend = _make_part_editor(_make_json_array(
            JsonString("first"), _make_breakable_string(broken, Ref(0)), JsonString("third")))
        _run_frames!(editor, 2)
        painted = length(rendered_output(backend))
        counts = [record.count for record in _get_print_records(editor)]
        post_operation!(editor, DoNothingOperation())
        drain_operations!(editor)
        run_frame!(editor)
        @test length(rendered_output(backend)) == painted + 1
        @test [record.count for record in _get_print_records(editor)] == counts
    end

    @testset "a mark that can not be drawn goes to the barrier above" begin
        # Two barriers at each node: the inner one draws its mark with a
        # substitute that throws, the outer one with a substitute that works.
        nested = FaultCatchingProjection(
            inner = FaultCatchingProjection(inner = JsonToSyntax(),
                                            substitute = BrokenMarkToSyntax()),
            substitute = FaultToSyntax())
        broken = Cell(true)
        editor, backend = _make_part_editor(
            _make_json_array(JsonString("first"), _make_breakable_string(broken, Ref(0)),
                             JsonString("third")),
            _make_barrier_pipeline(nested))
        _run_frames!(editor, 4)
        origins = [record.origin for record in _get_print_records(editor)]
        @test :BrokenMarkToSyntax in origins
        @test get_consecutive_fault_count(editor.faults, :device_write) == 0
        painted = _get_last_paint(backend)
        @test painted !== nothing
        @test startswith(painted, "[\n  \"first\", \n  ⚠")
        @test endswith(painted, ", \n  \"third\"\n]")
    end

    @testset "a click on the mark tries the part again" begin
        is_broken = Ref(true)
        barrier = FaultCatchingProjection(inner = BreakableLeafToSyntax(is_broken),
                                          substitute = FaultToSyntax())
        iomap = print_document(barrier, barrier, FaultPartProbe(),
                               _make_tolerant_context(FaultStore()))
        @test iomap.output isa SyntaxLeaf
        click = MouseClick(:left, 0, 0, 1, ModifierKeys(); time = 0.0)
        operation = read_intent(barrier, iomap, click)
        @test operation isa ReplaceViewStateOperation
        is_broken[] = false
        @test begin
            evaluate_operation(nothing, operation)
            !occursin("⚠", string(iomap.output))
        end
    end

    @testset "the menu of the mark tries the part again" begin
        is_broken = Ref(true)
        barrier = FaultCatchingProjection(inner = BreakableLeafToSyntax(is_broken),
                                          substitute = FaultToSyntax())
        iomap = print_document(barrier, barrier, FaultPartProbe(),
                               _make_tolerant_context(FaultStore()))
        right = MouseClick(:right, 0, 0, 1, ModifierKeys(); time = 0.0)
        operation = read_intent(barrier, iomap, right)
        @test get_wrapped_operation(operation) isa OpenContextMenuOperation
    end
end
end
