"""
    ProjecturedSubstrateTest

The test package of the substrate: the twenty-eight packages between the kernel
and the twenty domains. It is the second tier of the test-package DAG
(kernel ← substrate ← domain ← umbrella). It hosts:

- the unit tests of every substrate package, from the reactive containers to
  the widget projections, aggregated by `test_substrate()`;
- the static layering guard of each of the twenty-eight packages
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
import ProjecturedVersioning
import ProjecturedPlot
import ProjecturedGraphics
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
import ProjecturedFileFormat
import ProjecturedNaturalProjection
import ProjecturedConsole
import ProjecturedPdf
using ProjecturedKernelTest
# The real substrate example factories and the tier's registry slice.
using ProjecturedSubstrateExample
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.PrinterContextModule: PrinterContext
using ProjecturedProjection.IdentityProjectionModule: IdentityProjection
using ProjecturedKernel.ProjectionApiModule: print_document, read_intent
using ProjecturedCollection.CollectionModule
using ProjecturedPrimitive.PrimitiveModule
using ProjecturedProjection.CopyingProjectionModule
using ProjecturedProjection.FocusingProjectionModule: FocusingProjection, ReplaceFocusPartOperation
using ProjecturedProjection.ReversingProjectionModule: ReversingProjection
using ProjecturedProjection.FilteringProjectionModule: FilteringProjection
using ProjecturedProjection.SearchingProjectionModule: SearchingProjection
using ProjecturedProjection.SortingProjectionModule: SortingProjection
using ProjecturedProjection.SwitchingProjectionModule: SwitchingProjection
using ProjecturedProjection.WindowInputUnwrappingProjectionModule: WindowInputUnwrappingProjection
using ProjecturedPrimitive.PrimitiveModule: PrimitiveString
using ProjecturedKernel.ProjectionApiModule: map_reference_backward
using ProjecturedKernel.ProjectionApiModule: map_reference_forward
using ProjecturedKernel.EventModule: KeyDown
using ProjecturedKernel.EventModule: ModifierKeys
using ProjecturedReflection.BoundedSyncModule
using ProjecturedReflection.DocumentReflectionModule
using ProjecturedKernel.DocumentModule: get_cell_struct_kind
using ProjecturedVersioning.VersioningModule
using ProjecturedVersioning.VersioningToAnyProjectionModule: VersioningToAnyProjection
using ProjecturedDomain.DocumentCoreModule: DocumentNothing
using ProjecturedKernel.IntentModule: Intent
using ProjecturedKernel.OperationModule: ReplaceSelectionOperation, ReplaceReferencedValueOperation
using ProjecturedProjection.RecursiveProjectionModule: RecursiveProjection
using ProjecturedProjection.TypeDispatchingProjectionModule: TypeDispatchingProjection

using ProjecturedReflection.BoundedSyncModule
using ProjecturedReflection.DocumentReflectionModule
using ProjecturedWidget.ReflectionToWidgetModule
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
                  ProjecturedFocus,
                  ProjecturedVersioning,
                  ProjecturedPlot,
                  ProjecturedGraphics,
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
                  ProjecturedFileFormat,
                  ProjecturedNaturalProjection,
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
include("document/CollectionTest.jl")
include("document/DocumentWalkTest.jl")
include("document/BoundedSyncTest.jl")
include("document/DocumentReflectionTest.jl")
include("document/SelectionEnumeration.jl")
include("projection/CopyingProjectionTest.jl")
include("projection/FocusingTest.jl")
include("projection/ReversingTest.jl")
include("projection/FilteringTest.jl")
include("projection/SearchingTest.jl")
include("projection/SortingTest.jl")
include("projection/HigherOrderTest.jl")
include("projection/VersioningToAnyTest.jl")
include("serialization/FileProjectTest.jl")
include("serialization/MarkerLanguageTest.jl")
# ── visual documents ─────────────────────────────────────────────────────────
include("document/PointReferenceTest.jl")
include("document/SyntaxTest.jl")
include("document/TextTest.jl")
include("document/GraphicsTest.jl")
include("document/GeometryTest.jl")
include("document/FontMetricsTest.jl")
include("document/GraphicsLayoutTest.jl")
include("document/LayoutAllocatorTest.jl")
include("document/PrimitiveTest.jl")
include("document/PaneTest.jl")
include("document/PaneGeometryTest.jl")
include("document/TextSelectionEnumeration.jl")
# ── text / graphics projections ──────────────────────────────────────────────
include("projection/ProjectionTemplateTest.jl")
include("projection/PlotGeometryTest.jl")
include("projection/SyntaxToTextTest.jl")
include("projection/PrimitiveToTextTest.jl")
include("projection/TextToGraphicsTest.jl")
include("projection/WordWrappingTest.jl")
include("projection/TextFilteringTest.jl")
include("projection/TextHighlightingTest.jl")
include("projection/SelectionInvertingTest.jl")
# ── widget projections ───────────────────────────────────────────────────────
include("projection/ObjectToWidgetTest.jl")
include("projection/ObjectFieldToWidgetTest.jl")
include("projection/ObjectFieldToSyntaxTest.jl")
include("projection/ReflectionToWidgetTest.jl")
include("projection/ProjectionConfiguringTest.jl")
include("projection/CellTableToWidgetTableTest.jl")
include("projection/WidgetTextEditTest.jl")
include("projection/WidgetButtonTest.jl")
include("projection/WidgetGestureTest.jl")
include("projection/WidgetSelectTest.jl")
include("projection/WidgetMenuTest.jl")
include("projection/WidgetContextMenuTest.jl")
include("projection/WidgetDialogTest.jl")
include("projection/WidgetActionTest.jl")
include("projection/WidgetIconTest.jl")
include("projection/WidgetTreeTest.jl")
include("projection/WidgetToolbarTest.jl")
include("projection/WidgetTableTest.jl")
include("projection/WidgetTabStripTest.jl")
include("projection/WidgetSplitPaneTest.jl")
include("projection/PaneToWidgetTest.jl")
include("projection/PaneReaderTest.jl")
include("projection/PaneGestureTest.jl")
include("projection/PaneDragTest.jl")
include("projection/PaneRenameTest.jl")
include("projection/WidgetTransformPaneTest.jl")
include("projection/LayoutCloseoutTest.jl")
include("projection/WidgetFormsTest.jl")
include("projection/AnchorPointTest.jl")
include("projection/AnchoredLayoutTest.jl")
# ── interaction decorators (clipboard / tooltip) ─────────────────────────────
# The clipboard copy/cut/paste projection and the tooltip decorator's
# open/close state machine — both live in visual now and use only base/visual
# fixtures (Primitive / Text / Screen), so this is their lowest test home.
# (HoverProbe's tests stay in the umbrella: they wrap Json content.)
include("projection/ClipboardToAnyTest.jl")
include("projection/TooltipTest.jl")
# Widget/screen route decorators exercised on visual example fixtures
# (make_widget_split_pane_* / make_widget_popup_* live in ProjecturedVisualExample).
include("projection/SplitPaneDragTest.jl")
include("projection/ScrollPaneHoverTest.jl")
include("projection/WidgetPopupExampleTest.jl")
# ── visual-level generic drivers ─────────────────────────────────────────────
include("editor/NavigationPresets.jl")
include("editor/TypeinTest.jl")
include("editor/ClickRoundtripTest.jl")
# Collapse/expand round-trip over the syntax example (reuses ClickRoundtripTest's
# _find_text_iomap; both drive the Syntax→Text→Graphics pipeline).
include("editor/CollapseRoundtripTest.jl")
include("editor/PaneConstructTest.jl")
"""
    test_substrate_layering()

The static layered-architecture guard of every substrate package (see
`ProjecturedKernelTest.check_layering`). Each package is one concept and
declares no layer index, so the check is the topological include order of its
own entry file plus the file inventory of its own folder.
"""
function test_substrate_layering()
    for pkg in _SOURCES
        pkg === ProjecturedKernel && continue
        main = normpath(dirname(pathof(pkg)))
        check_layering(main, joinpath(main, "$(nameof(pkg)).jl"); name = String(nameof(pkg)))
    end
end

"""
    test_substrate()

Run the whole substrate suite: the layering guard of every package, every unit
test, and the printer walk over the tier's own examples.
"""
function test_substrate()
    @testset "ProjecturedSubstrate" begin
        test_substrate_layering()
        test_substrate_examples()
        test_collection()
        test_document_walk()
        test_bounded_sync()
        test_document_reflection()
        test_copying_projection()
        test_focusing()
        test_reversing()
        test_filtering()
        test_searching()
        test_sorting()
        test_switching()
        test_window_input_unwrapping()
        test_versioning_to_any()
        test_file_project()
        test_marker_language()
        # documents
        test_point_reference()
        test_syntax()
        test_text()
        test_graphics()
        test_affine_transform()
        test_font_metrics()
        test_graphics_layout()
        test_layout_allocator()
        test_layout_constraint_helpers()
        test_primitive()
        test_pane_surgery()
        test_pane_geometry()
        # text / graphics projections
        test_projection_template_hygiene()
        test_projection_template_fixed_children()
        test_plot_geometry()
        test_syntax_to_text()
        test_primitive_to_text()
        test_text_to_graphics()
        test_word_wrapping()
        test_text_filtering()
        test_text_highlighting()
        test_selection_inverting()
        # widget projections
        test_object_to_widget()
        test_object_field_to_widget()
        test_object_field_to_syntax()
        test_reflection_to_widget()
        test_projection_configuring()
        test_cell_table_to_widget_table()
        test_widget_text_editing()
        test_widget_button_behavior()
        test_widget_gestures()
        test_widget_select_dropdown()
        test_widget_menu()
        test_widget_context_menu()
        test_widget_dialog()
        test_widget_action()
        test_widget_icon()
        test_widget_tree()
        test_widget_toolbar()
        test_widget_table()
        test_widget_tab_strip()
        test_widget_split_pane()
        test_pane_to_widget()
        test_pane_reader()
        test_pane_gestures()
        test_pane_drag()
        test_pane_rename()
        test_pane_construct()
        test_widget_transform_pane()
        test_layout_closeout()
        test_widget_forms()
        test_anchor_point()
        test_anchored_layout()
        # interaction decorators
        test_clipboard_to_any()
        test_tooltip()
        test_split_pane_drag()
        test_scroll_pane_hover()
        test_widget_popup_example()
        # generic drivers over visual examples
        test_collapse_roundtrip()

    end
end

"""
    test_substrate_examples()

Walk the printer over every substrate example (`substrate_examples`) — one
`@test` per forced reactive cell, through the generic `test_printer` driver.
"""
function test_substrate_examples()
    @testset "SubstrateExamples" begin
        for ex in substrate_examples
            @testset "$(ex.name)" begin
                test_printer(ex)
            end
        end
    end
end

export test_substrate, test_substrate_layering, test_substrate_examples
export test_bounded_sync, test_document_reflection
export test_collection, test_copying_projection, test_focusing, test_reversing, test_filtering, test_searching, test_sorting
export test_switching, test_window_input_unwrapping
export test_versioning_to_any
export test_file_project, test_marker_language
export _text_leaf_length, _walk_document, collect_position_selections, collect_tree_selections
export test_point_reference
export test_syntax, test_text, test_graphics, test_affine_transform, test_font_metrics,
       test_graphics_layout, test_layout_allocator, test_layout_constraint_helpers,
       test_primitive, test_pane_surgery, test_pane_geometry, test_pane_to_widget,
       test_pane_reader, test_pane_gestures, test_pane_drag,
       test_pane_rename, test_pane_construct
export test_projection_template_hygiene, test_projection_template_fixed_children
export test_plot_geometry,
       test_syntax_to_text, test_primitive_to_text, test_text_to_graphics,
       test_word_wrapping, test_text_filtering, test_text_highlighting,
       test_selection_inverting
export test_reflection_to_widget
export test_object_field_to_widget, test_object_field_to_syntax
export test_object_to_widget, test_projection_configuring,
       test_widget_text_editing, test_widget_button_behavior, test_widget_gestures,
       test_widget_select_dropdown, test_widget_menu, test_widget_context_menu,
       test_widget_dialog, test_widget_action, test_widget_icon, test_widget_tree,
       test_widget_toolbar, test_widget_table, test_widget_tab_strip, test_widget_split_pane, test_widget_transform_pane,
       test_layout_closeout, test_widget_forms, test_anchor_point, test_anchored_layout
export test_clipboard_to_any, test_tooltip, test_split_pane_drag, test_scroll_pane_hover,
       test_widget_popup_example, test_collapse_roundtrip
export POSITION_NAV_KEYS, POSITION_SEED_GESTURE, TREE_NAV_KEYS, TREE_SEED_GESTURE,
       explore_position_selections, test_position_navigation,
       explore_tree_selections, test_tree_navigation
export walk_typein, test_typein
export test_click_roundtrip, test_text_nav_invariants,
       _find_text_iomap, _find_cursor_rect, _pipeline_measure, _seg_x_at,
       _path_contains_projection_ref

end # module ProjecturedSubstrateTest
