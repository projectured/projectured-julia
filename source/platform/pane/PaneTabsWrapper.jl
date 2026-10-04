# Fragment of `PaneModule` — the tabs of an editor, as a wrapper of
# `build_editor`, and the tab that `show_document!` opens.
#
# **The wrapper `tabs`** puts the root document in the one tab of a pane tree.
# It is on by default, so an editor that is built with the pane package loaded
# shows its documents as tabs, and a caller turns it off with `tabs = false`.
# A root that is a pane tree or a screen already is left as it is.
#
# **The tabs draw their own widgets.** `PaneToWidget` makes the widgets of the
# tree and leaves the content of each tab as it is. The stage after it draws a
# widget or a layout with the widget renderer, and sends every other document
# to the caller's projection. So the tabs work with a projection that draws no
# widget, and a content that is itself a widget draws as a widget. The widget
# printers hand their own context to a child, so a content can not be told by
# its place.

"""
    make_tabs_projection(projection; appearance, measure) -> Projection

The projection of a pane tree whose tabs hold documents that `projection`
draws: the tree, its tabs and every widget or layout draw with the widget
renderer, in the scaled widget theme of `appearance` and measured with
`measure`, and every other document draws with `projection`.
"""
function make_tabs_projection(projection; appearance::Appearance = Appearance(),
                              measure::TextMeasure = FontFileMeasure())
    rows = Pair{Type,Any}[LayoutToGraphics(; theme = get_scaled_theme!(appearance, GraphicsTheme)).dispatch;
                          WidgetToGraphics(; measure = measure,
                                           theme = get_scaled_theme!(appearance, WidgetTheme),
                                           graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)).dispatch;
                          Any => NestingProjection(projection; recursion = IdentityProjection())]
    ChainingProjection(
        RecursiveProjection(FaultCatchingProjection(inner = PaneToWidget(),
                                                    substitute = FaultToWidget())),
        RecursiveProjection(FaultCatchingProjection(inner = TypeDispatchingProjection(rows),
                                                    substitute = FaultToGraphics())))
end

"""
    tabs = true | (; title, appearance, measure)

The wrapper of `build_editor` that puts the root document in the one tab of a
pane tree, drawn with [`make_tabs_projection`](@ref). It is on by default, and
it does nothing when the root is a `PaneTree` or a `ScreenDocument` already. `title` names the tab;
the default is the title of the document, else "Document". The widgets of the
pane draw with the widget theme of `appearance`; the default is the `Appearance`
of the `appearance` wrapper of the same editor, so the keys of the zoom and of the
scales reach the tab strip too.
"""
function wrap_editor!(::Val{:tabs}, layer::Symbol, argument, parts::EditorParts)
    (parts.document isa PaneTree || parts.document isa ScreenDocument) && return parts
    options = argument === true ? (;) : argument
    document = parts.document
    title = get(options, :title, nothing)
    title === nothing && (title = something(get_document_title(document), "Document"))
    tree = PaneTree(PaneGroup([PaneTab(string(title), document)]))
    # The tree is the new root, so it holds the selection that the document
    # holds, rooted at the tree.
    inner = get_selection(document)
    inner === nothing || set_selection!(tree, @reference(tree, root.tabs[1].content.^(inner)))
    parts.document = tree
    parts.projection = make_tabs_projection(parts.projection;
        appearance = get(options, :appearance, get(parts.arguments, :appearance, Appearance())),
        measure = get(options, :measure, FontFileMeasure()))
    parts
end

get_wrapper_layers(::Val{:tabs}) = (:container => 0,)
is_wrapper_default(::Val{:tabs}) = true

"""
    show_document!(editor, content::PaneTree, document; title) -> nothing

Show `document` in a tab of the pane tree: the tab that shows it already, with
the focus, or a new tab named `title`.
"""
function show_document!(editor::Editor, ::PaneTree, document; title::AbstractString)
    tab = find_pane(editor, title)
    if tab !== nothing && get_document(tab).content === document
        focus_pane!(editor, tab)
    else
        open_pane!(editor, document; title = String(title))
    end
    nothing
end
