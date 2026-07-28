"""
    ProjecturedKernelTest

Test package for `ProjecturedKernel` — the base of the test-package DAG that
parallels the main DAG (kernel ← base ← visual ← domain ← umbrella; see
plan/pending/test-package-split.md). It hosts:

- the kernel's own unit tests (`test_cell`, `test_document_contract`,
  `test_reference_builder`, …), aggregated by `test_kernel()`;
- the **shared generic test drivers** reused by every higher test package and
  the `ProjecturedTest` umbrella: `test_printer` / `test_reader` / `test_repl`
  (label + document + projection forms), the generic navigation explorer
  (`explore_selections` / `test_navigation`, parameterized by gesture set and
  seed), the reflexive cell walker (`_walk!`, `WalkStatus`), and the event
  battery (`_ALL_READER_EVENTS`);
- the static `check_layering` guard shared by all four main packages'
  layered-architecture tests.

The drivers only call kernel API (`print_document`, `read_intent`,
`evaluate_operation`, `clear_selection!`) plus `Test`, so they live here at the
bottom of the DAG. The navigation driver carries no domain vocabulary: its
gesture presets (`test_position_navigation`, `test_tree_navigation`) live in
`ProjecturedVisualTest`, whose readers own those gesture vocabularies, and the
ground-truth selection enumerators (`collect_position_selections`,
`collect_tree_selections`) live in `ProjecturedBaseTest`, the lowest tier whose
document walk can express them (visual extends them for `TextString` leaves,
domain for JSON trees); the driver receives the enumerator as its `collect`
argument.

Like the umbrella, this is a **function library**: `using ProjecturedKernelTest`
from the repo-root environment, then call `test_kernel()` or any individual
`test_*` function.
"""
module ProjecturedKernelTest

using Test
import ProjecturedKernel
# The `Example` harness struct — the tier-typed driver overloads below
# dispatch on it; the concrete example sets live in the example packages.
using ProjecturedKernelExample: Example
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.SelectionModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.EventPatternModule
using ProjecturedKernel.GestureBindingModule
using ProjecturedKernel.ProjectionApiModule: print_document, read_intent

# ── shared static layering guard ────────────────────────────────────────────
include("layering/CheckLayering.jl")

# ── kernel unit tests (one suite per kernel layer) ──────────────────────────
include("cell/CellTest.jl")
include("cell/CellStructTest.jl")
include("cell/CellStructPlanTest.jl")
include("cell/PerformanceCounterTest.jl")
include("clock/ClockTest.jl")
include("document/DocumentContractTest.jl")
include("document/DocumentMacroTest.jl")
include("reference/ReferenceBuilderTest.jl")
include("reference/ReferenceEvalTest.jl")
include("operation/RerootingTest.jl")
include("operation/TraversalTest.jl")
include("event/EventModuleTest.jl")
include("event/EventCaseTest.jl")
include("gesture/GestureRecognizerTest.jl")
include("binding/GestureBindingTest.jl")
include("backend/HeadlessBackendTest.jl")
include("agent/AgentSeamTest.jl")

# ── generic drivers (document, projection) — reused by every layer above ────
include("editor/PrinterTest.jl")
include("editor/ReaderTest.jl")
include("editor/ReplTest.jl")
include("editor/NavigationTest.jl")
include("editor/ConstructTest.jl")

"""
    test_kernel_layering()

Static layered-architecture guard for `ProjecturedKernel`: the top include list
must be a topological order over the real `import ..XxxModule` edges, every src
file reached exactly once, files under a declared layer folder may only
import from layers of index ≤ their own, cross-layer symbol imports may
name only exported symbols, and every interface file declares without
implementing (AR-INTERFACE-DECLARES-ONLY).
"""
function test_kernel_layering()
    # `pkgdir` rejects the flat entryfile-at-root layout (main/ProjecturedKernel.jl
    # is not under a src/), so derive the package root from `pathof`.
    main = normpath(dirname(pathof(ProjecturedKernel)))
    check_layering(main, joinpath(main, "ProjecturedKernel.jl");
                   name = "kernel",
                   layers = ["cell", "clock", "event", "device", "gesture", "backend",
                             "document", "reference", "selection", "operation",
                             "binding", "iomap", "projection", "tool", "llm", "agent", "editor"],
                   check_private_imports = true,
                   # A layer's contract file, and its owning module.
                   interface_files = Dict(
                       "cell/CellInterface.jl"       => :CellModule,
                       "event/EventInterface.jl"     => :EventModule,
                       "document/DocumentInterface.jl" => :DocumentModule,
                       "reference/ReferenceInterface.jl" => :ReferenceModule,
                       "selection/SelectionInterface.jl"      => :SelectionModule,
                       "operation/Interface.jl"      => :OperationModule,
                       "backend/BackendInterface.jl" => :BackendModule,
                       "device/Device.jl"            => :DeviceModule,
                       "projection/ProjectionApi.jl" => :ProjectionApiModule,
                       "iomap/IoMapInterface.jl"     => :IoMapModule),
                   # AR-QUALIFIED-EXTENSION: files migrated to bare `using ..Xxx`
                   # + qualified extension (`Xxx.f(…) = …`). Opt-in, and it grows
                   # as the sweep proceeds; when it covers every file the
                   # parameter goes.
                   qualified_files = Set([
                       "projection/ProjectionReferenceStep.jl",   # the reference-step seam
                       "editor/Editor.jl",
                       "editor/Playback.jl",
                       "llm/LlmModule.jl",
                       "agent/AgentModule.jl"]))
end

"""
    test_kernel()

Run the whole kernel suite: the static layering guard, the `check_layering`
self-tests, and every kernel unit test.
"""
function test_kernel()
    @testset "ProjecturedKernel" begin
        test_kernel_layering()
        test_layering_checkers()
        test_cell()
        test_cell_struct()
        test_struct_plan()
        test_performance_counter()
        test_clock()
        test_document_contract()
        test_document_macro()
        test_reference_builder()
        test_reference_eval()
        test_rerooting()
        test_traversal()
        test_event_module()
        test_event_case()
        test_gesture_recognizer()
        test_gesture_binding()
        test_headless_backend()
        test_agent_seam()
        test_construct_oracle()
    end
end

export test_kernel, test_kernel_layering
# layering guard (shared by base/visual/domain test packages)
export check_layering, test_layering_checkers
# kernel unit suites
export test_cell, test_cell_struct, test_struct_plan, test_performance_counter, test_clock,
       test_document_contract, test_document_macro,
       test_reference_builder, test_reference_eval, test_rerooting,
       test_traversal, test_event_module, test_event_case,
       test_gesture_binding, test_gesture_recognizer, test_headless_backend, test_agent_seam
# generic drivers + walker internals reused by the higher test packages
export WalkStatus, _walk!, _WALK_MAX_DEPTH, _WALK_MAX_NODES,
       walk_printer_output, test_printer,
       _ALL_READER_EVENTS, walk_reader_events, test_reader,
       walk_repl_loop, test_repl,
       explore_selections, test_navigation, _assert_reaches_all,
       compare_content, test_construct_oracle

end # module ProjecturedKernelTest
