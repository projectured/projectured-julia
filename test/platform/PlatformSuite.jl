"""
    test_platform_layering()

The static layered-architecture guard of the platform (see
`ProjecturedKernelTest.check_layering`): the topological include order of its
entry file, and the file inventory of `source/platform/`. The rule of the edges
between its slices is `test_platform_slice_edges`.
"""
function test_platform_layering()
    for pkg in _SOURCES
        pkg === ProjecturedKernel && continue
        main = get_package_source_root(pkg)
        # The modules that the entry file binds with a loop, which the guard can not
        # read from the file: those of the packages below.
        aliases = Set{Symbol}(n for n in names(pkg; all = true)
                              if isdefined(pkg, n) && getfield(pkg, n) isa Module &&
                                 getfield(pkg, n) !== pkg &&
                                 parentmodule(getfield(pkg, n)) !== pkg)
        check_layering(main, pathof(pkg); name = String(nameof(pkg)), extra_aliases = aliases)
    end
end

"""
    PLATFORM_SLICE_EDGES

The slices of the platform, each with the slices of the platform that it may
use; each may also use the kernel. The table is the rule of the edges inside the
platform, which the `Project.toml` of each package no longer states once the
slices share one package. A new edge is a change of this table.
"""
const PLATFORM_SLICE_EDGES = Dict{String, Vector{String}}(
    "collection" => [],
    "component" => [],
    "serialization" => [],
    "style" => ["serialization", "settings"],
    "appearance" => ["graphics", "layout", "natural", "primitive", "projection", "screen", "style",
                     "syntax", "text", "tooltip", "widget"],
    "settingsmanaging" => ["collection", "graphics", "layout", "natural", "primitive", "projection",
                           "screen", "settings", "style", "widget"],
    "domain" => [],
    "settings" => [],
    "focus" => ["collection"],
    "plot" => ["style"],
    "primitive" => [],
    "projection" => ["collection", "focus", "primitive"],
    "versioning" => ["collection", "domain", "primitive"],
    "dragging" => ["collection", "projection"],
    "graphics" => ["collection", "projection", "style"],
    "layout" => ["collection", "focus", "graphics", "projection", "style"],
    "screen" => ["collection", "dragtracking", "gesturetracking", "graphics", "primitive",
                 "projection", "settings"],
    "text" => ["collection", "domain", "graphics", "primitive", "projection", "style"],
    "clipboard" => ["collection", "domain", "focus", "primitive", "projection",
                    "serialization", "text"],
    "tooltip" => ["graphics", "screen", "style"],
    "widget" => ["collection", "domain", "focus", "graphics", "layout", "primitive",
                 "projection", "screen", "serialization", "style", "text", "tooltip"],
    "natural" => ["collection", "domain", "graphics", "layout", "primitive", "projection",
                  "style", "text", "tooltip", "widget"],
    "pane" => ["clipboard", "collection", "domain", "dragging", "focus", "graphics",
               "layout", "primitive", "projection", "screen", "serialization", "style",
               "widget"],
    "reflection" => ["collection", "widget"],
    "inspector" => ["domain", "natural", "projection", "screen", "serialization", "style",
                    "text"],
    "syntax" => ["collection", "domain", "natural", "primitive", "projection", "style",
                 "text"],
    "fault" => ["collection", "domain", "focus", "graphics", "natural", "projection",
                "serialization", "settings", "style", "syntax", "text", "tooltip",
                "widget"],
    "fileformat" => ["collection", "domain", "layout", "natural", "primitive",
                     "projection", "serialization", "style", "syntax", "text", "widget"],
    "filesystem" => ["collection", "domain", "fileformat", "focus", "graphics", "natural",
                     "pane", "primitive", "projection", "serialization", "settingsmanaging",
                     "style", "syntax", "text", "undo", "widget"],
    "gesturehelp" => ["collection", "graphics", "projection", "screen", "style", "syntax",
                      "text"],
    "gesturelog" => ["collection", "domain", "graphics", "natural", "projection",
                     "serialization", "style", "syntax", "text"],
    "assistant" => ["collection", "conversation", "domain", "layout", "natural",
                    "primitive", "projection", "serialization", "style", "text",
                    "widget"],
    "conversation" => ["collection", "domain", "focus", "layout", "natural", "primitive",
                       "projection", "serialization", "style", "text", "widget"],
    "shell" => ["appearance", "assistant", "clipboard", "conversation", "domain", "fault", "fileformat",
                "filesystem", "focus", "gesturehelp", "gesturelog", "graphics", "help", "inspector",
                "log", "natural", "pane", "projection", "screen", "settings", "settingsmanaging",
                "statistics", "style", "syntax", "text", "tooltip", "widget"],
    "help" => ["domain", "natural", "serialization", "style", "syntax", "text"],
    "log" => ["collection", "domain", "natural", "serialization", "style", "syntax",
              "text"],
    "mcplog" => ["collection", "domain", "layout", "natural", "primitive", "projection",
                 "serialization", "shell", "style", "widget"],
    "task" => ["collection", "domain", "focus", "graphics", "layout", "natural", "pane",
               "primitive", "projection", "style", "widget"],
    "statistics" => ["collection", "domain", "layout", "natural", "projection",
                     "serialization", "style", "widget"],
    "undo" => ["collection", "graphics", "projection", "settings", "style", "syntax",
               "text"],
    "navigator" => ["collection", "filesystem", "layout", "natural", "pane", "primitive", "projection", "screen",
                    "serialization", "style", "syntax", "text", "widget"],
    "gesturetracking" => ["settings"],
    "dragtracking" => [],
    "display" => ["natural", "screen", "style", "widget"],
    "essentials" => ["display", "natural", "style"],
    "application" => ["assistant", "collection", "conversation", "domain", "fault",
                      "fileformat", "filesystem", "graphics", "natural", "pane", "primitive",
                      "projection", "screen", "serialization", "settings", "shell",
                      "style", "text", "tooltip", "undo", "widget"],
)

"""
    test_platform_slice_edges()

Each slice of the platform uses only the slices that `PLATFORM_SLICE_EDGES`
allows it, and the kernel; it uses no module of a domain, a backend or an
adapter.
"""
function test_platform_slice_edges()
    # The files of the loaded packages, so the test reads the same files in this
    # repository and in an installed package.
    check_slice_edges(get_package_source_root(ProjecturedPlatform),
                      [pathof(ProjecturedPlatform)], PLATFORM_SLICE_EDGES; name = "platform",
                      below_files = [pathof(ProjecturedKernel)])
end

"""
    test_platform()

Run the whole suite of the platform: its layering guard and the table of the
edges between its slices, every unit test, the printer walk over its own
examples, and the suites of the fault, file system, conversation, help, shell,
undo and display slices.
"""
function test_platform()
    @testset "ProjecturedPlatform" begin
        test_platform_layering()
        test_platform_slice_edges()
        test_platform_examples()
        test_collection()
        test_table_interface()
        test_mouse_target_field()
        test_mouse_target_chain()
        test_document_walk()
        test_bounded_sync()
        test_document_reflection()
        test_copying_projection()
        test_focusing()
        test_reversing()
        test_filtering()
        test_searching()
        test_sorting()
        test_switching()
        test_identity()
        test_window_input_unwrapping()
        test_versioning_to_any()
        test_text_file()
        test_marker_language()
        test_pred_file()
        # documents
        test_point_reference()
        test_syntax()
        test_text()
        test_graphics()
        test_pointer_shape()
        test_affine_transform()
        test_font_metrics()
        test_text_measure()
        test_line_spacing()
        test_theme()
        test_color_theme()
        test_font_fallback()
        test_font_face()
        test_graphics_layout()
        test_layout_allocator()
        test_layout_constraint_helpers()
        test_primitive()
        test_primitive_type_in()
        test_pane_surgery()
        test_pane_geometry()
        test_document_duplicate()
        # text / graphics projections
        test_projection_template_hygiene()
        test_projection_template_fixed_children()
        test_projection_template_conditional_children()
        test_projection_template_gesture_descent()
        test_projection_template_reconciled_children()
        test_projection_template_value_field()
        test_projection_template_wirings()
        test_plot_geometry()
        test_syntax_to_text()
        test_introduced_part_round_trip()
        test_every_kind_of_path()
        test_output_paths()
        test_primitive_to_text()
        test_text_to_graphics()
        test_text_line_model()
        test_inline_image_caret()
        test_word_wrapping()
        test_text_filtering()
        test_text_first_line()
        test_text_line_numbering()
        test_text_highlighting()
        test_selection_inverting()
        # widget projections
        test_object_to_widget()
        test_object_field_to_widget()
        test_object_field_to_syntax()
        test_reflection_to_widget()
        test_projection_configuring()
        test_cell_table_to_widget_table()
        test_widget_text_editing()
        test_widget_button_behavior()
        test_widget_button_labels()
        test_widget_slider_drag()
        test_widget_scroll_bar()
        test_widget_live_values()
        test_widget_progress()
        test_size_range_child_rule()
        test_size_range_cross_axis()
        test_size_range_composite()
        test_size_range_one_child()
        test_size_range_main_axis()
        test_widget_card_fold()
        test_widget_selection()
        test_selection_walking()
        test_gesture_tracking()
        test_mouse_target_move()
        test_widget_gestures()
        test_widget_select_dropdown()
        test_widget_menu()
        test_widget_context_menu()
        test_widget_dialog()
        test_widget_action()
        test_widget_icon()
        test_widget_colors()
        test_widget_scales()
        test_builder_appearance()
        test_text_and_syntax_themes()
        test_tool_themes()
        test_help_themes()
        test_appearance_wrapper()
        test_appearance_tab()
        test_appearance_file()
        test_settings()
        test_settings_wrapper()
        test_settings_tab()
        test_navigator()
        test_widget_tree()
        test_widget_toolbar()
        test_widget_table()
        test_widget_table_cell_policy()
        test_widget_table_cell_editing()
        test_widget_table_column_align()
        test_widget_table_fills_offer()
        test_widget_table_content_floor()
        test_shell_offers_only_its_size()
        test_widget_shell_layout()
        test_widget_shell_pointer()
        test_scroll_pane_axis_size()
        test_widget_table_list()
        test_widget_table_header_levels()
        test_layout_list()
        test_widget_table_list_header_floor()
        test_widget_table_cell_order()
        test_widget_table_part_selection()
        test_frozen_table_headers()
        test_widget_text_wrap()
        test_widget_tab_strip()
        test_widget_tab_label()
        test_mcp_log_pane()
        test_task_result()
        test_task_execution()
        test_task_group()
        test_build_step()
        test_task_document()
        test_task_views()
        test_task_group_verbs()
        test_widget_split_pane()
        test_pane_to_widget()
        test_pane_reader()
        test_pane_gestures()
        test_pane_drag()
        test_pane_rename()
        test_pane_construct()
        test_interface_api()
        test_widget_transform_pane()
        test_layout_closeout()
        test_grid_span()
        test_widget_forms()
        test_anchor_point()
        test_anchored_layout()
        test_scroll_layout()
        # interaction decorators
        test_clipboard()
        test_tooltip()
        test_window_fit()
        test_window_wrapper()
        test_document_composition()
        test_tabs_wrapper()
        test_split_pane_drag()
        test_part_pointer_shape()
        test_routed_gesture()
        test_layout_point()
        test_widget_point()
        test_column_chooser()
        test_widget_swatch()
        test_baseline_alignment()
        test_widget_forward()
        test_widget_round_trip()
        test_scroll_pane_hover()
        test_scroll_pane_bar()
        test_widget_table_bar()
        test_widget_rows_scroll()
        test_widget_popup_example()
        # generic drivers over visual examples
        test_collapse_roundtrip()


        # the suites of the slices that had a test package of their own
        test_fault()
        test_filesystem()
        test_conversation()
        test_help()
        test_shell()
        test_undo()
        test_display()
    end
end

"""
    test_platform_examples()

Walk the printer over every platform example (`platform_examples`) — one
`@test` per forced reactive cell, through the generic `test_printer` driver.
"""
function test_platform_examples()
    @testset "PlatformExamples" begin
        for ex in platform_examples
            @testset "$(ex.name)" begin
                test_printer(ex)
            end
        end
    end
end

export test_platform, test_platform_layering, test_platform_examples
export PLATFORM_SLICE_EDGES, test_platform_slice_edges
export test_bounded_sync, test_document_reflection
export test_identity
export test_collection, test_table_interface, test_mouse_target_field, test_mouse_target_chain, test_copying_projection, test_focusing, test_reversing, test_filtering, test_searching, test_sorting
export test_switching, test_window_input_unwrapping
export test_versioning_to_any
export test_text_file, test_marker_language, test_pred_file
export _text_leaf_length, _walk_document, collect_position_selections, collect_tree_selections
export test_point_reference
export test_syntax, test_text, test_graphics, test_pointer_shape, test_affine_transform, test_font_metrics, test_text_measure, test_line_spacing, test_theme, test_font_fallback, test_font_face,
       test_graphics_layout, test_layout_allocator, test_layout_constraint_helpers,
       test_primitive, test_primitive_type_in, test_pane_surgery, test_pane_geometry, test_pane_to_widget,
       test_pane_reader, test_pane_gestures, test_pane_drag,
       test_pane_rename, test_pane_construct, test_interface_api
export test_projection_template_hygiene, test_projection_template_fixed_children
export test_projection_template_conditional_children,
       test_projection_template_gesture_descent,
       test_projection_template_reconciled_children, test_projection_template_value_field,
       test_projection_template_wirings
export test_plot_geometry,
       test_syntax_to_text, test_introduced_part_round_trip, test_every_kind_of_path, test_output_paths, test_primitive_to_text, test_text_to_graphics, test_text_line_model, test_inline_image_caret,
       test_word_wrapping, test_text_filtering, test_text_first_line, test_text_line_numbering,
       test_text_highlighting, test_selection_inverting
export test_reflection_to_widget
export test_object_field_to_widget, test_object_field_to_syntax
export test_object_to_widget, test_projection_configuring,
       test_widget_text_editing, test_widget_button_behavior, test_widget_button_labels, test_widget_slider_drag, test_widget_scroll_bar, test_widget_live_values, test_widget_progress, test_size_range_child_rule, test_size_range_cross_axis, test_size_range_composite, test_size_range_one_child, test_size_range_main_axis, test_widget_card_fold, test_widget_selection, test_selection_walking, test_gesture_tracking, test_mouse_target_move, test_widget_gestures,
       test_widget_select_dropdown, test_widget_menu, test_widget_context_menu,
       test_widget_dialog, test_widget_action, test_widget_icon, test_widget_colors, test_widget_scales, test_builder_appearance, test_text_and_syntax_themes, test_tool_themes, test_help_themes, collect_font_sizes, draw_font_sizes, test_appearance_wrapper, test_appearance_tab, test_appearance_file, test_settings, test_settings_wrapper, test_settings_tab, test_navigator_document, test_navigator_gestures, test_open_page_operation, test_navigator, test_navigator_visits, test_navigator_choices, test_navigator_address, test_navigator_to_widget, test_widget_tree,
       test_widget_toolbar, test_widget_table, test_widget_table_cell_policy, test_widget_table_cell_editing, test_widget_table_column_align, test_widget_table_fills_offer, test_widget_table_content_floor, test_shell_offers_only_its_size, test_widget_shell_layout, test_widget_shell_pointer, test_scroll_pane_axis_size, test_widget_table_list, test_widget_table_list_header_floor, test_widget_table_cell_order, test_widget_table_part_selection, test_widget_table_header_levels, test_layout_list, test_frozen_table_headers, test_widget_text_wrap, test_widget_tab_strip, test_widget_tab_label, test_mcp_log_pane, test_task_result, test_task_execution, test_task_group, test_build_step, test_task_document, test_task_views, test_task_group_scale, test_task_group_verbs, test_widget_split_pane, test_widget_transform_pane,
       test_layout_closeout, test_grid_span, test_widget_forms, test_anchor_point, test_anchored_layout,
       test_scroll_layout
export test_clipboard, test_tooltip, test_window_fit, test_window_wrapper, test_document_composition,
       test_tabs_wrapper, test_split_pane_drag, test_part_pointer_shape, test_routed_gesture,
       test_layout_point, test_widget_point, test_column_chooser, test_widget_swatch, test_baseline_alignment,
       test_widget_forward,
       test_widget_round_trip,
       test_scroll_pane_hover, test_scroll_pane_bar, test_widget_table_bar,
       test_widget_rows_scroll,
       test_widget_popup_example, test_collapse_roundtrip
export POSITION_NAVIGATION_KEYS, POSITION_SEED_GESTURE, TREE_NAVIGATION_KEYS, TREE_SEED_GESTURE,
       explore_position_selections, test_position_navigation,
       explore_tree_selections, test_tree_navigation
export walk_typein, test_typein
export test_click_roundtrip, test_text_navigation_invariants,
       _find_text_iomap, _find_cursor_rect, _pipeline_measure, _segment_x_at,
       _path_contains_projection_reference
