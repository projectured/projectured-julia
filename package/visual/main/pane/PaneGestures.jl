"""
    PaneGesturesModule

The keyboard, as a reified [`@gestures`](@ref) table on `PaneTree`.

Every chord carries a modifier, because the plain keys belong to the content of
the focused tab. Two of them need more than that:

  * **`Ctrl+Alt` and the arrows** move the focus between groups. Plain
    `Alt`+arrow is the structural navigation of a document — a syntax tree binds
    it — so the pane layer takes the next chord out rather than fighting it.
  * **`Ctrl+Tab`** traverses the groups, and is declared `override` because the
    widget split pane answers every `Tab` with its own focus traversal. Plain
    `Tab` can not do this work at all: a text document takes it.

Nothing here builds an operation of its own — each rule calls a surgery builder,
which answers with a generic operation.
"""
module PaneGesturesModule

import ..GestureBindingModule: var"@gestures"
import ..PaneModule: PaneTree, PaneGroup, PaneTab, default_new_pane_tab, pane_groups
import ..PaneSurgeryModule: pane_focus, pane_focused_group, pane_focus_operation,
                            pane_open_tab_operation, pane_close_tab_operation,
                            pane_split_operation
import ..PaneGeometryModule: pane_neighbour_group, pane_next_group

# The tab a group shows: the one its own selection names, or its first. A group
# that has no tab answers 0, which names the group itself.
function _shown_index(group::PaneGroup)
    isempty(group.tabs) && return 0
    selection = getfield(group, :selection)[]
    index = _tabs_index(selection)
    (1 <= index <= length(group.tabs)) ? index : 1
end

function _tabs_index(selection)
    selection === nothing && return 0
    hasproperty(selection, :head) || return 0
    head = selection.head
    (hasproperty(head, :name) && head.name == "tabs") || return 0
    tail = selection.tail
    hasproperty(tail, :head) || return 0
    step = tail.head
    hasproperty(step, :start) ? Int(step.start) + 1 : 0
end

# ── The rules' bodies ──────────────────────────────────────────────────────

function _open_tab(tree::PaneTree)
    group = pane_focused_group(tree)
    group === nothing && return nothing
    pane_open_tab_operation(tree, group, default_new_pane_tab())
end

function _close_tab(tree::PaneTree)
    focus = pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    index == 0 && return nothing            # an empty group has no tab to close
    pane_close_tab_operation(tree, group, index)
end

function _split(tree::PaneTree, orientation::Symbol, side::Symbol)
    group = pane_focused_group(tree)
    group === nothing && return nothing
    pane_split_operation(tree, group, orientation, side, default_new_pane_tab())
end

function _move_focus(tree::PaneTree, direction::Symbol)
    group = pane_focused_group(tree)
    group === nothing && return nothing
    target = pane_neighbour_group(tree, group, direction)
    target === nothing && return nothing
    pane_focus_operation(tree, target, _shown_index(target))
end

function _traverse(tree::PaneTree, backward::Bool)
    group = pane_focused_group(tree)
    target = pane_next_group(tree, group; backward)
    (target === nothing || target === group) && return nothing
    pane_focus_operation(tree, target, _shown_index(target))
end

# The next or previous tab of the focused group, wrapping around.
function _sibling_tab(tree::PaneTree, step::Int)
    focus = pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    n = length(group.tabs)
    n == 0 && return nothing
    index == 0 && (index = 1)
    pane_focus_operation(tree, group, mod1(index + step, n))
end

# ── The table ──────────────────────────────────────────────────────────────

@gestures PaneTree begin
    KeyDown(:t; ctrl) => "Open a new tab" => _open_tab(doc)
    KeyDown(:w; ctrl) => "Close the focused tab" => _close_tab(doc)
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
end

end # module PaneGesturesModule
