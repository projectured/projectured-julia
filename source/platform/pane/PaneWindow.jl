# Fragment of `PaneModule` — the windows of tabs.
#
# The first window of an editor holds a tab tree inside the layers of its wrappers:
# an undo history, the menu bar, the toolbar and the status bar. A window that opens
# later with tabs gets the same layers around a tree of its own
# (`make_window_content`), and the screen draws it as the first window. Each window
# has its own tree, its own selection inside it and its own undo history.

"""
    OpenPaneWindowOperation(tab; title, x = -1, y = -1, width = 800, height = 600, acquire = true)

Open a window of tabs that holds `tab` in its one group, with the layers that the
first window of the editor has around its tabs, and give the tab the focus. `title`
is the title of the window, the name of the tab by default. `x` and `y` are the
place of the window on the screen, `(-1, -1)` to let the backend choose, and
`width` and `height` its size. With `acquire`, the window acquires what the tab
shows (`AcquireDocumentOperation`), as the open of a tab does. A tab that comes
from another window is held already, and takes `acquire = false`.

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
    acquire::Bool
end

OpenPaneWindowOperation(tab::PaneTab; title::AbstractString = get_pane_tab_title_string(tab),
                        x::Integer = -1, y::Integer = -1, width::Integer = 800, height::Integer = 600,
                        acquire::Bool = true) =
    OpenPaneWindowOperation(tab, String(title), Int(x), Int(y), Int(width), Int(height), acquire)

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
    operation.acquire && evaluate_operation(editor, AcquireDocumentOperation(operation.tab))
    nothing
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

# The point of an operation that a reader moves on the way up, from the frame of a
# part into the frame of the screen; the place `(-1, -1)` is no point, and stays.
_move_window_place(x::Int, y::Int, move) =
    (x, y) == AUTOMATIC_WINDOW_PLACE ? (x, y) : move(x, y)

GraphicsModule.map_operation_position(operation::OpenPaneWindowOperation, move) =
    OpenPaneWindowOperation(operation.tab, operation.title,
                            _move_window_place(operation.x, operation.y, move)...,
                            operation.width, operation.height, operation.acquire)

# ── A tab goes out of its window ─────────────────────────────────────────────

"""
    MovePaneTabToWindowOperation(tree, group, tab; x = -1, y = -1, width = 800, height = 600)

Move `tab` of `group` of `tree` into a new window of tabs
([`OpenPaneWindowOperation`](@ref)), with its upper left corner at `(x, y)` and the
size `(width, height)`. The tab leaves its group as a close takes it out
([`make_pane_remove_tab_operation`](@ref)), and what it shows keeps its work. A tab
that left `group` moves nothing.

The operation carries its documents, so the readers carry it to the editor as it is,
and its point moves into the frame of the screen on the way up. A reader marks it as
view state, so no history records it: the move takes the tab out of one window and
into another, which is no edit of one window.
"""
struct MovePaneTabToWindowOperation <: Operation
    tree::PaneTree
    group::PaneGroup
    tab::PaneTab
    x::Int
    y::Int
    width::Int
    height::Int
end

MovePaneTabToWindowOperation(tree::PaneTree, group::PaneGroup, tab::PaneTab;
                             x::Integer = -1, y::Integer = -1,
                             width::Integer = 800, height::Integer = 600) =
    MovePaneTabToWindowOperation(tree, group, tab, Int(x), Int(y), Int(width), Int(height))

OperationModule.is_self_contained_operation(::MovePaneTabToWindowOperation) = true
OperationModule.describe_operation(::MovePaneTabToWindowOperation) = "Move the tab to a new window"

GraphicsModule.map_operation_position(operation::MovePaneTabToWindowOperation, move) =
    MovePaneTabToWindowOperation(operation.tree, operation.group, operation.tab,
                                 _move_window_place(operation.x, operation.y, move)...,
                                 operation.width, operation.height)

function OperationModule.evaluate_operation(editor, operation::MovePaneTabToWindowOperation)
    index = findfirst(tab -> tab === operation.tab, operation.group.tabs)
    index === nothing && return nothing
    remove = make_pane_remove_tab_operation(operation.tree, operation.group, index)
    remove === nothing && return nothing
    place = find_document_path(getfield(editor, :document), operation.tree)
    place === nothing && return nothing
    evaluate_operation(editor, reroot_operation(remove, Tuple(get_reference_steps(place))))
    evaluate_operation(editor, OpenPaneWindowOperation(operation.tab;
        x = operation.x, y = operation.y, width = operation.width, height = operation.height,
        acquire = false))
end

# Whether a tab of `tree` can go out to a window of its own: the tree holds another
# tab, so the window it leaves keeps one. The only tab of a window would make the
# same window at another place.
can_move_pane_tab_out(tree::PaneTree) =
    sum(length(group.tabs) for group in get_pane_groups(tree); init = 0) > 1

# The least size of a window that a tab goes out to.
const _PANE_WINDOW_MINIMUM = (400, 300)

# ── The label of a tab outside the windows ───────────────────────────────────

# The id of the window of the label that follows the pointer outside the windows
# during the drag of a tab.
const _PANE_TAB_LABEL_WINDOW = :pane_tab_label

# The gap between the pointer and the label, below and right of it.
const _PANE_TAB_LABEL_GAP = (16, 12)

"""
    PaneTabLabelOperation(x, y, tab)
    PaneTabLabelOperation(nothing)

Show the label of `tab`, its icon and its name, in a small window with no frame
below and right of the point `(x, y)`, or move it there; with `nothing`, close it.
The drag of a tab shows it while the pointer is outside every window of the editor,
where a release opens a new window. It is pointer feedback: the reader marks it as
view state, so no history records it, and its point moves into the frame of the
screen on the way up.
"""
struct PaneTabLabelOperation <: Operation
    x::Int
    y::Int
    tab::Union{PaneTab,Nothing}
end

PaneTabLabelOperation(::Nothing) = PaneTabLabelOperation(0, 0, nothing)

OperationModule.is_self_contained_operation(::PaneTabLabelOperation) = true
OperationModule.describe_operation(::PaneTabLabelOperation) = "Show the label of the dragged tab"

GraphicsModule.map_operation_position(operation::PaneTabLabelOperation, move) =
    operation.tab === nothing ? operation :
    PaneTabLabelOperation(move(operation.x, operation.y)..., operation.tab)

function OperationModule.evaluate_operation(editor, operation::PaneTabLabelOperation)
    if operation.tab === nothing
        screen = get_wrapped_document(getfield(editor, :document))
        (hasproperty(screen, :windows) && any(window -> window.id === _PANE_TAB_LABEL_WINDOW, screen.windows)) ||
            return nothing
        return evaluate_operation(editor, CloseWindowOperation(_PANE_TAB_LABEL_WINDOW))
    end
    title = operation.tab.title
    label = WidgetToolbarItem(get_pane_tab_title_string(operation.tab); icon = title.icon)
    evaluate_operation(editor, OpenWindowOperation(; id = _PANE_TAB_LABEL_WINDOW, title = "",
        x = operation.x + _PANE_TAB_LABEL_GAP[1], y = operation.y + _PANE_TAB_LABEL_GAP[2],
        width = 240, height = 40, minimum_size = (24, 16), maximum_size = (240, 40),
        style = :tooltip, content = label))
end

# ── A tab goes into another window ───────────────────────────────────────────

"""
    MovePaneTabAcrossOperation(source_tree, source_group, tab, target_tree, target, zone, place)

Move `tab` of `source_group` of `source_tree` into the group `target` of
`target_tree`, the tree of another window: at `place` of its strip for the zone
`:strip`, at its end for the middle, and in a new group beside it for an edge band
(`:left`, `:right`, `:above`, `:below`). The tab takes the focus there and keeps
what it shows. When `source_tree` has no tab left, its window closes.

The operation carries its documents, so the readers carry it to the editor as it
is. A reader marks it as view state, so no history records it: the move takes the
tab out of one window and into another, which is no edit of one window.
"""
struct MovePaneTabAcrossOperation <: Operation
    source_tree::PaneTree
    source_group::PaneGroup
    tab::PaneTab
    target_tree::PaneTree
    target::PaneGroup
    zone::Symbol
    place::Union{Int,Nothing}
end

OperationModule.is_self_contained_operation(::MovePaneTabAcrossOperation) = true
OperationModule.describe_operation(::MovePaneTabAcrossOperation) = "Move the tab to another window"

function OperationModule.evaluate_operation(editor, operation::MovePaneTabAcrossOperation)
    index = findfirst(tab -> tab === operation.tab, operation.source_group.tabs)
    index === nothing && return nothing
    insert = _make_across_insert(operation)
    remove = make_pane_remove_tab_operation(operation.source_tree, operation.source_group, index)
    (insert === nothing || remove === nothing) && return nothing
    root = getfield(editor, :document)
    source_place = find_document_path(root, operation.source_tree)
    target_place = find_document_path(root, operation.target_tree)
    (source_place === nothing || target_place === nothing) && return nothing
    evaluate_operation(editor, reroot_operation(remove, Tuple(get_reference_steps(source_place))))
    evaluate_operation(editor, reroot_operation(insert, Tuple(get_reference_steps(target_place))))
    # A window whose last tab left it closes.
    any(group -> !isempty(group.tabs), get_pane_groups(operation.source_tree)) && return nothing
    id = _find_pane_tree_window(editor, operation.source_tree)
    id === nothing || evaluate_operation(editor, CloseWindowOperation(id))
    nothing
end

# The insert of the tab of `operation` into its target, as the edit of the target
# tree: the tab is held already, so it acquires nothing.
function _make_across_insert(operation::MovePaneTabAcrossOperation)
    orientation = get_pane_zone_orientation(operation.zone)
    if orientation === nothing
        target = operation.target
        index = (operation.zone === :strip && operation.place !== nothing) ? operation.place :
                length(target.tabs) + 1
        return make_pane_open_tab_operation(operation.target_tree, target, operation.tab;
                                            index, acquire = false)
    end
    make_pane_split_operation(operation.target_tree, operation.target; orientation,
                              side = operation.zone, tab = operation.tab, acquire = false)
end

# The id of the window of the screen of `editor` whose content holds `tree`, or
# `nothing`.
function _find_pane_tree_window(editor, tree::PaneTree)
    screen = get_wrapped_document(getfield(editor, :document))
    hasproperty(screen, :windows) || return nothing
    for window in screen.windows
        _holds_pane_tree(window.content, tree) && return window.id
    end
    nothing
end

# Whether `content`, the content of a window, holds `tree` inside its layers.
function _holds_pane_tree(content, tree::PaneTree)
    node = content
    for _ in 1:_TAB_DOCUMENT_LAYERS
        node === tree && return true
        wrapped = get_wrapped_document(node)
        if wrapped === node
            hasproperty(node, :content) || return false
            node = node.content
        else
            node = wrapped
        end
    end
    false
end

# ── The close of a window of tabs ────────────────────────────────────────────

# The window of `tree` closes: each of its tabs is released, as the close of a tab
# releases it, so what a tab holds outside the tree, such as the agent of an
# assistant or the watch of a file, ends.
_release_pane_tree_tabs(tree::PaneTree) =
    CompoundOperation(Any[ReleaseDocumentOperation(tab)
                          for group in get_pane_groups(tree) for tab in group.tabs])
