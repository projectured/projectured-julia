# Every rename of the functions that do not start with a verb

> **Kind:** plan · **Status:** pending · **Stands on:** [naming-rule-violations.md](naming-rule-violations.md) §14.9

374 names, grouped by the file that defines them. A dash means no change.

**source/assistant/AssistantTurn.jl**

| old | kind | new |
| --- | --- | --- |
| `conversation_to_string` | other verb | `render_conversation_as_string` |

**source/builder/Builder.jl**

| old | kind | new |
| --- | --- | --- |
| `workbench_app` | factory | `make_workbench_app` |

**source/chart/ChartDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `chart_axis_family` | getter | `get_chart_axis_family` |
| `chart_part_index` | getter | `get_chart_part_index` |
| `chart_parts` | getter | `get_chart_parts` |
| `chart_sample` | getter | `get_chart_sample` |
| `chart_sample_reference` | factory | `make_chart_sample_reference` |
| `chart_series_family` | getter | `get_chart_series_family` |
| `selected_sample` | getter | `get_selected_sample` |
| `selected_series_index` | getter | `get_selected_series_index` |

**source/chart/ChartPlot.jl**

| old | kind | new |
| --- | --- | --- |
| `chart_view_contains` | predicate | `is_chart_view_contains` |
| `chart_view_of` | getter | `get_chart_view_of` |

**source/chart/ChartPlotToGraphics.jl**

| old | kind | new |
| --- | --- | --- |
| `chart_part_reference` | getter | `get_chart_part_reference` |
| `chart_series_reference` | getter | `get_chart_series_reference` |
| `legend_item_rects` | getter | `get_legend_item_rects` |

**source/clipboard/OsClipboard.jl**

| old | kind | new |
| --- | --- | --- |
| `os_clipboard_read` | other verb | `read_os_clipboard` |
| `os_clipboard_write` | other verb | `write_os_clipboard` |

**source/collection/CollectionDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `deletecol!` | already filed | — |
| `deleterow` | mutator | `deleterow!` |
| `deleterow!` | already filed | — |
| `insertcol!` | already filed | — |
| `insertrow` | mutator | `insertrow!` |
| `insertrow!` | already filed | — |

**source/console/Console.jl**

| old | kind | new |
| --- | --- | --- |
| `console_render` | other verb | `render_console` |

**source/conversation/ConversationDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `thinking_part` | factory | `make_thinking_part` |

**source/conversation/ConversationEditor.jl**

| old | kind | new |
| --- | --- | --- |
| `composer_host_op` | other verb | `resolve_composer_host_op` |
| `composer_read` | other verb | `read_composer` |
| `new_draft` | factory | `make_draft` |

**source/conversation/Evaluator.jl**

| old | kind | new |
| --- | --- | --- |
| `eval_kind_label` | getter | `get_eval_kind_label` |
| `result_text` | factory | `make_result_text` |

**source/database/DatabaseAdapters.jl**

| old | kind | new |
| --- | --- | --- |
| `db_alive` | predicate | `is_db_alive` |
| `db_catalog_columns` | getter | `get_db_catalog_columns` |
| `db_catalog_databases` | getter | `get_db_catalog_databases` |
| `db_catalog_foreign_keys` | getter | `get_db_catalog_foreign_keys` |
| `db_catalog_schemas` | getter | `get_db_catalog_schemas` |
| `db_catalog_tables` | getter | `get_db_catalog_tables` |
| `db_close!` | mutator | `close_db!` |
| `db_connect!` | mutator | `connect_db!` |
| `db_delete!` | mutator | `delete_db!` |
| `db_execute_raw` | other verb | `execute_db_raw` |
| `db_insert!` | mutator | `insert_db!` |
| `db_query` | other verb | `query_db` |
| `db_rowid_column` | getter | `get_db_rowid_column` |
| `db_update!` | mutator | `update_db!` |

**source/dbcatalog/DbCatalogToSyntax.jl**

| old | kind | new |
| --- | --- | --- |
| `dbcatalog_marker_eligible` | predicate | `is_dbcatalog_marker_eligible` |

**source/domain/Domain.jl**

| old | kind | new |
| --- | --- | --- |
| `domain_insertion` | getter | `get_domain_insertion` |
| `domain_prefix` | getter | `get_domain_prefix` |
| `insertable` | already filed | — |
| `insertion_aliases` | getter | `get_insertion_aliases` |
| `insertion_candidates` | getter | `get_insertion_candidates` |
| `insertion_document` | getter | `get_insertion_document` |
| `insertion_names` | getter | `get_insertion_names` |
| `insertion_root` | getter | `get_insertion_root` |
| `nothing_document` | getter | `get_nothing_document` |

**source/executable/Executable.jl**

| old | kind | new |
| --- | --- | --- |
| `julia_main` | other verb (special) | `(do not rename)` |

**source/fileformat/DocumentFile.jl**

| old | kind | new |
| --- | --- | --- |
| `new_document_for` | factory | `make_document_for` |
| `new_document_seed` | factory | `make_document_seed` |

**source/filesystem/FileSystemToSyntax.jl**

| old | kind | new |
| --- | --- | --- |
| `filesystem_marker_eligible` | predicate | `is_filesystem_marker_eligible` |

**source/focus/Focus.jl**

| old | kind | new |
| --- | --- | --- |
| `first_focusable_path` | getter | `get_first_focusable_path` |
| `last_focusable_path` | getter | `get_last_focusable_path` |
| `next_focusable_index` | getter | `get_next_focusable_index` |

**source/formula/FormulaDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `cell_name` | getter | `get_cell_name` |
| `column_letter` | getter | `get_column_letter` |
| `formula_dependencies` | getter | `get_formula_dependencies` |
| `formula_references` | getter | `get_formula_references` |
| `formula_result_text` | factory | `make_formula_result_text` |
| `formula_to_expr` | other verb | `convert_formula_to_expr` |
| `topological_order` | other verb | `compute_topological_order` |
| `would_create_cycle` | predicate | `is_creating_cycle` |

**source/fsm/FsmDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `component_machine` | other verb | `find_component_machine` |
| `machine_states` | getter | `get_machine_states` |
| `machine_transitions` | getter | `get_machine_transitions` |
| `transition_index` | getter | `get_transition_index` |

**source/fsm/FsmToJuliaCode.jl**

| old | kind | new |
| --- | --- | --- |
| `event_constant_name` | getter | `get_event_constant_name` |
| `machine_field_name` | getter | `get_machine_field_name` |
| `state_constant_name` | getter | `get_state_constant_name` |

**source/gesturehelp/CommandPalette.jl**

| old | kind | new |
| --- | --- | --- |
| `command_palette_matches` | getter | `get_command_palette_matches` |
| `command_palette_row` | getter | `get_command_palette_row` |
| `command_palette_selected` | getter | `get_command_palette_selected` |
| `command_palette_selection` | factory | `make_command_palette_selection` |
| `command_palette_settled_selection` | getter | `get_command_palette_settled_selection` |
| `command_palette_step` | other verb | `step_command_palette` |

**source/gesturehelp/CommandPaletteDecorator.jl**

| old | kind | new |
| --- | --- | --- |
| `command_palette_projection` | factory | `make_command_palette_projection` |

**source/gesturehelp/GestureMap.jl**

| old | kind | new |
| --- | --- | --- |
| `gesture_map` | factory | `make_gesture_map` |
| `gesture_row` | factory | `make_gesture_row` |
| `gesture_rows` | other verb | `collect_gesture_rows` |

**source/graph/GraphLayoutChoice.jl**

| old | kind | new |
| --- | --- | --- |
| `deferred_layout_engine` | factory | `make_deferred_layout_engine` |
| `pure_julia_layout_engine` | factory | `make_pure_julia_layout_engine` |
| `resolved_layout_engine` | other verb | `resolve_layout_engine` |

**source/graph/GraphLayoutEngine.jl**

| old | kind | new |
| --- | --- | --- |
| `constraint_clusters` | getter | `get_constraint_clusters` |
| `constraint_fixed_sizes` | getter | `get_constraint_fixed_sizes` |
| `constraint_pins` | getter | `get_constraint_pins` |
| `extent_transform` | getter | `get_extent_transform` |
| `straight_routes` | getter | `get_straight_routes` |
| `supported_constraint_kinds` | getter | `get_supported_constraint_kinds` |
| `vertex_sizes` | getter | `get_vertex_sizes` |

**source/graph/omnetpp/ForceDirectedEmbedding.jl**

| old | kind | new |
| --- | --- | --- |
| `embed!` | false positive | — |
| `embedding_bounding_rectangle` | getter | `get_embedding_bounding_rectangle` |

**source/graph/omnetpp/ForceDirectedParameters.jl**

| old | kind | new |
| --- | --- | --- |
| `spring_distance_and_vector` | getter | `get_spring_distance_and_vector` |
| `spring_repose_length` | getter | `get_spring_repose_length` |
| `wall_set_position!` | mutator | `set_wall_position!` |
| `wall_set_variable!` | mutator | `set_wall_variable!` |

**source/graph/omnetpp/ForceDirectedParametersBase.jl**

| old | kind | new |
| --- | --- | --- |
| `body_bottom` | getter | `get_body_bottom` |
| `body_charge` | getter | `get_body_charge` |
| `body_left` | getter | `get_body_left` |
| `body_left_top` | getter | `get_body_left_top` |
| `body_mass` | getter | `get_body_mass` |
| `body_position` | getter | `get_body_position` |
| `body_right` | getter | `get_body_right` |
| `body_size` | getter | `get_body_size` |
| `body_top` | getter | `get_body_top` |
| `body_variable` | getter | `get_body_variable` |
| `class_name` | getter | `get_class_name` |
| `kinetic_energy` | getter | `get_kinetic_energy` |
| `potential_energy` | getter | `get_potential_energy` |
| `reinitialize!` | false positive | — |

**source/graph/omnetpp/Geometry.jl**

| old | kind | new |
| --- | --- | --- |
| `area` | getter | `get_area` |
| `base_plane_angle` | getter | `get_base_plane_angle` |
| `base_plane_distance` | getter | `get_base_plane_distance` |
| `base_plane_length` | getter | `get_base_plane_length` |
| `base_plane_length_square` | getter | `get_base_plane_length_square` |
| `base_plane_projection` | getter | `get_base_plane_projection` |
| `base_plane_rotate` | other verb | `rotate_base_plane` |
| `base_plane_transpose` | other verb | `transpose_base_plane` |
| `diagonal_length` | getter | `get_diagonal_length` |
| `nan_to_zero` | other verb | `convert_nan_to_zero` |

**source/graph/omnetpp/GraphComponent.jl**

| old | kind | new |
| --- | --- | --- |
| `bounding_rectangle` | getter | `get_bounding_rectangle` |
| `edge_count` | getter | `get_edge_count` |
| `vertex_count` | getter | `get_vertex_count` |

**source/graph/omnetpp/HeapEmbedding.jl**

| old | kind | new |
| --- | --- | --- |
| `heap_embed!` | mutator | `embed_heap!` |

**source/graph/omnetpp/LcgRandom.jl**

| old | kind | new |
| --- | --- | --- |
| `draw!` | false positive | — |
| `lcg_self_test` | other verb | `run_lcg_self_test` |
| `next01!` | mutator | `draw_uniform01!` |
| `uniform!` | mutator | `draw_uniform!` |

**source/graph/omnetpp/StarTreeEmbedding.jl**

| old | kind | new |
| --- | --- | --- |
| `star_tree_embed!` | mutator | `embed_star_tree!` |

**source/graphics/GraphicsDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `graphics_size` | getter | `get_graphics_size` |
| `polyline_arrowhead` | factory | `make_polyline_arrowhead` |

**source/json/JsonDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `entries` | already filed | — |

**source/julia/JuliaFile.jl**

| old | kind | new |
| --- | --- | --- |
| `julia_definition` | other verb | `find_julia_definition` |
| `julia_definition_name` | getter | `get_julia_definition_name` |

**source/julia/JuliaInsertionToSyntax.jl**

| old | kind | new |
| --- | --- | --- |
| `julia_completion` | getter | `get_julia_completion` |
| `julia_scaffold` | factory | `make_julia_scaffold` |

**source/kernel/cell/CellStructModule.jl**

| old | kind | new |
| --- | --- | --- |
| `cell_kind_of` | getter | `get_cell_kind_of` |
| `cell_struct_exprs` | other verb | `build_cell_struct_exprs` |
| `cell_struct_field_kinds` | getter | `get_cell_struct_field_kinds` |
| `cell_struct_kw_params` | other verb | `build_cell_struct_kw_params` |
| `cell_struct_kwctor` | other verb | `build_cell_struct_kwctor` |
| `cell_struct_macro_default` | other verb | `parse_cell_struct_macro_default` |
| `cell_struct_plan` | factory | `make_cell_struct_plan` |
| `cell_struct_positional_ctors` | other verb | `build_cell_struct_positional_ctors` |
| `cell_struct_required_count` | getter | `get_cell_struct_required_count` |
| `cell_struct_trailing_default_count` | getter | `get_cell_struct_trailing_default_count` |
| `cell_struct_value_types` | getter | `get_cell_struct_value_types` |

**source/kernel/document/DocumentModule.jl**

| old | kind | new |
| --- | --- | --- |
| `cell_layout_field_type` | getter | `get_cell_layout_field_type` |
| `document_cell_type` | getter | `get_document_cell_type` |
| `document_family` | getter | `get_document_family` |
| `document_native_type` | getter | `get_document_native_type` |
| `document_schema_name` | getter | `get_document_schema_name` |
| `should_descend_sync` | predicate | `is_descend_sync` |
| `string_predicate` | factory | `make_string_predicate` |
| `unsynced_placeholder` | getter | `get_unsynced_placeholder` |

**source/kernel/editor/Editor.jl**

| old | kind | new |
| --- | --- | --- |
| `evaluate!` | false positive | — |
| `print!` | false positive | — |
| `read!` | false positive | — |

**source/kernel/llm/LlmModule.jl**

| old | kind | new |
| --- | --- | --- |
| `llm_backend_names` | getter | `get_llm_backend_names` |
| `tool_schema` | other verb | `render_tool_schema` |

**source/kernel/operation/Intent.jl**

| old | kind | new |
| --- | --- | --- |
| `labelled_intent` | derived copy | `with_intent_labels` |

**source/kernel/projection/ChildrenContainer.jl**

| old | kind | new |
| --- | --- | --- |
| `children_container_type` | getter | `get_children_container_type` |

**source/kernel/projection/Projection.jl**

| old | kind | new |
| --- | --- | --- |
| `pure_print` | other verb (prefix qualifier) | `print_pure` |

**source/kernel/projection/ProjectionApi.jl**

| old | kind | new |
| --- | --- | --- |
| `pure_print_child` | other verb | `print_child_pure` |
| `pure_print_document` | other verb | `print_document_pure` |

**source/kernel/projection/ProjectionReferenceStep.jl**

| old | kind | new |
| --- | --- | --- |
| `introduced_reference` | factory | `make_introduced_reference` |
| `named_node_reference` | other verb | `normalize_named_node_reference` |

**source/kernel/projection/ProjectionTemplate.jl**

| old | kind | new |
| --- | --- | --- |
| `bound` | factory | `make_bound` |
| `collection` | factory | `make_collection` |
| `sections` | factory | `make_sections` |
| `tokens` | factory | `make_tokens` |

**source/kernel/tool/ToolModule.jl**

| old | kind | new |
| --- | --- | --- |
| `api_entry_names` | getter | `get_api_entry_names` |
| `api_modules` | getter | `get_api_modules` |
| `last_evaluated_value` | already filed | — |

**source/markdown/MarkdownFile.jl**

| old | kind | new |
| --- | --- | --- |
| `markdown_section` | getter | `get_markdown_section` |

**source/math/MathDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `math_accent_is_wide` | predicate | `is_math_accent_wide` |
| `math_big_operator_glyph` | getter | `get_math_big_operator_glyph` |
| `math_big_operator_is_text` | predicate | `is_math_big_operator_text` |
| `math_big_operator_name` | getter | `get_math_big_operator_name` |
| `math_delimiter_strings` | getter | `get_math_delimiter_strings` |
| `math_operator_class` | getter | `get_math_operator_class` |
| `math_operator_glyph` | getter | `get_math_operator_glyph` |
| `math_symbol_glyph` | getter | `get_math_symbol_glyph` |

**source/math/MathToGraphics.jl**

| old | kind | new |
| --- | --- | --- |
| `math_metrics` | getter | `get_math_metrics` |
| `math_to_graphics_dispatch` | factory | `make_math_to_graphics_dispatch` |

**source/mcp/Mcp.jl**

| old | kind | new |
| --- | --- | --- |
| `mcp_resources` | other verb | `render_mcp_resources` |
| `mcp_start!` | mutator | `start_mcp!` |
| `mcp_stop!` | mutator | `stop_mcp!` |
| `mcp_tools` | other verb | `render_mcp_tools` |

**source/natural/NaturalRegistry.jl**

| old | kind | new |
| --- | --- | --- |
| `natural_fallback_entries` | getter | `get_natural_fallback_entries` |
| `natural_graphics_entries` | getter | `get_natural_graphics_entries` |
| `natural_syntax_entries` | getter | `get_natural_syntax_entries` |

**source/odbc/Odbc.jl**

| old | kind | new |
| --- | --- | --- |
| `dsn_for` | getter | `get_dsn_for` |

**source/pane/PaneDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `pane_groups` | getter | `get_pane_groups` |
| `pane_normalized_weights` | getter | `get_pane_normalized_weights` |
| `pane_orientation_opposite` | getter | `get_pane_orientation_opposite` |
| `pane_parent` | getter | `get_pane_parent` |
| `pane_split_axis` | getter | `get_pane_split_axis` |
| `pane_tab_title_string` | getter | `get_pane_tab_title_string` |
| `pane_weight` | getter | `get_pane_weight` |
| `pane_weights` | getter | `get_pane_weights` |

**source/pane/PaneGeometry.jl**

| old | kind | new |
| --- | --- | --- |
| `pane_drop_zone` | getter | `get_pane_drop_zone` |
| `pane_group_at` | getter | `get_pane_group_at` |
| `pane_neighbour_group` | getter | `get_pane_neighbour_group` |
| `pane_next_group` | getter | `get_pane_next_group` |
| `pane_rectangle` | getter | `get_pane_rectangle` |
| `pane_rectangles` | getter | `get_pane_rectangles` |
| `pane_zone_orientation` | getter | `get_pane_zone_orientation` |

**source/pane/PaneProgram.jl**

| old | kind | new |
| --- | --- | --- |
| `pane_api` | factory | `make_pane_api` |

**source/pane/PaneSurgery.jl**

| old | kind | new |
| --- | --- | --- |
| `pane_close_tab_operation` | factory | `make_pane_close_tab_operation` |
| `pane_collection_path` | getter | `get_pane_collection_path` |
| `pane_drop_split_operation` | factory | `make_pane_drop_split_operation` |
| `pane_focus` | getter | `get_pane_focus` |
| `pane_focus_operation` | factory | `make_pane_focus_operation` |
| `pane_focus_title` | getter | `get_pane_focus_title` |
| `pane_focused_group` | getter | `get_pane_focused_group` |
| `pane_focused_tab_index` | getter | `get_pane_focused_tab_index` |
| `pane_move_tab_operation` | factory | `make_pane_move_tab_operation` |
| `pane_open_tab_operation` | factory | `make_pane_open_tab_operation` |
| `pane_path` | getter | `get_pane_path` |
| `pane_resize_operation` | factory | `make_pane_resize_operation` |
| `pane_retarget_title_operation` | factory | `make_pane_retarget_title_operation` |
| `pane_shown_tab_index` | getter | `get_pane_shown_tab_index` |
| `pane_split_operation` | factory | `make_pane_split_operation` |
| `pane_tab_reference` | getter | `get_pane_tab_reference` |
| `pane_title_caret_operation` | factory | `make_pane_title_caret_operation` |
| `pane_title_path` | getter | `get_pane_title_path` |

**source/plot/PlotGeometry.jl**

| old | kind | new |
| --- | --- | --- |
| `axis_span` | getter | `get_axis_span` |
| `bin_values` | other verb | `compute_bin_values` |
| `column_bounds` | getter | `get_column_bounds` |
| `histogram_values` | other verb | `compute_histogram_values` |
| `legend_layout` | other verb | `compute_legend_layout` |
| `nearest_sample` | other verb | `find_nearest_sample` |
| `nice_num` | other verb | `compute_nice_num` |
| `nice_ticks` | other verb | `compute_nice_ticks` |
| `pins_segments` | other verb | `build_pins_segments` |
| `visible_range` | getter | `get_visible_range` |

**source/plot/PlotStyle.jl**

| old | kind | new |
| --- | --- | --- |
| `marker_polygon` | other verb | `build_marker_polygon` |
| `series_color` | getter | `get_series_color` |
| `series_symbol` | getter | `get_series_symbol` |

**source/primitive/ObjectField.jl**

| old | kind | new |
| --- | --- | --- |
| `object_field_name` | getter | `get_object_field_name` |
| `object_field_value` | getter | `get_object_field_value` |

**source/process/ProcessDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `body_steps` | getter | `get_body_steps` |
| `node_at` | getter | `get_node_at` |
| `node_index` | getter | `get_node_index` |
| `unrefined_nodes` | getter | `get_unrefined_nodes` |

**source/reflection/BoundedSync.jl**

| old | kind | new |
| --- | --- | --- |
| `unsynced_marker` | factory | `make_unsynced_marker` |
| `unsynced_size` | getter | `get_unsynced_size` |

**source/reflection/DocumentReflection.jl**

| old | kind | new |
| --- | --- | --- |
| `reflection_value` | getter | `get_reflection_value` |

**source/rst/RstFile.jl**

| old | kind | new |
| --- | --- | --- |
| `rst_section` | getter | `get_rst_section` |
| `rst_title_text` | getter | `get_rst_title_text` |

**source/screen/WindowScene.jl**

| old | kind | new |
| --- | --- | --- |
| `window_scene` | factory | `make_window_scene` |
| `window_scene_projection` | factory | `make_window_scene_projection` |

**source/sdl/Sdl.jl**

| old | kind | new |
| --- | --- | --- |
| `sdl_decode_image` | other verb | `decode_sdl_image` |
| `sdl_display_size` | getter | `get_sdl_display_size` |
| `sdl_measure_text` | other verb | `measure_sdl_text` |
| `sdl_render_canvas` | other verb | `render_sdl_canvas` |

**source/sequencechart/SequenceChartDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `arrow_count` | getter | `get_arrow_count` |
| `arrow_from_event` | getter | `get_arrow_from_event` |
| `arrow_into_event` | getter | `get_arrow_into_event` |
| `arrow_kind` | getter | `get_arrow_kind` |
| `arrow_label` | getter | `get_arrow_label` |
| `arrow_reference` | getter | `get_arrow_reference` |
| `arrow_row` | getter | `get_arrow_row` |
| `arrow_source_axis` | getter | `get_arrow_source_axis` |
| `arrow_target_axis` | getter | `get_arrow_target_axis` |
| `axis_display_order` | getter | `get_axis_display_order` |
| `axis_reference` | getter | `get_axis_reference` |
| `band_reference` | getter | `get_band_reference` |
| `band_row` | getter | `get_band_row` |
| `band_state_name` | getter | `get_band_state_name` |
| `event_axis` | getter | `get_event_axis` |
| `event_count` | getter | `get_event_count` |
| `event_kind` | getter | `get_event_kind` |
| `event_label` | getter | `get_event_label` |
| `event_reference` | getter | `get_event_reference` |
| `event_row` | getter | `get_event_row` |
| `next_event_on_lane` | getter | `get_next_event_on_lane` |
| `selected_arrow` | getter | `get_selected_arrow` |
| `selected_axis_index` | getter | `get_selected_axis_index` |
| `selected_event` | getter | `get_selected_event` |
| `sequence_chart_part_index` | getter | `get_sequence_chart_part_index` |
| `sequence_chart_parts` | getter | `get_sequence_chart_parts` |

**source/sequencechart/SequenceChartGeometry.jl**

| old | kind | new |
| --- | --- | --- |
| `arc_geometry` | getter | `get_arc_geometry` |
| `arrow_coverage_dedup` | other verb | `dedup_arrow_coverage` |
| `arrow_route` | getter | `get_arrow_route` |
| `axis_cross_positions` | getter | `get_axis_cross_positions` |
| `band_intervals` | getter | `get_band_intervals` |
| `coordinate_to_time` | other verb | `convert_coordinate_to_time` |
| `event_ordinal` | getter | `get_event_ordinal` |
| `honest_tick_label` | getter | `get_honest_tick_label` |
| `timeline_coordinates` | getter | `get_timeline_coordinates` |
| `visible_arrows` | getter | `get_visible_arrows` |
| `visible_event_range` | getter | `get_visible_event_range` |
| `zero_time_spans` | getter | `get_zero_time_spans` |

**source/sequencechart/SequenceChartPlot.jl**

| old | kind | new |
| --- | --- | --- |
| `sequence_chart_view_of` | getter | `get_sequence_chart_view_of` |

**source/sequencechart/SequenceChartPlotToGraphics.jl**

| old | kind | new |
| --- | --- | --- |
| `arrow_hit` | getter | `get_arrow_hit` |
| `band_hit` | getter | `get_band_hit` |
| `event_hit` | getter | `get_event_hit` |
| `lane_cross_position` | getter | `get_lane_cross_position` |
| `lane_hit` | getter | `get_lane_hit` |
| `sequence_chart_reference` | other verb | `lift_sequence_chart_reference` |

**source/serialization/FileProject.jl**

| old | kind | new |
| --- | --- | --- |
| `content` | getter | `get_content` |
| `document_section` | getter | `get_document_section` |
| `file_document_type` | getter | `get_file_document_type` |
| `file_marker_text` | other verb | `format_file_marker_text` |
| `filename` | getter | `get_filename` |
| `marker_function` | getter | `get_marker_function` |
| `marker_text` | other verb | `format_marker_text` |
| `resolve!` | false positive | — |

**source/style/Geometry.jl**

| old | kind | new |
| --- | --- | --- |
| `affine_apply` | other verb | `apply_affine_transform` |
| `affine_identity` | not a function | — |
| `affine_inverse` | factory | `make_affine_inverse` |
| `affine_is_axis_aligned` | predicate | `is_affine_axis_aligned` |
| `affine_scale` | factory | `make_affine_scale` |
| `affine_translate` | factory | `make_affine_translate` |

**source/style/TrueType.jl**

| old | kind | new |
| --- | --- | --- |
| `truetype_measure_text` | other verb | `measure_truetype_text` |

**source/syntax/InsertionToSyntax.jl**

| old | kind | new |
| --- | --- | --- |
| `insertion_delete` | other verb | `compute_insertion_delete` |
| `insertion_insert` | other verb | `compute_insertion_insert` |

**source/syntax/SyntaxDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `syntax_child_path` | factory | `make_syntax_child_path` |
| `syntax_children` | getter | `get_syntax_children` |
| `syntax_closing` | getter | `get_syntax_closing` |
| `syntax_collapsed` | predicate | `is_syntax_collapsed` |
| `syntax_collapsible` | predicate | `is_syntax_collapsible` |
| `syntax_indentation` | getter | `get_syntax_indentation` |
| `syntax_opening` | getter | `get_syntax_opening` |
| `syntax_separator` | getter | `get_syntax_separator` |

**source/syntax/SyntaxNatural.jl**

| old | kind | new |
| --- | --- | --- |
| `natural_to_syntax_dispatch` | factory | `make_natural_to_syntax_dispatch` |

**source/text/TextDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `hinted_text` | factory | `make_hinted_text` |
| `text_caret_flat` | getter | `get_text_caret_flat` |
| `text_elem_to_flat` | getter | `get_text_elem_to_flat` |
| `text_flat_length` | getter | `get_text_flat_length` |
| `text_flat_offsets` | getter | `get_text_flat_offsets` |
| `text_flat_to_elem` | getter | `get_text_flat_to_elem` |
| `text_insert_op` | factory | `make_text_insert_op` |
| `text_selection_flat` | getter | `get_text_selection_flat` |
| `text_selection_substring` | getter | `get_text_selection_substring` |

**source/web/Web.jl**

| old | kind | new |
| --- | --- | --- |
| `web_key_to_symbol` | other verb | `convert_web_key_to_symbol` |

**source/widget/WidgetDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `action_shortcut_matches` | predicate | `matches_action_shortcut` |
| `as_action` | other verb | `resolve_action` |
| `numeric_validator` | factory | `make_numeric_validator` |
| `widget_column_chooser` | factory | `make_widget_column_chooser` |
| `widget_filter_bar` | factory | `make_widget_filter_bar` |
| `widget_lazy_table_row_selection` | factory | `make_widget_lazy_table_row_selection` |
| `widget_lazy_table_selected_row` | getter | `get_widget_lazy_table_selected_row` |
| `widget_list_selected` | getter | `get_widget_list_selected` |
| `widget_list_selection` | factory | `make_widget_list_selection` |
| `widget_pager` | factory | `make_widget_pager` |
| `widget_table_row_selection` | factory | `make_widget_table_row_selection` |
| `widget_table_selected_row` | getter | `get_widget_table_selected_row` |

**source/widget/WidgetToGraphics.jl**

| old | kind | new |
| --- | --- | --- |
| `frozen_extent` | getter | `get_frozen_extent` |
| `glyph_icon` | factory | `make_glyph_icon` |
| `image_icon` | factory | `make_image_icon` |
| `widget_theme_dark` | factory | `make_widget_theme_dark` |
| `widget_theme_light` | factory | `make_widget_theme_light` |
| `widget_theme_slate_dark` | factory | `make_widget_theme_slate_dark` |
| `widget_theme_slate_light` | factory | `make_widget_theme_slate_light` |

**source/workbench/WorkbenchDocument.jl**

| old | kind | new |
| --- | --- | --- |
| `title` | getter | `get_title` |

**test/kernel/KernelSuite.jl**

| old | kind | new |
| --- | --- | --- |
| `package_source_root` | getter | `get_package_source_root` |

**test/kernel/tool/DeclaredApiTest.jl**

| old | kind | new |
| --- | --- | --- |
| `toy_arrange` | fixture — exclude | — |
| `toy_count` | fixture — exclude | — |
| `toy_extra` | fixture — exclude | — |
| `toy_verb` | fixture — exclude | — |

**test/projectured/ExportCollisionTest.jl**

| old | kind | new |
| --- | --- | --- |
| `only_alpha` | fixture — exclude | — |
| `shared` | fixture — exclude | — |

**test/projectured/ProjecturedSuite.jl**

| old | kind | new |
| --- | --- | --- |
| `catalog_coverage_gap` | getter | `get_catalog_coverage_gap` |
| `nav_broken` | getter | `get_nav_broken` |
| `printer_locality_report` | other verb | `explore_printer_locality` |
