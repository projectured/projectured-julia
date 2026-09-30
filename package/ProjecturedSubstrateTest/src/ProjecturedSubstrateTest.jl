"""
    ProjecturedSubstrateTest

The test package of the substrate: the thirty packages between the kernel
and the twenty domains. It is the second tier of the test-package DAG
(kernel ← substrate ← domain ← umbrella). It hosts:

- the unit tests of every substrate package, from the reactive containers to
  the widget projections, aggregated by `test_substrate()`;
- the static layering guard of each of the thirty packages
  (`test_substrate_layering`, over `ProjecturedKernelTest.check_layering`);
- the **generic document-walk selection enumerators**: the CellVector-aware
  `_walk_document` and the ground-truth `collect_position_selections` /
  `collect_tree_selections`, plus the `TextString` method of
  `_text_leaf_length` that makes them see text leaves;
- the generic drivers a domain test reuses: the type-in explorer, the
  click-roundtrip and navigation-invariant drivers, and the navigation presets
  over `ProjecturedKernelTest`'s `explore_selections`.

Like the umbrella, this is a **function library**: `using ProjecturedSubstrateTest`
from the repo-root environment, then call `test_substrate()` or any individual
`test_*` function.
"""
module ProjecturedSubstrateTest

using Test
import ProjecturedKernel
import ProjecturedPlatform
import ProjecturedConsole
import ProjecturedPdf
using ProjecturedKernelTest
# The real substrate example factories and the tier's registry slice.
using ProjecturedSubstrateExample
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.ProjectionModule: PrinterContext
using ProjecturedPlatform.ProjectionAlgebraModule: IdentityProjection
using ProjecturedKernel.ProjectionModule: print_document, read_intent
using ProjecturedPlatform.CollectionModule
using ProjecturedPlatform.PrimitiveModule
using ProjecturedPlatform.ProjectionAlgebraModule
using ProjecturedPlatform.ProjectionAlgebraModule: FocusingProjection, ReplaceFocusPartOperation
using ProjecturedPlatform.ProjectionAlgebraModule: ReversingProjection
using ProjecturedPlatform.ProjectionAlgebraModule: FilteringProjection
using ProjecturedPlatform.ProjectionAlgebraModule: SearchingProjection
using ProjecturedPlatform.ProjectionAlgebraModule: SortingProjection
using ProjecturedPlatform.ProjectionAlgebraModule: SwitchingProjection
using ProjecturedPlatform.ProjectionAlgebraModule: WindowInputUnwrappingProjection
using ProjecturedPlatform.PrimitiveModule: PrimitiveString
using ProjecturedKernel.ProjectionModule: map_reference_backward
using ProjecturedKernel.ProjectionModule: map_reference_forward
using ProjecturedKernel.EventModule: KeyDown
using ProjecturedKernel.EventModule: ModifierKeys
using ProjecturedPlatform.ReflectionModule
using ProjecturedPlatform.ReflectionModule
using ProjecturedKernel.CellStructModule: get_cell_struct_kind
using ProjecturedPlatform.VersioningModule
using ProjecturedPlatform.VersioningModule: VersioningToAnyProjection
using ProjecturedPlatform.DomainModule: DocumentNothing
using ProjecturedKernel.IntentModule: Intent
using ProjecturedKernel.OperationModule: ReplaceSelectionOperation, ReplaceReferencedValueOperation
using ProjecturedKernel.OperationModule: ReplaceMouseTargetOperation, ReplacePathOperation,
    get_operation_path, replace_mouse_target!, reroot_operation, describe_operation,
    make_inverse_operation, DoNothingOperation, evaluate_operation
using ProjecturedPlatform.ProjectionAlgebraModule: RecursiveProjection
using ProjecturedPlatform.ProjectionAlgebraModule: TypeDispatchingProjection

using ProjecturedPlatform.ReflectionModule
using ProjecturedPlatform.ReflectionModule
using ProjecturedPlatform.ReflectionModule
using ProjecturedKernel.OperationModule: ReplaceReferencedValueOperation

const _SOURCES = (ProjecturedKernel, ProjecturedPlatform, ProjecturedConsole, ProjecturedPdf)
# The tests were written against the flat `Projectured` namespace. Build the
# same namespace over the packages above — one mechanical pass, exactly like the
# umbrella's re-export loop, but without re-exporting: alias every submodule and
# `using` its exported names into scope.
for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

# ── the tests of the packages that came out of base ─────────────────────────
include("../../../test/platform/document/CollectionDocumentTest.jl")
include("../../../test/platform/document/MouseTargetFieldTest.jl")
include("../../../test/platform/document/DocumentWalkTest.jl")
include("../../../test/platform/document/BoundedSyncTest.jl")
include("../../../test/platform/document/DocumentReflectionTest.jl")
include("../../../test/platform/document/SelectionEnumeration.jl")
include("../../../test/platform/projection/CopyingProjectionTest.jl")
include("../../../test/platform/projection/FocusingTest.jl")
include("../../../test/platform/projection/ReversingTest.jl")
include("../../../test/platform/projection/FilteringTest.jl")
include("../../../test/platform/projection/SearchingTest.jl")
include("../../../test/platform/projection/SortingTest.jl")
include("../../../test/platform/projection/HigherOrderTest.jl")
include("../../../test/platform/projection/IdentityTest.jl")
include("../../../test/platform/projection/VersioningToAnyTest.jl")
include("../../../test/platform/serialization/TextFileTest.jl")
include("../../../test/platform/serialization/MarkerLanguageTest.jl")
# ── visual documents ─────────────────────────────────────────────────────────
include("../../../test/platform/document/PointReferenceTest.jl")
include("../../../test/platform/document/SyntaxDocumentTest.jl")
include("../../../test/platform/document/TextDocumentTest.jl")
include("../../../test/platform/document/GraphicsDocumentTest.jl")
include("../../../test/platform/document/GeometryTest.jl")
include("../../../test/platform/document/FontMetricsTest.jl")
include("../../../test/platform/document/TextMeasureTest.jl")
include("../../../test/platform/document/LineSpacingTest.jl")
include("../../../test/platform/document/FontFallbackTest.jl")
include("../../../test/platform/document/GraphicsLayoutTest.jl")
include("../../../test/platform/document/LayoutAllocatorTest.jl")
include("../../../test/platform/document/PrimitiveDocumentTest.jl")
include("../../../test/platform/document/PaneDocumentTest.jl")
include("../../../test/platform/document/PaneGeometryTest.jl")
include("../../../test/platform/document/DocumentDuplicateTest.jl")
include("../../../test/platform/document/TextSelectionEnumeration.jl")
# ── text / graphics projections ──────────────────────────────────────────────
include("../../../test/platform/projection/ProjectionTemplateTest.jl")
include("../../../test/platform/projection/PlotGeometryTest.jl")
include("../../../test/platform/projection/SyntaxToTextTest.jl")
include("../../../test/platform/projection/IntroducedPartTest.jl")
include("../../../test/platform/projection/PrimitiveToTextTest.jl")
include("../../../test/platform/projection/TextToGraphicsTest.jl")
include("../../../test/platform/projection/TextLineModelTest.jl")
include("../../../test/platform/projection/InlineImageCaretTest.jl")
include("../../../test/platform/projection/WordWrappingTest.jl")
include("../../../test/platform/projection/TextFilteringTest.jl")
include("../../../test/platform/projection/TextFirstLineTest.jl")
include("../../../test/platform/projection/TextLineNumberingTest.jl")
include("../../../test/platform/projection/TextHighlightingTest.jl")
include("../../../test/platform/projection/SelectionInvertingTest.jl")
# ── widget projections ───────────────────────────────────────────────────────
include("../../../test/platform/projection/ObjectToWidgetTest.jl")
include("../../../test/platform/projection/ObjectFieldToWidgetTest.jl")
include("../../../test/platform/projection/ObjectFieldToSyntaxTest.jl")
include("../../../test/platform/projection/ReflectionToWidgetTest.jl")
include("../../../test/platform/projection/ProjectionConfiguringTest.jl")
include("../../../test/platform/projection/CellTableToWidgetTableTest.jl")
include("../../../test/platform/projection/WidgetTextEditTest.jl")
include("../../../test/platform/projection/WidgetButtonTest.jl")
include("../../../test/platform/projection/WidgetSliderTest.jl")
include("../../../test/platform/projection/WidgetScrollBarTest.jl")
include("../../../test/platform/projection/WidgetLiveValueTest.jl")
include("../../../test/platform/projection/SizeRangeChildRuleTest.jl")
include("../../../test/platform/projection/SizeRangeStackTest.jl")
include("../../../test/platform/projection/SizeRangeMainAxisTest.jl")
include("../../../test/platform/projection/WidgetCardFoldTest.jl")
include("../../../test/platform/projection/WidgetSelectionTest.jl")
include("../../../test/platform/projection/SelectionWalkingTest.jl")
include("../../../test/platform/projection/GestureTrackingTest.jl")
include("../../../test/platform/projection/MouseTargetTrackingTest.jl")
include("../../../test/platform/projection/MouseTargetMoveTest.jl")
include("../../../test/platform/projection/WidgetGestureTest.jl")
include("../../../test/platform/projection/WidgetSelectTest.jl")
include("../../../test/platform/projection/WidgetMenuTest.jl")
include("../../../test/platform/projection/WidgetShellTest.jl")
include("../../../test/platform/projection/WidgetContextMenuTest.jl")
include("../../../test/platform/projection/WidgetDialogTest.jl")
include("../../../test/platform/projection/WidgetActionTest.jl")
include("../../../test/platform/projection/WidgetIconTest.jl")
include("../../../test/platform/projection/WidgetColorTest.jl")
include("../../../test/platform/projection/WidgetTreeTest.jl")
include("../../../test/platform/projection/WidgetToolbarTest.jl")
include("../../../test/platform/projection/WidgetTableTest.jl")
include("../../../test/platform/projection/WidgetTextWrapTest.jl")
include("../../../test/platform/projection/WidgetTablePartsTest.jl")
include("../../../test/platform/projection/LayoutListTest.jl")
include("../../../test/platform/projection/WidgetTabStripTest.jl")
include("../../../test/platform/projection/WidgetSplitPaneTest.jl")
include("../../../test/platform/projection/PaneToWidgetTest.jl")
include("../../../test/platform/projection/PaneReaderTest.jl")
include("../../../test/platform/projection/PaneGestureTest.jl")
include("../../../test/platform/projection/PaneDragTest.jl")
include("../../../test/platform/projection/PaneRenameTest.jl")
include("../../../test/platform/projection/InterfaceApiTest.jl")
include("../../../test/platform/projection/WidgetTransformPaneTest.jl")
include("../../../test/platform/projection/LayoutCloseoutTest.jl")
include("../../../test/platform/projection/WidgetFormsTest.jl")
include("../../../test/platform/projection/AnchorPointTest.jl")
include("../../../test/platform/projection/AnchoredLayoutTest.jl")
# ── interaction decorators (clipboard / tooltip) ─────────────────────────────
# The clipboard copy/cut/paste projection and the tooltip decorator's
# open/close state machine — both live in visual now and use only base/visual
# fixtures (Primitive / Text / Screen), so this is their lowest test home.
# (HoverProbe's tests stay in the umbrella: they wrap Json content.)
include("../../../test/platform/projection/ClipboardTest.jl")
include("../../../test/platform/projection/TooltipProjectionTest.jl")
include("../../../test/platform/projection/WindowFitTest.jl")
include("../../../test/platform/projection/WindowWrapperTest.jl")
include("../../../test/platform/projection/DocumentCompositionTest.jl")
include("../../../test/platform/projection/TabsWrapperTest.jl")
# Widget/screen route decorators exercised on visual example fixtures
# (make_widget_split_pane_* / make_widget_popup_* live in ProjecturedVisualExample).
include("../../../test/platform/projection/SplitPaneDragTest.jl")
include("../../../test/platform/projection/RoutedGestureTest.jl")
include("../../../test/platform/projection/LayoutPointTest.jl")
include("../../../test/platform/projection/WidgetPointTest.jl")
include("../../../test/platform/projection/WidgetForwardTest.jl")
include("../../../test/platform/projection/WidgetRoundTripTest.jl")
include("../../../test/platform/projection/ScrollPaneHoverTest.jl")
include("../../../test/platform/projection/WidgetPopupExampleTest.jl")
# ── visual-level generic drivers ─────────────────────────────────────────────
include("../../../test/platform/editor/NavigationPresets.jl")
include("../../../test/platform/editor/TypeinTest.jl")
include("../../../test/platform/editor/ClickRoundtripTest.jl")
# Collapse/expand round-trip over the syntax example (reuses ClickRoundtripTest's
# _find_text_iomap; both drive the Syntax→Text→Graphics pipeline).
include("../../../test/platform/editor/CollapseRoundtripTest.jl")
include("../../../test/platform/editor/PaneConstructTest.jl")
include("../../../test/platform/SubstrateSuite.jl")

end # module ProjecturedSubstrateTest
