
# The standard widget projection: recursively dispatches every widget node
# through WidgetToGraphics. The light theme drives all colors, radius and
# spacing — see WidgetTheme. Use this for every per-widget example whose content
# is a plain string (label, checkbox, button, menu, composite, panes, …).
function make_widget_projection_example(; measure=FontFileMeasure())
    w2g = WidgetToGraphics(font_ubuntu_regular_20; measure=measure)
    # Several examples stack their variants with a VerticalLayout instead of
    # hand-positioned WidgetComposite children, so the renderer dispatches layout
    # nodes to LayoutToGraphics and widgets to WidgetToGraphics.
    inner = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        w2g.dispatch,
    )))
    # Tab starts over at the ends. A widget lights while its mouse target is set,
    # which each move of the pointer writes.
    ChainingProjection(
        FocusCyclingProjection(inner = inner),
    )
end

# Window-route projection for the widget popup example (Stage 3 Step 6). Composites
# the `ScreenDocument` through `WindowManager` + `ScreenToScreen`: a trigger's
# `OpenPopupOperation` bubbles up out of the window content, each reader moves its
# position into its own frame, and `ScreenToScreen` adds the window's origin and
# emits an `OpenWindowOperation` that `WindowManager` turns into a real popup
# window. Each window's content renders through the standard widget projection.
function make_widget_popup_projection_example(; measure=FontFileMeasure())
    widget_proj = make_widget_projection_example(; measure=measure)
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        _is_window_content(ref) &&
            return NestingProjection(widget_proj; recursion=IdentityProjection())
        ref isa EmptyReference &&
            return WindowManagingProjection(inner = ScreenToScreen())
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
    ref isa ConcreteReference || return false
    h = ref.head
    (h isa FieldReferenceStep && h.name == "windows") || return false
    r1 = ref.tail
    r1 isa ConcreteReference || return false
    r1.head isa RangeReferenceStep || return false
    r2 = r1.tail
    r2 isa ConcreteReference || return false
    (r2.head isa FieldReferenceStep && r2.head.name == "content") || return false
    r2.tail isa EmptyReference
end

# The editable-text widget projection. A WidgetText whose content is a TextBlock
# recurses that content through the Text domain, so the combined renderer must
# also dispatch TextBlock through TextToGraphics. All caret navigation / text
# editing then comes from TextToGraphics and the widget only maps the resulting
# references backward (see make_widget_text_document_example).
function make_widget_text_projection_example(; measure=FontFileMeasure())
    font = font_ubuntu_monospace_regular_20
    w2g  = WidgetToGraphics(font; measure=measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[
            TextBlock => TextToGraphics(measure=measure),
        ],
    )))
end
