"""
    ProjecturedPlatformTest

The test package of the platform: the thirty-eight slices between the
kernel and the seventeen domains. It is the second tier of the test-package
DAG (kernel ← platform ← domain ← umbrella). It hosts:

- the unit tests of every slice of the platform, from the reactive containers
  to the widget projections, aggregated by `test_platform()`;
- the static layering guard of the platform (`test_platform_layering`, over
  `ProjecturedKernelTest.check_layering`);
- the **generic document-walk selection enumerators**: the CellVector-aware
  `_walk_document` and the ground-truth `collect_position_selections` /
  `collect_tree_selections`, plus the `TextString` method of
  `_text_leaf_length` that makes them see text leaves;
- the generic drivers a domain test reuses: the type-in explorer, the
  click-roundtrip and navigation-invariant drivers, and the navigation presets
  over `ProjecturedKernelTest`'s `explore_selections`.

Like the umbrella, this is a **function library**: `using ProjecturedPlatformTest`
from the repo-root environment, then call `test_platform()` or any individual
`test_*` function.
"""
module ProjecturedPlatformTest

using Test
import ProjecturedKernel
import ProjecturedPlatform
import ProjecturedConsole
import ProjecturedPDF
using ProjecturedKernelTest
# The real platform example factories and the tier's registry slice.
using ProjecturedPlatformExample
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
using ProjecturedKernel.ProjectionModule: get_content_iomap
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

const _SOURCES = (ProjecturedKernel, ProjecturedPlatform, ProjecturedConsole, ProjecturedPDF)
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
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
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
include("../../../test/platform/document/PointerShapeTest.jl")
include("../../../test/platform/document/GeometryTest.jl")
include("../../../test/platform/document/FontMetricsTest.jl")
include("../../../test/platform/document/TextMeasureTest.jl")
include("../../../test/platform/document/LineSpacingTest.jl")
include("../../../test/platform/document/ThemeTest.jl")
include("../../../test/platform/document/ColorThemeTest.jl")
include("../../../test/platform/document/FontFallbackTest.jl")
include("../../../test/platform/document/FontFaceTest.jl")
include("../../../test/platform/document/GraphicsLayoutTest.jl")
include("../../../test/platform/document/LayoutAllocatorTest.jl")
include("../../../test/platform/document/PrimitiveDocumentTest.jl")
include("../../../test/platform/document/PrimitiveTypeInTest.jl")
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
include("../../../test/platform/projection/MouseTargetDriver.jl")
include("../../../test/platform/projection/ReflectionToWidgetTest.jl")
include("../../../test/platform/projection/ProjectionConfiguringTest.jl")
include("../../../test/platform/projection/CellTableToWidgetTableTest.jl")
include("../../../test/platform/projection/WidgetTextEditTest.jl")
include("../../../test/platform/projection/WidgetButtonTest.jl")
include("../../../test/platform/projection/WidgetSliderTest.jl")
include("../../../test/platform/projection/WidgetScrollBarTest.jl")
include("../../../test/platform/projection/WidgetLiveValueTest.jl")
include("../../../test/platform/projection/WidgetProgressTest.jl")
include("../../../test/platform/projection/SizeRangeChildRuleTest.jl")
include("../../../test/platform/projection/SizeRangeStackTest.jl")
include("../../../test/platform/projection/SizeRangeMainAxisTest.jl")
include("../../../test/platform/projection/WidgetCardFoldTest.jl")
include("../../../test/platform/projection/WidgetSelectionTest.jl")
include("../../../test/platform/projection/SelectionWalkingTest.jl")
include("../../../test/platform/projection/GestureTrackingTest.jl")
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
include("../../../test/platform/projection/WidgetScaleTest.jl")
include("../../../test/platform/projection/BuilderAppearanceTest.jl")
include("../../../test/platform/projection/TextThemeTest.jl")
include("../../../test/platform/projection/ToolThemeTest.jl")
include("../../../test/platform/projection/HelpThemeTest.jl")
include("../../../test/platform/appearance/AppearanceWrapperTest.jl")
include("../../../test/platform/appearance/AppearanceTabTest.jl")
include("../../../test/platform/appearance/AppearanceFileTest.jl")
include("../../../test/platform/settings/SettingsTest.jl")
include("../../../test/platform/settings/SettingsWrapperTest.jl")
include("../../../test/platform/settings/SettingsTabTest.jl")
include("../../../test/platform/navigator/NavigatorVisitsTest.jl")
include("../../../test/platform/navigator/NavigatorToWidgetTest.jl")
include("../../../test/platform/navigator/OpenPageOperationTest.jl")
include("../../../test/platform/navigator/NavigatorGesturesTest.jl")
include("../../../test/platform/projection/WidgetTreeTest.jl")
include("../../../test/platform/projection/WidgetToolbarTest.jl")
include("../../../test/platform/projection/WidgetTableTest.jl")
include("../../../test/platform/projection/WidgetTextWrapTest.jl")
include("../../../test/platform/projection/WidgetTablePartsTest.jl")
include("../../../test/platform/projection/WidgetTableCellOrderTest.jl")
include("../../../test/platform/projection/LayoutListTest.jl")
include("../../../test/platform/projection/WidgetTabStripTest.jl")
include("../../../test/platform/projection/WidgetTabLabelTest.jl")
include("../../../test/platform/mcplog/McpLogTest.jl")
include("../../../test/platform/task/TaskResultTest.jl")
include("../../../test/platform/task/TaskExecutionTest.jl")
include("../../../test/platform/task/TaskGroupTest.jl")
include("../../../test/platform/task/TaskDocumentTest.jl")
include("../../../test/platform/task/TaskGroupToWidgetTest.jl")
include("../../../test/platform/task/TaskVerbsTest.jl")
include("../../../test/platform/projection/WidgetSplitPaneTest.jl")
include("../../../test/platform/projection/PaneToWidgetTest.jl")
include("../../../test/platform/projection/PaneReaderTest.jl")
include("../../../test/platform/projection/PaneGestureTest.jl")
include("../../../test/platform/projection/PaneDragTest.jl")
include("../../../test/platform/projection/PaneRenameTest.jl")
include("../../../test/platform/projection/InterfaceApiTest.jl")
include("../../../test/platform/projection/WidgetTransformPaneTest.jl")
include("../../../test/platform/projection/LayoutCloseoutTest.jl")
include("../../../test/platform/projection/GridSpanTest.jl")
include("../../../test/platform/projection/WidgetFormsTest.jl")
include("../../../test/platform/projection/AnchorPointTest.jl")
include("../../../test/platform/projection/AnchoredLayoutTest.jl")
# ── interaction decorators (clipboard / tooltip) ─────────────────────────────
# The clipboard copy/cut/paste projection and the tooltip decorator's
# open/close state machine — both live in visual now and use only base/visual
# fixtures (Primitive / Text / Screen), so this is their lowest test home.
include("../../../test/platform/projection/ClipboardTest.jl")
include("../../../test/platform/projection/TooltipProjectionTest.jl")
include("../../../test/platform/projection/WindowFitTest.jl")
include("../../../test/platform/projection/WindowWrapperTest.jl")
include("../../../test/platform/projection/DocumentCompositionTest.jl")
include("../../../test/platform/projection/TabsWrapperTest.jl")
# Widget/screen route decorators exercised on visual example fixtures
# (make_widget_split_pane_* / make_widget_popup_* live in ProjecturedVisualExample).
include("../../../test/platform/projection/SplitPaneDragTest.jl")
include("../../../test/platform/projection/PartPointerShapeTest.jl")
include("../../../test/platform/projection/RoutedGestureTest.jl")
include("../../../test/platform/projection/LayoutPointTest.jl")
include("../../../test/platform/projection/WidgetPointTest.jl")
include("../../../test/platform/projection/ColumnChooserTest.jl")
include("../../../test/platform/projection/WidgetSwatchTest.jl")
include("../../../test/platform/projection/BaselineAlignmentTest.jl")
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
include("../../../test/platform/PlatformSuite.jl")


# The suites of the slices that had a package of their own, each in its own
# namespace, so that the helpers of two of them do not collide. This package
# exports what each exports.

module FaultTests

using Test
import ProjecturedPlatform
# The shared static layering guard lives at the bottom of the test-package DAG.
using ProjecturedKernelTest: check_layering, get_package_source_root
using ProjecturedPlatform.CollectionModule
using ProjecturedPlatform.FaultViewModule
using ProjecturedKernel.CellModule
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EditorModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.FaultModule
using ProjecturedKernel.GestureModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernelExample
using ProjecturedPlatform.ProjectionAlgebraModule
using ProjecturedPlatform.SyntaxModule
using ProjecturedPlatform.TextModule
# Through the package under test, which uses both: the tooltip binding that a
# fault report declares, and the widget a mark is drawn as.
using ProjecturedPlatform.DomainModule
using ProjecturedPlatform.GestureBindingModule
using ProjecturedPlatform.TooltipModule
using ProjecturedPlatform.WidgetModule
using ProjecturedPlatform.FocusModule
using ProjecturedPlatform.OperationModule
# A document of a real domain, whose template printers fail in a cell of their
# output and not in `print_document`.
import ProjecturedJSON
using ProjecturedJSON.JsonModule

import ProjecturedKernel.EditorModule: run_read_stage!

include("../../../test/platform/fault/FaultCatchingTest.jl")
include("../../../test/platform/fault/FaultSafeModeTest.jl")
include("../../../test/platform/fault/FaultPartTest.jl")
include("../../../test/platform/fault/FaultSuite.jl")
end # module FaultTests

module FileSystemTests

using Test
import ProjecturedPlatform
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
using ProjecturedPlatformExample
using ProjecturedKernelExample
using ProjecturedKernelTest
using ProjecturedPlatformExample
using ..ProjecturedPlatformTest

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPDF)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../test/platform/filesystem/projection/FileSystemToSyntaxTest.jl")
include("../../../test/platform/filesystem/projection/FileSystemToWidgetTest.jl")
include("../../../test/platform/filesystem/document/FileSystemDocumentTest.jl")
include("../../../test/platform/filesystem/document/WorkspaceDuplicateTest.jl")
include("../../../test/platform/filesystem/projection/WorkspaceToFileSystemTest.jl")

include("../../../test/platform/filesystem/FileSystemSuite.jl")
end # module FileSystemTests

module ConversationTests

using Test
import ProjecturedPlatform
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
using ProjecturedKernelExample
using ProjecturedKernelTest
using ProjecturedPlatformExample
using ..ProjecturedPlatformTest

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPDF)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../test/platform/conversation/AssistantApiTest.jl")
include("../../../test/platform/conversation/ConversationThemeTest.jl")

include("../../../test/platform/conversation/ConversationSuite.jl")
end # module ConversationTests

module HelpTests

using Test
import ProjecturedPlatform
# The shared static layering guard lives at the bottom of the test-package DAG.
using ProjecturedKernelTest: check_layering, get_package_source_root
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ProjectionModule
using ProjecturedPlatform.DomainModule
using ProjecturedPlatform.ProjectionAlgebraModule: ChainingProjection, RecursiveProjection
using ProjecturedPlatform.SyntaxModule: SyntaxToText
using ProjecturedPlatform.TextModule: TextToString
using ProjecturedPlatform.HelpModule

include("../../../test/platform/help/HelpListToSyntaxTest.jl")
include("../../../test/platform/help/AboutPageToSyntaxTest.jl")
include("../../../test/platform/help/HelpSuite.jl")
end # module HelpTests

module ShellTests

using Test
import ProjecturedPlatform
# The notation of the file that the file dialog saves.
import ProjecturedJSON
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
using ProjecturedKernelExample
using ProjecturedKernelTest
using ProjecturedPlatformExample
using ..ProjecturedPlatformTest

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPDF)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../test/platform/shell/WindowWrapTest.jl")
include("../../../test/platform/shell/WidgetTooltipTest.jl")
include("../../../test/platform/shell/ContextMenuWindowTest.jl")
include("../../../test/platform/shell/WindowShellTest.jl")
include("../../../test/platform/shell/WindowWrappersTest.jl")
include("../../../test/platform/shell/FileDialogTest.jl")
include("../../../test/platform/shell/TrackingScreenTest.jl")
include("../../../test/platform/shell/DragTrackingTest.jl")
include("../../../test/platform/shell/DragPointerShapeTest.jl")
include("../../../test/platform/shell/PointerLightTest.jl")

include("../../../test/platform/shell/ShellSuite.jl")
end # module ShellTests

module UndoTests

using Test
import ProjecturedPlatform
# The shared static layering guard lives at the bottom of the test-package DAG.
using ProjecturedKernelTest: check_layering, get_package_source_root
using ProjecturedPlatform.CollectionModule
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.OperationModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.SelectionModule
using ProjecturedKernel.ToolModule
using ProjecturedPlatform.ProjectionAlgebraModule: IdentityProjection
using ProjecturedPlatform.UndoModule

include("../../../test/platform/undo/UndoBufferTest.jl")
include("../../../test/platform/undo/UndoSuite.jl")
end # module UndoTests

module DisplayTests

using Test
using ProjecturedPlatform
using ProjecturedPlatform.DisplayModule
using ProjecturedKernel
using ProjecturedKernel.AgentModule
using ProjecturedKernel.BackendModule
using ProjecturedKernel.DocumentModule: @document, Document
using ProjecturedKernelTest
using ProjecturedPlatform.PaneModule
using ProjecturedPlatform.PrimitiveModule
using ProjecturedPlatform.ScreenModule
using ProjecturedPlatform.WidgetModule

import ProjecturedKernelTest: check_layering, get_package_source_root

include("../../../test/platform/display/EditorDisplayTest.jl")
include("../../../test/platform/display/DisplaySuite.jl")
end # module DisplayTests

for _part in (FaultTests, FileSystemTests, ConversationTests, HelpTests, ShellTests, UndoTests, DisplayTests)
    Core.eval(@__MODULE__, Expr(:using, Expr(:., :., nameof(_part))))
    for _n in names(_part)
        _n === nameof(_part) || Core.eval(@__MODULE__, Expr(:export, _n))
    end
end

end # module ProjecturedPlatformTest
