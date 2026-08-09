# Pane-tree example documents that hold real domain documents.
#
# The visual tier's `make_pane_document_example` fills its tabs with plain
# strings, because the pane slice sits below every source domain. This tier is
# above them, so a tab here can hold the json example document itself.

# Three tab groups, and the focused tab holds the json example document.
#
#   +-----------------+-----------+
#   |  data.json      |  notes    |
#   |  read me        +-----------+
#   |  license        |  scratch  |
#   +-----------------+-----------+
function make_pane_json_document_example()
    left = PaneGroup(PaneTab[
        PaneTab("data.json", make_json_document_example()),
        PaneTab("read me", PrimitiveString("A tab holds a document, and any document will do.\n\n" *
                                           "The first tab of this group holds the json example.\n" *
                                           "Ctrl+Tab traverses the tabs, Ctrl+T opens one.")),
        PaneTab("license", PrimitiveString("Public domain."))])
    notes = PaneGroup(PaneTab[PaneTab("notes", PrimitiveString("Drag a tab onto another group to move it."))])
    scratch = PaneGroup(PaneTab[PaneTab("scratch", PrimitiveString(""))])
    right = PaneSplit(:horizontal, [notes, scratch])
    tree = PaneTree(PaneSplit(:vertical, [left, right]; weights = [0.65, 0.35]))
    # Start with the focus on the json tab, so the layout opens showing it.
    set_selection!(tree, pane_tab_reference(tree, left, 1))
    tree
end

# A bare `WidgetTabbedPane` **as the document**, holding one domain document per
# tab. The pane tree above projects *to* a tabbed pane; this one **is** one, which
# is the smallest document that shows what a tab group does with a selection.
#
#   +--------------------------+
#   | data.json | data.xml     |
#   +--------------------------+
#   | { "name": "Alice", … }   |
#   +--------------------------+
function make_widget_tabs_document_example()
    WidgetTabbedPane([("data.json", make_json_document_example()),
                      ("data.xml",  make_xml_document_example())];
                     border = Inset(4, 4, 4, 4))
end
