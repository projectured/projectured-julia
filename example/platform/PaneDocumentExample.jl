# Pane-tree example documents.

# The state a fresh layout starts in: one tab group, with no tabs. The new-tab
# button on its strip is the only affordance, and `Ctrl+T` is the only chord that
# does anything — everything else in the layout grows from here.
make_empty_pane_document_example() = PaneTree(PaneGroup(PaneTab[]))

# A layout with something in it: two panes side by side, the right one split
# again so three groups share the window.
#
#   +-----------+-----------+
#   |           |  notes    |
#   |  read me  +-----------+
#   |  license  |  scratch  |
#   +-----------+-----------+
function make_pane_document_example()
    left = PaneGroup(PaneTab[
        PaneTab("read me", PrimitiveString("A pane tree organizes documents on the screen.\n\n" *
                                           "Ctrl+T opens a tab, Ctrl+W closes one.\n" *
                                           "Ctrl+\\ splits this group, Ctrl+Shift+\\ splits it the other way.\n" *
                                           "Ctrl+Alt and an arrow move the focus, Ctrl+Tab traverses.")),
        PaneTab("license", PrimitiveString("Public domain."))])
    notes = PaneGroup(PaneTab[PaneTab("notes", PrimitiveString("Drag a tab onto another group to move it."))])
    scratch = PaneGroup(PaneTab[PaneTab("scratch", PrimitiveString(""))])
    right = PaneSplit(:horizontal, [notes, scratch])
    tree = PaneTree(PaneSplit(:vertical, [left, right]; weights = [0.55, 0.45]))
    # Start with the focus in the first tab, so the layout opens showing it.
    set_selection!(tree, get_pane_tab_reference(tree, left, 1))
    tree
end
