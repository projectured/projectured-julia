"""
    ProjecturedPlatformExample

The visual tier of the example-package DAG that parallels the main DAG
(kernel ← visual ← domain ← umbrella; see
plan/done/example-package-split.md). It hosts:

- the visual-tier `Example` instances and their document/projection factories:
  syntax and text documents, the widget gallery, the layout examples, the
  collection views (reversing/filtering/searching/sorting), the text
  decorators (line numbering, word wrapping, filtering, highlighting), the
  object reflections (ObjectToSyntax / ObjectToWidget), and the rotating
  vector animation;
- the visual half of the example harness: `print_example` (console rendering
  of the projected output) and `write_example_pdf` (the dependency-free Pdf
  backend; text is measured from the font files, with no SDL).

The tier's registry slice is `platform_examples`; the global interleaved
`examples` registry lives in the `ProjecturedExample` umbrella.
"""
module ProjecturedPlatformExample

import ProjecturedKernel
import ProjecturedPlatform
import ProjecturedConsole
import ProjecturedPDF
using ProjecturedKernelExample
import ProjecturedKernelExample: Example

# The example factories were written against the flat `Projectured` namespace.
# Build the same flat namespace over this package's three main-package sources —
# one mechanical pass, exactly like the `Projectured` umbrella's re-export
# loop (but without re-exporting): alias every submodule and `using` its
# exported names into scope.
const _SOURCES = (ProjecturedKernel, ProjecturedPlatform, ProjecturedConsole, ProjecturedPDF)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../example/platform/GestureMapDocumentExample.jl")
include("../../../example/platform/SyntaxDocumentExample.jl")
include("../../../example/platform/TextDocumentExample.jl")
include("../../../example/platform/TextLayoutDocumentExample.jl")
include("../../../example/platform/ObjectDocumentExample.jl")
include("../../../example/platform/ObjectToWidgetDocumentExample.jl")
include("../../../example/platform/ObjectFieldDocumentExample.jl")
include("../../../example/platform/LineNumberingDocumentExample.jl")
include("../../../example/platform/TextToStringDocumentExample.jl")
include("../../../example/platform/WordWrappingDocumentExample.jl")
include("../../../example/platform/TextFilteringDocumentExample.jl")
include("../../../example/platform/TextHighlightingDocumentExample.jl")
include("../../../example/platform/WidgetDocumentExample.jl")
include("../../../example/platform/LayoutDocumentExample.jl")
include("../../../example/platform/CollectionDocumentExample.jl")
include("../../../example/platform/PrimitiveDocumentExample.jl")
include("../../../example/platform/AppearanceDocumentExample.jl")
include("../../../example/platform/LazyDocumentExample.jl")
include("../../../example/platform/PaneDocumentExample.jl")
include("../../../example/platform/RotatingVectorDocumentExample.jl")

include("../../../example/platform/SyntaxProjectionExample.jl")
include("../../../example/platform/TextProjectionExample.jl")
include("../../../example/platform/TextLayoutProjectionExample.jl")
include("../../../example/platform/ObjectProjectionExample.jl")
include("../../../example/platform/ObjectToWidgetProjectionExample.jl")
include("../../../example/platform/ObjectFieldProjectionExample.jl")
include("../../../example/platform/LineNumberingProjectionExample.jl")
include("../../../example/platform/TextToStringProjectionExample.jl")
include("../../../example/platform/WordWrappingProjectionExample.jl")
include("../../../example/platform/TextFilteringProjectionExample.jl")
include("../../../example/platform/TextHighlightingProjectionExample.jl")
include("../../../example/platform/WidgetProjectionExample.jl")
include("../../../example/platform/LayoutProjectionExample.jl")
include("../../../example/platform/CollectionProjectionExample.jl")
include("../../../example/platform/PrimitiveProjectionExample.jl")
include("../../../example/platform/LazyProjectionExample.jl")
include("../../../example/platform/PaneProjectionExample.jl")
include("../../../example/platform/ShowBesideExample.jl")
include("../../../example/platform/ReversingProjectionExample.jl")
include("../../../example/platform/FilteringProjectionExample.jl")
include("../../../example/platform/SearchingProjectionExample.jl")
include("../../../example/platform/SortingProjectionExample.jl")
# The table projection: NaturalToGraphics with the sans chrome font. It names no
# domain, and both the graph example and the table example need it.
include("../../../example/platform/TableProjectionExample.jl")

include("../../../example/platform/PlatformExamples.jl")
include("../../../example/platform/Harness.jl")

export Address, AppSettings, FormServer, Person, SearchSettings, WindowSettings, collection_example
export constraint_layout_example, filtering_example, force_next, force_prev, integers_from
export integers_from_bidirectional, layout_example, lazy_bidirectional_example
export make_primes_around, is_prime_number, make_lazy_list_view, show_lazy_list!
export show_beside!
export lazy_bidirectional_node, lazy_example, lazy_filter, lazy_filter_bidirectional
export lazy_node, line_numbering_example, make_anchored_layout_document_example
export make_clipboard_collection_document_example, make_clipboard_slice_document_example
export make_collection_document_example, make_cell_table_document_example
export make_list_node_document_example, make_collection_projection_example
export make_constraint_layout_document_example, make_constraint_layout_projection_example
export make_filtering_projection_example, make_flow_layout_document_example
export make_graphics_canvas_document_example, make_grid_layout_document_example
export make_horizontal_layout_document_example, make_layout_constraint_document_example
export make_layout_document_example, make_layout_projection_example
export make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example
export make_lazy_document_example, make_lazy_projection_example
export make_line_numbering_document_example, make_line_numbering_projection_example
export make_nested_object_to_widget_document_example, make_object_document_example
export make_object_projection_example, make_object_to_widget_document_example
export make_object_to_widget_projection_example, make_plain_text_document_example
export make_object_field_document_example, make_object_field_form_document_example
export make_object_field_form_projection_example, make_object_field_syntax_projection_example
export make_plain_text_projection_example, make_primitive_string_document_example
export make_primitive_string_projection_example, make_reference_inspector_document_example
export make_reversing_projection_example, make_rotating_vector_document
export make_screen_document_document_example, make_searching_projection_example
export make_sorting_projection_example, make_stack_layout_document_example
export make_syntax_document_example, make_syntax_leaf_document_example
export make_syntax_projection_example, make_text_document_example
export make_text_filtering_document_example, make_text_filtering_projection_example
export make_text_highlighting_document_example, make_text_highlighting_projection_example
export make_text_line_atom_document_example, make_text_newline_atom_document_example
export make_text_projection_example, make_text_string_atom_document_example
export make_text_layout_projection_example, make_text_baseline_document_example
export make_text_line_height_document_example, make_text_kerning_document_example
export make_text_selection_document_example, make_text_spacing_document_example
export text_baseline_example, text_line_height_example, text_kerning_example, text_selection_example
export text_spacing_single_example, text_spacing_one_and_a_half_example, text_spacing_double_example
export text_spacing_exactly_example, text_spacing_at_least_example
export text_layout_examples, text_spacing_examples
export make_text_to_string_document_example, make_text_to_string_projection_example
export make_text_with_image_example, make_tooltip_source_document_example
export make_vertical_layout_document_example, make_widget_accordion_document_example
export make_widget_alert_atom_document_example, make_widget_alert_document_example
export make_widget_avatar_document_example, make_widget_badge_atom_document_example
export make_widget_badge_document_example, make_widget_button_action_document_example
export make_widget_button_document_example, make_widget_button_image_document_example
export make_widget_card_document_example, make_widget_collapsible_card_document_example, make_widget_checkbox_document_example
export make_widget_composite_document_example, make_widget_context_menu_document_example
export make_widget_dialog_document_example, make_widget_disabled_document_example
export make_widget_document_example, make_widget_focus_document_example
export make_widget_insertion_document_example, make_widget_label_document_example
export make_widget_list_document_example, make_widget_menu_document_example
export make_widget_menu_item_document_example, make_widget_option_document_example
export make_widget_popup_document_example, make_widget_popup_projection_example
export make_widget_progress_document_example, make_widget_projection_example
export make_gesture_map_document_example
export make_table_projection_example, make_math_table_projection_example
export make_pane_document_example, make_empty_pane_document_example, make_pane_projection_example
export make_widget_radio_group_document_example, make_widget_scroll_bar_document_example
export make_widget_scroll_pane_document_example, make_widget_select_document_example
export make_widget_separator_atom_document_example, make_widget_separator_document_example
export make_widget_shell_document_example, make_widget_skeleton_atom_document_example
export make_widget_skeleton_document_example, make_widget_slider_document_example
export make_widget_spin_box_document_example, make_widget_split_pane_document_example
export make_widget_status_bar_document_example, make_widget_swatch_atom_document_example
export make_widget_swatch_document_example, make_widget_switch_atom_document_example
export make_widget_switch_document_example, make_widget_tabbed_pane_atom_document_example
export make_widget_tabbed_pane_document_example, make_widget_table_document_example
export make_widget_table_offered_document_example, make_widget_table_frozen_document_example
export make_widget_text_document_example, make_widget_text_projection_example
export make_widget_textarea_document_example, make_widget_title_pane_document_example
export make_widget_toggle_atom_document_example, make_widget_toggle_document_example
export make_widget_toggle_group_document_example, make_widget_toolbar_document_example
export make_widget_toolbar_item_document_example
export make_widget_tooltip_document_example, make_widget_transform_pane_document_example
export make_widget_tree_document_example, make_window_document_document_example
export make_word_wrapping_document_example, make_word_wrapping_projection_example
export nested_object_to_widget_example, object_example, object_to_widget_example
export object_field_form_example, object_field_syntax_example
export plain_text_example, print_example, reversing_example, rotating_vector_example
export searching_example, sieve, sieve_bidirectional, sieve_prev, sorting_example
export syntax_example, text_example, text_filtering_example, text_highlighting_example
export text_with_image_example, widget_accordion_example, widget_alert_example
export widget_avatar_example, widget_badge_example, widget_button_action_example
export widget_button_example, widget_button_image_example, widget_card_example, widget_collapsible_card_example
export widget_checkbox_example, widget_composite_example, widget_disabled_example
export widget_example, widget_focus_example, widget_label_example, widget_menu_example
export widget_menu_item_example, widget_popup_example, widget_progress_example
export widget_radio_group_example, widget_scroll_bar_example, widget_scroll_pane_example
export widget_offered_example, make_widget_offered_document_example
export widget_select_example, widget_separator_example, widget_shell_example
export widget_skeleton_example, widget_slider_example, widget_split_pane_example
export widget_swatch_example, widget_switch_example, widget_tabbed_pane_example, widget_table_example
export widget_table_offered_example, widget_table_frozen_example
export pane_example, empty_pane_example
export widget_text_example, widget_textarea_example, widget_title_pane_example
export widget_toggle_example, widget_toggle_group_example, widget_toolbar_example
export widget_toolbar_item_example
export widget_tooltip_example, widget_transform_pane_example, widget_tree_example
export word_wrapping_example, write_example_pdf
export Example, AtomicDocument, platform_examples, platform_atomic_documents
export print_example, write_example_pdf


# The examples of the slices that had a package of their own, each in its own
# namespace, so that the helpers of two of them do not collide. This package
# exports what each exports.

module FileSystemExamples

import ProjecturedPlatform
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedConsole
using ProjecturedKernelExample
using ..ProjecturedPlatformExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPDF)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../example/platform/filesystem/FileSystemDocumentExample.jl")
include("../../../example/platform/filesystem/FileSystemProjectionExample.jl")
include("../../../example/platform/filesystem/NavigatorDocumentExample.jl")
include("../../../example/platform/filesystem/NavigatorProjectionExample.jl")

export filesystem_example_root
export make_filesystem_document_example, make_filesystem_file_document_example, make_filesystem_directory_document_example
export make_filesystem_projection_example, make_filesystem_widget_projection_example
export make_navigator_document_example, make_navigator_projection_example
export make_workspace_folder_document_example, make_workspace_document_example
end # module FileSystemExamples

for _part in (FileSystemExamples,)
    Core.eval(@__MODULE__, Expr(:using, Expr(:., :., nameof(_part))))
    for _n in names(_part)
        _n === nameof(_part) || Core.eval(@__MODULE__, Expr(:export, _n))
    end
end

end # module ProjecturedPlatformExample
