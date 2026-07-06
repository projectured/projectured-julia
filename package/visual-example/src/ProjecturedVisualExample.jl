"""
    ProjecturedVisualExample

The visual tier of the example-package DAG that parallels the runtime DAG
(kernel ← visual ← domain ← umbrella; see
plan/pending/example-package-split.md). It hosts:

- the visual-tier `Example` instances and their document/projection factories:
  syntax and text documents, the widget gallery, the layout examples, the
  collection views (reversing/filtering/searching/sorting), the text
  decorators (line numbering, word wrapping, filtering, highlighting), the
  object reflections (ObjectToSyntax / ObjectToWidget), and the rotating
  vector animation;
- the visual half of the example harness: `print_example` (console rendering
  of the projected output) and `write_example_pdf` (the dependency-free Pdf
  backend; SDL font metrics are reached through the `make_backend` seam).

The tier's registry slice is `visual_examples`; the global interleaved
`examples` registry lives in the `ProjecturedExample` umbrella.
"""
module ProjecturedVisualExample

import ProjecturedKernel
import ProjecturedBase
import ProjecturedVisual
using ProjecturedKernelExample
import ProjecturedKernelExample: Example

# The example factories were written against the flat `Projectured` namespace.
# Build the same flat namespace over this package's three runtime sources —
# one mechanical pass, exactly like the `Projectured` umbrella's re-export
# loop (but without re-exporting): alias every submodule and `using` its
# exported names into scope.
for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual)
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("document/Syntax.jl")
include("document/Text.jl")
include("document/Object.jl")
include("document/ObjectToWidget.jl")
include("document/LineNumbering.jl")
include("document/TextToString.jl")
include("document/WordWrapping.jl")
include("document/TextFiltering.jl")
include("document/TextHighlighting.jl")
include("document/Widget.jl")
include("document/Layout.jl")
include("document/Collection.jl")
include("document/Primitive.jl")
include("document/Lazy.jl")
include("document/RotatingVector.jl")

include("projection/Syntax.jl")
include("projection/Text.jl")
include("projection/Object.jl")
include("projection/ObjectToWidget.jl")
include("projection/LineNumbering.jl")
include("projection/TextToString.jl")
include("projection/WordWrapping.jl")
include("projection/TextFiltering.jl")
include("projection/TextHighlighting.jl")
include("projection/Widget.jl")
include("projection/Layout.jl")
include("projection/Collection.jl")
include("projection/Primitive.jl")
include("projection/Lazy.jl")
include("projection/Reversing.jl")
include("projection/Filtering.jl")
include("projection/Searching.jl")
include("projection/Sorting.jl")

include("Examples.jl")
include("Harness.jl")

export Address, AppSettings, Person, SearchSettings, WindowSettings, collection_example
export constraint_layout_example, filtering_example, force_next, force_prev, integers_from
export integers_from_bidirectional, layout_example, lazy_bidirectional_example
export lazy_bidirectional_node, lazy_example, lazy_filter, lazy_filter_bidirectional, lazy_node
export line_numbering_example, make_collection_document_example
export make_collection_projection_example, make_constraint_layout_document_example
export make_constraint_layout_projection_example, make_filtering_projection_example
export make_layout_document_example, make_layout_projection_example
export make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example
export make_lazy_document_example, make_lazy_projection_example
export make_line_numbering_document_example, make_line_numbering_projection_example
export make_nested_object_to_widget_document_example, make_object_document_example
export make_object_projection_example, make_object_to_widget_document_example
export make_object_to_widget_projection_example, make_plain_text_document_example
export make_plain_text_projection_example, make_primitive_string_document_example
export make_primitive_string_projection_example, make_reversing_projection_example
export make_rotating_vector_document, make_searching_projection_example
export make_sorting_projection_example, make_syntax_document_example
export make_syntax_projection_example, make_text_document_example
export make_text_filtering_document_example, make_text_filtering_projection_example
export make_text_highlighting_document_example, make_text_highlighting_projection_example
export make_text_projection_example, make_text_to_string_document_example
export make_text_to_string_projection_example, make_text_with_image_example
export make_widget_accordion_document_example, make_widget_alert_document_example
export make_widget_avatar_document_example, make_widget_badge_document_example
export make_widget_button_action_document_example, make_widget_button_document_example
export make_widget_button_image_document_example, make_widget_card_document_example
export make_widget_checkbox_document_example, make_widget_composite_document_example
export make_widget_disabled_document_example, make_widget_document_example
export make_widget_focus_document_example, make_widget_label_document_example
export make_widget_menu_document_example, make_widget_menu_item_document_example
export make_widget_popup_document_example, make_widget_popup_projection_example
export make_widget_progress_document_example, make_widget_projection_example
export make_widget_radio_group_document_example, make_widget_scroll_bar_document_example
export make_widget_scroll_pane_document_example, make_widget_select_document_example
export make_widget_separator_document_example, make_widget_shell_document_example
export make_widget_skeleton_document_example, make_widget_slider_document_example
export make_widget_split_pane_document_example, make_widget_switch_document_example
export make_widget_tabbed_pane_document_example, make_widget_table_document_example
export make_widget_text_document_example, make_widget_text_projection_example
export make_widget_textarea_document_example, make_widget_title_pane_document_example
export make_widget_toggle_document_example, make_widget_toggle_group_document_example
export make_widget_toolbar_document_example, make_widget_tooltip_document_example
export make_widget_transform_pane_document_example, make_widget_tree_document_example
export make_word_wrapping_document_example, make_word_wrapping_projection_example
export nested_object_to_widget_example, object_example, object_to_widget_example
export plain_text_example, primitive_string_example, print_example, reversing_example
export rotating_vector_example, searching_example, sieve, sieve_bidirectional, sieve_prev
export sorting_example, syntax_example, text_example, text_filtering_example
export text_highlighting_example, text_with_image_example, widget_accordion_example
export widget_alert_example, widget_avatar_example, widget_badge_example
export widget_button_action_example, widget_button_example, widget_button_image_example
export widget_card_example, widget_checkbox_example, widget_composite_example
export widget_disabled_example, widget_example, widget_focus_example, widget_label_example
export widget_menu_example, widget_menu_item_example, widget_popup_example
export widget_progress_example, widget_radio_group_example, widget_scroll_bar_example
export widget_scroll_pane_example, widget_select_example, widget_separator_example
export widget_shell_example, widget_skeleton_example, widget_slider_example
export widget_split_pane_example, widget_switch_example, widget_tabbed_pane_example
export widget_table_example, widget_text_example, widget_textarea_example
export widget_title_pane_example, widget_toggle_example, widget_toggle_group_example
export widget_toolbar_example, widget_tooltip_example, widget_transform_pane_example
export widget_tree_example, word_wrapping_example, write_example_pdf
export Example, visual_examples
export print_example, write_example_pdf

end # module ProjecturedVisualExample
