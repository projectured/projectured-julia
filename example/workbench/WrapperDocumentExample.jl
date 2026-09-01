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

# Wrap any example document in a clipboard so the copy/cut/paste flow can operate
# over it. `collection=true` uses a ClipboardCollection (the elements view), else a
# ClipboardSlice (the single-slice view). Pairs with `make_clipboard_projection`.
make_clipboard_document(document; collection=false) =
    collection ? ClipboardCollection(document) : ClipboardSlice(document)

# Wrap any example document in a DraggingState, so a press that travels
# `threshold` pixels becomes a drag and a drop reorders the collection under the
# grab point. The wrapper is transparent to the printer. Pairs with
# `make_dragging_projection`.
make_dragging_document(document; threshold::Int=5) = DraggingState(document, threshold)

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

function make_workbench_document(document; title="untitled", filename=title)
    # Start the navigator in the current working directory, so the workbench opens
    # showing the files next to wherever the editor was launched from.
    cwd = pwd()
    nav_page = WorkbenchPage([
        WorkbenchNavigator(Workspace([WorkspaceFolder(basename(cwd), cwd)])),
    ])
    edit_page = WorkbenchPage([
        WorkbenchEditor(document; title=title, filename=filename),
    ])
    info_page = WorkbenchPage([
        WorkbenchConsole(),
        WorkbenchDescriptor(EmptyReference()),
        WorkbenchOperator(),
        WorkbenchSearcher(),
        WorkbenchEvaluator(),
    ])
    control_page = WorkbenchPage([
        # Example doc: explicit FakeLlm so the embedded assistant works offline.
        Assistant(; llm = FakeLlm()),
    ])
    WorkbenchWorkbench(nav_page, edit_page, info_page, control_page)
end
