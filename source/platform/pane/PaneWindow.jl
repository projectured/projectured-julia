# Fragment of `PaneModule` — the windows of tabs.
#
# The first window of an editor holds a tab tree inside the layers of its wrappers:
# an undo history, the menu bar, the toolbar and the status bar. A window that opens
# later with tabs gets the same layers around a tree of its own
# (`make_window_content`), and the screen draws it as the first window. Each window
# has its own tree, its own selection inside it and its own undo history.

"""
    OpenPaneWindowOperation(tab; title, x = -1, y = -1, width = 800, height = 600)

Open a window of tabs that holds `tab` in its one group, with the layers that the
first window of the editor has around its tabs, and give the tab the focus. `title`
is the title of the window, the name of the tab by default. `x` and `y` are the
place of the window on the screen, `(-1, -1)` to let the backend choose, and
`width` and `height` its size.

The operation names no place, so the readers carry it to the editor as it is, and
no history records it: a window is no edit of a document. The tab must be in no
other tree when the operation runs.
"""
struct OpenPaneWindowOperation <: Operation
    tab::PaneTab
    title::String
    x::Int
    y::Int
    width::Int
    height::Int
end

OpenPaneWindowOperation(tab::PaneTab; title::AbstractString = get_pane_tab_title_string(tab),
                        x::Integer = -1, y::Integer = -1, width::Integer = 800, height::Integer = 600) =
    OpenPaneWindowOperation(tab, String(title), Int(x), Int(y), Int(width), Int(height))

OperationModule.is_self_contained_operation(::OpenPaneWindowOperation) = true
OperationModule.describe_operation(::OpenPaneWindowOperation) = "Open a window with the tab"

function OperationModule.evaluate_operation(editor, operation::OpenPaneWindowOperation)
    tree = PaneTree(PaneGroup(PaneTab[operation.tab]))
    set_selection!(tree, @reference(tree, root.tabs[1]))
    content = make_window_content(editor, tree)
    evaluate_operation(editor, OpenWindowOperation(; id = _make_pane_window_id(editor),
        title = operation.title, x = operation.x, y = operation.y,
        width = operation.width, height = operation.height, style = :normal,
        content, selection = get_selection(content)))
end

# An id for a new window of tabs that no window of the screen of `editor` has:
# `tabs-2`, `tabs-3` and so on.
function _make_pane_window_id(editor)
    screen = get_wrapped_document(getfield(editor, :document))
    ids = hasproperty(screen, :windows) ? Set(window.id for window in screen.windows) : Set{Symbol}()
    for k in 2:typemax(Int)
        id = Symbol("tabs-", k)
        id in ids || return id
    end
end
