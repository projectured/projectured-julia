# The frame guards of the kernel: the parts of the loop that move work into a frame
# keep each frame flat at any size of that work. Each scene runs on a small headless
# editor whose view shows one value, so the rest of a frame is the same at each
# size; the harness is `FrameGuard.jl`.
#
# - The inbox: a burst of operations that another task posts.
# - The posts of the owner task: an operation that posts many operations to its own
#   editor.
# - The faults: a burst of faults with distinct keys.
# - A cell write: one write in each frame to the one cell of many that the view shows.
# - Code units: a burst of calls that another task makes through the door of the
#   editor.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.CellModule: Cell, Computation
import ProjecturedKernel.EditorModule
using ProjecturedKernel.EditorModule: Editor, post_operation!, run_print_stage!
import ProjecturedKernel.OperationModule: Operation, evaluate_operation
import ProjecturedKernel.AgentModule: run_on_editor_task!
import ProjecturedKernel.FaultModule: record_fault!, FaultPolicy
using ProjecturedKernelExample

@document struct KernelFrameGuardProbe
    shown::Int = 0
    others::Any = nothing
end

# The view shows one value: the field `shown`, plus one.
struct KernelFrameGuardProjection <: Projection end
ProjectionModule.print_document(::KernelFrameGuardProjection, recursion, input, context) =
    SimpleIoMap(nothing, input, Cell(Computation(() -> input.shown + 1)))

# An operation that adds one to a counter, and an operation that posts `count` of
# them to its own editor.
struct KernelFrameGuardCountOperation <: Operation
    counter::Threads.Atomic{Int}
end

evaluate_operation(::Editor, operation::KernelFrameGuardCountOperation) =
    (Threads.atomic_add!(operation.counter, 1); nothing)

struct KernelFrameGuardFanOutOperation <: Operation
    count::Int
    counter::Threads.Atomic{Int}
end

function evaluate_operation(editor::Editor, operation::KernelFrameGuardFanOutOperation)
    for _ in 1:operation.count
        post_operation!(editor, KernelFrameGuardCountOperation(operation.counter))
    end
    nothing
end

# An operation that writes the field that the view shows.
struct KernelFrameGuardWriteOperation <: Operation
    document::KernelFrameGuardProbe
end

evaluate_operation(::Editor, operation::KernelFrameGuardWriteOperation) =
    (operation.document.shown += 1; nothing)

function _make_kernel_frame_guard_editor(document = KernelFrameGuardProbe())
    editor = Editor(document, KernelFrameGuardProjection(); backend = HeadlessBackend(),
                    devices = Device[],
                    fault_policy = FaultPolicy(is_console_enabled = false, is_sound_enabled = false))
    run_print_stage!(editor)
    editor
end

# A burst whose input is `size` units that count into `counter`, and that is done
# when the counter reaches every unit given so far.
function _make_kernel_frame_guard_burst(name, give!; sizes = [100, 1_000, 10_000])
    counter = Threads.Atomic{Int}(0)
    target = Ref(0)
    FrameScene(name; sizes, is_burst = true,
               make_editor = size -> (counter[] = 0; target[] = 0; _make_kernel_frame_guard_editor()),
               give_input! = (editor, size) -> (target[] += size; give!(editor, size, counter)),
               is_input_done = editor -> counter[] >= target[])
end

# Another task posts `size` operations that count into `counter`.
function _post_kernel_frame_guard_operations(editor, size, counter)
    Threads.@spawn for _ in 1:size
        post_operation!(editor, KernelFrameGuardCountOperation(counter))
    end
    nothing
end

# Another task makes `size` calls through the door of the editor, without a wait.
function _call_kernel_frame_guard_editor(editor, size, counter)
    Threads.@spawn for _ in 1:size
        run_on_editor_task!(() -> Threads.atomic_add!(counter, 1), editor; wait = false)
    end
    nothing
end

# The task of the editor records `size` faults with distinct keys.
function _record_kernel_frame_guard_faults(editor, size)
    for i in 1:size
        record_fault!(editor.faults, :evaluate; origin = Symbol("frame_guard_", i),
                      exception = ErrorException("a fault of the frame guard"))
    end
    nothing
end

const _KERNEL_FRAME_GUARD_INBOX = _make_kernel_frame_guard_burst(
    "a burst of operations that another task posts", _post_kernel_frame_guard_operations)

const _KERNEL_FRAME_GUARD_OWNER_POSTS = _make_kernel_frame_guard_burst(
    "an operation that posts many operations to its own editor",
    (editor, size, counter) -> post_operation!(editor, KernelFrameGuardFanOutOperation(size, counter)))

# A drain takes at most 64 calls into one code unit, so each size is above that.
const _KERNEL_FRAME_GUARD_CODE_UNITS = _make_kernel_frame_guard_burst(
    "a burst of calls that another task makes", _call_kernel_frame_guard_editor)

# The store keeps at most its capacity of 64 keys, so each size is above it: the
# report of a frame is bounded by the capacity, and not by the burst.
const _KERNEL_FRAME_GUARD_FAULTS = FrameScene("a burst of faults with distinct keys";
    sizes = [100, 1_000, 10_000], is_burst = true,
    make_editor = size -> _make_kernel_frame_guard_editor(),
    give_input! = _record_kernel_frame_guard_faults)

# A document of `size` cells of which the view shows one, and a write to that one
# in each frame.
const _KERNEL_FRAME_GUARD_CELL_WRITE = FrameScene("one write to the shown cell of many cells";
    sizes = [1_000, 10_000, 100_000],
    make_editor = function (size)
        document = KernelFrameGuardProbe()
        document.others = [Cell(i) for i in 1:size]
        _make_kernel_frame_guard_editor(document)
    end,
    give_input! = (editor, size) -> post_operation!(editor, KernelFrameGuardWriteOperation(editor.document)))

# Whether this process can run a code unit on a thread other than the one of this
# task, which held frames need.
_has_kernel_frame_guard_unit_thread() =
    EditorModule._find_code_unit_place(Threads.threadid()) !== nothing

function test_kernel_frame_guards()
@testset "the frame guards of the kernel" begin
    @testset "the inbox drains a burst of another task in flat frames" begin
        check_frame_growth(_KERNEL_FRAME_GUARD_INBOX)
    end

    @testset "a burst of posts of the owner task drains in flat frames" begin
        works = measure_frame_work(_KERNEL_FRAME_GUARD_OWNER_POSTS)
        growth = compute_frame_growth(works)
        @test all(work -> work.is_finished, works)
        # @broken: the drain takes every operation that the owner task posted to its own editor in one frame, with no bound for each frame; plan/pending/guards-keep-the-frame-short-at-any-size.md
        @test_broken growth.time_ratio <= FLAT_TIME_RATIO
        # @broken: the drain takes every operation that the owner task posted to its own editor in one frame, with no bound for each frame; plan/pending/guards-keep-the-frame-short-at-any-size.md
        @test_broken growth.allocation_ratio <= FLAT_ALLOCATION_RATIO
        print_frame_work(_KERNEL_FRAME_GUARD_OWNER_POSTS.name, works)
    end

    @testset "a burst of faults with distinct keys reports in flat frames" begin
        check_frame_growth(_KERNEL_FRAME_GUARD_FAULTS)
    end

    @testset "a write to the one shown cell of many cells is a flat frame" begin
        check_frame_growth(_KERNEL_FRAME_GUARD_CELL_WRITE)
    end

    if _has_kernel_frame_guard_unit_thread()
        @testset "a burst of calls of another task runs in flat frames" begin
            check_frame_growth(_KERNEL_FRAME_GUARD_CODE_UNITS)
        end
    end
end
end
