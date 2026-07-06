"""
    ProjecturedKernelTest

Test package for `ProjecturedKernel` — the base of the test-package DAG that
parallels the runtime DAG (kernel ← base ← visual ← domain ← umbrella; see
plan/pending/test-package-split.md). It hosts:

- the kernel's own unit tests (`test_cell`, `test_document_contract`,
  `test_reference_builder`, …), aggregated by `test_kernel()`;
- the **shared generic test drivers** reused by every higher test package and
  the `ProjecturedTest` umbrella: `test_printer` / `test_reader` / `test_repl`
  (label + document + projection forms), the navigation explorers
  (`explore_text_selections`, `explore_tree_selections`), the reflexive cell
  walker (`_walk!`, `WalkStatus`), and the event battery
  (`_ALL_READER_EVENTS`);
- the static `check_layering` guard shared by all four runtime packages'
  layered-architecture tests.

The drivers only call kernel API (`print_document`, `read_intent`,
`evaluate_operation`, `clear_selection!`) plus `Test`, so they live here at the
bottom of the DAG. Ground-truth selection enumerators (`collect_text_selections`,
`collect_tree_selections`) are declared here as open generics; their
implementations live in the test package of the lowest runtime layer that can
express them (base for the generic walk, visual for `TextString` leaves,
domain for JSON trees).

Like the umbrella, this is a **function library**: `using ProjecturedKernelTest`
from the repo-root environment, then call `test_kernel()` or any individual
`test_*` function.
"""
module ProjecturedKernelTest

using Test
import ProjecturedKernel
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.KeyboardModule
using ProjecturedKernel.ModifiersModule
using ProjecturedKernel.MouseModule
using ProjecturedKernel.GestureModule
using ProjecturedKernel.FocusingProjectionModule
using ProjecturedKernel.ProjectionApiModule: print_document, read_intent

# ── shared static layering guard ────────────────────────────────────────────
include("layering/CheckLayering.jl")

# ── kernel unit tests (one suite per kernel layer) ──────────────────────────
include("cell/CellTest.jl")
include("cell/PerformanceCounterTest.jl")
include("cell/TimeTest.jl")
include("document/DocumentContractTest.jl")
include("reference/ReferenceBuilderTest.jl")
include("reference/ReferenceEvalTest.jl")
include("operation/RerootingTest.jl")
include("operation/TraversalTest.jl")
include("device/GestureModuleTest.jl")
include("device/EventCaseTest.jl")
include("device/GestureBindingTest.jl")
include("backend/HeadlessBackendTest.jl")
include("agent/AgentSeamTest.jl")

# ── generic drivers (document, projection) — reused by every layer above ────
include("editor/FocusingTest.jl")
include("editor/PrinterTest.jl")
include("editor/ReaderTest.jl")
include("editor/ReplTest.jl")
include("editor/TextNavigationTest.jl")
include("editor/SyntaxTreeNavigationTest.jl")

"""
    test_kernel_layering()

Static layered-architecture guard for `ProjecturedKernel`: the top include list
must be a topological order over the real `import ..XxxModule` edges, every src
file reached exactly once, and files under a declared layer folder may only
import from layers of index ≤ their own.
"""
function test_kernel_layering()
    src = normpath(joinpath(pkgdir(ProjecturedKernel), "src"))
    check_layering(src, joinpath(src, "ProjecturedKernel.jl");
                   name = "kernel",
                   layers = ["cell", "document", "reference", "operation", "device",
                             "backend", "projection", "agent", "editor"])
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
        test_performance_counter()
        test_time()
        test_document_contract()
        test_reference_builder()
        test_reference_eval()
        test_rerooting()
        test_traversal()
        test_gesture_module()
        test_event_case()
        test_gesture_binding()
        test_headless_backend()
        test_agent_seam()
        test_focusing()
    end
end

export test_kernel, test_kernel_layering
# layering guard (shared by base/visual/domain test packages)
export check_layering, test_layering_checkers
# kernel unit suites
export test_cell, test_performance_counter, test_time, test_document_contract,
       test_reference_builder, test_reference_eval, test_rerooting,
       test_traversal, test_gesture_module, test_event_case,
       test_gesture_binding, test_headless_backend, test_agent_seam,
       test_focusing
# generic drivers + walker internals reused by the higher test packages
export WalkStatus, _walk!, _WALK_MAX_DEPTH, _WALK_MAX_NODES,
       walk_printer_output, test_printer,
       _ALL_READER_EVENTS, walk_reader_events, test_reader,
       walk_repl_loop, test_repl,
       explore_text_selections, test_text_navigation,
       explore_tree_selections, test_tree_navigation,
       collect_text_selections, collect_tree_selections, _assert_reaches_all

end # module ProjecturedKernelTest
