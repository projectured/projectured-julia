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
import ProjecturedCollection
import ProjecturedPrimitive
import ProjecturedDomain
import ProjecturedSerialization
import ProjecturedStyle
import ProjecturedComponent
import ProjecturedProjection
import ProjecturedReflection
import ProjecturedDragging
import ProjecturedFocus
import ProjecturedGestureTracking
import ProjecturedVersioning
import ProjecturedPlot
import ProjecturedGraphics
import ProjecturedMouseTargetTracking
import ProjecturedScreen
import ProjecturedLayout
import ProjecturedText
import ProjecturedWidget
import ProjecturedSyntax
import ProjecturedPane
import ProjecturedClipboard
import ProjecturedTooltip
import ProjecturedInspector
import ProjecturedGestureHelp
import ProjecturedGestureLog
import ProjecturedFault
import ProjecturedFileFormat
import ProjecturedNatural
import ProjecturedConsole
import ProjecturedPdf
using ProjecturedKernelTest
# The real substrate example factories and the tier's registry slice.
using ProjecturedSubstrateExample
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.ProjectionModule: PrinterContext
using ProjecturedProjection.ProjectionAlgebraModule: IdentityProjection
using ProjecturedKernel.ProjectionModule: print_document, read_intent
using ProjecturedCollection.CollectionModule
using ProjecturedPrimitive.PrimitiveModule
using ProjecturedProjection.ProjectionAlgebraModule
using ProjecturedProjection.ProjectionAlgebraModule: FocusingProjection, ReplaceFocusPartOperation
using ProjecturedProjection.ProjectionAlgebraModule: ReversingProjection
using ProjecturedProjection.ProjectionAlgebraModule: FilteringProjection
using ProjecturedProjection.ProjectionAlgebraModule: SearchingProjection
using ProjecturedProjection.ProjectionAlgebraModule: SortingProjection
using ProjecturedProjection.ProjectionAlgebraModule: SwitchingProjection
using ProjecturedProjection.ProjectionAlgebraModule: WindowInputUnwrappingProjection
using ProjecturedPrimitive.PrimitiveModule: PrimitiveString
using ProjecturedKernel.ProjectionModule: map_reference_backward
using ProjecturedKernel.ProjectionModule: map_reference_forward
using ProjecturedKernel.EventModule: KeyDown
using ProjecturedKernel.EventModule: ModifierKeys
using ProjecturedReflection.ReflectionModule
using ProjecturedReflection.ReflectionModule
using ProjecturedKernel.CellStructModule: get_cell_struct_kind
using ProjecturedVersioning.VersioningModule
using ProjecturedVersioning.VersioningModule: VersioningToAnyProjection
using ProjecturedDomain.DomainModule: DocumentNothing
using ProjecturedKernel.IntentModule: Intent
using ProjecturedKernel.OperationModule: ReplaceSelectionOperation, ReplaceReferencedValueOperation
using ProjecturedKernel.OperationModule: ReplaceMouseTargetOperation, ReplacePathOperation,
    get_operation_path, replace_mouse_target!, reroot_operation, describe_operation,
    make_inverse_operation, DoNothingOperation, evaluate_operation
using ProjecturedProjection.ProjectionAlgebraModule: RecursiveProjection
using ProjecturedProjection.ProjectionAlgebraModule: TypeDispatchingProjection

using ProjecturedReflection.ReflectionModule
using ProjecturedReflection.ReflectionModule
using ProjecturedReflection.ReflectionModule
using ProjecturedKernel.OperationModule: ReplaceReferencedValueOperation

const _SOURCES = (ProjecturedKernel,
                  ProjecturedCollection,
                  ProjecturedPrimitive,
                  ProjecturedDomain,
                  ProjecturedSerialization,
                  ProjecturedStyle,
                  ProjecturedComponent,
                  ProjecturedProjection,
                  ProjecturedReflection,
                  ProjecturedDragging,
                  ProjecturedFocus, ProjecturedGestureTracking,
                  ProjecturedVersioning,
                  ProjecturedPlot,
                  ProjecturedGraphics, ProjecturedMouseTargetTracking,
                  ProjecturedScreen,
                  ProjecturedLayout,
                  ProjecturedText,
                  ProjecturedWidget,
                  ProjecturedSyntax,
                  ProjecturedPane,
                  ProjecturedClipboard,
                  ProjecturedTooltip,
                  ProjecturedInspector,
                  ProjecturedGestureHelp,
                  ProjecturedGestureLog,
                  ProjecturedFault,
                  ProjecturedFileFormat,
                  ProjecturedNatural,
                  ProjecturedConsole,
                  ProjecturedPdf)
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
include("../../../test/substrate/document/CollectionDocumentTest.jl")
include("../../../test/substrate/document/MouseTargetFieldTest.jl")
include("../../../test/substrate/document/DocumentWalkTest.jl")
include("../../../test/substrate/document/BoundedSyncTest.jl")
include("../../../test/substrate/document/DocumentReflectionTest.jl")
include("../../../test/substrate/document/SelectionEnumeration.jl")
include("../../../test/substrate/projection/CopyingProjectionTest.jl")
include("../../../test/substrate/projection/FocusingTest.jl")
include("../../../test/substrate/projection/ReversingTest.jl")
include("../../../test/substrate/projection/FilteringTest.jl")
include("../../../test/substrate/projection/SearchingTest.jl")
include("../../../test/substrate/projection/SortingTest.jl")
include("../../../test/substrate/projection/HigherOrderTest.jl")
include("../../../test/substrate/projection/IdentityTest.jl")
include("../../../test/substrate/projection/VersioningToAnyTest.jl")
include("../../../test/substrate/serialization/TextFileTest.jl")
include("../../../test/substrate/serialization/MarkerLanguageTest.jl")
# ── visual documents ─────────────────────────────────────────────────────────
include("../../../test/substrate/document/PointReferenceTest.jl")
include("../../../test/substrate/document/SyntaxDocumentTest.jl")
include("../../../test/substrate/document/TextDocumentTest.jl")
include("../../../test/substrate/document/GraphicsDocumentTest.jl")
include("../../../test/substrate/document/GeometryTest.jl")
include("../../../test/substrate/document/FontMetricsTest.jl")
include("../../../test/substrate/document/TextMeasureTest.jl")
include("../../../test/substrate/document/LineSpacingTest.jl")
include("../../../test/substrate/document/FontFallbackTest.jl")
include("../../../test/substrate/document/GraphicsLayoutTest.jl")
include("../../../test/substrate/document/LayoutAllocatorTest.jl")
include("../../../test/substrate/document/PrimitiveDocumentTest.jl")
include("../../../test/substrate/document/PaneDocumentTest.jl")
include("../../../test/substrate/document/PaneGeometryTest.jl")
include("../../../test/substrate/document/DocumentDuplicateTest.jl")
include("../../../test/substrate/document/TextSelectionEnumeration.jl")
# ── text / graphics projections ──────────────────────────────────────────────
include("../../../test/substrate/projection/ProjectionTemplateTest.jl")
include("../../../test/substrate/projection/PlotGeometryTest.jl")
include("../../../test/substrate/projection/SyntaxToTextTest.jl")
include("../../../test/substrate/projection/IntroducedPartTest.jl")
include("../../../test/substrate/projection/PrimitiveToTextTest.jl")
include("../../../test/substrate/projection/TextToGraphicsTest.jl")
include("../../../test/substrate/projection/TextLineModelTest.jl")
include("../../../test/substrate/projection/InlineImageCaretTest.jl")
include("../../../test/substrate/projection/WordWrappingTest.jl")
include("../../../test/substrate/projection/TextFilteringTest.jl")
include("../../../test/substrate/projection/TextFirstLineTest.jl")
include("../../../test/substrate/projection/TextLineNumberingTest.jl")
include("../../../test/substrate/projection/TextHighlightingTest.jl")
include("../../../test/substrate/projection/SelectionInvertingTest.jl")
# ── widget projections ───────────────────────────────────────────────────────
include("../../../test/substrate/projection/ObjectToWidgetTest.jl")
include("../../../test/substrate/projection/ObjectFieldToWidgetTest.jl")
include("../../../test/substrate/projection/ObjectFieldToSyntaxTest.jl")
include("../../../test/substrate/projection/ReflectionToWidgetTest.jl")
include("../../../test/substrate/projection/ProjectionConfiguringTest.jl")
include("../../../test/substrate/projection/CellTableToWidgetTableTest.jl")
include("../../../test/substrate/projection/WidgetTextEditTest.jl")
include("../../../test/substrate/projection/WidgetButtonTest.jl")
include("../../../test/substrate/projection/WidgetSliderTest.jl")
include("../../../test/substrate/projection/WidgetLiveValueTest.jl")
include("../../../test/substrate/projection/SizeRangeChildRuleTest.jl")
include("../../../test/substrate/projection/SizeRangeStackTest.jl")
include("../../../test/substrate/projection/SizeRangeMainAxisTest.jl")
include("../../../test/substrate/projection/WidgetCardFoldTest.jl")
include("../../../test/substrate/projection/WidgetSelectionTest.jl")
include("../../../test/substrate/projection/SelectionWalkingTest.jl")
include("../../../test/substrate/projection/GestureTrackingTest.jl")
include("../../../test/substrate/projection/MouseTargetTrackingTest.jl")
include("../../../test/substrate/projection/WidgetGestureTest.jl")
include("../../../test/substrate/projection/WidgetSelectTest.jl")
include("../../../test/substrate/projection/WidgetMenuTest.jl")
include("../../../test/substrate/projection/WidgetShellTest.jl")
include("../../../test/substrate/projection/WidgetContextMenuTest.jl")
include("../../../test/substrate/projection/WidgetDialogTest.jl")
include("../../../test/substrate/projection/WidgetActionTest.jl")
include("../../../test/substrate/projection/WidgetIconTest.jl")
include("../../../test/substrate/projection/WidgetColorTest.jl")
include("../../../test/substrate/projection/WidgetTreeTest.jl")
include("../../../test/substrate/projection/WidgetToolbarTest.jl")
include("../../../test/substrate/projection/WidgetTableTest.jl")
include("../../../test/substrate/projection/WidgetTextWrapTest.jl")
include("../../../test/substrate/projection/WidgetTableListTest.jl")
include("../../../test/substrate/projection/WidgetTabStripTest.jl")
include("../../../test/substrate/projection/WidgetSplitPaneTest.jl")
include("../../../test/substrate/projection/PaneToWidgetTest.jl")
include("../../../test/substrate/projection/PaneReaderTest.jl")
include("../../../test/substrate/projection/PaneGestureTest.jl")
include("../../../test/substrate/projection/PaneDragTest.jl")
include("../../../test/substrate/projection/PaneRenameTest.jl")
include("../../../test/substrate/projection/InterfaceApiTest.jl")
include("../../../test/substrate/projection/WidgetTransformPaneTest.jl")
include("../../../test/substrate/projection/LayoutCloseoutTest.jl")
include("../../../test/substrate/projection/WidgetFormsTest.jl")
include("../../../test/substrate/projection/AnchorPointTest.jl")
include("../../../test/substrate/projection/AnchoredLayoutTest.jl")
# ── interaction decorators (clipboard / tooltip) ─────────────────────────────
# The clipboard copy/cut/paste projection and the tooltip decorator's
# open/close state machine — both live in visual now and use only base/visual
# fixtures (Primitive / Text / Screen), so this is their lowest test home.
# (HoverProbe's tests stay in the umbrella: they wrap Json content.)
include("../../../test/substrate/projection/ClipboardTest.jl")
include("../../../test/substrate/projection/TooltipProjectionTest.jl")
include("../../../test/substrate/projection/WindowFitTest.jl")
# Widget/screen route decorators exercised on visual example fixtures
# (make_widget_split_pane_* / make_widget_popup_* live in ProjecturedVisualExample).
include("../../../test/substrate/projection/SplitPaneDragTest.jl")
include("../../../test/substrate/projection/RoutedGestureTest.jl")
include("../../../test/substrate/projection/LayoutPointTest.jl")
include("../../../test/substrate/projection/WidgetPointTest.jl")
include("../../../test/substrate/projection/WidgetForwardTest.jl")
include("../../../test/substrate/projection/WidgetRoundTripTest.jl")
include("../../../test/substrate/projection/ScrollPaneHoverTest.jl")
include("../../../test/substrate/projection/WidgetPopupExampleTest.jl")
# ── visual-level generic drivers ─────────────────────────────────────────────
include("../../../test/substrate/editor/NavigationPresets.jl")
include("../../../test/substrate/editor/TypeinTest.jl")
include("../../../test/substrate/editor/ClickRoundtripTest.jl")
# Collapse/expand round-trip over the syntax example (reuses ClickRoundtripTest's
# _find_text_iomap; both drive the Syntax→Text→Graphics pipeline).
include("../../../test/substrate/editor/CollapseRoundtripTest.jl")
include("../../../test/substrate/editor/PaneConstructTest.jl")
include("../../../test/substrate/SubstrateSuite.jl")

end # module ProjecturedSubstrateTest
