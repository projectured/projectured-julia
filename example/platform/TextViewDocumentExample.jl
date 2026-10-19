# One text in two views at three places. The left place and the right place show
# view A, so they share its caret; the middle place shows view B, with a caret of
# its own. The text holds no caret.
#
#   +--------------+--------------+--------------+
#   |  view A      |  view B      |  view A      |
#   +--------------+--------------+--------------+
function make_text_view_document_example()
    style = StyleText(StyleFont("Ubuntu Mono", 20), color_default)
    content = make_text_block("One text, two views.\n" *
                              "The left and the right place\n" *
                              "show view A: one caret.\n" *
                              "The middle place shows view B,\n" *
                              "with a caret of its own.", style)
    view_a = TextView(content)
    view_b = TextView(content)
    tree = PaneTree(PaneSplit(:vertical, [PaneGroup([PaneTab("view A", view_a)]),
                                          PaneGroup([PaneTab("view B", view_b)]),
                                          PaneGroup([PaneTab("view A again", view_a)])]))
    # The caret of view B first, so it stays when the focus goes to view A.
    replace_selection!(tree, concat_references(@reference(tree, root.elements[2].tabs[1].content),
                                               make_flat_caret_reference(4)))
    replace_selection!(tree, concat_references(@reference(tree, root.elements[1].tabs[1].content),
                                               make_flat_caret_reference(9)))
    tree
end
