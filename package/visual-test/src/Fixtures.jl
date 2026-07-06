# ═══════════════════════════════════════════════════════════════════════════
# visual-test/src/Fixtures.jl
#
# Local widget/layout fixtures, mirrored from `ProjecturedExample` (which this
# package must not depend on — the example package sits above the whole
# runtime stack). Per plan/pending/test-package-split.md, low test packages
# build small local fixture documents/projections inline until the examples
# themselves are split per package; these copies are byte-for-byte the example
# factories, so the split becomes a no-op swap later.
# ═══════════════════════════════════════════════════════════════════════════

# The standard widget projection: recursively dispatches every widget node
# through WidgetToGraphics. The light theme drives all colors, radius and
# spacing — see WidgetTheme.
function make_widget_projection_example(; measure=truetype_measure_text)
    w2g = WidgetToGraphics(font_ubuntu_regular_20; measure=measure)
    # Several fixtures stack their variants with a VerticalLayout instead of
    # hand-positioned WidgetComposite children, so the renderer dispatches layout
    # nodes to LayoutToGraphics and widgets to WidgetToGraphics.
    inner = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        w2g.dispatch,
    )))
    # Wrap in the hover tracker so a button's `hovered` flag clears when the
    # pointer leaves it (container routing only delivers a move to the hit child).
    ChainingProjection(
        WidgetHoverTrackingProjection(inner = inner),
    )
end

# Window-route projection for the widget popup fixture: composites the
# `ScreenDocument` through `WindowManager` + `ScreenToScreen`, with a
# `WidgetPopupResolverProjection` between them; each window's content renders
# through the standard widget projection.
function make_widget_popup_projection_example(; measure=truetype_measure_text)
    widget_proj = make_widget_projection_example(; measure=measure)
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        _is_window_content(ref) &&
            return NestingProjection(widget_proj; recursion=IdentityProjection())
        ref isa EmptyReferencePath &&
            return WindowManagingProjection(
                inner = WidgetPopupResolverProjection(inner = ScreenToScreen()))
        return IdentityProjection()
    end)
    RecursiveProjection(
        TypeDispatchingProjection(
            WindowDocument => ScreenToScreen(),
            Any            => ref_dispatch,
        ))
end

# True iff `ref` addresses a window's whole content: `windows[i].content`.
function _is_window_content(ref)
    ref isa ConcreteReferencePath || return false
    h = ref.head
    (h isa FieldReference && h.name == "windows") || return false
    r1 = ref.tail
    r1 isa ConcreteReferencePath || return false
    r1.head isa RangeReference || return false
    r2 = r1.tail
    r2 isa ConcreteReferencePath || return false
    (r2.head isa FieldReference && r2.head.name == "content") || return false
    r2.tail isa EmptyReferencePath
end

# Project a tree of `HorizontalLayout` / `VerticalLayout` / `GridLayout` /
# `FlowLayout` whose leaves are widgets. The dispatcher routes layout nodes to
# their `…ToGraphicsCanvas` projections and any other document (widgets in
# this fixture) to `WidgetToGraphics`.
function make_layout_projection_example(; measure=truetype_measure_text)
    font = font_ubuntu_regular_20
    # Dark foreground — this fixture renders directly onto the backend's
    # default (light) background, without a `WidgetShell` to provide a
    # dark fill behind it.
    fg   = (0x22, 0x22, 0x2a, 0xff)
    ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(
            HorizontalLayout => HorizontalLayoutToGraphicsCanvas(),
            VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
            GridLayout       => GridLayoutToGraphicsCanvas(),
            FlowLayout       => FlowLayoutToGraphicsCanvas(),
            Any              => WidgetToGraphics(font; measure=measure),
        )),
    )
end

# A *nested* settings object exercising ObjectToWidget's recursive form: a
# sub-struct (`window`) renders as a collapsible card holding its own
# label|control grid, and a vector (`tags`) renders as a collapsible card
# holding a vertical list. Scalar fields at every level whose backing is a
# `Cell` stay editable.
@document struct WindowSettings
    title::String
    width::Int
    height::Int
    visible::Bool
    selection::Reference
end

@document struct AppSettings
    name::String
    dark_mode::Bool
    window::WindowSettings
    tags::Vector
    selection::Reference
end

function make_nested_object_to_widget_document_example()
    AppSettings("MyApp", true,
                WindowSettings("Main", 800, 600, true, nothing),
                Any["alpha", "beta"], nothing)
end
