# One text in two views at three places of a vertical layout. The first and the
# third place show view A, so they share its caret; the second place shows view B,
# with a caret of its own. The text holds no caret.
#
#   +----------------------+
#   |  view A              |
#   +----------------------+
#   |  view B              |
#   +----------------------+
#   |  view A              |
#   +----------------------+
function make_text_view_document_example()
    style = StyleText(StyleFont("Ubuntu Mono", 20), color_default)
    content = make_text_block("One text, two views.\n" *
                              "The first and the third place\n" *
                              "show view A: one caret.\n" *
                              "The second place shows view B,\n" *
                              "with a caret of its own.", style)
    view_a = TextView(content)
    view_b = TextView(content)
    layout = VerticalLayout([view_a, view_b, view_a]; gap = 20)
    # The caret of view B first, so it stays when the focus goes to view A.
    replace_selection!(layout, concat_references(@reference(layout, children[2]), make_flat_caret_reference(4)))
    replace_selection!(layout, concat_references(@reference(layout, children[1]), make_flat_caret_reference(9)))
    layout
end
