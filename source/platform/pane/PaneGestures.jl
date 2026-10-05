# Fragment of `PaneModule`.
#
# The keyboard, as a reified [`@gestures`](@ref) table on `PaneTree`.
#
# Every chord carries a modifier, because the plain keys belong to the content of
# the focused tab. Two of them need more than that:
#
#   * **`Ctrl+Alt` and the arrows** move the focus between groups. Plain
#     `Alt`+arrow is the structural navigation of a document — a syntax tree binds
#     it — so the pane layer takes the next chord out rather than fighting it.
#   * **`Ctrl+Tab`** traverses the groups, and is declared `override` because the
#     widget split pane answers every `Tab` with its own focus traversal. Plain
#     `Tab` can not do this work at all: a text document takes it.
#
# Nothing here builds an operation of its own — each rule calls a surgery builder,
# which answers with a generic operation.
const _NO_MODIFIERS = ModifierKeys()

# ── The rules' bodies ──────────────────────────────────────────────────────

function _open_tab(tree::PaneTree)
    group = get_pane_focused_group(tree)
    group === nothing && return nothing
    make_pane_open_tab_operation(tree, group, default_new_pane_tab())
end

function _close_tab(tree::PaneTree)
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    index == 0 && return nothing            # an empty group has no tab to close
    make_pane_close_tab_operation(tree, group, index)
end

function _duplicate_tab(tree::PaneTree)
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    index == 0 && return nothing            # an empty group has no tab to duplicate
    make_pane_duplicate_tab_operation(tree, group, index)
end

function _split(tree::PaneTree, orientation::Symbol, side::Symbol)
    group = get_pane_focused_group(tree)
    group === nothing && return nothing
    make_pane_split_operation(tree, group; orientation, side, tab = default_new_pane_tab())
end

function _move_focus(tree::PaneTree, direction::Symbol)
    group = get_pane_focused_group(tree)
    group === nothing && return nothing
    target = get_pane_neighbour_group(tree, group, direction)
    target === nothing && return nothing
    make_pane_focus_operation(tree, target, get_pane_shown_tab_index(target))
end

function _traverse(tree::PaneTree, backward::Bool)
    group = get_pane_focused_group(tree)
    target = get_pane_next_group(tree, group; backward)
    (target === nothing || target === group) && return nothing
    make_pane_focus_operation(tree, target, get_pane_shown_tab_index(target))
end

# The next or previous tab of the focused group, wrapping around.
function _sibling_tab(tree::PaneTree, step::Int)
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    n = length(group.tabs)
    n == 0 && return nothing
    index == 0 && (index = 1)
    make_pane_focus_operation(tree, group, mod1(index + step, n))
end

# ── The tab title ──────────────────────────────────────────────────────────
#
# A rename is not a mode. The title is a text document, so putting the caret in it
# *is* the editing state, and the editing itself is the title document's own
# business: each keystroke is handed to `read_gesture(title, …)`, whose
# `@gestures PrimitiveString` table inserts and deletes, and the answer is
# re-rooted onto the tree. This slice writes no editing code.

# Put the caret at the end of the focused tab's name.
function _rename(tree::PaneTree)
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    index == 0 && return nothing
    make_pane_title_caret_operation(tree, group, index)
end

# Leave the title: the selection goes back to the tab it names.
function _leave_title(tree::PaneTree)
    found = get_pane_focus_title(tree)
    found === nothing && return nothing
    make_pane_focus_operation(tree, found[1], found[2])
end

# Hand one keystroke to the name in the title and re-root what it answers. The event
# is rebuilt from the pattern's own bound fields, because a rule body sees those
# and not the event object.
function _title_edit(tree::PaneTree, event)
    found = get_pane_focus_title(tree)
    found === nothing && return nothing
    group, index = found
    answer = read_gesture(group.tabs[index].title.name, event)
    answer === nothing && return nothing
    make_pane_retarget_title_operation(tree, group, index; operation = answer)
end

# ── The walk at a tab ──────────────────────────────────────────────────────
#
# The generic walk (`SelectionWalkingProjection`) steps between the fields of a
# document. At a tab that is wrong twice: the field next to a tab's content is
# the tab's title, which is not an object of the content, and the object above
# a tab is the split that holds its group. So the pane answers the Alt + arrow
# keys at a tab itself. A whole tab steps sideways to its neighbour, steps down
# into its content, and is the top of the walk. The root of a tab's content has
# no sibling.

# Which of the two the selection names as a whole — `:tab` or `:content` — with
# the group and the tab's index, or `nothing` for any other selection.
function _find_walk_tab(tree::PaneTree)
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    index == 0 && return nothing
    selection = strip_reference_types(get_selection(tree))
    tab = get_pane_tab_reference(tree, group, index)
    tab !== nothing && selection == strip_reference_types(tab) && return (group, index, :tab)
    content = get_pane_content_path(tree, group, index)
    content !== nothing && selection == strip_reference_types(content) && return (group, index, :content)
    nothing
end

function _walk_tab(tree::PaneTree, key::Symbol)
    found = _find_walk_tab(tree)
    found === nothing && return nothing
    group, index, part = found
    if part === :content
        key in (:left, :right) || return nothing
        return ReplaceSelectionOperation(get_pane_content_path(tree, group, index))
    end
    key === :down && return ReplaceSelectionOperation(get_pane_content_path(tree, group, index))
    key === :up && return make_pane_focus_operation(tree, group, index)
    step = key === :left ? -1 : 1
    make_pane_focus_operation(tree, group, clamp(index + step, 1, length(group.tabs)))
end

# ── The table ──────────────────────────────────────────────────────────────

@gestures PaneTree begin
    KeyDown(:t; ctrl) => "Open a new tab" => _open_tab(doc)
    KeyDown(:w; ctrl) => "Close the focused tab" => _close_tab(doc)
    KeyDown(:d; ctrl, shift) => "Duplicate the focused tab" => _duplicate_tab(doc)
    KeyDown(:backslash; ctrl) =>
        "Split vertically — the new pane on the right" => _split(doc, :vertical, :right)
    KeyDown(:backslash; ctrl, shift) =>
        "Split horizontally — the new pane below" => _split(doc, :horizontal, :below)
    when(KeyDown(k; ctrl, alt), k in (:left, :right, :up, :down)) =>
        "Move the focus to the group in that direction" =>
            _move_focus(doc, k)
    override(KeyDown(:tab; ctrl)) => "Focus the next group" => _traverse(doc, false)
    override(KeyDown(:tab; ctrl, shift)) => "Focus the previous group" => _traverse(doc, true)
    KeyDown(:page_down; ctrl) => "Focus the next tab" => _sibling_tab(doc, 1)
    KeyDown(:page_up; ctrl) => "Focus the previous tab" => _sibling_tab(doc, -1)
    when(KeyDown(k; alt), k in (:left, :right, :up, :down)) =>
        "Walk from a whole tab to its neighbour or into its content" =>
            _walk_tab(doc, k)
    KeyDown(:f2;) => "Put the caret in the tab name" => _rename(doc)
    # The four rules of a rename. Each answers `nothing` unless the caret is in a
    # name, so a key that means something else keeps meaning it — the rule body
    # is the guard, because a `when(…)` guard sees only the event's own fields.
    KeyDown(:escape;) => "Leave the tab name" => _leave_title(doc)
    KeyPress(c, t) => "Type in the tab name" => _title_edit(doc, KeyPress(c, t, _NO_MODIFIERS;
                                                                          time = time()))
    KeyDown(:backspace;) =>
        "Delete backward in the tab name" => _title_edit(doc, KeyDown(:backspace, _NO_MODIFIERS;
                                                                      time = time()))
    KeyDown(:delete;) =>
        "Delete forward in the tab name" => _title_edit(doc, KeyDown(:delete, _NO_MODIFIERS;
                                                                     time = time()))
end
