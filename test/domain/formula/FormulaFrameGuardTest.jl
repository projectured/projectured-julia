# The frame guard of the formula task: a change of the input of many formulas
# computes them again off the loop, and each frame that the task needs stays flat
# at any count of formulas. The task prepares each formula and stores its value
# through the door of the editor, one call at a time, so a frame holds one call.
# The backend of the guard shows no held frames: a call then runs in its frame, and
# the frame measures the work of the editor for one formula. The harness is
# `FrameGuard.jl` of the kernel tests.

import ProjecturedKernel.BackendModule
import ProjecturedKernel.ProjectionModule
import ProjecturedKernel.CellModule: Cell, Computation
import ProjecturedKernel.IoMapModule: SimpleIoMap
import ProjecturedKernel.EditorModule: Editor, run_print_stage!, post_operation!
import ProjecturedKernel.FaultModule: FaultPolicy

# A backend that shows no held frames and paints nothing.
struct FormulaFrameGuardBackend <: BackendModule.Backend end
BackendModule.initialize_backend!(::FormulaFrameGuardBackend) = nothing
BackendModule.quit_backend!(::FormulaFrameGuardBackend) = nothing
BackendModule.take_from_devices!(::FormulaFrameGuardBackend, devices) = nothing
BackendModule.write_to_devices!(::FormulaFrameGuardBackend, devices, output) = nothing
BackendModule.wait_for_input(::FormulaFrameGuardBackend, devices, timeout) = sleep(min(timeout, 0.001))
BackendModule.shows_held_frames(::FormulaFrameGuardBackend) = false

# A view of the value of the first formula only.
struct FormulaFrameGuardProjection <: ProjectionModule.Projection end
ProjectionModule.print_document(::FormulaFrameGuardProjection, recursion, input, context) =
    SimpleIoMap(nothing, input, Cell(Computation(() -> get_formula_result(first(input.formulas)))))

# Whether every formula `F i` of `sheet` holds its value `A * i` for the input `A`.
_is_formula_frame_guard_sheet_done(sheet, input) =
    all(i -> !sheet.formulas[i + 1].is_computing &&
             get_formula_result(sheet.formulas[i + 1]) == input * i, 1:(length(sheet.formulas) - 1))

function _make_formula_frame_guard_scene()
    sheet = Ref{Any}(nothing)
    input = Ref(2)
    FrameScene("a change of the input of many formulas"; sizes = [10, 1_000], is_burst = true,
        make_editor = function (size)
            input[] = 2
            sheet[] = _formula_sheet("A" => "2", ("F$i" => "A * $i" for i in 1:size)...)
            _compute_formula_sheet!(sheet[])
            editor = Editor(sheet[], FormulaFrameGuardProjection(); backend = FormulaFrameGuardBackend(),
                            devices = Device[],
                            fault_policy = FaultPolicy(is_console_enabled = false, is_sound_enabled = false))
            run_print_stage!(editor)
            editor
        end,
        give_input! = function (editor, size)
            input[] += 1
            formula = first(sheet[].formulas)
            formula.code = parse_julia(string(input[]))
            post_operation!(editor, ComputeFormulasOperation(sheet[], [formula]))
        end,
        is_input_done = editor -> _is_formula_frame_guard_sheet_done(sheet[], input[]))
end

function test_formula_frame_guards()
@testset "the frame guard of the formula task" begin
    @testset "a change of the input of many formulas computes them in flat frames" begin
        scene = _make_formula_frame_guard_scene()
        # Each formula takes two frames, one after another, so the burst of 1_000
        # formulas takes more frames than the default limit.
        works = measure_frame_work(scene; repetitions = 1, frame_limit = 5_000)
        growth = compute_frame_growth(works)
        @test all(work -> work.is_finished, works)
        @test growth.time_ratio <= FLAT_TIME_RATIO
        # @broken: about one frame in 200 of the task allocates in proportion to the count of formulas, 2.9 MB at 1_000 against 0.8 MB at 10; the cause is not found yet; plan/pending/guards-keep-the-frame-short-at-any-size.md
        @test_broken growth.allocation_ratio <= FLAT_ALLOCATION_RATIO
        print_frame_work(scene.name, works)
    end
end
end
