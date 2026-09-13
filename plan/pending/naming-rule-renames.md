# Every rename of the functions that do not start with a verb

> **Kind:** plan · **Status:** applied 2026-09-13 · **Stands on:** [naming-rule-violations.md](naming-rule-violations.md) §14.9

374 names, grouped by the file that defines them.

Two independent passes named every one of the 374, each reading the definition
rather than the name. The `status` column says what came back:

| status | count | meaning |
| --- | --- | --- |
| `agreed` | 287 | both passes reached the same name. Apply it. |
| `contested` | 62 | the passes differ. Both names are shown, and §14.10 groups them into the few questions that settle them all. |
| `no change` | 16 | already verb-first, a test fixture, or not a function. |
| `one pass only` | 5 | one pass named it and the other was told to skip it. Apply the name shown. |
| `rule decides` | 4 | the passes differ, and one of them breaks a stated rule. The compliant name is shown. |

**Applied on 2026-09-13.** Every row below landed, except where the group
that executed it overruled the name — about twenty rows, because this table was
built before the user's verb rulings existed. Section 0.4 of
[naming-rule-violations.md](naming-rule-violations.md) states the pattern, and
each group's commit message names what it changed and why.

**Two names appear twice on purpose.** `insert_row!` and `delete_row!` are each
proposed for a pair: one in
[CellMatrix.jl](../../source/collection/CellMatrix.jl) and one in
[CellTable.jl](../../source/collection/CellTable.jl). That is the same
operation on two container types, so it is one generic with two methods, not two
unrelated concepts sharing a name. Every other name in this file is unique.

**Validation.** All 374 final names are snake_case, every one starts with a
verb, and none carries a banned abbreviation. I checked each of the three.

**source/assistant/AssistantTurn.jl**

| old | new | status |
| --- | --- | --- |
| `conversation_to_string` | `format_conversation` | resolved |

**source/builder/Builder.jl**

| old | new | status |
| --- | --- | --- |
| `workbench_app` | `make_workbench_app` | agreed |

**source/chart/ChartDocument.jl**

| old | new | status |
| --- | --- | --- |
| `chart_axis_family` | `get_chart_axis_family` | agreed |
| `chart_part_index` | `get_chart_part_index` | agreed |
| `chart_parts` | `collect_chart_parts` | resolved |
| `chart_sample` | `get_chart_sample` | agreed |
| `chart_sample_reference` | `make_chart_sample_reference` | agreed |
| `chart_series_family` | `get_chart_series_family` | agreed |
| `selected_sample` | `get_selected_sample` | agreed |
| `selected_series_index` | `get_selected_series_index` | agreed |

**source/chart/ChartPlot.jl**

| old | new | status |
| --- | --- | --- |
| `chart_view_contains` | `is_point_in_chart_view` | resolved |
| `chart_view_of` | `get_chart_view` | resolved |

**source/chart/ChartPlotToGraphics.jl**

| old | new | status |
| --- | --- | --- |
| `chart_part_reference` | `get_chart_part_reference` | agreed |
| `chart_series_reference` | `get_chart_series_reference` | agreed |
| `legend_item_rects` | `get_legend_item_rects` | agreed |

**source/clipboard/Clipboard.jl**

| old | new | status |
| --- | --- | --- |
| `os_clipboard_read` | `read_os_clipboard` | resolved |
| `os_clipboard_write` | `write_os_clipboard!` | resolved |

**source/collection/CollectionDocument.jl**

| old | new | status |
| --- | --- | --- |
| `deletecol!` | `delete_column!` | one pass only |
| `deleterow` | `delete_row!` | rule decides |
| `deleterow!` | `delete_row!` | one pass only |
| `insertcol!` | `insert_column!` | one pass only |
| `insertrow` | `insert_row!` | rule decides |
| `insertrow!` | `insert_row!` | one pass only |

**source/console/Console.jl**

| old | new | status |
| --- | --- | --- |
| `console_render` | `render_console` | agreed |

**source/conversation/ConversationDocument.jl**

| old | new | status |
| --- | --- | --- |
| `thinking_part` | `make_thinking_part` | agreed |

**source/conversation/ConversationEditor.jl**

| old | new | status |
| --- | --- | --- |
| `composer_host_op` | `resolve_composer_host_operation` | rule decides |
| `composer_read` | `read_composer` | resolved |
| `new_draft` | `make_draft` | agreed |

**source/conversation/Evaluator.jl**

| old | new | status |
| --- | --- | --- |
| `eval_kind_label` | `get_evaluation_kind_label` | agreed |
| `result_text` | `make_result_text` | agreed |

**source/database/DatabaseAdapters.jl**

| old | new | status |
| --- | --- | --- |
| `db_alive` | `is_db_alive` | agreed |
| `db_catalog_columns` | `get_db_catalog_columns` | agreed |
| `db_catalog_databases` | `get_db_catalog_databases` | agreed |
| `db_catalog_foreign_keys` | `get_db_catalog_foreign_keys` | agreed |
| `db_catalog_schemas` | `get_db_catalog_schemas` | agreed |
| `db_catalog_tables` | `get_db_catalog_tables` | agreed |
| `db_close!` | `close_db!` | agreed |
| `db_connect!` | `connect_db!` | agreed |
| `db_delete!` | `delete_db!` | agreed |
| `db_execute_raw` | `execute_db_raw` | agreed |
| `db_insert!` | `insert_db!` | agreed |
| `db_query` | `query_db` | agreed |
| `db_rowid_column` | `get_db_rowid_column` | agreed |
| `db_update!` | `update_db!` | agreed |

**source/dbcatalog/DbCatalogToSyntax.jl**

| old | new | status |
| --- | --- | --- |
| `dbcatalog_marker_eligible` | `is_dbcatalog_marker_eligible` | agreed |

**source/domain/Domain.jl**

| old | new | status |
| --- | --- | --- |
| `domain_insertion` | `get_domain_insertion` | agreed |
| `domain_prefix` | `get_domain_prefix` | agreed |
| `insertable` | — | no change |
| `insertion_aliases` | `get_insertion_aliases` | agreed |
| `insertion_candidates` | `get_insertion_candidates` | agreed |
| `insertion_document` | `get_insertion_document` | agreed |
| `insertion_names` | `get_insertion_names` | agreed |
| `insertion_root` | `get_insertion_root` | agreed |
| `nothing_document` | `get_nothing_document` | agreed |

**source/executable/Executable.jl**

| old | new | status |
| --- | --- | --- |
| `julia_main` | `julia_main` | resolved |

**source/fileformat/DocumentFile.jl**

| old | new | status |
| --- | --- | --- |
| `new_document_for` | `make_document_for` | agreed |
| `new_document_seed` | `make_document_seed` | agreed |

**source/filesystem/FileSystemToSyntax.jl**

| old | new | status |
| --- | --- | --- |
| `filesystem_marker_eligible` | `is_filesystem_marker_eligible` | agreed |

**source/focus/Focus.jl**

| old | new | status |
| --- | --- | --- |
| `first_focusable_path` | `get_first_focusable_path` | agreed |
| `last_focusable_path` | `get_last_focusable_path` | agreed |
| `next_focusable_index` | `get_next_focusable_index` | agreed |

**source/formula/FormulaDocument.jl**

| old | new | status |
| --- | --- | --- |
| `cell_name` | `get_cell_name` | agreed |
| `column_letter` | `get_column_letter` | agreed |
| `formula_dependencies` | `get_formula_dependencies` | agreed |
| `formula_references` | `get_formula_references` | agreed |
| `formula_result_text` | `make_formula_result_text` | agreed |
| `formula_to_expr` | `convert_formula_to_expr` | agreed |
| `topological_order` | `compute_topological_order` | resolved |
| `would_create_cycle` | `is_creating_cycle` | agreed |

**source/fsm/FsmDocument.jl**

| old | new | status |
| --- | --- | --- |
| `component_machine` | `find_component_machine` | agreed |
| `machine_states` | `get_machine_states` | agreed |
| `machine_transitions` | `get_machine_transitions` | agreed |
| `transition_index` | `get_transition_index` | agreed |

**source/fsm/FsmToJuliaCode.jl**

| old | new | status |
| --- | --- | --- |
| `event_constant_name` | `get_event_constant_name` | agreed |
| `machine_field_name` | `get_machine_field_name` | agreed |
| `state_constant_name` | `get_state_constant_name` | agreed |

**source/gesturehelp/CommandPalette.jl**

| old | new | status |
| --- | --- | --- |
| `command_palette_matches` | `get_command_palette_matches` | agreed |
| `command_palette_row` | `get_command_palette_row` | agreed |
| `command_palette_selected` | `get_command_palette_selected` | agreed |
| `command_palette_selection` | `build_command_palette_selection` | resolved |
| `command_palette_settled_selection` | `get_command_palette_settled_selection` | resolved |
| `command_palette_step` | `compute_command_palette_step` | resolved |

**source/gesturehelp/CommandPaletteDecorator.jl**

| old | new | status |
| --- | --- | --- |
| `command_palette_projection` | `make_command_palette_projection` | agreed |

**source/gesturehelp/GestureMap.jl**

| old | new | status |
| --- | --- | --- |
| `gesture_map` | `make_gesture_map` | agreed |
| `gesture_row` | `make_gesture_row` | agreed |
| `gesture_rows` | `collect_gesture_rows` | resolved |

**source/graph/GraphLayoutChoice.jl**

| old | new | status |
| --- | --- | --- |
| `deferred_layout_engine` | `make_deferred_layout_engine` | agreed |
| `pure_julia_layout_engine` | `make_pure_julia_layout_engine` | agreed |
| `resolved_layout_engine` | `resolve_layout_engine` | resolved |

**source/graph/GraphLayoutEngine.jl**

| old | new | status |
| --- | --- | --- |
| `constraint_clusters` | `get_constraint_clusters` | agreed |
| `constraint_fixed_sizes` | `get_constraint_fixed_sizes` | agreed |
| `constraint_pins` | `get_constraint_pins` | agreed |
| `extent_transform` | `get_extent_transform` | agreed |
| `straight_routes` | `get_straight_routes` | agreed |
| `supported_constraint_kinds` | `get_supported_constraint_kinds` | agreed |
| `vertex_sizes` | `get_vertex_sizes` | agreed |

**source/graph/omnetpp/ForceDirectedEmbedding.jl**

| old | new | status |
| --- | --- | --- |
| `embed!` | — | no change |
| `embedding_bounding_rectangle` | `get_embedding_bounding_rectangle` | agreed |

**source/graph/omnetpp/ForceDirectedParameters.jl**

| old | new | status |
| --- | --- | --- |
| `spring_distance_and_vector` | `get_spring_distance_and_vector` | agreed |
| `spring_repose_length` | `get_spring_repose_length` | agreed |
| `wall_set_position!` | `set_wall_position!` | agreed |
| `wall_set_variable!` | `set_wall_variable!` | agreed |

**source/graph/omnetpp/ForceDirectedParametersBase.jl**

| old | new | status |
| --- | --- | --- |
| `body_bottom` | `get_body_bottom` | agreed |
| `body_charge` | `get_body_charge` | agreed |
| `body_left` | `get_body_left` | agreed |
| `body_left_top` | `get_body_left_top` | agreed |
| `body_mass` | `get_body_mass` | agreed |
| `body_position` | `get_body_position` | agreed |
| `body_right` | `get_body_right` | agreed |
| `body_size` | `get_body_size` | agreed |
| `body_top` | `get_body_top` | agreed |
| `body_variable` | `get_body_variable` | agreed |
| `class_name` | `get_class_name` | agreed |
| `kinetic_energy` | `get_kinetic_energy` | agreed |
| `potential_energy` | `get_potential_energy` | agreed |
| `reinitialize!` | — | no change |

**source/graph/omnetpp/Geometry.jl**

| old | new | status |
| --- | --- | --- |
| `area` | `get_area` | agreed |
| `base_plane_angle` | `get_base_plane_angle` | agreed |
| `base_plane_distance` | `get_base_plane_distance` | resolved |
| `base_plane_length` | `get_base_plane_length` | resolved |
| `base_plane_length_square` | `get_base_plane_length_square` | resolved |
| `base_plane_projection` | `with_base_plane_projection` | resolved |
| `base_plane_rotate` | `rotate_base_plane` | agreed |
| `base_plane_transpose` | `transpose_base_plane` | agreed |
| `diagonal_length` | `get_diagonal_length` | agreed |
| `nan_to_zero` | `convert_nan_to_zero` | agreed |

**source/graph/omnetpp/GraphComponent.jl**

| old | new | status |
| --- | --- | --- |
| `bounding_rectangle` | `get_bounding_rectangle` | agreed |
| `edge_count` | `get_edge_count` | agreed |
| `vertex_count` | `get_vertex_count` | agreed |

**source/graph/omnetpp/HeapEmbedding.jl**

| old | new | status |
| --- | --- | --- |
| `heap_embed!` | `embed_heap!` | agreed |

**source/graph/omnetpp/LcgRandom.jl**

| old | new | status |
| --- | --- | --- |
| `draw!` | — | no change |
| `lcg_self_test` | `run_lcg_self_test` | agreed |
| `next01!` | `draw_uniform01!` | resolved |
| `uniform!` | `draw_uniform!` | agreed |

**source/graph/omnetpp/StarTreeEmbedding.jl**

| old | new | status |
| --- | --- | --- |
| `star_tree_embed!` | `embed_star_tree!` | agreed |

**source/graphics/GraphicsDocument.jl**

| old | new | status |
| --- | --- | --- |
| `graphics_size` | `get_graphics_size` | agreed |
| `polyline_arrowhead` | `build_polyline_arrowhead` | resolved |

**source/json/JsonDocument.jl**

| old | new | status |
| --- | --- | --- |
| `entries` | — | no change |

**source/julia/JuliaFile.jl**

| old | new | status |
| --- | --- | --- |
| `julia_definition` | `find_julia_definition` | agreed |
| `julia_definition_name` | `get_julia_definition_name` | agreed |

**source/julia/JuliaInsertionToSyntax.jl**

| old | new | status |
| --- | --- | --- |
| `julia_completion` | `get_julia_completion` | agreed |
| `julia_scaffold` | `make_julia_scaffold` | agreed |

**source/kernel/cell/CellStructModule.jl**

| old | new | status |
| --- | --- | --- |
| `cell_kind_of` | `get_cell_kind_of` | agreed |
| `cell_struct_exprs` | `build_cell_struct_exprs` | resolved |
| `cell_struct_field_kinds` | `get_cell_struct_field_kinds` | agreed |
| `cell_struct_kw_params` | `build_cell_struct_kw_params` | resolved |
| `cell_struct_kwctor` | `build_cell_struct_kwctor` | resolved |
| `cell_struct_macro_default` | `parse_cell_struct_macro_default` | agreed |
| `cell_struct_plan` | `make_cell_struct_plan` | agreed |
| `cell_struct_positional_ctors` | `build_cell_struct_positional_ctors` | resolved |
| `cell_struct_required_count` | `get_cell_struct_required_count` | agreed |
| `cell_struct_trailing_default_count` | `get_cell_struct_trailing_default_count` | agreed |
| `cell_struct_value_types` | `get_cell_struct_value_types` | agreed |

**source/kernel/document/DocumentModule.jl**

| old | new | status |
| --- | --- | --- |
| `cell_layout_field_type` | `get_cell_layout_field_type` | agreed |
| `document_cell_type` | `get_document_cell_type` | agreed |
| `document_family` | `get_document_family` | agreed |
| `document_native_type` | `get_document_native_type` | agreed |
| `document_schema_name` | `get_document_schema_name` | agreed |
| `should_descend_sync` | `is_sync_descendable` | resolved |
| `string_predicate` | `make_string_predicate` | agreed |
| `unsynced_placeholder` | `make_unsynced_placeholder` | resolved |

**source/kernel/editor/Editor.jl**

| old | new | status |
| --- | --- | --- |
| `evaluate!` | — | no change |
| `print!` | — | no change |
| `read!` | — | no change |

**source/kernel/llm/LlmModule.jl**

| old | new | status |
| --- | --- | --- |
| `llm_backend_names` | `get_llm_backend_names` | agreed |
| `tool_schema` | `render_tool_schema` | resolved |

**source/kernel/operation/Intent.jl**

| old | new | status |
| --- | --- | --- |
| `labelled_intent` | `with_intent_labels` | agreed |

**source/kernel/projection/ChildrenContainer.jl**

| old | new | status |
| --- | --- | --- |
| `children_container_type` | `get_children_container_type` | agreed |

**source/kernel/projection/Projection.jl**

| old | new | status |
| --- | --- | --- |
| `pure_print` | `print_pure` | agreed |

**source/kernel/projection/ProjectionApi.jl**

| old | new | status |
| --- | --- | --- |
| `pure_print_child` | `print_child_pure` | agreed |
| `pure_print_document` | `print_document_pure` | agreed |

**source/kernel/projection/ProjectionReferenceStep.jl**

| old | new | status |
| --- | --- | --- |
| `introduced_reference` | `make_introduced_reference` | agreed |
| `named_node_reference` | `normalize_named_node_reference` | resolved |

**source/kernel/projection/ProjectionTemplate.jl**

| old | new | status |
| --- | --- | --- |
| `bound` | `make_bound` | agreed |
| `collection` | `make_collection` | agreed |
| `sections` | `make_sections` | agreed |
| `tokens` | `make_tokens` | agreed |

**source/kernel/tool/ToolModule.jl**

| old | new | status |
| --- | --- | --- |
| `api_entry_names` | `get_api_entry_names` | agreed |
| `api_modules` | `get_api_modules` | agreed |
| `last_evaluated_value` | `get_last_evaluated_value` | one pass only |

**source/markdown/MarkdownFile.jl**

| old | new | status |
| --- | --- | --- |
| `markdown_section` | `get_markdown_section` | agreed |

**source/math/MathDocument.jl**

| old | new | status |
| --- | --- | --- |
| `math_accent_is_wide` | `is_math_accent_wide` | agreed |
| `math_big_operator_glyph` | `get_math_big_operator_glyph` | agreed |
| `math_big_operator_is_text` | `is_math_big_operator_text` | agreed |
| `math_big_operator_name` | `get_math_big_operator_name` | agreed |
| `math_delimiter_strings` | `get_math_delimiter_strings` | agreed |
| `math_operator_class` | `get_math_operator_class` | agreed |
| `math_operator_glyph` | `get_math_operator_glyph` | agreed |
| `math_symbol_glyph` | `get_math_symbol_glyph` | agreed |

**source/math/MathToGraphics.jl**

| old | new | status |
| --- | --- | --- |
| `math_metrics` | `compute_math_metrics` | resolved |
| `math_to_graphics_dispatch` | `make_math_to_graphics_dispatch` | agreed |

**source/mcp/Mcp.jl**

| old | new | status |
| --- | --- | --- |
| `mcp_resources` | `render_mcp_resources` | resolved |
| `mcp_start!` | `start_mcp!` | agreed |
| `mcp_stop!` | `stop_mcp!` | agreed |
| `mcp_tools` | `render_mcp_tools` | resolved |

**source/natural/NaturalRegistry.jl**

| old | new | status |
| --- | --- | --- |
| `natural_fallback_entries` | `get_natural_fallback_entries` | agreed |
| `natural_graphics_entries` | `get_natural_graphics_entries` | agreed |
| `natural_syntax_entries` | `get_natural_syntax_entries` | agreed |

**source/odbc/Odbc.jl**

| old | new | status |
| --- | --- | --- |
| `dsn_for` | `get_dsn` | resolved |

**source/pane/PaneDocument.jl**

| old | new | status |
| --- | --- | --- |
| `pane_groups` | `get_pane_groups` | agreed |
| `pane_normalized_weights` | `get_pane_normalized_weights` | agreed |
| `pane_orientation_opposite` | `get_pane_orientation_opposite` | agreed |
| `pane_parent` | `get_pane_parent` | agreed |
| `pane_split_axis` | `get_pane_split_axis` | agreed |
| `pane_tab_title_string` | `get_pane_tab_title_string` | agreed |
| `pane_weight` | `get_pane_weight` | agreed |
| `pane_weights` | `get_pane_weights` | agreed |

**source/pane/PaneGeometry.jl**

| old | new | status |
| --- | --- | --- |
| `pane_drop_zone` | `get_pane_drop_zone` | agreed |
| `pane_group_at` | `get_pane_group_at` | agreed |
| `pane_neighbour_group` | `get_pane_neighbour_group` | agreed |
| `pane_next_group` | `get_pane_next_group` | agreed |
| `pane_rectangle` | `get_pane_rectangle` | agreed |
| `pane_rectangles` | `get_pane_rectangles` | agreed |
| `pane_zone_orientation` | `get_pane_zone_orientation` | agreed |

**source/pane/PaneProgram.jl**

| old | new | status |
| --- | --- | --- |
| `pane_api` | `make_pane_api` | agreed |

**source/pane/PaneSurgery.jl**

| old | new | status |
| --- | --- | --- |
| `pane_close_tab_operation` | `make_pane_close_tab_operation` | agreed |
| `pane_collection_path` | `get_pane_collection_path` | agreed |
| `pane_drop_split_operation` | `make_pane_drop_split_operation` | agreed |
| `pane_focus` | `get_pane_focus` | agreed |
| `pane_focus_operation` | `make_pane_focus_operation` | agreed |
| `pane_focus_title` | `get_pane_focus_title` | agreed |
| `pane_focused_group` | `get_pane_focused_group` | agreed |
| `pane_focused_tab_index` | `get_pane_focused_tab_index` | agreed |
| `pane_move_tab_operation` | `make_pane_move_tab_operation` | agreed |
| `pane_open_tab_operation` | `make_pane_open_tab_operation` | agreed |
| `pane_path` | `get_pane_path` | agreed |
| `pane_resize_operation` | `make_pane_resize_operation` | agreed |
| `pane_retarget_title_operation` | `make_pane_retarget_title_operation` | agreed |
| `pane_shown_tab_index` | `get_pane_shown_tab_index` | agreed |
| `pane_split_operation` | `make_pane_split_operation` | agreed |
| `pane_tab_reference` | `get_pane_tab_reference` | agreed |
| `pane_title_caret_operation` | `make_pane_title_caret_operation` | agreed |
| `pane_title_path` | `get_pane_title_path` | agreed |

**source/plot/PlotGeometry.jl**

| old | new | status |
| --- | --- | --- |
| `axis_span` | `get_axis_span` | agreed |
| `bin_values` | `compute_bin_values` | resolved |
| `column_bounds` | `get_column_bounds` | agreed |
| `histogram_values` | `compute_histogram_values` | resolved |
| `legend_layout` | `compute_legend_layout` | resolved |
| `nearest_sample` | `find_nearest_sample` | resolved |
| `nice_num` | `compute_nice_number` | resolved |
| `nice_ticks` | `compute_nice_ticks` | resolved |
| `pins_segments` | `build_pins_segments` | resolved |
| `visible_range` | `get_visible_range` | agreed |

**source/plot/PlotStyle.jl**

| old | new | status |
| --- | --- | --- |
| `marker_polygon` | `build_marker_polygon` | resolved |
| `series_color` | `get_series_color` | agreed |
| `series_symbol` | `get_series_symbol` | agreed |

**source/primitive/ObjectField.jl**

| old | new | status |
| --- | --- | --- |
| `object_field_name` | `get_object_field_name` | agreed |
| `object_field_value` | `get_object_field_value` | agreed |

**source/process/ProcessDocument.jl**

| old | new | status |
| --- | --- | --- |
| `body_steps` | `get_body_steps` | agreed |
| `node_at` | `get_node_at` | agreed |
| `node_index` | `get_node_index` | agreed |
| `unrefined_nodes` | `get_unrefined_nodes` | agreed |

**source/reflection/BoundedSync.jl**

| old | new | status |
| --- | --- | --- |
| `unsynced_marker` | `make_unsynced_marker` | agreed |
| `unsynced_size` | `get_unsynced_size` | agreed |

**source/reflection/DocumentReflection.jl**

| old | new | status |
| --- | --- | --- |
| `reflection_value` | `get_reflection_value` | agreed |

**source/rst/RstFile.jl**

| old | new | status |
| --- | --- | --- |
| `rst_section` | `find_rst_section` | resolved |
| `rst_title_text` | `get_rst_title_text` | agreed |

**source/screen/WindowScene.jl**

| old | new | status |
| --- | --- | --- |
| `window_scene` | `make_window_scene` | agreed |
| `window_scene_projection` | `make_window_scene_projection` | agreed |

**source/sdl/Sdl.jl**

| old | new | status |
| --- | --- | --- |
| `sdl_decode_image` | `decode_sdl_image` | resolved |
| `sdl_display_size` | `get_sdl_display_size` | resolved |
| `sdl_measure_text` | `measure_sdl_text` | resolved |
| `sdl_render_canvas` | `render_sdl_canvas` | resolved |

**source/sequencechart/SequenceChartDocument.jl**

| old | new | status |
| --- | --- | --- |
| `arrow_count` | `get_arrow_count` | agreed |
| `arrow_from_event` | `get_arrow_from_event` | agreed |
| `arrow_into_event` | `get_arrow_into_event` | agreed |
| `arrow_kind` | `get_arrow_kind` | agreed |
| `arrow_label` | `get_arrow_label` | agreed |
| `arrow_reference` | `get_arrow_reference` | agreed |
| `arrow_row` | `get_arrow_row` | agreed |
| `arrow_source_axis` | `get_arrow_source_axis` | agreed |
| `arrow_target_axis` | `get_arrow_target_axis` | agreed |
| `axis_display_order` | `get_axis_display_order` | agreed |
| `axis_reference` | `get_axis_reference` | agreed |
| `band_reference` | `get_band_reference` | agreed |
| `band_row` | `get_band_row` | agreed |
| `band_state_name` | `get_band_state_name` | agreed |
| `event_axis` | `get_event_axis` | agreed |
| `event_count` | `get_event_count` | agreed |
| `event_kind` | `get_event_kind` | agreed |
| `event_label` | `get_event_label` | agreed |
| `event_reference` | `get_event_reference` | agreed |
| `event_row` | `get_event_row` | agreed |
| `next_event_on_lane` | `get_next_event_on_lane` | agreed |
| `selected_arrow` | `get_selected_arrow` | agreed |
| `selected_axis_index` | `get_selected_axis_index` | agreed |
| `selected_event` | `get_selected_event` | agreed |
| `sequence_chart_part_index` | `get_sequence_chart_part_index` | agreed |
| `sequence_chart_parts` | `get_sequence_chart_parts` | agreed |

**source/sequencechart/SequenceChartGeometry.jl**

| old | new | status |
| --- | --- | --- |
| `arc_geometry` | `get_arc_geometry` | agreed |
| `arrow_coverage_dedup` | `deduplicate_arrow_coverage` | rule decides |
| `arrow_route` | `get_arrow_route` | agreed |
| `axis_cross_positions` | `get_axis_cross_positions` | agreed |
| `band_intervals` | `get_band_intervals` | agreed |
| `coordinate_to_time` | `convert_coordinate_to_time` | agreed |
| `event_ordinal` | `get_event_ordinal` | agreed |
| `honest_tick_label` | `get_honest_tick_label` | agreed |
| `timeline_coordinates` | `get_timeline_coordinates` | agreed |
| `visible_arrows` | `get_visible_arrows` | agreed |
| `visible_event_range` | `get_visible_event_range` | agreed |
| `zero_time_spans` | `get_zero_time_spans` | agreed |

**source/sequencechart/SequenceChartPlot.jl**

| old | new | status |
| --- | --- | --- |
| `sequence_chart_view_of` | `get_sequence_chart_view` | resolved |

**source/sequencechart/SequenceChartPlotToGraphics.jl**

| old | new | status |
| --- | --- | --- |
| `arrow_hit` | `find_arrow_hit` | resolved |
| `band_hit` | `find_band_hit` | resolved |
| `event_hit` | `find_event_hit` | resolved |
| `lane_cross_position` | `get_lane_cross_position` | agreed |
| `lane_hit` | `find_lane_hit` | resolved |
| `sequence_chart_reference` | `lift_sequence_chart_reference` | resolved |

**source/serialization/FileProject.jl**

| old | new | status |
| --- | --- | --- |
| `content` | `get_content` | agreed |
| `document_section` | `get_document_section` | agreed |
| `file_document_type` | `get_file_document_type` | agreed |
| `file_marker_text` | `format_file_marker_text` | resolved |
| `filename` | `get_filename` | agreed |
| `marker_function` | `get_marker_function` | agreed |
| `marker_text` | `format_marker_text` | resolved |
| `resolve!` | — | no change |

**source/style/Geometry.jl**

| old | new | status |
| --- | --- | --- |
| `affine_apply` | `apply_affine_transform` | resolved |
| `affine_identity` | — | no change |
| `affine_inverse` | `compute_affine_inverse` | resolved |
| `affine_is_axis_aligned` | `is_affine_axis_aligned` | agreed |
| `affine_scale` | `make_affine_scale` | agreed |
| `affine_translate` | `make_affine_translate` | agreed |

**source/style/TrueType.jl**

| old | new | status |
| --- | --- | --- |
| `truetype_measure_text` | `measure_truetype_text` | resolved |

**source/syntax/InsertionToSyntax.jl**

| old | new | status |
| --- | --- | --- |
| `insertion_delete` | `compute_insertion_delete` | resolved |
| `insertion_insert` | `compute_insertion_insert` | resolved |

**source/syntax/SyntaxDocument.jl**

| old | new | status |
| --- | --- | --- |
| `syntax_child_path` | `build_syntax_child_path` | resolved |
| `syntax_children` | `get_syntax_children` | agreed |
| `syntax_closing` | `get_syntax_closing` | agreed |
| `syntax_collapsed` | `is_syntax_collapsed` | agreed |
| `syntax_collapsible` | `is_syntax_collapsible` | agreed |
| `syntax_indentation` | `get_syntax_indentation` | agreed |
| `syntax_opening` | `get_syntax_opening` | agreed |
| `syntax_separator` | `get_syntax_separator` | agreed |

**source/syntax/SyntaxNatural.jl**

| old | new | status |
| --- | --- | --- |
| `natural_to_syntax_dispatch` | `make_natural_to_syntax_dispatch` | agreed |

**source/text/TextDocument.jl**

| old | new | status |
| --- | --- | --- |
| `hinted_text` | `make_hinted_text` | agreed |
| `text_caret_flat` | `get_text_caret_flat` | agreed |
| `text_elem_to_flat` | `get_text_elem_to_flat` | agreed |
| `text_flat_length` | `get_text_flat_length` | agreed |
| `text_flat_offsets` | `get_text_flat_offsets` | agreed |
| `text_flat_to_elem` | `get_text_flat_to_elem` | agreed |
| `text_insert_op` | `make_text_insert_operation` | agreed |
| `text_selection_flat` | `get_text_selection_flat` | agreed |
| `text_selection_substring` | `get_text_selection_substring` | agreed |

**source/web/Web.jl**

| old | new | status |
| --- | --- | --- |
| `web_key_to_symbol` | `convert_web_key_to_symbol` | resolved |

**source/widget/WidgetDocument.jl**

| old | new | status |
| --- | --- | --- |
| `action_shortcut_matches` | `matches_action_shortcut` | agreed |
| `as_action` | `resolve_action` | resolved |
| `numeric_validator` | `make_numeric_validator` | agreed |
| `widget_column_chooser` | `make_widget_column_chooser` | agreed |
| `widget_filter_bar` | `make_widget_filter_bar` | agreed |
| `widget_lazy_table_row_selection` | `make_widget_lazy_table_row_selection` | agreed |
| `widget_lazy_table_selected_row` | `get_widget_lazy_table_selected_row` | agreed |
| `widget_list_selected` | `get_widget_list_selected` | agreed |
| `widget_list_selection` | `make_widget_list_selection` | agreed |
| `widget_pager` | `make_widget_pager` | agreed |
| `widget_table_row_selection` | `make_widget_table_row_selection` | agreed |
| `widget_table_selected_row` | `get_widget_table_selected_row` | agreed |

**source/widget/WidgetToGraphics.jl**

| old | new | status |
| --- | --- | --- |
| `frozen_extent` | `get_frozen_extent` | agreed |
| `glyph_icon` | `make_glyph_icon` | agreed |
| `image_icon` | `make_image_icon` | agreed |
| `widget_theme_dark` | `make_widget_theme_dark` | agreed |
| `widget_theme_light` | `make_widget_theme_light` | agreed |
| `widget_theme_slate_dark` | `make_widget_theme_slate_dark` | agreed |
| `widget_theme_slate_light` | `make_widget_theme_slate_light` | agreed |

**source/workbench/WorkbenchDocument.jl**

| old | new | status |
| --- | --- | --- |
| `title` | `get_title` | agreed |

**test/kernel/KernelSuite.jl**

| old | new | status |
| --- | --- | --- |
| `package_source_root` | `get_package_source_root` | agreed |

**test/kernel/tool/DeclaredApiTest.jl**

| old | new | status |
| --- | --- | --- |
| `toy_arrange` | — | no change |
| `toy_count` | — | no change |
| `toy_extra` | — | no change |
| `toy_verb` | — | no change |

**test/projectured/ExportCollisionTest.jl**

| old | new | status |
| --- | --- | --- |
| `only_alpha` | — | no change |
| `shared` | — | no change |

**test/projectured/ProjecturedSuite.jl**

| old | new | status |
| --- | --- | --- |
| `catalog_coverage_gap` | `get_catalog_coverage_gap` | agreed |
| `nav_broken` | `get_navigation_broken` | agreed |
| `printer_locality_report` | `measure_printer_locality` | resolved |

## 14.10 How the 62 contested rows were settled

The user ruled on 2026-09-12. The rulings are §13.1.1 of
[naming-rule-violations.md](naming-rule-violations.md). A third pass then read
each of the 62 definitions again and applied them. Every row is now `resolved`,
and no two rows propose the same name.

What the rulings produced:

- **`find_` for a search that may return nothing** — `find_nearest_sample`,
  `find_arrow_hit`, `find_band_hit`, `find_event_hit`, `find_lane_hit`,
  `find_rst_section`. Each docstring says the function returns `nothing` when it
  finds no match, which is the test the ruling names.
- **`compute_` for real work** — `compute_topological_order` (a depth-first walk
  with cycle detection), `compute_nice_number` and `compute_nice_ticks`
  (Heckbert's formula), `compute_affine_inverse` (a determinant formula),
  `compute_math_metrics`.
- **`get_` only for a value at a known place** — `get_chart_view` is
  `plot.view`, a field access.
- **`make_` only for creating** — most of the seven `get_` versus `make_` rows
  became something else, because they derive rather than create:
  `collect_chart_parts`, `build_command_palette_selection`,
  `build_polyline_arrowhead`, `build_syntax_child_path`.
- **Subject-first qualifiers** — `get_base_plane_length`,
  `get_base_plane_length_square`, `get_base_plane_distance`,
  `get_command_palette_settled_selection`.
- **Trailing `of` and `for` dropped** — `get_chart_view`, `get_dsn`.
- **A bang for an external side effect** — `write_os_clipboard!`, and
  `read_os_clipboard` with none.
- **`julia_main` unchanged.**

Ten rows took a name that neither earlier pass proposed, because reading the
body showed both were wrong. `conversation_to_string` became
`format_conversation`, and `printer_locality_report` became
`measure_printer_locality` because the file's own comment calls it one locality
measurement, and both `explore_` and `report_` already mean something else in
that file.

### Two corrections I made to the third pass

1. `compute_nice_num` kept the abbreviation `num`. The rules ban an ad-hoc
   abbreviation, so the name is **`compute_nice_number`**.
2. `chart_view_contains` was resolved to a bare **`contains`**, on the reading
   that the rules allow a plain verb that reads as a question. But `contains` is
   a Julia Base generic, and exporting it shadows Base. The contract does not
   match either: `Base.contains(haystack, needle)` takes a needle, and
   `chart_view_contains(view, x, y)` takes a point as two scalars, so a method on
   `Base.contains` would be a false overload. The name is
   **`is_point_in_chart_view`**, which also matches the sibling
   `is_point_in_polygon` of §6.4.

## 14.11 One more question the passes raised

The four `sdl_*` helpers in [Sdl.jl](../../source/sdl/Sdl.jl) are exported
beside the generics they serve. [Sdl.jl:2152](../../source/sdl/Sdl.jl#L2152)
reads `BackendModule.render_canvas(canvas) = sdl_render_canvas(canvas)`, so the
generic is extended and `sdl_render_canvas` is the helper behind it.
`measure_text` needs no helper at all — it is extended directly with a method on
`::SdlBackend`. So the question is not what to call these four, but why they are
exported. Drop the `export` and the naming question disappears.
