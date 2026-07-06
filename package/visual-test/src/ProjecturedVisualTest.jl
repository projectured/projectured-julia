"""
    ProjecturedVisualTest

Test package for `ProjecturedVisual` — third tier of the test-package DAG that
parallels the runtime DAG (kernel ← base ← visual ← domain ← umbrella; see
plan/pending/test-package-split.md). It hosts:

- the visual documents' tests (syntax/text/graphics/geometry/layout);
- the text/graphics/widget projection tests on local fixtures;
- the visual-level generic drivers: the type-in explorer (`walk_typein`,
  `test_typein`) and the click-roundtrip / nav-invariant drivers (they walk
  `TextToGraphics` output, so this is their lowest home);
- the `TextString` method of `ProjecturedBaseTest._text_leaf_length`, making
  `collect_text_selections` see document-domain text leaves.

Everything is aggregated by `test_visual()`; the layering guard is
`test_visual_layering()` (via `ProjecturedKernelTest.check_layering`).

Like the umbrella, this is a **function library**: `using ProjecturedVisualTest`
from the repo-root environment, then call `test_visual()` or any individual
`test_*` function.
"""
module ProjecturedVisualTest

using Test
import ProjecturedKernel
import ProjecturedBase
import ProjecturedVisual
using ProjecturedKernelTest
using ProjecturedBaseTest
# The real visual-tier example factories and the tier's registry slice — the
# mirrored Fixtures.jl copies are gone (plan/pending/example-package-split.md).
using ProjecturedVisualExample
import ProjecturedBaseTest: _text_leaf_length

# The tests below were written against the flat `Projectured` namespace. Build
# the same flat namespace over this package's three runtime sources — one
# mechanical pass, exactly like the `Projectured` umbrella's re-export loop
# (but without re-exporting): alias every submodule and `using` its exported
# names into scope.
for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual)
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # a submodule defined *by* this source (skip re-exported aliases of the other source)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        # alias the submodule so `XxxModule.foo` keeps resolving
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        # bring its exported names into scope
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

# ── visual documents ─────────────────────────────────────────────────────────
include("document/SyntaxTest.jl")
include("document/TextTest.jl")
include("document/GraphicsTest.jl")
include("document/GeometryTest.jl")
include("document/GraphicsLayoutTest.jl")
include("document/LayoutAllocatorTest.jl")
include("document/PrimitiveTest.jl")
include("document/SelectionEnumeration.jl")

# ── text / graphics projections ──────────────────────────────────────────────
include("projection/ProjectionTemplateTest.jl")
include("projection/SyntaxToTextTest.jl")
include("projection/PrimitiveToTextTest.jl")
include("projection/TextToGraphicsTest.jl")
include("projection/WordWrappingTest.jl")
include("projection/TextFilteringTest.jl")
include("projection/TextHighlightingTest.jl")
include("projection/SelectionInvertingTest.jl")

# ── widget projections ───────────────────────────────────────────────────────
include("projection/ObjectToWidgetTest.jl")
include("projection/ProjectionConfiguringTest.jl")
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
include("projection/WidgetTransformPaneTest.jl")
include("projection/LayoutCloseoutTest.jl")
include("projection/WidgetFormsTest.jl")
include("projection/AnchorPointTest.jl")

# ── visual-level generic drivers ─────────────────────────────────────────────
include("editor/TypeinTest.jl")
include("editor/ClickRoundtripTest.jl")

"""
    test_visual_layering()

Static layered-architecture guard for `ProjecturedVisual` (see
`ProjecturedKernelTest.check_layering`). Within-tier slice→slice edges
(e.g. widget → layout) are allowed provided the slice DAG is acyclic, which
is what the topological include-order check enforces; no layer indices are
declared.
"""
function test_visual_layering()
    src = normpath(joinpath(pkgdir(ProjecturedVisual), "src"))
    check_layering(src, joinpath(src, "ProjecturedVisual.jl"); name = "visual")
end

"""
    test_visual()

Run the whole visual suite: the static layering guard, every visual test, and
the printer walk over the tier's own examples.
"""
function test_visual()
    @testset "ProjecturedVisual" begin
        test_visual_layering()
        test_visual_examples()
        # documents
        test_syntax()
        test_text()
        test_graphics()
        test_affine_transform()
        test_graphics_layout()
        test_layout_allocator()
        test_layout_constraint_helpers()
        test_primitive()
        # text / graphics projections
        test_projection_template_hygiene()
        test_syntax_to_text()
        test_primitive_to_text()
        test_text_to_graphics()
        test_word_wrapping()
        test_text_filtering()
        test_text_highlighting()
        test_selection_inverting()
        # widget projections
        test_object_to_widget()
        test_projection_configuring()
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
        test_widget_transform_pane()
        test_layout_closeout()
        test_widget_forms()
        test_anchor_point()
    end
end

"""
    test_visual_examples()

Walk the printer over every visual-tier example (`visual_examples`) — one
`@test` per forced reactive cell, via the generic `test_printer` driver.
"""
function test_visual_examples()
    @testset "VisualExamples" begin
        for ex in visual_examples
            @testset "\$(ex.name)" begin
                test_printer(ex)
            end
        end
    end
end

export test_visual, test_visual_layering, test_visual_examples
export test_syntax, test_text, test_graphics, test_affine_transform,
       test_graphics_layout, test_layout_allocator, test_layout_constraint_helpers,
       test_primitive
export test_projection_template_hygiene
export test_syntax_to_text, test_primitive_to_text, test_text_to_graphics,
       test_word_wrapping, test_text_filtering, test_text_highlighting,
       test_selection_inverting
export test_object_to_widget, test_projection_configuring,
       test_widget_text_editing, test_widget_button_behavior, test_widget_gestures,
       test_widget_select_dropdown, test_widget_menu, test_widget_context_menu,
       test_widget_dialog, test_widget_action, test_widget_icon, test_widget_tree,
       test_widget_toolbar, test_widget_table, test_widget_transform_pane,
       test_layout_closeout, test_widget_forms, test_anchor_point
export walk_typein, test_typein
export test_click_roundtrip, test_text_nav_invariants,
       _find_text_iomap, _find_cursor_rect, _pipeline_measure, _seg_x_at,
       _path_contains_projection_ref

end # module ProjecturedVisualTest
