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
`ProjecturedPlatformTest`, whose readers own those gesture vocabularies, and the
ground-truth selection enumerators (`collect_position_selections`,
`collect_tree_selections`) live in `ProjecturedPlatformTest`, the lowest tier whose
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
using ProjecturedKernel.GestureModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.GestureBindingModule
using ProjecturedKernel.ProjectionModule: print_document, read_intent

# ── shared static layering guard ────────────────────────────────────────────
include("../../../test/kernel/layering/CheckLayering.jl")

# ── kernel unit tests (one suite per kernel layer) ──────────────────────────
include("../../../test/kernel/fault/FaultDefaultsTest.jl")
include("../../../test/kernel/fault/FaultRecordTest.jl")
include("../../../test/kernel/fault/FaultStoreTest.jl")
include("../../../test/kernel/fault/FaultCascadeTest.jl")
include("../../../test/kernel/fault/FaultBarrierTest.jl")
include("../../../test/kernel/cell/CellTest.jl")
include("../../../test/kernel/struct/CellStructTest.jl")
include("../../../test/kernel/struct/CellStructPlanTest.jl")
include("../../../test/kernel/cell/UntrackedCellTest.jl")
include("../../../test/kernel/cell/CellFaultScopeTest.jl")
include("../../../test/kernel/performance/PerformanceCounterTest.jl")
include("../../../test/kernel/performance/FrameMeasurementTest.jl")
include("../../../test/kernel/clock/ClockTest.jl")
include("../../../test/kernel/projection/PrinterContextTest.jl")
include("../../../test/kernel/projection/RoutedChangeTest.jl")
include("../../../test/kernel/projection/IntroducedPathTest.jl")
include("../../../test/kernel/projection/ProjectionReferenceStepTest.jl")
include("../../../test/kernel/projection/ProjectionDefaultsTest.jl")
include("../../../test/kernel/projection/ProjectionMacroTest.jl")
include("../../../test/kernel/document/DocumentContractTest.jl")
include("../../../test/kernel/document/DocumentMacroTest.jl")
include("../../../test/kernel/reference/ReferenceBuilderTest.jl")
include("../../../test/kernel/reference/ReferenceEvaluationTest.jl")
include("../../../test/kernel/reference/ReferenceRulesTest.jl")
include("../../../test/kernel/reference/ReferencedDocumentTest.jl")
include("../../../test/kernel/reference/TypeReferenceTest.jl")
include("../../../test/kernel/selection/SelectionTest.jl")
include("../../../test/kernel/operation/OperationsTest.jl")
include("../../../test/kernel/operation/RerootingTest.jl")
include("../../../test/kernel/operation/InversionTest.jl")
include("../../../test/kernel/operation/TraversalTest.jl")
include("../../../test/kernel/operation/DescriptionTest.jl")
include("../../../test/kernel/intent/IntentTest.jl")
include("../../../test/kernel/event/EventModuleTest.jl")
include("../../../test/kernel/gesture/GestureModuleTest.jl")
include("../../../test/kernel/gesture/GestureRecognitionTest.jl")
include("../../../test/kernel/gesture/GesturePatternTest.jl")
include("../../../test/kernel/device/DeviceModuleTest.jl")
include("../../../test/kernel/binding/GestureBindingTest.jl")
include("../../../test/kernel/iomap/IoMapReconcileTest.jl")
include("../../../test/kernel/iomap/IoMapDefaultsTest.jl")
include("../../../test/kernel/backend/HeadlessBackendTest.jl")
include("../../../test/kernel/llm/LlmDefaultsTest.jl")
include("../../../test/kernel/agent/AgentDefaultsTest.jl")
include("../../../test/kernel/agent/AgentLoopTest.jl")
include("../../../test/kernel/tool/DeclaredApiTest.jl")
include("../../../test/kernel/tool/SearchQueryTest.jl")
include("../../../test/kernel/tool/MeaningSearchTest.jl")
include("../../../test/kernel/tool/RelevanceSearchTest.jl")
include("../../../test/kernel/tool/SearchAnswerTest.jl")
include("../../../test/kernel/tool/CodeExecutionTest.jl")
include("../../../test/kernel/tool/DocstringSummaryTest.jl")

# ── generic drivers (document, projection) — reused by every layer above ────
include("../../../test/kernel/editor/PrinterTest.jl")
include("../../../test/kernel/editor/ReaderTest.jl")
include("../../../test/kernel/editor/ReplTest.jl")
include("../../../test/kernel/editor/NavigationTest.jl")
include("../../../test/kernel/editor/ConstructTest.jl")
include("../../../test/kernel/editor/EscapeQuitTest.jl")
include("../../../test/kernel/editor/InboxTest.jl")
include("../../../test/kernel/editor/FrameDrainTest.jl")
include("../../../test/kernel/editor/FeedsTest.jl")
include("../../../test/kernel/editor/WaitTest.jl")
include("../../../test/kernel/editor/TimerTest.jl")
include("../../../test/kernel/editor/BuildEditorTest.jl")
include("../../../test/kernel/editor/FaultBarriersTest.jl")
include("../../../test/kernel/editor/DocumentEditsTest.jl")
include("../../../test/kernel/playback/PlaybackTest.jl")

include("../../../test/kernel/KernelSuite.jl")

end # module ProjecturedKernelTest
