# Lightweight wrapper that escapes the surrounding projection's type-dispatch
# path so an arbitrary Julia value (the editor's document, projection, …) can
# be embedded in a widget tree without the widget projection trying to render
# it as one of its known node types. Routed to the ObjectToSyntax chain.
struct EditorIntrospection
    value::Any
end

function make_scrolling_document(document; width=nothing, height=nothing)
    size = (width !== nothing && height !== nothing) ? Point2D(width, height) : nothing
    WidgetScrollPane(document; size=size)
end

function make_introspection_document(document, projection; title="content")
    WidgetTabbedPane(Any[
        (title,              document),
        ("editor.document",   EditorIntrospection(document)),
        ("editor.projection", EditorIntrospection(projection)),
    ])
end

# DraggingState and DraggingProjection, dragging's two helpers, are types of
# `ProjecturedPlatform`, so a program can drag without this package's
# dependencies. The gallery uses them from there; see `DraggingModule`.

# Wrap any example document in a WidgetShell, so the content sits inside a
# top-level window frame: a menu bar, a toolbar, and a status bar that names the
# example. The chrome mirrors `make_widget_shell_document_example`. Its commands
# are inert here, because the gallery composes no popup resolver, so a submenu
# draws but does not open. Pairs with `make_shell_projection`.
function make_shell_document(document; title="untitled", width=nothing, height=nothing)
    new_action  = Action("New")
    open_action = Action("Open")
    save_action = Action("Save"; shortcut=Shortcut(:s; ctrl=true))
    menu_bar = WidgetMenu([
        WidgetMenuItem("File"; submenu=WidgetMenu([
            WidgetMenuItem(new_action),
            WidgetMenuItem(open_action),
            WidgetMenuItem(save_action)])),
        WidgetMenuItem("Edit"; submenu=WidgetMenu([
            WidgetMenuItem("Undo"), WidgetMenuItem("Redo")])),
        WidgetMenuItem("Help"; submenu=WidgetMenu([
            WidgetMenuItem("About")])),
    ]; orientation=:horizontal)
    toolbar = WidgetToolbar([WidgetMenuItem(new_action),
                             WidgetMenuItem(open_action),
                             WidgetMenuItem(save_action)];
                            padding=Inset(4, 4, 4, 4))
    status_bar = WidgetStatusBar([title, "Ready"])
    size = (width !== nothing && height !== nothing) ? Point2D(width, height) : nothing
    WidgetShell(document;
                menu_bar=menu_bar, toolbar=toolbar, status_bar=status_bar,
                size=size)
end

# Wrap a text document in a find bar view: the text, highlighted or filtered by
# a pattern, under a collapsible card that holds a form of the fields of the
# pattern. Ctrl+F shows the bar and puts the caret in the pattern, and Escape
# hides it and puts the caret back in the text. The pattern "dolor" makes the
# highlight visible at once. Pairs with `make_find_bar_projection`.
function make_find_bar_document(document; filter::Bool = false)
    text = filter ? FilteredText(; text = document, pattern = "dolor") :
                    HighlightedText(; text = document, pattern = "dolor")
    title = filter ? "Filter" : "Find"
    rows = Any[(WidgetLabel(title), ObjectField(text, "pattern")),
               (WidgetLabel("Regular expression"), ObjectField(text, "regex")),
               (WidgetLabel("Ignore case"), ObjectField(text, "case_insensitive"))]
    filter && push!(rows, (WidgetLabel("Invert"), ObjectField(text, "invert")))
    bar = WidgetCard(; title = WidgetLabel(title), collapsible = true, content = FormLayout(rows))
    FindBarView(; bar, content = text)
end
